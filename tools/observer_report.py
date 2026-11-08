"""Extract only MIDBOT telemetry; suggestions are never counted as executed actions."""
from pathlib import Path
import argparse
from collections import Counter, defaultdict
import glob
import json
import math
import re

PREFIX = '[MIDBOT observe] '
LINE = re.compile(r'^(?:(?:\d{2}/\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)? )?\[VScript\] )?\[MIDBOT observe\] (.*)$')


def read_records(paths):
    records, malformed = [], 0
    for path in paths:
        with Path(path).open(encoding='utf-8', errors='replace') as stream:
            for line_number, line in enumerate(stream, 1):
                matched = LINE.match(line.rstrip('\r\n'))
                if not matched:
                    continue
                try:
                    record = json.loads(matched.group(1))
                    if record.get('schema') != 'midbot-observer-1' or not isinstance(record.get('data'), dict):
                        raise ValueError('unsupported record')
                    if not isinstance(record.get('kind'), str) or not isinstance(record.get('time'), (int, float)) or not math.isfinite(record['time']):
                        raise ValueError('invalid event fields')
                    if record['kind'] == 'snapshot' and not isinstance(record['data'].get('hero'), dict):
                        raise ValueError('invalid snapshot hero')
                    record = dict(record, source_file=Path(path).name, source_line=line_number)
                    records.append(record)
                except (ValueError, TypeError, AttributeError):
                    malformed += 1
    return records, malformed


def summarize(records, malformed=0):
    grouped = defaultdict(list)
    for record in records:
        grouped[(record['source_file'], record.get('run_id'))].append(record)
    runs = []
    for (filename, run_id), events in grouped.items():
        snapshots = [e for e in events if e['kind'] == 'snapshot']
        counts = Counter(e['kind'] for e in events)
        actions = Counter(e['data'].get('action', 'unknown') for e in events if e['kind'] == 'action_submitted')
        times = [e['time'] for e in snapshots if isinstance(e.get('time'), (int, float))]
        counters = {}
        for key in ('last_hits', 'denies', 'deaths', 'kills'):
            values = [e['data'].get('hero', {}).get(key) for e in snapshots]
            values = [x for x in values if isinstance(x, (int, float)) and not isinstance(x, bool)]
            counters[key] = {'first': values[0] if values else None, 'last': values[-1] if values else None,
                             'observed_positive_increments': sum(max(0, b-a) for a, b in zip(values, values[1:])) if values else None,
                             'counter_resets': sum(b < a for a, b in zip(values, values[1:]))}
        latest = snapshots[-1]['data'].get('hero', {}) if snapshots else {}
        runs.append({'file': filename, 'run_id': run_id, 'profile': events[0].get('profile'),
                     'controller': events[0].get('controller'), 'snapshots': len(snapshots),
                     'first_sample_time': min(times) if times else None, 'last_sample_time': max(times) if times else None,
                     'sample_gaps_over_2s': sum(b-a > 2 for a, b in zip(times, times[1:])),
                     'samples_after_10_minutes': sum(t >= 600 for t in times),
                     'counters': counters, 'events': dict(counts), 'submitted_actions': dict(actions),
                     'last_level': latest.get('level'), 'last_gold': latest.get('gold'), 'last_souls': latest.get('souls'),
                     'cast_hit_rate': None, 'per_action_kills': None, 'reward_labels': None,
                     'attribution': 'interval_counters_and_submissions_only'})
    return {'schema': 'midbot-observer-report-1', 'records': len(records), 'malformed_records': malformed,
            'telemetry_available': bool(records), 'runs': runs,
            'limits': ['Shadow decisions are suggestions, not actions.',
                       'Counters do not identify the action that caused a last-hit or kill.',
                       'Samples after 10:00 prove observation continuity, not successful gameplay.',
                       'Hit rate, native command ownership and performance overhead remain unmeasured.']}


def write_report(records, report, output):
    output = Path(output); output.mkdir(parents=True, exist_ok=True)
    (output / 'telemetry.jsonl').write_text(''.join(json.dumps(r, ensure_ascii=False) + '\n' for r in records), encoding='utf-8')
    (output / 'summary.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    lines = ['# Отчёт MIDBOT', '', f"Записей: {report['records']}; повреждённых: {report['malformed_records']}.", '']
    if not report['telemetry_available']:
        lines += ['В этом журнале нет данных нового наблюдателя. Статистика неизвестна, а не равна нулю.', '']
    for run in report['runs']:
        lines += [f"## {run['file']}", '', f"Профиль: {run['profile']}; контроллер: {run['controller']}.",
                  f"Снимков: {run['snapshots']}; время: {run['first_sample_time']}–{run['last_sample_time']}.", '',
                  '| Счётчик | Первый | Последний | Наблюдаемый прирост | Сбросы |',
                  '|---|---:|---:|---:|---:|']
        for key, value in run['counters'].items():
            fmt = lambda x: 'неизвестно' if x is None else str(x)
            lines.append('| ' + key + ' | ' + ' | '.join(fmt(value[k]) for k in
                         ('first', 'last', 'observed_positive_increments', 'counter_resets')) + ' |')
        lines += ['', 'Поданные собственные приказы: ' + json.dumps(run['submitted_actions'], ensure_ascii=False), '']
    lines += ['Точность койлов, награды и привязка убийства к конкретному действию этим отчётом не вычисляются.',
              'Рекомендации теневой политики не считаются исполненными. Продолжение записи после 10:00 не доказывает активную игру.', '']
    (output / 'REPORT.md').write_text('\n'.join(lines), encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('logs', nargs='+')
    parser.add_argument('--outdir', required=True, type=Path)
    args = parser.parse_args()
    paths = sorted({p for pattern in args.logs for p in glob.glob(pattern)})
    if not paths:
        parser.error('No matching log files')
    records, bad = read_records(paths)
    report = summarize(records, bad)
    write_report(records, report, args.outdir)
    print(json.dumps({'files': len(paths), 'telemetry_records': len(records), 'output': str(args.outdir)}))


if __name__ == '__main__':
    main()
