"""End-to-end apply leg (Phase 10): run the bot's queue path without a browser.

Loads the exported approved-jobs queue, runs process_queue with the SAME wiring
main.py uses in queue mode — real artifact-integrity gate (Phase 6), real claim
store (Phase 8), real durable ResultWriter — but with a mock apply_fn in place
of the browser. Outcome per job is decided by company so the e2e can assert both
a submitted and a manual_review path. Prints a JSON summary on stdout for the
orchestrator to assert against.

Run from the bot checkout: `cd <linkedin-bot> && uv run python apply.py <queue> <results> <claims_dir>`.
"""

import asyncio
import json
import os
import sys

# The bot package is importable from the bot checkout (the orchestrator cd's there).
sys.path.insert(0, os.getcwd())

from src.integration.artifacts import resolve_job_artifacts  # noqa: E402
from src.integration.claims import ClaimStore, claimant_from_store  # noqa: E402
from src.integration.executor_config import QueueExecutionConfig  # noqa: E402
from src.integration.queue_loader import load_queue, queue_min_score  # noqa: E402
from src.integration.queue_models import ApplicationResult, utc_now_iso  # noqa: E402
from src.integration.queue_runner import process_queue  # noqa: E402
from src.integration.result_writer import ResultWriter  # noqa: E402


def make_apply_fn():
    async def apply_fn(job, config):
        now = utc_now_iso()
        if "Acme" in (job.company or ""):
            return ApplicationResult.for_job(
                job, executor_run_id=config.executor_run_id,
                result="submitted", started_at=now, finished_at=now,
            )
        # A sensitive question the bot won't auto-answer -> manual review.
        return ApplicationResult.for_job(
            job, executor_run_id=config.executor_run_id,
            result="manual_review", started_at=now, finished_at=now,
            manual_action_required=True,
            error_code="sponsorship",
            error_message="Do you require visa sponsorship?",
        )

    return apply_fn


def main() -> None:
    queue_path, results_path, claims_dir = sys.argv[1], sys.argv[2], sys.argv[3]
    doc, jobs = load_queue(queue_path)  # validates approved-jobs.v1
    config = QueueExecutionConfig(
        executor_run_id="e2e-run", min_score=queue_min_score(doc), submit=True
    )
    writer = ResultWriter(results_path)
    claim, release, finalize = claimant_from_store(ClaimStore(claims_dir))

    results = asyncio.run(
        process_queue(
            jobs,
            make_apply_fn(),
            config,
            on_result=writer.append,
            verify_artifacts=resolve_job_artifacts,  # real integrity gate
            claim=claim,
            release_claim=release,
            finalize_claim=finalize,
        )
    )

    summary = {
        "queue_ids": [j.integration_id for j in jobs],
        "queue_resume_sha": {j.integration_id: j.resume_sha256 for j in jobs},
        "results": [
            {
                "integration_id": r.integration_id,
                "result": r.result,
                "error_code": r.error_code,
                "resume_sha256": r.resume_sha256,
            }
            for r in results
        ],
    }
    print(json.dumps(summary))


if __name__ == "__main__":
    main()
