"""Run the isolated feature suite with LF and Windows CRLF sources."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='.kill-chat-checkouts-', dir=root) as directory:
    scratch = Path(directory)
    scratch.resolve().relative_to(root.resolve())
    for ending in ('LF', 'CRLF'):
        checkout = scratch / ending
        checkout.mkdir()
        shutil.copyfile(root / 'ability_item_usage_nevermore.lua', checkout / 'ability_item_usage_nevermore.lua')
        for folder in ('laning', 'tests/social'):
            shutil.copytree(root / folder, checkout / folder, ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
        for path in checkout.rglob('*'):
            if path.suffix in ('.lua', '.py'):
                data = path.read_bytes().replace(b'\r\n', b'\n')
                path.write_bytes(data if ending == 'LF' else data.replace(b'\n', b'\r\n'))
        result = subprocess.run([sys.executable, '-X', 'utf8', str(checkout / 'tests/social/run_tests.py')],
                                capture_output=True, text=True, encoding='utf-8')
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)
        assert 'KILL_CHAT PASSED 23 cases' in result.stdout
        print(f'PASS {ending}: 23 kill-chat cases')
