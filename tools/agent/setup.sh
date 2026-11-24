#!/bin/sh
# One-time setup for a clone: turn on the git hooks and make the labels on GitHub. Safe to run again.
set -e
cd "$(dirname "$0")/../.."
git config core.hooksPath .githooks
label() { gh label create "$1" --color "$2" --description "$3" --force >/dev/null && echo "label: $1"; }
label ready-for-agent 0E8A16 "An agent may pick this up on its own"
label needs-triage    FBCA04 "Filed by an agent; the owner has not looked yet"
label two-way-door    C5DEF5 "Review: a revert undoes it"
label one-way-door    B60205 "Review: no going back once shipped"
label auto-merge-ok   0E8A16 "Gate: the agent may merge"
label needs-human     D93F0B "Gate: the owner reviews and merges"
echo "setup: ok"
