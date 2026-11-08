from pathlib import Path
import os
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[2]
os.chdir(root)
lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().ECONOMY_REVIEW_SCENARIO = lua.execute((root / 'tests/economy/economy_test.lua').read_text(encoding='utf-8'))
lua.execute((root / 'tests/economy/review_test.lua').read_text(encoding='utf-8'))
