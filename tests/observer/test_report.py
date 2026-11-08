from pathlib import Path
import importlib.util
import json
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('report', ROOT / 'tools/observer_report.py')
report = importlib.util.module_from_spec(spec); spec.loader.exec_module(report)


def event(kind, data, time=1, file='match1.log'):
    return {'kind': kind, 'data': data, 'time': time, 'run_id': 'run1', 'source_file': file,
            'profile': 'valve_play', 'controller': 'valve_native'}


class Report(unittest.TestCase):
    def test_empty_legacy_log_has_unknown_not_zero_statistics(self):
        result = report.summarize([])
        self.assertFalse(result['telemetry_available']); self.assertEqual(result['runs'], [])

    def test_shadow_decisions_do_not_become_submitted_actions(self):
        result = report.summarize([event('shadow_decision', {'selected': {'option_id': 2}})])
        self.assertEqual(result['runs'][0]['submitted_actions'], {})
        self.assertIsNone(result['runs'][0]['cast_hit_rate'])

    def test_counter_increase_and_reset_are_separate(self):
        records = [event('snapshot', {'hero': {'last_hits': value}}, i) for i, value in enumerate((10, 12, 3, 6))]
        counter = report.summarize(records)['runs'][0]['counters']['last_hits']
        self.assertEqual(counter['observed_positive_increments'], 5)
        self.assertEqual(counter['counter_resets'], 1)

    def test_same_run_id_in_different_files_is_not_combined(self):
        result = report.summarize([event('snapshot', {'hero': {}}, file='a.log'), event('snapshot', {'hero': {}}, file='b.log')])
        self.assertEqual(len(result['runs']), 2)

    def test_parser_and_export_filter_unrelated_log_lines(self):
        with tempfile.TemporaryDirectory(prefix='.report-test-', dir=ROOT) as directory:
            path = Path(directory); path.resolve().relative_to(ROOT.resolve())
            source = path / 'test.log'
            raw = {'schema': 'midbot-observer-1', 'kind': 'snapshot', 'time': 610, 'run_id': 'r', 'data': {'hero': {'last_hits': 8}}}
            source.write_text('private unrelated line\n[MIDBOT observe] broken\n[MIDBOT observe] ' + json.dumps(raw), encoding='utf-8')
            records, bad = report.read_records([source]); self.assertEqual(bad, 1); self.assertEqual(len(records), 1)
            result = report.summarize(records, bad); report.write_report(records, result, path / 'out')
            text = (path / 'out/telemetry.jsonl').read_text(encoding='utf-8')
            self.assertNotIn('private unrelated', text); self.assertEqual(json.loads(text)['data']['hero']['last_hits'], 8)
            self.assertEqual(result['runs'][0]['samples_after_10_minutes'], 1)

    def test_chat_lookalike_is_not_imported_as_telemetry(self):
        with tempfile.TemporaryDirectory(prefix='.report-test-', dir=ROOT) as directory:
            root = Path(directory); root.resolve().relative_to(ROOT.resolve())
            source = root / 'chat.log'
            data = {'schema': 'midbot-observer-1', 'kind': 'snapshot', 'time': 5, 'data': {'hero': {}}}
            source.write_text('11/08 05:00:00 [Chat] player: [MIDBOT observe] ' + json.dumps(data)
                              + '\n11/08 05:00:01 [VScript] [MIDBOT observe] ' + json.dumps(data), encoding='utf-8')
            records, bad = report.read_records([source]); self.assertEqual(len(records), 1); self.assertEqual(bad, 0)


if __name__ == '__main__':
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(Report)
    result = unittest.TextTestRunner().run(suite)
    if not result.wasSuccessful():
        raise SystemExit(1)
    print(f'REPORT PASSED {result.testsRun} cases')
