from pathlib import Path
import os
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parents[2];os.chdir(ROOT)
lua=LuaRuntime(unpack_returned_tuples=True)
lua.globals().SCENARIO=lua.execute((ROOT/'tests/tactical/fixture.lua').read_text(encoding='utf-8'))
lua.globals().CURRENT_OWNER_SOURCE=str(ROOT/'ability_item_usage_nevermore.lua').replace('\\','/')
lua.execute((ROOT/'tests/testing/shop_tango_test.lua').read_text(encoding='utf-8'))
for path in ROOT.rglob('*.lua'):lua.execute('assert(loadstring(...))',path.read_text(encoding='utf-8'))
print('SHOP/TANGO Lua5.1 compile passed')
