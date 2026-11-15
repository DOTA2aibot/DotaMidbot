from pathlib import Path
import importlib.util
import tempfile
import unittest
import zipfile
from lupa.lua51 import LuaRuntime

R=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('native_probe',R/'tools/package_native_rune_probe.py')
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)

class NativeProbe(unittest.TestCase):
 def test_only_the_rune_entries_helper_and_profile_differ(self):
  normal=p.base.collect('tower_pressure_test',R,'test');probe=p.collect(R,'test')
  self.assertEqual(set(normal)-set(probe),{'mode_rune_nevermore.lua','mode_rune_generic.lua'})
  self.assertEqual(set(probe)-set(normal),set())
  self.assertEqual({n for n in probe if probe[n]!=normal[n]}, {'laning/profile.lua','laning/economy/runes.lua'})
  self.assertNotIn('bot_generic.lua',probe)
  self.assertIn('mode_watcher_nevermore.lua',probe)
 def test_disabled_helper_has_no_api_access_or_orders(self):
  lua=LuaRuntime(unpack_returned_tuples=True);lua.execute('GetBot=function() error("must not access bot API") end')
  helper=lua.execute(p.DISABLED_HELPER.decode())
  self.assertEqual(helper.GetDesire(),0)
  self.assertEqual(helper.Decide(),(None,"native_rune_diagnostic"))
  for _ in range(120):helper.Think();helper.Leave()
 def test_archive_rejects_old_generic_suppressor(self):
  with tempfile.TemporaryDirectory(dir=R) as d:
   archive=Path(d)/'native.zip';m=p.build(archive,'test');self.assertEqual(p.verify(archive),m)
   with zipfile.ZipFile(archive,'a') as z:z.writestr('bots/mode_rune_generic.lua','function GetDesire() return 0 end')
   with self.assertRaises(ValueError):p.verify(archive)

if __name__=='__main__':unittest.main()
