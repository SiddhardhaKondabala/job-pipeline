# Rollout runbook

How to actually run the career-ops ↔ LinkedIn-bot pipeline for real, safely.

The loop is one-directional and file-based:

```
career-ops export ──▶ linkedin-approved.json ──▶ bot (queue mode) ──▶ linkedin-results.jsonl ──▶ career-ops import ──▶ tracker
```

Everything below is driven from the hub by `make` targets (they resolve paths
from `.env`). **Nothing submits an application unless you explicitly run
`make run-submit CONFIRM=yes`.** Build up to that over the stages below — don't
skip to it.

## 0. Preconditions (once)

- `make bootstrap ARGS=--deps` — resolves `.env`, creates the integration dir,
  syncs schemas, and installs the career-ops npm deps and the bot's Python deps.
  The real **import** step needs the career-ops deps (`js-yaml` etc.); the
  export and the offline `validate` run without them.
- career-ops is onboarded: `cv.md`, `config/profile.yml`, a tracker with
  `Evaluated` jobs, and a tailored resume PDF per job (`data/pdf-index.tsv`).
- The bot has its secrets (`.env`) and a resume — see the bot's own setup. A
  real run logs into LinkedIn in a browser, so do the first ones attended.

Sanity check the wiring any time with `make env` and `make test`.

## 1. Export the approved queue

```bash
make export            # or: make export MIN_SCORE=4.5
```

Writes `linkedin-approved.json` to `$CAREER_OPS_INTEGRATION_DIR` with only the
jobs that pass career-ops' approval policy (Evaluated, score ≥ min, verified,
Apply decision, no hard stop / agency gate / blacklist, a valid LinkedIn URL,
and a tailored resume that passed its fact check). The queue is **personal data
and lives outside both git repos.**

**Review it.** It is a short JSON file — open it and confirm the jobs are ones
you actually want to apply to. This is the human gate the rest of the pipeline
trusts.

## 2. Validate offline (no browser)

```bash
make validate
```

Loads and schema-validates the queue and confirms every job's resume/cover
letter still exists and matches the SHA-256 career-ops recorded — all without
launching a browser or logging in. Fix any problem here before spending a login.

## 3. Dry run

```bash
make run-dry
```

The bot loads and validates the queue and artifact hashes, then stops without
initializing credentials, the LLM, or a browser. Use it to confirm the file and
contract plumbing; login is first exercised by `run-test`.

> **Upgrade note:** regenerate `linkedin-approved.json` with `make export` after
> upgrading from a pre-hardening release. Older queues may have no approval
> hashes and are intentionally rejected for `manual_review`; they are never
> applied using existence-only artifact checks.

## 4. Test run — fill, never submit

```bash
make run-test            # MAX=1 by default; MAX=3 to do three
```

The bot drives the real Easy Apply flow for `MAX` job(s) but **never clicks the
final submit** (`--test-mode`). Watch it in the dashboard (below). Confirm it
uploads the career-ops resume, answers ordinary questions, and stops for a
sensitive one (work authorization, sponsorship, salary, …) unless you have
pre-answered it in the bot's `config/sensitive_answers.yaml`.

## 5. First real submission — one job

```bash
make run-submit CONFIRM=yes        # MAX=1
```

Submits for real, one job. `CONFIRM=yes` is required; `MAX` defaults to 1. Then:

```bash
make import-dry                    # preview the tracker changes (writes nothing)
make import                        # apply them (idempotent)
```

Open the tracker and confirm the submitted job moved to `Applied`, and that a
`manual_review` / `captcha` / `requires_mfa` job kept its status with a note.

## 6. Scale up

Once a single real submission round looks right end to end, raise the batch:

```bash
make run-submit CONFIRM=yes MAX=10
make import
```

Re-export whenever the tracker changes (new evaluations, statuses). Re-running
export → run → import is safe: results are idempotent on `(run, job)`, and the
importer never duplicates a note or downgrades a status.

## Monitoring

Run the bot dashboard (`cd linkedin-bot && uv run python dashboard.py`, port
8000) and watch the **Queue Runs** panel: per-job state (applied / needs review
/ failed / pending / in progress), the manual-review reason or challenge, and
claim state. It reads the same queue, results, and claims files.

## Safety, interruption, and retries

- **Claims.** Before applying, each job is claimed under
  `$CAREER_OPS_INTEGRATION_DIR/claims/`, so two runs never apply the same job and
  a resumed run skips jobs already attempted. A **transient failure releases the
  claim** (so a later run retries); a real attempt or a human-needed stop
  finalizes it permanently. An abandoned in-progress claim expires after 24
  hours by default; set `CAREER_OPS_CLAIM_TIMEOUT_SECONDS` to another duration,
  or `0` to disable expiration. Expired active claims are removed lazily when a
  run or status read next examines them. The per-job `.lock` files are stable
  coordination files and intentionally remain; do not delete them while a run
  may be active. Never delete the whole claims directory: that would also reopen
  confirmed submissions. Remove a single `.claim` only after checking its
  durable result and tracker state. If terminal claim finalization fails, the
  application result is still written and the run stops with an explicit
  reconciliation error; do not retry that job until its result and claim agree.
- **Stopping.** Ctrl-C, or Stop in the dashboard, halts the run cleanly; the
  in-flight job's claim is released and durable results remain for finished jobs.
- **Nothing silently submits.** `run-test` never submits; only
  `run-submit CONFIRM=yes` does.
- **Integrity.** A resume/cover letter whose bytes no longer match what
  career-ops approved is never uploaded — it is reported for manual review.

## Command summary

| Step | Command | Submits? |
|------|---------|----------|
| Export queue | `make export` | — |
| Offline validate | `make validate` | no (no browser) |
| Dry run | `make run-dry` | no |
| Test run | `make run-test [MAX=n]` | no (fills only) |
| Real run | `make run-submit CONFIRM=yes [MAX=n]` | **yes** |
| Import (preview) | `make import-dry` | — |
| Import | `make import` | — |
