from pathlib import Path
import json
import os
import subprocess
import sys
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[2]
os.chdir(root)
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute((root / 'tests/observer/observer_test.lua').read_text(encoding='utf-8'))
sample = json.loads(lua.globals().OBSERVER_SAMPLE_JSON)
assert sample['kind'] == 'snapshot' and sample['schema'] == 'midbot-observer-1'
assert sample['data']['hero']['last_hits'] == 2
assert sample['data']['attack_owner'] == 'native_or_unattributed'
print('OBSERVER JSON PASSED 1 case')
subprocess.run([sys.executable, '-X', 'utf8', str(root / 'tests/observer/test_report.py')], check=True)
