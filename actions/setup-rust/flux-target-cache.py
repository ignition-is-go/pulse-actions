"""Native Flux snapshots for the shared Linux workflow; remove targets after save."""
import json
import os
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import tomllib


def command(*args, capture=False):
    return subprocess.run(args, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None).stdout


def restore():
    root = Path(os.environ['GITHUB_WORKSPACE']).resolve()
    config = tomllib.loads((root / 'flux.toml').read_text())
    if not config.get('cache', {}).get('s3'):
        raise ValueError('S3 workflow requires [cache.s3] in flux.toml; see setup-rust documentation')
    flux = os.environ['CARGO_FLUX_BIN']
    metadata = json.loads(command('cargo', 'metadata', '--no-deps', '--format-version', '1', capture=True))
    paths = []
    for value in [metadata['target_directory'], metadata.get('build_directory') or metadata['target_directory']]:
        relative = Path(value).resolve().relative_to(root)
        if relative == Path('.'):
            raise ValueError('Cargo target must not be the source checkout')
        if str(relative) not in paths:
            paths.append(str(relative))
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    repo = os.environ['GITHUB_REPOSITORY']
    ref = os.environ['GITHUB_REF']
    default_ref = 'refs/heads/' + event['repository']['default_branch']
    scope = os.environ.get('FLUX_CACHE_SCOPE', '')
    suffix = ':' + scope if scope else ''
    key = command(flux, 'storage', 'cargo-key', '--scope', f'{repo}:{ref}{suffix}', capture=True).strip()
    fallback = command(flux, 'storage', 'cargo-key', '--scope', f'{repo}:{default_ref}{suffix}', capture=True).strip()
    path_args = [arg for p in paths for arg in ['--path', p]]
    command(flux, 'storage', 'restore', '--key', key, '--key', fallback, *path_args)
    for p in paths:
        command(flux, 'storage', 'sources', '--restore', '--path', p)
    writable = os.environ.get('GITHUB_EVENT_NAME') != 'pull_request_target' and (
        'pull_request' not in event or event['pull_request']['head']['repo']['full_name'] == repo)
    state = {'paths': paths, 'key': key, 'writable': writable}
    with tempfile.NamedTemporaryFile(mode='w', dir=os.environ['RUNNER_TEMP'], suffix='.flux-cache.json', delete=False) as f:
        json.dump(state, f)
        state_file = f.name
    with open(os.environ['GITHUB_OUTPUT'], 'a') as f:
        f.write(f'state={state_file}\n')


def save():
    state_file = Path(os.environ['FLUX_CACHE_STATE'])
    state = json.loads(state_file.read_text())
    if not state['writable']:
        print('Read-only cache job: retaining local targets')
        return
    flux = os.environ['CARGO_FLUX_BIN']
    paths = [p for p in state['paths'] if Path(p).exists()]
    if paths:
        for p in paths:
            command(flux, 'storage', 'sources', '--path', p)
        command(flux, 'storage', 'save', '--key', state['key'],
                *[arg for p in paths for arg in ['--path', p]])
        root = Path(os.environ['GITHUB_WORKSPACE']).resolve()
        targets = [Path(p) for p in paths]
        for target in targets:
            resolved = target.resolve()
            if target.is_symlink() or resolved == root or not resolved.is_relative_to(root):
                raise ValueError('Refusing to clean a target outside this checkout')
        for target in targets:
            shutil.rmtree(target)
            print(f'Removed uploaded local Cargo target: {target}')
    state_file.unlink()


if __name__ == '__main__':
    {'restore': restore, 'save': save}[sys.argv[1]]()
