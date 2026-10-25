# job-pipeline — orchestration for the career-ops <-> LinkedIn-bot integration.
# The hub owns no application code; it drives the two repos by path (see .env).
#
# Written for GNU make 3.81 (macOS default): no .ONESHELL. Each recipe is one
# shell invocation via `\` line continuation, so a sourced .env persists across
# the commands in that recipe.

SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help
.PHONY: help bootstrap env sync-schemas check-schemas check-parity test test-career-ops test-bot

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
	cd "$$CAREER_OPS_DIR" && node --test tests/integration-*.test.mjs tests/export-approved-jobs.test.mjs

test-bot: ## bot integration unit tests
	@$(LOADENV) \
	cd "$$LINKEDIN_BOT_DIR" && uv run --quiet pytest tests/test_integration_*.py tests/test_queue_*.py tests/test_apply_agent_security.py -o addopts="" -q

test: check-schemas check-parity test-career-ops test-bot ## drift + parity + both integration suites
	@echo ""
	@echo "All integration checks passed."
