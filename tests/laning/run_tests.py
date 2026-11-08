"""Offline tests against the real Lua 5.1 code; no Dota engine simulation claim."""
from pathlib import Path
import os, json, hashlib
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[2]
os.chdir(root)
lua = LuaRuntime(unpack_returned_tuples=True)
print('Runtime:', lua.eval('_VERSION'), flush=True)
def verify_pinned_lua(relative_path, expected):
    # Git's canonical text uses LF; an existing Windows checkout may use CRLF.
    # Normalize only that pair. BOMs, whitespace and real source edits still fail.
    data = (root / relative_path).read_bytes().replace(b'\r\n', b'\n')
    actual = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
    assert actual == expected, f'Pinned Lua fixture changed: {relative_path}: {actual} != {expected}'


verify_pinned_lua('tests/laning/audit_sources/t016_pr23_b0773c2.lua', '37a491daa059b083c577b723b704a9c7ed6cbed1')
verify_pinned_lua('tests/laning/audit_sources/t016_merged_f4bf3aa.lua', 'e1f605d27676528f25da72353d2d1f57babeec01')
for name in ['test_policy.lua', 'test_adapter.lua', 'advanced_test.lua', 'creeps_xp_tower_test.lua', 'runtime_test.lua']:
    p = root / 'tests/laning' / name
    lua.execute(p.read_text(encoding='utf-8'))
# Parse the nested plan/snapshot record, including stable numeric option IDs encoded as object keys.
sample = lua.globals().ADVANCED_RECORD_SAMPLE
assert sample, 'Advanced trace fixture was not produced'
if sample:
    record = json.loads(sample)
    assert record['reward_status'] == 'not_defined'
    assert len(record['action_masks']) == 25
    assert record['observation']['build'] == 'mock'
    assert record['candidate_plans'] and record['engine_event']['status'] == 'submitted'
    print('OPTIONS RECORD JSON PASSED 1 case', flush=True)
# Parse diagnostic output as actual JSON, not just string comparison.
captured = []
lua.globals().print = captured.append
lua.execute('Trace = dofile("laning/trace.lua")')
lua.execute('Trace.Emit({kind="attack", reason="last_hit", seq=1, hp_fraction=0.7, outcome_attribution="interval_only"})')
event = json.loads(captured[-1].split('] ', 1)[1])
assert event['outcome_attribution'] == 'interval_only' and event['seq'] == 1
lua.execute('Trace.Emit({text="quote: \\" slash: \\\\ newline: \\n", value=0/0})')
event = json.loads(captured[-1].split('] ', 1)[1])
assert event['value'] is None
print('TRACE JSON PASSED 2 cases')
