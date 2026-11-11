# job-pipeline

A one-clone, safe-by-default **job-application pipeline**. It discovers and scores
jobs, tailors your résumé and cover letter to each one, and — only when you
explicitly confirm — applies on LinkedIn and records the result.

This repo is the **hub**. It owns no application code; it wires together two
tools and keeps them in sync:

- **career-ops** — the *system of record*. Discovers, deduplicates, scores (1–5),
  checks liveness, tailors the résumé/cover letter from **your own CV**, and owns
  the final application status.
- **LinkedIn bot** — the *execution engine*. Applies to jobs you approved and
  reports results back.

```
career-ops ──export──▶ linkedin-approved.json ──▶ bot (queue mode) ──▶ linkedin-results.jsonl ──import──▶ career-ops tracker
                    (approved-jobs.v1)                              (application-result.v1)
```

The bridge is file-based and opt-in. Nothing applies to any job unless you run
the guarded submit step with `CONFIRM=yes`.

> **Credit.** The two tools are open-source projects we do not own, both MIT:
> career-ops ([career-ops-hq/career-ops](https://github.com/career-ops-hq/career-ops))
> and the LinkedIn bot ([beatwad/LinkedIn-AI-Job-Applier-Ultimate](https://github.com/beatwad/LinkedIn-AI-Job-Applier-Ultimate)).
> This hub pins our integration forks of both as submodules so one clone
> reproduces the whole pipeline.

---

## Who this is for

You want to run the full pipeline with **your own résumé and your own job search**.
You bring a CV and (for the apply step) a LinkedIn account. You never touch anyone
else's data — the pipeline creates a fresh, private data directory for you.

If you only want résumé/cover-letter tailoring and not the auto-apply bridge, you
can use career-ops on its own (`npx @santifer/career-ops init`) and stop reading
here. The rest of this guide sets up the **full** pipeline.

---

## 1. What you need

Install these first (all free):

| Tool | Why | Check |
|------|-----|-------|
| **git** | clone the repos | `git --version` |
| **Node.js 18+** (ships `npm` + `npx`) | runs career-ops | `node --version` |
| **uv** | runs the Python LinkedIn bot | `uv --version` |
| **An LLM provider API key** | career-ops scores and tailors with an LLM (OpenRouter by default) | — |
| *(optional)* an **AI coding CLI** (e.g. Claude Code) | runs career-ops' `/career-ops` tailoring modes | — |

`bootstrap.sh --deps` installs the per-repo dependencies for you (`npm install`,
`uv sync`) and, if needed, Playwright's Chromium for PDF export.

---

## 2. Clone the whole pipeline (one command)

The hub pins both forks as submodules, so a recursive clone brings everything:

```bash
git clone --recurse-submodules https://github.com/SiddhardhaKondabala/job-pipeline.git
cd job-pipeline
```

> Already cloned without `--recurse-submodules`? Run:
> `git submodule update --init --recursive`

After this you have, inside `job-pipeline/`:

```
job-pipeline/
  career-ops/     # the tailoring + tracking tool (submodule)
  linkedin-bot/   # the apply engine (submodule)
  bootstrap.sh    # sets everything up
  Makefile        # run everything from here
```

---

## 3. Bootstrap

```bash
./bootstrap.sh --deps     # installs deps, writes .env, creates your data dir, syncs schemas
make test                 # verifies the bridge end-to-end (no browser, never applies)
```

`bootstrap.sh` is idempotent — safe to re-run. It:

- creates **`../career-data/`** next to the hub — your **private data root** for
  the queue and results (see §6: this never gets a git remote),
- writes a resolved `.env` with absolute paths (edit it freely; delete it to
  regenerate),
- seeds the bot's config from its examples,
- copies the canonical schemas into the bot.

Run `make env` to print the resolved paths, and `make help` for every target.

---

## 4. Add your own CV

career-ops tailors **your** résumé — it never invents facts, it only rewords what
your CV already says.

```bash
cd career-ops
cp examples/cv-example.md cv.md          # then edit cv.md to be your real CV
cp config/profile.example.yml config/profile.yml   # your name, contact, links
cp .env.example .env                     # add your LLM provider API key
```

- `cv.md` is **git-ignored** in career-ops — it stays out of the code repo.
- The fact-check guard blocks any tailored CV whose claims are not in `cv.md`.
  Always read a CV before you send it.

See career-ops' own README for the full list of modes (`/career-ops text`,
`/career-ops pdf`, cover letters, the scanner, etc.).

---

## 5. Configure the LinkedIn bot (only needed for the apply step)

`bootstrap` seeds the bot's config from `linkedin-bot/examples/config/`. Open the
seeded files under `linkedin-bot/config/` and fill in:

- your LinkedIn login and search preferences,
- your answers to common application questions.

Keep credentials in the bot's own config/`.env` — never commit them. The bot runs
locally; it applies only to jobs this hub exported and you approved.

---

## 6. Your data stays yours

- **`career-data/` is private and local-only.** It holds your queue, your results,
  and (via career-ops) a copy of your CV with personal details. **Do not add a git
  remote to it and do not push it** — a push publishes your whole job search.
- The hub's `.gitignore` already blocks `career-data/`, `*.jsonl`, `*.log`, and
  `.env` from ever entering this repo.
- The two tool repos git-ignore your `cv.md`, `profile.yml`, and bot credentials.

---

## 7. Run the pipeline — safe by default

Nothing applies to a job until **you** run the guarded submit step. Follow the
staged loop (full detail in **[docs/ROLLOUT.md](docs/ROLLOUT.md)**):

```bash
make export               # career-ops: build the approved queue from your tracker
make validate             # offline schema + artifact pre-flight (no browser)
make run-dry              # bot: load + validate the queue only (never applies)
make run-test             # bot: fill an application but NEVER submit (MAX=1 default)
make run-submit CONFIRM=yes   # bot: REALLY submit — guarded (MAX=1 default)
make import               # career-ops: record the results in your tracker
```

Each step is reversible up to `run-submit`. `run-submit` is the only step that
touches the outside world, and it refuses to run without `CONFIRM=yes`. Raise the
count with `MAX=<n>` once you trust it on one job.

---

## 8. Hand this to your AI assistant

If you drive setup through an AI coding CLI (Claude Code or similar), give it this
exact sequence. Each step is concrete and checkable:

```
1. Clone the hub with submodules:
     git clone --recurse-submodules https://github.com/SiddhardhaKondabala/job-pipeline.git
     cd job-pipeline
2. Run: ./bootstrap.sh --deps   (installs deps, writes .env, creates ../career-data)
3. Run: make test               (must pass before going further)
4. In career-ops/: copy examples/cv-example.md -> cv.md and REPLACE it with the
   user's real CV. Copy config/profile.example.yml -> config/profile.yml and fill
   in the user's details. Copy .env.example -> .env and ask the user for their
   LLM provider API key.
5. In linkedin-bot/config/: fill in the user's LinkedIn preferences. Ask the user
   for credentials — never guess them.
6. Never add a git remote to ../career-data and never push it. Never commit cv.md,
   profile.yml, .env, or any credential file.
7. To apply to jobs, run the loop in §7 in order. Do NOT run
   `make run-submit CONFIRM=yes` without the user's explicit go-ahead for that run.
```

The guardrails that matter for an agent:

- **Facts:** career-ops never fabricates CV claims; the fact-check guard blocks
  unsupported terms. Do not bypass it.
- **Outside world:** only `make run-submit CONFIRM=yes` submits. Treat it as a
  stop-and-confirm point every time.
- **Privacy:** `career-data/` is the user's private job search. Local only.

---

## 9. The shared contract (how the two tools stay in sync)

The JSON Schemas (`approved-jobs.v1`, `application-result.v1`) are canonical in
career-ops (`career-ops/schemas/`). The bot carries a vendored copy. `make
sync-schemas` copies career-ops → bot, and `make check-schemas` (part of `make
test`) fails if they ever drift. One contract, enforced across two repos.

---

## 10. Own it yourself (advanced)

The integration code lives on an `integration/*` branch **inside each tool repo**,
because it imports those repos' internals. To own a backed-up copy and pull
upstream updates cleanly, fork both tools and pin your forks as submodules. The
exact fork, upstream-sync, and submodule commands are in
**[docs/MAINTENANCE.md](docs/MAINTENANCE.md)**.

---

## Troubleshooting

- **`make test` fails right after clone** — run `git submodule update --init
  --recursive`, then `./bootstrap.sh --deps` again.
- **`bootstrap` says a repo is MISSING** — point it at the repos explicitly:
  `CAREER_OPS_DIR=/path LINKEDIN_BOT_DIR=/path ./bootstrap.sh`
- **PDF export fails** — install the browser: `npx playwright install chromium`
  inside `career-ops/`.
- **`uv` not found** — install it (`curl -LsSf https://astral.sh/uv/install.sh | sh`),
  then re-run `./bootstrap.sh --deps`.
