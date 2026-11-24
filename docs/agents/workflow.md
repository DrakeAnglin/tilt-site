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
5. **Open the pull request.** `git push -u origin <branch>`, then `gh pr create`. Write the body in the template's shape (Matt Pocock's `pr` skill, when installed, is the guide): `Closes #<n>`, summary, evidence, door, blast radius, what could go wrong.
6. **Wait for CI.** `gh pr checks <pr> --watch`. Red? Fix it, push, wait again.
7. **Review, by someone else.** Start the `pr-reviewer` agent with only the pull request number. It has no part of this session's context. It posts its own summary, evidence, merge danger and findings as a comment on the pull request.
8. **Fix what must be fixed**, push, and have `pr-reviewer` look again. Three rounds at most; the merge script counts them, and after that it goes to a human.
9. **Gate.** Start the `merge-gate` agent with the pull request number. It reads the review and the policy and decides: merge, or human.
10. **Merge or hand over.**
    - Merge: `tools/agent/merge_pr.sh <pr>`. It checks the rules again and squash-merges. The change is live on the site a minute or two later: open the page and look.
    - Human: the `needs-human` label, always with a comment that says why: a TL;DR first, notes after. Tell the owner the TL;DR and stop. Do not merge.
11. **Clean up.** After a merge: remove the worktree (`git worktree remove`), delete the local branch. The issue closes itself through `Closes #<n>`.

## The owner's out

The owner can open `main` for direct pushes: `tools/agent/allow_main.sh` in their own terminal (30 minutes by default, `off` to close). While it is open, the guard and the pre-push hook let a push to `main` through. An agent cannot open it and does not ask for it to dodge a review. If the owner tells you to push to `main` and it is closed, ask them to run the command.

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
