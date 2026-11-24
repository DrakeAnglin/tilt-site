#!/bin/sh
# Run what an agent can run on this Mac before opening a pull request. CI also builds the site the way GitHub Pages does.
set -e
cd "$(dirname "$0")/../.."
python3 -m unittest tools/agent/test_agent.py
# Every page starts with front matter, or Jekyll will not turn it into a page.
for PAGE in index.md privacy.md support.md; do
  [ "$(head -1 "$PAGE")" = "---" ] || { echo "check: $PAGE has no front matter"; exit 1; }
done
# Links between pages, written (name/), point at pages that exist.
for NAME in $(grep -ohE '\]\([a-z-]+/\)' *.md | tr -d '](/)' | sort -u); do
  [ -f "$NAME.md" ] || { echo "check: a link points at $NAME/, and there is no $NAME.md"; exit 1; }
done
if command -v jekyll >/dev/null 2>&1; then
  jekyll build --quiet --destination "$(mktemp -d)"
else
  echo "site build skipped: no jekyll on this Mac (CI builds it)"
fi
echo "check: ok"
