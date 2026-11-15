from pathlib import Path
import importlib.util,tempfile,unittest,zipfile
R=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('pressure_package',R/'tools/package_bot.py');p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
class PressurePackage(unittest.TestCase):
 def test_only_the_opt_in_profile_replaces_roam_and_neutral_capture(self):
  for profile in p.PROFILES:
   files=p.collect(profile,R,'scope-test');active=profile=='tower_pressure_test'
   self.assertEqual('mode_roam_nevermore.lua' in files,active)
   self.assertEqual('mode_side_shop_nevermore.lua' in files,active)
   self.assertEqual('mode_watcher_nevermore.lua' in files,active)
   self.assertEqual(b'tower_pressure_enabled = true' in files['laning/profile.lua'],active)
   self.assertEqual(b'ignore_watchers = true' in files['laning/profile.lua'],active)
   self.assertNotIn('mode_attack_nevermore.lua',files)
   self.assertNotIn('mode_laning_nevermore.lua',files) if profile!='lane_probe' else None
 def test_experimental_archive_verifies_and_uses_actual_version(self):
  with tempfile.TemporaryDirectory(dir=R,prefix='.pressure-package-') as d:
   archive=Path(d)/'test.zip';m=p.build('tower_pressure_test',archive,'scope-test',R)
   self.assertEqual(p.verify(archive),m)
   self.assertEqual(m['version'],'v0.4.2-recovery-test')
   self.assertTrue(m['economy_enabled']);self.assertTrue(m['wards_enabled'])
   with zipfile.ZipFile(archive) as z:
    self.assertIn(b'Native ROAM ganks/objective trips are not available',z.read('INSTALL.txt'))
    self.assertIn(m['version'].encode(),z.read('INSTALL.txt'))
 def test_all_test_control_has_no_pressure_entrypoints(self):
  files=p.collect('all_test',R,'control')
  self.assertNotIn('mode_roam_nevermore.lua',files);self.assertNotIn('mode_side_shop_nevermore.lua',files)
  self.assertNotIn(b'tower_pressure_enabled = true',files['laning/profile.lua'])
if __name__=='__main__':unittest.main()
