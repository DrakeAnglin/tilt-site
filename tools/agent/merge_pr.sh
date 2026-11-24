#!/bin/sh
# Merge a pull request, but only when the rules in docs/agents/review-policy.md allow an agent to.
#   tools/agent/merge_pr.sh <pr>            check, then squash-merge
#   tools/agent/merge_pr.sh <pr> --check    check only
# "Not yet" (CI running, no review) just stops. "Not allowed" also gets the needs-human label,
# and the owner merges on GitHub.
set -eu
PR=${1:?usage: merge_pr.sh <pr> [--check]}
MODE=${2:-}
[ -z "$MODE" ] || [ "$MODE" = --check ] || { echo "usage: merge_pr.sh <pr> [--check]" >&2; exit 2; }

MAX_LINES=400
MAX_REVIEWS=3

J=$(gh pr view "$PR" --json number,state,isDraft,isCrossRepository,baseRefName,headRefName,headRefOid,mergeable,additions,deletions,labels,comments)
get() { printf '%s' "$J" | jq -r "$1"; }
SHA=$(get .headRefOid)
NO=""      # not allowed: a human decides
WAIT=""    # not yet: try again later
no() { NO="$NO
- $1"; }
wait_for() { WAIT="$WAIT
- $1"; }

[ "$(get .state)" = OPEN ] || { echo "#$PR is not open ($(get .state)). Nothing to do."; exit 1; }
[ "$(get .isDraft)" = false ] || wait_for "pull request is a draft"
[ "$(get .baseRefName)" = main ] || no "base is not main"
[ "$(get .isCrossRepository)" = false ] || no "comes from a fork"
case "$(get .mergeable)" in
  MERGEABLE) ;;
  UNKNOWN) wait_for "GitHub has not worked out yet whether it merges cleanly" ;;
  *) wait_for "does not merge cleanly into main: bring the branch up to date" ;;
esac

# A label set by hand, or by the gate, wins over everything else.
for L in needs-human one-way-door; do
  [ "$(get "[.labels[].name] | index(\"$L\")")" = null ] || no "has the $L label"
done

LINES=$(( $(get .additions) + $(get .deletions) ))
[ "$LINES" -lt "$MAX_LINES" ] || no "$LINES changed lines (must be under $MAX_LINES): too big for an agent to vouch for. Confirm: the change is one thing, and read the summary against the diff."

# Every changed file (and the old name of a renamed one), not only the first page.
FILES=$(gh api "repos/{owner}/{repo}/pulls/$PR/files" --paginate --jq '.[] | .filename, (.previous_filename // empty)')
[ -n "$FILES" ] || no "could not list the changed files"
# Human-only paths: pattern, why a person is needed, what the person confirms.
# Keep the same as the list in docs/agents/review-policy.md.
human_only() {
  HIT=$(printf '%s\n' "$FILES" | grep -E "$1" | tr '\n' ' ' || true)
  [ -z "$HIT" ] || no "$2 Confirm: $3 Files: $HIT"
}
human_only '^privacy\.md$' \
  "The privacy policy changed: a promise to users, and what Apple reviews." \
  "every sentence is true of the app and the hardware as they are today."
human_only '^(_config\.yml|CNAME)$' \
  "The site's address or what gets published changed." \
  "links from the app and the App Store listing still work, and nothing private is published."
# Only what decides a merge. Pages, layouts, workflow docs, skills and CLAUDE.md are open to agents.
human_only '^(tools/agent/|docs/agents/review-policy\.md$|\.github/workflows/|\.claude/agents/|\.claude/settings[^/]*\.json$|\.githooks/)' \
  "What decides a merge changed (policy, reviewer, gate, merge script, guard or CI), and an agent does not approve that for itself." \
  "the rules still say what you want: who may merge, the doors, the human-only list."

# CI: the 'ci' check must have passed, and nothing may be failing or still running.
CHECKS=$(gh pr checks "$PR" --json name,bucket 2>/dev/null) || true
printf '%s' "$CHECKS" | jq -e 'type == "array"' >/dev/null 2>&1 || CHECKS='[]'
if [ "$(printf '%s' "$CHECKS" | jq -r '[.[] | select(.bucket == "fail" or .bucket == "cancel")] | length')" != 0 ]; then
  wait_for "CI is red: fix it"
elif [ "$(printf '%s' "$CHECKS" | jq -r '[.[] | select(.name == "ci" and .bucket == "pass")] | length')" = 0 ] ||
     [ "$(printf '%s' "$CHECKS" | jq -r '[.[] | select(.bucket != "pass" and .bucket != "skipping")] | length')" != 0 ]; then
  wait_for "CI has not finished"
fi

# The review and the gate must both be for this exact commit.
# Anyone can comment on a public repo: count only what the account running this posted.
ME=$(gh api user --jq .login)
markers() { get "[.comments[] | select(.author.login == \"$ME\") | .body | capture(\"<!-- $1 (?<m>[^>]*) -->\"; \"g\") | .m]"; }
field() { printf '%s' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p"; }
REVIEW=$(markers factory-review | jq -r 'last // ""')
GATE=$(markers factory-gate | jq -r 'last // ""')
[ "$(markers factory-review | jq -r length)" -le "$MAX_REVIEWS" ] || no "More than $MAX_REVIEWS rounds of review without a clean result. Confirm: read the last review and decide whether to go on."
if [ -z "$REVIEW" ]; then wait_for "no review yet (run the pr-reviewer agent)"
elif [ "$(field "$REVIEW" sha)" != "$SHA" ]; then wait_for "the review is for an older commit (run pr-reviewer again)"
else
  [ "$(field "$REVIEW" door)" = two-way ] || no "The review says one-way door: no going back once shipped. Confirm: you want this, and the reason in the review holds."
  [ "$(field "$REVIEW" must-fix)" = 0 ] || wait_for "the review has must-fix findings"
fi
if [ -z "$GATE" ]; then wait_for "no gate verdict yet (run the merge-gate agent)"
elif [ "$(field "$GATE" sha)" != "$SHA" ]; then wait_for "the gate verdict is for an older commit (run merge-gate again)"
else
  [ "$(field "$GATE" verdict)" = merge ] || no "The gate says a human decides: see its comment for why and what to confirm."
fi

if [ -n "$NO" ]; then
  echo "Not merging #$PR. A human decides:$NO"
  [ -z "$WAIT" ] || echo "Also not ready:$WAIT"
  if [ "$MODE" != --check ]; then
    gh pr edit "$PR" --add-label needs-human >/dev/null
    gh pr edit "$PR" --remove-label auto-merge-ok >/dev/null 2>&1 || true
    # The label never stands alone: say why, once per commit.
    # Leave out "has the label": whoever set it has said why already.
    WHY=$(printf '%s\n' "$NO" | grep '^- ' | grep -v 'has the needs-human label' || true)
    if [ -n "$WHY" ] && [ "$(get "[.comments[] | select(.author.login == \"$ME\") | .body | select(contains(\"factory-human sha=$SHA\"))] | length")" = 0 ]; then
      FIRST=$(printf '%s\n' "$WHY" | sed -n '1s/^- //p' | sed "s/ Confirm:.*//")
      COUNT=$(printf '%s\n' "$WHY" | grep -c '^- ')
      [ "$COUNT" -le 1 ] || FIRST="$FIRST ($((COUNT - 1)) more below.)"
      gh pr comment "$PR" --body "## Needs human review

**TL;DR:** An agent may not merge this. $FIRST

### Why, and what to confirm
$WHY

When you are happy, merge on GitHub.

<!-- factory-human sha=$SHA -->" >/dev/null
    fi
  fi
  exit 1
fi
if [ -n "$WAIT" ]; then
  echo "Not merging #$PR yet:$WAIT"
  exit 1
fi

echo "#$PR passes every rule."
[ "$MODE" = --check ] && exit 0
gh pr merge "$PR" --squash --match-head-commit "$SHA"
git push origin --delete "$(get .headRefName)" >/dev/null 2>&1 || true
echo "Merged #$PR."
