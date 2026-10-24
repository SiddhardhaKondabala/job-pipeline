"""validate_bot.py — the bot's verdict on fixture files, for the parity test.

Prints "<file>\tVALID|INVALID" per file. Imports the live validator from
$LINKEDIN_BOT_DIR so the parity test checks the real module, not a copy.

  python validate_bot.py <approved-jobs|application-result> <file>...
"""

import json
import os
import sys

bot = os.environ.get("LINKEDIN_BOT_DIR")
if not bot:
    print("LINKEDIN_BOT_DIR not set (run ./bootstrap.sh)", file=sys.stderr)
    sys.exit(2)
sys.path.insert(0, os.path.join(bot, "src"))

from integration.schemas import (  # noqa: E402
    validate_application_result,
    validate_approved_jobs,
)

kind = sys.argv[1]
validate = validate_approved_jobs if kind == "approved-jobs" else validate_application_result

for f in sys.argv[2:]:
    try:
        with open(f) as fh:
            doc = json.load(fh)
        verdict = "VALID" if not validate(doc) else "INVALID"
    except Exception:
        verdict = "INVALID"
    print(f"{f}\t{verdict}")
