"""Verify the current package contract of the installed runtime profile.

installed_v036.json is a HISTORICAL artifact: it pins the bytes of the runtime
installed for the v0.3.6 combined test (revision 4850e41a29, 51 files). The
source tree has legitimately evolved since (rune diagnostics, rune_distance,
mode_rune_generic), so current bytes no longer equal the historical reference
and must not be compared against it. Current-package checks below verify the
new contract explicitly, including the generic rune entry (T025).
"""
from pathlib import Path
import importlib.util
import json
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
# Historical reference, kept for provenance/auditing only — see module docstring.
REFERENCE = json.loads((Path(__file__).with_name('installed_v036.json')).read_text(encoding='utf-8'))
spec = importlib.util.spec_from_file_location('package_bot_parity', ROOT / 'tools/package_bot.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)

CURRENT_FILE_COUNT = 52  # all_test: 50 laning/root files + rune entry + generic rune entry


class PackageParity(unittest.TestCase):
    def test_current_package_contract(self):
        files = package.collect('all_test', ROOT, 'current-reviewed-commit')
        self.assertEqual(len(files), CURRENT_FILE_COUNT)
        # T025: generic rune silencer ships only in all_test, never in valve_lane_economy.
        self.assertIn('mode_rune_generic.lua', files)
        self.assertIn('mode_rune_nevermore.lua', files)
        self.assertNotIn('mode_laning_nevermore.lua', files)
        self.assertIn(b'current-reviewed-commit', files['laning/profile.lua'])
        economy_only = package.collect('valve_lane_economy', ROOT, 'current-reviewed-commit')
        self.assertNotIn('mode_rune_generic.lua', economy_only)
        self.assertIn('mode_rune_nevermore.lua', economy_only)

    def test_new_commit_changes_provenance_only(self):
        base = package.collect('all_test', ROOT, 'reviewed-commit-a')
        other = package.collect('all_test', ROOT, 'reviewed-commit-b')
        differing = {name for name in base if base[name] != other[name]}
        self.assertEqual(differing, {'laning/profile.lua'})
        self.assertIn(b'reviewed-commit-b', other['laning/profile.lua'])
        self.assertNotIn(b'helper.BindLegacy', other['laning/profile.lua'])
        self.assertIn(b'helper.BindLegacy, getfenv(1)', other['ability_item_usage_nevermore.lua'])
        self.assertNotIn('mode_laning_nevermore.lua', other)

    def test_packaged_archive_passes_verifier(self):
        with tempfile.TemporaryDirectory(prefix='.package-parity-', dir=ROOT) as folder:
            path = Path(folder) / 'integration.zip'
            manifest = package.build('all_test', path, 'new-reviewed-commit', ROOT)
            self.assertEqual(package.verify(path), manifest)
            self.assertEqual(manifest['version'], REFERENCE['version'])
            self.assertTrue(manifest['economy_enabled'])
            self.assertFalse(manifest['runtime_enabled'])
            self.assertEqual(len(manifest['files_sha256']), CURRENT_FILE_COUNT)


if __name__ == '__main__':
    unittest.main()
