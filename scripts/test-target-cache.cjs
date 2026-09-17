const { test } = require('node:test');
const assert = require('node:assert/strict');
const { prepare } = require('../actions/setup-rust/prepare-target-cache.cjs');

const env = {
  CACHE_AUTH: 'static', CACHE_ENDPOINT: 'http://cache.example.invalid:9000',
  CACHE_BUCKET: 'cache', CACHE_ACCESS_KEY: 'test', CACHE_SECRET_KEY: 'test',
  CACHE_WORKSPACES: '.', CACHE_SHARED_KEY: 'v1', CACHE_LOCK_HASH: 'lock',
  CACHE_ENV_HASH: 'manifests', CACHE_DEFAULT_BRANCH: 'main',
  GITHUB_WORKSPACE: '/work/repo', GITHUB_REPOSITORY: 'example/repo',
  GITHUB_REF: 'refs/heads/main', RUNNER_OS: 'Linux', RUNNER_ARCH: 'X64',
};
const run = (program) => ({cargo: '{"target_directory":"/work/repo/custom-target"}', rustc: 'rustc 1.97.1', git: 'abc123'})[program];
const config = (overrides = {}) => prepare({...env, ...overrides}, run);

test('resolves custom Cargo target and endpoint transport', () => {
  const result = config();
  assert.equal(result.paths, '/work/repo/custom-target');
  assert.equal(result.endpoint, 'cache.example.invalid');
  assert.equal(result.port, '9000');
  assert.equal(result.insecure, 'true');
  assert.equal(config({CACHE_ENDPOINT: 'https://cache.example.invalid'}).port, '443');
  assert.equal(config({CACHE_ENDPOINT: 'https://cache.example.invalid'}).insecure, 'false');
});
test('supports explicit workspace mappings and deduplicates targets', () => {
  assert.equal(config({CACHE_WORKSPACES: '. -> target\n. -> target\nsub -> output'}).paths,
    '/work/repo/target\n/work/repo/sub/output');
});
test('keys separate repositories, branches, toolchains, dependencies and build environments', () => {
  const base = config();
  for (const changes of [
    {GITHUB_REPOSITORY: 'example/other'}, {GITHUB_REF: 'refs/heads/feature'},
    {RUNNER_OS: 'Windows'}, {RUNNER_ARCH: 'ARM64'}, {CACHE_LOCK_HASH: 'new-lock'},
    {CACHE_ENV_HASH: 'new-manifests'}, {CACHE_SHARED_KEY: 'v2'}, {RUSTFLAGS: '-C target-cpu=native'},
    {CACHE_WORKSPACES: '. -> other-target'},
  ]) assert.notEqual(config(changes).key, base.key);
  assert.notEqual(prepare(env, (p, ...args) => p === 'rustc' ? 'new compiler' : run(p, ...args)).key, base.key);
  assert.notEqual(prepare(env, (p, ...args) => p === 'git' ? 'new revision' : run(p, ...args)).key, base.key);
  const pr = config({GITHUB_REF: 'refs/pull/3/merge'});
  assert.equal(pr['restore-key'].split('\n')[1], base['restore-key']);
  assert.equal(base['restore-key'].split('\n').length, 1);
});
test('rejects missing credentials, unsupported auth and malformed endpoints without printing secrets', () => {
  for (const name of ['CACHE_ENDPOINT', 'CACHE_BUCKET', 'CACHE_ACCESS_KEY', 'CACHE_SECRET_KEY']) {
    assert.throws(() => config({[name]: ''}), /requires/);
  }
  for (const auth of ['ambient', 'anonymous', 'wrong']) assert.throws(() => config({CACHE_AUTH: auth}), /static/);
  for (const endpoint of ['ftp://cache.example.invalid', 'invalid', 'https://user:secret@cache.example.invalid',
    'https://cache.example.invalid/path', 'https://cache.example.invalid?query=1']) {
    assert.throws(() => config({CACHE_ENDPOINT: endpoint}), /HTTP\(S\) origin/);
  }
  assert.throws(() => config({CACHE_SECRET_KEY: 'sensitive\ninjected'}), error =>
    !error.message.includes('sensitive') && /single-line/.test(error.message));
});
test('rejects empty mappings, glob paths and target directories containing source', () => {
  for (const mapping of [' \n ', '. ->', '. -> a -> b', '. -> .', '. -> ..', '. -> target/*']) {
    assert.throws(() => config({CACHE_WORKSPACES: mapping}));
  }
});
test('includes a separate Cargo build directory', () => {
  const result = prepare(env, (p, ...args) => p === 'cargo' ?
    '{"target_directory":"/work/repo/target","build_directory":"/work/repo/build"}' : run(p, ...args));
  assert.equal(result.paths, '/work/repo/target\n/work/repo/build');
});
