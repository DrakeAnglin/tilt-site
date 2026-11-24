---
name: work-issue
description: Take one GitHub issue, or one plain request, all the way to main on its own: worktree branch, build, tests, pull request, CI, independent review, merge gate, merge or hand to a human. Use when asked to fix, build or change something in this repo, or to work an issue by number.
---

Follow `docs/agents/workflow.md` step by step, start to finish, without stopping to ask. Read it now.

What each step leans on:

- **Local check**: `tools/agent/check.sh`.
- **Review**: start the `pr-reviewer` agent with a prompt that is only `Review pull request <n>`. Do not tell it what you did or what you think: it must come to it fresh.
- **Gate**: start the `merge-gate` agent with only `Gate pull request <n>`.
- **Merge**: `tools/agent/merge_pr.sh <n>`. If it refuses, it says why. Fix that, or hand over. Never go around it.

Done means one of two things, and you say which:

1. Merged: the pull request link, what changed, and any issues you filed on the way.
2. Waiting for the owner: the pull request link, the `needs-human` reason, and what to look at.
