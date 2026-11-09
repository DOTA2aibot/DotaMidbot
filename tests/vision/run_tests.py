from pathlib import Path
import os
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parents[2];os.chdir(ROOT)
lua=LuaRuntime(unpack_returned_tuples=True)
lua.globals().SCENARIO=lua.execute((ROOT/'tests/tactical/fixture.lua').read_text(encoding='utf-8'))
lua.globals().CURRENT_OWNER_SOURCE=str(ROOT/'ability_item_usage_nevermore.lua').replace('\\','/')
lua.execute((ROOT/'tests/vision/vision_test.lua').read_text(encoding='utf-8'))
lua.execute((ROOT/'tests/vision/phase_test.lua').read_text(encoding='utf-8'))
lua.execute((ROOT/'tests/vision/calibration_test.lua').read_text(encoding='utf-8'))
lua.execute((ROOT/'tests/vision/supply_delivery_test.lua').read_text(encoding='utf-8'))
lua.execute((ROOT/'tests/vision/recovery_test.lua').read_text(encoding='utf-8'))
for p in ROOT.rglob('*.lua'):lua.execute('assert(loadstring(...))',p.read_text(encoding='utf-8'))
print('VISION Lua5.1 compile passed')
