"""Verify shared workflow wiring to the pinned native Flux S3 setup action."""
from pathlib import Path
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[1]


class FluxWorkflowCacheTest(unittest.TestCase):
    def setUp(self):
        self.steps = yaml.safe_load((ROOT / '.github/workflows/cargo-flux-quality.yml').read_text())['jobs']['check']['steps']
        self.setup = next(s for s in self.steps if s.get('name') == 'Set up Cargo Flux and its native S3 client')

    def test_verified_action_preserves_callers_version(self):
        self.assertEqual(self.setup['uses'], 'ignition-is-go/cargo-flux@eecab76c2c1296cb7e9e5b8d8d72149e49282fb4')
        self.assertEqual(self.setup['with']['version'], '${{ inputs.cargo-flux-version }}')
        self.assertFalse(any('cargo install cargo-flux' in s.get('run', '') for s in self.steps))

    def test_native_cache_follows_existing_s3_selection_and_credentials(self):
        inputs = self.setup['with']
        self.assertEqual(inputs['cache'], "${{ inputs.cache-target-backend == 's3' && 's3' || '' }}")
        for action_input, secret in [('cache-endpoint', 'CI_CACHE_ENDPOINT'), ('cache-bucket', 'CI_CACHE_BUCKET'), ('cache-access-key-id', 'CI_CACHE_ACCESS_KEY'), ('cache-secret-access-key', 'CI_CACHE_SECRET_KEY'), ('cache-session-token', 'CI_CACHE_SESSION_TOKEN')]:
            self.assertIn('secrets.' + secret, inputs[action_input])
        self.assertFalse(any(k.startswith('AWS_') for k in self.setup.get('env', {})))
        run = next(s for s in self.steps if s.get('name') == 'Run Cargo Flux tasks')
        self.assertLess(self.steps.index(self.setup), self.steps.index(run))

    def test_native_snapshots_replace_custom_target_transfers_and_clean_after_tasks(self):
        rust = next(s for s in self.steps if s.get('uses') == '$/actions/setup-rust')
        self.assertEqual(rust['with']['cache-targets'], "${{ inputs.cache-target-backend != 's3' }}")
        restore = next(s for s in self.steps if s.get('id') == 'flux-target-cache')
        save = next(s for s in self.steps if s.get('name') == 'Save native Flux snapshot and clean local targets')
        tasks = next(s for s in self.steps if s.get('name') == 'Run Cargo Flux tasks')
        self.assertLess(self.steps.index(restore), self.steps.index(tasks))
        self.assertLess(self.steps.index(tasks), self.steps.index(save))
        self.assertIn('success()', save['if'])
        self.assertEqual(save['with']['state'], '${{ steps.flux-target-cache.outputs.state }}')


if __name__ == '__main__':
    unittest.main()
