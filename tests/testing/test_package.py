from pathlib import Path
import importlib.util,tempfile,unittest,zipfile
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('testing_package',ROOT/'tools/package_bot.py');p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
class ShopPackage(unittest.TestCase):
    def test_only_explicit_test_profile_contains_generic_purchase(self):
        for profile in p.PROFILES:
            files=p.collect(profile,ROOT,'test-shop')
            self.assertEqual('item_purchase_generic.lua' in files,profile=='all_test')
            self.assertEqual(b'ally_ward_free_shop = true' in files['laning/profile.lua'],profile=='all_test')
            self.assertIn('item_purchase_nevermore.lua',files)
    def test_test_archive_preserves_personal_sf_and_tango(self):
        with tempfile.TemporaryDirectory(prefix='.package-shop-',dir=ROOT) as d:
            path=Path(d)/'test.zip';m=p.build('all_test',path,'test-shop',ROOT);self.assertEqual(p.verify(path),m)
            with zipfile.ZipFile(path) as z:
                self.assertEqual(z.read('bots/item_purchase_nevermore.lua'),(ROOT/'item_purchase_nevermore.lua').read_bytes())
                self.assertIn('bots/laning/tactical/tango.lua',z.namelist())
                self.assertNotIn('bots/mode_laning_nevermore.lua',z.namelist())
if __name__=='__main__':unittest.main()
