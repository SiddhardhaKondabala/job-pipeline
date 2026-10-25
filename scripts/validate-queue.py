"""Offline pre-flight for an approved-jobs queue (Phase 11 rollout).

Validates a queue the way the bot does at start-up, but WITHOUT launching a
browser or logging in: it loads and schema-validates the queue, then checks
every job's resume/cover-letter artifact exists and matches its SHA-256. Use it
before a real run so a bad queue or a missing/swapped artifact is caught up
front, offline.

Run from the bot checkout: `cd <linkedin-bot> && uv run python validate-queue.py <queue.json>`.
Exit 0 when the queue is clean, 1 otherwise.
"""

import os
import sys

sys.path.insert(0, os.getcwd())

from src.integration.artifacts import preflight_artifacts  # noqa: E402
from src.integration.queue_loader import QueueError, load_queue  # noqa: E402
from src.integration.schemas import SchemaError  # noqa: E402


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: validate-queue.py <queue.json>", file=sys.stderr)
        return 2
    queue_path = sys.argv[1]
    try:
        doc, jobs = load_queue(queue_path)
    except (QueueError, SchemaError) as e:
        print(f"INVALID queue: {e}", file=sys.stderr)
        return 1

    problems = preflight_artifacts(jobs)
    print(f"queue ok: {len(jobs)} job(s), min_score={doc['min_score']}, executor={doc['executor']}")
    if problems:
        for job, err in problems:
            print(
                f"  ARTIFACT PROBLEM  {job.integration_id}  {job.company} — {job.role}: {err}",
                file=sys.stderr,
            )
        print(f"{len(problems)}/{len(jobs)} job(s) have artifact problems", file=sys.stderr)
        return 1
    print(f"all {len(jobs)} artifact(s) present and match their approved SHA-256")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
