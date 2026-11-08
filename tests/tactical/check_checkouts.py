"""Feature and root-attachment verification with LF/CRLF; no game installation."""
from pathlib import Path
import shutil,subprocess,sys,tempfile

root=Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='.tactical-checkout-',dir=root) as directory:
    scratch=Path(directory);scratch.resolve().relative_to(root.resolve())
    for ending in ('LF','CRLF'):
        checkout=scratch/ending;checkout.mkdir()
        for folder in ('laning','tests/tactical','tools'):
            shutil.copytree(root/folder,checkout/folder,ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
        for p in checkout.rglob('*'):
            if p.is_file() and p.suffix in ('.lua','.py','.json'):
                b=p.read_bytes().replace(b'\r\n',b'\n');p.write_bytes(b if ending=='LF' else b.replace(b'\n',b'\r\n'))
        result=subprocess.run([sys.executable,'-X','utf8',str(checkout/'tests/tactical/run_tests.py')],capture_output=True,text=True,encoding='utf-8')
        if result.returncode: raise AssertionError(result.stdout+result.stderr)
        assert 'TACTICAL PASSED 82 cases' in result.stdout
        print(f'PASS {ending}:82 tactical cases')
    candidate=scratch/'candidate.lua'
    source=root/'tests/tactical/fixtures/ability_pr43_f605944.lua'
    before=source.read_bytes()
    result=subprocess.run([sys.executable,'-X','utf8',str(root/'tools/attach_tactical.py'),'--source',str(source),'--output',str(candidate)],capture_output=True,text=True,encoding='utf-8')
    if result.returncode:raise AssertionError(result.stderr)
    assert source.read_bytes()==before
    from lupa.lua51 import LuaRuntime
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute('assert(loadstring(...))',candidate.read_text(encoding='utf-8'))
    print('PASS generated attached current-owner candidate: Lua5.1 compile; original bytes preserved')
