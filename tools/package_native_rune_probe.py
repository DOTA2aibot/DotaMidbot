"""Separate diagnostic archive: no scripted rune mode, no dynamic nil fallback."""
from pathlib import Path
import argparse
import importlib.util
import json
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('probe_base_package', ROOT/'tools/package_bot.py')
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
PROFILE = 'native_rune_probe'
DISABLED_HELPER = b'''-- Diagnostic only: native rune controller owns all rune movement/pickup.
local M={};
function M.Decide() return nil,"native_rune_diagnostic" end;
function M.GetDesire() return 0 end;
function M.Think() end;
function M.Leave() end;
return M;
'''
README = '''Native rune diagnostic only; start a NEW local match.
Both mode_rune_nevermore.lua and mode_rune_generic.lua are absent.
The own rune helper has no orders. Valve controls rune choice, travel and pickup.
The custom 500 rule, bounty exclusion, retry budget and wrong-way guard do NOT apply.
Other bots may now take runes too. Keep the southern water rune for SF.
This profile does not force Valve to want a rune: no attempt is inconclusive.
Test until 4:30 with SF needing resources, ideally an empty Bottle.
Record whether SF actually walks to southern water and receives it.
Snapshot mode/action/position/Bottle are evidence; there are no own rune_order events.
Pressure, abilities, wards, PT/Wand and purchases remain from the test baseline.
Not a full-match or release candidate. Keep the previous archive for rollback.
'''


def collect(root=ROOT, revision='uncommitted'):
    if not re.fullmatch(r'[A-Za-z0-9._-]{1,80}', revision):
        raise ValueError('Invalid revision')
    files = base.collect('tower_pressure_test', root, revision)
    del files['mode_rune_nevermore.lua']
    del files['mode_rune_generic.lua']
    files['laning/profile.lua'] = files['laning/profile.lua'].replace(
        b'name = "tower_pressure_test"', b'name = "native_rune_probe"').replace(
        b'source_revision = ', b'native_rune_diagnostic = true, source_revision = ')
    files['laning/economy/runes.lua'] = DISABLED_HELPER
    return files


def verify(path):
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        if len(names) != len(set(names)) or z.testzip() is not None:
            raise ValueError('Invalid archive')
        m = json.loads(z.read('MANIFEST.json'))
        if m.get('format') != 'midbot-native-rune-probe-1' or m.get('profile') != PROFILE:
            raise ValueError('Not a native rune diagnostic')
        expected = collect(ROOT, m['source_revision'])
        if m['files_sha256'] != {n: base.sha(b) for n,b in sorted(expected.items())}:
            raise ValueError('Unexpected diagnostic runtime')
        if set(names) != {'MANIFEST.json','INSTALL.txt'} | {'bots/'+n for n in expected}:
            raise ValueError('Unexpected files or unsafe paths')
        if z.read('INSTALL.txt') != README.encode():
            raise ValueError('Missing diagnostic instructions')
        for n,b in expected.items():
            if z.read('bots/'+n) != b:
                raise ValueError('Runtime mismatch: '+n)
        return m


def build(output, revision='uncommitted'):
    output = Path(output)
    if output.suffix != '.zip' or output.is_symlink() or output.exists():
        raise ValueError('Expected a new regular ZIP path')
    files = collect(ROOT, revision)
    version = re.search(r'version\s*=\s*"([^"]+)"', (ROOT/'laning/observer/config.lua').read_text(encoding='utf-8')).group(1)
    m = dict(format='midbot-native-rune-probe-1', version=version, profile=PROFILE,
             source_revision=revision, controller='native_rune_diagnostic_with_midbot_pressure',
             own_rune_orders_enabled=False, native_rune_execution_verified=False,
             dota_execution_verified=False, clean_folder_install_required=True,
             files_sha256={n:base.sha(b) for n,b in sorted(files.items())})
    with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as z:
        for n,b in sorted(files.items()): z.writestr('bots/'+n,b)
        z.writestr('MANIFEST.json',json.dumps(m,indent=2))
        z.writestr('INSTALL.txt',README)
    verify(output)
    return m


def install(archive, game_dir):
    # Reuse only the checked staging/backup installer with this stricter validator.
    previous = base.verify
    base.verify = verify
    try:
        return base.install(archive, game_dir)
    finally:
        base.verify = previous


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--revision',default='uncommitted')
    args=parser.parse_args()
    print(json.dumps(build(args.output,args.revision)))
