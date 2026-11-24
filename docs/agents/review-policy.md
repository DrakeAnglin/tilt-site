# Review policy

How a pull request is judged before it goes into `main`. The `pr-reviewer` and `merge-gate` agents follow this. `tools/agent/merge_pr.sh` enforces the hard rules, whatever the agents say.

**This repo is public, and merging to `main` publishes to the live site** within a minute or two. The review reads every changed page as a stranger would.

## Doors

Every pull request gets one door.

**Two-way door**: reverting the commit puts everything back. Most changes: wording, layout, a new help page.

**One-way door**: once it is live, a revert does not undo it. In this repo:

- A promise to users: the privacy policy, warranty or safety wording, a price, a ship date. People may have read and relied on it.
- Something private made public: a name, an email, an address, a key, a serial number, an unreleased plan. It is copied and cached the moment it is live.
- An address that other things point at: renaming or removing a page that the app, the App Store listing or a printed QR code links to (`privacy`, `support`), or changing `baseurl`.
- Deleting an issue, a release or a branch.

When unsure, call it one-way.

## Who merges

**The agent merges** when all of these are true:

1. Two-way door.
2. CI is green on the commit that was reviewed.
3. The review found nothing that must be fixed, or the fixes are in and reviewed again.
4. What the page says is true: it matches the product as it is in `DrakeAnglin/tilt` today. Or the change is not to a page.
5. The change does what the issue asked and nothing else.
6. Under 400 changed lines.
7. No human-only path is touched (below).

`needs-human` and `one-way-door` stick: a pull request with either is never merged by an agent, and only the owner takes them off.

**A human merges** in every other case, and the pull request always says why. See below.

## What goes on the pull request

Three things, each with the same parts, so the owner can read any one of them alone:

| Who | Where | What |
| --- | --- | --- |
| Author | The pull request body (the template) | Summary, Evidence, Merge Danger: door, blast radius, what could go wrong |
| `pr-reviewer` | A comment | Its own TL;DR, Summary, Evidence and Merge Danger, written from the diff, then the findings |
| `merge-gate` | A comment | TL;DR of the verdict, door, blast radius, what could go wrong, then the seven rules as notes |

**`needs-human` never stands alone.** It always comes with two things: **why** a person is needed (what a person can judge here that tests and agents cannot), and **what to confirm** (three checks at most, each naming a file). The gate writes them in its comment and in the pull request body under `## Human Review`. `merge_pr.sh` writes them in a comment when it is the one that refuses.

Anyone can comment on a public repo, so the merge script counts a review or a gate verdict only when the owner's account posted it.

## Human-only paths

- `privacy.md`: a promise to users, and what Apple reviews.
- `_config.yml`, `CNAME`: the site's address and what gets published.
- `docs/agents/review-policy.md`, `.claude/agents/`, `.claude/settings.json`, `tools/agent/`, `.githooks/`, `.github/workflows/`: what decides a merge. An agent does not approve that for itself.

Everything else is open to agents: the other pages, `_layouts/`, `docs/agents/workflow.md`, `.claude/skills/`, `CLAUDE.md`, the pull request template.

The script's list is in `tools/agent/merge_pr.sh`, with the why and the what-to-confirm for each line. Keep the two the same.
