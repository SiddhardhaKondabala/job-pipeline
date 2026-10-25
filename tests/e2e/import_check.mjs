// End-to-end import leg (Phase 10): run the REAL career-ops importer over the
// bot's results, matching each result back to a tracker row by integration_id.
//
// Uses runImport with an injected apply step (a recorder) so the dependency-free
// matching + status-mapping runs without the js-yaml-backed set-status writer.
// Reads the tracker from CAREER_OPS_ROOT (set by the orchestrator to the shared
// e2e workspace). Prints {calls, counts} as JSON for the orchestrator to assert.
//
// Run from the career-ops checkout: `node import_check.mjs <results.jsonl>`.

import { runImport } from '../../career-ops/import-application-results.mjs';

const resultsPath = process.argv[2];

const calls = [];
const applyFn = async (action) => {
  calls.push({ reportNumber: action.reportNumber, state: action.state, note: action.note });
};

const { counts } = await runImport(['--results', resultsPath], { applyFn });
process.stdout.write(JSON.stringify({ calls, counts }) + '\n');
