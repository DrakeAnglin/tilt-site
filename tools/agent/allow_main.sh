#!/bin/sh
# The owner's out: allow direct pushes to main from this clone for a short time.
#   tools/agent/allow_main.sh          open for 30 minutes
#   tools/agent/allow_main.sh 10       open for 10 minutes
#   tools/agent/allow_main.sh off      close now
# Only the owner runs this, in their own terminal. It refuses without one, and the guard stops agents from running it.
set -eu
[ -t 0 ] && [ -t 1 ] || { echo "allow_main: only the owner runs this, in a terminal." >&2; exit 1; }
FILE="$(git rev-parse --git-common-dir)/factory-allow-main"
if [ "${1:-}" = off ]; then
  rm -f "$FILE"
  echo "main is closed again: pull requests only."
  exit 0
fi
MIN=${1:-30}
case "$MIN" in ''|*[!0-9]*) echo "usage: allow_main.sh [minutes|off]" >&2; exit 2 ;; esac
echo $(( $(date +%s) + MIN * 60 )) > "$FILE"
echo "main is open for direct pushes from this clone for $MIN minutes. Close it sooner with: tools/agent/allow_main.sh off"
