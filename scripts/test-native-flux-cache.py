# /// script
# requires-python = ">=3.11"
# dependencies = ["moto[server]==5.2.3"]
# ///
"""Exercise the shared adapter with a real Flux binary and an isolated S3 server."""
import json
import logging
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

import boto3
from moto.server import ThreadedMotoServer

ROOT = Path(__file__).resolve().parents[1]
logging.getLogger('werkzeug').setLevel(logging.ERROR)


def run(args, cwd, env, ok=True):
    result = subprocess.run(args, cwd=cwd, env=env, text=True, capture_output=True)
    if ok and result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result


def main():
    server = ThreadedMotoServer(ip_address='127.0.0.1', port=0, verbose=False)
    server.start()
    try:
        host, port = server.get_host_and_port()
        endpoint = f'http://{host}:{port}'
        s3 = boto3.client('s3', endpoint_url=endpoint, aws_access_key_id='test', aws_secret_access_key='test', region_name='us-east-1')
        s3.create_bucket(Bucket='flux-ci-fixture')
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            root = base / 'checkout'
            shutil.copytree(ROOT / 'fixtures/rust-job', root, ignore=shutil.ignore_patterns('target'))
            (root / '.cargo').mkdir(exist_ok=True)
            (root / '.cargo/config.toml').write_text('[build]\ntarget-dir = "out"\n')
            (root / 'flux.toml').write_text('[cache.s3]\nendpoint_env="CARGO_FLUX_S3_ENDPOINT"\nbucket_env="CARGO_FLUX_S3_BUCKET"\nprefix="rust/v1/flux/fixture"\ntimeout_seconds=10\n')
            event = base / 'event.json'
            event.write_text(json.dumps({'repository': {'default_branch': 'main'}}))
            output = base / 'output'
            env = dict(os.environ, GITHUB_WORKSPACE=str(root), GITHUB_REPOSITORY='example/project', GITHUB_REF='refs/heads/main', GITHUB_EVENT_NAME='push', GITHUB_EVENT_PATH=str(event), GITHUB_OUTPUT=str(output), RUNNER_TEMP=str(base), CARGO_FLUX_S3_ENDPOINT=endpoint, CARGO_FLUX_S3_BUCKET='flux-ci-fixture', CARGO_FLUX_S3_ACCESS_KEY_ID='test', CARGO_FLUX_S3_SECRET_ACCESS_KEY='test', CARGO_FLUX_S3_REGION='us-east-1')
            for name in ['CARGO_TARGET_DIR', 'RUSTC_WRAPPER', 'RUSTC_WORKSPACE_WRAPPER']:
                env.pop(name, None)
            for args in [['git', 'init', '-q'], ['git', 'add', '.']]:
                run(args, root, env)
            adapter = [sys.executable, str(ROOT / 'actions/setup-rust/flux-target-cache.py')]
            run(adapter + ['restore'], root, env)
            env['FLUX_CACHE_STATE'] = output.read_text().strip().split('=', 1)[1]
            run(['cargo', 'test', '--offline'], root, env)
            (root / 'dist').mkdir()
            (root / 'dist/published').write_text('published artifact')
            failed_env = dict(env, CARGO_FLUX_S3_ENDPOINT='http://127.0.0.1:9')
            assert run(adapter + ['save'], root, failed_env, ok=False).returncode != 0
            assert (root / 'out').is_dir(), 'failed upload removed local outputs'
            assert Path(env['FLUX_CACHE_STATE']).exists()
            run(adapter + ['save'], root, env)
            assert not (root / 'out').exists(), 'successful upload left local outputs'
            assert (root / 'dist/published').read_text() == 'published artifact'
            objects = s3.list_objects_v2(Bucket='flux-ci-fixture').get('Contents', [])
            assert objects and all(o['Key'].startswith('rust/v1/flux/fixture/') for o in objects)
            output.write_text('')
            env['GITHUB_REF'] = 'refs/heads/feature'
            run(adapter + ['restore'], root, env)
            assert (root / 'out').is_dir(), 'native S3 snapshot was not restored'
            run(['cargo', 'test', '--offline'], root, env)
            print('PASS: native S3 miss/build, failed-save retention, successful-save cleanup, artifact preservation, restore and offline test')
    finally:
        server.stop()


if __name__ == '__main__':
    main()
