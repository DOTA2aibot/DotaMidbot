"""Regression: run the real suite with LF/CRLF files and reject edited fixtures.

No working-tree file is rewritten. Both checkouts live in TemporaryDirectory.
Run from any directory: python -X utf8 tests/laning/verify_checkouts.py
"""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]


def run(checkout):
    return subprocess.run(
        [sys.executable, '-X', 'utf8', str(checkout / 'tests/laning/run_tests.py')],
        cwd=checkout, capture_output=True, text=True, encoding='utf-8',
    )


with tempfile.TemporaryDirectory(prefix='.midbot-checkouts-', dir=root) as directory:
    # Keep scratch files in the writable checkout, including restricted Windows setups.
    Path(directory).resolve().relative_to(root.resolve())
    for ending in ('LF', 'CRLF'):
        checkout = Path(directory) / ending
        checkout.mkdir()
        for name in ('hero_selection.lua', 'ability_item_usage_nevermore.lua', 'item_purchase_nevermore.lua'):
            shutil.copyfile(root / name, checkout / name)
        for name in ('laning', 'tests/laning', 'tests/observer', 'tests/economy', 'tests/purchase', 'profiles', 'tools'):
            shutil.copytree(root / name, checkout / name,
                            ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
        for path in checkout.rglob('*'):
            if path.suffix not in ('.lua', '.py'):
                continue
            data = path.read_bytes().replace(b'\r\n', b'\n')
            path.write_bytes(data if ending == 'LF' else data.replace(b'\n', b'\r\n'))

        result = run(checkout)
        if result.returncode:
            raise AssertionError(f'{ending} suite failed:\n{result.stdout}\n{result.stderr}')
        print(f'PASS {ending}: full Lua/JSON suite', flush=True)

        # A comment is still a source change: newline tolerance must not unpin it.
        for name in ('t016_pr23_b0773c2.lua', 't016_merged_f4bf3aa.lua'):
            fixture = checkout / 'tests/laning/audit_sources' / name
            original = fixture.read_bytes()
            fixture.write_bytes(original + b'-- unexpected source edit\n')
            rejected = run(checkout)
            fixture.write_bytes(original)
            if rejected.returncode == 0 or 'Pinned Lua fixture changed' not in rejected.stderr or name not in rejected.stderr:
                raise AssertionError(f'{ending}: modified {name} was not rejected by its pin')
            print(f'PASS {ending}: edited {name} rejected', flush=True)
