# /// script
# dependencies = ["moto[server]==5.2.3"]
# ///
"""Run with `uv run scripts/test-s3-artifact.py`; no S3 credentials needed."""
import logging
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

import boto3
from moto.server import ThreadedMotoServer

ROOT = Path(__file__).resolve().parents[1]
ACTION = ROOT / ".github/actions/s3-artifact/dist/index.js"
logging.getLogger("werkzeug").setLevel(logging.ERROR)


def run(workspace, env):
    result = subprocess.run(["node", str(ACTION)], cwd=workspace, env=env, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"artifact action failed:\n{result.stdout}\n{result.stderr}")
    return result.stdout


with tempfile.TemporaryDirectory(prefix="pulse-s3-artifact-") as directory:
    root = Path(directory)
    workspace = root / "workspace"
    workspace.mkdir()
    (workspace / "target/release").mkdir(parents=True)
    payload = os.urandom(8 * 1024 * 1024)
    (workspace / "target/release/server").write_bytes(payload)
    (workspace / "web/dist").mkdir(parents=True)
    (workspace / "web/dist/index.html").write_text("web")
    output = root / "output"
    output.touch()
    server = ThreadedMotoServer(ip_address="127.0.0.1", port=0, verbose=False)
    server.start()
    try:
        host, port = server.get_host_and_port()
        endpoint = f"http://{host}:{port}"
        client = boto3.client("s3", endpoint_url=endpoint, region_name="us-east-1",
                              aws_access_key_id="testing", aws_secret_access_key="testing")
        client.create_bucket(Bucket="artifacts")
        env = os.environ | {
            "GITHUB_WORKSPACE": str(workspace), "GITHUB_REPOSITORY": "example/repo",
            "GITHUB_OUTPUT": str(output), "INPUT_ENDPOINT": endpoint, "INPUT_BUCKET": "artifacts",
            "INPUT_ACCESS-KEY": "testing", "INPUT_SECRET-KEY": "testing", "INPUT_SESSION-TOKEN": "",
            "INPUT_NAME": "linux-build", "INPUT_RUN-ID": "123", "INPUT_COMPRESSION-LEVEL": "1",
            "INPUT_OPERATION": "upload", "INPUT_PATH": "target/release/server\nweb/dist",
        }
        run(workspace, env)
        objects = client.list_objects_v2(Bucket="artifacts")["Contents"]
        assert len(objects) == 1 and objects[0]["Key"].startswith("rust/v1/artifacts/"), objects
        assert objects[0]["Key"].endswith("/123/linux-build.tzst"), objects
        shutil.rmtree(workspace / "target")
        shutil.rmtree(workspace / "web")
        destination = workspace / "restored"
        env.update({"INPUT_OPERATION": "download", "INPUT_PATH": str(destination)})
        run(workspace, env)
        assert (destination / "target/release/server").read_bytes() == payload
        assert (destination / "web/dist/index.html").read_text() == "web"
        print("PASS: streamed an artifact through S3 and restored its workspace-relative layout.")
    finally:
        server.stop()
