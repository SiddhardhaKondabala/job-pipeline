// validate_careerops.mjs — career-ops' verdict on fixture files, for the parity
// test. Prints "<file>\tVALID|INVALID" per file. Imports the live validator from
// $CAREER_OPS_DIR so the parity test checks the real module, not a copy.
//
//   node validate_careerops.mjs <approved-jobs|application-result> <file>...
import { pathToFileURL } from 'node:url';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const careerOpsDir = process.env.CAREER_OPS_DIR;
if (!careerOpsDir) {
  console.error('CAREER_OPS_DIR not set (run ./bootstrap.sh)');
  process.exit(2);
}
const kind = process.argv[2];
const files = process.argv.slice(3);
const mod = await import(pathToFileURL(join(careerOpsDir, 'lib', 'integration-schema.mjs')).href);
const validate = kind === 'approved-jobs' ? mod.validateApprovedJobs : mod.validateApplicationResult;

for (const f of files) {
  let verdict = 'INVALID';
  try {
    verdict = validate(JSON.parse(readFileSync(f, 'utf-8'))).valid ? 'VALID' : 'INVALID';
  } catch {
    verdict = 'INVALID';
  }
  console.log(`${f}\t${verdict}`);
}
