"""Run the exact A02 suites, preserving subprocess output and evidence."""
from pathlib import Path
import datetime
import json
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
GODOT = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe')
REPORT = ROOT / 'reports/refactoring'
LOGS = REPORT / 'headless-logs'

def _unique_fields(pairs):
    fields = {}
    for key, value in pairs:
        if key in fields:
            raise ValueError('duplicate RESULT field: ' + key)
        fields[key] = value
    return fields


def parse_result(line):
    """Parse JSON or JSON-valued key=value fields without guessing missing data."""
    payload = re.sub(r'^\s*RESULT\b\s*', '', line, count=1)
    decoder = json.JSONDecoder(object_pairs_hook=_unique_fields)
    if payload.startswith('{'):
        fields = decoder.decode(payload)
    else:
        pairs = []
        while payload:
            match = re.match(r'([A-Za-z_][A-Za-z_0-9]*)\s*=\s*', payload)
            if not match:
                raise ValueError('invalid key=value RESULT')
            value, end = decoder.raw_decode(payload[match.end():])
            pairs.append((match.group(1), value))
            tail = payload[match.end() + end:]
            if tail and not tail[0].isspace():
                raise ValueError('missing RESULT field separator')
            payload = tail.lstrip()
        fields = _unique_fields(pairs)
    if not isinstance(fields, dict) or type(fields.get('checks')) is not int or fields['checks'] < 0:
        raise ValueError('RESULT checks must be an explicit nonnegative integer')
    if not isinstance(fields.get('failures'), list):
        raise ValueError('RESULT failures must be an explicit array')
    return fields


def read_log(path):
    # Byte decoding retains CRLF; invalid UTF-8 must surface, never become U+FFFD.
    return Path(path).read_bytes().decode('utf-8')


def analyze_logs(stdout, stderr, *, exit_code, timed_out):
    """Judge recorded evidence, never infer an assertion count from exit status."""
    lines = stdout.splitlines() + stderr.splitlines()
    result_lines = [line for line in lines if re.match(r'^\s*RESULT\b', line)]
    check_lines = [line for line in lines if re.match(r'^\s*CHECK\b', line)]
    assertion_failures = [line for line in check_lines if re.search(r'\sfalse\s*$', line)]
    malformed_checks = [line for line in check_lines if not re.search(r'\s(?:true|false)\s*$', line)]
    errors = [line for line in lines if re.search(r'(SCRIPT ERROR|SHADER ERROR|^\s*ERROR:|^\s*FAIL\b)', line)]
    warnings = [line for line in lines if re.match(r'^\s*WARNING:', line)]
    parsed = []
    parse_errors = []
    reasons = []
    for line in result_lines:
        try:
            parsed.append(parse_result(line))
        except ValueError as exc:
            parse_errors.append({'line': line, 'error': str(exc)})
    if timed_out:
        reasons.append('timeout')
    if exit_code != 0:
        reasons.append('nonzero_exit')
    if not result_lines:
        reasons.append('missing_result')
    if len(result_lines) > 1:
        reasons.append('multiple_results')
    if parse_errors:
        reasons.append('invalid_result')
    if errors:
        reasons.append('engine_error')
    if assertion_failures:
        reasons.append('check_false')
    if malformed_checks:
        reasons.append('invalid_check')
    if any(item['failures'] for item in parsed):
        reasons.append('result_failures')
    checks = [item['checks'] for item in parsed]
    if check_lines and any(value != len(check_lines) for value in checks):
        reasons.append('check_count_mismatch')
    if assertion_failures and any(not item['failures'] for item in parsed):
        reasons.append('check_result_contradiction')
    return {'status': 'RED' if reasons else 'PASS', 'result_lines': result_lines,
            'parsed_results': parsed, 'checks': checks, 'observed_check_count': len(check_lines),
            'check_trace_present': bool(check_lines), 'assertion_failures': assertion_failures,
            'malformed_checks': malformed_checks, 'errors': errors, 'warnings': warnings,
            'result_parse_errors': parse_errors, 'failure_reasons': reasons}

def save(report):
    REPORT.mkdir(parents=True, exist_ok=True)
    (REPORT / 'baseline-headless.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    lines = ['A02 headless baseline', 'HEAD: ' + report['head'], 'Godot: ' + str(GODOT), 'Timeout: 180 seconds per suite', 'Only headless branches verified; window/input coverage not implied.', '']
    lines.append('Executed: %d / %d; PASS: %d; RED: %d' % (len(report['suites']), report['expected_count'], sum(x['status'] == 'PASS' for x in report['suites']), sum(x['status'] == 'RED' for x in report['suites'])))
    lines.append('Suite | Status | Exit | Timeout | RESULT checks | Observed CHECKs | Failure reasons')
    for item in report['suites']:
        lines.append('%s | %s | %s | %s | %s | %s | %s' % (item['suite'], item['status'], item['exit_code'], item['timed_out'], item['checks'], item.get('observed_check_count'), item.get('failure_reasons', [])))
    for key in ['verification', 'issues', 'diagnostics']:
        if key in report:
            lines.extend([key, json.dumps(report[key], ensure_ascii=False, indent=2)])
    for item in report['suites']:
        lines.extend(['== ' + item['suite'], json.dumps(item, ensure_ascii=False, indent=2), '--- FULL STDOUT ---', read_log(ROOT / item['stdout_log']), '--- FULL STDERR ---', read_log(ROOT / item['stderr_log']), ''])
    (REPORT / 'baseline-headless.txt').write_text('\n'.join(lines), encoding='utf-8', newline='')

def main():
    if not GODOT.is_file():
        raise FileNotFoundError(GODOT)
    plan = (ROOT / 'docs/refactoring-plan.md').read_text(encoding='utf-8')
    section = next(line for line in plan.splitlines() if '**A02**' in line)
    names = re.search(r'for s in (.*?); do', section).group(1).split()
    assert len(names) == 24 and len(set(names)) == 24, names
    for name in names:
        assert (ROOT / 'tests' / (name + '.tscn')).is_file(), name
    LOGS.mkdir(parents=True, exist_ok=True)
    report = {'task': 'A02', 'started_at': datetime.datetime.now().astimezone().isoformat(), 'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(), 'godot': str(GODOT), 'expected_count': 24, 'timeout_seconds': 180, 'suites': []}
    for name in names:
        cmd = [str(GODOT), '--headless', '--fixed-fps', '60', '--path', '.', '--scene', 'res://tests/' + name + '.tscn']
        out = LOGS / (name + '.stdout.log')
        err = LOGS / (name + '.stderr.log')
        started = time.monotonic()
        timed_out = False
        with out.open('wb') as stdout, err.open('wb') as stderr:
            proc = subprocess.Popen(cmd, cwd=ROOT, stdout=stdout, stderr=stderr)
            try:
                code = proc.wait(timeout=180)
            except subprocess.TimeoutExpired:
                timed_out = True
                subprocess.run(['taskkill', '/PID', str(proc.pid), '/T', '/F'], capture_output=True)
                proc.kill()
                code = proc.wait()
        evidence = analyze_logs(read_log(out), read_log(err), exit_code=code, timed_out=timed_out)
        item = {'suite': name, 'command': cmd, 'exit_code': code, 'timed_out': timed_out, 'duration_seconds': round(time.monotonic() - started, 3), **evidence, 'stdout_log': out.relative_to(ROOT).as_posix(), 'stderr_log': err.relative_to(ROOT).as_posix(), 'analysis': None}
        report['suites'].append(item)
        save(report)
        print(name, item['status'], 'exit=', code, 'timeout=', timed_out, item['result_lines'], item['failure_reasons'], flush=True)
    report['completed_at'] = datetime.datetime.now().astimezone().isoformat()
    report['actual_count'] = len(report['suites'])
    report['pass_count'] = sum(item['status'] == 'PASS' for item in report['suites'])
    report['red_count'] = sum(item['status'] == 'RED' for item in report['suites'])
    save(report)
    return 1 if report['red_count'] or report['actual_count'] != report['expected_count'] else 0

if __name__ == '__main__':
    raise SystemExit(main())
