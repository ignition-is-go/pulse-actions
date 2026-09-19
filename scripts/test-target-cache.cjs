const { test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const root = path.resolve('/work/repo');
const { prepare } = require('../actions/setup-rust/prepare-target-cache.cjs');

const env = {
  CACHE_AUTH: 'static', CACHE_ENDPOINT: 'http://cache.example.invalid:9000',
  CACHE_BUCKET: 'cache', CACHE_ACCESS_KEY: 'test', CACHE_SECRET_KEY: 'test',
  CACHE_WORKSPACES: '.', CACHE_SHARED_KEY: 'v1', CACHE_LOCK_HASH: 'lock',
  CACHE_ENV_HASH: 'manifests', CACHE_TRANSFER: 'staged', CACHE_DEFAULT_BRANCH: 'main',
  CACHE_CARGO_HOME: path.join(root, '.cargo'),
  GITHUB_WORKSPACE: root, GITHUB_REPOSITORY: 'example/repo',
  GITHUB_REF: 'refs/heads/main', RUNNER_OS: 'Linux', RUNNER_ARCH: 'X64',
};
const run = (program) => ({cargo: JSON.stringify({target_directory: path.join(root, 'custom-target')}), rustc: 'rustc 1.97.1', git: 'abc123'})[program];
const config = (overrides = {}) => prepare({...env, ...overrides}, run);

test('resolves custom Cargo target and endpoint transport', () => {
  const result = config();
  assert.equal(result.paths, path.join(root, 'custom-target'));
  assert.equal(result.endpoint, 'cache.example.invalid');
  assert.equal(result.port, '9000');
  assert.equal(result.insecure, 'true');
  assert.equal(config({CACHE_ENDPOINT: 'https://cache.example.invalid'}).port, '443');
  assert.equal(config({CACHE_ENDPOINT: 'https://cache.example.invalid'}).insecure, 'false');
});
test('supports explicit workspace mappings and deduplicates targets', () => {
  assert.equal(config({CACHE_WORKSPACES: '. -> target\n. -> target\nsub -> output'}).paths,
    [path.join(root, 'target'), path.join(root, 'sub/output')].join('\n'));
});
test('uses separate lockfile-based paths and keys for the Cargo home cache', () => {
  const result = config();
  assert.equal(result['cargo-home-paths'], [path.join(root, '.cargo/registry/cache'),
    path.join(root, '.cargo/git/db')].join('\n'));
  assert.notEqual(result['cargo-home-key'], result.key);
  assert.equal(config({GITHUB_REF: 'refs/heads/other'})['cargo-home-key'], result['cargo-home-key']);
  assert.notEqual(config({CACHE_LOCK_HASH: 'other-lock'})['cargo-home-key'], result['cargo-home-key']);
});
test('keys separate repositories, branches, toolchains, dependencies and build environments', () => {
  const base = config();
  for (const changes of [
    {GITHUB_REPOSITORY: 'example/other'}, {GITHUB_REF: 'refs/heads/feature'},
    {RUNNER_OS: 'Windows'}, {RUNNER_ARCH: 'ARM64'}, {CACHE_LOCK_HASH: 'new-lock'},
    {CACHE_ENV_HASH: 'new-manifests'}, {CACHE_SHARED_KEY: 'v2'}, {RUSTFLAGS: '-C target-cpu=native'},
    {CACHE_WORKSPACES: '. -> other-target'}, {CACHE_TRANSFER: 'streaming'},
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

test('same-repository PRs warm their own cache without exposing it to branch builds', () => {
  const prEnv = {GITHUB_EVENT_NAME: 'pull_request', GITHUB_REF: 'refs/pull/3/merge',
    GITHUB_BASE_REF: 'dev', CACHE_PR_HEAD_REPOSITORY: env.GITHUB_REPOSITORY};
  const pr = config(prEnv);
  assert.equal(pr['restore-only'], 'false');
  const prefixes = pr['restore-key'].split('\n');
  assert.equal(prefixes.length, 3);
  assert.ok(pr.key.startsWith(prefixes[0]));
  assert.equal(prefixes[1], config({GITHUB_REF: 'refs/heads/dev'})['restore-key'].split('\n')[0]);
  assert.equal(prefixes[2], config()['restore-key']);
  for (const ref of ['refs/heads/main', 'refs/heads/dev', 'refs/pull/4/merge']) {
    assert.ok(!config({GITHUB_REF: ref})['restore-key'].includes(prefixes[0]));
  }
  assert.equal(config({...prEnv, CACHE_PR_HEAD_REPOSITORY: 'fork/repo'})['restore-only'], 'true');
  assert.equal(config({...prEnv, CACHE_PR_HEAD_REPOSITORY: ''})['restore-only'], 'true');
  assert.equal(config({...prEnv, GITHUB_EVENT_NAME: 'pull_request_target'})['restore-only'], 'true');
  assert.equal(config({GITHUB_EVENT_NAME: 'push'})['restore-only'], 'false');
});
test('rejects empty mappings, glob paths and target directories containing source', () => {
  for (const mapping of [' \n ', '. ->', '. -> a -> b', '. -> .', '. -> ..', '. -> target/*']) {
    assert.throws(() => config({CACHE_WORKSPACES: mapping}));
  }
});
test('includes a separate Cargo build directory', () => {
  const result = prepare(env, (p, ...args) => p === 'cargo' ?
    JSON.stringify({target_directory: path.join(root, 'target'), build_directory: path.join(root, 'build')}) : run(p, ...args));
  assert.equal(result.paths, [path.join(root, 'target'), path.join(root, 'build')].join('\n'));
});

test('provider object names preserve lookup prefixes on Windows and Unix', () => {
  for (const [os, platformPath, namespace] of [
    ['Linux', path.posix, 'rust/v1/targets/'],
    ['macOS', path.posix, 'rust/v1/targets/'],
    ['Windows', path.win32, 'rust-target-v1-'],
  ]) {
    const result = config({RUNNER_OS: os});
    const { key } = result;
    assert.ok(key.startsWith(namespace));
    assert.ok(result['restore-key'].split('\n').every(prefix => prefix.startsWith(namespace)));
    assert.ok(platformPath.join(key, 'cache.tzst').startsWith(key + platformPath.sep));
    if (os !== 'Windows') {
      assert.ok(platformPath.join(key, 'cache.tzst').startsWith('rust/v1/'));
    }
  }
});
