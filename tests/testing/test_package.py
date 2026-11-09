from pathlib import Path
import importlib.util,tempfile,unittest,zipfile
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('testing_package',ROOT/'tools/package_bot.py');p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
class ShopPackage(unittest.TestCase):
    def test_ward_mode_and_flag_only_ship_in_explicit_ward_profiles(self):
        for profile in p.PROFILES:
            files=p.collect(profile,ROOT,'test-phase')
            self.assertEqual('mode_ward_nevermore.lua' in files,profile in p.WARD_PROFILES)
            self.assertEqual(b'ward_phase_enabled = true' in files['laning/profile.lua'],profile in p.WARD_PROFILES)
    def test_only_explicit_test_profile_contains_generic_purchase(self):
        for profile in p.PROFILES:
            files=p.collect(profile,ROOT,'test-shop')
            self.assertEqual('item_purchase_generic.lua' in files,profile=='all_test')
            self.assertEqual(b'ally_ward_free_shop = true' in files['laning/profile.lua'],profile=='all_test')
            self.assertIn('item_purchase_nevermore.lua',files)
            self.assertNotIn('mode_roam_nevermore.lua',files)
            self.assertNotIn(b'delivery_lane_guard = true',files['laning/profile.lua'])
            self.assertEqual('mode_item_nevermore.lua' in files,profile=='all_test')
            self.assertEqual(b'stationary_delivery_enabled = true' in files['laning/profile.lua'],profile=='all_test')
    def test_test_archive_preserves_personal_sf_and_tango(self):
        with tempfile.TemporaryDirectory(prefix='.package-shop-',dir=ROOT) as d:
            path=Path(d)/'test.zip';m=p.build('all_test',path,'test-shop',ROOT);self.assertEqual(p.verify(path),m)
            with zipfile.ZipFile(path) as z:
                self.assertEqual(z.read('bots/item_purchase_nevermore.lua'),(ROOT/'item_purchase_nevermore.lua').read_bytes())
                self.assertIn('bots/laning/tactical/tango.lua',z.namelist())
                self.assertNotIn('bots/mode_laning_nevermore.lua',z.namelist())
    def test_clean_install_removes_old_courier_roam_entry(self):
        with tempfile.TemporaryDirectory(prefix='.package-rollback-',dir=ROOT) as d:
            folder=Path(d);archive=folder/'new.zip';p.build('all_test',archive,'test-rollback',ROOT)
            game=folder/'client/game/dota';(game.parent/'bin/win64').mkdir(parents=True)
            (game.parent/'bin/win64/dota2.exe').write_bytes(b'not executed fixture')
            old=game/'scripts/vscripts/bots';old.mkdir(parents=True);(old/'mode_roam_nevermore.lua').write_text('old guard',encoding='utf-8')
            result=p.install(archive,game,check_running=False)
            self.assertFalse((old/'mode_roam_nevermore.lua').exists())
            self.assertTrue((Path(result['previous_bots_backup'])/'mode_roam_nevermore.lua').exists())
            self.assertIn(b'delivery_lane_guard = false', (old/'laning/profile.lua').read_bytes())
if __name__=='__main__':unittest.main()
