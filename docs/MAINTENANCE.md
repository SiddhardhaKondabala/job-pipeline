# Maintenance

How to own, back up, and keep updating integration code that lives inside two
repos we do not own.

## The model

- Our code lives on an `integration/*` branch **inside each repo** (it imports
  their internals, so it cannot move out).
- You **fork** both repos to your GitHub. The fork is your owned, backed-up
  copy. The original stays reachable as a remote named `upstream`.
- This hub (`job-pipeline`) pins both forks as **submodules** at a known commit,
  so one clone reproduces the whole pipeline.

## 1. Fork both repos (do this on GitHub, then wire the remotes)

Fork `career-ops-hq/career-ops` and `beatwad/LinkedIn-AI-Job-Applier-Ultimate`
to your account in the GitHub UI. Then, in each existing local clone, add your
fork as `origin` and the original as `upstream`:

```bash
# career-ops
cd career-ops
git remote rename origin upstream
git remote add origin git@github.com:<you>/career-ops.git
git push -u origin integration/linkedin-career-ops

# LinkedIn bot
cd ../LinkedIn-AI-Job-Applier-Ultimate
git remote rename origin upstream
git remote add origin git@github.com:<you>/LinkedIn-AI-Job-Applier-Ultimate.git
git push -u origin integration/career-ops-queue
```

Your integration branches are now on your forks. `main`/`release` still track
the originals through `upstream`.

## 2. Pull upstream updates (per fork, whenever upstream moves)

```bash
cd career-ops
git fetch upstream
git checkout integration/linkedin-career-ops
git rebase upstream/main        # bot uses: git rebase upstream/release
# resolve conflicts, then:
make -C ../job-pipeline test     # confirm the bridge still passes
git push --force-with-lease origin integration/linkedin-career-ops
```

Rebase keeps our integration commits on top of the latest upstream, so the diff
we maintain stays small and reviewable.

## 3. Pin the forks into the hub as submodules (after forking)

```bash
cd job-pipeline
git submodule add -b integration/linkedin-career-ops \
  git@github.com:<you>/career-ops.git career-ops
git submodule add -b integration/career-ops-queue \
  git@github.com:<you>/LinkedIn-AI-Job-Applier-Ultimate.git linkedin-bot
git commit -m "chore: pin career-ops and bot forks as submodules"
```

`bootstrap.sh` auto-detects these submodule dirs (`career-ops/`, `linkedin-bot/`)
and prefers them over sibling clones. Anyone can then reproduce the pipeline:

```bash
git clone --recurse-submodules git@github.com:<you>/job-pipeline.git
cd job-pipeline && ./bootstrap.sh && make test
```

Bump a submodule to a newer integration commit with:

```bash
cd career-ops && git pull && cd ..
git add career-ops && git commit -m "chore: bump career-ops submodule"
```

## Why not vendor everything into one repo?

The exporter/importer are career-ops `.mjs` scripts that import career-ops
internals; the bot's queue mode edits its own Python entrypoints. Both must run
inside their repo's tree. Forks + submodules give single-command reproducibility
and clean upstream syncing without copying code we don't own.
