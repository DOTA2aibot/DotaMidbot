from pathlib import Path
import hashlib,json,os,sys
from lupa.lua51 import LuaRuntime
root=Path(__file__).resolve().parents[2];os.chdir(root)
pin=json.loads((root/'tests/tactical/BASE.json').read_text(encoding='utf-8'))
fixture=root/'tests/tactical/fixtures/ability_pr43_f605944.lua'
assert hashlib.sha256(fixture.read_bytes().replace(b'\r\n',b'\n')).hexdigest()==pin['fixture_sha256']
lua=LuaRuntime(unpack_returned_tuples=True)
if len(sys.argv)>1:
    lua.globals().CURRENT_OWNER_SOURCE=str(Path(sys.argv[1]).resolve()).replace('\\','/')
lua.globals().SCENARIO=lua.execute((root/'tests/tactical/fixture.lua').read_text(encoding='utf-8'))
lua.execute((root/'tests/tactical/test_tactical.lua').read_text(encoding='utf-8'))
for p in root.rglob('*.lua'):
    lua.execute('assert(loadstring(...))',p.read_text(encoding='utf-8'))
print('TACTICAL LUA51 compile and source pin PASSED',flush=True)
