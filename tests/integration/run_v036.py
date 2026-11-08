from pathlib import Path
import os
from lupa.lua51 import LuaRuntime
root=Path(__file__).resolve().parents[2];os.chdir(root)
lua=LuaRuntime(unpack_returned_tuples=True)
lua.globals().ECON_CASE=lua.execute((root/'tests/economy/economy_test.lua').read_text(encoding='utf-8'))
lua.globals().TACTICAL_SCENARIO=lua.execute((root/'tests/tactical/fixture.lua').read_text(encoding='utf-8'))
lua.globals().CURRENT_OWNER_SOURCE=str(root/'ability_item_usage_nevermore.lua').replace('\\','/')
lua.execute((root/'tests/integration/v036_test.lua').read_text(encoding='utf-8'))
