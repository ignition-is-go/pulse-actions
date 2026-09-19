const core = require('@actions/core');
const { client, find, restore } = require('./cache');

async function main() {
  if (process.platform !== 'linux') throw new Error('The streaming S3 target cache supports Linux only.');
  const names = ['endpoint', 'port', 'insecure', 'region', 'bucket', 'access-key', 'secret-key',
    'session-token', 'path', 'key', 'restore-keys', 'restore-only', 'compression-level'];
  for (const name of names) core.saveState(name, core.getInput(name));

  const bucket = core.getInput('bucket', { required: true });
  const key = core.getInput('key', { required: true });
  const restoreKeys = core.getMultilineInput('restore-keys');
  const match = await find(client(), bucket, key, restoreKeys);
  core.saveState('matched-key', match?.key || '');
  core.setOutput('cache-hit', String(match?.key === key));
  core.setOutput('cache-size', String(match?.size || 0));
  core.setOutput('cache-matched-key', match?.key || '');
  if (!match) {
    core.info('No compatible S3 target cache was found.');
    return;
  }
  await restore(client(), bucket, match);
}

main().catch(error => core.setFailed(error.message));
