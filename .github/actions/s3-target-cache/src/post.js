const core = require('@actions/core');
const { client, save, state } = require('./cache');

async function post() {
  if (state('restore-only') === 'true') {
    core.info('Target cache is restore-only; skipping save.');
    return;
  }
  const key = state('key');
  if (state('matched-key') === key) {
    core.info('The exact target cache key was restored; skipping save.');
    return;
  }
  await save(client(), state('bucket'), key, state('path').split(/\r?\n/).filter(Boolean), state('compression-level'));
}

post().catch(error => core.setFailed(error.message));
