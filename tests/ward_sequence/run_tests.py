from pathlib import Path
import os
from lupa.lua51 import LuaRuntime
R=Path(__file__).resolve().parents[2];os.chdir(R)
lua=LuaRuntime(unpack_returned_tuples=True)
lua.globals().SCENARIO=lua.execute((R/'tests/tactical/fixture.lua').read_text(encoding='utf-8'))
lua.execute((R/'tests/ward_sequence/sequence_test.lua').read_text(encoding='utf-8'))
for p in R.rglob('*.lua'):lua.execute('assert(loadstring(...))',p.read_text(encoding='utf-8'))
print('WARD_SEQUENCE Lua5.1 compile passed')
