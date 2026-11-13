const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { cleanup } = require('../actions/cleanup-rust-targets/post.cjs');
const { targetPaths } = require('../actions/setup-rust/prepare-target-cache.cjs');

test('removes resolved Cargo outputs while preserving published artifacts and uploaded cache', () => {
  const base = fs.mkdtempSync(path.join(os.tmpdir(), 'target-cleanup-'));
  try {
    const root = path.join(base, 'checkout');
    fs.mkdirSync(path.join(root, 'target'), { recursive: true });
    fs.mkdirSync(path.join(root, 'build'));
    fs.mkdirSync(path.join(root, 'dist'));
    fs.writeFileSync(path.join(root, 'target', 'binary'), 'compiled');
    fs.writeFileSync(path.join(root, 'build', 'object'), 'object');
    fs.copyFileSync(path.join(root, 'target', 'binary'), path.join(root, 'dist', 'binary'));
    const targets = targetPaths({ GITHUB_WORKSPACE: root }, () => JSON.stringify({
      target_directory: path.join(root, 'target'), build_directory: path.join(root, 'build'),
    }));
    fs.cpSync(path.join(root, 'target'), path.join(base, 'uploaded-cache'), { recursive: true });
    cleanup(root, targets);
    assert.equal(fs.existsSync(path.join(root, 'target')), false);
    assert.equal(fs.existsSync(path.join(root, 'build')), false);
    assert.equal(fs.readFileSync(path.join(root, 'dist', 'binary'), 'utf8'), 'compiled');
    assert.equal(fs.readFileSync(path.join(base, 'uploaded-cache', 'binary'), 'utf8'), 'compiled');
    cleanup(root, targets); // A retry is harmless.
  } finally { fs.rmSync(base, { recursive: true, force: true }); }
});

test('preserves checkout root, external targets and symlinked shared caches', () => {
  const base = fs.mkdtempSync(path.join(os.tmpdir(), 'target-boundary-'));
  try {
    const root = path.join(base, 'checkout');
    const shared = path.join(base, 'shared');
    fs.mkdirSync(root); fs.mkdirSync(shared);
    fs.writeFileSync(path.join(shared, 'keep'), 'cached');
    fs.symlinkSync(shared, path.join(root, 'target'), 'junction');
    cleanup(root, [root, shared, path.join(root, 'target')]);
    assert.equal(fs.existsSync(root), true);
    assert.equal(fs.readFileSync(path.join(shared, 'keep'), 'utf8'), 'cached');
  } finally { fs.rmSync(base, { recursive: true, force: true }); }
});

test('cleanup post is success-only and registered before every cache save action', () => {
  const action = fs.readFileSync(path.join(__dirname, '../actions/setup-rust/action.yml'), 'utf8');
  const cleanupAt = action.indexOf('uses: $/actions/cleanup-rust-targets');
  for (const cache of ['uses: Swatinem/rust-cache@', 'uses: actions/cache@', 'uses: tespkg/actions-cache@', 'uses: $/actions/s3-target-cache']) {
    assert.ok(action.indexOf(cache) > cleanupAt, cache);
  }
  const metadata = fs.readFileSync(path.join(__dirname, '../actions/cleanup-rust-targets/action.yml'), 'utf8');
  assert.match(metadata, /post-if: success\(\)/);
});
