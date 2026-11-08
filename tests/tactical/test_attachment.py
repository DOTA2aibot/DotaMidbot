from pathlib import Path
import importlib.util
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('attach',ROOT/'tools/attach_tactical.py')
mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
SOURCE=(ROOT/'tests/tactical/fixtures/ability_pr43_f605944.lua').read_text(encoding='utf-8')
class Attachment(unittest.TestCase):
    def test_only_footer_added(self):
        result=mod.attach(SOURCE)
        self.assertEqual(result,SOURCE.rstrip()+'\n'+mod.FOOTER)
    def test_idempotent(self):
        result=mod.attach(SOURCE)
        self.assertEqual(mod.attach(result),result)
    def test_invalid_contract_rejected(self):
        with self.assertRaises(ValueError):mod.attach('function AbilityUsageThink() end')
    def test_script_environment_is_passed(self):
        self.assertIn('getfenv(1)',mod.FOOTER)
        self.assertNotIn('BindLegacy, _G',mod.FOOTER)
if __name__=='__main__':unittest.main()
