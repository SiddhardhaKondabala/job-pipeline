#!/usr/bin/env bash
#
# sync-schemas.sh — copy the canonical JSON Schemas from career-ops (the system
# of record) into the bot's vendored copy. career-ops owns the contract; the bot
# only carries a copy so it can validate standalone. Run this after any schema
# change, then commit both repos.
#
set -euo pipefail

HUB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$HUB/.env" ]; then set -a; . "$HUB/.env"; set +a; fi
: "${CAREER_OPS_DIR:?set CAREER_OPS_DIR or run ./bootstrap.sh}"
: "${LINKEDIN_BOT_DIR:?set LINKEDIN_BOT_DIR or run ./bootstrap.sh}"

SRC="$CAREER_OPS_DIR/schemas"
DST="$LINKEDIN_BOT_DIR/src/integration/schemas"
SCHEMAS=(approved-jobs.v1.schema.json application-result.v1.schema.json)

mkdir -p "$DST"
for f in "${SCHEMAS[@]}"; do
  if [ ! -f "$SRC/$f" ]; then
    echo "ERROR: canonical schema missing: $SRC/$f" >&2
    exit 1
  fi
  cp "$SRC/$f" "$DST/$f"
  echo "synced $f  ->  $DST/$f"
done
