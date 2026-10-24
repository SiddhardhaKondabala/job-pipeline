#!/usr/bin/env bash
#
# validator-parity.test.sh — the two validators must agree.
#
# The drift test guarantees the schema FILES are identical. This guarantees the
# two VALIDATORS (career-ops' dependency-free one and the bot's jsonschema one)
# reach the same verdict on the same document. Each fixture under
# fixtures/contract/<kind>/{valid,invalid}/ is run through both; the test fails
# unless both agree with each other AND with the fixture's directory.
#
set -euo pipefail

HUB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$HUB/.env" ]; then set -a; . "$HUB/.env"; set +a; fi
: "${CAREER_OPS_DIR:?run ./bootstrap.sh}"
: "${LINKEDIN_BOT_DIR:?run ./bootstrap.sh}"

FIX="$HUB/fixtures/contract"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0

run_kind() {
  kind="$1"
  : > "$tmp/expected"
  for verdict in VALID INVALID; do
    d="valid"; [ "$verdict" = INVALID ] && d="invalid"
    for f in "$FIX/$kind/$d"/*.json; do
      [ -e "$f" ] || continue
      printf '%s\t%s\n' "$f" "$verdict" >> "$tmp/expected"
    done
  done
  files="$(cut -f1 "$tmp/expected")"
  [ -n "$files" ] || { echo "no fixtures for $kind" >&2; return 0; }

  node "$HUB/scripts/parity/validate_careerops.mjs" "$kind" $files > "$tmp/co"
  uv run --quiet --project "$LINKEDIN_BOT_DIR" python "$HUB/scripts/parity/validate_bot.py" "$kind" $files > "$tmp/bot"

  while IFS=$'\t' read -r f exp; do
    co="$(awk -F'\t' -v f="$f" '$1==f{print $2}' "$tmp/co")"
    bo="$(awk -F'\t' -v f="$f" '$1==f{print $2}' "$tmp/bot")"
    name="$(basename "$(dirname "$f")")/$(basename "$f")"
    if [ "$co" = "$exp" ] && [ "$bo" = "$exp" ]; then
      echo "ok     [$kind] $name  (career-ops=$co bot=$bo)"
    else
      echo "FAIL   [$kind] $name  expected=$exp career-ops=$co bot=$bo"; fail=1
    fi
  done < "$tmp/expected"
}

run_kind approved-jobs
run_kind application-result

if [ "$fail" -ne 0 ]; then
  echo
  echo "VALIDATOR PARITY MISMATCH — the two sides disagree on a fixture." >&2
  exit 1
fi
echo
echo "validator parity OK (career-ops and bot agree on every fixture)"
