# /// script
# dependencies = ["moto[server]==5.2.3", "PyYAML==6.0.3"]
# ///
"""Run with `uv run scripts/test-s3-target-cache.py`; no LAN credentials needed."""
from dataclasses import dataclass
import hashlib
import json
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


@dataclass(frozen=True)
class CacheProvider:
    step_id: str
    kind: str
    transfer: str
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


def exercise(base, provider):
    provider_id = provider.step_id
    base.mkdir()
    bucket = f"cache-{provider_id}-{provider.transfer}"
    workspace = base / "workspace"
    shutil.copytree(ROOT / "fixtures/rust-job", workspace, ignore=shutil.ignore_patterns("target"))
    (workspace / ".cargo").mkdir()
    (workspace / ".cargo/config.toml").write_text('[build]\ntarget-dir = "output"\nbuild-dir = "build"\n')
    env = {k: v for k, v in os.environ.items() if not k.startswith(("AWS_", "SCCACHE_", "CARGO_", "RUSTC_", "INPUT_", "STATE_", "GITHUB_"))}
    env.update({
        "GITHUB_WORKSPACE": str(workspace), "GITHUB_REPOSITORY": "example/repo",
        "GITHUB_REF": "refs/heads/main", "GITHUB_OUTPUT": str(base / "output"),
        "GITHUB_STATE": str(base / "state"), "GITHUB_ENV": str(base / "environment"), "RUNNER_TEMP": str(base),
        "RUNNER_OS": {"Darwin": "macOS"}.get(platform.system(), platform.system()),
        "RUNNER_ARCH": platform.machine(),
        "CACHE_WORKSPACES": ".", "CACHE_SHARED_KEY": "round-trip",
        "CACHE_CARGO_HOME": str(base / "cargo-home"),
        "CACHE_TRANSFER": provider.transfer,
        "CACHE_DEFAULT_BRANCH": "main", "CACHE_AUTH": "static", "CACHE_BUCKET": bucket,
        "CACHE_ACCESS_KEY": "testing", "CACHE_SECRET_KEY": "testing",
        "AWS_ACCESS_KEY_ID": "testing", "AWS_SECRET_ACCESS_KEY": "testing",
        "AWS_DEFAULT_REGION": "us-east-1", "AWS_EC2_METADATA_DISABLED": "true",
    })
    for name in ["output", "state", "environment"]:
        (base / name).touch()
    run(["git", "init", "-q"], workspace, env)
    run(["git", "add", "."], workspace, env)
    run(["git", "-c", "user.name=Cache Test", "-c", "user.email=cache@example.invalid", "commit", "-qm", "fixture"], workspace, env)
    action = yaml.safe_load((ROOT / "actions/cache-rust-s3/action.yml").read_text())
    step = next(step for step in action["runs"]["steps"] if step.get("id") == provider_id)
    if step["uses"].startswith("$/"):
        provider_path = ROOT / step["uses"][2:]
    else:
        repo, ref = step["uses"].split("@")
        provider_path = base / "provider"
        provider_path.mkdir()
        run(["git", "init", "-q"], provider_path, env)
        run(["git", "fetch", "-q", "--depth=1", f"https://github.com/{repo}.git", ref], provider_path, env)
        run(["git", "checkout", "-q", "FETCH_HEAD"], provider_path, env)
    server = ThreadedMotoServer(ip_address="127.0.0.1", port=0, verbose=False)
    server.start()
    try:
        host, port = server.get_host_and_port()
        endpoint = f"http://{host}:{port}"
        env["CACHE_ENDPOINT"] = endpoint
        client = boto3.client("s3", endpoint_url=endpoint, region_name="us-east-1",
                              aws_access_key_id="testing", aws_secret_access_key="testing")
        client.create_bucket(Bucket=bucket)
        run(["node", str(ROOT / "actions/cache-rust-s3/prepare.cjs")], workspace, env)
        config = command_file(base / "output")
        expressions = {f"steps.config.outputs.{k}": v for k, v in config.items()}
        expressions.update({
            "inputs.bucket": bucket, "inputs.access-key": "testing",
            "inputs.secret-key": "testing", "inputs.session-token": "",
            "inputs.zstd-level": "3", "inputs.transfer": provider.transfer,
            "inputs.failure-policy": "fail",
            "github.event_name == 'pull_request' || github.event_name == 'pull_request_target'": "false",
        })
        for name, value in step.get("env", {}).items():
            env[name] = re.sub(r"\$\{\{ (.*?) \}\}", lambda m: expressions[m[1]], str(value))
        for name, value in step["with"].items():
            env[f"INPUT_{name.upper()}"] = re.sub(r"\$\{\{ (.*?) \}\}", lambda m: expressions[m[1]], str(value))
        provider_action = yaml.safe_load((provider_path / "action.yml").read_text())
        for name, spec in provider_action.get("inputs", {}).items():
            env.setdefault(f"INPUT_{name.upper()}", str(spec.get("default", "")))
        restore = ["node", str(provider_path / provider_action["runs"]["main"])]
        save = ["node", str(provider_path / provider_action["runs"]["post"])]
        log = run(restore, workspace, env)
        assert command_file(base / "output")["cache-hit"] == "false", log
        env.update({f"STATE_{k}": v for k, v in command_file(base / "state").items()})
        cargo_home = provider.kind == "registry"
        if cargo_home:
            targets = [Path(p) for p in config["cargo-home-paths"].splitlines()]
            for index, target in enumerate(targets):
                target.mkdir(parents=True)
                (target / "fixture").write_text(f"cargo-home-{index}")
        else:
            run(["cargo", "test", "--locked"], workspace, env)
            targets = [Path(p) for p in config["paths"].splitlines()]
            assert workspace / "output" in targets
            assert workspace / "build" in targets
        artifacts = {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
                     for target in targets for p in target.rglob("*") if p.is_file()}
        assert artifacts, "Rust build produced no artifacts"
        log = run(save, workspace, env)
        assert "cache saved to s3" in log.lower(), log
        objects = client.list_objects_v2(Bucket=bucket)["Contents"]
        if cargo_home:
            namespace = "rust/v1/cargo-home/"
        else:
            namespace = "rust/v1/targets/"
        assert len(objects) == 1 and objects[0]["Key"].startswith(namespace), objects
        for target in targets:
            shutil.rmtree(target)
        log = run(restore, workspace, env)
        assert command_file(base / "output")["cache-hit"] == "true", log
        for artifact, digest in artifacts.items():
            assert hashlib.sha256(Path(artifact).read_bytes()).hexdigest() == digest, artifact
        if not cargo_home:
            run(["cargo", "test", "--offline", "--locked"], workspace, env)
        env["INPUT_KEY"] += "-next-commit"
        env["INPUT_RESTORE-ONLY"] = "true"
        log = run(restore, workspace, env)
        env.update({f"STATE_{k}": v for k, v in command_file(base / "state").items()})
        assert command_file(base / "output")["cache-hit"] == "false", log
        assert "cache" in log.lower() and "s3" in log.lower(), log
        run(save, workspace, env)
        assert len(client.list_objects_v2(Bucket=bucket)["Contents"]) == 1
        print(f"PASS ({provider_id}): restored {len(artifacts)} cached files byte-for-byte from S3.")
        print(f"PASS ({provider_id}): fallback behavior and read-only mode work.")
        denied = dict(env)
        denied["STATE_key"] = config["key"] + "-denied"
        denied["STATE_matched-key"] = ""
        denied["STATE_restore-only"] = "false"
        denied["INPUT_RESTORE-ONLY"] = "false"
        client.put_bucket_policy(Bucket=bucket, Policy=json.dumps({"Version": "2012-10-17", "Statement": [{"Effect": "Deny", "Principal": "*", "Action": "s3:PutObject", "Resource": f"arn:aws:s3:::{bucket}/*"}]}))
        result = subprocess.run(save, cwd=workspace, env=denied, text=True, capture_output=True, timeout=60)
        assert result.returncode != 0, "denied upload was reported as success"
        assert all(target.exists() for target in targets), "failed save removed a target"
        assert f'PULSE_CARGO_{provider.kind.upper()}_SAVE_FAILED' in (base / 'environment').read_text()
        other_kind = 'TARGET' if provider.kind == 'registry' else 'REGISTRY'
        assert f'PULSE_CARGO_{other_kind}_SAVE_FAILED' not in (base / 'environment').read_text()
        (base / "environment").write_text("")
        denied["STATE_failure-policy"] = "warn"
        result = subprocess.run(save, cwd=workspace, env=denied, text=True, capture_output=True, timeout=60)
        assert result.returncode == 0, result.stdout + result.stderr
        assert all(target.exists() for target in targets)
        assert f'PULSE_CARGO_{provider.kind.upper()}_SAVE_FAILED' in (base / 'environment').read_text()
        other_kind = 'TARGET' if provider.kind == 'registry' else 'REGISTRY'
        assert f'PULSE_CARGO_{other_kind}_SAVE_FAILED' not in (base / 'environment').read_text()
        print(f"PASS ({provider_id}): denied upload retains targets in fail and warn modes.")
    finally:
        server.stop()


with tempfile.TemporaryDirectory(prefix="pulse-s3-test-") as directory:
    root = Path(directory).resolve()
    providers = [CacheProvider("registry-cache", "registry", "staged"),
                 CacheProvider("target-cache", "target", "staged")]
    if platform.system() == "Linux":
        providers.append(CacheProvider("target-cache", "target", "streaming"))
    for provider in providers:
        exercise(root / (provider.step_id + "-" + provider.transfer), provider)
