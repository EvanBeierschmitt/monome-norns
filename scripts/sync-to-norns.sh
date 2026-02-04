#!/usr/bin/env bash
# Sync this repo to norns at ~/dust/code/lines/
# Usage: ./scripts/sync-to-norns.sh
#   NORNS_HOST=norns.local NORNS_USER=we (defaults)
# Requires: norns on same WiFi, rsync, ssh access (user we).

set -e
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINES_DIR="$REPO_ROOT/lines"
NORNS_HOST="${NORNS_HOST:-norns.local}"
NORNS_USER="${NORNS_USER:-we}"
REMOTE="${NORNS_USER}@${NORNS_HOST}:~/dust/code/lines/"

echo "Syncing lines/ to ${REMOTE}"
rsync -avz --delete \
  --exclude '.DS_Store' \
  "$LINES_DIR/" "$REMOTE"

echo "Done. On norns: SELECT > lines > K3 to run (or let warmreload reload)."
