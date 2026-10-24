# job-pipeline

The owned hub for the **career-ops ↔ LinkedIn-bot** job-application pipeline.

career-ops ([career-ops-hq/career-ops](https://github.com/career-ops-hq/career-ops))
is the **system of record**: it discovers, deduplicates, scores (1–5), checks
liveness, tailors the resume/cover letter, and owns the final application status.
The LinkedIn bot ([beatwad/LinkedIn-AI-Job-Applier-Ultimate](https://github.com/beatwad/LinkedIn-AI-Job-Applier-Ultimate))
is the **execution engine**: it applies to explicitly approved jobs and reports
results back. The bridge is file-based and opt-in; neither side changes its
standalone behaviour.

We do **not** own the two upstream repos. This hub is the one thing we do own.
It holds no application code — it drives the two repos by path and keeps the
shared contract in sync.

```
career-ops ──export──▶ linkedin-approved.json ──▶ bot (queue mode) ──▶ linkedin-results.jsonl ──import──▶ career-ops tracker
                    (approved-jobs.v1)                              (application-result.v1)
```

## Layout

```
job-pipeline/
  bootstrap.sh            # one-time/idempotent setup
  Makefile                # run everything from here
  .env.example            # template; bootstrap writes a resolved .env
  scripts/sync-schemas.sh # copy canonical schemas career-ops -> bot
  tests/schema-drift.test.sh  # fail if the copies drift
  fixtures/               # shared e2e fixtures (Phase 10)
  docs/MAINTENANCE.md     # forking + upstream sync + submodules
```

The two repos and the personal-data dir live **outside** the hub (as sibling
clones today, as submodules once you fork):

```
Code/
  career-ops/                        (branch: integration/linkedin-career-ops)
  LinkedIn-AI-Job-Applier-Ultimate/  (branch: integration/career-ops-queue)
  career-data/                       (personal data — queue + results)
  job-pipeline/                      (this hub)
```

## Quick start

```bash
cd job-pipeline
./bootstrap.sh          # resolves repo paths, writes .env, creates career-data, syncs schemas
make test               # schema drift check + both integration test suites
make help               # all targets
```

`bootstrap.sh --deps` also installs repo dependencies (`npm install`, `uv sync`)
when they are missing. Without `--deps` it assumes the repos are already set up.

If the repos are not sibling clones, point the hub at them:

```bash
CAREER_OPS_DIR=/path/to/career-ops \
LINKEDIN_BOT_DIR=/path/to/LinkedIn-AI-Job-Applier-Ultimate \
./bootstrap.sh
```

## The shared contract

The JSON Schemas (`approved-jobs.v1`, `application-result.v1`) are canonical in
career-ops (`career-ops/schemas/`). The bot carries a vendored copy under
`src/integration/schemas/`. `make sync-schemas` copies career-ops → bot, and
`make check-schemas` (part of `make test`) fails if they ever differ. One
contract, enforced across two repos.

## Maintaining code we don't own

Our integration code lives on an `integration/*` branch **inside each repo**,
because it imports those repos' internals. To own and back it up, and to pull
upstream updates cleanly, fork both and sync via an `upstream` remote. See
[docs/MAINTENANCE.md](docs/MAINTENANCE.md) for the exact fork, upstream-sync, and
submodule commands.
