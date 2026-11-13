const core = require('@actions/core');
const { client, save, state } = require('./cache');

async function post() {
  if (state('restore-only') === 'true') {
    core.info('Cargo cache is restore-only; skipping save.');
    return;
  }
  const key = state('key');
  if (state('matched-key') === key) {
    core.info('The exact Cargo cache key was restored; skipping save.');
    return;
  }
  await save(client(), state('bucket'), key, state('path').split(/\r?\n/).filter(Boolean), state('compression-level'));
}

post().catch(error => {
  const kind = state('kind') || 'target';
  core.exportVariable(`PULSE_CARGO_${kind.toUpperCase()}_SAVE_FAILED`, 'true');
  if (state('failure-policy') === 'fail') core.setFailed(error.message);
  else core.warning(error.message);
});
