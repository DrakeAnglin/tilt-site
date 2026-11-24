# tilt-site

The public website for Tilt (GitHub Pages, built by Jekyll from `main`). The product, its words and its decisions live in the `DrakeAnglin/tilt` repo, usually checked out next to this one as `../blinds`: read its `CONTEXT.md` for the right words before writing a page.

**This repo is public and `main` is the live site.** Nothing private goes in a page, an issue, a pull request or a commit message.

## Issue tracker

GitHub Issues on `DrakeAnglin/tilt-site` (via the `gh` CLI). See `docs/agents/issue-tracker.md`.

## How work gets into main

Every change goes: issue, own branch in its own worktree, pull request, CI, independent review, merge gate. Nothing is pushed to `main`. To do a task start to finish, use the `/work-issue` skill. See `docs/agents/workflow.md` and `docs/agents/review-policy.md`.

- Checks: `tools/agent/check.sh` (CI also builds the site the way GitHub Pages does).
- Review: the `pr-reviewer` agent, started fresh with only the pull request number. It names the door: one-way or two-way.
- Merge: `tools/agent/merge_pr.sh <pr>`, after the `merge-gate` agent says merge. Otherwise the `needs-human` label with a why, and the owner merges.
- Something unrelated found on the way: a new issue with `needs-triage`, not a fix in this branch.
