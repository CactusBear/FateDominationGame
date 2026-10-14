"""Offline, read-only regression cost accounting. Never imports a runner or runs Godot."""
from __future__ import annotations
import argparse
from collections import Counter, defaultdict
import hashlib
import json
import math
from pathlib import Path
import re

ROOT = Path('E:/scratch')
R58 = ROOT / 'isolated-1105873e41cd4f6a94a999e65ac6af50'
R73 = ROOT / 'isolated-04d85ad08c0e44368a323e16e9b8ddc7'
DEFAULTS = [
    ('round58', R58 / 'pre-continuation-manifest.json'),
    ('round58', R58 / 'manifest.json'),
    ('round73', R73 / 'manifest.json'),
    ('round73', R73 / 'round73-continuation-manifest.json'),
    ('round73', R73 / 'round73-continuation-7d1e41e07ecf4ae0bfdeaef23f879593-manifest.json'),
    ('round71-specialist', ROOT / 'isolated-b3cc1bfe631149fa94f6a7c789f25491/manifest.json'),
    ('round71-specialist', ROOT / 'isolated-ed9fd487c32d490087e239301371f838/manifest.json'),
    ('round72-specialist', ROOT / 'round69-modal-hover-round72-current-final/isolated-1b8da5c153464e80aa535ecedfa7aa64/manifest.json'),
]


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def duration(value):
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
        raise ValueError(f'invalid duration: {value!r}')
    return float(value)


def scene_of(command):
    if '--scene' in command:
        i = command.index('--scene')
        if i + 1 < len(command):
            return command[i + 1]
    return None


def phase_of(label, command):
    if label == 'probe' or label.endswith('-probe'):
        return 'probe'
    if '--import' in command:
        return 'coldimport'
    if scene_of(command):
        return 'scene'
    return 'other_process'


def collect(inputs):
    """Deduplicate cumulative snapshots, not distinct repeated executions.

    Owner/run_id + PID + exact argv identifies one execution in this bounded
    archive corpus. Without PID use exact argv + label within manifest owner;
    this fallback is marked uncertain and never silently merges conflicts.
    """
    rows, sources, seen, links, stops = [], [], {}, [], []
    for cohort, path in inputs:
        path = Path(path)
        m = json.loads(path.read_text(encoding='utf-8'))
        sha = digest(path)
        sources.append({'kind': 'manifest', 'path': path.as_posix(), 'sha256': sha})
        owner = m.get('run_id') or m.get('generated') or path.parent.as_posix()
        continuation = m.get('continuation') or {}
        links.append({'manifest': path.as_posix(), 'owner': owner,
                      'parent_manifest': continuation.get('parent_manifest') or m.get('continuation_of'),
                      'parent_sha256': continuation.get('parent_manifest_sha256') or continuation.get('prior_manifest_sha256'),
                      'new_freeze': continuation.get('new_freeze'),
                      'import_repeated': continuation.get('import_repeated')})
        stops.append({'cohort': cohort, 'manifest': path.as_posix(), 'stage': m.get('stage'),
                      'error': m.get('error'), 'stop_reason': m.get('stop_reason'),
                      'first_failure': m.get('first_failure')})
        suite_rows = m.get('suites', []) + m.get('prerequisites', []) + m.get('required_harness_steps', [])
        by_command = {tuple(s.get('command', [])): s for s in suite_rows if s.get('command')}
        for n, p in enumerate(m.get('processes', [])):
            if p.get('pid') is not None and not (p.get('exited') is True and p.get('active_owned_processes') == 0):
                raise ValueError(f'not a completed Job: {path}:processes[{n}]')
            command = p.get('command', [])
            seconds = duration(p.get('duration_seconds'))
            pid = p.get('pid')
            key = (str(owner), pid, tuple(command)) if pid is not None else (str(owner), None, tuple(command), p.get('label'))
            s = by_command.get(tuple(command), {})
            row = {'cohort': cohort, 'owner': owner, 'pid': pid, 'label': p.get('label'),
                   'command': command, 'scene': scene_of(command), 'suite': s.get('suite'),
                   'phase': phase_of(p.get('label', ''), command), 'duration_seconds': seconds,
                   'duration_scope': 'executor launch through owned Job drain; not scene-only CPU/wall',
                   'duration_missing': seconds is None, 'identity_uncertain': pid is None,
                   'exit_code': p.get('exit_code'), 'budget_failure': p.get('budget_failure'),
                   'outcome': 'executor_safety_abort' if p.get('budget_failure') else 'natural_exit',
                   'business_passed': s.get('passed', s.get('analysis', {}).get('passed')),
                   'fixture_root': s.get('fixture_root'),
                   'evidence': [{'manifest': path.as_posix(), 'manifest_sha256': sha, 'process_index': n}]}
            if key in seen:
                old = seen[key]
                for field in ('label', 'duration_seconds', 'exit_code', 'budget_failure'):
                    if old[field] != row[field]:
                        raise ValueError(f'conflicting cumulative process: {key}: {field}')
                old['evidence'].extend(row['evidence'])
                if row['suite']:
                    old['suite'] = row['suite']
                continue
            seen[key] = row
            rows.append(row)
    return rows, sources, links, stops


def aggregate(rows):
    measured = [r for r in rows if r['duration_seconds'] is not None]
    phase = defaultdict(float)
    cohorts = defaultdict(lambda: {'processes': 0, 'seconds': 0.0, 'scene_processes': 0, 'safety_abort_seconds': 0.0})
    suites = defaultdict(float)
    for r in rows:
        seconds = r['duration_seconds'] or 0.0
        phase[r['phase']] += seconds
        c = cohorts[r['cohort']]
        c['processes'] += 1
        c['seconds'] += seconds
        c['scene_processes'] += r['phase'] == 'scene'
        if r['outcome'] == 'executor_safety_abort':
            c['safety_abort_seconds'] += seconds
        if r['scene']:
            suites[r['scene']] += seconds
    total = math.fsum(r['duration_seconds'] for r in measured)
    assert math.isclose(total, math.fsum(phase.values()), abs_tol=1e-7)
    prepare = Counter((r['cohort'], r['phase']) for r in rows if r['phase'] in ('probe', 'coldimport'))
    return {'unique_processes': len(rows), 'known_duration_processes': len(measured),
            'missing_duration_processes': len(rows) - len(measured), 'started_process_seconds': total,
            'phase_seconds': dict(phase), 'cohorts': dict(cohorts),
            'top10_suites': sorted(suites.items(), key=lambda p: (-p[1], p[0]))[:10],
            'preparation_counts': [{'cohort': c, 'phase': p, 'count': n, 'repeats_after_first': max(0, n-1)} for (c,p),n in sorted(prepare.items())],
            'parallel_classes': dict(Counter(r.get('parallel_class', 'unknown_serial') for r in rows))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    if out.drive.upper() != 'E:' or out.exists():
        raise ValueError('require a new self-owned E output directory')
    rows, sources, links, stops = collect(DEFAULTS)
    # User stopped further classification/benchmark work: preserve cost data only.
    data = {'schema': 'regression-cost-profile/v1', 'rows': rows, 'sourcehash': sources,
            'continuation_links': links, 'manifest_stops': stops,
            'summary': aggregate(rows),
            'unmeasured': ['scene_only_wall', 'Job_tail', 'copy', 'hash', 'archive', 'developer_edit_time']}
    out.mkdir(parents=True)
    for name, value in [('rows.json', rows), ('sourcehash.json', sources), ('profile.json', data)]:
        (out / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'output': out.as_posix(), 'summary': data['summary']}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
