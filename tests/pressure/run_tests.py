from pathlib import Path
import os
from lupa.lua51 import LuaRuntime
R=Path(__file__).resolve().parents[2];os.chdir(R)
lua=LuaRuntime(unpack_returned_tuples=True)
lua.globals().SCENARIO=lua.execute((R/'tests/tactical/fixture.lua').read_text(encoding='utf-8'))
lua.execute((R/'tests/pressure/pressure_test.lua').read_text(encoding='utf-8'))
lua.execute((R/'tests/pressure/local_deward_test.lua').read_text(encoding='utf-8'))
