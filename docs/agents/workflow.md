# Agent workflow

How one agent takes one issue from request to `main`, without a person in the loop unless the review asks for one. The `/work-issue` skill runs these steps.

## Rules

- **One issue, one branch, one worktree, one pull request.** Never work in the main checkout: other agents and the owner are using it.
- **Nothing goes to `main` except through a pull request.** No direct pushes. Merging is done by `tools/agent/merge_pr.sh` or by the owner on GitHub, never by `gh pr merge`.
- **Stay on the issue.** Something else found on the way becomes a new issue, not part of this change.
- **Do not stop to ask** unless the issue cannot be understood, or the review policy says a human decides.

## Steps

1. **Pick up the issue.** `gh issue view <n> --comments`. No issue yet? Make one first from the request. Claim it: `gh issue edit <n> --add-assignee @me`.
2. **Branch in a worktree.** If the session is not already in its own worktree:
   `git fetch origin && git worktree add .claude/worktrees/issue-<n> -b issue-<n>-<short-name> origin/main`, then work there.
3. **Build it.** Read `CLAUDE.md`. For the product's words and facts, read `CONTEXT.md` in the `DrakeAnglin/tilt` repo. Small commits. Remember that the repo is public: nothing private in a page, a commit message, an issue or a pull request.
4. **Check locally.** `tools/agent/check.sh` must pass.
5. **Open the pull request.** `git push -u origin <branch>`, then `gh pr create`. Right after, turn on the app's watch for the pull request (Auto-fix: `set_monitor` with `auto_fix`), so this session is woken on a conflict, a red CI or a comment. If that tool is not there or is not approved, go on without it. Write the body in the template's shape (Matt Pocock's `pr` skill, when installed, is the guide): `Closes #<n>`, summary, evidence, door, blast radius, what could go wrong.
6. **Wait for CI.** `gh pr checks <pr> --watch`. Red? Fix it, push, wait again.
7. **Review, by someone else.** Start the `pr-reviewer` agent with only the pull request number. It has no part of this session's context. It posts its own summary, evidence, merge danger and findings as a comment on the pull request.
8. **Fix what must be fixed**, push, and have `pr-reviewer` look again. Three rounds at most; the merge script counts them, and after that it goes to a human.
9. **Gate.** Start the `merge-gate` agent with the pull request number. It reads the review and the policy and decides: merge, or human.
10. **Merge or hand over.**
    - Merge: `tools/agent/merge_pr.sh <pr>`. It checks the rules again and squash-merges. The change is live on the site a minute or two later: open the page and look.
    - Human: the `needs-human` label, always with a comment that says why: a TL;DR first, notes after. Then notify the owner (below), tell them the TL;DR and stop. Do not merge.
11. **Clean up.** After a merge: remove the worktree (`git worktree remove`), delete the local branch. The issue closes itself through `Closes #<n>`.

## The owner's out

The owner can open `main` for direct pushes: `tools/agent/allow_main.sh` in their own terminal (30 minutes by default, `off` to close). While it is open, the guard and the pre-push hook let a push to `main` through. An agent cannot open it and does not ask for it to dodge a review. If the owner tells you to push to `main` and it is closed, ask them to run the command.

## Merge conflicts

Other pull requests merge while yours is open, and yours can stop merging cleanly. That is yours to notice and fix; it is not a reason to stop.

**When to look** (`gh pr view <pr> --json mergeable --jq .mergeable`; on `UNKNOWN`, wait a few seconds and ask again):

- before asking for review, and before merging (`merge_pr.sh` refuses a pull request that does not merge cleanly)
- when the app wakes you about your pull request
- right after you merge anything: `gh pr list --json number,mergeable,headRefName`. Your merge may have put other open pull requests into conflict.

**How to resolve**, in the pull request's worktree:

1. `git fetch origin && git merge origin/main`. Merge, never rebase or force push: the review is tied to commits.
2. Fix each conflict so that what both sides meant is kept. Two new sections in the same place: keep both. Read the other change to see what it meant (`git log origin/main -- <file>`).
3. `tools/agent/check.sh`, commit the merge, push.
4. Have `pr-reviewer` look again: the review is for the commit before. Then the gate. Each review counts toward the three-round limit, so a pull request that keeps conflicting ends up with the owner.

**Someone else's pull request** that your merge put into conflict: if its worktree is on this Mac under `.claude/worktrees/` and has nothing uncommitted, resolve it there the same way and leave a comment on the pull request saying what you did and that it needs review again. Otherwise leave a comment and do not touch the branch. A pull request from a fork is never yours to touch.

**Do not guess.** When the two sides really disagree (the same sentence, two meanings; a page one side deleted and the other changed), stop: `needs-human` with a comment that says why, shows both sides, and names what the owner should confirm. Then notify the owner.

## Notifying the owner

The owner is often away from the Mac. Send one push notification with the `PushNotification` tool (load it with ToolSearch if it is not loaded; if it is not there, skip it and go on) when:

- a pull request is handed over: `tilt-site#<pr> needs you: <the why, in one sentence>`
- you are stuck and cannot go on without the owner: say what you need. One push, then wait.

One line, under 200 characters, the thing to act on first. None for a clean merge or for progress: a push that was not needed costs the owner's attention.

## Things found on the way

A bug, a smell, a missing test that is not this issue: file it and move on.

`gh issue create --label needs-triage --title "..." --body "Found while working on #<n>. ..."`

Say what was seen, where (file and line), and how to see it again. Do not fix it in this branch.

## Labels

| Label | Meaning |
| --- | --- |
| `ready-for-agent` | The owner says an agent may pick this issue up on its own |
| `needs-triage` | Filed by an agent; the owner has not looked yet |
| `two-way-door` / `one-way-door` | The reviewer's door for a pull request |
| `auto-merge-ok` | The gate says the agent may merge |
| `needs-human` | The owner reviews and merges this one |

The review rules are in [review-policy.md](review-policy.md).
