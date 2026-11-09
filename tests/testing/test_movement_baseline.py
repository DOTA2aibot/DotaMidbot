"""Freeze the movement/vision subset Artem explicitly selected from installed v0312."""
from pathlib import Path
import hashlib, importlib.util, json, unittest

ROOT = Path(__file__).resolve().parents[2]
REFERENCE = json.loads(Path(__file__).with_name('installed_v0312_movement.json').read_text(encoding='utf-8'))
spec = importlib.util.spec_from_file_location('movement_package', ROOT/'tools/package_bot.py')
package = importlib.util.module_from_spec(spec); spec.loader.exec_module(package)


class MovementBaseline(unittest.TestCase):
    def test_requested_movement_and_ability_bytes_outside_authorised_ward_changes_are_preserved(self):
        files = package.collect('all_test', ROOT, 'baseline-check')
        self.assertEqual(REFERENCE['version'], 'v0.3.12-ward-recovery')
        for name, expected in REFERENCE['files_sha256'].items():
            # v0316 explicitly changes ward policy/purchases; the historical reference stays intact.
            if name.startswith('laning/vision/') or name in {'item_purchase_nevermore.lua', 'mode_ward_nevermore.lua', 'laning/tactical/wards.lua'}:
                continue
            with self.subTest(path=name):
                self.assertEqual(hashlib.sha256(files[name]).hexdigest(), expected)

    def test_courier_roam_experiment_is_absent_from_source_and_every_bundle(self):
        self.assertFalse((ROOT/'profiles/all_test/mode_roam_nevermore.lua').exists())
        self.assertFalse(list((ROOT/'laning/items').glob('delivery_guard*.lua')))
        for profile in package.PROFILES:
            files = package.collect(profile, ROOT, 'baseline-check')
            self.assertNotIn('mode_roam_nevermore.lua', files)
            self.assertFalse(any('delivery_guard' in n for n in files))
            self.assertNotIn(b'delivery_lane_guard', files['laning/profile.lua'])


if __name__ == '__main__':
    unittest.main()
