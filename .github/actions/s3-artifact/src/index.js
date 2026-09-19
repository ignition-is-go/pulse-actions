const core = require('@actions/core');
const { createHash, randomUUID } = require('node:crypto');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { pipeline } = require('node:stream/promises');
const { Client } = require('minio');

function waitFor(child, label) {
  return new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('exit', code => code === 0 ? resolve() : reject(new Error(`${label} exited with code ${code}`)));
  });
}

function storage() {
  const endpoint = new URL(core.getInput('endpoint', { required: true }));
  if (!['http:', 'https:'].includes(endpoint.protocol) || endpoint.username || endpoint.password ||
      endpoint.pathname !== '/' || endpoint.search || endpoint.hash) {
    throw new Error('S3 artifact endpoint must be an HTTP(S) origin without credentials or a path.');
  }
  return new Client({
    endPoint: endpoint.hostname,
    port: Number(endpoint.port || (endpoint.protocol === 'https:' ? 443 : 80)),
    useSSL: endpoint.protocol === 'https:',
    region: 'auto',
    accessKey: core.getInput('access-key', { required: true }),
    secretKey: core.getInput('secret-key', { required: true }),
    sessionToken: core.getInput('session-token') || undefined,
  });
}

function objectKey() {
  const repository = createHash('sha256').update(process.env.GITHUB_REPOSITORY).digest('hex').slice(0, 32);
  const runId = core.getInput('run-id', { required: true });
  const name = encodeURIComponent(core.getInput('name', { required: true }));
  if (!/^\d+$/.test(runId)) throw new Error('Artifact run ID must be numeric.');
  return `artifacts/v1/${repository}/${runId}/${name}.tzst`;
}

function uploadPaths() {
  const workspace = path.resolve(process.env.GITHUB_WORKSPACE);
  return core.getMultilineInput('path', { required: true }).map(candidate => {
    if (/[*?\[\]\r\n]/.test(candidate)) throw new Error('S3 artifact paths must be literal paths.');
    const absolute = path.resolve(workspace, candidate);
    const relative = path.relative(workspace, absolute);
    if (!relative || relative === '..' || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) {
      throw new Error('S3 artifact paths must be inside the workspace.');
    }
    if (!fs.existsSync(absolute)) throw new Error(`Artifact path does not exist: ${candidate}`);
    return relative;
  });
}

async function upload(client, bucket, key) {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'pulse-artifact-'));
  const manifest = path.join(temporary, 'manifest.txt');
  fs.writeFileSync(manifest, `${uploadPaths().join('\n')}\n`);
  const level = core.getInput('compression-level') || '3';
  if (!/^([1-9]|1[0-9])$/.test(level)) throw new Error('Compression level must be from 1 through 19.');
  const tar = spawn('tar', ['--posix', '-cf', '-', '-C', process.env.GITHUB_WORKSPACE,
    '--files-from', manifest, '--use-compress-program', 'zstdmt'], {
    stdio: ['ignore', 'pipe', 'inherit'], env: { ...process.env, ZSTD_CLEVEL: level },
  });
  try {
    core.info(`Streaming artifact to S3 with zstd level ${level}.`);
    await Promise.all([client.putObject(bucket, key, tar.stdout), waitFor(tar, 'artifact upload')]);
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
}

async function download(client, bucket, key) {
  const destination = path.resolve(process.env.GITHUB_WORKSPACE, core.getInput('path', { required: true }));
  fs.mkdirSync(destination, { recursive: true });
  const stat = await client.statObject(bucket, key);
  core.info(`Streaming ${stat.size} bytes from S3 into ${destination}.`);
  const source = await client.getObject(bucket, key);
  const tar = spawn('tar', ['-xf', '-', '-C', destination, '--no-same-owner',
    '--use-compress-program', 'unzstd'], { stdio: ['pipe', 'inherit', 'inherit'] });
  await Promise.all([pipeline(source, tar.stdin), waitFor(tar, 'artifact download')]);
  core.setOutput('size', String(stat.size));
}

async function main() {
  if (process.platform !== 'linux') throw new Error('S3 artifact transfers currently support Linux only.');
  const operation = core.getInput('operation', { required: true });
  const bucket = core.getInput('bucket', { required: true });
  const key = objectKey();
  const client = storage();
  if (operation === 'upload') await upload(client, bucket, key);
  else if (operation === 'download') await download(client, bucket, key);
  else throw new Error('Artifact operation must be upload or download.');
  core.setOutput('object-key', key);
}

main().catch(error => core.setFailed(error.message));
