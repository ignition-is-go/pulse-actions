# /// script
# dependencies = ["moto[server]==5.2.3"]
# ///
"""Keep an isolated denied-save S3 fixture alive through the runner's post steps.

The child inherits RUNNER_TRACKING_ID and is reclaimed by normal job cleanup.
No production credentials, cache namespace or network interface is used.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time

import boto3
from moto.server import ThreadedMotoServer


def serve(root):
    server = ThreadedMotoServer(ip_address='127.0.0.1', port=0, verbose=False)
    server.start()
    host, port = server.get_host_and_port()
    client = boto3.client('s3', endpoint_url=f'http://{host}:{port}', region_name='us-east-1',
                          aws_access_key_id='testing', aws_secret_access_key='testing')
    bucket = 'denied-target-save'
    client.create_bucket(Bucket=bucket)
    client.put_bucket_policy(Bucket=bucket, Policy=json.dumps({
        'Version': '2012-10-17', 'Statement': [{'Effect': 'Deny', 'Principal': '*',
        'Action': 's3:PutObject', 'Resource': f'arn:aws:s3:::{bucket}/*'}]}))
    (root / 'ready.tmp').write_text(json.dumps({'port': port, 'bucket': bucket}))
    (root / 'ready.tmp').replace(root / 'ready.json')
    threading.Event().wait()


def start():
    root = Path(tempfile.mkdtemp(prefix='target-save-warning-', dir=os.environ['RUNNER_TEMP']))
    subprocess.Popen([sys.executable, str(Path(__file__).resolve()), '--serve', str(root)],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(300):
        if (root / 'ready.json').exists():
            config = json.loads((root / 'ready.json').read_text())
            break
        time.sleep(0.1)
    else:
        raise RuntimeError('Owned S3 fixture did not become ready')
    target = Path(os.environ['GITHUB_WORKSPACE']) / '.ci-cache-warning-target'
    target.mkdir()
    (target / 'warm').write_text('warm compiler fixture\n')
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        for key, value in config.items():
            output.write(f'{key}={value}\n')


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--serve':
        serve(Path(sys.argv[2]))
    else:
        start()
