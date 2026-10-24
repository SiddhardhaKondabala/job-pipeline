#!/usr/bin/env bash
#
# schema-drift.test.sh — fail if the bot's vendored schemas differ from the
# canonical career-ops schemas. This is what keeps ONE contract across two
# repos: CI (and `make test`) refuse to pass while the copies have drifted.
# Fix drift with `make sync-schemas` (then commit both repos).
#
set -euo pipefail

HUB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$HUB/.env" ]; then set -a; . "$HUB/.env"; set +a; fi
: "${CAREER_OPS_DIR:?set CAREER_OPS_DIR or run ./bootstrap.sh}"
: "${LINKEDIN_BOT_DIR:?set LINKEDIN_BOT_DIR or run ./bootstrap.sh}"

SRC="$CAREER_OPS_DIR/schemas"
DST="$LINKEDIN_BOT_DIR/src/integration/schemas"
SCHEMAS=(approved-jobs.v1.schema.json application-result.v1.schema.json)

fail=0
for f in "${SCHEMAS[@]}"; do
  if [ ! -f "$DST/$f" ]; then
    echo "DRIFT  $f missing from bot ($DST)"; fail=1; continue
  fi
  if diff -q "$SRC/$f" "$DST/$f" >/dev/null 2>&1; then
    echo "ok     $f in sync"
  else
    echo "DRIFT  $f differs between career-ops and bot:"
    diff "$SRC/$f" "$DST/$f" || true
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo
  echo "Schemas have drifted. Run: make sync-schemas   (then commit both repos)" >&2
  exit 1
fi
echo "schemas in sync"
