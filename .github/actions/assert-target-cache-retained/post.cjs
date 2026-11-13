const assert = require('node:assert/strict');
const fs = require('node:fs');
assert.equal(process.env.PULSE_CARGO_TARGET_SAVE_FAILED, 'true');
assert.equal(fs.readFileSync(process.env.STATE_fixture, 'utf8'), 'warm compiler fixture\n');
console.log('PASS real post steps: warned S3 save retained the local compiler target.');
