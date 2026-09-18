# /// script
# dependencies = ["moto[server]==5.2.3", "PyYAML==6.0.3"]
# ///
"""Run with `uv run scripts/test-s3-target-cache.py`; no LAN credentials needed."""
import hashlib
import logging
import os
import platform
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

import boto3
from moto.server import ThreadedMotoServer
import yaml

ROOT = Path(__file__).resolve().parents[1]
logging.getLogger("werkzeug").setLevel(logging.ERROR)


def run(args, cwd, env):
    result = subprocess.run(args, cwd=cwd, env=env, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"{args[0]} failed:\n{result.stdout}\n{result.stderr}")
    return result.stdout


def command_file(file):
    lines = iter(file.read_text().splitlines())
    values = {}
    for line in lines:
        if "<<" in line:
            name, marker = line.split("<<", 1)
            value = []
            for part in lines:
                if part == marker:
                    break
                value.append(part)
            values[name] = "\n".join(value)
        elif "=" in line:
            name, value = line.split("=", 1)
            values[name] = value
    return values


def exercise(base):
    workspace = base / "workspace"
    shutil.copytree(ROOT / "fixtures/rust-job", workspace, ignore=shutil.ignore_patterns("target"))
    (workspace / ".cargo").mkdir()
    (workspace / ".cargo/config.toml").write_text('[build]\ntarget-dir = "output"\nbuild-dir = "build"\n')
    env = {k: v for k, v in os.environ.items() if not k.startswith(("AWS_", "SCCACHE_", "CARGO_", "RUSTC_", "INPUT_", "STATE_", "GITHUB_"))}
    env.update({
        "GITHUB_WORKSPACE": str(workspace), "GITHUB_REPOSITORY": "example/repo",
        "GITHUB_REF": "refs/heads/main", "GITHUB_OUTPUT": str(base / "output"),
        "GITHUB_STATE": str(base / "state"), "RUNNER_TEMP": str(base),
        "RUNNER_OS": {"Darwin": "macOS"}.get(platform.system(), platform.system()),
        "RUNNER_ARCH": platform.machine(),
        "CACHE_WORKSPACES": ".", "CACHE_SHARED_KEY": "round-trip",
        "CACHE_DEFAULT_BRANCH": "main", "CACHE_AUTH": "static", "CACHE_BUCKET": "cache",
        "CACHE_ACCESS_KEY": "testing", "CACHE_SECRET_KEY": "testing",
        "AWS_ACCESS_KEY_ID": "testing", "AWS_SECRET_ACCESS_KEY": "testing",
        "AWS_DEFAULT_REGION": "us-east-1", "AWS_EC2_METADATA_DISABLED": "true",
    })
    for name in ["output", "state"]:
        (base / name).touch()
    run(["git", "init", "-q"], workspace, env)
    run(["git", "add", "."], workspace, env)
    run(["git", "-c", "user.name=Cache Test", "-c", "user.email=cache@example.invalid", "commit", "-qm", "fixture"], workspace, env)
    action = yaml.safe_load((ROOT / "actions/setup-rust/action.yml").read_text())
    step = next(step for step in action["runs"]["steps"] if step.get("id") == "s3-target-cache")
    repo, ref = step["uses"].split("@")
    provider = base / "provider"
    provider.mkdir()
    run(["git", "init", "-q"], provider, env)
    run(["git", "fetch", "-q", "--depth=1", f"https://github.com/{repo}.git", ref], provider, env)
    run(["git", "checkout", "-q", "FETCH_HEAD"], provider, env)
    server = ThreadedMotoServer(ip_address="127.0.0.1", port=0, verbose=False)
    server.start()
    try:
        host, port = server.get_host_and_port()
        endpoint = f"http://{host}:{port}"
        env["CACHE_ENDPOINT"] = endpoint
        client = boto3.client("s3", endpoint_url=endpoint, region_name="us-east-1",
                              aws_access_key_id="testing", aws_secret_access_key="testing")
        client.create_bucket(Bucket="cache")
        run(["node", str(ROOT / "actions/setup-rust/prepare-target-cache.cjs")], workspace, env)
        config = command_file(base / "output")
        expressions = {f"steps.s3-target-config.outputs.{k}": v for k, v in config.items()}
        expressions.update({
            "inputs.compiler-cache-bucket": "cache", "inputs.compiler-cache-access-key": "testing",
            "inputs.compiler-cache-secret-key": "testing", "inputs.compiler-cache-session-token": "",
            "github.event_name == 'pull_request' || github.event_name == 'pull_request_target'": "false",
        })
        for name, value in step["with"].items():
            env[f"INPUT_{name.upper()}"] = re.sub(r"\$\{\{ (.*?) \}\}", lambda m: expressions[m[1]], str(value))
        restore = ["node", str(provider / "dist/restore/index.js")]
        save = ["node", str(provider / "dist/save/index.js")]
        log = run(restore, workspace, env)
        assert command_file(base / "output")["cache-hit"] == "false", log
        env.update({f"STATE_{k}": v for k, v in command_file(base / "state").items()})
        run(["cargo", "test", "--locked"], workspace, env)
        targets = [Path(p) for p in config["paths"].splitlines()]
        assert workspace / "output" in targets
        assert workspace / "build" in targets
        artifacts = {str(p.relative_to(workspace)): hashlib.sha256(p.read_bytes()).hexdigest()
                     for target in targets for p in target.rglob("*") if p.is_file()}
        assert artifacts, "Rust build produced no artifacts"
        log = run(save, workspace, env)
        assert "Cache saved to s3 successfully" in log, log
        objects = client.list_objects_v2(Bucket="cache")["Contents"]
        assert len(objects) == 1 and objects[0]["Key"].startswith("rust-target-v1-")
        for target in targets:
            shutil.rmtree(target)
        log = run(restore, workspace, env)
        assert command_file(base / "output")["cache-hit"] == "true", log
        for relative, digest in artifacts.items():
            assert hashlib.sha256((workspace / relative).read_bytes()).hexdigest() == digest, relative
        run(["cargo", "test", "--offline", "--locked"], workspace, env)
        env["INPUT_KEY"] += "-next-commit"
        log = run(restore, workspace, env)
        assert command_file(base / "output")["cache-hit"] == "false", log
        assert "Cache restored from s3 successfully" in log, log
        env["INPUT_RESTORE-ONLY"] = "true"
        run(save, workspace, env)
        assert len(client.list_objects_v2(Bucket="cache")["Contents"]) == 1
        print(f"PASS: restored {len(artifacts)} Rust build files byte-for-byte from S3; offline tests passed.")
        print("PASS: prefix restore works; read-only mode does not upload; GitHub fallback disabled.")
    finally:
        server.stop()


with tempfile.TemporaryDirectory(prefix="pulse-s3-test-") as directory:
    exercise(Path(directory).resolve())
