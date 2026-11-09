"""Keep the historical reference, test current packaging without freezing HEAD."""
from pathlib import Path
import hashlib,importlib.util,json,tempfile,unittest,zipfile
ROOT=Path(__file__).resolve().parents[2]
REFERENCE=json.loads(Path(__file__).with_name('installed_v036.json').read_text(encoding='utf-8'))
spec=importlib.util.spec_from_file_location('package_parity',ROOT/'tools/package_bot.py')
package=importlib.util.module_from_spec(spec);spec.loader.exec_module(package)

class PackageParity(unittest.TestCase):
    def test_historical_reference_remains_intact(self):
        # A historic checksum identifies that artifact; future HEAD may evolve.
        self.assertEqual(REFERENCE['version'],'v0.3.6-github')
        self.assertEqual(len(REFERENCE['files_sha256']),51)
        digest=hashlib.sha256(json.dumps(REFERENCE['files_sha256'],sort_keys=True).encode()).hexdigest()[:10]
        self.assertEqual(digest,REFERENCE['fingerprint'])
        self.assertEqual(digest,'4850e41a29')

    def test_new_revision_changes_only_generated_profile(self):
        before=package.collect('all_test',ROOT,'review-a')
        after=package.collect('all_test',ROOT,'review-b')
        self.assertEqual(set(before),set(after))
        self.assertEqual({n for n in before if before[n]!=after[n]},{'laning/profile.lua'})
        self.assertIn(b'helper.BindLegacy, getfenv(1)',after['ability_item_usage_nevermore.lua'])
        self.assertNotIn('mode_laning_nevermore.lua',after)
        self.assertIn('laning/vision/supply.lua',after)
        self.assertIn('laning/vision/inventory.lua',after)

    def test_current_archive_bytes_match_collected_source(self):
        with tempfile.TemporaryDirectory(prefix='.package-parity-',dir=ROOT) as folder:
            path=Path(folder)/'current.zip'
            manifest=package.build('all_test',path,'review-current',ROOT)
            self.assertEqual(package.verify(path),manifest)
            expected=package.collect('all_test',ROOT,'review-current')
            self.assertEqual(manifest['files_sha256'],{n:package.sha(b) for n,b in sorted(expected.items())})
            self.assertEqual(manifest['version'],'v0.3.17-sentry-test')
            self.assertTrue(manifest['economy_enabled']);self.assertFalse(manifest['runtime_enabled'])
            with zipfile.ZipFile(path) as archive:
                for name,data in expected.items():self.assertEqual(archive.read('bots/'+name),data,name)

if __name__=='__main__':unittest.main()
