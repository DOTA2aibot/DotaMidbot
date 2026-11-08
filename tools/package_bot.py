"""Build explicit play/probe bundles; install by replacing the complete bots folder."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
import re
from pathlib import Path, PurePosixPath
import subprocess
import time
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ROOT_LUA = ('hero_selection.lua', 'ability_item_usage_nevermore.lua', 'item_purchase_nevermore.lua')
PROBE_ENTRY = 'mode_laning_nevermore.lua'
PROFILES = {'valve_play': ('valve_native', False), 'lane_probe': ('midbot_runtime', True),
            'valve_wards': ('valve_native', False)}


def profile_source(profile, revision='uncommitted'):
    if not re.fullmatch(r'[A-Za-z0-9._-]{1,80}', revision):
        raise ValueError('Revision must be a plain ASCII identifier or commit SHA')
    controller, enabled = PROFILES[profile]
    return (f'return {{ name = "{profile}", controller = "{controller}", '
            f'runtime_enabled = {str(enabled).lower()}, '
            f'observer_enabled = {str(not enabled).lower()}, '
            f'wards_enabled = {str(profile == "valve_wards").lower()}, '
            f'source_revision = "{revision}" }};\n').encode('utf-8')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def below(path, parent):
    path.resolve().relative_to(parent.resolve())
    return path


def collect(profile, root=ROOT, revision='uncommitted'):
    if profile not in PROFILES:
        raise ValueError('Unknown controller profile')
    # Source tree itself is the play layout; the old root entry must be removed.
    unexpected = list(root.glob('mode_*.lua')) + list(root.glob('bot_*.lua'))
    if unexpected:
        raise ValueError('Stale root controller entry: ' + unexpected[0].name)
    files = {}
    paths = [root / name for name in ROOT_LUA] + sorted((root / 'laning').rglob('*.lua'))
    for path in paths:
        below(path, root)
        if path.is_symlink():
            raise ValueError('Source links are not supported')
        files[path.relative_to(root).as_posix()] = path.read_bytes()
    files['laning/profile.lua'] = profile_source(profile, revision)
    if profile == 'lane_probe':
        source = root / 'profiles/lane_probe' / PROBE_ENTRY
        below(source, root)
        files[PROBE_ENTRY] = source.read_bytes()
    return files


def build(profile, output, revision='uncommitted', root=ROOT):
    files = collect(profile, root, revision)
    controller, enabled = PROFILES[profile]
    manifest = {
        'format': 'midbot-bundle-1', 'version': 'v0.3.3', 'profile': profile,
        'controller': controller, 'runtime_enabled': enabled,
        'observer_enabled': not enabled, 'wards_enabled': profile == 'valve_wards',
        'source_revision': revision, 'revision_claim_verified_by_packager': False,
        'dota_execution_verified': False, 'clean_folder_install_required': True,
        'results_attribution': 'Valve movement/attacks + MIDBOT abilities/purchases'
        if not enabled else 'MIDBOT diagnostic runtime; not a full-match policy',
        'files_sha256': {name: sha(data) for name, data in sorted(files.items())},
    }
    readme = '''MIDBOT v0.3.3 / PROFILE: %s

Install the entire bots folder into game/dota/scripts/vscripts/bots.
IMPORTANT: replace the OLD bots folder, never overlay/extract over it.
An old root mode_laning_nevermore.lua would keep overriding Valve laning.
The installer in tools/package_bot.py --install performs a checked backup + replacement.
Start a NEW match after installation; hot reload is not a supported profile switch.

valve_play: native engine movement/attacks; custom abilities and purchases.
valve_wards: same baseline + opt-in in-range mid ward placement test.
lane_probe: existing diagnostic controller, one attack and a 600-second lane window.
This bundle does not fix extra bot slots or claim any measured LH/hit-rate result.
Game execution must be verified in the installed client.
''' % profile
    output = Path(output)
    if output.suffix.lower() != '.zip' or output.is_symlink():
        raise ValueError('Output must be a regular .zip path')
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(files.items()):
            archive.writestr('bots/' + name, data)
        archive.writestr('MANIFEST.json', json.dumps(manifest, ensure_ascii=False, indent=2))
        archive.writestr('INSTALL.txt', readme)
    verify(output)
    return manifest


def verify(path):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)) or archive.testzip() is not None:
            raise ValueError('Invalid archive entries/CRC')
        for name in names:
            rel = PurePosixPath(name)
            if rel.is_absolute() or '..' in rel.parts or '\\' in name or ':' in name:
                raise ValueError('Unsafe archive path')
        manifest = json.loads(archive.read('MANIFEST.json'))
        profile = manifest['profile']
        if profile not in PROFILES:
            raise ValueError('Unknown profile')
        controller, enabled = PROFILES[profile]
        if manifest['controller'] != controller or manifest['runtime_enabled'] is not enabled:
            raise ValueError('Profile metadata mismatch')
        if manifest.get('observer_enabled') is not (not enabled) or manifest.get('wards_enabled') is not (profile == 'valve_wards'):
            raise ValueError('Observer/ward profile mismatch')
        files = manifest['files_sha256']
        if set(names) != {'MANIFEST.json', 'INSTALL.txt'} | {'bots/' + n for n in files}:
            raise ValueError('Archive and manifest file sets differ')
        if not set(ROOT_LUA).issubset(files):
            raise ValueError('Missing hero/ability/purchase entry')
        if archive.read('bots/laning/profile.lua') != profile_source(profile, manifest['source_revision']):
            raise ValueError('Runtime profile mismatch')
        entries = {n for n in files if '/' not in n and (n.startswith('mode_') or n.startswith('bot_'))}
        if entries != ({PROBE_ENTRY} if enabled else set()):
            raise ValueError('Unexpected controller entrypoints')
        for name, expected in files.items():
            if sha(archive.read('bots/' + name)) != expected:
                raise ValueError('File hash mismatch: ' + name)
        return manifest


def install(archive_path, game_dir, check_running=True):
    manifest = verify(archive_path)
    game = Path(game_dir).absolute()
    if game.name.lower() != 'dota' or game.parent.name.lower() != 'game':
        raise ValueError('Expected the installed game/dota directory')
    if not (game.parent / 'bin/win64/dota2.exe').is_file():
        raise ValueError('Dota executable not found next to game/dota')
    if check_running and os.name == 'nt':
        tasks = subprocess.run(['tasklist', '/FI', 'IMAGENAME eq dota2.exe', '/FO', 'CSV', '/NH'],
                               capture_output=True, check=True).stdout.lower()
        if b'"dota2.exe"' in tasks:
            raise ValueError('Close Dota 2 before installing')
    parent = below(game / 'scripts/vscripts', game)
    target = below(parent / 'bots', game)
    # Reject links/junctions before any rename, including links within game/dota.
    for path in (game, game / 'scripts', parent, target):
        if path.is_symlink() or path.resolve() != path.absolute():
            raise ValueError('Linked installation paths are not supported')
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:8]
    stage = below(parent / ('.midbot-stage-' + stamp), game)
    backup = below(parent / ('bots.backup-' + stamp), game)
    if target.exists() and not target.is_dir():
        raise ValueError('bots must be a directory')
    if backup.exists() or stage.exists():
        raise ValueError('Installation staging/backup already exists')
    parent.mkdir(parents=True, exist_ok=True)
    stage.mkdir()
    with zipfile.ZipFile(archive_path) as archive:
        for name in manifest['files_sha256']:
            destination = below(stage / name, stage)
            destination.parent.mkdir(parents=True, exist_ok=True)
            data = archive.read('bots/' + name)
            destination.write_bytes(data)
            if sha(destination.read_bytes()) != manifest['files_sha256'][name]:
                raise ValueError('Staged verification failed')
    (stage / 'MIDBOT-INSTALL.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    had_previous = target.exists()
    def rename_checked(source, destination):
        below(source, game); below(destination, game)
        # Windows indexing/AV can briefly lock a just-written directory.
        for delay in (0.05, 0.1, 0.2, None):
            try:
                source.rename(destination)
                return
            except PermissionError:
                if delay is None:
                    raise
                time.sleep(delay)
    # Both resolved absolute rename targets have been checked within this game directory.
    if had_previous:
        rename_checked(target, backup)
    try:
        rename_checked(stage, target)
    except Exception:
        if had_previous:
            rename_checked(backup, target)
        raise
    return {'installed': str(target), 'profile': manifest['profile'],
            'previous_bots_backup': str(backup) if had_previous else None,
            'dota_execution_verified': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', choices=PROFILES, default='valve_play')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--revision', default='uncommitted')
    parser.add_argument('--install', type=Path, metavar='ZIP')
    parser.add_argument('--game-dir', type=Path)
    args = parser.parse_args()
    if args.install:
        if not args.game_dir or args.output:
            parser.error('--install requires --game-dir and cannot be combined with --output')
        print(json.dumps(install(args.install, args.game_dir), ensure_ascii=False))
    else:
        if not args.output or args.game_dir:
            parser.error('Building requires --output; --game-dir is only for --install')
        info = build(args.profile, args.output, args.revision)
        print(json.dumps({'archive': str(args.output), 'profile': info['profile'],
                          'files': len(info['files_sha256']), 'dota_execution_verified': False}))


if __name__ == '__main__':
    main()
