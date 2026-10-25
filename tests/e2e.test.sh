#!/usr/bin/env bash
# Phase 10 — full-loop end-to-end test of the career-ops <-> LinkedIn-bot bridge.
#
# Proves the three independently-tested pieces actually interoperate, keyed
# consistently by integration_id, with no browser and no npm/pip install:
#
#   career-ops export  ->  approved-jobs.v1 queue
#        -> bot queue run (real integrity gate + claims + result writer, mock apply)
#        -> application-result.v1 JSONL
#        -> career-ops import (real match + status mapping, injected writer)
#        -> the tracker status change the loop WOULD apply.
#
# One job is applied (submitted -> Applied); one hits a sensitive question
# (manual_review -> status kept + note), exercising the Phase 6/7/8 paths too.

set -euo pipefail

HUB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAREER_OPS_DIR="${CAREER_OPS_DIR:-$HUB/career-ops}"
LINKEDIN_BOT_DIR="${LINKEDIN_BOT_DIR:-$HUB/linkedin-bot}"

PASS=0
fail() { echo "  ✗ $1" >&2; PASS=1; }
ok() { echo "  ✓ $1"; }

W="$(mktemp -d "${TMPDIR:-/tmp}/e2e-XXXXXX")"
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/data" "$W/reports" "$W/output"

echo "e2e: building workspace $W"

# --- fixture workspace (one tracker, two Evaluated jobs with reports + resumes) ---
cat > "$W/data/applications.md" <<'MD'
# Applications Tracker

| # | Date | Company | Via | Role | Score | Status | PDF | Report | Notes |
|---|------|---------|-----|------|-------|--------|-----|--------|-------|
| 1 | 2026-06-20 | Acme | — | Staff Engineer | 4.2/5 | Evaluated | ✅ | [1](../reports/001-acme.md) | strong fit |
| 2 | 2026-06-21 | Globex | — | ML Engineer | 4.3/5 | Evaluated | ✅ | [2](../reports/002-globex.md) | strong fit |
MD

write_report() { # path url company role score
  cat > "$1" <<MD
# $3 — $4

**URL:** $2
**Score:** $5/5
**Legitimacy:** High Confidence

## Machine Summary

\`\`\`yaml
company: "$3"
role: "$4"
score: $5
legitimacy_tier: "High Confidence"
final_decision: "Apply"
hard_stops: []
confidence: "high"
via: null
\`\`\`
MD
}
write_report "$W/reports/001-acme.md"   "https://www.linkedin.com/jobs/view/4011111111" "Acme"   "Staff Engineer" "4.2"
write_report "$W/reports/002-globex.md" "https://www.linkedin.com/jobs/view/4022222222" "Globex" "ML Engineer"    "4.3"

printf '%s\t%s\t%s\t%s\t%s\t%s\n' 1 output/cv-001.pdf output/cv-001.html a4 2026-06-20 cv  > "$W/data/pdf-index.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' 2 output/cv-002.pdf output/cv-002.html a4 2026-06-21 cv >> "$W/data/pdf-index.tsv"
printf '%%PDF-1.4 acme resume'   > "$W/output/cv-001.pdf"
printf '%%PDF-1.4 globex resume' > "$W/output/cv-002.pdf"

# --- 1. export (career-ops, dependency-free) ---
echo "e2e: [1/3] export approved queue"
( cd "$CAREER_OPS_DIR" && CAREER_OPS_ROOT="$W" node export-approved-jobs.mjs \
    --source linkedin --min-score 4.0 --out "$W/queue.json" ) >/dev/null
python3 - "$W/queue.json" <<'PY' || fail "export produced an unexpected queue"
import json, sys
q = json.load(open(sys.argv[1]))
assert q["schema"] == "approved-jobs.v1", q["schema"]
assert len(q["jobs"]) == 2, f'expected 2 jobs, got {len(q["jobs"])}'
assert all(j.get("resume_sha256") for j in q["jobs"]), "queue missing resume_sha256"
PY
[ "$PASS" = 0 ] && ok "export: 2 approved jobs with resume hashes"

# --- 2. apply (bot, real wiring, mock apply) ---
echo "e2e: [2/3] bot queue run (no browser)"
( cd "$LINKEDIN_BOT_DIR" && uv run --quiet python "$HUB/tests/e2e/apply.py" \
    "$W/queue.json" "$W/results.jsonl" "$W/claims" ) > "$W/apply.json"
python3 - "$W/apply.json" "$W/queue.json" <<'PY' || fail "apply leg did not produce the expected results"
import json, sys
a = json.load(open(sys.argv[1]))
by = {r["integration_id"]: r for r in a["results"]}
assert len(a["results"]) == 2, f'expected 2 results, got {len(a["results"])}'
assert set(by) == set(a["queue_ids"]), "result ids do not match queue ids"
# Each result echoes the exact resume hash career-ops exported (Phase 6).
for iid, r in by.items():
    assert r["resume_sha256"] == a["queue_resume_sha"][iid], f"hash mismatch for {iid}"
acme = next(r for r in a["results"] if "4011111111" in r["integration_id"])
globex = next(r for r in a["results"] if "4022222222" in r["integration_id"])
assert acme["result"] == "submitted", acme
assert globex["result"] == "manual_review" and globex["error_code"] == "sponsorship", globex
PY
[ "$PASS" = 0 ] && ok "apply: 1 submitted, 1 manual_review; hashes propagated"

# --- 3. import (career-ops, real match + mapping, injected writer) ---
echo "e2e: [3/3] import results back to the tracker"
CAREER_OPS_ROOT="$W" node "$HUB/tests/e2e/import_check.mjs" "$W/results.jsonl" > "$W/import.json"
python3 - "$W/import.json" <<'PY' || fail "import leg did not close the loop as expected"
import json, sys
imp = json.load(open(sys.argv[1]))
calls = {c["reportNumber"]: c for c in imp["calls"]}
assert set(calls) == {1, 2}, f"expected both rows matched, got {sorted(calls)}"
# Submitted -> Applied; manual_review -> status kept (Evaluated) + note.
assert calls[1]["state"] == "Applied", calls[1]
assert calls[2]["state"] == "Evaluated", calls[2]
assert "manual_review" in calls[2]["note"] or "sponsorship" in calls[2]["note"].lower(), calls[2]
assert imp["counts"]["status_changed"] == 1, imp["counts"]
PY
[ "$PASS" = 0 ] && ok "import: report 1 -> Applied, report 2 kept + noted (loop closed)"

if [ "$PASS" = 0 ]; then
  echo "e2e: full loop passed (export -> apply -> import, keyed by integration_id)."
else
  echo "e2e: FAILED" >&2
fi
exit "$PASS"
