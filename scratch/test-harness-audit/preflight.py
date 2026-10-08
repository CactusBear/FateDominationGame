"""只读验收前置检查；绝不启动 Godot。所有结论只表示静态/日志证据。"""
import argparse
import ast
import json
import pathlib
import re
import subprocess

DEFAULT = pathlib.Path('E:/Projects/Godot/FateDominationGame-master')

def reconcile(text, exit_code):
    lines = [x for x in text.splitlines() if re.search(r'\bRESULT\b', x)]
    parsed = []
    for line in lines:
        body = line.split('RESULT', 1)[1].strip()
        checks = None
        count = None
        skip = bool(re.search(r'(?:window_only|external_pair_only|skipped)\s*[=:]\s*true', body, re.I))
        try:
            obj = json.loads(body)
            checks = obj.get('checks')
            value = obj.get('failures')
            count = len(value) if isinstance(value, list) else value if type(value) is int else None
            skip |= any(obj.get(k) is True for k in ('window_only', 'external_pair_only', 'skipped'))
        except (ValueError, AttributeError):
            m = re.search(r'checks\s*=\s*(\d+)', body)
            checks = int(m[1]) if m else None
            m = re.search(r'failures\s*=\s*(\d+)', body)
            if m:
                count = int(m[1])
            else:
                m = re.search(r'failures\s*=\s*(\[.*\])', body)
                if m:
                    try:
                        value = ast.literal_eval(m[1])
                        count = len(value) if isinstance(value, list) else None
                    except (ValueError, SyntaxError):
                        count = 0 if m[1].strip() == '[]' else 1
        parsed.append({'line': line, 'checks': checks, 'failure_count': count, 'skip': skip})
    errors = [x for x in text.splitlines() if re.search(r'SCRIPT ERROR|Parse Error|SHADER ERROR|\bERROR:', x)]
    failed = exit_code != 0 or bool(errors) or any(x['failure_count'] and x['failure_count'] > 0 for x in parsed)
    unknown = not parsed or any(x['failure_count'] is None for x in parsed)
    skipped = any(x['skip'] for x in parsed)
    status = 'FAIL' if failed else 'INCOMPLETE' if unknown else 'SKIP' if skipped else 'LOG_CLEAN_NOT_RUNTIME_VERIFIED'
    return {'exit': exit_code, 'status': status, 'results': parsed, 'error_count': len(errors), 'errors': errors, 'window_execution': 'UNPROVEN: require explicit branch marker/check-count comparison and source/command provenance'}

def git(project, *args, stdin=None):
    proc = subprocess.run(['git', *args], cwd=project, input=stdin.encode('utf-8') if stdin is not None else None, capture_output=True, timeout=20)
    if proc.returncode not in (0, 1):
        raise RuntimeError(proc.stderr.decode('utf-8', errors='replace'))
    return proc.stdout.decode('utf-8', errors='replace')

def script_chain(project, initial):
    chain, missing = [], []
    seen = set()
    current = initial
    while current and current not in seen:
        seen.add(current)
        file = project / current.removeprefix('res://')
        if not file.is_file():
            missing.append(current)
            break
        text = file.read_text(encoding='utf-8-sig')
        chain.append((current, text))
        match = re.search(r'^extends\s+"(res://[^\"]+)"', text, re.M)
        current = match[1] if match else None
    return chain, missing

def scan(project):
    scenes = sorted((project / 'tests').glob('*_test.tscn'))
    tracked = set(git(project, 'ls-files', 'tests').splitlines())
    paths = sorted(x.relative_to(project).as_posix() for x in (project / 'tests').rglob('*') if x.is_file() and x.suffix in ('.gd', '.tscn'))
    ignored = [x for x in git(project, 'check-ignore', '-z', '--stdin', stdin='\0'.join(paths) + '\0').split('\0') if x]
    rows = []
    for scene in scenes:
        text = scene.read_text(encoding='utf-8-sig')
        refs = re.findall(r'path="(res://[^\"]+)"', text)
        scripts = []
        for resource in re.findall(r'\[ext_resource\s+([^\]]+)\]', text):
            attributes = dict(re.findall(r'(\w+)="([^\"]*)"', resource))
            if attributes.get('type') == 'Script' and attributes.get('path', '').startswith('res://'):
                scripts.append(attributes['path'])
        chains = [script_chain(project, x) for x in scripts]
        sources = '\n'.join(t for chain, _ in chains for _, t in chain)
        missing = [x for x in refs if not (project / x.removeprefix('res://')).is_file()]
        missing += [x for _, absent in chains for x in absent]
        gate = bool(re.search(r'get_cmdline_user_args\(\).*has\("window"\)', sources))
        display = 'DisplayServer.get_name()' in sources
        reports = sorted(set(re.findall(r'res://(?:tests/)?runtime_reports', sources)))
        cmd = ['<console.exe>', '--fixed-fps', '60', '--path', str(project), '--scene', 'res://tests/' + scene.name]
        if not gate and not display:
            cmd.insert(1, '--headless')
        if gate:
            cmd += ['--', 'window']
        rows.append({'scene': scene.relative_to(project).as_posix(), 'tracked': scene.relative_to(project).as_posix() in tracked, 'scripts': [x for chain, _ in chains for x, _ in chain], 'missing_direct_resources': sorted(set(missing)), 'entry_hint': bool(re.search(r'func\s+_(?:ready|initialize)\(', sources)), 'watchdog_hint': bool(re.search(r'watchdog|time_limit|timeout_guard', sources, re.I)), 'window_user_arg': gate, 'display_gate_hint': display, 'result_hint': 'RESULT' in sources, 'quit_hint': 'quit(' in sources, 'report_roots': reports, 'proposed_command_not_executed': cmd})
    data = pathlib.Path('E:/Projects/Godot/FateDomination/test')
    junction = pathlib.Path('C:/Users/Administrator/AppData/Roaming/FateDomination')
    return {'scope': 'STATIC_ONLY; Godot never launched; source snapshot may change while other agents write', 'project': str(project), 'suite_count': len(rows), 'source_files': len(paths), 'ignored_untracked_sources': ignored, 'untracked_suite_count': sum(not x['tracked'] for x in rows), 'rows': rows, 'storage': {'expected': str(data), 'exists': data.is_dir(), 'compatibility_path': str(junction), 'resolved': str(junction.resolve()), 'target_matches': junction.exists() and junction.resolve() == data.resolve(), 'junction_hint': junction.is_junction() if hasattr(junction, 'is_junction') else None}, 'output_roots': {p: (project / p).is_dir() for p in ('runtime_reports', 'tests/runtime_reports')}, 'blocking_static': [x['scene'] for x in rows if x['missing_direct_resources'] or not x['entry_hint']]}

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--project', type=pathlib.Path, default=DEFAULT)
    ap.add_argument('--out', type=pathlib.Path, default=pathlib.Path(__file__).with_name('inventory.json'))
    ap.add_argument('--log', type=pathlib.Path)
    ap.add_argument('--exit-code', help='真实原始进程退出码或 TIMEOUT；禁止使用 grep 的退出码')
    args = ap.parse_args()
    if args.log:
        if args.exit_code is None:
            ap.error('--log 必须同时传 --exit-code')
        try:
            code = int(args.exit_code)
        except ValueError:
            code = args.exit_code
        result = reconcile(args.log.read_text(encoding='utf-8-sig', errors='replace'), code)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 1 if result['status'] in ('FAIL', 'INCOMPLETE', 'SKIP') else 0
    result = scan(args.project.resolve())
    # 输出必须限制在本代理拥有的 scratch 目录，防止误写生产路径。
    output = args.out.resolve()
    if not output.is_relative_to(pathlib.Path(__file__).resolve().parent):
        ap.error('--out 必须在 scratch/test-harness-audit 内')
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({k: v for k, v in result.items() if k not in ('rows', 'ignored_untracked_sources')}, ensure_ascii=False, indent=2))
    print('inventory:', output)
    return 2 if result['blocking_static'] or not result['storage']['target_matches'] else 0

if __name__ == '__main__':
    raise SystemExit(main())
