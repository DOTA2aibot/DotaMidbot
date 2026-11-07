"""Run isolated reproductions against the saved PR21 head; never modifies PR source."""
from pathlib import Path
import os, hashlib
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[2]
os.chdir(root)
expected = {
    'ability_item_usage_nevermore.lua': 'b984c38cf1fb901399209f49ccab7899fe843aea',
    'item_purchase_nevermore.lua': '21012c5531fe1748c93294c131defcc05c721c69',
}
for name, blob in expected.items():
    data = (root / 'tests/laning/audit_sources' / name).read_bytes()
    actual = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
    assert actual == blob, f'PR21 source changed: {name}: {actual}'
print('PR21 head 5456b9e: saved source blobs verified', flush=True)
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute((root / 'tests/laning/release_audit.lua').read_text(encoding='utf-8'))
