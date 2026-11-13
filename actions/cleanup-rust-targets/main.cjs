const { appendFileSync } = require('node:fs');
const { execFileSync } = require('node:child_process');
const { targetPaths } = require('../cache-rust-s3/prepare.cjs');

const paths = targetPaths({
  ...process.env, CACHE_WORKSPACES: process.env.INPUT_WORKSPACES,
}, (program, args, cwd) => execFileSync(program, args, { cwd, encoding: 'utf8' }));
appendFileSync(process.env.GITHUB_STATE, `targets=${JSON.stringify(paths)}\n`);
