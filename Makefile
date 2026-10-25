# job-pipeline — orchestration for the career-ops <-> LinkedIn-bot integration.
# The hub owns no application code; it drives the two repos by path (see .env).
#
# Written for GNU make 3.81 (macOS default): no .ONESHELL. Each recipe is one
# shell invocation via `\` line continuation, so a sourced .env persists across
# the commands in that recipe.

SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help
.PHONY: help bootstrap env sync-schemas check-schemas check-parity test test-career-ops test-bot test-e2e \
        export validate run-dry run-test run-submit import-dry import

# Operational defaults (override on the command line, e.g. `make run-test MAX=3`).
MIN_SCORE ?= 4.0
MAX ?= 1
QUEUE_PATH = $${CAREER_OPS_INTEGRATION_DIR}/$${LINKEDIN_APPROVED_QUEUE:-linkedin-approved.json}
RESULTS_PATH = $${CAREER_OPS_INTEGRATION_DIR}/$${LINKEDIN_RESULTS:-linkedin-results.jsonl}

# Prefix for recipes that need the resolved paths. Tolerant of a missing .env.
LOADENV = set -a; [ -f .env ] && . ./.env; set +a;

help: ## show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | sort | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

bootstrap: ## set up env + dirs + schema sync (add ARGS=--deps to install deps)
	@./bootstrap.sh $(ARGS)

env: ## print the resolved paths
	@$(LOADENV) \
	echo "CAREER_OPS_DIR             = $${CAREER_OPS_DIR:-<unset: run make bootstrap>}"; \
	echo "LINKEDIN_BOT_DIR          = $${LINKEDIN_BOT_DIR:-<unset>}"; \
	echo "CAREER_OPS_ROOT           = $${CAREER_OPS_ROOT:-<unset>}"; \
	echo "CAREER_OPS_INTEGRATION_DIR = $${CAREER_OPS_INTEGRATION_DIR:-<unset>}"

sync-schemas: ## copy canonical schemas career-ops -> bot
	@./scripts/sync-schemas.sh

check-schemas: ## fail if the two schema copies have drifted
	@./tests/schema-drift.test.sh

check-parity: ## fail if the two validators disagree on shared fixtures
	@./tests/validator-parity.test.sh

test-career-ops: ## career-ops integration unit tests
	@$(LOADENV) \
	cd "$$CAREER_OPS_DIR" && node --test tests/integration-*.test.mjs tests/export-approved-jobs.test.mjs tests/import-application-results.test.mjs

test-bot: ## bot integration unit tests
	@$(LOADENV) \
	cd "$$LINKEDIN_BOT_DIR" && uv run --quiet pytest tests/test_integration_*.py tests/test_queue_*.py tests/test_outcome_mapping.py tests/test_executor_adapter.py tests/test_apply_approved_job.py tests/test_result_writer.py tests/test_apply_agent_security.py -o addopts="" -q

test-e2e: ## full-loop end-to-end (export -> bot apply -> import), no browser/deps
	@$(LOADENV) \
	bash tests/e2e.test.sh

test: check-schemas check-parity test-career-ops test-bot test-e2e ## drift + parity + both suites + e2e
	@echo ""
	@echo "All integration checks passed."

# --- operational loop (see docs/ROLLOUT.md) ---------------------------------
# Safe by default: nothing submits unless you run `run-submit` with CONFIRM=yes.

export: ## career-ops: build the approved queue from the tracker
	@$(LOADENV) \
	cd "$$CAREER_OPS_DIR" && node export-approved-jobs.mjs \
	  --source linkedin --min-score $(MIN_SCORE) --out "$(QUEUE_PATH)"

validate: ## offline: schema + artifact pre-flight of the queue (NO browser)
	@$(LOADENV) \
	cd "$$LINKEDIN_BOT_DIR" && uv run --quiet python "$(CURDIR)/scripts/validate-queue.py" "$(QUEUE_PATH)"

run-dry: ## bot: load + validate the queue, then stop (opens the browser to log in; never applies)
	@$(LOADENV) \
	cd "$$LINKEDIN_BOT_DIR" && uv run python main.py \
	  --approved-jobs "$(QUEUE_PATH)" --results "$(RESULTS_PATH)" --dry-run

run-test: ## bot: fill the application but NEVER submit (MAX job[s], default 1)
	@$(LOADENV) \
	cd "$$LINKEDIN_BOT_DIR" && uv run python main.py \
	  --approved-jobs "$(QUEUE_PATH)" --results "$(RESULTS_PATH)" --max-jobs $(MAX) --test-mode

run-submit: ## bot: REALLY submit — guarded. Run with CONFIRM=yes (MAX job[s], default 1)
	@if [ "$(CONFIRM)" != "yes" ]; then \
	  echo "run-submit performs REAL applications."; \
	  echo "Re-run with:  make run-submit CONFIRM=yes [MAX=$(MAX)]"; \
	  exit 2; \
	fi
	@$(LOADENV) \
	cd "$$LINKEDIN_BOT_DIR" && uv run python main.py \
	  --approved-jobs "$(QUEUE_PATH)" --results "$(RESULTS_PATH)" --max-jobs $(MAX) --submit

import-dry: ## career-ops: preview the tracker updates from results (writes nothing)
	@$(LOADENV) \
	cd "$$CAREER_OPS_DIR" && node import-application-results.mjs --results "$(RESULTS_PATH)" --dry-run

import: ## career-ops: apply the results to the tracker (idempotent)
	@$(LOADENV) \
	cd "$$CAREER_OPS_DIR" && node import-application-results.mjs --results "$(RESULTS_PATH)"
