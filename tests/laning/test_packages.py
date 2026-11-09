"""Real ZIP and directory replacement tests; never install into an actual Dota folder."""
from pathlib import Path
import importlib.util
import json
import tempfile
import unittest
from unittest import mock
import zipfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('midbot_packager', ROOT / 'tools/package_bot.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class Packages(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='.package-test-', dir=ROOT)
        self.scratch = Path(self.temp.name)
        self.scratch.resolve().relative_to(ROOT.resolve())
        self.addCleanup(self.temp.cleanup)

    def bundle(self, profile='valve_play'):
        path = self.scratch / (profile + '.zip')
        package.build(profile, path, 'test-fixture')
        return path

    def fake_game(self):
        game = self.scratch / 'client/game/dota'
        exe = game.parent / 'bin/win64/dota2.exe'
        exe.parent.mkdir(parents=True); exe.write_bytes(b'test placeholder, never executed')
        game.mkdir()
        return game

    def rewrite(self, archive_path, transform):
        with zipfile.ZipFile(archive_path) as z:
            content = {n: z.read(n) for n in z.namelist()}
        transform(content)
        with zipfile.ZipFile(archive_path, 'w') as z:
            for name, data in content.items():
                z.writestr(name, data)

    def test_source_tree_does_not_override_native_laning(self):
        self.assertFalse((ROOT / package.PROBE_ENTRY).exists())
        self.assertTrue((ROOT / 'profiles/lane_probe' / package.PROBE_ENTRY).is_file())

    def test_default_play_has_no_controller_entrypoints(self):
        path = self.bundle()
        info = package.verify(path)
        self.assertFalse(info['runtime_enabled'])
        self.assertEqual(info['controller'], 'valve_native')
        self.assertFalse(info['dota_execution_verified'])
        roots = {n for n in info['files_sha256'] if '/' not in n}
        self.assertEqual(roots, set(package.ROOT_LUA))

    def test_probe_has_the_explicit_entry_and_enabled_profile(self):
        path = self.bundle('lane_probe')
        info = package.verify(path)
        self.assertTrue(info['runtime_enabled'])
        with zipfile.ZipFile(path) as z:
            self.assertEqual(z.read('bots/' + package.PROBE_ENTRY),
                             (ROOT / 'profiles/lane_probe' / package.PROBE_ENTRY).read_bytes())

    def test_wards_are_an_explicit_profile_and_never_enable_lane_runtime(self):
        info = package.verify(self.bundle('valve_wards'))
        self.assertTrue(info['observer_enabled']); self.assertTrue(info['wards_enabled'])
        self.assertFalse(info['runtime_enabled']); self.assertNotIn(package.PROBE_ENTRY, info['files_sha256'])

    def test_default_play_keeps_ward_actions_disabled(self):
        info = package.verify(self.bundle())
        self.assertTrue(info['observer_enabled']); self.assertFalse(info['wards_enabled'])

    def test_economy_has_rune_and_ward_modes_and_keeps_native_lane(self):
        path = self.bundle('valve_lane_economy')
        info = package.verify(path)
        self.assertTrue(info['economy_enabled'])
        # T024 (Олег 08.11): economy-профиль теперь включает и установку вардов —
        # иначе купленные варды лежали мёртвым грузом.
        self.assertTrue(info['wards_enabled'])
        self.assertFalse(info['runtime_enabled'])
        self.assertEqual(info['controller'], 'valve_native_with_midbot_rune')
        roots = {n for n in info['files_sha256'] if '/' not in n}
        self.assertEqual(roots, set(package.ROOT_LUA) | {package.RUNE_ENTRY,package.WARD_ENTRY})
        with zipfile.ZipFile(path) as z:
            self.assertEqual(z.read('bots/' + package.RUNE_ENTRY),
                             (ROOT / 'profiles/lane_economy' / package.RUNE_ENTRY).read_bytes())

    def test_ordinary_play_and_wards_do_not_enable_economy(self):
        for profile in ('valve_play', 'valve_wards', 'lane_probe'):
            info = package.verify(self.bundle(profile))
            self.assertFalse(info['economy_enabled'])
            self.assertNotIn(package.RUNE_ENTRY, info['files_sha256'])

    def test_forged_economy_flag_is_rejected(self):
        path = self.bundle()
        def change(content):
            info = json.loads(content['MANIFEST.json'])
            info['economy_enabled'] = True
            content['MANIFEST.json'] = json.dumps(info).encode()
        self.rewrite(path, change)
        with self.assertRaisesRegex(ValueError, 'Economy profile mismatch'):
            package.verify(path)

    def test_previous_observer_bundle_format_remains_usable_for_rollback(self):
        path = self.bundle()
        def legacy(content):
            info = json.loads(content['MANIFEST.json'])
            info['version'] = 'v0.3.3'
            del info['economy_enabled']
            key = 'bots/laning/profile.lua'
            content[key] = content[key].replace(b'economy_enabled = false, ', b'')
            info['files_sha256']['laning/profile.lua'] = package.sha(content[key])
            content['MANIFEST.json'] = json.dumps(info).encode()
        self.rewrite(path, legacy)
        self.assertEqual(package.verify(path)['version'], 'v0.3.3')

    def test_install_replaces_stale_probe_and_preserves_backup(self):
        game = self.fake_game()
        old = game / 'scripts/vscripts/bots'
        old.mkdir(parents=True)
        (old / package.PROBE_ENTRY).write_text('old probe')
        (old / 'personal.lua').write_text('preserve in backup')
        result = package.install(self.bundle(), game, check_running=False)
        self.assertFalse((old / package.PROBE_ENTRY).exists())
        self.assertFalse((old / 'personal.lua').exists())
        backup = Path(result['previous_bots_backup'])
        backup.resolve().relative_to(game.resolve())
        self.assertEqual((backup / package.PROBE_ENTRY).read_text(), 'old probe')
        self.assertEqual((backup / 'personal.lua').read_text(), 'preserve in backup')
        self.assertEqual(json.loads((old / 'MIDBOT-INSTALL.json').read_text())['profile'], 'valve_play')

    def test_install_rejects_wrong_game_path_before_writes(self):
        path = self.bundle()
        wrong = self.scratch / 'wrong'
        with self.assertRaises(ValueError):
            package.install(path, wrong, check_running=False)
        self.assertFalse(wrong.exists())

    def test_failed_stage_rename_restores_the_previous_bots(self):
        game = self.fake_game()
        old = game / 'scripts/vscripts/bots'; old.mkdir(parents=True)
        (old / 'original.lua').write_text('original contents')
        archive = self.bundle()
        rename = Path.rename
        def fail_stage(path, destination):
            if path.name.startswith('.midbot-stage-'):
                raise OSError('simulated final rename failure')
            return rename(path, destination)
        with mock.patch.object(Path, 'rename', fail_stage):
            with self.assertRaisesRegex(OSError, 'simulated'):
                package.install(archive, game, check_running=False)
        self.assertEqual((old / 'original.lua').read_text(), 'original contents')

    def test_temporary_windows_rename_lock_is_retried_without_losing_backup(self):
        game = self.fake_game(); old = game / 'scripts/vscripts/bots'; old.mkdir(parents=True)
        (old / 'original.lua').write_text('preserved')
        archive = self.bundle(); rename = Path.rename; attempts = []
        def locked(path, destination):
            if path.name.startswith('.midbot-stage-'):
                attempts.append(path)
                if len(attempts) < 3:
                    raise PermissionError('temporary Windows lock')
            return rename(path, destination)
        with mock.patch.object(Path, 'rename', locked), mock.patch.object(package.time, 'sleep'):
            result = package.install(archive, game, check_running=False)
        self.assertEqual(len(attempts), 3)
        self.assertEqual((Path(result['previous_bots_backup']) / 'original.lua').read_text(), 'preserved')

    def test_unlisted_entry_is_rejected_before_install(self):
        path = self.bundle()
        self.rewrite(path, lambda d: d.update({'bots/mode_laning_nevermore.lua': b'stale'}))
        with self.assertRaisesRegex(ValueError, 'file sets differ'):
            package.verify(path)

    def test_profile_bytes_cannot_silently_enable_runtime_in_play(self):
        path = self.bundle()
        self.rewrite(path, lambda d: d.update({'bots/laning/profile.lua': package.profile_source('lane_probe')}))
        with self.assertRaisesRegex(ValueError, 'Runtime profile mismatch'):
            package.verify(path)

    def test_builder_rejects_an_overlaid_source_layout(self):
        source = self.scratch / 'source'; source.mkdir()
        (source / package.PROBE_ENTRY).write_text('stale root entry')
        with self.assertRaisesRegex(ValueError, 'Stale root controller'):
            package.collect('valve_play', source)


if __name__ == '__main__':
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(Packages)
    result = unittest.TextTestRunner(verbosity=1).run(suite)
    if not result.wasSuccessful():
        raise SystemExit(1)
    print(f'PACKAGES PASSED {result.testsRun} cases')
