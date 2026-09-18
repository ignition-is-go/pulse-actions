const { createHash, randomUUID } = require('node:crypto');
const { execFileSync } = require('node:child_process');
const { appendFileSync } = require('node:fs');
const path = require('node:path');

function hash(value) {
  return createHash('sha256').update(JSON.stringify(value)).digest('hex').slice(0, 32);
}

function prepare(env, run = (program, args, cwd) =>
  execFileSync(program, args, { cwd, encoding: 'utf8' }).trim()) {
  for (const field of ['CACHE_AUTH', 'CACHE_ENDPOINT', 'CACHE_BUCKET',
    'CACHE_ACCESS_KEY', 'CACHE_SECRET_KEY', 'CACHE_SESSION_TOKEN']) {
    if (/[\r\n]/.test(env[field] || '')) throw new Error(`${field} must be single-line.`);
  }
  if (env.CACHE_AUTH !== 'static') {
    throw new Error('S3 target caching requires static compiler-cache authentication.');
  }
  for (const field of ['CACHE_ENDPOINT', 'CACHE_BUCKET', 'CACHE_ACCESS_KEY', 'CACHE_SECRET_KEY']) {
    if (!env[field]) throw new Error(`S3 target caching requires ${field}.`);
  }
  let endpoint;
  try { endpoint = new URL(env.CACHE_ENDPOINT); }
  catch { throw new Error('S3 target cache endpoint must be an HTTP(S) origin.'); }
  if (!['http:', 'https:'].includes(endpoint.protocol) || endpoint.username ||
      endpoint.password || endpoint.pathname !== '/' || endpoint.search || endpoint.hash) {
    throw new Error('S3 target cache endpoint must be an HTTP(S) origin without credentials or a path.');
  }

  const root = env.GITHUB_WORKSPACE;
  const workspaces = (env.CACHE_WORKSPACES || '.').split(/\r?\n/).map(s => s.trim()).filter(Boolean);
  const paths = [];
  for (const entry of workspaces) {
    const parts = entry.split('->').map(s => s.trim());
    if (parts.length > 2 || parts.some(s => !s)) throw new Error('Invalid cache-workspaces entry.');
    const cwd = path.resolve(root, parts[0]);
    let directories;
    if (parts.length === 2) {
      directories = [path.resolve(cwd, parts[1])];
    } else {
      const metadata = JSON.parse(run('cargo', ['metadata', '--no-deps', '--format-version', '1'], cwd));
      directories = [metadata.target_directory, metadata.build_directory || metadata.target_directory];
    }
    for (const target of directories) {
      if (typeof target !== 'string' || /[\r\n!*?\[\]]/.test(target)) {
        throw new Error('Target directory must be a literal, single-line path.');
      }
      const relative = path.relative(path.resolve(target), root);
      if (!relative || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative))) {
        throw new Error('Target directory must not contain the source checkout.');
      }
      paths.push(path.resolve(target));
    }
  }
  if (!paths.length) throw new Error('At least one cache workspace is required.');
  const uniquePaths = [...new Set(paths)];
  const compiler = run('rustc', ['--version', '--verbose'], root);
  const revision = run('git', ['rev-parse', 'HEAD'], root);
  const buildEnv = Object.entries(env).filter(([name]) =>
    /^(RUSTFLAGS|RUSTDOCFLAGS|CARGO_ENCODED_RUSTFLAGS|CARGO_BUILD_TARGET|CC|CXX|CFLAGS|CXXFLAGS)$/.test(name)
    || /^CARGO_(PROFILE_|TARGET_)/.test(name)).sort(([a], [b]) => a.localeCompare(b));
  const identity = hash([env.RUNNER_OS, env.RUNNER_ARCH, compiler, uniquePaths.map(p => path.relative(root, p)),
    env.CACHE_SHARED_KEY, env.CACHE_ENV_HASH, env.CACHE_LOCK_HASH, buildEnv]);
  const prefix = `rust-target-v1-${hash(env.GITHUB_REPOSITORY)}-${identity}`;
  const branchPrefix = `${prefix}-${hash(env.GITHUB_REF)}-`;
  const defaultPrefix = `${prefix}-${hash(`refs/heads/${env.CACHE_DEFAULT_BRANCH}`)}-`;
  const restorePrefixes = [branchPrefix];
  if (env.GITHUB_BASE_REF) restorePrefixes.push(`${prefix}-${hash(`refs/heads/${env.GITHUB_BASE_REF}`)}-`);
  restorePrefixes.push(defaultPrefix);
  const pullRequest = env.GITHUB_EVENT_NAME === 'pull_request';
  const restoreOnly = env.GITHUB_EVENT_NAME === 'pull_request_target' ||
    (pullRequest && env.CACHE_PR_HEAD_REPOSITORY !== env.GITHUB_REPOSITORY);
  return {
    endpoint: endpoint.hostname,
    port: endpoint.port || (endpoint.protocol === 'https:' ? '443' : '80'),
    insecure: String(endpoint.protocol === 'http:'),
    paths: uniquePaths.join('\n'),
    key: `${branchPrefix}${revision}`,
    'restore-key': [...new Set(restorePrefixes)].join('\n'),
    'restore-only': String(restoreOnly),
  };
}

if (require.main === module) {
  try {
    const values = prepare(process.env);
    for (const [name, value] of Object.entries(values)) {
      const delimiter = randomUUID();
      appendFileSync(process.env.GITHUB_OUTPUT, `${name}<<${delimiter}\n${value}\n${delimiter}\n`);
    }
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}

module.exports = { prepare };
