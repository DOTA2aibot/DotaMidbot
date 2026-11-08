"""Verify that committed source reproduces the installed v0.3.6 runtime.

The legacy revision is used only to compare historical profile bytes. A normal
build should supply its current commit SHA, which changes provenance alone.
"""
from pathlib import Path
import hashlib
import importlib.util
import json
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
REFERENCE = json.loads((Path(__file__).with_name('installed_v036.json')).read_text(encoding='utf-8'))
spec = importlib.util.spec_from_file_location('package_bot_parity', ROOT / 'tools/package_bot.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class PackageParity(unittest.TestCase):
    def test_historical_runtime_bytes(self):
        files = package.collect('all_test', ROOT, REFERENCE['revision'])
        actual = {name: package.sha(data) for name, data in sorted(files.items())}
        self.assertEqual(actual, REFERENCE['files_sha256'])
        self.assertEqual(len(files), 51)
        fingerprint = hashlib.sha256(json.dumps(actual, sort_keys=True).encode()).hexdigest()[:10]
        self.assertEqual(fingerprint, REFERENCE['fingerprint'])

    def test_new_commit_changes_provenance_only(self):
        files = package.collect('all_test', ROOT, 'new-reviewed-commit')
        for name, data in files.items():
            if name != 'laning/profile.lua':
                self.assertEqual(package.sha(data), REFERENCE['files_sha256'][name], name)
        self.assertIn(b'new-reviewed-commit', files['laning/profile.lua'])
        self.assertNotIn(b'helper.BindLegacy', files['laning/profile.lua'])
        self.assertIn(b'helper.BindLegacy, getfenv(1)', files['ability_item_usage_nevermore.lua'])
        self.assertNotIn('mode_laning_nevermore.lua', files)

    def test_packaged_archive_passes_verifier(self):
        with tempfile.TemporaryDirectory(prefix='.package-parity-', dir=ROOT) as folder:
            path = Path(folder) / 'integration.zip'
            manifest = package.build('all_test', path, 'new-reviewed-commit', ROOT)
            self.assertEqual(package.verify(path), manifest)
            self.assertEqual(manifest['version'], REFERENCE['version'])
            self.assertTrue(manifest['economy_enabled'])
            self.assertFalse(manifest['runtime_enabled'])
            self.assertEqual(len(manifest['files_sha256']), 51)


if __name__ == '__main__':
    unittest.main()
