"""Run Lua 5.1 fixtures using optional lupa (development dependency only)."""
from pathlib import Path
import os
import sys
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[2]
source = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else None
os.chdir(root)
lua = LuaRuntime(unpack_returned_tuples=True)
if source:
    lua.globals().PURCHASE_SOURCE = str(source)
print('Runtime:', lua.eval('_VERSION'), flush=True)
lua.execute((root / 'tests/purchase/test_purchase.lua').read_text(encoding='utf-8'))
