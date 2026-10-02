const core = require('@actions/core');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { pipeline } = require('node:stream/promises');
const { Client } = require('minio');

const archiveName = 'cache.tzst';

function state(name) {
  return core.getState(name) || core.getInput(name);
}

function client(values = {}) {
  const insecure = values.insecure ?? state('insecure');
  return new Client({
    endPoint: values.endpoint ?? state('endpoint'),
    port: Number(values.port ?? state('port')),
    useSSL: insecure !== 'true',
    region: values.region ?? state('region'),
    accessKey: values.accessKey ?? state('access-key'),
    secretKey: values.secretKey ?? state('secret-key'),
    sessionToken: (values.sessionToken ?? state('session-token')) || undefined,
  });
}

function objectName(key) {
  return `${key.replace(/\/$/, '')}/${archiveName}`;
}

async function statExact(storage, bucket, key) {
  try {
    const stat = await storage.statObject(bucket, objectName(key));
    return { name: objectName(key), size: stat.size, key };
  } catch (error) {
    if (error.code === 'NotFound' || error.code === 'NoSuchKey') return null;
    throw error;
  }
}

async function newestForPrefix(storage, bucket, prefix) {
  const objects = [];
  const stream = storage.listObjectsV2(bucket, prefix, true);
  await new Promise((resolve, reject) => {
    stream.on('data', object => {
      if (object.name?.endsWith(`/${archiveName}`)) objects.push(object);
    });
    stream.on('error', reject);
    stream.on('end', resolve);
  });
  objects.sort((a, b) => new Date(b.lastModified) - new Date(a.lastModified));
  const object = objects[0];
  if (!object) return null;
  return { name: object.name, size: object.size, key: object.name.slice(0, -(`/${archiveName}`.length)) };
}

async function find(storage, bucket, key, restoreKeys) {
  const exact = await statExact(storage, bucket, key);
  if (exact) return exact;
  for (const prefix of restoreKeys) {
    const candidate = await newestForPrefix(storage, bucket, prefix);
    if (candidate) return candidate;
  }
  return null;
}

function waitFor(child, label) {
  return new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('exit', code => code === 0 ? resolve() : reject(new Error(`${label} exited with code ${code}`)));
  });
}

async function restore(storage, bucket, object) {
  core.info(`Streaming ${object.size} bytes from S3 into the Cargo target cache.`);
  const source = await storage.getObject(bucket, object.name);
  const tar = spawn('tar', ['-xf', '-', '-P', '-C', process.env.GITHUB_WORKSPACE,
    '--use-compress-program', 'unzstd'], { stdio: ['pipe', 'inherit', 'inherit'] });
  await Promise.all([pipeline(source, tar.stdin), waitFor(tar, 'tar restore')]);
}

async function save(storage, bucket, key, paths, compressionLevel) {
  const existing = paths.filter(candidate => fs.existsSync(candidate));
  if (!existing.length) {
    core.info('No target-cache paths exist; skipping save.');
    return;
  }
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'pulse-target-cache-'));
  const manifest = path.join(temporary, 'manifest.txt');
  fs.writeFileSync(manifest, `${existing.join('\n')}\n`);
  const tar = spawn('tar', ['--posix', '-cf', '-', '-P', '-C', process.env.GITHUB_WORKSPACE,
    '--files-from', manifest, '--use-compress-program', 'zstdmt'], {
    stdio: ['ignore', 'pipe', 'inherit'],
    env: { ...process.env, ZSTD_CLEVEL: compressionLevel },
  });
  try {
    core.info(`Streaming the Cargo target cache to S3 with zstd level ${compressionLevel}.`);
    await Promise.all([
      storage.putObject(bucket, objectName(key), tar.stdout),
      waitFor(tar, 'tar save'),
    ]);
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
  core.info('Target cache saved to S3.');
}

module.exports = { client, find, restore, save, state };
