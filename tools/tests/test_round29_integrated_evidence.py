"""Round29 read-only production evidence collection; no game assertions rewritten."""
import sys
sys.dont_write_bytecode = True
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import time
import uuid

PROJECT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('isolated', PROJECT / 'tools/run_isolated_godot_test.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

scheduler_spec = importlib.util.spec_from_file_location(
    'regression_parallel_scheduler', PROJECT / 'tools/tests/regression_parallel_scheduler.py')
scheduler = importlib.util.module_from_spec(scheduler_spec)
scheduler_spec.loader.exec_module(scheduler)
# The existing async owned-process adapter is reused; it is not a scheduler.
parallel_adapter_spec = importlib.util.spec_from_file_location(
    'regression_parallel_smoke_adapter', PROJECT / 'tools/tests/regression_parallel_smoke.py')
parallel_adapter = importlib.util.module_from_spec(parallel_adapter_spec)
sys.modules.setdefault('regression_parallel_scheduler', scheduler)
parallel_adapter_spec.loader.exec_module(parallel_adapter)


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for block in iter(lambda: f.read(1048576), b''):
            h.update(block)
    return h.hexdigest()


EDITOR_VCS_TRANSFORM_AUTHORIZATION = {
    'scope': 'isolated_project_copy_only',
    'section': '[editor]',
    'fields': ['version_control/plugin_name', 'version_control/autoload_on_startup'],
    'reason': 'Disable development VCS autoload only in the isolated freeze before import.',
}


def _section_blocks(text):
    return re.split(r'(?m)^(?=\[[^\n]+\]\s*$)', text)


def transform_isolated_editor_vcs(text):
    """Transform only the explicitly authorized VCS fields in a frozen copy."""
    if not isinstance(text, str):
        raise TypeError('project.godot text required')
    blocks = _section_blocks(text)
    editor_indexes = [i for i, block in enumerate(blocks) if block.startswith('[editor]')]
    if len(editor_indexes) != 1:
        raise ValueError('exactly one [editor] section required')
    index = editor_indexes[0]
    editor = blocks[index]
    operations = []
    transformed_lines = []
    counts = {field: 0 for field in EDITOR_VCS_TRANSFORM_AUTHORIZATION['fields']}
    for line in editor.splitlines(keepends=True):
        stripped = line.strip()
        if stripped.startswith('version_control/plugin_name='):
            counts['version_control/plugin_name'] += 1
            operations.append({'field': 'version_control/plugin_name', 'action': 'remove',
                               'original': line.rstrip('\r\n'), 'transformed': None})
            continue
        if stripped.startswith('version_control/autoload_on_startup='):
            counts['version_control/autoload_on_startup'] += 1
            ending = line[len(line.rstrip('\r\n')):]
            prefix = line[:len(line) - len(line.lstrip())]
            new_line = prefix + 'version_control/autoload_on_startup=false' + ending
            operations.append({'field': 'version_control/autoload_on_startup', 'action': 'replace',
                               'original': line.rstrip('\r\n'), 'transformed': new_line.rstrip('\r\n')})
            transformed_lines.append(new_line)
            continue
        transformed_lines.append(line)
    for field, count in counts.items():
        if count != 1:
            raise ValueError('authorized editor field count for %s is %s' % (field, count))
    blocks[index] = ''.join(transformed_lines)
    transformed = ''.join(blocks)
    changed_sections = [name for name, before, after in zip(
        ('[editor]',), (editor,), (blocks[index],)) if before != after]
    if any(before != after for i, (before, after) in enumerate(zip(_section_blocks(text), blocks)) if i != index):
        raise ValueError('transformation changed a non-authorized project section')
    return transformed, {
        'scope': EDITOR_VCS_TRANSFORM_AUTHORIZATION['scope'],
        'authorized_section': EDITOR_VCS_TRANSFORM_AUTHORIZATION['section'],
        'authorized_fields': list(EDITOR_VCS_TRANSFORM_AUTHORIZATION['fields']),
        'reason': EDITOR_VCS_TRANSFORM_AUTHORIZATION['reason'],
        'operations': operations,
        'source_sha256': hashlib.sha256(text.encode('utf-8')).hexdigest(),
        'transformed_sha256': hashlib.sha256(transformed.encode('utf-8')).hexdigest(),
        'editor_before_sha256': hashlib.sha256(editor.encode('utf-8')).hexdigest(),
        'editor_after_sha256': hashlib.sha256(blocks[index].encode('utf-8')).hexdigest(),
        'changed_sections': changed_sections,
        'unauthorized_changes': [],
    }


def load(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'), object_pairs_hook=runner.unique_fields)


def save(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')


def parse(line):
    payload = re.sub(r'^\s*RESULT\b\s*', '', line, count=1)
    prefix = re.match(r'([A-Za-z_][\w.-]*)\s+(?=[A-Za-z_]\w*\s*=|\{)', payload)
    suite = prefix[1] if prefix else None
    if prefix:
        payload = payload[prefix.end():]
    decoder = json.JSONDecoder(object_pairs_hook=runner.unique_fields,
                               parse_constant=lambda x: (_ for _ in ()).throw(ValueError(x)))
    if payload.startswith('{'):
        result = decoder.decode(payload)
    else:
        pairs = []
        while payload:
            m = re.match(r'([A-Za-z_]\w*)\s*=\s*', payload)
            if not m:
                raise ValueError('invalid field')
            val, end = decoder.raw_decode(payload[m.end():])
            pairs.append((m[1], val))
            tail = payload[m.end() + end:]
            if tail and not tail[0].isspace():
                raise ValueError('separator missing')
            payload = tail.lstrip()
        result = runner.unique_fields(pairs)
    if suite is not None and ('suite' in result or 'suite_prefix' in result):
        raise ValueError('duplicate suite prefix field')
    if 'suite_prefix' in result:
        raise ValueError('reserved suite_prefix field')
    if not isinstance(result, dict) or type(result.get('checks')) is not int or result['checks'] <= 0:
        raise ValueError('missing/invalid positive checks')
    if 'failures' not in result and 'failed' not in result:
        raise ValueError('missing explicit failures/failed')
    if 'failures' in result and not (isinstance(result['failures'], list) or type(result['failures']) is int):
        raise ValueError('invalid failures')
    if 'failed' in result and (type(result['failed']) is not int or result['failed'] < 0):
        raise ValueError('invalid failed')
    if type(result.get('failures')) is int and result['failures'] < 0:
        raise ValueError('negative failures')
    return dict(result, suite_prefix=suite)


def analyze(out, err, code):
    lines = out.splitlines() + err.splitlines()
    results = [x for x in out.splitlines() if re.match(r'^\s*RESULT\b', x)]
    reasons = []
    result = None
    if code != 0:
        reasons.append('nonzero_exit')
    if len(results) != 1 or any(re.match(r'^\s*RESULT\b', x) for x in err.splitlines()):
        reasons.append('expected_one_stdout_result')
    else:
        try:
            result = parse(results[0])
            if result.get('failures') or result.get('failed'):
                reasons.append('result_failures')
        except ValueError as exc:
            reasons.append('invalid_result: ' + str(exc))
    errors = [x for x in lines if re.search(r'SCRIPT ERROR|SHADER ERROR|^\s*ERROR:|^\s*FAIL\b', x)]
    if errors:
        reasons.append('engine_or_assertion_error')
    checks = [x for x in lines if re.match(r'^\s*CHECK\b', x)]
    def check_value(line):
        leading = re.match(r'^\s*CHECK\s+(true|false)\s+\S', line)
        trailing = re.search(r'\s(true|false)\s*$', line)
        values = ([leading[1]] if leading else []) + ([trailing[1]] if trailing else [])
        return values[0] if values and len(set(values)) == 1 else None
    if any(check_value(x) is None for x in checks):
        reasons.append('malformed_check')
    if any(check_value(x) == 'false' for x in checks):
        reasons.append('false_check')
    ids = [m[1] for x in checks if (m := re.search(r'\b(?:id|check_id)=([A-Za-z0-9_-]+)\b', x))]
    if len(ids) != len(set(ids)):
        reasons.append('duplicate_explicit_check_id')
    # 每行是一次真实调用事件；同文案循环不是重复 RESULT。
    if checks and result and len(checks) != result['checks']:
        reasons.append('check_count_mismatch')
    return {'passed': not reasons, 'reasons': reasons, 'result': result,
            'result_lines': results, 'errors': errors,
            'raw_check_events': checks, 'observed_checks': len(checks)}


def summarize_current(m):
    """只聚合当前快照；历史审计另列，不静默隐藏拒绝原因。"""
    rows = m.get('suites',[])
    selected = m.get('selected_suites',[])
    reasons = []
    names = [r['suite'] for r in rows]
    if not selected or len(names) != len(set(names)) or set(names) != set(selected) or len(names) != len(selected):
        reasons.append('incomplete_or_duplicate_current_suites')
    if any(not r['passed'] for r in rows): reasons.append('current_suite_failure')
    if any(r.get('frozen_drift') for r in rows): reasons.append('frozen_drift')
    if any(r.get('parallel_drift') or r.get('current_vs_frozen') for r in rows): reasons.append('current_source_drift')
    if m.get('engine_source_unchanged') is False: reasons.append('source_engine_changed')
    if m.get('generated_exists_after_cleanup') is True: reasons.append('generated_cleanup_incomplete')
    if m.get('final_drift'): reasons.append('source_final_drift')
    if m.get('error'): reasons.append('execution_error')
    transform = m.get('editor_transform', {})
    if transform.get('verified') is not True: reasons.append('editor_transform_unverified')
    if transform.get('unauthorized_changes'): reasons.append('unauthorized_editor_transform')
    imported = m.get('import',{})
    if imported.get('exit') != 0: reasons.append('current_import_nonzero_or_missing')
    if imported.get('errors'): reasons.append('current_import_engine_errors')
    if m.get('cleanup','generated_removed') != 'generated_removed': reasons.append('cleanup_not_verified')
    return {'passed':not reasons,'reasons':reasons,'current_suite_count':len(rows),
            'current_suite_pass_count':sum(r['passed'] for r in rows),'import_errors':imported.get('errors',[])}


def summary_tests():
    clean = {'selected_suites':['a_test'],'suites':[{'suite':'a_test','passed':True,'frozen_drift':[]}],
             'import':{'exit':0,'errors':[]},'final_drift':[],'historical':{'passed':False},
             'editor_transform':{'verified':True,'unauthorized_changes':[]}}
    assert summarize_current(clean)['passed'], 'historical RED must not contaminate current freeze'
    for changes in [{'import':{'exit':0,'errors':['ERROR: Cannot get class GitPlugin']}},
                    {'import':{'exit':1,'errors':[]}}, {'final_drift':['x']},
                    {'suites':[]}, {'suites':[{'suite':'a_test','passed':False,'frozen_drift':[]}]}]:
        assert not summarize_current(dict(clean,**changes))['passed'], changes


def parser_tests():
    summary_tests()
    assert parse('RESULT activation checks=21 failures=[]')['checks'] == 21
    assert parse('RESULT active_choice checks=65 failed=0')['checks'] == 65
    assert parse('RESULT {"checks":1,"failures":[]}')['checks'] == 1
    assert analyze('CHECK true label\nRESULT checks=1 failures=[]', '', 0)['passed']
    repeated = analyze('CHECK a true\nCHECK a true\nRESULT checks=2 failed=0', '', 0)
    assert repeated['passed'] and repeated['observed_checks'] == 2, repeated
    assert not analyze('CHECK false label\nRESULT checks=1 failures=[]', '', 0)['passed']
    for line in ['RESULT checks=true failures=[]', 'RESULT checks=1.5 failures=[]',
                 'RESULT checks=1 checks=1 failures=[]', 'RESULT checks=1',
                 'RESULT checks=1 failures=false', 'RESULT checks=1 failed=false']:
        try:
            parse(line)
        except ValueError:
            pass
        else:
            raise AssertionError(line)
    assert not analyze('CHECK a true\nRESULT checks=1 failed=0','RESULT checks=1 failed=0',0)['passed']
    assert not analyze('CHECK true a false\nRESULT checks=1 failed=0','',0)['passed']
    for out in ['RESULT checks=1 failed=1', 'CHECK a false\nRESULT checks=1 failed=0',
                'CHECK a true\nCHECK a true\nRESULT checks=1 failed=0',
                'CHECK a true\nCHECK a false\nRESULT checks=2 failed=0',
                'CHECK a true\nRESULT checks=1 failed=0\nSCRIPT ERROR: test',
                'RESULT checks=1 failed=0\nRESULT checks=1 failed=0', '']:
        assert not analyze(out, '', 0)['passed']


VALIDATION20 = [
    'net_data_validation_test', 'net_validation_task_test', 'net_validation_simulation_test',
    'net_validation_hard_timeout_test', 'net_validation_io_feedback_test', 'net_validation_io_measure_test',
    'net_background_validation_feedback_test', 'net_parallel_validation_feedback_test',
    'net_server_discovery_validation_test', 'room_data_preparation_consumer_test',
    'room_data_preparation_dependencies_test', 'content_environment_test',
    'worker_content_environment_test', 'lobby_content_environment_restore_test',
    'net_data_sync_test', 'net_blob_test', 'net_blob_authorization_test',
    'net_blob_send_authorization_test', 'net_blob_concurrent_test', 'net_worker_startup_contract_test']
ROUND32_CURRENT_13 = [
    'net_validation_task_test', 'net_validation_simulation_test', 'net_validation_hard_timeout_test',
    'net_parallel_validation_feedback_test', 'room_data_preparation_consumer_test',
    'room_data_preparation_dependencies_test', 'lobby_content_environment_restore_test',
    'net_data_sync_test', 'net_blob_test', 'net_blob_authorization_test',
    'net_blob_send_authorization_test', 'net_blob_concurrent_test',
    'net_worker_startup_contract_test']
EXTRA = ['player_choice_source_command_test', 'client_identity_inbox_contract_test',
         'host_room_inbox_contract_test', 'net_selection_settings_test', 'net_runtime_guard_test',
         'net_resume_identity_test', 'gateway_deferred_test', 'gateway_disconnect_safe_close_test',
         'gateway_instance_binding_test', 'gateway_relisten_acceptance_test',
         'net_server_gateway_test', 'net_server_gateway_restart_test']


def historical(evidence):
    root = PROJECT / 'reports/refactoring/round28-D15'
    records = load(root / 'final-green.json')
    rows = []
    archive = evidence / 'round28-originals'
    archive.mkdir(exist_ok=True)
    for item in records:
        logs = [root / (item['name'] + '.' + role + '.log') for role in ('stdout', 'stderr')]
        out, err = [p.read_text(encoding='utf-8') for p in logs]
        row = {'name': item['name'], 'exit': item['exit'], **analyze(out, err, item['exit']),
               'logs': [{'path': str(p), 'sha256': digest(p)} for p in logs],
               'summary_result_matches': item['results'] == [x for x in out.splitlines() if x.startswith('RESULT')]}
        rows.append(row)
        for p in logs:
            shutil.copyfile(p, archive / p.name)
    for name in ('final-green.json', 'verification-final.json'):
        shutil.copyfile(root / name, archive / name)
    binding = load(root / 'verification-final.json')['hashes']
    for b in binding:
        b['current_sha256'] = digest(PROJECT / b['file'])
        b['current_matches_round28'] = b['current_sha256'] == b['frozen']
    f09 = []
    froot = Path('E:/Fate-F09-room-agent/reports')
    for name in ('green-final', 'F08', 'F06', 'F07', 'E07d', 'settings', 'guard', 'reconnect'):
        record = load(froot / (name + '.json'))
        log = Path(record['log'])
        text = log.read_text(encoding='utf-8')
        f09.append({'name': name, 'exit': record['exit'], 'log_sha256': digest(log),
                    'json_sha256': digest(froot / (name + '.json')), **analyze(text, '', record['exit'])})
        shutil.copyfile(log, archive / ('f09-' + log.name))
        shutil.copyfile(froot / (name + '.json'), archive / ('f09-' + name + '.json'))
    release = Path('E:/FateReleaseRound28')
    freeze = load(release / 'freeze-manifest-v3.json')
    source_hashes = freeze['source_files']
    target = Path(freeze['target'])
    comparisons = []
    for rel, expected in source_hashes.items():
        if rel.startswith(('scripts/', 'assets/scenes/')) or rel == 'project.godot':
            p = PROJECT / rel
            frozen = target / rel
            comparisons.append({'path': rel, 'round28_sha256': expected,
                'frozen_exists': frozen.is_file(),
                'frozen_matches': digest(frozen) == expected if frozen.is_file() else None,
                'current_sha256': digest(p) if p.is_file() else None,
                'current_matches': p.is_file() and digest(p) == expected})
    for name in ('freeze-manifest-v3.json', 'release-manifest-v3.json', 'final-candidate-audit.json', 'cleanup-evidence.json', 'round28-release-candidate.md'):
        shutil.copyfile(release / name, archive / ('release-' + name))
    package = release / 'candidate-package-v3'
    audit = load(release / 'final-candidate-audit.json')
    actual_pcks = [{'path': str(p), 'sha256': digest(p),
                    'matches_audit': digest(p) == audit['pck_index']['sha256']} for p in package.rglob('*.pck')]
    release_steps = []
    for i, step in enumerate(load(release / 'release-manifest-v3.json')['steps']):
        log = Path(step['log'])
        text = log.read_text(encoding='utf-8')
        release_steps.append({'exit': step['exit_code'], 'command': step['command'], 'log': str(log),
            'sha256': digest(log), 'errors': [x for x in text.splitlines() if re.search(r'SCRIPT ERROR|ERROR:', x)]})
        shutil.copyfile(log, archive / ('release-step-' + str(i) + '.log'))
    f09_bindings = []
    f09_report = (froot / 'round28-F09-room.md').read_text(encoding='utf-8')
    for rel, sha in re.findall(r'- ([\w/.-]+): `([a-f0-9]{64})`', f09_report):
        p = PROJECT / ('scripts/net/session/' + rel if rel in {'lobby_session.gd', 'host_room_inbox.gd'} else 'tests/' + rel)
        f09_bindings.append({'path': str(p), 'historical_sha256': sha, 'current_sha256': digest(p), 'matches': digest(p) == sha})
    shutil.copyfile(froot / 'round28-F09-room.md', archive / 'f09-report.md')
    return {'D15': {'suite_count': len(rows), 'check_total': sum(x['result']['checks'] for x in rows if x['result']),
        'strict_pass_count': sum(x['passed'] for x in rows), 'rows': rows, 'hash_binding': binding,
        'binding_limit': 'Only four post-run hashes retained; no full per-suite pre/post binding in round28.'},
        'F09': f09, 'F09_hash_bindings': f09_bindings, 'release': {'comparison': comparisons, 'pcks': actual_pcks,
        'steps': release_steps, 'pck_recheck_status': 'present_verified' if actual_pcks else 'ABSENT_RECYCLED_CANNOT_REVERIFY',
        'runtime_status': 'Static audit/export evidence does not certify runtime freeze.'}}


def snapshot_hashes(files, root):
    return {p.as_posix(): digest(root / p) if (root / p).is_file() else None for p in files}


ROUND33_EXTRA = [
    'host_guard_inbox_contract_test', 'net_guard_rollback_test',
    'rule_guard_root_transaction_v2_test', 'rule_guard_rollback_test',
    'rule_guard_chain_rollback_test', 'rule_guard_continuation_occurrence_test',
    'round29-shared-presentation_test', 'shared_spell_view_contract_test',
    'local_spell_restore_test', 'mirror_spell_negative_test',
    'match_view_test', 'match_view_privacy_test',
    'client_match_inbox_contract_test', 'gateway_bind_failure_test']
ROUND33_OLD_MANIFEST = Path('E:/scratch/isolated-58a7a37b252b4755a7a62919f6db433e/manifest.json')
ROUND33_SUPPLEMENT_MANIFEST = Path('E:/scratch/isolated-b4cf8faad56442b7af9fc7d50c6da696/manifest.json')


ROUND40_NEW = ['newspecial_spell_materialization_test', 'command_spell_source_activation_test',
               'round39_restore_transaction_test', 'assembly_publish_lifecycle_test']
ROUND40_GUI = ['local_spell_restore_test']
ROUND40_LONG = ['net_server_gateway_restart_test']
ROUND40_NEGATIVE = ['gateway_bind_failure_test']


def build_round40_selection(old):
    original = old['selected_suites']
    actual = [r['suite'] for r in old['suites']]
    if (len(original) != 66 or len(set(original)) != 66 or
            len(actual) != 66 or set(actual) != set(original)):
        raise ValueError('Round33 exact 66-name coverage required')
    names = list(dict.fromkeys(original + ROUND40_NEW))
    special = set(ROUND40_GUI + ROUND40_LONG + ROUND40_NEGATIVE)
    categories = {'pure_headless': [n for n in names if n not in special],
                  'gui_required': list(ROUND40_GUI), 'long_correctness': list(ROUND40_LONG),
                  'scoped_bind_negative': list(ROUND40_NEGATIVE)}
    red = [r['suite'] for r in old['suites'] if not r['passed']]
    focused = list(dict.fromkeys([n for n in red if n not in set(ROUND40_GUI + ROUND40_LONG)] +
                                ROUND40_NEW + ['gateway_relisten_acceptance_test',
                                'room_data_preparation_consumer_test', 'room_data_preparation_dependencies_test']))
    return {'names': names, 'original_count': len(original), 'selected_count': len(names),
            'categories': categories, 'focused': focused,
            'headless': [n for n in names if n not in ROUND40_GUI],
            'original_red': red, 'policy': 'One new freeze; GUI not skipped/PASS, long correctness runs once in complete phase.'}


def build_round41_selection(old):
    selection = build_round40_selection(old)
    reader = 'validation_checkpoint_reader_test'
    selection['names'].append(reader)
    selection['headless'].append(reader)
    selection['categories']['pure_headless'].append(reader)
    selection['selected_count'] = len(selection['names'])
    selection['focused'] = list(dict.fromkeys(['net_validation_hard_timeout_test', reader] + selection['focused']))
    selection['policy'] = 'One Round41 freeze; focused first red then all authorized runnable headless once; blocked output roots never executed/PASS.'
    return selection


def build_round42_selection(old):
    selection = build_round41_selection(old)
    assembly = 'assembly_publish_lifecycle_test'
    selection['focused'] = [assembly] + [n for n in selection['focused'] if n != assembly]
    selection['headless'] = [assembly] + [n for n in selection['headless'] if n != assembly]
    selection['policy'] = 'One Round42 freeze; whole-selection static preflight before suites, native66 first; complete only after unique fixture owners close output contracts.'
    return selection


def assembly_native_module():
    spec = importlib.util.spec_from_file_location('assembly_native', PROJECT/'tools/diagnostics/assembly_native_probe.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def round42_explicit_dependencies():
    return ['tests/isolated_fixture_root_contract_test.gd','tests/isolated_fixture_root_contract_test.tscn']


def round42_fixture_contracts(names, target, handoff=None):
    """Bind the delegated first-argument consumer to its completed unique owner's bytes."""
    report = Path(handoff) if handoff is not None else PROJECT/'docs/round42-explicit-fixture-roots.md'
    if not report.is_file():
        raise runner.SafetyError('explicit output fixture owner handoff not complete')
    text = report.read_text(encoding='utf-8')
    declared = dict((rel, sha) for sha, rel in re.findall(r'(?m)^([a-f0-9]{64})\s+(tests/[\w./-]+)$',text))
    consumers = {'lobby_content_environment_restore_test','net_blob_concurrent_test'} & set(names)
    required = ['tests/'+name+'.gd' for name in sorted(consumers)]
    if consumers:
        required += round42_explicit_dependencies()
    bindings = [{'path':rel,'owner_sha256':declared.get(rel),
                 'frozen_sha256':digest(Path(target)/rel) if (Path(target)/rel).is_file() else None} for rel in required]
    for binding in bindings:
        binding['matches_owner'] = bool(binding['owner_sha256'] and binding['owner_sha256']==binding['frozen_sha256'])
    blockers = [{'suite':name,'path':'tests/'+name+'.gd',
                 'reason':'delegated fixture consumer/helper bytes not bound to completed unique-owner handoff'}
                for name in sorted(consumers) if any(not x['matches_owner'] for x in bindings)]
    return {'blockers':blockers,'bindings':bindings,'handoff':str(report),'handoff_sha256':digest(report)}


def round42_static_preflight(selection, env, target=PROJECT):
    """One low-cost whole-selection gate; never discover missing probe after 15 suites."""
    import subprocess
    required = ['HERMES_ASSEMBLY_PROBE','HERMES_ASSEMBLY_PYTHON','HERMES_ASSEMBLY_SCOPE',
                'HERMES_ASSEMBLY_SCOPE_SHA256','HERMES_ASSEMBLY_TOKEN']
    if any(not env.get(key) for key in required):
        raise runner.SafetyError('explicit assembly probe/python/current scope environment missing')
    native = assembly_native_module()
    helper = native.safe(env['HERMES_ASSEMBLY_PROBE'])
    scope_path = native.safe(env['HERMES_ASSEMBLY_SCOPE'])
    if digest(scope_path) != env['HERMES_ASSEMBLY_SCOPE_SHA256']:
        raise runner.SafetyError('assembly scope hash mismatch')
    scope = load(scope_path)
    native.validate_paths(scope, env['HERMES_ASSEMBLY_TOKEN'], 'identity', [scope['fixture_root']])
    identity = native.process_identity(os.getpid())
    if scope['owner_pid'] != os.getpid() or scope['owner_creation'] != identity['creation']:
        raise runner.SafetyError('static preflight refuses foreign/stale scope owner')
    native.within(helper, scope['generated'])
    native.within(scope_path, scope['generated'])
    if digest(helper) != scope['helper_sha256'] or digest(PROJECT/'tools/diagnostics/assembly_native_probe.py') != scope['helper_sha256']:
        raise runner.SafetyError('frozen native helper drift')
    python = Path(env['HERMES_ASSEMBLY_PYTHON'])
    if not python.is_absolute() or not python.is_file():
        raise runner.SafetyError('explicit installed Python executable missing')
    check = subprocess.run([str(python), '-B', '-c', 'import ctypes,json,sys; print(sys.executable)'],
                           env=env, capture_output=True, text=True, timeout=15)
    if check.returncode or Path(check.stdout.strip()) != python:
        raise runner.SafetyError('assembly Python launch preflight rejected')
    contract = round42_fixture_contracts(selection['names'],target)
    blockers = contract['blockers']
    hashes = {}
    for name in selection['names']:
        for suffix in ['.gd','.tscn']:
            rel = 'tests/' + name + suffix
            path = Path(target)/rel
            if not path.is_file():
                raise runner.SafetyError('selected source missing before suites: ' + rel)
            hashes[rel] = digest(path)
    return {'passed':True,'probe_environment':{key:env[key] for key in required},
            'python_sha256':digest(python),'python_launch_exit':check.returncode,
            'helper_sha256':scope['helper_sha256'],'suite_source_hashes':hashes,
            'fixture_owner_contract':contract,
            'full_safety_blockers':blockers,'complete_allowed':not blockers,
            'policy':'Known output-owner blockers allow safe focused only; block entire complete phase, not partial full PASS.'}


def configure_assembly_scope(env, generated, fixtures, target, engine, token, archive, suffix='preflight'):
    """Immutable current UUID authorization; inherited unrelated probe keys are never trusted."""
    native = assembly_native_module()
    helper = generated/'assembly_native_probe.py'
    if not helper.exists():
        shutil.copyfile(PROJECT/'tools/diagnostics/assembly_native_probe.py', helper)
    owner = native.process_identity(os.getpid())
    scope = {'version':1,'run_id':token,'generated':generated.as_posix(),
             'fixture_root':fixtures.as_posix(),'source_root':(target/'data').as_posix(),
             'engine':engine.as_posix(),'engine_sha256':digest(engine),
             'owner_pid':os.getpid(),'owner_creation':owner['creation'],'helper_sha256':digest(helper)}
    path = generated/('assembly-scope-'+suffix+'.json')
    save(path,scope)
    dest = archive/'native-input'
    dest.mkdir(exist_ok=True)
    shutil.copyfile(path,dest/path.name)
    shutil.copyfile(helper,dest/helper.name)
    env.update(HERMES_ASSEMBLY_PROBE=helper.as_posix(),HERMES_ASSEMBLY_PYTHON=Path(sys.executable).as_posix(),
               HERMES_ASSEMBLY_SCOPE=path.as_posix(),HERMES_ASSEMBLY_TOKEN=token,
               HERMES_ASSEMBLY_SCOPE_SHA256=digest(path))
    return scope


def build_integrated_selection(old, supplement, extras):
    actual = [row['suite'] for row in old['suites']]
    if len(actual) != len(set(actual)) or not set(actual).issubset(old['selected_suites']):
        raise ValueError('duplicate/unselected historical suite')
    names = list(dict.fromkeys(actual + supplement['selected_suites'] + list(extras)))
    return {'names': names, 'old_actual_count': len(actual),
            'old_selected_count': len(old['selected_suites']),
            'supplement_count': len(supplement['selected_suites']),
            'selected_count': len(names),
            'missing_from_old_selection': [n for n in old['selected_suites'] if n not in names],
            'policy': 'Historical names only; every result is rerun in one new candidate freeze.'}


def analyze_integrated_suite(name, out, err, code, frozen_root, frozen_hashes):
    strict = analyze(out, err, code)
    row = dict(strict, strict_passed=strict['passed'], classification='positive')
    if name == 'gateway_relisten_acceptance_test':
        if (strict['result'] or {}).get('checks') != 38:
            row['passed'] = False
            row['reasons'] = strict['reasons'] + ['gateway_positive_expected_38_checks']
    if name != 'gateway_bind_failure_test':
        return row
    rel = 'tests/gateway_bind_failure_test.gd'
    source = Path(frozen_root) / rel
    expected = ["ERROR: Couldn't create an ENet host.",
                'at: _create (modules/enet/enet_connection.cpp:319)',
                'GDScript backtrace (most recent call first):',
                '[0] listen (res://scripts/net/transport/enet_transport.gd:44)',
                '[1] listen (res://scripts/net/server/server_gateway.gd:51)',
                '[2] run (res://tests/gateway_bind_failure_test.gd:13)']
    bound = bool(source.is_file() and digest(source) == frozen_hashes.get(rel)
                 and len(source.read_text(encoding='utf-8').splitlines()) >= 13
                 and source.read_text(encoding='utf-8').splitlines()[12].strip()
                 == 'var result:Error = gateway.listen(port,"127.0.0.1",root)')
    exact = [x.strip() for x in err.splitlines() if x.strip()] == expected
    protocol = analyze(out, '', code)
    permitted = bool(bound and exact and protocol['passed']
                     and (protocol['result'] or {}).get('checks') == 7
                     and protocol['observed_checks'] == 7)
    row.update(classification='scoped_bind_negative', passed=permitted,
               result=protocol['result'], reasons=[] if permitted else
               list(dict.fromkeys(strict['reasons'] + ['scoped_bind_negative_unverified'])),
               scoped_negative_error={'exact_stderr_matches':exact,
                   'frozen_source_hash_and_line13_match':bound,
                   'expected_checks':7, 'verified':permitted,
                   'strict_pass_preserved':strict['passed']})
    return row


def suite_command(engine, target, name, fixture_root):
    command = [str(engine), '--headless', '--fixed-fps', '60', '--path', str(target),
               '--scene', 'res://tests/' + name + '.tscn']
    if name in {'room_data_preparation_consumer_test', 'room_data_preparation_dependencies_test',
                'net_server_gateway_restart_test'}:
        command += ['--', Path(fixture_root).as_posix()]
    return command


def summarize_integrated(m):
    result = summarize_current(m)
    reasons = list(result['reasons'])
    probes = m.get('user_probes', [])
    if len(probes) != 2 or {p.get('role') for p in probes} != {'main','worker'}:
        reasons.append('main_worker_physical_probe_missing')
    elif any(p.get('worker_pool_max_threads') != 20 for p in probes):
        reasons.append('actual_worker_pool_not_20')
    processes = m.get('processes', [])
    if not processes or any(p.get('exited') is not True or p.get('active_owned_processes') != 0
                            or p.get('log_handles_released') is not True for p in processes):
        reasons.append('owned_process_exit_or_log_release_unverified')
    if m.get('selection_inputs_unchanged') is not True:
        reasons.append('historical_input_bytes_changed_or_unverified')
    rows = m.get('suites', [])
    names = [r['suite'] for r in rows]
    return dict(result, passed=not reasons, reasons=reasons,
                selected_count=len(m.get('selected_suites',[])), actual_count=len(rows),
                pass_count=sum(r['passed'] for r in rows),
                strict_pass_count=sum(r.get('strict_passed',r['passed']) for r in rows),
                checks_total=sum((r.get('result') or {}).get('checks',0) for r in rows),
                observed_check_total=sum(r.get('observed_checks',0) for r in rows),
                error_count=sum(len(r.get('errors',[])) for r in rows),
                missing=[n for n in m.get('selected_suites',[]) if n not in names],
                failed=[r['suite'] for r in rows if not r['passed']])


def finish_integrated(m, owner, evidence, report):
    m['selection_inputs_unchanged'] = all(digest(x['path']) == x['sha256'] for x in m['selection_inputs'])
    m['current_summary'] = summarize_integrated(m)
    m['passed'] = m['current_summary']['passed']
    m['claim'] = 'candidate_only_not_final_freeze'
    m['aggregator_sha256'] = digest(__file__)
    m['generic_runner_sha256'] = digest(PROJECT / 'tools/run_isolated_godot_test.py')
    archive = PROJECT / ('reports/refactoring/round33-integrated-' + m['run_id'])
    archive.mkdir(parents=True)
    shutil.copytree(evidence, archive / 'evidence')
    shutil.copyfile(__file__, archive / 'aggregator.py')
    shutil.copyfile(PROJECT / 'tools/tests/test_round33_integrated_selection.py', archive / 'selection-tests.py')
    m['archive'] = str(archive)
    m['archived_logs'] = [{'path':str(archive / 'evidence' / Path(x['path']).name),
                           'sha256':x['sha256'],'bytes':x['bytes']} for x in m['logs']]
    m['archive_log_hashes_verified'] = all(digest(x['path']) == x['sha256'] for x in m['archived_logs'])
    if not m['archive_log_hashes_verified']:
        m['passed'] = False
        m['current_summary']['passed'] = False
        m['current_summary']['reasons'].append('archive_log_hash_mismatch')
    save(owner / 'manifest.json', m)
    save(archive / 'manifest.json', m)
    s = m['current_summary']
    lines = ['# Round33 integrated candidate', '',
             '**同一候选副本串行整合；不宣称最终 freeze。top passed=%s。**' % str(m['passed']).lower(),
             'manifest：`%s`；独占所有权 manifest：`%s`。' % (archive / 'manifest.json',owner / 'manifest.json'),
             '执行命令：`python -B tools/tests/test_round29_integrated_evidence.py --round33`。',
             '全部真实 Godot headless、fixed-fps 60、每套180秒、Windows Job仅自有PID；没有窗口输入验收。', '',
             '## 选择与总计',
             '读取原39实际记录及原52 selected_suites，再与 round32 补13和实际存在的新场景去重；仅复用名字，旧结果不参与本次计数。',
             '选择=%s；执行=%s；专属判定通过=%s；严格零错误通过=%s；合法唯一 RESULT checks 合计=%s；原始 CHECK事件=%s；engine/assertion错误行=%s；import错误=%s。' %
             (s['selected_count'],s['actual_count'],s['pass_count'],s['strict_pass_count'],s['checks_total'],s['observed_check_total'],s['error_count'],len(s['import_errors'])),
             '缺套：`%s`；红项：`%s`；顶层拒绝原因：`%s`。' %
             (json.dumps(s['missing'],ensure_ascii=False),json.dumps(s['failed'],ensure_ascii=False),json.dumps(s['reasons'],ensure_ascii=False)),
             '双 RESULT 的套件不计入合法唯一 RESULT checks；其原始 RESULT 全文保留，未删除第二行或充抵通过数。',
             '选择清单：```json\n%s\n```' % json.dumps(m['selection'],ensure_ascii=False,indent=2), '',
             '## 隔离、导入与20线程',
             '真实 main/worker user://随机token、物理E路径、独立PID和child exit0已由verify_probe读回；原回执摘要在manifest。',
             '```json',json.dumps(m.get('user_probes',[]),ensure_ascii=False,indent=2),'```',
             'import exit=%s；errors=%s。' % (m.get('import',{}).get('exit'),json.dumps(m.get('import',{}).get('errors',[]),ensure_ascii=False)),
             '唯一副本转换仍限 `[editor]` 两项VCS字段；threading原文不变，实际主/worker worker_pool_max_threads均要求20。',
             '```json',json.dumps(m.get('editor_transform',{}),ensure_ascii=False,indent=2),'```', '',
             '## 正向38与独立bind负向7',
             'gateway_relisten_acceptance_test要求38 checks及全日志零错误。gateway_bind_failure_test单列，要求7 checks、精确六行stderr、冻结源码hash和第13行调用绑定；通用analyze仍拒绝这个原生ERROR。没有全局忽略。', '',
             '## F06 duplicate RESULT：唯一测试owner交接',
             '`tests/client_match_inbox_contract_test.gd` 正常成功路径第149行输出original阶段RESULT，await reconnect_contract后第151行再输出累计RESULT；不是引擎重复转发。',
             '交接唯一 test owner：F06 client inbox contract 写入者（由主代理路由）；整合代理仅保留冻结源码/日志，不修改该测试，也不放宽重复RESULT。另有status=GREEN/RED裸值不符合严格JSON值协议，需要同一owner同时处理，不能靠解析器放宽。', '',
             '## 全量suite结果', '|suite|exit|checks|CHECK事件|通过/分类|errors / reasons|', '|---|---:|---:|---:|---|---|']
    for row in m['suites']:
        lines.append('|%s|%s|%s|%s|%s / %s|%s|' % (row['suite'],row['exit'],
                     (row.get('result') or {}).get('checks'),row['observed_checks'],row['passed'],row.get('classification','execution_failure'),
                     '; '.join(row['errors']+row['reasons']+[row.get('execution_error','')]).replace('|','/')))
    lines += ['', '## 红项精确证据',]
    for row in m['suites']:
        if row['passed']:
            continue
        lines += ['### '+row['suite'], '实际命令：`'+json.dumps(row['command'],ensure_ascii=False)+'`',
                  'RESULT：```text\n'+'\n'.join(row['result_lines'])+'\n```',
                  '错误：```text\n'+'\n'.join(row['errors'])+'\n```',
                  '冻结失败目标源码：`evidence/failed-source/'+row['suite']+'.gd`；完整日志：`evidence/'+row['suite']+'.stdout.log` / stderr.log。']
    lines += ['', '## 漂移与回收',
              '源码最终相对候选漂移：`'+json.dumps(m.get('final_drift',[]),ensure_ascii=False)+'`。',
              '源码套件期间并行漂移：`'+json.dumps([(r['suite'],r['parallel_drift']) for r in m['suites'] if r.get('parallel_drift')],ensure_ascii=False)+'`。',
              '冻结副本漂移：`'+json.dumps([(r['suite'],r['frozen_drift']) for r in m['suites'] if r.get('frozen_drift')],ensure_ascii=False)+'`。',
              '并行UI/mirror修改不会回灌候选；后续源树不是这个版本。只记录candidate，不拼39+13不同版本或反复整批重跑。',
              '清理=%s；generated存在=%s；源Godot hash未变=%s；自有全部进程退出/日志释放=%s。' %
              (m['cleanup'],m.get('generated_exists_after_cleanup'),m.get('engine_source_unchanged'),
               all(p.get('exited') and p.get('active_owned_processes') == 0 and p.get('log_handles_released') for p in m['processes'])),
              'archive日志摘要读回一致=%s；两份旧manifest字节未变=%s。大副本（E引擎/项目/import缓存/APPDATA）已按自有生成树回收，保留最小原始证据。' %
              (m['archive_log_hashes_verified'],m['selection_inputs_unchanged']),
              '未改generic runner、production、游戏tests或旧证据；未git add/commit。']
    report.write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print(json.dumps({'manifest':str(archive/'manifest.json'),'report':str(report),
                      'cleanup':m['cleanup'],**s},ensure_ascii=False),flush=True)


def run():
    parser_tests()
    integrated = '--round33' in sys.argv
    selection = None
    selection_inputs = []
    names = list(ROUND32_CURRENT_13)
    if integrated:
        selection_inputs = [{'path':str(p),'sha256':digest(p)} for p in
                            [ROUND33_OLD_MANIFEST, ROUND33_SUPPLEMENT_MANIFEST]]
        selection = build_integrated_selection(load(ROUND33_OLD_MANIFEST),
                                               load(ROUND33_SUPPLEMENT_MANIFEST), ROUND33_EXTRA)
        names = selection['names']
        if selection['missing_from_old_selection']:
            raise runner.SafetyError('old selection coverage missing: ' + str(selection))
        for name in names:
            for suffix in ('.gd', '.tscn'):
                if not (PROJECT / ('tests/' + name + suffix)).is_file():
                    raise runner.SafetyError('selected scene/script missing: ' + name + suffix)
        print(json.dumps({'selection':selection,'inputs':selection_inputs},ensure_ascii=False),flush=True)
    root = runner.physical_e('E:/scratch')
    token = uuid.uuid4().hex
    owner = root / ('isolated-' + token)
    owner.mkdir()
    generated = owner / 'generated'
    evidence = owner / 'evidence'
    generated.mkdir()
    evidence.mkdir()
    m = {'run_id': token, 'generated': str(generated), 'processes': [], 'suites': [],
         'source_files': [], 'cleanup': 'not_started',
         'selection_policy': 'Exactly the current Round31 13-suite list; no historical suites are merged.',
         'selected_suites': names}
    if integrated:
        m.update(round=33, status='integrated_candidate_not_final_freeze',
                 selection_policy=selection['policy'], selection=selection,
                 selection_inputs=selection_inputs)
    budgets = {'seconds': 180, 'bytes': 3221225472, 'min_free': 1073741824}
    env = os.environ.copy()
    for key, sub in [('APPDATA', 'appdata'), ('LOCALAPPDATA', 'localappdata')]:
        (generated / sub).mkdir()
        env[key] = str(generated / sub)
    (generated / 'localappdata/hermes/cache/scratch').mkdir(parents=True, exist_ok=True)
    fixture_root = generated / 'fixtures'
    fixture_root.mkdir()
    env['FATE_TEST_SCRATCH_ROOT'] = fixture_root.as_posix()
    env.pop('HERMES_RECOVERY_VALIDATION_ROOT', None)
    source_engine = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe')
    engine = generated / 'Godot.exe'
    report = PROJECT / ('docs/round33-integrated-candidate.md' if integrated else 'docs/round32-clean-import-regression.md')
    try:
        if '--suites' in sys.argv:
            requested = sys.argv[sys.argv.index('--suites') + 1].split(',')
            if requested != names:
                raise runner.SafetyError('requires the exact explicit selection')
        m['selected_suites'] = names
        includes = ['project.godot', 'scripts', 'assets', 'data', 'game_data', 'addons', 'json_maker', 'icon.svg']
        for name in names:
            includes.extend(['tests/' + name + '.gd', 'tests/' + name + '.tscn'])
        files = runner.source_files(PROJECT, includes)
        # Resolve only explicitly referenced test dependencies, never copy all tests.
        selected = set(files)
        pending = list(files)
        while pending:
            rel = pending.pop()
            if rel.suffix not in {'.gd', '.tscn', '.tres', '.godot'}:
                continue
            for ref in re.findall(r'res://(tests/[^\s\"\'<>]+)', (PROJECT / rel).read_text(encoding='utf-8-sig')):
                dep = Path(ref)
                if (PROJECT / dep).is_file() and dep not in selected:
                    runner.contained(PROJECT / dep, PROJECT)
                    selected.add(dep)
                    pending.append(dep)
        files = sorted(selected)
        m['freeze_before'] = snapshot_hashes(files, PROJECT)
        target = generated / 'project'
        target.mkdir()
        for rel in files:
            dest = target / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(PROJECT / rel, dest)
            if digest(dest) != m['freeze_before'][rel.as_posix()]:
                raise runner.SafetyError('source drift during copy: ' + str(rel))
        m['freeze_after'] = snapshot_hashes(files, PROJECT)
        if m['freeze_before'] != m['freeze_after']:
            raise runner.SafetyError('source drift across freeze')
        m['source_files'] = [{'path': str(p), 'sha256': m['freeze_before'][p.as_posix()]} for p in files]
        config_path = target / 'project.godot'
        frozen_before_config_sha256 = digest(config_path)
        source_config_sha256 = m['freeze_before']['project.godot']
        if frozen_before_config_sha256 != source_config_sha256:
            raise runner.SafetyError('project.godot freeze hash mismatch before authorized transform')
        config_before = config_path.read_text(encoding='utf-8-sig')
        transformed_config, transform = transform_isolated_editor_vcs(config_before)
        with config_path.open('w', encoding='utf-8', newline='') as stream:
            stream.write(transformed_config)
        frozen_after_config_sha256 = digest(config_path)
        transform.update({
            'path': 'project.godot',
            'source_file_sha256': source_config_sha256,
            'frozen_before_sha256': frozen_before_config_sha256,
            'frozen_after_sha256': frozen_after_config_sha256,
            'authorized_paths': ['project.godot'],
            'source_unchanged_after_transform': digest(PROJECT / 'project.godot') == source_config_sha256,
        })
        threading_before = re.search(r'^\[threading\]\s*\n(.*?)(?=^\[|\Z)', config_before, re.M | re.S)
        threading_after = re.search(r'^\[threading\]\s*\n(.*?)(?=^\[|\Z)', transformed_config, re.M | re.S)
        transform['threading_before'] = threading_before[0] if threading_before else None
        transform['threading_after'] = threading_after[0] if threading_after else None
        transform['threading_unchanged'] = bool(threading_before and threading_after and threading_before[0] == threading_after[0])
        transform['worker_pool_max_threads_20'] = bool(threading_after and re.search(r'(?m)^worker_pool/max_threads=20\s*$', threading_after[1]))
        transform['verified'] = bool(
            transform['source_unchanged_after_transform'] and
            transform['changed_sections'] == ['[editor]'] and
            transform['unauthorized_changes'] == [] and
            transform['threading_unchanged'] and
            transform['worker_pool_max_threads_20'] and
            frozen_after_config_sha256 == transform['transformed_sha256']
        )
        m['editor_transform'] = transform
        frozen_hashes_after_transform = snapshot_hashes(files, target)
        source_vs_frozen = [p.as_posix() for p in files
                            if m['freeze_before'][p.as_posix()] != frozen_hashes_after_transform[p.as_posix()]]
        if source_vs_frozen != ['project.godot']:
            raise runner.SafetyError('freeze differs outside authorized project.godot transform: ' + str(source_vs_frozen))
        m['freeze_target_after_transform'] = frozen_hashes_after_transform
        m['freeze_authorized_source_differences'] = source_vs_frozen
        relevant = [p for p in files if p.suffix in {'.gd', '.tscn', '.godot', '.json'} and not p.as_posix().startswith(('assets/textures/', 'data/'))]
        shutil.copyfile(source_engine, engine)
        m['engine_sha256'] = digest(engine)
        assert digest(source_engine) == m['engine_sha256']
        runner.physical_e(engine)
        config = (target / 'project.godot').read_text(encoding='utf-8-sig')
        if (PROJECT / 'override.cfg').exists() or re.search(r'^\s*config/project_settings_override', config, re.M):
            raise runner.SafetyError('override refused')
        app = re.search(r'^\[application\]\s*\n(.*?)(?=^\[|\Z)', config, re.M | re.S)
        probe = generated / 'probe'
        probe.mkdir()
        probe_config = 'config_version=5\n[application]\n' + app[1]
        if integrated:
            probe_config += '\n' + transform['threading_after']
        (probe / 'project.godot').write_text(probe_config, encoding='utf-8')
        (probe / 'probe.gd').write_text(runner.PROBE_SCRIPT, encoding='utf-8')
        out, err, code = runner.execute([str(engine), '--headless', '--path', str(probe), '--script', 'res://probe.gd', '--', token, 'main', str(generated)], env, generated, evidence, 'probe', budgets, m['processes'])
        if code or 'ERROR:' in out + err:
            raise runner.SafetyError('real probe failed')
        m['user_probes'] = runner.verify_probe(out, generated, token)
        if integrated and any(item.get('worker_pool_max_threads') != 20 for item in m['user_probes']):
            raise runner.SafetyError('main/worker actual worker_pool_max_threads must both be 20')
        out, err, code = runner.execute([str(engine), '--headless', '--editor', '--import', '--path', str(target)], env, generated, evidence, 'import', budgets, m['processes'])
        m['import'] = {'exit': code, 'errors': [x for x in (out + err).splitlines() if 'ERROR:' in x]}
        # Preserve actual import errors; still exercise each requested scene rather than fabricate green.
        for name in names:
            before = snapshot_hashes(relevant, PROJECT)
            frozen_before = snapshot_hashes(relevant, target)
            command = suite_command(engine, target, name, fixture_root)
            row = {'suite': name, 'command': command, 'fixture_root': fixture_root.as_posix(), 'source_before': before, 'frozen_before': frozen_before}
            try:
                out, err, code = runner.execute(command, env, generated, evidence, name, budgets, m['processes'])
                parsed = (analyze_integrated_suite(name,out,err,code,target,frozen_before)
                          if integrated else analyze(out,err,code))
                row.update(exit=code, **parsed)
            except Exception as exc:
                rec = m['processes'][-1]
                out = (evidence / (name + '.stdout.log')).read_text(encoding='utf-8')
                err = (evidence / (name + '.stderr.log')).read_text(encoding='utf-8')
                row.update(exit=rec.get('exit_code'), **analyze(out, err, rec.get('exit_code')))
                row['passed'] = False
                row['execution_error'] = str(exc)
            row['source_after'] = snapshot_hashes(relevant, PROJECT)
            row['frozen_after'] = snapshot_hashes(relevant, target)
            row['parallel_drift'] = [p for p in before if before[p] != row['source_after'][p]]
            row['frozen_drift'] = [p for p in frozen_before if frozen_before[p] != row['frozen_after'][p]]
            row['current_vs_frozen_raw'] = [p for p in before if row['source_after'][p] != frozen_before[p]]
            authorized = set(m['editor_transform']['authorized_paths'])
            row['authorized_current_vs_frozen'] = [p for p in row['current_vs_frozen_raw'] if p in authorized]
            row['current_vs_frozen'] = [p for p in row['current_vs_frozen_raw'] if p not in authorized]
            m['suites'].append(row)
            save(owner / 'manifest.json', m)
            print(name, row['exit'], row['passed'], row['result_lines'], row['reasons'], flush=True)
            if integrated and not row['passed']:
                failure_dir = evidence / 'failed-source'
                failure_dir.mkdir(exist_ok=True)
                shutil.copyfile(target / ('tests/' + name + '.gd'), failure_dir / (name + '.gd'))
        if integrated:
            for name in ('gateway_bind_failure_test','client_match_inbox_contract_test'):
                shutil.copyfile(target / ('tests/' + name + '.gd'), evidence / (name + '.hash-bound.gd'))
        m['source_final'] = snapshot_hashes(files, PROJECT)
        m['final_drift'] = [p for p in m['freeze_before'] if m['source_final'][p] != m['freeze_before'][p]]
    except Exception as exc:
        m['error'] = type(exc).__name__ + ': ' + str(exc)
        print(m['error'], flush=True)
    finally:
        m['logs'] = [{'path': str(p), 'sha256': digest(p), 'bytes': p.stat().st_size} for p in evidence.glob('*.log')]
        m['current_summary'] = summarize_current(m)
        m['passed'] = m['current_summary']['passed']
        save(owner / 'manifest.json', m)
        try:
            runner.delete_owned(generated, owner)
            m['cleanup'] = 'generated_removed'
            m['engine_source_unchanged'] = digest(source_engine) == m.get('engine_sha256')
            m['generated_exists_after_cleanup'] = generated.exists()
        except Exception as exc:
            m['cleanup'] = 'retained: ' + str(exc)
            m['passed'] = False
        m['current_summary'] = summarize_current(m)
        m['passed'] = m['current_summary']['passed']
        save(owner / 'manifest.json', m)
        if integrated:
            finish_integrated(m, owner, evidence, report)
        else:
            lines = ['# Round32 clean import regression', '',
                     '结论：' + ('**top passed=true**（本次同一新 freeze 的当前13套与干净 import 均严格通过）' if m['passed'] else '**top passed=false**（未达到验收门槛）'), '',
                     '证据 manifest：`' + str(owner / 'manifest.json') + '`',
                     '仅运行当前明确的13套；不读取旧 manifest 计数，不拼接旧39套；全程 headless、单套180秒、同一独占E freeze。',
                     '生产 project.godot、production/game tests、generic runner 和 MCP 均未修改；GitPlugin 错误没有全局忽略规则。', '',
                     '## 隔离 project.godot transformation',
                     '授权范围仅为副本 `[editor]` 的 `version_control/plugin_name` 与 `version_control/autoload_on_startup`；源工程保持原 hash。',
                     '原/冻 hash 与逐字段 transformation：', '```json', json.dumps(m.get('editor_transform', {}), ensure_ascii=False, indent=2), '```',
                     'freeze 比较中唯一允许的 source→frozen 差异：`' + json.dumps(m.get('freeze_authorized_source_differences', []), ensure_ascii=False) + '`。其余 freeze/source/frozen 漂移均严格拒绝。',
                     '20线程保持：' + str(m.get('editor_transform', {}).get('worker_pool_max_threads_20')) + '；threading 原文与变换后原文相同：' + str(m.get('editor_transform', {}).get('threading_unchanged')) + '。', '',
                     '## Clean import',
                     'import exit=%s；ERROR 行数=%s；错误内容：%s' % (m.get('import', {}).get('exit'), len(m.get('import', {}).get('errors', [])), json.dumps(m.get('import', {}).get('errors', []), ensure_ascii=False)), '',
                     '## 13 suites', '|套件|真实 exit|checks|严格判定|错误/原因|', '|---|---:|---:|---|---|']
            for row in m['suites']:
                lines.append('|%s|%s|%s|%s|%s|' % (row['suite'], row['exit'], (row['result'] or {}).get('checks'), row['passed'], '; '.join(row['errors'] + row['reasons'] + [row.get('execution_error', '')]).replace('|', '/')))
            lines += ['', '同一 freeze 的最终源码漂移：`' + json.dumps(m.get('final_drift', []), ensure_ascii=False) + '`；套件期间源码并行漂移/冻结漂移见 manifest，未降级比较。',
                      '## Raw logs', 'raw stdout/stderr/import/probe 日志均保留在独占 evidence 目录，以下为逐文件读回 hash：']
            for log in m.get('logs', []):
                lines.append('- `%s` sha256=`%s` bytes=%s' % (log['path'], log['sha256'], log['bytes']))
            lines += ['', '## Cleanup',
                      '清理状态：`' + m['cleanup'] + '`；generated 删除后存在性=' + str(m.get('generated_exists_after_cleanup')) + '；源 Godot hash 未变=' + str(m.get('engine_source_unchanged')) + '。',
                      'transformation 单元已完成 RED（无函数时 AttributeError）→GREEN（当前测试 PASS）；真实 Godot clean import 与13套重跑结果以 manifest 为准。']
            report.write_text('\n'.join(lines) + '\n', encoding='utf-8')
            print(json.dumps({'passed': m['passed'], 'manifest': str(owner / 'manifest.json'), 'report': str(report), 'cleanup': m['cleanup']}, ensure_ascii=False), flush=True)
    return 0 if m['passed'] else 1


def resume(owner_arg):
    """Resume only a preserved owned freeze after outer transport interruption."""
    import subprocess
    owner = runner.physical_e(owner_arg)
    m = load(owner / 'manifest.json')
    generated = runner.contained(owner / 'generated', owner)
    target = runner.contained(generated / 'project', generated)
    evidence = owner / 'evidence'
    engine = generated / 'Godot.exe'
    # Confirm no native process still uses this exact owned executable tree.
    query = "Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -like '" + str(generated).replace("'", "''") + "*' } | Select-Object ProcessId,ExecutablePath | ConvertTo-Json -Compress"
    state = subprocess.check_output(['powershell.exe', '-NoProfile', '-Command', query], text=True).strip()
    if state:
        raise runner.SafetyError('owned process still live: ' + state)
    m['outer_interruption'] = {'reason': 'terminal transport limit 420 seconds', 'live_owned_executables': state,
                               'resume_same_freeze': True}
    assert digest(engine) == m['engine_sha256']
    files = [Path(x['path']) for x in m['source_files']]
    frozen_now = snapshot_hashes(files, target)
    assert frozen_now == m['freeze_before'], 'preserved freeze changed'
    relevant = [p for p in files if p.suffix in {'.gd', '.tscn', '.godot', '.json'} and not p.as_posix().startswith(('assets/textures/', 'data/'))]
    env = os.environ.copy()
    env['APPDATA'] = str(generated / 'appdata')
    env['LOCALAPPDATA'] = str(generated / 'localappdata')
    (generated / 'localappdata/hermes/cache/scratch').mkdir(parents=True, exist_ok=True)
    fixture_root = generated / ('fixtures-' + uuid.uuid4().hex)
    fixture_root.mkdir()
    env['FATE_TEST_SCRATCH_ROOT'] = fixture_root.as_posix()
    env.pop('HERMES_RECOVERY_VALIDATION_ROOT', None)
    if '--retry-preflight' in sys.argv:
        retry = {'net_validation_task_test', 'net_validation_simulation_test', 'net_validation_hard_timeout_test',
                 'net_parallel_validation_feedback_test', 'room_data_preparation_consumer_test',
                 'room_data_preparation_dependencies_test', 'gateway_relisten_acceptance_test'}
        m.setdefault('preflight_attempts', []).extend(x for x in m['suites'] if x['suite'] in retry)
        m['suites'] = [x for x in m['suites'] if x['suite'] not in retry]
    budgets = {'seconds': 180, 'bytes': 3221225472, 'min_free': 1073741824}
    # Reparse original logs with corrected bool-first CHECK recognition.
    for row in m['suites']:
        out = (evidence / (row['suite'] + '.stdout.log')).read_text(encoding='utf-8')
        err = (evidence / (row['suite'] + '.stderr.log')).read_text(encoding='utf-8')
        row.update(analyze(out, err, row['exit']))
        if row.get('execution_error'):
            row['passed'] = False
    for row in m['historical']['D15']['rows']:
        name = row['name']
        a = evidence / 'round28-originals'
        row.update(analyze((a / (name + '.stdout.log')).read_text(encoding='utf-8'), (a / (name + '.stderr.log')).read_text(encoding='utf-8'), row['exit']))
    m['historical']['D15']['strict_pass_count'] = sum(x['passed'] for x in m['historical']['D15']['rows'])
    for row in m['historical']['F09']:
        rec = load(evidence / 'round28-originals' / ('f09-' + row['name'] + '.json'))
        text = (evidence / 'round28-originals' / ('f09-' + Path(rec['log']).name)).read_text(encoding='utf-8')
        row.update(analyze(text, '', row['exit']))
    try:
        completed = {x['suite'] for x in m['suites']}
        for name in m['selected_suites']:
            if name in completed:
                continue
            for role in ('stdout', 'stderr'):
                p = evidence / (name + '.' + role + '.log')
                if p.exists():
                    p.rename(evidence / (name + '.prior-attempt-' + uuid.uuid4().hex + '.' + role + '.log'))
            before = snapshot_hashes(relevant, PROJECT)
            frozen_before = snapshot_hashes(relevant, target)
            cmd = [str(engine), '--headless', '--fixed-fps', '60', '--path', str(target), '--scene', 'res://tests/' + name + '.tscn']
            if name in {'room_data_preparation_consumer_test', 'room_data_preparation_dependencies_test'}:
                cmd += ['--', fixture_root.as_posix()]
            row = {'suite': name, 'command': cmd, 'fixture_root': fixture_root.as_posix(), 'source_before': before, 'frozen_before': frozen_before}
            try:
                out, err, code = runner.execute(cmd, env, generated, evidence, name, budgets, m['processes'])
                row.update(exit=code, **analyze(out, err, code))
            except Exception as exc:
                rec = m['processes'][-1]
                out = (evidence / (name + '.stdout.log')).read_text(encoding='utf-8')
                err = (evidence / (name + '.stderr.log')).read_text(encoding='utf-8')
                row.update(exit=rec.get('exit_code'), **analyze(out, err, rec.get('exit_code')))
                row['passed'] = False
                row['execution_error'] = str(exc)
            row['source_after'] = snapshot_hashes(relevant, PROJECT)
            row['frozen_after'] = snapshot_hashes(relevant, target)
            row['parallel_drift'] = [p for p in before if before[p] != row['source_after'][p]]
            row['frozen_drift'] = [p for p in frozen_before if frozen_before[p] != row['frozen_after'][p]]
            row['current_vs_frozen'] = [p for p in before if row['source_after'][p] != frozen_before[p]]
            m['suites'].append(row)
            save(owner / 'manifest.json', m)
            print(name, row['exit'], row['passed'], row['result_lines'], row['reasons'], flush=True)
        m['source_final'] = snapshot_hashes(files, PROJECT)
        m['final_drift'] = [p for p in m['freeze_before'] if m['source_final'][p] != m['freeze_before'][p]]
    except Exception as exc:
        m['error'] = str(exc)
    finally:
        m['logs'] = [{'path': str(p), 'sha256': digest(p), 'bytes': p.stat().st_size} for p in evidence.glob('*.log')]
        m['current_summary'] = summarize_current(m)
        m['passed'] = m['current_summary']['passed']
        save(owner / 'manifest.json', m)
        try:
            m['deleted_generated_bytes'] = runner.tree_bytes(generated)
            runner.delete_owned(generated, owner)
            m['cleanup'] = 'generated_removed'
            m['generated_exists_after_cleanup'] = generated.exists()
            m['engine_source_unchanged'] = digest('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe') == m['engine_sha256']
        except Exception as exc:
            m['cleanup'] = 'retained: ' + str(exc)
            m['passed'] = False
        m['current_summary'] = summarize_current(m)
        m['passed'] = m['current_summary']['passed']
        save(owner / 'manifest.json', m)
        hist = m['historical']['D15']
        lines = ['# Round29 核心共同回归', '', '**未达到最终冻结 PASS。**',
                 '完整证据：`' + str(owner / 'manifest.json') + '`',
                 '同一物理E独占快照；真实主/child user://探针，Job所有权，单套180s，仅headless。生产和游戏测试均未改。',
                 '外层420s工具截断后核验自有引擎路径无存活进程，从未变更的同一快照继续；中断日志另存，不作为通过。', '',
                 'Round28-D15原始20套、checks合计%s；严格聚合通过%s/20。重复CHECK标签/多RESULT/缺checks均失败关闭。' % (hist['check_total'], hist['strict_pass_count']),
                 '原证据仅4项事后源码hash，不是20套完整前后hash绑定；其中当前漂移：' + json.dumps([x['file'] for x in hist['hash_binding'] if not x['current_matches_round28']], ensure_ascii=False),
                 'Round28 F09原始JSON/日志已读回归档；F06两个RESULT拒绝。release PCK实际hash与审计核对；历史freeze已回收不能再校验原副本，不拼成整体通过。', '',
                 '|套件|exit|checks|严格通过|真实错误/拒绝原因|', '|---|---:|---:|---|---|']
        for row in m['suites']:
            lines.append('|%s|%s|%s|%s|%s|' % (row['suite'], row['exit'], (row['result'] or {}).get('checks'), row['passed'], '; '.join(row['errors'] + row['reasons'] + [row.get('execution_error', '')]).replace('|', '/')))
        lines += ['', 'Validation20显式清单（未找到历史唯一命名清单，不能冒称既定全量）：', ', '.join(VALIDATION20), '',
                  '每套源码/快照前后hash与并行漂移均在manifest；最终源码漂移：' + json.dumps(m.get('final_drift', []), ensure_ascii=False),
                  '回收：' + m['cleanup'] + '；生成树含单份E引擎、import缓存和APPDATA，删除后不存在性已核验。原D引擎hash未变。',
                  '原始日志、命令、PID、exit与失败证据保留；tests/reports可能被gitignore，未add、未提交。']
        (PROJECT / 'docs/round29-core-regression.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
        print(json.dumps({'manifest': str(owner / 'manifest.json'), 'passed': m['passed'], 'cleanup': m['cleanup'], 'suites': len(m['suites'])}), flush=True)
    return 0 if m['passed'] else 1


def finalize(owner_arg):
    """Read back archived results; never upgrade an incomplete batch to freeze PASS."""
    owner = runner.physical_e(owner_arg)
    m = load(owner / 'manifest.json')
    evidence = owner / 'evidence'
    assert m['cleanup'] == 'generated_removed' and not (owner / 'generated').exists()
    m['historical'] = historical(evidence)
    names = [x['suite'] for x in m['suites']]
    assert len(names) == len(set(names)), 'duplicate suite records'
    for row in m['suites']:
        out = (evidence / (row['suite'] + '.stdout.log')).read_text(encoding='utf-8')
        err = (evidence / (row['suite'] + '.stderr.log')).read_text(encoding='utf-8')
        row.update(analyze(out, err, row['exit']))
        row['raw_log_hashes'] = {role: digest(evidence / (row['suite'] + '.' + role + '.log')) for role in ('stdout', 'stderr')}
        if row.get('execution_error'):
            row['passed'] = False
    gw = next(x for x in m['suites'] if x['suite'] == 'gateway_relisten_acceptance_test')
    stderr = (evidence / 'gateway_relisten_acceptance_test.stderr.log').read_text(encoding='utf-8')
    expected = ["ERROR: Couldn't create an ENet host.",
        'at: _create (modules/enet/enet_connection.cpp:319)',
        'GDScript backtrace (most recent call first):',
        '[0] listen (res://scripts/net/transport/enet_transport.gd:44)',
        '[1] listen (res://scripts/net/server/server_gateway.gd:51)',
        '[2] run (res://tests/gateway_relisten_acceptance_test.gd:92)']
    test_path = 'tests/gateway_relisten_acceptance_test.gd'
    test = PROJECT / test_path
    same_source = digest(test) == gw['frozen_before'][test_path]
    source_lines = test.read_text(encoding='utf-8').splitlines()
    exact = [x.strip() for x in stderr.splitlines() if x.strip()] == expected
    call_matches = 'check(gateway.listen(port,"127.0.0.1",root) != OK,"端口占用监听失败")' in source_lines[91]
    stdout = (evidence / 'gateway_relisten_acceptance_test.stdout.log').read_text(encoding='utf-8')
    markers = all('CHECK ' + label + ' true' in stdout.splitlines() for label in
                  ['真实 ENet 占用目标端口', '端口占用监听失败', '传输监听失败不得开放', '失败后公开重监听成功'])
    gw['scoped_negative_error'] = {'exact_stderr_matches': exact, 'test_hash_matches_freeze': same_source,
        'source_line_92_matches': call_matches, 'negative_and_recovery_checks': markers,
        'expected_count': 1, 'error_outside_bound_negative': not exact,
        'negative_binding_verified': exact and same_source and call_matches and markers,
        'strict_pass_preserved': gw['passed'],
        'note': 'Separate stdout/stderr have no cross-stream timestamps. Binding uses exact unique native error/backtrace, hash-bound call site and surrounding assertions, not a global ENet ignore.'}
    if same_source:
        shutil.copyfile(test, evidence / 'gateway_relisten_acceptance_test.hash-bound.gd')
    files = [Path(x['path']) for x in m['source_files']]
    m['source_after_cleanup_readback'] = snapshot_hashes(files, PROJECT)
    m['final_drift'] = [p for p in m['freeze_before'] if m['source_after_cleanup_readback'][p] != m['freeze_before'][p]]
    m['final_drift_timing'] = 'Read after cleanup; per-suite before/after observations retained independently.'
    m['missing_suites'] = [x for x in m['selected_suites'] if x not in names]
    m['verified_actual_suite_count'] = len(names)
    m['verified_strict_pass_count'] = sum(x['passed'] for x in m['suites'])
    m['validation20_completed_count'] = sum(x in names for x in VALIDATION20)
    m['validation20_missing'] = [x for x in VALIDATION20 if x not in names]
    m['passed'] = False
    shutil.copyfile(Path(__file__), evidence / 'test_round29_integrated_evidence.final.py')
    m['final_aggregator_sha256'] = digest(Path(__file__))
    m['finalize_command'] = [sys.executable, '-B', str(Path(__file__)), '--finalize', str(owner)]
    m['logs'] = [{'path': str(p), 'sha256': digest(p), 'bytes': p.stat().st_size} for p in evidence.glob('*.log')]
    save(owner / 'manifest.json', m)
    hist = m['historical']['D15']
    lines = ['# Round29 核心共同回归：最终原始证据', '', '**整体 passed=false；不能作为最终冻结 PASS。**',
        '证据：`' + str(owner / 'manifest.json') + '`',
        '实际39套记录（严格通过%s）；选择52套，缺13套；Validation20执行%s/20，另有预检失败旧尝试独立保留，不充抵最终套数。' % (m['verified_strict_pass_count'], m['validation20_completed_count']),
        '全生产只读，唯一代码为 tools/tests/test_round29_integrated_evidence.py。相同E独占快照；物理主/child user://回执、随机token、不同PID、child exit0均读回核验；Windows Job只管理自有进程；单套180s，无窗口。',
        '每套实际命令/exit/错误、源码及快照前后hash、并行漂移均在manifest。快照全程未漂移；源码并行变化不借专项记录拼接PASS。', '',
        '## Round28原始检验',
        'D15真实20套/913 checks与summary一致；严格通过%s/20，6套重复CHECK标签被拒绝。仅4项事后hash，不能证明全部20套运行的版本绑定。' % hist['strict_pass_count'],
        'D15相对当前漂移：' + json.dumps([x['file'] for x in hist['hash_binding'] if not x['current_matches_round28']], ensure_ascii=False),
        'F09原始8组JSON与日志读回归档；F06双RESULT严格拒绝。F09源码hash差异：' + json.dumps([x['path'] for x in m['historical']['F09_hash_bindings'] if not x['matches']], ensure_ascii=False),
        '发行v3全部5个原始step日志已读取归档；原freeze、exe/PCK已按原cleanup回收，实包不可再次验hash。保留audit/index只是历史证据，不宣称运行验证或重新校验实包。', '',
        '## Gateway负向精确绑定',
        'gateway_relisten真实exit0、41 checks、无失败；stderr唯一错误为 `ERROR: Couldn\'t create an ENet host.`，唯一回溯为测试第92行明确占端口负向调用。测试源码hash与本次快照一致，占端口/拒绝监听/保持关闭/恢复监听断言均true，完整stderr精确6行匹配，绑定之外零错误。',
        '负向绑定核验=' + str(gw['scoped_negative_error']['negative_binding_verified']) + '；原始strict passed仍false，整体passed=false。没有全局忽略ENet错误；无跨stdout/stderr时间顺序证据。', '',
        '## 39套真实结果', '|套件|exit|checks|严格通过|真实错误/拒绝原因|', '|---|---:|---:|---|---|']
    for row in m['suites']:
        lines.append('|%s|%s|%s|%s|%s|' % (row['suite'], row['exit'], (row['result'] or {}).get('checks'), row['passed'], '; '.join(row['errors'] + row['reasons'] + [row.get('execution_error', '')]).replace('|', '/')))
    lines += ['', '## 未完成与并行漂移', '未完成13套：' + ', '.join(m['missing_suites']),
        'Validation20为聚合器明确列出的20套选择；未检索到历史唯一清单，不能冒称既定全量。',
        '本次有界失败：外层工具420s截断，随后复用原快照恢复；预检夹具缺显式根的旧失败归档保留；补齐夹具根重试时旧日志归档同名导致WinError183，批次停止并保守回收，13套缺失。该聚合器重名问题现已改为UUID归档，未重跑伪造补齐结果。',
        '单套180s timeout：' + ', '.join(x['suite'] for x in m['suites'] if x.get('execution_error') == 'timeout'),
        '源码运行期间漂移：' + json.dumps([(x['suite'], x['parallel_drift']) for x in m['suites'] if x['parallel_drift']], ensure_ascii=False),
        '清理后源码hash相对快照差异（不是运行末刻）：' + json.dumps(m['final_drift'], ensure_ascii=False), '',
        '## 归档与回收',
        'generated已删除，读回不存在；单份E主引擎、项目副本、APPDATA和import缓存均回收，D源引擎hash未变。删除字节=' + str(m.get('deleted_generated_bytes')) + '。',
        '保留manifest、全部真实日志/历史原始证据及精确hash绑定的网关专项源码。tests/reports可能被忽略，未git add、未提交；项目内只新增聚合器与本报告。']
    (PROJECT / 'docs/round29-core-regression.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print(json.dumps({'count': len(names), 'strict_pass_count': m['verified_strict_pass_count'],
        'missing': m['missing_suites'], 'gateway_negative_verified': gw['scoped_negative_error']['negative_binding_verified'],
        'drift': m['final_drift'], 'cleanup': m['cleanup'], 'passed': False}, ensure_ascii=False))
    return 1


def summarize_archived(manifest_arg):
    source = runner.physical_e(manifest_arg)
    before = digest(source)
    m = load(source)
    result = summarize_current(m)
    target = runner.physical_e('E:/scratch') / ('round31-summary-' + uuid.uuid4().hex)
    target.mkdir()
    save(target / 'summary.json',dict(result,source_manifest=str(source),source_sha256=before,parser_sha256=digest(__file__)))
    assert digest(source) == before, 'historical manifest changed'
    print(json.dumps(dict(result,summary=str(target / 'summary.json'),historical_manifest_unchanged=True),ensure_ascii=False))
    return 0 if result['passed'] else 1


def reparse_archived(manifest_arg):
    """只读重解析历史字节；绝不重写旧 manifest 或旧日志。"""
    source = runner.physical_e(manifest_arg)
    prior = load(source)
    evidence = source.parent / 'evidence'
    token = uuid.uuid4().hex
    target = runner.physical_e('E:/scratch') / ('round31-reparse-' + token)
    target.mkdir()
    inputs = [source] + sorted(evidence.glob('*.log'))
    before = {str(p): digest(p) for p in inputs}
    rows = []
    for old in prior['suites']:
        logs = {role: evidence / (old['suite'] + '.' + role + '.log') for role in ('stdout','stderr')}
        out, err = [logs[role].read_bytes().decode('utf-8') for role in ('stdout','stderr')]
        rows.append({'suite': old['suite'], 'exit': old['exit'], 'prior_reasons': old['reasons'],
                     **analyze(out,err,old['exit']), 'logs': {role: {'path':str(p),'sha256':digest(p)} for role,p in logs.items()},
                     'source_before':old['source_before'], 'source_after':old['source_after'],
                     'frozen_before':old['frozen_before'], 'frozen_after':old['frozen_after'],
                     'parallel_drift':old['parallel_drift'], 'frozen_drift':old['frozen_drift']})
    after = {str(p):digest(p) for p in inputs}
    assert before == after, 'historical bytes changed'
    result = {'source_manifest':str(source), 'input_hashes_before':before, 'input_hashes_after':after,
              'historical_unchanged':True, 'rows':rows, 'count':len(rows), 'strict_pass_count':sum(r['passed'] for r in rows),
              'passed':False, 'policy':'Historical reparse only; no new freeze PASS; no merging with old39.',
              'original_final_drift':prior.get('final_drift',[]), 'parser_sha256':digest(__file__)}
    save(target / 'reparsed.json',result)
    print(json.dumps({'report':str(target / 'reparsed.json'),'count':len(rows),'strict_pass_count':result['strict_pass_count'],'historical_unchanged':True},ensure_ascii=False))
    return 1 if not all(r['passed'] for r in rows) else 0


ROUND40_EXPECTED_CHECKS = {
    'net_validation_hard_timeout_test':37, 'validation_checkpoint_reader_test':10,
    'worker_content_environment_test':45,
    'newspecial_spell_materialization_test':13, 'command_spell_source_activation_test':54,
    'round39_restore_transaction_test':61, 'assembly_publish_lifecycle_test':66,
    'client_match_inbox_contract_test':45, 'gateway_deferred_test':16,
    'gateway_disconnect_safe_close_test':7, 'net_server_gateway_test':19,
    'net_server_discovery_validation_test':33, 'net_validation_io_feedback_test':23,
    'net_background_validation_feedback_test':25, 'net_server_gateway_restart_test':61,
    'round50_finished_lobby_receipt_test':16, 'round47_host_lifecycle_board_test':14,
}
ROUND40_OUTPUT_ARGS = {
    'room_data_preparation_consumer_test','room_data_preparation_dependencies_test',
    'net_server_gateway_test','net_server_discovery_validation_test','net_server_gateway_restart_test',
    'net_background_validation_feedback_test','net_validation_io_feedback_test',
    'round39_restore_transaction_test','assembly_publish_lifecycle_test',
    'lobby_content_environment_restore_test','net_blob_concurrent_test',
    'server_data_status_inbox_approval_test',
}


def round40_command(engine, target, name, output):
    if name in ROUND40_GUI:
        raise ValueError('GUI requires actual non-headless evidence; not executable by headless runner')
    command = [Path(engine).as_posix(), '--headless', '--fixed-fps','60', '--path',
               Path(target).as_posix(), '--scene','res://tests/'+name+'.tscn']
    if name in ROUND40_OUTPUT_ARGS:
        command += ['--',Path(output).as_posix()]
    return command


def analyze_round40_suite(name, out, err, code, target, hashes):
    result = analyze_integrated_suite(name,out,err,code,target,hashes)
    expected = ROUND40_EXPECTED_CHECKS.get(name)
    if expected and (result.get('result') or {}).get('checks') != expected:
        result['passed'] = False
        result['reasons'].append('expected_checks_%d' % expected)
    if name == 'assembly_publish_lifecycle_test' and 'ASSEMBLY_NATIVE_SKIP' in out + err:
        result['passed'] = False
        result['reasons'].append('mandatory_native_branch_skipped')
    return result


def summarize_round40(m):
    current = summarize_integrated(m)
    reasons = list(current['reasons'])
    focused = m.get('focused',[])
    expected = m.get('focused_expected',[])
    if m.get('phase_policy') == 'complete_only_current_freeze':
        if expected or focused:
            reasons.append('unexpected_focused_credit_in_complete_candidate')
    elif not expected or [r['suite'] for r in focused] != expected:
        reasons.append('focused_incomplete')
    if any(not r['passed'] for r in focused): reasons.append('focused_failure')
    if m.get('pre_full_drift'): reasons.append('pre_full_source_drift')
    if m.get('full_safety_blockers'): reasons.append('unsafe_full_output_contract')
    if m.get('archive_verified') is not True: reasons.append('archive_unverified')
    if m.get('round') == 43:
        pre=m.get('prerequisites',[])
        if (len(pre)!=1 or pre[0]['suite']!='worker_content_environment_test' or not pre[0]['passed']
                or pre[0].get('exit')!=0 or (pre[0].get('result') or {}).get('checks')!=45):
            reasons.append('worker45_prerequisite_not_verified')
        selected=m.get('selected_suites',[])
        static=m.get('scene_static_preflight',{})
        if len(selected)!=70 or len(set(selected))!=70: reasons.append('exact70_selection_required')
        if static.get('passed') is not True or {r['suite'] for r in static.get('suites',[])}!=set(selected):
            reasons.append('whole70_static_preflight_unverified')
        errors=m.get('worker_engine_errors',[])
        scoped=m.get('worker_scoped_negatives',[])
        if (len(errors)!=len(scoped) or any(not b['binding'].get('verified') for b in scoped)
                or any(error not in [b['error'] for b in scoped] for error in errors)):
            reasons.append('worker_engine_error')
        if m.get('readonly_tool_drift'): reasons.append('readonly_tool_drift')
    return dict(current, headless_candidate_passed=not reasons, passed=not reasons,
                headless_source_candidate_PASS=not reasons if m.get('round')==43 else False,
                release_passed=False, reasons=reasons,
                focused_count=len(focused), focused_pass_count=sum(r['passed'] for r in focused))


def round40_history(archive):
    """Bind original bytes, not a synthetic historical success or current freeze PASS."""
    reports = ['round33-integrated-candidate','round36-fixture-contracts','round36-end-command-port',
               'round36-gateway-fixtures','round36-validation-feedback','round37-special-spell-takeover',
               'round38-assembly-publish','round39-restart-restore-transaction','round39-native-cold-import']
    inputs = []
    for name in reports:
        source = PROJECT / ('docs/'+name+'.md')
        inputs.append({'path':str(source),'sha256':digest(source)})
        shutil.copyfile(source,archive/source.name)
    root = PROJECT / 'reports/refactoring'
    correctness = root / 'round36-gateway-correctness-restart-fd397e5f782d416b9175f258a8851337'
    cm = load(correctness/'manifest.json')
    stdout = correctness/'net_server_gateway_restart_test.stdout.log'
    stderr = correctness/'net_server_gateway_restart_test.stderr.log'
    for path in [correctness/'manifest.json',stdout,stderr]:
        inputs.append({'path':str(path),'sha256':digest(path)})
        shutil.copyfile(path,archive/('correctness-'+path.name))
    entry = cm['suites'][0]
    parsed = analyze(stdout.read_text(encoding='utf-8'),stderr.read_text(encoding='utf-8'),entry['exit'])
    bindings = []
    for x in cm['source_files']:
        p = PROJECT/x['path']
        if x['path'].startswith(('scripts/','tests/')):
            bindings.append({'path':x['path'],'historical_sha256':x['sha256'],
                             'current_sha256':digest(p) if p.is_file() else None})
    for x in bindings: x['current_matches']=x['historical_sha256']==x['current_sha256']
    gui = root/'main-review/round37-final-local_spell_restore_test.log'
    text = gui.read_text(encoding='utf-8')
    inputs.append({'path':str(gui),'sha256':digest(gui)})
    shutil.copyfile(gui,archive/gui.name)
    gui_source = {rel:digest(PROJECT/rel) for rel in ['tests/local_spell_restore_test.gd',
                  'tests/local_spell_restore_test.tscn','scripts/system/global/master_manager.gd',
                  'scripts/game_scene/battle_board_v2.gd','scripts/game_scene/tactical_board_ui.gd']}
    return {'inputs':inputs,'restart_correctness':{'manifest':str(correctness/'manifest.json'),
            'historical_only':True,'analysis':parsed,'expected_checks':61,'source_bindings':bindings,
            'performance_60s_passed':False,'correctness_600s_passed':parsed['passed'],
            'performance_lines':[x for x in stdout.read_text(encoding='utf-8').splitlines() if x.startswith('GATEWAY_PERFORMANCE_GATE')]},
            'gui':{'suite':'local_spell_restore_test','status':'REQUIRES_VERSION_BOUND_NON_HEADLESS_EVIDENCE',
            'log':str(gui),'log_sha256':digest(gui),'recorded_checks':25,
            'protocol_reparse':analyze(text,'',0),
            'exit_zero_source':'round37-special-spell-takeover.md reports exit0; original standalone exit receipt unavailable',
            'non_headless_renderer_recorded':'Vulkan' in text,
            'historical_source_hash_binding':None,'current_capture_not_execution_binding':gui_source,
            'version_gap':'No retained execution-time source manifest found alongside round37 GUI log; current hashes do not prove that run version.',
            'counts_as_current_pass':False}}


def round41_runnable_partition(names, blockers):
    blocked = [b['suite'] for b in blockers]
    if len(names) != len(set(names)) or len(blocked) != len(set(blocked)) or not set(blocked).issubset(names):
        raise ValueError('duplicate or unselected output contract')
    return {'runnable':[n for n in names if n not in blocked], 'blocked':blocked}


ROUND42_DEPENDENCY_NEGATIVE_SOURCES = {
    'tests/room_data_preparation_dependencies_test.gd':'58b1a49de8dec3eece1a6a7c7bf59d0960c7df3501c3b851aa6c8ebf2de9ce98',
    'scripts/system/global/load_game.gd':'2a78f90ac18bd76ea2ea3181349d069874bda5df3ce8280134e17f9ef17c92e5',
    'scripts/net/validation/room_data_validation_worker.gd':'86e281f0c0987e7b76a2736373bb046ec9e0c278bef71d0d82424fe8da407a9c',
}


def round42_dependency_worker_negative(archive, manifest, error):
    """Exact single-card rejection only; preserve strict ERROR red and original logs."""
    evidence = {'verified':False,'strict_passed':False,'classification':'unclassified_worker_error'}
    try:
        rel = Path(error['path'])
        if rel.is_absolute() or '..' in rel.parts or rel.parts[0] != 'worker': return evidence
        phase, index = rel.parts[1].split('-')
        if phase not in {'focused','complete'}: return evidence
        rows = manifest['focused' if phase=='focused' else 'prerequisites' if phase=='prerequisite' else 'suites']
        row = rows[int(index)]
        if row['phase'] != phase: return evidence
        if row['suite'] != 'room_data_preparation_dependencies_test' or not row['passed'] or row.get('exit') != 0:
            return evidence
        if row['result']['checks'] != 34 or row['observed_checks'] != 34 or row.get('frozen_drift'):
            return evidence
        bound = manifest.get('frozen_hashes',{})
        if any(bound.get(p) != sha for p,sha in ROUND42_DEPENDENCY_NEGATIVE_SOURCES.items()): return evidence
        path = Path(archive)/rel
        text = path.read_text(encoding='utf-8')
        original = Path(row['fixture_root']).joinpath(*rel.parts[2:]).parent/'validation-data'
        expected_lines = ['ERROR: 无法读取角色目录：'+(original/name).as_posix() for name in ['masters','servants']]
        actual_errors = [line for line in text.splitlines() if re.search(r'SCRIPT ERROR|SHADER ERROR|^\s*ERROR:',line)]
        if error['lines'] != expected_lines or actual_errors != expected_lines: return evidence
        expected = []
        for i,(name,line,call) in enumerate([('masters',185,'load_masters_from_jsons'),('servants',197,'load_servants_from_jsons')]):
            expected += [expected_lines[i], 'at: push_error (core/variant/variant_utility.cpp:1023)',
                'GDScript backtrace (most recent call first):',
                '[0] %s (res://scripts/system/global/load_game.gd:%d)' % (call,line),
                '[1] load_game (res://scripts/system/global/load_game.gd:%d)' % (35+i),
                '[2] reload_game (res://scripts/system/global/load_game.gd:51)',
                '[3] _inspect_loaded_content (res://scripts/net/validation/room_data_validation_worker.gd:127)',
                '[4] _ready (res://scripts/net/validation/room_data_validation_worker.gd:61)']
        lines = [line.strip() for line in text.splitlines()]
        start = lines.index(expected_lines[0])
        if lines[start:start+len(expected)] != expected: return evidence
        worker_root = path.parent
        approved = load(worker_root/'manifest.json')
        if approved != [{'hash':'799dcd2605baeb811684fcf095cf94b70b09eb2ae43099bcdad702145cf7eef1',
                         'path':'attacks/basic/surveil/surveil.json','size':3653}]: return evidence
        report = load(worker_root/'report.json')
        if (report.get('ok') is not False or report.get('masters') != 0 or report.get('servants') != 0
            or report.get('errors') != ['所选数据缺少可加载的御主或从者']): return evidence
        summaries = [json.loads(line.split(' ',1)[1]) for line in text.splitlines() if line.startswith('ROOM_DATA_VALIDATION ')]
        if summaries != [report]: return evidence
        label = row['phase']+'-'+row['suite']
        processes = [p for p in manifest['processes'] if p['label']==label]
        if len(processes)!=1 or not processes[0].get('exited') or processes[0].get('active_owned_processes')!=0:
            return evidence
        evidence.update(verified=True,classification='scoped_single_card_negative',suite=row['suite'],
                        exact_errors=expected_lines,source_hashes=ROUND42_DEPENDENCY_NEGATIVE_SOURCES,
                        engine_log_sha256=digest(path),manifest_sha256=digest(worker_root/'manifest.json'),
                        report_sha256=digest(worker_root/'report.json'),own_job_exit=processes[0])
    except (OSError,KeyError,ValueError,IndexError,TypeError):
        pass
    return evidence


def round42_stop(stage, error, rows):
    reason = ('freeze_source_drift' if stage == 'freeze' and 'source drift' in error
              else stage + '_rejected')
    return {'stop_reason':reason,'business_suites_executed':len(rows),
            'business_failed':[row['suite'] for row in rows if not row['passed']]}


def archive_fixture_artifacts(fixtures, archive):
    index = []
    for path in fixtures.rglob('*'):
        if path.is_file() and (round61_artifact_declared(path) or path.name == 'config.json'):
            dest=archive/'worker'/path.relative_to(fixtures)
            dest.parent.mkdir(parents=True,exist_ok=True)
            sha=digest(path)
            shutil.copyfile(path,dest)
            index.append({'path':str(dest.relative_to(archive)),'sha256':sha,'verified':digest(dest)==sha})
    return index


def fixture_engine_errors(index, archive):
    rows = [{'path':x['path'],'lines':[line for line in (archive/x['path']).read_text(encoding='utf-8',errors='replace').splitlines()
             if re.search(r'SCRIPT ERROR|SHADER ERROR|^\s*ERROR:',line)]} for x in index if x['path'].endswith('.log')]
    return [row for row in rows if row['lines']]


def round43_reparse_archive(manifest_path):
    """Reparse real complete70 only; never execute Godot or rewrite historical bytes."""
    source=runner.physical_e(manifest_path);archive=source.parent
    before=digest(source);m=load(source)
    if m.get('round')!=43 or m.get('cleanup')!='generated_removed':
        raise runner.SafetyError('requires completed owned Round43 archive')
    names=[row['suite'] for row in m['suites']]
    if len(names)!=70 or len(set(names))!=70 or set(names)!=set(m['selected_suites']):
        raise runner.SafetyError('requires exact complete unique70, not a partial freeze')
    original_summary=m['summary'].copy()
    if any(digest(archive/item['path'])!=item['sha256'] for item in m['logs']+m['worker_artifacts']):
        raise runner.SafetyError('archived original byte hash changed')
    source_now=snapshot_hashes([Path(item['path']) for item in m['source_files']],PROJECT)
    drift=[rel for rel,sha in m['freeze_before'].items() if source_now[rel]!=sha]
    if drift: raise runner.SafetyError('current source differs from executed freeze: '+str(drift))
    for row in m['suites']:
        label=row['phase']+'-'+row['suite']
        out=(archive/'evidence'/(label+'.stdout.log')).read_text(encoding='utf-8')
        err=(archive/'evidence'/(label+'.stderr.log')).read_text(encoding='utf-8')
        row.update(analyze_round40_suite(row['suite'],out,err,row['exit'],PROJECT,m['frozen_hashes']))
        if row.get('execution_error') or row.get('parallel_drift') or row.get('frozen_drift') or row.get('current_vs_frozen'):
            row['passed']=False
        if row['suite'] in ROUND40_LONG:
            value=round43_restart_readback(archive,m,row)
            m['restart_current']['archive_readback']=value
            m['restart_current']['final_save_readback']=value['saved']
            if not value['verified']:
                row['passed']=False;row['reasons'].append('restart_journal_save_archive_unverified')
    m['worker_scoped_negatives']=[]
    for error in m['worker_engine_errors']:
        binding=round42_dependency_worker_negative(archive,m,error)
        if not binding['verified']: binding=round43_bind_log_negative(archive,m,error)
        if binding['verified']: m['worker_scoped_negatives'].append({'error':error,'binding':binding})
    source_after=snapshot_hashes([Path(item['path']) for item in m['source_files']],PROJECT)
    if digest(source)!=before or source_after!=source_now:
        raise runner.SafetyError('source/original archive changed during reparse')
    m['reparse']={'mode':'read_only_current_complete70_reparse_no_execution','original_manifest':str(source),
        'original_manifest_sha256':before,'original_summary':original_summary,
        'original_bytes_unchanged':True,'all_original_log_and_worker_hashes_verified':True,
        'execution_aggregator_sha256':digest(archive/'aggregator.py'),'reparser_sha256':digest(__file__),
        'current_source_drift':drift,'source_matches_execution_before_after':True,
        'changes':['native archive separator interpretation','exact bound Godot logger duplicate classification']}
    m['summary']=summarize_round40(m);m['passed']=m['summary']['passed']
    return m


def round43_bind_log_negative(archive, manifest, error):
    """Classify only the exact bound negative also duplicated by Godot's own file logger."""
    from pathlib import PureWindowsPath
    value={'verified':False,'strict_passed':False,'classification':'unclassified_worker_error'}
    try:
        rel=PureWindowsPath(error['path'])
        if rel.is_absolute() or '..' in rel.parts or len(rel.parts)!=6: return value
        if rel.parts[0]!='worker' or rel.parts[1]!='complete-'+str(manifest['selected_suites'].index('gateway_bind_failure_test')):
            return value
        row=manifest['suites'][manifest['selected_suites'].index('gateway_bind_failure_test')]
        if (row['suite']!='gateway_bind_failure_test' or row['exit']!=0 or row.get('frozen_drift')
                or not row.get('scoped_negative_error',{}).get('verified')): return value
        app=PureWindowsPath(manifest['user_probes'][0]['path']).name
        if rel.parts[2:]!=('appdata',app,'logs','godot.log'): return value
        original=PureWindowsPath(manifest['generated'])/'f'/Path(*rel.parts[1:])
        if original!=PureWindowsPath(row['explicit_environment']['APPDATA'])/app/'logs/godot.log': return value
        for source in ['tests/gateway_bind_failure_test.gd','scripts/net/transport/enet_transport.gd','scripts/net/server/server_gateway.gd']:
            if digest(PROJECT/source)!=manifest['frozen_hashes'].get(source): return value
        evidence=Path(archive)/'evidence'
        out=(evidence/'complete-gateway_bind_failure_test.stdout.log').read_text(encoding='utf-8')
        err=(evidence/'complete-gateway_bind_failure_test.stderr.log').read_text(encoding='utf-8')
        scope=analyze_integrated_suite(row['suite'],out,err,row['exit'],PROJECT,manifest['frozen_hashes'])
        if not scope['passed'] or scope['result']['checks']!=7 or error['lines']!=scope['errors']: return value
        path=Path(archive).joinpath(*rel.parts)
        runner.contained(path,archive)
        item=next(i for i in manifest['worker_artifacts'] if PureWindowsPath(i['path']).parts==rel.parts)
        if digest(path)!=item['sha256']: return value
        log=path.read_text(encoding='utf-8')
        lines=[line.strip() for line in log.splitlines() if line.strip()]
        expected=[line.strip() for line in err.splitlines() if line.strip()]
        start=lines.index(expected[0])
        if lines[start:start+len(expected)]!=expected: return value
        without=lines[:start]+lines[start+len(expected):]
        if without!=[line.strip() for line in out.splitlines() if line.strip()]: return value
        proc=next(p for p in manifest['processes'] if p['label']=='complete-gateway_bind_failure_test')
        if not proc.get('exited') or proc.get('active_owned_processes')!=0 or not proc.get('log_handles_released'): return value
        value.update(verified=True,classification='scoped_bind_negative_logger_copy',suite=row['suite'],
                     exact_errors=error['lines'],log_sha256=digest(path),stdout_sha256=digest(evidence/'complete-gateway_bind_failure_test.stdout.log'),
                     stderr_sha256=digest(evidence/'complete-gateway_bind_failure_test.stderr.log'),
                     exact_six_line_trace_and_seven_checks=True,source_hash_and_line13_bound=True,own_job_exit=proc)
    except (OSError,KeyError,ValueError,IndexError,StopIteration,TypeError):
        pass
    return value


def round43_restart_readback(archive, manifest, row):
    """Bind retained binary journal to the actual save, independent of native separators."""
    from pathlib import PureWindowsPath
    value={'verified':False,'saved':[],'reasons':[]}
    try:
        archive=Path(archive)
        expected=('worker','complete-'+str(manifest['selected_suites'].index(row['suite'])))
        artifacts=[]
        for item in manifest['worker_artifacts']:
            rel=PureWindowsPath(item['path'])
            if rel.is_absolute() or '..' in rel.parts: raise ValueError('unsafe archived relative path')
            if rel.parts[:2]==expected: artifacts.append(item)
        saves=[item for item in artifacts if PureWindowsPath(item['path']).name=='round39-final-save.json']
        if len(saves)!=1: raise ValueError('expected one real final save artifact')
        item=saves[0];save_path=archive.joinpath(*PureWindowsPath(item['path']).parts)
        runner.contained(save_path,archive)
        if digest(save_path)!=item['sha256']: raise ValueError('final save archive hash mismatch')
        data=load(save_path)
        original=PureWindowsPath(data['journal'])
        fixture=PureWindowsPath(row['fixture_root'])
        original.relative_to(fixture)  # Cannot substitute a sibling suite or unrelated saved game.
        relative=original.relative_to(PureWindowsPath(manifest['generated'])/'f')
        journal=archive/'worker'/Path(*relative.parts)
        runner.contained(journal,archive)
        sha=digest(journal)
        indexed=next((i for i in artifacts if PureWindowsPath(i['path']).parts==('worker',)+relative.parts),None)
        if indexed is None or sha!=indexed['sha256'] or sha!=data['journal_sha256']:
            raise ValueError('journal bytes differ from captured save/index')
        receipt=data['receipt'];result=receipt['result']
        if (data['game_over'] is not True or receipt.get('ok') is not True or result.get('saved') is not True
                or data['tail_hash']!=result['state_hash'] or data['records']!=result['records']):
            raise ValueError('actual final save receipt/hash/records inconsistent')
        command_receipt=journal.parent.parent.parent/'control'/(receipt['request_id']+'.response.json')
        if load(command_receipt)!=receipt: raise ValueError('save receipt not equal to original command response')
        value['saved']=[{'save_path':Path(*PureWindowsPath(item['path']).parts).as_posix(),'save_sha256':item['sha256'],
            'journal_path':journal.relative_to(archive).as_posix(),'journal_sha256':sha,'journal_matches_save':True,
            'tail_hash':data['tail_hash'],'records':data['records'],'game_over':True,
            'command_response_path':command_receipt.relative_to(archive).as_posix(),
            'command_response_sha256':digest(command_receipt)}]
        value['verified']=True
    except (OSError,ValueError,KeyError,StopIteration,TypeError) as exc:
        value['reasons'].append(str(exc))
    return value


def round43_gui_binding(current_hashes):
    """Read independent execution-time GUI evidence; never count it in headless70."""
    path=PROJECT/'reports/refactoring/round42-modal-zoom/final4/manifest.json'
    gui=load(path);reasons=[]
    historical=gui['source_before']
    if any(gui.get(key)!=historical for key in ['source_after_copy','source_after_execution','source_final']):
        reasons.append('gui_execution_source_drift')
    differences=[]
    for rel,sha in historical.items():
        current=current_hashes.get(rel)
        if current is None and (PROJECT/rel).is_file(): current=digest(PROJECT/rel)
        if current!=sha: differences.append(rel)
    if differences: reasons.append('independent_gui_source_mismatch')
    row=next(r for r in gui['suites'] if r['suite']=='local_spell_restore_test')
    out=path.parent/'evidence/local_spell_restore_test.stdout.log'
    err=path.parent/'evidence/local_spell_restore_test.stderr.log'
    analysis=analyze(out.read_text(encoding='utf-8'),err.read_text(encoding='utf-8'),row['exit_code'])
    if not analysis['passed'] or (analysis['result'] or {}).get('checks')!=25: reasons.append('gui_protocol_or_exit')
    if row.get('headless') is not False or '--headless' in row['command'] or row['command'][-2:]!=['--','window']:
        reasons.append('gui_wrong_mode')
    proc=next(p for p in gui['processes'] if p['label']=='local_spell_restore_test')
    if not proc.get('exited') or proc.get('active_owned_processes')!=0 or not proc.get('log_handles_released'):
        reasons.append('gui_owned_exit_unverified')
    if any(not (path.parent/'evidence'/rel).is_file() or digest(path.parent/'evidence'/rel)!=sha
           for rel,sha in gui['evidence_hashes'].items()): reasons.append('gui_evidence_hash_mismatch')
    return {'suite':'local_spell_restore_test','verified':not reasons,'reasons':reasons,
            'manifest':str(path),'manifest_sha256':digest(path),'source_hashes':historical,
            'current_source_differences':differences,'checks':25,'exit':row['exit_code'],
            'command':row['command'],'process':proc,'analysis':analysis,
            'stdout_sha256':digest(out),'stderr_sha256':digest(err),'counts_as_headless_pass':False,
            'scope':'Independent same-source-hash real window25; not current headless suite or release PASS.'}


def round43_scene_preflight(selection, target, files):
    """Static inheritance/dependency evidence for the exact 70; execution still owns RESULT truth."""
    names=selection['headless']
    if len(names)!=70 or len(set(names))!=70 or 'local_spell_restore_test' in names:
        raise ValueError('exact unique headless70 required')
    target=Path(target)
    included={Path(p).as_posix() for p in files}
    rows=[];blockers=[]
    for name in names:
        pending=['tests/'+name+'.gd','tests/'+name+'.tscn'];closure=set();protocol=[];writes=[];roots=[]
        while pending:
            rel=pending.pop()
            if rel in closure: continue
            closure.add(rel)
            path=target/rel
            if rel not in included or not path.is_file():
                blockers.append({'suite':name,'path':rel,'reason':'required static dependency absent from freeze'})
                continue
            if path.suffix not in {'.gd','.tscn','.tres','.godot'}: continue
            text=path.read_text(encoding='utf-8-sig')
            for i,line in enumerate(text.splitlines(),1):
                if 'print(' in line and ('"RESULT' in line or "'RESULT" in line):
                    protocol.append({'path':rel,'line':i,'source':line.strip()})
                if any(token in line for token in ['FileAccess.WRITE','make_dir','store_string','save_png','rename_absolute','remove_absolute']):
                    writes.append({'path':rel,'line':i,'source':line.strip()})
                if any(token in line for token in ['get_cmdline_user_args','get_environment','user://','E:/','C:/']):
                    roots.append({'path':rel,'line':i,'source':line.strip()})
            output_refs=set(re.findall(r'save_png\("res://([^"\n]+)"',text))
            output_refs.update(re.findall(r'FileAccess\.open\("res://([^"\n]+)",\s*FileAccess\.WRITE',text))
            for ref in re.findall(r'res://([^\s\"\'<>]+)',text):
                if ref in output_refs: continue  # Declared generated output inside owned freeze, not an input.
                if not ref.endswith(('.gd','.tscn','.tres','.json','.png','.svg','.wav','.ogg')): continue
                if '%' in ref or '{' in ref: continue
                # All production bytes are explicitly included. Follow test-only resources as a closure.
                if ref.startswith('tests/'):
                    pending.append(ref)
                elif ref not in included or not (target/ref).is_file():
                    blockers.append({'suite':name,'path':ref,'reason':'required static resource absent from freeze'})
        if not protocol:
            blockers.append({'suite':name,'reason':'no inherited stdout RESULT producer'})
        if name in ROUND40_OUTPUT_ARGS:
            contract='explicit argv[0] physical E fixture; user:// and LOCALAPPDATA process-isolated'
            if not any('get_cmdline_user_args' in r['source'] for r in roots):
                blockers.append({'suite':name,'reason':'explicit argv root consumer missing'})
        else:
            contract='explicit per-process APPDATA/LOCALAPPDATA/FATE_TEST_SCRATCH_ROOT under owned physical E; res:// freeze only'
        effective={};overridden=[];chain=[];parent='tests/'+name+'.gd'
        while parent:
            if parent in chain: raise runner.SafetyError('inheritance cycle: '+parent)
            chain.append(parent)
            text=(target/parent).read_text(encoding='utf-8-sig')
            for block in re.split(r'(?m)(?=^func )',text):
                method=re.match(r'func (\w+)',block)
                if not method: continue
                if method[1] in effective:
                    overridden.append({'method':method[1],'parent':parent,'selected_owner':effective[method[1]]});continue
                effective[method[1]]=parent
                for line in block.splitlines():
                    if re.search(r'(?:root|directory|work|path|folder|cache)[\w.]*\s*(?::[^=]+)?=\s*"[A-Z]:/',line,re.I):
                        blockers.append({'suite':name,'path':parent,'method':method[1],
                                         'source':line.strip(),'reason':'effective absolute write root not owned or injected'})
            match=re.match(r'extends "res://(tests/[^"]+)"',text)
            parent=match[1] if match else None
        rows.append({'suite':name,'source_sha256':digest(target/('tests/'+name+'.gd')),
                     'effective_inheritance_chain':chain,'effective_method_owners':effective,'overridden_methods_not_invoked':overridden,
                     'test_dependencies':sorted(closure),'protocol_sources':protocol,
                     'protocol_gate':'one stdout RESULT; positive integer checks; empty failures; exit0; no unscoped ERROR',
                     'output_contract':contract,'output_root_sources':roots,'write_sources':writes,
                     'native_scope':'exact per-suite immutable helper/scope required; mandatory66 no SKIP' if name=='assembly_publish_lifecycle_test' else None})
    return {'suites':rows,'blockers':blockers,'passed':not blockers,
            'limit':'Static evidence does not execute or prove unique RESULT; overridden inherited methods retained for review.'}


def round43_continue_after(row, process, collect_failures=False):
    """Continue independent suites only after owned resource safety is proven."""
    if any(row.get(key) for key in ('frozen_drift','parallel_drift','current_vs_frozen')):
        return False
    if (process.get('exited') is not True or process.get('active_owned_processes') != 0
            or process.get('log_handles_released') is not True
            or process.get('budget_failure') not in (None, 'timeout')):
        return False
    if row.get('execution_error') not in (None, 'timeout'):
        return False
    return bool(row['passed'] or collect_failures)


def run_round40(round_number=40):
    parser_tests()
    prior_path = PROJECT/'reports/refactoring/round33-integrated-b9fbd2011963493eaf6b76f02032de1e/manifest.json'
    selection = ({43:build_round42_selection,42:build_round42_selection,41:build_round41_selection}.get(round_number,build_round40_selection))(load(prior_path))
    complete_only = round_number in {42,43} and '--complete-candidate' in sys.argv
    collect_failures = '--collect-failures' in sys.argv
    if collect_failures and (round_number != 43 or not complete_only):
        raise ValueError('collect-failures requires explicit Round43 complete candidate')
    if round_number == 43 and not complete_only:
        raise ValueError('Round43 requires explicit complete-candidate; no partial focused versions')
    if round_number == 43:
        selection['policy']='One freeze; worker45 prerequisite then exact70; explicit collect failures never relaxes gates.'
    root = runner.physical_e('E:/scratch')
    token = uuid.uuid4().hex
    owner = root/('isolated-'+token)
    owner.mkdir()
    generated = owner/'generated'
    generated.mkdir()
    archive = PROJECT/('reports/refactoring/round%d-integrated-' % round_number + token)
    archive.mkdir(parents=True)
    evidence = archive/'evidence'
    evidence.mkdir()
    history_dir = archive/'history'
    history_dir.mkdir()
    m = {'run_id':token,'round':round_number,'generated':str(generated),'archive':str(archive),
         'selection':selection,'selected_suites':selection['headless'],
         'focused_expected':[] if complete_only else selection['focused'],'focused':[],'suites':[],
         'processes':[],'cleanup':'not_started','claim':'candidate_only_not_final_delivery',
         'selection_inputs':[{'path':str(prior_path),'sha256':digest(prior_path)}]}
    m['stage'] = 'history'
    m['phase_policy'] = 'complete_only_current_freeze' if complete_only else 'focused_then_complete_current_freeze'
    m['collect_failures'] = collect_failures
    m['prerequisites'] = []
    save(owner/'manifest.json',m)
    env = os.environ.copy()
    for key, sub in [('TEMP','tmp'),('TMP','tmp'),('TMPDIR','tmp'),('APPDATA','appdata'),('LOCALAPPDATA','localappdata')]:
        (generated/sub).mkdir(exist_ok=True)
        env[key]=(generated/sub).as_posix()
    (generated/'localappdata/hermes/cache/scratch').mkdir(parents=True)
    fixtures=generated/'f'
    fixtures.mkdir()
    env['FATE_TEST_SCRATCH_ROOT']=fixtures.as_posix()
    for key in ['HERMES_RECOVERY_VALIDATION_ROOT','FATE_R39_CORRECTNESS','FATE_R39_SAVE_PREFLIGHT',
                'FATE_R36_FAULT','FD_RESTORE_TRANSACTION_TRACE','FD_RECOVERY_DIAGNOSTICS',
                'FD_GUARD_FIXTURE_REJECT_AUTH','FATE_TEST_IO_PREFLIGHT_FAIL']:
        env.pop(key,None)
    for key in list(env):
        if key.startswith('HERMES_ASSEMBLY_'):
            env.pop(key,None)
    budgets={'seconds':180,'bytes':8*1024**3,'min_free':1024**3}
    source_engine=Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe')
    m['source_engine_before_sha256'] = digest(source_engine)
    engine=generated/'Godot.exe'
    target=generated/'project'
    files=[]
    try:
        m['history']=round40_history(history_dir)
        m['selection_inputs']+=m['history']['inputs']
        includes=['project.godot','scripts','assets','data','game_data','addons','json_maker','icon.svg']
        if round_number in {42,43}:
            includes += round42_explicit_dependencies()
        for name in selection['names']:
            includes += ['tests/'+name+'.gd','tests/'+name+'.tscn']
        selected=set(runner.source_files(PROJECT,includes))
        pending=list(selected)
        while pending:
            rel=pending.pop()
            if rel.suffix not in {'.gd','.tscn','.tres','.godot'}: continue
            for ref in re.findall(r'res://(tests/[^\s\"\'<>]+)',(PROJECT/rel).read_text(encoding='utf-8-sig')):
                dep=Path(ref)
                if (PROJECT/dep).is_file() and dep not in selected:
                    runner.contained(PROJECT/dep,PROJECT)
                    selected.add(dep);pending.append(dep)
        files=sorted(selected)
        if round_number == 43:
            m['stage']='source_static_preflight'
            m['source_static_preflight']=round43_scene_preflight(selection,PROJECT,files)
            save(archive/'source-static-preflight.json',m['source_static_preflight'])
            if m['source_static_preflight']['blockers']: raise runner.SafetyError('source static preflight rejected')
            original42=PROJECT/'reports/refactoring/round42-integrated-68eeb9d161c54e47ab9e25b4fa18cc6b/manifest.json'
            if load(original42)['selected_suites']!=selection['headless']: raise runner.SafetyError('original70 selection differs')
            m['selection_inputs'].append({'path':str(original42),'sha256':digest(original42)})
            m['readonly_tools_before']={str(p):digest(p) for p in [PROJECT/'tools/run_isolated_godot_test.py',PROJECT/'tools/diagnostics/assembly_native_probe.py',Path(__file__)]}
        m['stage'] = 'freeze'
        m['freeze_before']=snapshot_hashes(files,PROJECT)
        target.mkdir()
        for rel in files:
            dest=target/rel;dest.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(PROJECT/rel,dest)
            if digest(dest)!=m['freeze_before'][rel.as_posix()]:
                raise runner.SafetyError('source drift while copying: '+str(rel))
        m['freeze_after']=snapshot_hashes(files,PROJECT)
        if m['freeze_after']!=m['freeze_before']: raise runner.SafetyError('source drift across freeze')
        m['source_files']=[{'path':p.as_posix(),'sha256':m['freeze_before'][p.as_posix()]} for p in files]
        config_path=target/'project.godot'
        config=config_path.read_text(encoding='utf-8-sig')
        if (PROJECT/'override.cfg').exists() or re.search(r'^\s*config/project_settings_override',config,re.M):
            raise runner.SafetyError('override refused')
        transformed,transform=transform_isolated_editor_vcs(config)
        config_path.write_text(transformed,encoding='utf-8',newline='')
        threading=re.search(r'^\[threading\]\s*\n(.*?)(?=^\[|\Z)',transformed,re.M|re.S)
        transform.update(authorized_paths=['project.godot'],
                         source_file_sha256=m['freeze_before']['project.godot'],
                         frozen_after_sha256=digest(config_path))
        transform['verified']=bool(threading and 'worker_pool/max_threads=20' in threading[0]
                 and threading[0] in config and digest(config_path)==transform['transformed_sha256'])
        m['editor_transform']=transform
        if not transform['verified']: raise runner.SafetyError('editor/threading transform unverified')
        expected=snapshot_hashes(files,target)
        m['frozen_hashes']=expected
        differences=[p for p in expected if expected[p]!=m['freeze_before'][p]]
        if differences!=['project.godot']: raise runner.SafetyError('unauthorized freeze differences')
        # Exact current source preflight: these legacy fixtures lack any explicit root consumer.
        blockers=[]
        for name, line, literal in [
            ('lobby_content_environment_restore_test',12,'E:/Projects/Godot/FateDomination/test/lobby-content-environment-'),
            ('net_blob_concurrent_test',9,'E:/Projects/Godot/FateDomination/test/concurrent-blob-')]:
            rel='tests/'+name+'.gd'
            text=(target/rel).read_text(encoding='utf-8')
            if literal in text:
                blockers.append({'suite':name,'path':rel,'line':line,'source_sha256':expected[rel],
                                 'reason':'unguarded absolute write root outside owned generated; no explicit root contract',
                                 'literal':literal})
        for b in blockers:
            b['owner_handoff'] = 'Main agent routes to unique game-test owner; integrated agent is read-only.'
            b['required_contract'] = 'OS.get_cmdline_user_args()[0], checked explicit physical E root; missing/unsafe root fails before any write.'
            b['authorized_output'] = (fixtures/('complete-'+str(selection['headless'].index(b['suite'])))).as_posix()
            b['suite_command_only_fix_possible'] = False
        m['full_safety_blockers']=blockers
        partition=round41_runnable_partition(selection['headless'],blockers)
        m['runnable_headless']=partition['runnable']
        m['blocked_not_run']=partition['blocked']
        save(archive/'output-root-owner-handoff.json',blockers)
        shutil.copyfile(source_engine,engine)
        m['engine_sha256']=digest(engine)
        if digest(source_engine)!=m['engine_sha256']: raise runner.SafetyError('engine copy mismatch')
        runner.physical_e(engine)
        if round_number in {42,43}:
            m['stage'] = 'static_preflight'
            m['native_scope'] = configure_assembly_scope(env,generated,fixtures,target,engine,token,archive)
            m['static_preflight'] = round42_static_preflight(selection,env,target)
            if round_number == 43:
                m['scene_static_preflight']=round43_scene_preflight(selection,target,files)
                save(archive/'scene-static-preflight.json',m['scene_static_preflight'])
                if m['scene_static_preflight']['blockers']: raise runner.SafetyError('whole70 static scene preflight rejected')
                m['gui_independent']=round43_gui_binding(m['freeze_before'])
                save(archive/'gui-independent-binding.json',m['gui_independent'])
                m['selection_inputs'].append({'path':m['gui_independent']['manifest'],'sha256':m['gui_independent']['manifest_sha256']})
            handoff = m['static_preflight']['fixture_owner_contract']
            m['selection_inputs'].append({'path':handoff['handoff'],'sha256':handoff['handoff_sha256']})
            blockers = m['static_preflight']['full_safety_blockers']
            m['full_safety_blockers'] = blockers
            partition = round41_runnable_partition(selection['headless'],blockers)
            m['runnable_headless'],m['blocked_not_run'] = partition['runnable'],partition['blocked']
            save(archive/'static-preflight.json',m['static_preflight'])
            save(archive/'output-root-owner-handoff.json',blockers)
            print(json.dumps({'static_preflight':m['static_preflight']},ensure_ascii=False),flush=True)
            if blockers:
                raise runner.SafetyError('whole-selection output-owner static preflight rejected before any suite')
        probe=generated/'probe';probe.mkdir()
        m['stage'] = 'main_child_probe'
        app=re.search(r'^\[application\]\s*\n(.*?)(?=^\[|\Z)',transformed,re.M|re.S)[1]
        (probe/'project.godot').write_text('config_version=5\n[application]\n'+app+'\n'+threading[0],encoding='utf-8')
        (probe/'probe.gd').write_text(runner.PROBE_SCRIPT,encoding='utf-8')
        out,err,code=runner.execute([engine.as_posix(),'--headless','--path',probe.as_posix(),
             '--script','res://probe.gd','--',token,'main',generated.as_posix()],env,generated,evidence,'probe',budgets,m['processes'])
        if code or 'ERROR:' in out+err: raise runner.SafetyError('real main/child probe failed')
        m['user_probes']=runner.verify_probe(out,generated,token)
        if any(x['worker_pool_max_threads']!=20 for x in m['user_probes']): raise runner.SafetyError('pool not 20')
        m['stage'] = 'import'
        out,err,code=runner.execute([engine.as_posix(),'--headless','--editor','--import','--path',target.as_posix()],
                                  env,generated,evidence,'import',budgets,m['processes'])
        m['import']={'exit':code,'errors':[x for x in (out+err).splitlines() if re.search(r'SCRIPT ERROR|SHADER ERROR|ERROR:',x)]}
        if code or m['import']['errors']: raise runner.SafetyError('current cold import rejected')
        phases = ([('prerequisite',['worker_content_environment_test']),('complete',selection['headless'])] if round_number == 43 else
                  [('complete',selection['headless'])] if complete_only else
                  [('focused',selection['focused']),('complete',partition['runnable'] if round_number == 41 else selection['headless'])])
        for phase,names in phases:
            m['stage'] = phase
            if phase=='complete':
                if round_number == 43 and (len(m['prerequisites'])!=1 or not m['prerequisites'][0]['passed']):
                    m['full_not_started']='worker45_prerequisite_failure';break
                if round_number in {42,43}:
                    pre_full_workers = archive_fixture_artifacts(fixtures,archive)
                    m['pre_full_worker_errors'] = fixture_engine_errors(pre_full_workers,archive)
                    m['pre_full_worker_classifications'] = [round42_dependency_worker_negative(archive,m,error)
                                                           for error in m['pre_full_worker_errors']]
                    if any(not x['verified'] for x in m['pre_full_worker_classifications']):
                        m['full_not_started']='focused_worker_error';break
                m['pre_full_drift']=[p for p,sha in m['freeze_before'].items() if digest(PROJECT/p)!=sha]
                if any(not r['passed'] for r in m['focused']):
                    m['full_not_started']='focused_failure';break
                if m['pre_full_drift']:
                    m['full_not_started']='source_drift';break
                if blockers and round_number != 41:
                    m['full_not_started']='unsafe_full_output_contract';break
            for index,name in enumerate(names):
                label=phase+'-'+name
                output_index = selection['headless'].index(name) if phase == 'complete' else index
                output=fixtures/(phase+'-'+str(output_index));output.mkdir()
                command=round40_command(engine,target,name,output)
                local=env.copy();budget=budgets.copy()
                if round_number == 43:
                    for key,sub in [('APPDATA','appdata'),('LOCALAPPDATA','localappdata')]:
                        (output/sub).mkdir();local[key]=(output/sub).as_posix()
                    (output/'localappdata/hermes/cache/scratch').mkdir(parents=True)
                    local['FATE_TEST_SCRATCH_ROOT']=output.as_posix()
                if round_number in {42,43} and name == 'assembly_publish_lifecycle_test':
                    scratch = output/'localappdata/hermes/cache/scratch'
                    scratch.mkdir(parents=True,exist_ok=True)
                    local['LOCALAPPDATA'] = (output/'localappdata').as_posix()
                    local['HERMES_RECOVERY_VALIDATION_ROOT'] = (scratch/('assembly-'+token)).as_posix()
                    configure_assembly_scope(local,generated,output,target,engine,token,archive,label)
                if name in ROUND40_LONG:
                    local['FATE_R39_CORRECTNESS']='1';budget['seconds']=600
                before=snapshot_hashes(files,PROJECT)
                frozen_before=snapshot_hashes(files,target)
                row={'suite':name,'phase':phase,'command':command,'fixture_root':output.as_posix(),
                     'source_before':before,'frozen_before':frozen_before,'budget':budget}
                if round_number in {42,43}:
                    row['explicit_environment'] = {k:v for k,v in local.items() if k.startswith('HERMES_ASSEMBLY_')
                                                   or k in {'APPDATA','LOCALAPPDATA','HERMES_RECOVERY_VALIDATION_ROOT','FATE_TEST_SCRATCH_ROOT'}}
                try:
                    out,err,code=runner.execute(command,local,generated,evidence,label,budget,m['processes'])
                    row.update(exit=code,**analyze_round40_suite(name,out,err,code,target,expected))
                except Exception as exc:
                    rec=m['processes'][-1]
                    out=(evidence/(label+'.stdout.log')).read_text(encoding='utf-8')
                    err=(evidence/(label+'.stderr.log')).read_text(encoding='utf-8')
                    row.update(exit=rec.get('exit_code'),**analyze(out,err,rec.get('exit_code')))
                    row.update(passed=False,execution_error=str(exc))
                row['source_after']=snapshot_hashes(files,PROJECT)
                row['frozen_after']=snapshot_hashes(files,target)
                row['parallel_drift']=[p for p in before if before[p]!=row['source_after'][p]]
                row['frozen_drift']=[p for p in expected if expected[p]!=row['frozen_after'][p]]
                row['current_vs_frozen']=[p for p in m['freeze_before'] if m['freeze_before'][p]!=row['source_after'][p]]
                if row['parallel_drift'] or row['frozen_drift'] or row['current_vs_frozen']:
                    row['passed']=False;row['reasons'].append('source_or_frozen_drift')
                m['focused' if phase=='focused' else 'prerequisites' if phase=='prerequisite' else 'suites'].append(row)
                save(owner/'manifest.json',m);save(archive/'manifest.json',m)
                print(json.dumps({'phase':phase,'suite':name,'exit':row['exit'],'passed':row['passed'],
                                  'result':row['result'],'reasons':row['reasons']},ensure_ascii=False),flush=True)
                if not row['passed']:
                    failed=evidence/'failed-source';failed.mkdir(exist_ok=True)
                    shutil.copyfile(target/('tests/'+name+'.gd'),failed/(label+'.gd'))
                    if round_number == 43:
                        dependencies=next(r['test_dependencies'] for r in m['scene_static_preflight']['suites'] if r['suite']==name)
                        trace_refs=re.findall(r'res://([\w/.-]+\.gd):',out+err)
                        row['minimal_original_input_sources']=[]
                        for rel in sorted(set(dependencies+trace_refs+['project.godot'])):
                            if rel not in expected or not (target/rel).is_file(): continue
                            dest=failed/label/rel;dest.parent.mkdir(parents=True,exist_ok=True)
                            shutil.copyfile(target/rel,dest)
                            row['minimal_original_input_sources'].append({'path':rel,'sha256':digest(dest),'matches_frozen':digest(dest)==expected[rel]})
                    if phase != 'complete' or not round43_continue_after(row,m['processes'][-1],collect_failures):
                        m['full_not_started']=('focused_failure' if phase=='focused' else 'complete_first_failure') if round_number!=43 else phase+'_failure_stop'
                        break
                elif round_number == 43 and not round43_continue_after(row,m['processes'][-1],collect_failures):
                    m['full_not_started']='shared_resource_safety_stop'
                    break
            if m.get('full_not_started'): break
        m['final_drift']=[p for p,sha in m['freeze_before'].items() if digest(PROJECT/p)!=sha]
    except Exception as exc:
        m['error']=type(exc).__name__+': '+str(exc)
        m.update(round42_stop(m['stage'],m['error'],m.get('prerequisites',[])+m['focused']+m['suites']))
        print(m['error'],flush=True)
    finally:
        # Retain real worker logs/receipts before consuming the owned UUID tree.
        if round_number in {42,43}:
            audit = generated/'native-audit'
            if audit.exists():
                shutil.copytree(audit,archive/'native-audit')
            native_path = PROJECT/'tools/diagnostics/assembly_native_probe.py'
            if native_path.is_file():
                m['native_helper_sha256'] = digest(native_path)
                shutil.copyfile(native_path,archive/'assembly_native_probe.py')
            m['native_audit_receipts'] = [{'path':str(p.relative_to(archive)), 'sha256':digest(p), 'receipt':load(p)}
                                        for p in sorted((archive/'native-audit').glob('*.json'))]
        worker_index=archive_fixture_artifacts(fixtures,archive)
        m['worker_artifacts']=worker_index
        # Worker logs are part of the gate, not silently separate from suite stdout.
        m['worker_engine_errors']=fixture_engine_errors(worker_index,archive)
        m['worker_scoped_negatives'] = []
        if round_number in {42,43}:
            for error in m['worker_engine_errors']:
                binding = round42_dependency_worker_negative(archive,m,error)
                if round_number == 43 and not binding['verified']:
                    binding = round43_bind_log_negative(archive,m,error)
                if binding['verified']:
                    m['worker_scoped_negatives'].append(dict(error=error,binding=binding))
            save(archive/'worker-scoped-negative-bindings.json',m['worker_scoped_negatives'])
        m['selection_inputs_unchanged']=all(digest(x['path'])==x['sha256'] for x in m['selection_inputs'])
        if round_number == 43:
            m['readonly_tools_after']={p:digest(p) for p in m.get('readonly_tools_before',{})}
            m['readonly_tool_drift']=[p for p,sha in m.get('readonly_tools_before',{}).items() if m['readonly_tools_after'][p]!=sha]
            row=next((r for r in m['suites'] if r['suite'] in ROUND40_LONG),None)
            if row:
                text=(evidence/'complete-net_server_gateway_restart_test.stdout.log').read_text(encoding='utf-8')
                performance=[json.loads(line.split(' ',1)[1]) for line in text.splitlines() if line.startswith('GATEWAY_PERFORMANCE_GATE ')]
                m['restart_current']={'runs':1,'correctness_budget_seconds':row['budget']['seconds'],
                    'correctness_passed':row['passed'],'exit':row['exit'],'performance_gate':performance,
                    'performance_passed':len(performance)==1 and performance[0].get('passed') is True,
                    'artifacts':[x for x in worker_index if len(Path(x['path']).parts)>1 and Path(x['path']).parts[1]=='complete-'+str(selection['headless'].index(row['suite']))]}
                readback=round43_restart_readback(archive,m,row)
                m['restart_current']['archive_readback']=readback
                m['restart_current']['final_save_readback']=readback['saved']
                if row['passed'] and not readback['verified']:
                    row['passed']=False;row['reasons'].append('restart_journal_save_archive_unverified')
        shutil.copyfile(__file__,archive/'aggregator.py')
        shutil.copyfile(PROJECT/'tools/tests/test_round40_selection.py',archive/'selection-tests.py')
        m['logs']=[{'path':str(p.relative_to(archive)),'sha256':digest(p),'bytes':p.stat().st_size}
                   for p in archive.rglob('*') if p.is_file() and p.name!='manifest.json']
        m['archive_verified']=all(digest(archive/x['path'])==x['sha256'] for x in m['logs']) and all(x['verified'] for x in worker_index)
        save(archive/'manifest.json',m);save(owner/'manifest.json',m)
        try:
            if not m['archive_verified']: raise runner.SafetyError('archive readback mismatch')
            if any(not x.get('exited') or x.get('active_owned_processes')!=0 or not x.get('log_handles_released') for x in m['processes']):
                raise runner.SafetyError('owned exit/release unverified')
            m['cleanup_no_launch'] = not m['processes']
            m['deleted_generated_bytes']=runner.tree_bytes(generated)
            runner.delete_owned(generated,owner)
            m['cleanup']='generated_removed'
            m['generated_exists_after_cleanup']=generated.exists()
            m['engine_source_unchanged']=digest(source_engine)==m['source_engine_before_sha256']
        except Exception as exc: m['cleanup']='retained: '+str(exc)
        m['summary']=summarize_round40(m)
        if len(m['worker_engine_errors']) != len(m['worker_scoped_negatives']):
            m['summary']['headless_source_candidate_PASS']=m['summary']['headless_candidate_passed']=m['summary']['passed']=False
            m['summary']['reasons'].append('worker_engine_error')
        m['passed']=m['summary']['passed']
        m.setdefault('stop_reason',m.get('full_not_started','completed'))
        save(archive/'manifest.json',m);save(owner/'manifest.json',m)
        report=PROJECT/('docs/round43-final-source-candidate.md' if round_number == 43 else
                        'docs/round42-integrated-probe.md' if round_number == 42 else 'docs/round%d-integrated.md' % round_number)
        lines=['# Round%d 整合候选（不是最终交付）' % round_number,'',
           '结论：headless_candidate_passed=%s；release_passed=false。' % m['passed'],
           'manifest：`%s`；所有权：`%s`。' % (archive/'manifest.json',owner/'manifest.json'),
           '命令：`python -B tools/tests/test_round29_integrated_evidence.py --round%d%s`；仅自有Windows Job PID，无窗口。' %
           (round_number,' --complete-candidate' if complete_only else ''),
           '阶段策略=%s；当前完整结果不充抵或合并任何历史focused记录。' % m['phase_policy'],
           '## 选择与分阶段结果',
           '原66项+显式新增后=%d；分类：pure_headless=%d，GUI=%d，长正确性=%d，精确bind负向=%d；要求headless集合=%d。' %
           (selection['selected_count'],len(selection['categories']['pure_headless']),len(ROUND40_GUI),len(ROUND40_LONG),len(ROUND40_NEGATIVE),len(selection['headless'])),
           '聚焦=%d/%d；完整回归实际=%d/%d（聚焦记录不充抵完整记录）；停止原因=%s。' %
           (m['summary']['focused_pass_count'],len(m['focused_expected']),len(m['suites']),len(selection['headless']),m['stop_reason']),
           '精确阶段=%s；前置错误=%s；实际聚焦执行数=%d；focused=0不代表业务PASS或FAIL。' % (m['stage'],m.get('error','none'),len(m['focused'])),
           'import：`%s`；最终源码漂移：`%s`。' % (json.dumps(m.get('import'),ensure_ascii=False),json.dumps(m.get('final_drift',[]),ensure_ascii=False)),
           '安全可运行headless=%d；未授权不得执行=%s；即使安全集合通过，也不将缺失套件升级为全候选PASS。' % (len(m.get('runnable_headless',[])),json.dumps(m.get('blocked_not_run',[]),ensure_ascii=False)),
           '完整选集及分类见manifest.selection；唯一新freeze，未修生产/游戏tests/generic runner。',
           '## 实际结果','|phase|suite|exit|checks|passed|原因|','|---|---|---:|---:|---|---|']
        for r in m.get('prerequisites',[])+m['focused']+m['suites']:
            lines.append('|%s|%s|%s|%s|%s|%s|' % (r['phase'],r['suite'],r['exit'],(r.get('result') or {}).get('checks'),r['passed'],';'.join(r['reasons'])))
            if not r['passed']:
                lines+=['精确失败：`%s`；原始RESULT=%s；错误=%s；源码与完整日志在evidence。' %
                        (r['suite'],json.dumps(r['result_lines'],ensure_ascii=False),json.dumps(r['errors'],ensure_ascii=False))]
        lines+=['## 完整回归输出根安全门','```json',json.dumps(m.get('full_safety_blockers',[]),ensure_ascii=False,indent=2),'```',
                '上述未提供显式输出根的只读夹具不得写副本外旧目录；未擅自变换源码、创建junction或降低隔离门。',
                '## GUI证据版本（不计本次PASS）','```json',json.dumps(m.get('history',{}).get('gui',{}),ensure_ascii=False,indent=2),'```',
                'local_spell_restore保留完整鼠标GUI边界，不重跑错误模式、不跳断言、不算headless功能失败或PASS。',
                '## Restart性能与完整正确性',
                '历史round39真实600s correctness exit0/61项与60s performance RED分列；原始日志已读回并绑定输入hash，source_bindings见manifest.history。不是本轮完整集合通过，也没有重复历史长计算。',
                '本轮完整阶段如启动，长场景仅执行一次600s correctness；当前实际次数=%d。' % sum(r['suite'] in ROUND40_LONG for r in m['suites']),
                '## 发行阻断与收尾',
                'native冷import发行仍阻断：round39已证宿主EditorHelp cleanup后deferred doc->generate空对象异常0xC0000005；无新正式DLL/两次fresh GREEN/export。当前整合headless import不替代发行冷导入门。',
                '未完成GUI执行时版本绑定、实际GUI/发行EXE/跨机/跨网；引擎修复分支仍需用户确认；不叫最终交付或发行GREEN。',
                'cleanup=%s；generated_exists=%s；源engine未变=%s；先归档摘要读回=%s。' %
                (m['cleanup'],m.get('generated_exists_after_cleanup'),m.get('engine_source_unchanged'),m['archive_verified']),
                '汇总拒绝原因：`%s`；worker错误：`%s`。' % (json.dumps(m['summary']['reasons'],ensure_ascii=False),json.dumps(m['worker_engine_errors'],ensure_ascii=False))]
        if round_number in {42,43}:
            lines += ['## 当前原生授权与精确负向分类',
                      '统一静态预检在所有suite之前完成；显式Python仅作只读安装解释器，所有生成/fixture/source/引擎根要求无链接物理E。',
                      '当前 helper SHA256=`%s`；原生调用回执=%d。scope原字节、环境、argv、父PID/创建时间/Job成员、7份scan/2份identity/1份lock回执均独立保留。' %
                      (m.get('native_helper_sha256'),len(m.get('native_audit_receipts',[]))),
                      'assembly必需66项门未改；出现ASSEMBLY_NATIVE_SKIP即拒绝。历史round38日志不计本轮PASS。',
                      'child ERROR原始列表原样保留，strict拒绝仍false；只对源码hash、34项唯一RESULT、单卡manifest、完整两段回溯、负向report及自有Job退出全部相符的dependencies分支分类。任何额外ERROR、坏hash/manifest或不同suite均不豁免。',
                      '```json',json.dumps(m.get('worker_scoped_negatives',[]),ensure_ascii=False,indent=2),'```']
        if round_number == 43:
            summary=m['summary']
            lines[0]='# Round43 完整源码候选（非发行PASS）'
            lines[2]='headless_source_candidate_PASS=%s；release_passed=false；Q03 Godot冷native导入引擎阻断仍在。' % summary['headless_source_candidate_PASS']
            lines += ['## 当前完整70计数与全部RED',
                '实际=%d/70；unique=%d；分类通过=%d；严格零ERROR通过=%d；合法RESULT checks=%d；原始CHECK=%d；原始ERROR/失败行=%d。' % (summary['actual_count'],len({r['suite'] for r in m['suites']}),summary['pass_count'],summary['strict_pass_count'],summary['checks_total'],summary['observed_check_total'],summary['error_count']),
                '未执行=%s；所有当前RED=%s；collect_failures=%s。' % (json.dumps(summary['missing'],ensure_ascii=False),json.dumps(summary['failed'],ensure_ascii=False),m['collect_failures']),
                'worker45前置仅列prerequisites，不充抵完整70。每套独立进程/Job及独占APPDATA、LOCALAPPDATA、FATE_TEST_SCRATCH_ROOT；单套内部失败不从聚合器启动后续业务或重试。',
                '静态先检查当前全70的输出根/继承依赖/协议生产者，再验证唯一freeze当前native scope；单元fail1继续pass2但整体false，默认仍failfast。',
                '历史Round42 39记录原字节不变，仅复用选择名字；本轮没有第二freeze或多版本partial绿。',
                '## 当前独立同hash GUI（不计headlessPASS）',
                'verified=%s；checks=%s；exit=%s；2075依赖当前差异=%s；manifest=%s。' % (m.get('gui_independent',{}).get('verified'),m.get('gui_independent',{}).get('checks'),m.get('gui_independent',{}).get('exit'),json.dumps(m.get('gui_independent',{}).get('current_source_differences'),ensure_ascii=False),m.get('gui_independent',{}).get('manifest')),
                '窗口原命令、PID、hash及零ERROR重解析在gui-independent-binding.json；只复核已有真实非headless25，不造新窗口执行。',
                '## 当前restart正确性/性能/原journal-save',
                '```json',json.dumps({k:v for k,v in m.get('restart_current',{}).items() if k!='artifacts'},ensure_ascii=False,indent=2),'```',
                'correctness仅本轮完整集合一次600s，不放宽61门；performance原60s独立判定，RED不改成GREEN。journal、control请求/回执、recovery、终局save与恢复comparison归档worker树，save记录的journal SHA逐字节读回。',
                '## 最小原输入、退出与回收']
            for row in m.get('prerequisites',[])+m['suites']:
                if row['passed']: continue
                lines += ['### '+row['phase']+' / '+row['suite'],
                    '实际原argv：`'+json.dumps(row['command'],ensure_ascii=False)+'`',
                    'exit=%s；reasons=%s；execution_error=%s；budget=%s。' % (row['exit'],json.dumps(row['reasons'],ensure_ascii=False),row.get('execution_error'),json.dumps(row['budget'])),
                    '完整RESULT='+json.dumps(row['result_lines'],ensure_ascii=False),
                    '全部原ERROR/FAIL='+json.dumps(row['errors'],ensure_ascii=False),
                    '最小原源码输入及hash：```json\n'+json.dumps(row.get('minimal_original_input_sources',[]),ensure_ascii=False,indent=2)+'\n```',
                    '完整stdout/stderr=evidence/'+row['phase']+'-'+row['suite']+'.*.log；派生回执见worker/；不修改原输入修下一红。']
            lines += ['所有自有根/派生进程退出、ActiveProcesses0及日志句柄释放='+str(all(p.get('exited') and p.get('active_owned_processes')==0 and p.get('log_handles_released') for p in m['processes'])),
                      '只读production/游戏tests/generic runner/native helper未改；工具漂移='+json.dumps(m.get('readonly_tool_drift',[]))+'；source/freeze前后hash见manifest。',
                      '归档读回=%s；回收=%s；生成树残留=%s；删除字节=%s；源引擎不变=%s。' % (m['archive_verified'],m['cleanup'],m.get('generated_exists_after_cleanup'),m.get('deleted_generated_bytes'),m.get('engine_source_unchanged'))]
        report.write_text('\n'.join(lines)+'\n',encoding='utf-8')
        print(json.dumps({'manifest':str(archive/'manifest.json'),'report':str(report),**m['summary']},ensure_ascii=False),flush=True)
    return 0 if m['passed'] else 1


ROUND50_BASE_MANIFEST = 'reports/refactoring/round42-integrated-68eeb9d161c54e47ab9e25b4fa18cc6b/manifest.json'
# Explicit landed scenes only. Helpers are dependency inputs, never extra suite credit.
ROUND50_ADDITIONS = [
    'round47_host_lifecycle_test', 'round47_host_lifecycle_board_test',
    'round47_presenter_power_test', 'server_data_status_inbox_contract_test',
    'server_data_status_inbox_approval_test', 'deployment_approved_root_test',
    'server_simulation_default_budget_test', 'validation_countdown_contract_test',
    'server_validation_countdown_test', 'round47_public_test_observer_test',
    'command_spell_test', 'ask_player_option_test', 'requirement_null_test',
    'session_restart_test', 'debug_console_pause_test',
    'round47_worker_launch_route_test', 'round47_worker_launch_lifecycle_test',
    'round50_validation_launch_route_test', 'net_server_cli_test',
    'round50_finished_lobby_receipt_test', 'round50_finished_lobby_tight_test',
    'net_server_cli_p2p_test', 'net_server_identity_cli_test',
    'net_server_cfg_test', 'net_server_relay_cfg_test',
    'validation_pipeline_performance_test', 'validation_stage_timing_test',
    'server_shutdown_close_handoff_test', 'server_shutdown_close_handoff_pending_test',
    'net_server_shutdown_failure_test', 'loader_error_boundary_test',
]
ROUND50_CURRENT_CHECKS = {
    'server_shutdown_close_handoff_test': 86,
    'server_shutdown_close_handoff_pending_test': 36,
    'net_server_shutdown_failure_test': 161,
}

# Round58 names/counts only, never historical PASS credit. Interrupted totals
# are bounded by preserved fixtures (end38/round28=66/activation21)
# or later complete RESULT samples (groups43/relay22). Restart stays61.
# Groups43 is a later sample floor, NOT a fabricated Round58 RESULT total.
ROUND64_BASELINE_CHECKS = {
    'assembly_publish_lifecycle_test': 66,
    'round28-command-migration_test': 66,
    'battle_board_end_command_test': 38,
    'battle_board_activation_command_test': 21,
    'active_choice_source_command_test': 65,
    'card_choice_source_command_test': 18,
    'location_choice_source_command_test': 37,
    'battle_command_adapter_test': 29,
    'match_command_dispatcher_test': 313,
    'match_command_result_protocol_test': 39,
    'match_commands_test': 17,
    'net_pending_test': 20,
    'net_cards_test': 7,
    'net_move_test': 11,
    'net_locations_test': 7,
    'net_authority_ui_preview_feedback_test': 8,
    'battle_board_v2_test': 53,
    'battle_play_groups_test': 43,
    'deploy_rules_layer_test': 22,
    'mana_spend_test': 45,
    'regular_play_test': 54,
    'player_choice_source_command_test': 65,
    'client_identity_inbox_contract_test': 58,
    'host_room_inbox_contract_test': 34,
    'net_selection_settings_test': 7,
    'net_runtime_guard_test': 34,
    'net_resume_identity_test': 26,
    'gateway_deferred_test': 16,
    'gateway_disconnect_safe_close_test': 7,
    'gateway_instance_binding_test': 20,
    'net_server_gateway_test': 19,
    'net_server_gateway_restart_test': 61,
    'net_data_validation_test': 13,
    'net_validation_io_feedback_test': 23,
    'net_validation_io_measure_test': 9,
    'net_background_validation_feedback_test': 25,
    'net_server_discovery_validation_test': 33,
    'content_environment_test': 30,
    'worker_content_environment_test': 45,
    'gateway_relisten_acceptance_test': 38,
    'net_validation_task_test': 31,
    'net_validation_simulation_test': 35,
    'net_validation_hard_timeout_test': 37,
    'net_parallel_validation_feedback_test': 9,
    'room_data_preparation_consumer_test': 50,
    'room_data_preparation_dependencies_test': 34,
    'lobby_content_environment_restore_test': 1544,
    'net_data_sync_test': 14,
    'net_blob_test': 42,
    'net_blob_authorization_test': 58,
    'net_blob_send_authorization_test': 14,
    'net_blob_concurrent_test': 20,
    'net_worker_startup_contract_test': 15,
    'host_guard_inbox_contract_test': 72,
    'net_guard_rollback_test': 39,
    'rule_guard_root_transaction_v2_test': 115,
    'rule_guard_rollback_test': 19,
    'rule_guard_chain_rollback_test': 17,
    'rule_guard_continuation_occurrence_test': 54,
    'round29-shared-presentation_test': 142,
    'shared_spell_view_contract_test': 87,
    'mirror_spell_negative_test': 73,
    'match_view_test': 226,
    'match_view_privacy_test': 137,
    'client_match_inbox_contract_test': 45,
    'gateway_bind_failure_test': 7,
    'newspecial_spell_materialization_test': 13,
    'command_spell_source_activation_test': 54,
    'round39_restore_transaction_test': 61,
    'validation_checkpoint_reader_test': 10,
    'round47_host_lifecycle_test': 33,
    'round47_host_lifecycle_board_test': 14,
    'round47_presenter_power_test': 23,
    'server_data_status_inbox_contract_test': 65,
    'server_data_status_inbox_approval_test': 22,
    'deployment_approved_root_test': 47,
    'server_simulation_default_budget_test': 13,
    'validation_countdown_contract_test': 21,
    'round47_public_test_observer_test': 7,
    'command_spell_test': 61,
    'ask_player_option_test': 16,
    'requirement_null_test': 14,
    'session_restart_test': 30,
    'debug_console_pause_test': 15,
    'round47_worker_launch_route_test': 22,
    'round47_worker_launch_lifecycle_test': 39,
    'round50_validation_launch_route_test': 16,
    'net_server_cli_test': 11,
    'round50_finished_lobby_receipt_test': 16,
    'net_server_cli_p2p_test': 13,
    'net_server_identity_cli_test': 22,
    'net_server_cfg_test': 18,
    'net_server_relay_cfg_test': 22,
    'validation_pipeline_performance_test': 259,
    'validation_stage_timing_test': 23,
    'server_shutdown_close_handoff_test': 86,
    'server_shutdown_close_handoff_pending_test': 36,
    'net_server_shutdown_failure_test': 161,
}
ROUND64_REFRESHED_CHECKS = {'battle_board_end_command_test': 46, 'round28-command-migration_test': 74, 'battle_board_activation_command_test': 21, 'active_choice_source_command_test': 65, 'location_choice_source_command_test': 37, 'player_choice_source_command_test': 65, 'battle_play_groups_test': 56, 'loader_error_boundary_test': 62}
ROUND64_MIGRATED_SIX = ['battle_board_end_command_test','round28-command-migration_test',
    'battle_board_activation_command_test','active_choice_source_command_test',
    'location_choice_source_command_test','player_choice_source_command_test']
ROUND64_LOADER_MODES = [
    {'suite':'loader_error_boundary_test','mode':mode,'expected_checks':9,
     'counts_as_formal_scene':False,'execution_status':'not_run',
     'runner':'tests/round62_loader_error_boundary_runner.py',
     'policy':'exact scoped six errors only; extra mode must reject extra real error'}
    for mode in ['expectednegative','expectednegative_extra']]


def round64_mandatory_checks():
    groups=[ROUND64_BASELINE_CHECKS,ROUND40_EXPECTED_CHECKS,ROUND50_CURRENT_CHECKS,ROUND64_REFRESHED_CHECKS]
    return {name:max(group.get(name,0) for group in groups) for name in set().union(*groups)}


# The actual runner's extraction branch is adapted at the caller boundary.
# Its generated helper belongs only to the independent diagnostic project.
ROUND50_EXTRACTED_HARNESSES = {
    'round50_finished_lobby_tight_test': {
        'kind': 'extracted_harness',
        'helper': 'tight_session.gd',
        'archive': 'tight_session_extracted.gd',
        'runner': 'tests/round50_finished_lobby_receipt_runner.py',
        'parent': 'scripts/net/session/lobby_session.gd',
        'archive_hash_required': True,
        'counts_as_formal_scene': False,
        'required': True,
        'expected_checks': 6,
    },
}


def round50_source_fingerprint(hashes):
    return hashlib.sha256(json.dumps(hashes, sort_keys=True, separators=(',', ':')).encode('utf-8')).hexdigest()


def round50_extraction_callable(source):
    """Adapt the real inline tight branch, not a second extraction implementation.

    The runner has no public source-root argument. Compile only its extraction
    body, with caller-owned freeze/run paths; never invoke main/copy/live roots.
    No subprocess, imports or unrelated runner statements enter this callable.
    """
    import ast
    tree = ast.parse(source)
    mains = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'main']
    if len(mains) != 1: raise runner.SafetyError('actual extraction main missing/ambiguous')
    branches = [n for n in mains[0].body if isinstance(n, ast.If)
                and ast.unparse(n.test) == "args.suite == 'tight'"
                and any(isinstance(x, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'shim'
                                                        for t in x.targets) for x in n.body)]
    if len(branches) != 1: raise runner.SafetyError('actual tight extraction branch missing/ambiguous')
    branch = branches[0]
    if branch.orelse: raise runner.SafetyError('unsupported extraction else branch')
    body = ast.Module(body=branch.body, type_ignores=[])
    stored = {n.id for n in ast.walk(body) if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Store)}
    loaded = {n.id for n in ast.walk(body) if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Load)}
    if loaded - stored - {'freeze', 'run', 're', 'RuntimeError'}:
        raise runner.SafetyError('unsupported actual extraction scope dependencies')
    if any(isinstance(n, (ast.Import, ast.ImportFrom, ast.FunctionDef, ast.ClassDef, ast.Global, ast.Nonlocal))
           for n in ast.walk(body)):
        raise runner.SafetyError('unsupported extraction API shape')
    accesses=[]
    for node in ast.walk(body):
        if not isinstance(node,ast.Call) or not isinstance(node.func,ast.Attribute): continue
        if node.func.attr not in {'read_text','write_text'}: continue
        path=node.func.value
        if (not isinstance(path,ast.BinOp) or not isinstance(path.op,ast.Div)
                or not isinstance(path.left,ast.Name) or not isinstance(path.right,ast.Constant)
                or not isinstance(path.right.value,str)):
            raise runner.SafetyError('unsupported actual extraction path scope')
        accesses.append((path.left.id,path.right.value,node.func.attr))
    expected_accesses=[('freeze','project.godot','write_text'),
        ('freeze','scripts/net/session/lobby_session.gd','read_text'),
        ('freeze','tight_session.gd','write_text'),('run','tight_session_extracted.gd','write_text')]
    if sorted(accesses)!=sorted(expected_accesses):
        raise runner.SafetyError('actual extraction file scope changed; owner API handoff required')
    names = [n.value for n in branch.body if isinstance(n, ast.Assign)
             and any(isinstance(t, ast.Name) and t.id == 'names' for t in n.targets)]
    if len(names) != 1: raise runner.SafetyError('actual extraction function list missing')
    functions = ast.literal_eval(names[0])
    if not isinstance(functions, tuple) or not functions or any(not isinstance(n,str) for n in functions):
        raise runner.SafetyError('actual extraction function list invalid')
    text = source.decode('utf-8-sig') if isinstance(source, bytes) else source
    segment = ast.get_source_segment(text, branch)
    code = compile(body, 'frozen-round50-runner-tight-extraction', 'exec')
    def extract(freeze, archive):
        exec(code, {'__builtins__':{'RuntimeError':RuntimeError}, 're':re,
                    'freeze':Path(freeze), 'run':Path(archive)})
    return extract, {'api_kind':'caller_adapter_actual_tight_branch',
        'runner_sha256':hashlib.sha256(source if isinstance(source,bytes) else source.encode('utf-8')).hexdigest(),
        'extraction_branch_sha256':hashlib.sha256(segment.encode('utf-8')).hexdigest(),
        'functions':list(functions), 'scope_dependencies':['freeze','run','re'],
        'authorized_file_accesses':[list(item) for item in accesses],
        'live_project_main_called':False}


def round50_verify_harness_archive(archive, index):
    try:
        if not index or len({i['path'] for i in index}) != len(index): return False
        for item in index:
            rel = Path(item['path'])
            if rel.is_absolute() or '..' in rel.parts: return False
            path = runner.contained(Path(archive)/rel, archive)
            if not path.is_file() or digest(path) != item['sha256']: return False
        return True
    except (OSError, ValueError, KeyError, runner.SafetyError):
        return False


def summarize_round50_harnesses(m):
    expected = [r['suite'] for r in m['selection']['required_harness_steps']]
    rows = m.get('required_harness_steps', [])
    names = [r['suite'] for r in rows]
    not_run = [n for n in expected if not any(r['suite']==n and r.get('execution_status')=='executed' for r in rows)]
    reasons = []
    if len(names)!=len(set(names)) or set(names)!=set(expected): reasons.append('required_harness_incomplete_or_duplicate')
    if not_run: reasons.append('required_harness_not_run')
    for row in rows:
        if row.get('passed') is not True: reasons.append('required_harness_failed')
        if row.get('archive_verified') is not True: reasons.append('required_harness_archive_unverified')
        if (row.get('same_freeze_verified') is not True or not m.get('parent_source_fingerprint')
                or row.get('parent_source_fingerprint') != m['parent_source_fingerprint']):
            reasons.append('required_harness_parent_fingerprint_mismatch')
    return {'passed':not reasons, 'reasons':list(dict.fromkeys(reasons)), 'not_run':not_run,
            'required_count':len(expected), 'executed_count':sum(r.get('execution_status')=='executed' for r in rows),
            'pass_count':sum(r.get('passed') is True for r in rows)}


def summarize_round50_current(m):
    summary=summarize_integrated(m)
    harness=summarize_round50_harnesses(m)
    summary['required_harness']=harness
    if not harness['passed']:
        summary['passed']=False;summary['reasons'].extend(harness['reasons'])
    if len(m.get('worker_engine_errors',[])) != len(m.get('worker_scoped_negatives',[])):
        summary['passed']=False;summary['reasons'].append('unscoped_worker_engine_error')
    if len(m.get('prerequisites',[]))!=1 or not m['prerequisites'][0]['passed']:
        summary['passed']=False;summary['reasons'].append('worker45_prerequisite_missing_or_failed')
    if m.get('scheduler') is not None and m.get('scheduler_accounted') is not True:
        summary['passed']=False;summary['reasons'].append('scheduler_accounting_unverified')
    summary.update(sourcePASS=False,releasePASS=False,gui_executed=False,native_standalone_executed=False)
    return summary


def run_round50_harness(target, engine, env, generated, evidence, budgets, processes, hashes):
    """Required independent scene under this caller's frozen source fingerprint."""
    name = 'round50_finished_lobby_tight_test'
    definition = ROUND50_EXTRACTED_HARNESSES[name]
    fingerprint = round50_source_fingerprint(hashes)
    row = {'suite':name, 'execution_status':'not_run', 'passed':False,
           'parent_source_fingerprint':fingerprint, 'archive_verified':False,
           'same_freeze_verified':False, 'counts_as_formal_scene':False, 'reasons':[]}
    generated=runner.physical_e(generated)
    evidence=runner.physical_e(evidence)
    diag = generated/'diagnostics'/name
    archive = evidence/'harness'/name
    runner.no_links(diag);runner.no_links(archive)
    diag.mkdir(parents=True);archive.mkdir(parents=True)
    diag=runner.contained(diag,generated);archive=runner.contained(archive,evidence)
    process_start=len(processes)
    inputs = [definition['parent'], definition['runner'], 'tests/'+name+'.gd', 'tests/'+name+'.tscn']
    try:
        for rel in inputs:
            source = runner.contained(Path(target)/rel, target)
            if digest(source) != hashes.get(rel): raise runner.SafetyError('harness frozen input drift: '+rel)
            dest=diag/rel;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,dest)
            saved=archive/'source'/rel;saved.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,saved)
        extract, api = round50_extraction_callable((diag/definition['runner']).read_bytes())
        row['extraction_api']=api
        extract(diag, archive)
        if digest(diag/definition['helper']) != digest(archive/definition['archive']):
            raise runner.SafetyError('extraction helper/archive mismatch')
        row['helper_sha256']=digest(diag/definition['helper'])
        row['source_sha256']=hashes[definition['parent']]
        identity=assembly_native_module().process_identity(os.getpid())
        scope={'parent_source_fingerprint':fingerprint, 'parent_source_hashes':hashes,
               'source_root':Path(target).as_posix(),'diagnostic_root':diag.as_posix(),
               'generated_root':Path(generated).as_posix(),'archive_root':archive.as_posix(),
               'source_sha256':row['source_sha256'],'helper_sha256':row['helper_sha256'],
               'engine_sha256':digest(engine),'owner_pid':os.getpid(),
               'owner_creation':identity['creation'], 'api':api,
               'formal_project_helper_created':(Path(target)/definition['helper']).exists()}
        if scope['formal_project_helper_created']: raise runner.SafetyError('helper leaked into formal project')
        save(archive/'scope.json',scope)
        row['archive_index']=[{'path':p.relative_to(archive).as_posix(),'sha256':digest(p)}
                              for p in sorted(archive.rglob('*')) if p.is_file()]
        row['archive']=archive.as_posix()
        row['archive_verified']=round50_verify_harness_archive(archive,row['archive_index'])
        if not row['archive_verified']: raise runner.SafetyError('harness archive invalid before execution')
        local=env.copy()
        for key,sub in [('APPDATA','appdata'),('LOCALAPPDATA','localappdata'),('TEMP','tmp'),('TMP','tmp'),('TMPDIR','tmp')]:
            directory=diag/sub;directory.mkdir(exist_ok=True);local[key]=directory.as_posix()
        local['FATE_TEST_SCRATCH_ROOT']=diag.as_posix()
        command=[Path(engine).as_posix(),'--headless','--fixed-fps','60','--path',diag.as_posix(),
                 '--scene','res://tests/'+name+'.tscn']
        row['command']=command
        out,err,code=runner.execute(command,local,generated,evidence,'required-'+name,dict(budgets,seconds=180),processes)
        row.update(exit=code, execution_status='executed', **analyze(out,err,code))
        paths=[line[len('ACTUAL_USER_PATH '):] for line in out.splitlines() if line.startswith('ACTUAL_USER_PATH ')]
        row['actual_user_paths']=paths
        row['user_isolated']=len(paths)==1 and runner.physical_e(paths[0]).is_relative_to(diag.resolve())
        owned=processes[-1]
        row['owned_exit_verified']=bool(owned.get('exited') and owned.get('active_owned_processes')==0
                                       and owned.get('log_handles_released') is True)
        row['same_freeze_verified']=all(digest(Path(target)/rel)==hashes[rel]
            and digest(diag/rel)==hashes[rel] for rel in inputs)
        row['same_freeze_verified']=bool(row['same_freeze_verified']
            and digest(diag/definition['helper'])==row['helper_sha256']
            and digest(engine)==scope['engine_sha256'])
        row['archive_verified']=round50_verify_harness_archive(archive,row['archive_index'])
        if (not row['user_isolated'] or not row['owned_exit_verified'] or not row['same_freeze_verified']
                or not row['archive_verified'] or (row.get('result') or {}).get('checks')!=6
                or row['observed_checks']!=6):
            row['passed']=False;row['reasons'].append('required_harness_contract_unverified')
    except Exception as exc:
        launched=[p for p in processes[process_start:] if p.get('label')=='required-'+name]
        if launched:
            row['execution_status']='executed'
            row['exit']=launched[-1].get('exit_code')
            stdout=evidence/('required-'+name+'.stdout.log')
            stderr=evidence/('required-'+name+'.stderr.log')
            if stdout.is_file() and stderr.is_file():
                row.update(analyze(stdout.read_text(encoding='utf-8'),stderr.read_text(encoding='utf-8'),row['exit']))
        row['passed']=False;row['reasons'].append(type(exc).__name__+': '+str(exc))
    save(archive/'step.json',row)
    print(json.dumps({'required_harness_step':row},ensure_ascii=False),flush=True)
    return row


ROUND70_REQUIRED_CHECKS = {'round70_declared_card_backs_test':320,
    'view_builder_non_card_objects_test':11,'match_view_privacy_test':137,'mirror_spell_negative_test':94}
ROUND70_APPROVED_PRODUCERS = {
    'scripts/match/view_builder.gd':'78607bec727a0698e81370e33e988caa0b41def226a04f5e13bd4b8e6567ca8e',
    'scripts/match/view_mirror.gd':'8007a3cc6e2e1ed0bb319ba3e1b3bd21fb825e7b9bc24f3f212a724c514eef20',
}
ROUND70_APPROVED_TESTS = {
    'tests/round70_declared_card_backs_test.gd':'dffa7a4c70371f9489e690f276fbfc08d739bdee4f8ddc85bfa95a8aaa8fc78e',
    'tests/round70_declared_card_backs_test.tscn':'1aa08a57c6a84de44b35620c92e1910508e4f6fb4c079bd071fde1bc394d1de2',
    'tests/match_view_privacy_test.gd':'291b62fdd3d311da0849634c287c1780dfddf5580fce3be296e3724f0d3e4766',
    'tests/mirror_spell_negative_test.gd':'1fdac36d68d00c6a914f90faf62adeb4f6943239185dc32c8709247616e54379',
    'tests/view_builder_non_card_objects_test.gd':'b4106fab3cfd41b35fc82a122eba0158d4e25d8a0a5f9b4de54640765640dce5',
    'tests/view_builder_non_card_objects_test.tscn':'d5a819bc6d9a0d9deca9f7529f4b49bab669b06b2e86c0217ce1fd1b6c6f23a7',
}


def build_round50_selection(old, project=PROJECT, current_approved=False):
    if len(ROUND50_ADDITIONS)!=len(set(ROUND50_ADDITIONS)):
        raise ValueError('duplicate declared candidate addition')
    selected = old['selected_suites']
    prior = old['selection']
    if (len(selected) != 70 or len(set(selected)) != 70 or
            prior['headless'] != selected or len(prior['names']) != 71 or
            len(set(prior['names'])) != 71 or
            set(prior['names']) != set(selected) | {'local_spell_restore_test'}):
        raise ValueError('current original unique70/GUI selection manifest required; not historical results')
    root = Path(project)
    names, blocked, extracted_harnesses, required_steps = list(prior['names']), [], [], []
    for name in ROUND50_ADDITIONS + ([n for n in ROUND70_REQUIRED_CHECKS if n not in prior['names'] and n not in ROUND50_ADDITIONS] if current_approved else []):
        harness = ROUND50_EXTRACTED_HARNESSES.get(name)
        if harness is not None:
            required = [harness['parent'],harness['runner'],'tests/'+name+'.gd','tests/'+name+'.tscn']
            missing = [rel for rel in required if not (root/rel).is_file()]
            row = {'suite':name,'execution_contract':dict(harness),'execution_status':'not_run'}
            required_steps.append(row)
            if missing:
                rejected=dict(row,reason='extracted_harness inputs not landed',missing=missing)
                blocked.append(rejected);extracted_harnesses.append(rejected)
            continue
        missing = ['tests/' + name + suffix for suffix in ('.gd', '.tscn')
                   if not (root / ('tests/' + name + suffix)).is_file()]
        if not missing:
            text=(root/('tests/'+name+'.gd')).read_text(encoding='utf-8-sig')
            missing=[ref for ref in re.findall(r'(?:preload|load)\(\s*["\']res://([^"\']+)',text)
                     if not (root/ref).is_file()]
        if missing:
            blocked.append({'suite':name, 'reason':'not landed', 'missing':missing})
        elif name not in names:
            names.append(name)
    accounted=set(names)|{r['suite'] for r in blocked}
    for missing in sorted(set(ROUND64_BASELINE_CHECKS)-accounted):
        blocked.append({'suite':missing,'reason':'original98 selection omitted from current declaration','missing':[]})
    categories = {'short_headless':[], 'native_integration':[], 'gui_required':[],
                  'long_correctness':[], 'performance':[], 'known_engine_negative':[]}
    for name in names:
        mode = ('gui_required' if name in {'local_spell_restore_test','server_validation_countdown_test'} else
                'native_integration' if name == 'assembly_publish_lifecycle_test' else
                'long_correctness' if name in {'net_server_gateway_restart_test','round47_host_lifecycle_board_test'} else
                'performance' if name in {'validation_pipeline_performance_test','validation_stage_timing_test'} else
                'known_engine_negative' if name == 'gateway_bind_failure_test' else 'short_headless')
        categories[mode].append(name)
    headless = list(selected) + [n for n in names if n not in selected and n not in categories['gui_required']]
    result = {'names':names, 'headless':headless, 'categories':categories,
            'selected_count':len(names), 'headless_count':len(headless),
            'baseline_headless_count':len(selected), 'blocked_not_landed':blocked,
            'blocked_extracted_harness':extracted_harnesses,
            'required_harness_steps':required_steps,
            'extracted_harness_contracts':[row['execution_contract'] for row in required_steps],
            'formal_scene_checks':{'round50_finished_lobby_receipt_test':16,
                                   'round47_host_lifecycle_board_test':14},
            'mandatory_checks':round64_mandatory_checks(),
            'baseline_minimum_checks':dict(ROUND64_BASELINE_CHECKS),
            'refreshed_actual_checks':dict(ROUND64_REFRESHED_CHECKS),
            'count_policy':'explicit positive minimum; unique RESULT; observed equals declared when printed; no ERROR exemption',
            'independent_loader_modes':[dict(row) for row in ROUND64_LOADER_MODES],
            'default_simulation_seconds':15, 'worker_pool_max_threads':20,
            'native_standalone':[
                {'path':'tools/tests/test_temporary_cleanup_core.py','class':'TemporaryCleanupCoreTests',
                 'command':['python','-B','tools/tests/test_temporary_cleanup_core.py'], 'counts_as_godot_pass':False},
                {'path':'tools/tests/test_process_tree_owner_core.py','class':'ProcessTreeOwnerTests',
                 'command':['python','-B','tools/tests/test_process_tree_owner_core.py'], 'counts_as_godot_pass':False}],
            'supplementary_gui':[{'suite':'round47_host_lifecycle_board_test','argv':['window'],
                                  'counts_as_headless_pass':False}],
            'focused':[], 'policy':'One current freeze only; default failfast; collect-failures retains overall FALSE; no historical PASS credit.'}
    if current_approved:
        result['semantic_contracts']={'match_view_test':round73_match_view_contract(root)}
        result['historical_nonmandatory_checks']={'match_view_test':result['mandatory_checks'].pop('match_view_test')}
        result['round70_cardback_required']=True
        result['round70_required_suites']=list(ROUND70_REQUIRED_CHECKS)
        for name,minimum in ROUND70_REQUIRED_CHECKS.items():
            result['mandatory_checks'][name]=max(minimum,result['mandatory_checks'].get(name,0))
        result['count_policy']+='; round70 declared-card-back contract required, not historical PASS'
    result['program_count']=len(names)+len(result['native_standalone'])
    result['required_harness_count']=len(required_steps)
    result['supplementary_gui_invocation_count']=len(result['supplementary_gui'])
    return result


def round50_excluded(relative):
    """Exclude prior products and credential inputs before reading/copying bytes."""
    parts = Path(relative).as_posix().lower().split('/')
    excluded = {'.git','.godot','__pycache__','reports','runtime_reports','scratch',
                'records','secrets','credentials','keys','release','exports','.godot_ai_update'}
    name = parts[-1]
    return (any(p in excluded for p in parts) or name.startswith('.env') or
            (name.startswith('~') and name.endswith('.dll')) or
            name.endswith(('.pem','.key','.pfx','.p12','.pyc','.log','.tmp')) or
            any(s in name for s in ('private_key','credentials','identity_registry','players.json')))


def round50_command(engine, target, name, output, window=False, user_root=None):
    gui = name in {'local_spell_restore_test','server_validation_countdown_test'}
    if gui and not window:
        raise ValueError('non-headless GUI evidence required: ' + name)
    native = assembly_native_module()
    for path in [engine, target, output]: native.safe(path)
    command = [Path(engine).as_posix()]
    if not window: command.append('--headless')
    command += ['--fixed-fps','60','--path',Path(target).as_posix(),
                '--scene','res://tests/'+name+'.tscn']
    if name == 'server_validation_countdown_test':
        if user_root is None: raise ValueError('actual physical E user root required for config consumer')
        native.within(user_root,output)
        command += ['--','--config',(Path(user_root)/'countdown.cfg').as_posix()]
    elif name == 'loader_error_boundary_test':
        command += ['--',Path(output).as_posix(),'green']
    elif name == 'round47_host_lifecycle_board_test' and window:
        command += ['--','window']
    elif name in ROUND40_OUTPUT_ARGS:
        command += ['--',Path(output).as_posix()]
    return command


def round71_declared_outputs(code):
    """Only literal writes and same-function literal variable save_png outputs."""
    outputs = set(re.findall(r'save_png\(\s*["\']res://([^"\']+)["\']', code))
    outputs.update(re.findall(r'FileAccess\.open\(\s*["\']res://([^"\']+)["\']\s*,\s*FileAccess\.WRITE', code))
    for block in re.split(r'(?m)(?=^(?:static )?func )', code):
        for name, relative in re.findall(r'\bvar\s+(\w+)\s*(?::\s*String\s*)?:?=\s*["\']res://([^"\']+)["\']', block):
            if re.search(r'\.save_png\(\s*'+re.escape(name)+r'\s*\)', block):
                outputs.add(relative)
    return outputs


def round50_preflight(project=PROJECT, approved_root=Path('E:/scratch'), contract_proof=False, current_approved=False):
    """Read-only in-memory snapshot. No mkdir, source copy, cold import or Godot."""
    import ast
    import subprocess
    if any(not Path(p).is_absolute() or Path(p).drive.upper() != 'E:' or '..' in Path(p).parts
           for p in [project,approved_root]):
        raise runner.SafetyError('explicit physical E roots required before filesystem access')
    project, approved_root = runner.physical_e(project), runner.physical_e(approved_root)
    if not (project/'project.godot').is_file() or not approved_root.is_dir():
        raise runner.SafetyError('explicit existing project and approved physical E parent required')
    baseline = project/ROUND50_BASE_MANIFEST
    baseline_bytes = baseline.read_bytes()
    old = json.loads(baseline_bytes.decode('utf-8-sig'), object_pairs_hook=runner.unique_fields)
    selection = build_round50_selection(old, project, current_approved=current_approved)
    if contract_proof:
        import copy
        selection=copy.deepcopy(selection)
        names=['loader_error_boundary_test']+ROUND64_MIGRATED_SIX
        selection['parent_candidate_counts']={'headless':selection['headless_count'],
                                             'formal':selection['selected_count']}
        selection.update(names=names,headless=names,selected_count=len(names),headless_count=len(names),
                         required_harness_steps=[],extracted_harness_contracts=[],required_harness_count=0,
                         blocked_not_landed=[r for r in selection['blocked_not_landed'] if r['suite'] in names],
                         blocked_extracted_harness=[],contract_proof=True)
        selection['categories']={k:[n for n in group if n in names] for k,group in selection['categories'].items()}
        selection['program_count']=len(names)+len(selection['native_standalone'])
    blockers = list(selection['blocked_not_landed'])
    # Enumerate production trees, but never enumerate tests as an include tree.
    includes = ['project.godot','scripts','assets','data','game_data','addons','json_maker','icon.svg']
    files = set()
    excluded_files = []
    for include in includes:
        start = project/include
        if not start.exists():
            blockers.append({'path':include,'reason':'production include missing'});continue
        candidates = [start]
        if start.is_dir():
            candidates = []
            for directory, dirs, leaves in os.walk(start, followlinks=False):
                runner.no_links(directory)
                dirs[:] = [d for d in dirs if not round50_excluded(Path(directory,d).relative_to(project))]
                for d in dirs: runner.no_links(Path(directory,d))
                candidates.extend(Path(directory,n) for n in leaves)
        for p in candidates:
            rel = p.relative_to(project).as_posix()
            if round50_excluded(rel): excluded_files.append(rel);continue
            runner.no_links(p)
            if p.is_file(): files.add(rel)
    for name in selection['names']+(['worker_content_environment_test'] if contract_proof else []):
        files.update('tests/'+name+s for s in ('.gd','.tscn'))
    # Independent required inputs share the parent fingerprint, not scene counts.
    for item in selection['required_harness_steps']:
        contract=item['execution_contract']
        files.update([contract['runner'],contract['parent'],'tests/'+item['suite']+'.gd','tests/'+item['suite']+'.tscn'])
    # Explicit inherited/root-contract helper inputs, even when Git ignores them.
    files.update(round42_explicit_dependencies())
    snapshots = {}
    hashes = {}
    pending = list(files)
    textual = {'.gd','.tscn','.tres','.godot','.gdextension'}
    while pending:
        rel = pending.pop()
        if rel in hashes: continue
        p = runner.contained(project/rel, project)
        if round50_excluded(rel):
            blockers.append({'path':rel,'reason':'input dependency is records/secret/generated output'});continue
        if not p.is_file():
            blockers.append({'path':rel,'reason':'dependency not landed'});continue
        data = p.read_bytes()
        hashes[rel] = hashlib.sha256(data).hexdigest()
        if p.suffix not in textual: continue
        text = data.decode('utf-8-sig')
        snapshots[rel] = text
        # Comments are not executable dependency declarations. Dynamic outputs aren't inputs.
        code = '\n'.join(l for l in text.splitlines() if not l.lstrip().startswith(('#',';')))
        outputs = round71_declared_outputs(code)
        declared = set(re.findall(r'(?:preload|load|get_file_as_string|get_file_as_bytes|FileAccess\.open)\(\s*["\']res://([^"\']+)',code))
        declared.update(re.findall(r'(?m)^\s*extends\s+["\']res://([^"\']+)',code))
        if p.suffix in {'.tscn','.tres','.godot','.gdextension'}:
            declared.update(re.findall(r'res://([^\s\"\'<>]+)',code))
        # Static tests used as real subprocess scenes also participate; unrelated
        # negative-builder string payloads (e.g. res://other.tscn) are not loads.
        declared.update(re.findall(r'res://(tests/[^\s\"\'<>]+)',code))
        for dep in sorted(declared):
            harness = ROUND50_EXTRACTED_HARNESSES.get(Path(rel).stem)
            if (harness and rel=='tests/'+Path(rel).stem+'.gd' and dep==harness['helper']):
                # Generated only by the validated independent extraction step.
                continue
            if dep in outputs or '%' in dep or '{' in dep: continue
            if not dep.endswith(('.gd','.tscn','.tres','.png','.svg','.json','.wav','.ogg','.dll')): continue
            if dep not in files:
                if dep.startswith('tests/') and not round50_excluded(dep):
                    files.add(dep);pending.append(dep)
                elif not (project/dep).is_file():
                    blockers.append({'path':dep,'consumer':rel,'reason':'static resource not landed'})
                else:
                    blockers.append({'path':dep,'consumer':rel,'reason':'required static input outside explicit freeze roots'})
    scenes = []
    for name in selection['names']:
        script = 'tests/'+name+'.gd'
        chain, effective = [], {}
        current = script
        while current:
            if current in chain:
                blockers.append({'suite':name,'reason':'inheritance cycle'});break
            chain.append(current)
            text = snapshots.get(current,'')
            for block in re.split(r'(?m)(?=^(?:static )?func )', text):
                method = re.match(r'(?:static )?func (\w+)',block)
                if method and method[1] not in effective: effective[method[1]] = {'path':current,'body':block}
            parent = re.match(r'\s*extends ["\']res://([^"\']+)',text)
            current = parent[1] if parent else None
        deps, todo = set(chain+['tests/'+name+'.tscn']), list(chain)
        while todo:
            for dep in re.findall(r'res://(tests/[^\s\"\'<>]+)',snapshots.get(todo.pop(),'')):
                if dep in snapshots and dep not in deps: deps.add(dep);todo.append(dep)
        protocol = [p for p in sorted(deps) if re.search(r'print\(["\']RESULT\b',snapshots.get(p,''))]
        if not protocol: blockers.append({'suite':name,'reason':'no actual dependency RESULT definition'})
        roots = []
        for method, definition in effective.items():
            for i,line in enumerate(definition['body'].splitlines(),1):
                if any(t in line for t in ('get_cmdline_user_args','get_environment','user://','approved_data_root','workspace_root')):
                    roots.append({'method':method,'path':definition['path'],'source':line.strip()})
                if re.search(r'(?:root|directory|work|path|folder|cache)[\w.]*\s*(?::[^=]+)?=\s*"[A-Z]:/',line,re.I):
                    blockers.append({'suite':name,'path':definition['path'],'reason':'effective absolute root not injected','source':line.strip()})
        if name in ROUND40_OUTPUT_ARGS and not any('get_cmdline_user_args' in r['source'] for r in roots):
            # Helper/preload may own the root parser rather than the selected child.
            if not any('get_cmdline_user_args' in snapshots.get(p,'') for p in deps):
                blockers.append({'suite':name,'reason':'explicit argv[0] root consumer absent'})
        writer = effective.get('_write_configuration',{})

        if name == 'round47_worker_launch_lifecycle_test' and '/engine/' in snapshots.get(script,''):
            blockers.append({'suite':name,'reason':'standalone fixture requires root sibling /engine/; generic mandatory66 engine layout is generated/Godot.exe; owner must parameterize actual binary contract'})
        scenes.append({'suite':name,'mode':next(k for k,v in selection['categories'].items() if name in v),
                       'effective_inheritance_chain':chain,'effective_method_owners':{k:v['path'] for k,v in effective.items()},
                       'test_dependencies':sorted(deps),'protocol_sources':protocol,'output_root_sources':roots,
                       'configuration_writer':writer.get('path'),
                       'configuration_consumer':'scripts/net/server/server_bootstrap.gd.read_configuration (JSON and CFG)' if writer else None,
                       'output_contract':'argv root where declared; per-suite physical E APPDATA/LOCALAPPDATA/FATE_TEST_SCRATCH_ROOT; res:// only in owned freeze; approved data is frozen project/data',
                       'execution_status':'not_run'})
    config = snapshots.get('project.godot','')
    if (project/'override.cfg').exists() or re.search(r'^\s*config/project_settings_override',config,re.M):
        blockers.append({'path':'project.godot','reason':'undeclared override refused'})
    if not re.search(r'(?m)^worker_pool/max_threads=20\s*$',config):
        blockers.append({'path':'project.godot','reason':'worker pool must remain current20'})
    cfg_bytes = (project/'assets/config/server.cfg').read_bytes()
    cfg = cfg_bytes.decode('utf-8-sig')
    data_section = re.search(r'(?ms)^\[data\]\s*\n(.*?)(?=^\[|\Z)',cfg)
    if (not data_section or
            [v.strip() for v in re.findall(r'(?m)^random_sim_budget_sec\s*=\s*([^;\n]+)',data_section[1])] not in [['15.0'],['15']] or
            [v.strip() for v in re.findall(r'(?m)^random_sim_enabled\s*=\s*([^;\n]+)',data_section[1])] != ['true']):
        blockers.append({'path':'assets/config/server.cfg','reason':'default simulation budget must remain15'})
    helper = project/'tools/diagnostics/assembly_native_probe.py'
    helper_bytes = helper.read_bytes()
    tree = ast.parse(helper_bytes)
    defined = {n.name for n in tree.body if isinstance(n,(ast.FunctionDef,ast.ClassDef))}
    required = {'validate_paths','validate_caller','process_identity','safe','within','access'}
    if not required.issubset(defined): raise runner.SafetyError('native probe real function definitions missing')
    native_spec = importlib.util.spec_from_file_location('round50_native',helper)
    native = importlib.util.module_from_spec(native_spec);native_spec.loader.exec_module(native)
    token = uuid.uuid4().hex
    generated = approved_root/('isolated-'+token)/'generated'
    owner_identity = native.process_identity(os.getpid())
    scope = {'version':1,'run_id':token,'generated':generated.as_posix(),
             'fixture_root':(generated/'f/complete-0').as_posix(),
             'source_root':(generated/'project/data').as_posix(),'engine':(generated/'Godot.exe').as_posix(),
             'owner_pid':os.getpid(),'owner_creation':owner_identity['creation']}
    native.validate_paths(scope,token,'identity',[scope['fixture_root']])
    # Open existing approved parent for FILE_ADD_SUBDIRECTORY only; no creation/write.
    write_access = native.access(approved_root,0x4)
    if write_access != 0: blockers.append({'path':approved_root.as_posix(),'reason':'approved parent add-directory access refused','win32_error':write_access})
    check = subprocess.run([sys.executable,'-B','-c','import ctypes,json,sys; print(sys.executable)'],
                           capture_output=True,text=True,timeout=15)
    python_verified = check.returncode == 0 and Path(check.stdout.strip()) == Path(sys.executable)
    if not python_verified: blockers.append({'reason':'installed Python launch preflight refused'})
    standalone = []
    for item in selection['native_standalone']:
        p = project/item['path']
        available = p.is_file() and any(isinstance(n,ast.ClassDef) and n.name == item['class'] for n in ast.parse(p.read_bytes()).body)
        stem='temporary_cleanup' if item['class']=='TemporaryCleanupCoreTests' else 'process_tree_owner'
        source_paths=['addons/fate_server_signals/src/'+stem+'_core.cpp',
                      'addons/fate_server_signals/src/'+stem+'_core.hpp',
                      'tools/tests/'+stem+'_core_probe.cpp']
        sources={rel:digest(project/rel) for rel in source_paths if (project/rel).is_file()}
        standalone.append(dict(item,definition_exists=available,source_hashes=sources,execution_status='not_run'))
        if not available: blockers.append({'path':item['path'],'reason':'standalone native actual class missing'})
        for rel in source_paths:
            if rel not in sources: blockers.append({'path':rel,'reason':'standalone native required source not landed'})
    owner_contract=round42_fixture_contracts(selection['names'],project)
    blockers.extend(owner_contract['blockers'])
    drift = [rel for rel,sha in hashes.items() if not (project/rel).is_file() or digest(project/rel) != sha]
    harness_preflight=[]
    for item in selection['required_harness_steps']:
        contract=item['execution_contract']
        row={'suite':item['suite'],'execution_status':'not_run','callable_verified':False,
             'counts_as_formal_scene':False,'archive_verified':False}
        try:
            path=project/contract['runner']
            source=path.read_bytes()
            if hashlib.sha256(source).hexdigest()!=hashes.get(contract['runner']):
                raise runner.SafetyError('extraction runner snapshot drift')
            extract,api=round50_extraction_callable(source)
            parent=snapshots[contract['parent']]
            for function in api['functions']:
                if not re.search(r'^func '+re.escape(function)+r'\(',parent,re.M):
                    raise runner.SafetyError('actual Session extraction function absent: '+function)
            row.update(callable_verified=callable(extract),api=api,
                       parent_sha256=hashes[contract['parent']])
        except Exception as exc:
            row['error']=type(exc).__name__+': '+str(exc)
            blockers.append({'suite':item['suite'],'reason':'required harness generation API rejected','error':row['error']})
        harness_preflight.append(row)
    if baseline.read_bytes() != baseline_bytes: drift.append(ROUND50_BASE_MANIFEST)
    if helper.read_bytes() != helper_bytes: drift.append('tools/diagnostics/assembly_native_probe.py')
    if (project/'assets/config/server.cfg').read_bytes() != cfg_bytes: drift.append('assets/config/server.cfg')
    if drift: blockers.append({'reason':'source drift during readonly snapshot','paths':drift})
    return {'status':'selection_blocked' if blockers else 'selection_ready','sourcePASS':False,'releasePASS':False,
            'selection':selection,'baseline_manifest':ROUND50_BASE_MANIFEST,
            'baseline_manifest_sha256':hashlib.sha256(baseline_bytes).hexdigest(),
            'scenes':scenes,'freeze_files':sorted(hashes),'freeze_hashes':hashes,
            'parent_source_fingerprint':round50_source_fingerprint(hashes),
            'harness_preflight':harness_preflight,
            'excluded_test_hashes':{p.relative_to(project).as_posix():digest(p)
                for p in (project/'tests').rglob('*') if p.is_file()
                and p.suffix in {'.gd','.tscn','.py'}
                and p.relative_to(project).as_posix() not in hashes
                and not round50_excluded(p.relative_to(project))},
            'excluded_files':sorted(excluded_files),'blockers':blockers,'snapshot_drift':drift,
            'native_standalone':standalone,'fixture_owner_contract':owner_contract,
            'native_preflight':{'helper_sha256':hashlib.sha256(helper_bytes).hexdigest(),
                'actual_definitions':sorted(required),'authorization_plan_valid':True,'parent_add_directory_win32_error':write_access,
                'python_launch_exit':check.returncode,'python_verified':python_verified,'own_process_identity':owner_identity,
                'actual_main_worker_user_probe_executed':False,'mandatory66_executed':False},
            'business_suites_executed':0,'godot_launch_count':0,'cold_import_count':0,
            'approved_root':approved_root.as_posix(),'limit':'Only static/prelaunch contract readiness; no Godot behavior, GUI, native DLL capability, sourcePASS or releasePASS.'}


ROUND73_MATCH_VIEW_SOURCES = {
    'tests/match_view_test.gd':'ec654b2099433cf98e1166ddf35d4afe3bc4216e588883b110d697b7a126b5fe',
    'tests/match_journal_test.gd':'749ba26efa538be867c51d28a503170ec5b737be54e5c272472aca9019c3039f',
}


def round73_match_view_contract(target):
    """Exact current source contract, not a guessed floor from random AI steps."""
    from collections import Counter
    target=Path(target)
    for rel,sha in ROUND73_MATCH_VIEW_SOURCES.items():
        if digest(target/rel)!=sha:
            raise runner.SafetyError('match_view semantic source changed; nextcandidate required: '+rel)
    source=(target/'tests/match_view_test.gd').read_text(encoding='utf-8')
    run=source.split('func run() -> void:\n',1)[1]
    if ('GameStart.game_start([0, 1, 2])' not in run or
            'for observer in [-1, 0, 1, 2]:' not in run or
            'while not GameProgress.is_game_over and steps < 3000:' not in run or
            'check(GameProgress.is_game_over, "real AI match reaches end through view loopback")' not in run):
        raise runner.SafetyError('match_view observer/terminal structure not bound')
    minimum=Counter();calls=[]
    for line in run.splitlines():
        if not line.lstrip().startswith('check('):continue
        match=re.search(r', "([^"\n]+)"',line)
        if not match:raise runner.SafetyError('unparsed static assertion label')
        label=match[1];calls.append(line.strip())
        if label=='loopback step ':continue
        if label=='mirror accepts observer ':
            for observer in [-1,0,1,2]:minimum['mirror accepts observer %d:'%observer]+=1
            continue
        tabs=len(line)-len(line.lstrip('\t'))
        multiplier=1 if tabs==1 else 4 if tabs==2 else 12 if tabs==3 else 9 if tabs==4 else None
        if multiplier is None:raise runner.SafetyError('unbound assertion loop depth')
        minimum[label]+=multiplier
    return {'schema':'match-view-source-semantics/v1','source_hashes':dict(ROUND73_MATCH_VIEW_SOURCES),
        'static_assertion_calls':calls,'minimum_label_multiset':dict(minimum),
        'observer_ids':[-1,0,1,2],'players_per_observer':3,'loop_maximum':3000,
        'terminal_label':'real AI match reaches end through view loopback',
        'historical_random_total_not_a_gate':226}


def round73_match_view_analyze(row,target,hashes):
    from collections import Counter
    try:
        contract=round73_match_view_contract(target)
        if hashes and any(hashes.get(rel)!=sha for rel,sha in contract['source_hashes'].items()):
            raise runner.SafetyError('frozen match_view semantic hash mismatch')
        labels=[]
        for event in row['raw_check_events']:
            match=re.fullmatch(r'\s*CHECK\s+(.*?)\s+(true|false)\s*',event)
            if not match:match=re.fullmatch(r'\s*CHECK\s+(true|false)\s+(.*?)\s*',event)
            if not match:raise runner.SafetyError('semantic CHECK label undecodable')
            labels.append((match[2].strip(),match[1]) if match[1] in {'true','false'} else (match[1].strip(),match[2]))
        counts=Counter(label for label,value in labels)
        missing={label:n-counts[label] for label,n in contract['minimum_label_multiset'].items() if counts[label]<n}
        steps=[int(m[1]) for label,value in labels if (m:=re.fullmatch(r'loopback step ([1-9][0-9]*)',label))]
        terminal=contract['terminal_label']
        allowed=set(contract['minimum_label_multiset'])
        unknown=[label for label,value in labels if label not in allowed and not re.fullmatch(r'loopback step ([1-9][0-9]*)',label)]
        failures=[]
        if missing:failures.append('semantic_fixed_assertion_multiset_missing')
        if unknown:failures.append('semantic_unknown_check')
        if not steps or steps!=list(range(1,len(steps)+1)) or len(steps)>contract['loop_maximum']:
            failures.append('semantic_loop_sequence_missing_or_duplicate')
        loop_positions=[i for i,(label,value) in enumerate(labels) if label.startswith('loopback step ')]
        if loop_positions and loop_positions!=list(range(loop_positions[0],loop_positions[-1]+1)):
            failures.append('semantic_loop_events_not_contiguous')
        if not labels or labels[-1]!=(terminal,'true') or counts[terminal]!=1:
            failures.append('semantic_terminal_not_final_true')
        if (row.get('result') or {}).get('checks')!=len(labels):failures.append('semantic_declared_observed_mismatch')
        row['semantic_contract']={'contract':contract,'missing':missing,'unknown':unknown,'loop_steps':len(steps),
            'final_terminal_true':bool(labels and labels[-1]==(terminal,'true')),'passed':not failures}
        row['reasons'].extend(failures)
        row['passed']=row['passed'] and not failures
    except (OSError,ValueError,runner.SafetyError) as exc:
        row['passed']=False;row['reasons'].append('semantic_source_refusal: '+str(exc))
    return row


def analyze_round50_suite(name, out, err, code, target, hashes):
    # Round40 historical exact counts remain untouched. The current candidate
    # uses explicit positive floors; analyze still binds events to one RESULT.
    row=analyze_integrated_suite(name,out,err,code,target,hashes)
    floors=round64_mandatory_checks()
    expected=None if name=='match_view_test' else floors.get(name)
    if name=='match_view_test':row=round73_match_view_analyze(row,target,hashes)
    count=(row.get('result') or {}).get('checks')
    if expected and (type(count) is not int or count < expected):
        row['passed']=False;row['reasons'].append('mandatory_checks_%d'%expected)
    if name in set(ROUND50_CURRENT_CHECKS)|set(ROUND64_REFRESHED_CHECKS) and (not count or row['observed_checks'] != count):
        row['passed']=False;row['reasons'].append('mandatory_observed_checks')
    if name=='assembly_publish_lifecycle_test' and 'ASSEMBLY_NATIVE_SKIP' in out+err:
        row['passed']=False;row['reasons'].append('mandatory_native_branch_skipped')
    return row


def round61_artifact_declared(path):
    """Reuse the older runner's declared evidence classes, never config/keys."""
    path = Path(path)
    return (path.suffix == '.log' or path.name.endswith(('.result.json', '.response.json'))
            or path.name in {'ready.json', 'supervisor.json', 'recovery.json', 'report.json',
                             'manifest.json', 'transaction-evidence.json', 'round39-final-save.json'}
            or (path.suffix == '.json' and 'recovery-comparison' in path.parts))


def round73_retention_contract(target,hashes):
    contracts={}
    for identity,producer in [('control_ipc','scripts/net/server/server_console_channel.gd'),('tag_cache','scripts/system/global/load_game.gd')]:
        sha=digest(Path(target)/producer)
        if sha!=hashes.get(producer):raise runner.SafetyError('retention producer hash mismatch')
        contracts[identity]={'producer':producer,'sha256':sha}
    return contracts


def round73_producer_retained(path,contracts):
    rel=Path(path).as_posix()
    expected={'control_ipc':('scripts/net/server/server_console_channel.gd',r'(?:[^/]+/)*console/control\.json'),
        'tag_cache':('scripts/system/global/load_game.gd',r'(?:[^/]+/)*data/tag_list\.json')}
    for identity,(producer,pattern) in expected.items():
        contract=contracts.get(identity,{})
        if (contract.get('producer')==producer and re.fullmatch('[0-9a-f]{64}',contract.get('sha256',''))
                and re.fullmatch(pattern,rel)):
            return True
    return False


def round61_protected(path,contracts=None):
    """Metadata-only refusal: no contents of saves/configuration/credentials read."""
    path = Path(path)
    return (any(part.lower() in {'records', 'secrets', 'keys', 'credentials', 'identities'} for part in path.parts)
            or path.suffix.lower() in {'.cfg', '.pem', '.key', '.pfx', '.p12'}
            # Declared LoadGame.STORED_JSONS_PATH cache: retain, never grant
            # deletion/archive permission merely from its known producer name.
            or path.name.lower() in {'config.json', 'players.json', 'identity_registry.json', 'stored_jsons.dat'}
            or path.name.lower().startswith('.env')
            or any(token in path.name.lower() for token in ('private_key', 'credentials', 'identity_registry'))
            or round73_producer_retained(path,contracts or {}))


def round61_allocate_runtime(fixtures, manifest, phase, index, suite):
    """Authorize two exact UUID child scopes before launching their producer."""
    fixtures = Path(fixtures)
    fixtures.mkdir(parents=True, exist_ok=True)
    runner.no_links(fixtures)
    scopes = []
    for kind in ['runtime', 'recycle']:
        token = uuid.uuid4().hex
        owner = fixtures / ('isolated-' + token)
        generated = owner / 'generated'
        generated.mkdir(parents=True)
        runner.contained(generated, fixtures)
        info = generated.stat()
        binding = {'run_id':token, 'generated':str(generated), 'owner':str(owner),
                   'directory_identity':[info.st_dev, info.st_ino], 'kind':kind,
                   'parent_run_id':manifest['run_id'], 'parent_generated':manifest['generated'],
                   'phase':phase, 'index':index, 'suite':suite,
                   'frozen_fingerprint':round50_source_fingerprint(manifest['frozen_hashes'])}
        save(owner/'manifest.json', dict(binding, processes=[]))
        scopes.append(binding)
    manifest.setdefault('suite_runtime_owners', []).append(scopes)
    return Path(scopes[0]['generated'])


def round61_reclaim_runtime(owner, manifest, row, target):
    """Archive/read back first; unknown bytes refuse before any rename/deletion.

    Retained saves never move or get read. Smaller recycling scope stays under
    the same charged parent; delete_owned remains the sole deletion primitive.
    """
    owner = Path(owner)
    active=manifest.get('active_manifest_relative','manifest.json')
    if active!='manifest.json' and active!='round73-continuation-manifest.json' and not re.fullmatch(r'round73-continuation-[0-9a-f]{32}-manifest\.json',active):
        raise runner.SafetyError('undeclared active ownership manifest')
    if (Path(manifest['generated']).parent != owner or owner.name != 'isolated-'+manifest['run_id']
            or load(runner.no_links(owner/active)) != manifest):
        raise runner.SafetyError('parent UUID ownership receipt readback mismatch')
    output = runner.contained(Path(row['fixture_root']), Path(manifest['generated']))
    scopes = [pair for pair in manifest.get('suite_runtime_owners', [])
              if pair[0]['generated'] == str(output)]
    if len(scopes) != 1:
        raise runner.SafetyError('unknown runtime authorization scope')
    runtime, recycle = scopes[0]
    label = row['phase'] + '-' + row['suite']
    procs = [p for p in manifest['processes'] if p.get('label') == label and p.get('command') == row['command']]
    if len(procs) != 1 or type(procs[0].get('pid')) is not int or procs[0]['pid'] <= 0:
        raise runner.SafetyError('runtime request/Job identity missing or ambiguous')
    proc = procs[0]
    if (proc.get('exited') is not True or proc.get('active_owned_processes') != 0
            or proc.get('log_handles_released') is not True):
        raise runner.SafetyError('runtime Job live or log handles unreleased')
    hashes = manifest['frozen_hashes']
    if manifest.get('retention_contracts') and manifest['retention_contracts']!=round73_retention_contract(target,hashes):
        raise runner.SafetyError('explicit retention producer declaration mismatch')
    fingerprint = round50_source_fingerprint(hashes)
    if snapshot_hashes([Path(p) for p in hashes], Path(target)) != hashes:
        raise runner.SafetyError('frozen inputs readback mismatch')
    archive = owner/'worker'/('runtime-'+runtime['run_id'])
    archive.mkdir(parents=True, exist_ok=True)
    artifacts = []
    def retain_bytes(source, dest):
        runner.no_links(source)
        runner.no_links(dest.parent)
        sha = digest(source)
        if dest.exists():
            raise runner.SafetyError('refuse evidence overwrite')
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, dest)
        if digest(source) != sha or digest(dest) != sha:
            raise runner.SafetyError('runtime archive readback mismatch')
        artifacts.append({'path':dest.relative_to(owner).as_posix(), 'sha256':sha, 'verified':True})
        return sha
    for binding in [runtime, recycle]:
        directory = runner.contained(Path(binding['generated']), Path(manifest['generated']))
        info = directory.stat()
        if ([info.st_dev, info.st_ino] != binding['directory_identity']
                or binding['parent_run_id'] != manifest['run_id']
                or binding['parent_generated'] != manifest['generated']
                or binding['frozen_fingerprint'] != fingerprint
                or binding['phase'] != row['phase'] or binding['suite'] != row['suite']):
            raise runner.SafetyError('runtime complete identity binding mismatch')
        runner.tree_bytes(directory)
        receipt = Path(binding['owner'])/'manifest.json'
        record = load(runner.no_links(receipt))
        if record != dict(binding, processes=[]):
            raise runner.SafetyError('runtime ownership receipt changed')
        save(receipt, dict(binding, processes=[proc]))
        retain_bytes(receipt, archive/(binding['kind']+'-ownership.json'))
    for role in ['stdout', 'stderr']:
        retain_bytes(owner/'evidence'/(label+'.'+role+'.log'), archive/(role+'.log'))
    save(archive/'frozen-inputs.json', hashes)
    if load(archive/'frozen-inputs.json') != hashes:
        raise runner.SafetyError('frozen input map archive mismatch')
    artifacts.append({'path':(archive/'frozen-inputs.json').relative_to(owner).as_posix(),
                      'sha256':digest(archive/'frozen-inputs.json'), 'verified':True})
    candidates, retained, unknown, response_evidence = [], [], [], []
    approved_hashes = set(hashes.values())
    for path in sorted(output.rglob('*')):
        runner.no_links(path)
        if not path.is_file():
            continue
        rel = path.relative_to(output)
        if round61_protected(rel,manifest.get('retention_contracts')):
            info=path.stat()
            retained.append({'path':rel.as_posix(), 'bytes':info.st_size,
                             'identity':[info.st_dev,info.st_ino], 'content_read':False})
            continue
        if round61_artifact_declared(rel):
            dest = archive/'artifacts'/rel
            sha = retain_bytes(path, dest)
            candidates.append((path, rel, sha, dest))
            if path.name.endswith('.response.json'):
                projection = {}
                try:
                    response = load(dest)
                    if isinstance(response,dict):
                        projection = {key:response[key] for key in
                            ['ok','room','pid','instance','authority_host_mode','request_id']
                            if key in response and type(response[key]) in (str,int,bool)}
                        result_fields = response.get('result',{})
                        if isinstance(result_fields,dict):
                            projection['result'] = {key:result_fields[key] for key in
                                ['closing','saved','released','exited'] if type(result_fields.get(key)) is bool}
                except (OSError,ValueError,TypeError):
                    pass
                response_evidence.append({'path':dest.relative_to(owner).as_posix(),
                    'raw_sha256':sha,'raw_bytes_preserved':True,'nonsecret_fields':projection,
                    'projection_is_not_recoverable_raw_evidence':True})
        else:
            if manifest.get('retain_unknown_no_delete'):
                unknown.append(rel.as_posix())
                continue  # never read undeclared ordinary bytes under retain mode
            sha = digest(path)
            if sha not in approved_hashes:
                unknown.append(rel.as_posix())
            else:
                candidates.append((path, rel, sha, None))
    if unknown:
        raise runner.SafetyError('undeclared runtime files; no deletion: '+json.dumps(unknown,ensure_ascii=False))
    # Validate the whole plan again before the first move; archive failures and
    # reparse/unknown refusal cannot partially delete the runtime.
    runner.tree_bytes(output)
    if any(digest(p) != sha or (dest is not None and digest(dest) != sha)
           for p, rel, sha, dest in candidates):
        raise runner.SafetyError('runtime plan changed before recycle')
    result = {'status':'retained_protected' if retained else 'removed',
              'runtime_owner':runtime, 'retained':retained, 'artifacts':artifacts,
              'response_evidence':response_evidence,
              'quota_owner':manifest['generated'], 'quota_policy':'entire original owner, unchanged 8GiB',
              'before_bytes':runner.tree_bytes(output), 'reclaimed_bytes':0}
    save(archive/'recycle-intent.json', dict(result, plan=[{'path':rel.as_posix(),'sha256':sha}
                                                        for p,rel,sha,dest in candidates]))
    row['runtime_recycle_mutation_started']=True
    if retained:
        stage = Path(recycle['generated'])
        for path, rel, sha, dest in candidates:
            moved = stage/rel
            moved.parent.mkdir(parents=True, exist_ok=True)
            path.rename(moved)
            if digest(moved) != sha:
                raise runner.SafetyError('recycle moved-byte readback mismatch; retained for recovery')
        result['reclaimed_bytes'] = runner.tree_bytes(stage)
        runner.delete_owned(stage, Path(recycle['owner']))
    else:
        result['reclaimed_bytes'] = runner.tree_bytes(output)
        runner.delete_owned(output, Path(runtime['owner']))
        runner.delete_owned(Path(recycle['generated']), Path(recycle['owner']))
    result['runtime_exists_after'] = output.exists()
    result['retained_files_verified']=all((output/i['path']).is_file()
        and (output/i['path']).stat().st_size==i['bytes']
        and [(output/i['path']).stat().st_dev,(output/i['path']).stat().st_ino]==i['identity'] for i in retained)
    if not result['retained_files_verified']:
        raise runner.SafetyError('retained file identity changed; recovery required')
    save(archive/'recycle-result.json', result)
    if load(archive/'recycle-result.json') != result:
        raise runner.SafetyError('runtime recycle result readback failed')
    return result


# Explicit caller evidence: these short headless scenes only use their own
# process user-data and have no declared port/output/recovery/native contract.
# This allowlist is policy, not an inference from a suite name or dependency set.
ROUND71_CALLER_PARALLEL_SAFE = frozenset({
    'net_data_validation_test',
    'net_cards_test',
    'net_move_test',
    'net_locations_test',
    'net_worker_startup_contract_test',
})


def round71_scheduler_options(jobs, cpu_budget, memory_budget, disk_budget, runtime_disk):
    """Validate CLI scheduler policy before any suite or freeze allocation."""
    if type(jobs) is not int or jobs not in (1, 2, 4):
        raise runner.SafetyError('jobs must be 1, 2 or 4')
    if type(runtime_disk) is not int or runtime_disk <= 0:
        raise runner.SafetyError('runtime aggregate disk budget must be positive')
    if jobs == 1:
        budget = scheduler.Resources(1, 1, runtime_disk)
        return {'jobs': 1, 'mode': 'serial_compat', 'budget': budget,
                'lane_resources': budget, 'cancel_file': None,
                'resource_policy_version': 'round71-caller-resources/v1'}
    values = (cpu_budget, memory_budget, disk_budget)
    if any(type(value) is not int or value <= 0 for value in values):
        raise runner.SafetyError('parallel jobs require explicit positive cpu/memory/disk budget')
    if disk_budget > runtime_disk:
        raise runner.SafetyError('parallel disk budget exceeds remaining aggregate owner budget')
    if any(value < jobs for value in values):
        raise runner.SafetyError('parallel jobs unsupported by aggregate budget; need one reservation per lane')
    budget = scheduler.Resources(cpu_budget, memory_budget, disk_budget)
    lane = scheduler.Resources(cpu_budget // jobs, memory_budget // jobs, disk_budget // jobs)
    return {'jobs': jobs, 'mode': 'bounded_parallel', 'budget': budget,
            'lane_resources': lane, 'cancel_file': None,
            'resource_policy_version': 'round71-caller-resources/v1'}


def round71_parallel_resource_policy(name, phase, selection, options, jobs=None):
    """Return caller-owned capability/resource data; unknown stays exclusive."""
    categories = selection.get('categories', {})
    category = next((key for key, names in categories.items() if name in names), None)
    known = bool(
        options['jobs'] > 1 and phase == 'complete'
        and category == 'short_headless'
        and name in ROUND71_CALLER_PARALLEL_SAFE
    )
    reason = 'approved short-headless isolated caller allowlist' if known else (
        'serial phase barrier' if phase != 'complete' else
        'not in explicit parallel-safe caller allowlist')
    return {
        'resource_policy_version': 'round71-caller-resources/v1',
        'suite': name, 'phase': phase, 'category': category,
        'known_parallel': known,
        'resources': options['lane_resources'] if known else options['budget'],
        'exclusive_keys': frozenset() if known else frozenset({'full-entry-serial-barrier'}),
        'exclusive': not known,
        'reason': reason,
    }


def round71_build_scheduler_tasks(phases, selection, options):
    """Build one FIFO task plan; phase/name keys keep prerequisite accounting unique."""
    tasks, policies = [], {}
    for phase, names in phases:
        for name in names:
            key = phase + '-' + name
            if key in policies:
                raise runner.SafetyError('duplicate scheduler task key: ' + key)
            policy = round71_parallel_resource_policy(name, phase, selection, options)
            policies[key] = policy
            tasks.append(scheduler.Task(
                key, policy['resources'], known_parallel=policy['known_parallel'],
                exclusive_keys=policy['exclusive_keys'], exclusive=policy['exclusive']))
    return tasks, policies


def round71_record_scheduler_accounting(manifest, report):
    """Project scheduler accounting without replacing suite RESULT analysis."""
    expected = list(report.get('expected', []))
    executed = list(report.get('executed', []))
    notrun = list(report.get('notrun', []))
    result_keys = [row.get('key') for row in report.get('results', [])]
    accounted = bool(report.get('accounted') and
                     set(expected) == set(executed) | set(notrun) and
                     not set(executed) & set(notrun) and
                     result_keys == [key for key in expected if key in set(executed)])
    manifest.update(scheduler_expected=expected, scheduler_executed=executed,
                    scheduler_notrun=notrun, scheduler_result_keys=result_keys,
                    scheduler_accounted=accounted,
                    scheduler_errors=list(report.get('errors', [])))
    if not accounted:
        manifest.setdefault('scheduler_errors', []).append(
            {'stage': 'accounting', 'error': 'expected/executed/notrun/results mismatch'})
    return manifest


class _Round71CompletedHandle:
    """Already-finished serial caller handle for the scheduler contract."""
    def __init__(self, row, job0=True):
        self.row = dict(row)
        self.job0 = bool(job0)
        self.cancelled = False

    def poll(self):
        return True

    def cancel(self):
        self.cancelled = True
        self.row['passed'] = False

    def finish(self):
        result = dict(self.row)
        result.update(job0=self.job0, cancelled=self.cancelled)
        if self.cancelled:
            result['passed'] = False
        return result


class _Round71AsyncSuiteHandle:
    """Owns one existing OwnedProcess and finalizes on the scheduler thread."""
    def __init__(self, process, caller, task_key, base, lane_evidence):
        self.process = process
        self.caller = caller
        self.task_key = task_key
        self.base = base
        self.lane_evidence = lane_evidence
        self.finished = None

    def poll(self):
        return self.process.poll()

    def cancel(self):
        self.process.cancel()

    def finish(self):
        if self.finished is None:
            result = self.process.finish()
            self.finished = self.caller.finish_parallel(
                self.task_key, self.base, self.lane_evidence, result)
        return dict(self.finished)


class _Round71SuiteCaller:
    """Injectable suite caller: all mutable manifest work stays on one scheduler thread."""
    def __init__(self, *, manifest, preflight, source_project, files, before, frozen,
                 owner, generated, target, fixtures, engine, evidence, env, budgets,
                 selection, options, collect_failures, task_specs, report_path):
        self.m = manifest
        self.preflight = preflight
        self.source_project = Path(source_project)
        self.files = list(files)
        self.before = dict(before)
        self.frozen = dict(frozen)
        self.owner = Path(owner)
        self.generated = Path(generated)
        self.target = Path(target)
        self.fixtures = Path(fixtures)
        self.engine = Path(engine)
        self.evidence = Path(evidence)
        self.env = dict(env)
        self.budgets = dict(budgets)
        self.selection = selection
        self.options = options
        self.collect_failures = bool(collect_failures)
        self.task_specs = task_specs
        self.report_path = Path(report_path)
        self.stop_reason = None

    def _prelaunch_safety(self, name):
        current_source = snapshot_hashes(self.files, self.source_project)
        current_frozen = snapshot_hashes(self.files, self.target)
        origin_drift = round73_origin_drift(self.preflight)
        if current_source != self.before or current_frozen != self.frozen or origin_drift:
            raise runner.SafetyError('same-freeze/source drift before suite: ' + json.dumps({
                'suite': name,
                'source': [p for p in self.before if current_source.get(p) != self.before[p]],
                'frozen': [p for p in self.frozen if current_frozen.get(p) != self.frozen[p]],
                'origin': origin_drift,
            }, ensure_ascii=False))

    def _make_request(self, task_key):
        spec = self.task_specs[task_key]
        phase, name, index, policy = (spec['phase'], spec['name'], spec['index'], spec['policy'])
        self._prelaunch_safety(name)
        output = round61_allocate_runtime(self.fixtures, self.m, phase, index, name)
        local = self.env.copy()
        for key, sub in [('APPDATA', 'appdata'), ('LOCALAPPDATA', 'localappdata')]:
            (output / sub).mkdir()
            local[key] = (output / sub).as_posix()
        (output / 'localappdata/hermes/cache/scratch').mkdir(parents=True)
        local['FATE_TEST_SCRATCH_ROOT'] = output.as_posix()
        local['ROUND47_ROUTE_ROOT'] = output.as_posix()
        if name in ROUND50_CURRENT_CHECKS:
            local['ROUND56_HANDOFF_ROOT'] = output.as_posix()
            local['HERMES_SHUTDOWN_TEST_ROOT'] = output.as_posix()
        if name == 'assembly_publish_lifecycle_test':
            local['HERMES_RECOVERY_VALIDATION_ROOT'] = (
                output / 'localappdata/hermes/cache/scratch' /
                ('assembly-' + self.m['run_id'])).as_posix()
            configure_assembly_scope(local, self.generated, output, self.target,
                                     self.engine, self.m['run_id'], self.evidence,
                                     phase + '-' + name)
        budget = dict(self.budgets)
        if name == 'net_server_gateway_restart_test':
            local['FATE_R39_CORRECTNESS'] = '1'
            budget['seconds'] = 600
        if name in self.selection['categories'].get('performance', []):
            budget['seconds'] = 600
        execution_target = self.target
        if self.options['jobs'] > 1 and policy['known_parallel']:
            # A parallel lane never writes the shared imported freeze. Make a
            # normal independent copy; no hardlink/symlink or shared writable tree.
            execution_target = self.generated / 'parallel-projects' / task_key
            execution_target.parent.mkdir(parents=True, exist_ok=True)
            if execution_target.exists():
                raise runner.SafetyError('parallel project copy already exists: ' + task_key)
            shutil.copytree(self.target, execution_target, symlinks=False)
            runner.no_links(execution_target)
            if snapshot_hashes(self.files, execution_target) != self.frozen:
                raise runner.SafetyError('parallel project copy hash mismatch: ' + task_key)
        command = round71_suite_command(self.engine, execution_target, name, output, self.selection)
        label = phase + '-' + name
        policy_record = dict(policy, resources=policy['resources'].__dict__)
        row = {'suite': name, 'phase': phase, 'command': command,
               'fixture_root': output.as_posix(), 'budget': budget,
               'policy': policy_record,
               'execution_project_root': execution_target.as_posix(),
               'explicit_environment': {k: local[k] for k in
                   ['APPDATA', 'LOCALAPPDATA', 'FATE_TEST_SCRATCH_ROOT']}}
        return spec, output, local, budget, command, label, row

    @staticmethod
    def _failed_row(base, error, exit_code=None):
        row = dict(base)
        row.update(exit=exit_code, result=None, result_lines=[], raw_check_events=[],
                   observed_checks=0, errors=[], reasons=[str(error)], passed=False,
                   strict_passed=False, execution_error=str(error))
        return row

    def _record_restart(self, row, budget, output_text, performance_gate=None):
        if row['suite'] != 'net_server_gateway_restart_test':
            return
        if performance_gate is None:
            performance_gate = [json.loads(line.split(' ', 1)[1]) for line in
                                output_text.splitlines()
                                if line.startswith('GATEWAY_PERFORMANCE_GATE ')]
        self.m['restart_current'] = {
            'runs': 1, 'correctness_budget_seconds': budget['seconds'],
            'correctness_passed': row.get('passed'), 'exit': row.get('exit'),
            'performance_gate': performance_gate,
            'performance_passed': len(performance_gate) == 1 and
                                  performance_gate[0].get('passed') is True,
        }

    def _append_and_reclaim(self, row, process):
        destination = self.m['prerequisites' if row['phase'] == 'prerequisite' else 'suites']
        destination.append(row)
        save(self.owner / 'manifest.json', self.m)
        if self.m.get('contract_proof'):
            row['runtime_reclamation'] = {
                'status': 'retained_no_reclamation',
                'reason': 'bounded count proof grants no additional deletion authority'}
        else:
            try:
                row['runtime_reclamation'] = round61_reclaim_runtime(
                    self.owner, self.m, row, Path(row.get('execution_project_root', self.target)))
                artifacts = row['runtime_reclamation'].get('artifacts', [])
                self.m['worker_artifacts'].extend(artifacts)
                self.m['worker_engine_errors'].extend(
                    fixture_engine_errors(artifacts, self.owner))
            except Exception as exc:
                row['runtime_reclamation'] = {
                    'status': 'recovery_required' if row.get('runtime_recycle_mutation_started')
                              else 'blocked_no_deletion',
                    'error': type(exc).__name__ + ': ' + str(exc)}
                row['passed'] = False
                row.setdefault('reasons', []).append('runtime_reclamation_failed')
                self.stop_reason = self.stop_reason or 'runtime_reclamation_failure'
        save(self.owner / 'manifest.json', self.m)
        if process is not None and not round43_continue_after(
                row, process, self.collect_failures if row['phase'] == 'complete' else False):
            self.stop_reason = self.stop_reason or (row['phase'] + '_failure_or_safety_stop')
        return row

    def launch(self, task):
        task_key = task.key
        spec = self.task_specs[task_key]
        try:
            spec, output, local, budget, command, label, base = self._make_request(task_key)
            if self.options['jobs'] == 1:
                record_start = len(self.m['processes'])
                try:
                    out, err, code = runner.execute(
                        command, local, self.generated, self.evidence, label,
                        budget, self.m['processes'])
                    row = dict(base, exit=code, **round71_analyze_suite(
                        spec['name'], out, err, code, self.target, self.frozen,
                        self.selection))
                except Exception as exc:
                    record = self.m['processes'][-1] if len(self.m['processes']) > record_start else None
                    code = record.get('exit_code') if record else None
                    stdout = self.evidence / (label + '.stdout.log')
                    stderr = self.evidence / (label + '.stderr.log')
                    out = stdout.read_text(encoding='utf-8') if stdout.is_file() else ''
                    err = stderr.read_text(encoding='utf-8') if stderr.is_file() else ''
                    row = dict(base, exit=code, **analyze(out, err, code))
                    row.update(passed=False, execution_error=str(exc))
                self._record_restart(row, budget, out)
                row['parallel_drift'] = round73_origin_drift(self.preflight)
                row['current_vs_frozen'] = list(row['parallel_drift'])
                row['frozen_drift'] = [rel for rel, sha in self.frozen.items()
                                       if digest(self.target / rel) != sha]
                if row['parallel_drift'] or row['frozen_drift']:
                    row['passed'] = False
                    row.setdefault('reasons', []).append('source_or_frozen_drift')
                record = self.m['processes'][-1] if len(self.m['processes']) > record_start else None
                row = self._append_and_reclaim(row, record)
                job0 = bool(record and record.get('exited') is True and
                             record.get('active_owned_processes') == 0 and
                             record.get('log_handles_released') is True)
                return _Round71CompletedHandle(row, job0=job0)

            lane_evidence = self.evidence / 'parallel' / task_key
            lane_evidence.mkdir(parents=True, exist_ok=True)
            record = {'label': label, 'scheduler_task': task_key}
            self.m['processes'].append(record)
            # OwnedProcess uses its cwd for the original runner boundary. Its disk
            # check is aggregate; scheduler.monitor charges owner+retained bytes.
            lane = spec['policy']['resources']
            process_resources = scheduler.Resources(lane.cpu, lane.memory,
                                                    self.options['budget'].disk)
            def read_result(exit_code):
                out = (lane_evidence / 'runner.stdout.log').read_text(encoding='utf-8')
                err = (lane_evidence / 'runner.stderr.log').read_text(encoding='utf-8')
                analysis = round71_analyze_suite(
                    spec['name'], out, err, exit_code,
                    Path(base['execution_project_root']), self.frozen,
                    self.selection)
                if spec['name'] == 'net_server_gateway_restart_test':
                    analysis['performance_gate'] = [json.loads(line.split(' ', 1)[1])
                        for line in out.splitlines()
                        if line.startswith('GATEWAY_PERFORMANCE_GATE ')]
                return dict(exit=exit_code, **analysis)
            process = parallel_adapter.OwnedProcess(
                runner, command, local, self.generated, lane_evidence,
                process_resources, budget['seconds'], record, read_result)
            return _Round71AsyncSuiteHandle(process, self, task_key, base, lane_evidence)
        except Exception as exc:
            row = self._failed_row({'suite': spec['name'], 'phase': spec['phase'],
                                    'command': [], 'fixture_root': '',
                                    'budget': {}, 'policy': spec['policy']}, exc)
            self.stop_reason = self.stop_reason or 'launch_safety_stop'
            return _Round71CompletedHandle(row, job0=False)

    def finish_parallel(self, task_key, base, lane_evidence, result):
        row = dict(base)
        row.update(result)
        if row['suite'] == 'net_server_gateway_restart_test':
            self._record_restart(row, row['budget'], '', row.get('performance_gate', []))
        label = base['phase'] + '-' + base['suite']
        for role in ('stdout', 'stderr'):
            source = lane_evidence / ('runner.' + role + '.log')
            destination = self.evidence / (label + '.' + role + '.log')
            if source.is_file():
                if destination.exists():
                    raise runner.SafetyError('refuse evidence overwrite: ' + str(destination))
                shutil.copyfile(source, destination)
        row['parallel_drift'] = round73_origin_drift(self.preflight)
        row['current_vs_frozen'] = list(row['parallel_drift'])
        execution_target = Path(row.get('execution_project_root', self.target))
        row['frozen_drift'] = [rel for rel, sha in self.frozen.items()
                               if digest(execution_target / rel) != sha]
        if row['parallel_drift'] or row['frozen_drift']:
            row['passed'] = False
            row.setdefault('reasons', []).append('source_or_frozen_drift')
        process = next((item for item in reversed(self.m['processes'])
                        if item.get('scheduler_task') == task_key), None)
        return self._append_and_reclaim(row, process)

    def monitor(self):
        if self.stop_reason:
            return self.stop_reason
        charged = runner.tree_bytes(self.owner) + self.m.get('retained_input_bytes', 0)
        self.m['peak_observed_bytes'] = max(self.m.get('peak_observed_bytes', 0), charged)
        if charged > self.options['budget'].disk:
            return 'global_disk_budget'
        if shutil.disk_usage(self.owner).free < self.m.get('min_free_bytes', 0):
            return 'global_free_space_budget'
        return None

    def cancelled(self):
        signal = self.options.get('cancel_file')
        return bool(signal and Path(signal).is_file())


def run_round50_full(preflight, collect_failures=False, resource_proof=False,
                     contract_proof=False, scheduler_config=None):
    """Future one-freeze headless run. Blocked preflight performs no allocation."""
    if preflight['status'] != 'selection_ready' or preflight['blockers']:
        print(json.dumps({'status':'selection_blocked','sourcePASS':False,'releasePASS':False,
                          'godot_launch_count':0,'blockers':preflight['blockers']},ensure_ascii=False))
        return 1
    if bool(preflight['selection'].get('contract_proof')) != bool(contract_proof):
        raise runner.SafetyError('contract proof selection/mode mismatch')
    source_project = runner.physical_e(preflight.get('source_root', PROJECT))
    if resource_proof:preflight=round71_resource_preflight(preflight)
    root = runner.physical_e(preflight['approved_root'])
    selection = preflight['selection']
    names = selection['headless']
    files = [Path(p) for p in preflight['freeze_files']]
    before = preflight['freeze_hashes']
    # The proof adapter already closes both the prerequisite and relay inputs.
    # Do not filter again against the formal-only selection and drop worker.
    if snapshot_hashes(files,source_project) != before or round73_origin_drift(preflight):
        raise runner.SafetyError('source changed after preflight; no cold freeze/import allowed')
    token = uuid.uuid4().hex
    owner = root/('isolated-'+token)
    generated = owner/'generated'
    evidence = owner/'evidence'
    generated.mkdir(parents=True);evidence.mkdir()
    target, engine, fixtures = generated/'project', generated/'Godot.exe', generated/'f'
    target.mkdir();fixtures.mkdir()
    source_engine = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe')
    env = os.environ.copy()
    for key,sub in [('APPDATA','appdata'),('LOCALAPPDATA','localappdata'),('TEMP','tmp'),('TMP','tmp'),('TMPDIR','tmp')]:
        (generated/sub).mkdir(exist_ok=True);env[key]=(generated/sub).as_posix()
    (generated/'localappdata/hermes/cache/scratch').mkdir(parents=True)
    for key in list(env):
        if key.startswith(('HERMES_ASSEMBLY_','FATE_','FD_','ROUND47_')) or key == 'HERMES_RECOVERY_VALIDATION_ROOT': env.pop(key,None)
    budgets = {'seconds':180,'bytes':8*1024**3,'min_free':1024**3}
    retained_input_bytes=runner.tree_bytes(runner.physical_e(preflight['input_owner'])) if preflight.get('input_owner') else 0
    if retained_input_bytes>=budgets['bytes']:raise runner.SafetyError('protected retained input byte_budget')
    budgets['bytes']-=retained_input_bytes  # shared prepared input remains charged, not moved outside quota
    # Generic cleanup validates the exact native str(Path), not POSIX spelling.
    m = {'round':50,'run_id':token,'generated':str(generated),'selected_suites':names,
         'selection':selection,'collect_failures':bool(collect_failures),'suites':[],'prerequisites':[],
         'processes':[],'cleanup':'not_started','freeze_before':before,
         'parent_source_fingerprint':round50_source_fingerprint(before),
         'required_harness_steps':[], 'resource_proof':bool(resource_proof), 'contract_proof':bool(contract_proof),
         'suite_runtime_owners':[], 'worker_artifacts':[], 'worker_engine_errors':[],
         'selection_inputs':[{'path':str(source_project/ROUND50_BASE_MANIFEST),'sha256':preflight['baseline_manifest_sha256']}],
         'sourcePASS':False,'releasePASS':False,'claim':'current_headless_candidate_only_not_final',
         'native_standalone_status':'independent commands required; not run or credited by Godot suite runner',
         'gui_status':'not_run_no_headless_credit',
         'excluded_test_hashes':preflight.get('excluded_test_hashes',{}),
         'executor_hashes':{rel:digest(PROJECT/rel) for rel in
             ['tools/tests/test_round29_integrated_evidence.py','tools/tests/test_round50_candidate_selection.py',
              'tools/run_isolated_godot_test.py','tools/diagnostics/assembly_native_probe.py']}}
    if resource_proof:
        m['excluded_test_hashes']=dict(m['excluded_test_hashes'],**{rel:sha for rel,sha in preflight['freeze_hashes'].items()
            if rel.startswith('tests/') and rel not in before})
    m['prepared_contract']=preflight.get('prepared_contract')
    m['source_root']=source_project.as_posix()
    m['origin_source_root']=preflight.get('origin_source_root',source_project.as_posix())
    m['source_identity']=preflight.get('source_identity')
    save(owner/'manifest.json',m)
    for rel,sha in m['executor_hashes'].items():
        dest=evidence/'executor'/rel;dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(PROJECT/rel,dest)
        if digest(dest)!=sha: raise runner.SafetyError('executor archive drift: '+rel)
    print(json.dumps({'started_manifest':(owner/'manifest.json').as_posix(),
        'selected_count':len(names),'formal_count':selection['selected_count'],
        'parent_source_fingerprint':m['parent_source_fingerprint']},ensure_ascii=False),flush=True)
    try:
        m['stage']='freeze'
        for rel in files:
            dest=target/rel;dest.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(source_project/rel,dest)
            if digest(dest) != before[rel.as_posix()]: raise runner.SafetyError('source drift during copy: '+rel.as_posix())
        if snapshot_hashes(files,source_project) != before: raise runner.SafetyError('source drift across freeze')
        config_path=target/'project.godot'
        config=config_path.read_text(encoding='utf-8-sig')
        transformed,transform=transform_isolated_editor_vcs(config)
        config_path.write_text(transformed,encoding='utf-8',newline='')
        threading=re.search(r'^\[threading\]\s*\n(.*?)(?=^\[|\Z)',transformed,re.M|re.S)
        transform.update(authorized_paths=['project.godot'],verified=bool(threading and threading[0] in config
            and re.search(r'(?m)^worker_pool/max_threads=20\s*$',threading[0]) and digest(config_path)==transform['transformed_sha256']))
        m['editor_transform']=transform
        if not transform['verified']: raise runner.SafetyError('unauthorized editor/threading transform')
        frozen=snapshot_hashes(files,target);m['frozen_hashes']=frozen
        m['frozen_source_fingerprint']=round50_source_fingerprint(frozen)
        save(owner/'manifest.json',m)  # upfront, before every native/Godot child
        if [p for p in frozen if frozen[p]!=before[p]] != ['project.godot']:
            raise runner.SafetyError('freeze differs outside authorized editor VCS fields')
        shutil.copyfile(source_engine,engine)
        m['engine_sha256']=digest(engine)
        if digest(source_engine)!=m['engine_sha256']: raise runner.SafetyError('engine copy mismatch')
        runner.physical_e(engine)
        m['stage']='native_preflight'
        configure_assembly_scope(env,generated,fixtures,target,engine,token,evidence)
        m['native_preflight']=round73_native_preflight(selection,env,target)
        if m['native_preflight']['full_safety_blockers']: raise runner.SafetyError('owner/native preflight blocked')
        m['stage']='main_worker_probe'
        probe=generated/'probe';probe.mkdir()
        app=re.search(r'^\[application\]\s*\n(.*?)(?=^\[|\Z)',transformed,re.M|re.S)[1]
        (probe/'project.godot').write_text('config_version=5\n[application]\n'+app+'\n'+threading[0],encoding='utf-8')
        (probe/'probe.gd').write_text(runner.PROBE_SCRIPT,encoding='utf-8')
        out,err,code=runner.execute([engine.as_posix(),'--headless','--path',probe.as_posix(),
            '--script','res://probe.gd','--',token,'main',generated.as_posix()],env,generated,evidence,'probe',budgets,m['processes'])
        if code or re.search(r'SCRIPT ERROR|SHADER ERROR|ERROR:',out+err): raise runner.SafetyError('real main/worker probe rejected')
        m['user_probes']=runner.verify_probe(out,generated,token)
        if any(p['worker_pool_max_threads']!=20 for p in m['user_probes']): raise runner.SafetyError('actual pool must remain20')
        m['stage']='required_extracted_harness'
        # Same frozen inputs and same Job executor; dedicated runner main would
        # independently snapshot the live project and cannot be called here.
        if snapshot_hashes(files,source_project)!=before or snapshot_hashes(files,target)!=frozen:
            raise runner.SafetyError('source/freeze drift before required harness')
        harness = (None if resource_proof or contract_proof else
                   run_round50_harness(target,engine,env,generated,evidence,budgets,m['processes'],before))
        if not resource_proof and not contract_proof: m['required_harness_steps'].append(harness)
        save(owner/'manifest.json',m)
        if snapshot_hashes(files,source_project)!=before or snapshot_hashes(files,target)!=frozen:
            if harness is not None: harness['passed']=False;harness['same_freeze_verified']=False
            raise runner.SafetyError('source/freeze drift after required harness')
        if harness is not None and not harness['passed'] and not (collect_failures
                and harness.get('execution_status')=='executed'
                and harness.get('archive_verified') is True
                and harness.get('same_freeze_verified') is True
                and harness.get('user_isolated') is True
                and harness.get('owned_exit_verified') is True
                and m['processes'][-1].get('budget_failure') in (None,'timeout')):
            raise runner.SafetyError('required harness failed or unsafe; no formal PASS credit')
        m['stage']='import'
        out,err,code=runner.execute([engine.as_posix(),'--headless','--editor','--import','--path',target.as_posix()],
            env,generated,evidence,'import',budgets,m['processes'])
        m['import']={'exit':code,'errors':[l for l in (out+err).splitlines() if re.search(r'SCRIPT ERROR|SHADER ERROR|ERROR:',l)]}
        if code or m['import']['errors']: raise runner.SafetyError('cold import rejected; no ERROR expansion')
        m['stage'] = 'schedule'
        # Scheduler admission/monitoring charges one original envelope, including
        # retained input bytes; runner per-process bytes remains reduced below.
        runtime_disk = 8 * 1024**3
        raw_scheduler = scheduler_config or {}
        options = round71_scheduler_options(
            raw_scheduler.get('jobs', 1), raw_scheduler.get('cpu_budget'),
            raw_scheduler.get('memory_budget_bytes'), raw_scheduler.get('disk_budget_bytes'),
            runtime_disk)
        options['cancel_file'] = raw_scheduler.get('cancel_file')
        phases = [('prerequisite', ['worker_content_environment_test']), ('complete', names)]
        tasks, policies = round71_build_scheduler_tasks(phases, selection, options)
        if options['jobs'] > 1 and sum(task.known_parallel for task in tasks) < 2:
            raise runner.SafetyError('jobs>1 unsupported: fewer than two approved parallel-safe suites')
        task_specs = {}
        for phase, requested in phases:
            for index, name in enumerate(requested):
                key = phase + '-' + name
                task_specs[key] = {'phase': phase, 'name': name, 'index': index,
                                   'policy': policies[key]}
        m['scheduler_config'] = {
            'jobs': options['jobs'], 'mode': options['mode'],
            'budget': options['budget'].__dict__,
            'lane_resources': options['lane_resources'].__dict__,
            'cancel_file': options.get('cancel_file'),
            'resource_policy_version': options['resource_policy_version'],
        }
        m['scheduler_policy'] = {
            key: dict(value, resources=value['resources'].__dict__)
            for key, value in policies.items()}
        m['min_free_bytes'] = budgets['min_free']
        caller = _Round71SuiteCaller(
            manifest=m, preflight=preflight, source_project=source_project,
            files=files, before=before, frozen=frozen, owner=owner,
            generated=generated, target=target, fixtures=fixtures, engine=engine,
            evidence=evidence, env=env, budgets=budgets, selection=selection,
            options=options, collect_failures=collect_failures, task_specs=task_specs,
            report_path=owner / 'manifest.json')
        report = scheduler.run(
            tasks, caller.launch, budget=options['budget'], jobs=options['jobs'],
            cancelled=caller.cancelled, monitor=caller.monitor, interval=0.05)
        round71_record_scheduler_accounting(m, report)
        m['scheduler'] = report
        m['stop_reason'] = report.get('stop_reason') or caller.stop_reason or 'completed'
        if not m['scheduler_accounted']:
            raise runner.SafetyError('scheduler expected/executed/notrun/results accounting rejected')
        m['final_drift']=[p for p,sha in before.items() if digest(source_project/p)!=sha]
    except Exception as exc:
        m['error']=type(exc).__name__+': '+str(exc)
    finally:
        origin_project=Path(m['origin_source_root'])
        m['next_candidate_source_drift']=round73_origin_drift(preflight)
        m['excluded_test_changes']=[{'path':rel,'before':sha,
            'after':digest(origin_project/rel) if (origin_project/rel).is_file() else None}
            for rel,sha in m['excluded_test_hashes'].items()
            if not (origin_project/rel).is_file() or digest(origin_project/rel)!=sha]
        m['excluded_test_additions']=[p.relative_to(origin_project).as_posix()
            for folder in ['tests','newtests'] for p in (origin_project/folder).rglob('*') if p.is_file() and p.suffix in {'.gd','.tscn','.py'}
            and p.relative_to(origin_project).as_posix() not in before
            and p.relative_to(origin_project).as_posix() not in m['excluded_test_hashes']
            and not round50_excluded(p.relative_to(origin_project))]
        m['bytes_in_owner']=runner.tree_bytes(owner)
        m['retained_input_bytes']=retained_input_bytes
        m['aggregate_charged_bytes']=m['bytes_in_owner']+retained_input_bytes
        m['byte_budget']=8*1024**3
        m['runtime_byte_budget']=budgets['bytes']
        m['final_drift']=sorted(set([p for p,sha in before.items() if not (source_project/p).is_file() or digest(source_project/p)!=sha]
            +m['next_candidate_source_drift']))
        m['executor_unchanged']=all(digest(PROJECT/rel)==sha for rel,sha in m['executor_hashes'].items())
        for step in m['required_harness_steps']:
            step['archive_verified']=round50_verify_harness_archive(step.get('archive',''),step.get('archive_index',[]))
            if not step['archive_verified']: step['passed']=False
        # Harness source/runner/extraction artifacts are diagnostics, not saves.
        # Worker archives retain only logs and validation reports/manifests:
        # never configs, player registries, private keys, saves or records.
        # Already archived per-suite artifacts survive removal of their producer.
        m.setdefault('worker_artifacts',[])
        for p in fixtures.rglob('*'):
            rel=p.relative_to(fixtures)
            if not p.is_file() or round61_protected(rel): continue
            if not round61_artifact_declared(rel): continue
            dest=owner/'worker'/rel;dest.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(p,dest)
            m['worker_artifacts'].append({'path':dest.relative_to(owner).as_posix(),'sha256':digest(dest),'verified':digest(p)==digest(dest)})
        # .log is excluded as a freeze input, not excluded as a real error gate.
        m.setdefault('worker_engine_errors',[])
        for p in fixtures.rglob('*.log'):
            if round61_protected(p.relative_to(fixtures)): continue
            lines=[l for l in p.read_text(encoding='utf-8',errors='replace').splitlines() if re.search(r'SCRIPT ERROR|SHADER ERROR|^\s*ERROR:',l)]
            if lines: m['worker_engine_errors'].append({'path':(Path('worker')/p.relative_to(fixtures)).as_posix(),'lines':lines})
        m['worker_scoped_negatives']=[]
        for error in m['worker_engine_errors']:
            binding=round42_dependency_worker_negative(owner,m,error)
            if not binding['verified']: binding=round43_bind_log_negative(owner,m,error)
            if binding['verified']: m['worker_scoped_negatives'].append({'error':error,'binding':binding})
        m['selection_inputs_unchanged']=all(digest(i['path'])==i['sha256'] for i in m['selection_inputs'])
        m['logs']=[{'path':p.relative_to(owner).as_posix(),'sha256':digest(p)} for p in evidence.rglob('*') if p.is_file()]+m['worker_artifacts']
        m['archive_verified']=all(digest(owner/i['path'])==i['sha256'] for i in m['logs'])
        save(owner/'manifest.json',m)
        try:
            if not m['archive_verified'] or any(not p.get('exited') or p.get('active_owned_processes')!=0
                 or p.get('log_handles_released') is not True for p in m['processes']): raise runner.SafetyError('archive/owned process release not verified')
            if resource_proof or contract_proof:
                m['shared_runtime_retained']={'freeze':target.as_posix(),'engine':engine.as_posix(),
                    'reason':'Two-scene proof retains shared input bytes; only suite runtimes recycled.'}
                raise runner.SafetyError('resource proof retains shared freeze/engine and res runtime evidence')
            retained=[p.relative_to(generated).as_posix() for p in generated.rglob('*')
                      if p.is_file() and round61_protected(p.relative_to(generated))
                      and not (p.is_relative_to(target) and p.relative_to(target).as_posix() in m.get('frozen_hashes',{}))]
            if retained or any(r.get('runtime_reclamation',{}).get('status')!='removed'
                               for r in m['prerequisites']+m['suites']):
                m['protected_runtime_retained']=retained
                raise runner.SafetyError('retain shared freeze and unarchived protected/blocked runtime')
            runner.delete_owned(generated,owner)
            m['cleanup']='generated_removed';m['generated_exists_after_cleanup']=generated.exists()
            m['engine_source_unchanged']=digest(source_engine)==m.get('engine_sha256')
        except Exception as exc: m['cleanup']='retained: '+str(exc)
        summary=summarize_round50_current(m)
        m['summary']=summary;m['passed']=summary['passed']
        if resource_proof:
            m['resource_proof_passed']=bool(not m.get('error') and m['archive_verified']
                and len(m['prerequisites'])==1 and len(m['suites'])==1
                and all(r['passed'] and r.get('runtime_reclamation',{}).get('status') in {'removed','retained_protected'}
                        and r['runtime_reclamation'].get('retained_files_verified') is True
                        and r['runtime_reclamation'].get('reclaimed_bytes',0)>0
                        for r in m['prerequisites']+m['suites'])
                and (m['suites'][0].get('result') or {}).get('checks')==22
                and not m['worker_engine_errors'] and not m['final_drift']
                and all(p.get('exited') is True and p.get('active_owned_processes')==0
                        and p.get('log_handles_released') is True for p in m['processes']))
            m['passed']=False
            summary.update(passed=False,resource_proof_passed=m['resource_proof_passed'],
                           sourcePASS=False,releasePASS=False)
        if contract_proof:
            actual=[r['suite'] for r in m['suites']]
            m['contract_proof_passed']=bool(not m.get('error') and actual==names and len(set(actual))==len(names)
                and len(m['prerequisites'])==1 and all(r['passed'] for r in m['prerequisites']+m['suites'])
                and m['archive_verified'] and not m['worker_engine_errors'] and not m['final_drift']
                and m['executor_unchanged'] and all(p.get('exited') is True and p.get('active_owned_processes')==0
                    and p.get('log_handles_released') is True for p in m['processes']))
            m['passed']=False
            summary.update(passed=False,contract_proof_passed=m['contract_proof_passed'],sourcePASS=False,releasePASS=False,
                actual_count=len(actual),unique_count=len(set(actual)),
                proof_observed_checks=sum(r['observed_checks'] for r in m['suites']))
        save(owner/'manifest.json',m)
        print(json.dumps({'manifest':(owner/'manifest.json').as_posix(),**summary},ensure_ascii=False),flush=True)
    return 0 if (m.get('contract_proof_passed') if contract_proof else
                 m.get('resource_proof_passed') if resource_proof else m['passed']) else 1


def round50_missing_plan(preflight, m):
    if (preflight['status']!='selection_ready' or preflight['blockers']
            or m.get('round')!=50 or m['selected_suites']!=preflight['selection']['headless']
            or m['freeze_before']!=preflight['freeze_hashes']
            or m['parent_source_fingerprint']!=preflight['parent_source_fingerprint']
            or m.get('final_drift') or m.get('cleanup')!='generated_removed'
            or m.get('archive_verified') is not True):
        raise runner.SafetyError('current continuation source/selection/archive contract mismatch')
    if any(p.get('exited') is not True or p.get('active_owned_processes')!=0
           or p.get('log_handles_released') is not True for p in m['processes']):
        raise runner.SafetyError('prior owned processes not released')
    rows=[r['suite'] for r in m['suites']]
    if len(rows)!=len(set(rows)) or any(n not in m['selected_suites'] for n in rows):
        raise runner.SafetyError('prior executed rows duplicate or unselected')
    missing=[n for n in m['selected_suites'] if n not in rows]
    launched={p['label'][9:] for p in m['processes'] if p['label'].startswith('complete-')}
    if any(n in launched for n in missing):
        raise runner.SafetyError('executedbroken missing RESULT/row must not be rerun')
    if set(rows)!=launched or not missing:
        raise runner.SafetyError('prior launched/row accounting mismatch or nothing missing')
    return missing


def run_round50_missing(preflight, manifest):
    """Only unlaunched scenes; exact existing token, freeze bytes, roots and env."""
    path=runner.physical_e(manifest);owner=path.parent;m=load(path)
    names=round50_missing_plan(preflight,m)
    token=m['run_id'];generated=owner/'generated';evidence=owner/'evidence'
    if owner.name!='isolated-'+token or generated.exists() or str(generated)!=m['generated']:
        raise runner.SafetyError('exact released original owner required; never retoken')
    if any(digest(owner/i['path'])!=i['sha256'] for i in m['logs']):
        raise runner.SafetyError('original evidence readback changed')
    original=owner/'pre-continuation-manifest.json'
    if original.exists(): raise runner.SafetyError('continuation already attempted; no blind retry')
    shutil.copyfile(path,original)
    original_sha=digest(original)
    before=m['freeze_before'];files=[Path(p) for p in sorted(before)]
    if snapshot_hashes(files,PROJECT)!=before: raise runner.SafetyError('source changed before continuation')
    m['continuation']={'prior_manifest_sha256':original_sha,'requested':names,
        'policy':'Only previously unlaunched names; old RED/exit/logs unchanged; exact token/root/fingerprint.',
        'executor_sha256':digest(__file__),'source_fingerprint':m['parent_source_fingerprint']}
    generated.mkdir();target=generated/'project';target.mkdir();fixtures=generated/'f';fixtures.mkdir()
    engine=generated/'Godot.exe';source_engine=Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe')
    env=os.environ.copy()
    for key,sub in [('APPDATA','appdata'),('LOCALAPPDATA','localappdata'),('TEMP','tmp'),('TMP','tmp'),('TMPDIR','tmp')]:
        root=generated/sub;root.mkdir(exist_ok=True);env[key]=root.as_posix()
    (generated/'localappdata/hermes/cache/scratch').mkdir(parents=True)
    for key in list(env):
        if key.startswith(('HERMES_ASSEMBLY_','FATE_','FD_','ROUND47_')) or key=='HERMES_RECOVERY_VALIDATION_ROOT':env.pop(key,None)
    budgets={'seconds':180,'bytes':8*1024**3,'min_free':1024**3}
    m['cleanup']='continuation_started';save(path,m)
    try:
        for rel in files:
            dest=target/rel;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(PROJECT/rel,dest)
            if digest(dest)!=before[rel.as_posix()]:raise runner.SafetyError('continuation copy source drift')
        cfg=target/'project.godot';text,transform=transform_isolated_editor_vcs(cfg.read_text(encoding='utf-8-sig'))
        cfg.write_text(text,encoding='utf-8',newline='')
        frozen=m['frozen_hashes']
        if snapshot_hashes(files,target)!=frozen or snapshot_hashes(files,PROJECT)!=before:
            raise runner.SafetyError('reconstructed original freeze bytes mismatch')
        shutil.copyfile(source_engine,engine)
        if digest(engine)!=m['engine_sha256']:raise runner.SafetyError('original engine hash mismatch')
        if digest(PROJECT/'tools/diagnostics/assembly_native_probe.py')!=m['executor_hashes']['tools/diagnostics/assembly_native_probe.py']:
            raise runner.SafetyError('original native helper changed')
        configure_assembly_scope(env,generated,fixtures,target,engine,token,evidence,'continuation-default')
        save(evidence/'continuation-executor.json',{'sha256':digest(__file__),'prior_manifest_sha256':original_sha,'source_fingerprint':m['parent_source_fingerprint']})
        shutil.copyfile(__file__,evidence/'continuation-executor.py')
        out,err,code=runner.execute([engine.as_posix(),'--headless','--editor','--import','--path',target.as_posix()],env,generated,evidence,'continuation-import',budgets,m['processes'])
        m['continuation']['import']={'exit':code,'errors':[l for l in (out+err).splitlines() if re.search(r'SCRIPT ERROR|SHADER ERROR|ERROR:',l)]}
        if code or m['continuation']['import']['errors']:raise runner.SafetyError('continuation cold import rejected')
        for name in names:
            if snapshot_hashes(files,PROJECT)!=before or snapshot_hashes(files,target)!=frozen:raise runner.SafetyError('continuation source/freeze drift')
            index=m['selected_suites'].index(name)
            output=round61_allocate_runtime(fixtures,m,'complete',index,name)
            local=env.copy()
            for key,sub in [('APPDATA','appdata'),('LOCALAPPDATA','localappdata')]:
                root=output/sub;root.mkdir();local[key]=root.as_posix()
            (output/'localappdata/hermes/cache/scratch').mkdir(parents=True)
            local['FATE_TEST_SCRATCH_ROOT']=output.as_posix();local['ROUND47_ROUTE_ROOT']=output.as_posix()
            if name in ROUND50_CURRENT_CHECKS:
                local['ROUND56_HANDOFF_ROOT']=output.as_posix();local['HERMES_SHUTDOWN_TEST_ROOT']=output.as_posix()
            budget=dict(budgets)
            if name in m['selection']['categories']['performance']:budget['seconds']=600
            command=round50_command(engine,target,name,output);label='complete-'+name
            if (evidence/(label+'.stdout.log')).exists() or (evidence/(label+'.stderr.log')).exists():raise runner.SafetyError('unlaunched scene already has logs; retain broken evidence')
            row={'suite':name,'phase':'complete','command':command,'fixture_root':output.as_posix(),'budget':budget,
                 'explicit_environment':{k:local[k] for k in ['APPDATA','LOCALAPPDATA','FATE_TEST_SCRATCH_ROOT']},'continuation':True}
            save(path,m)
            try:
                out,err,code=runner.execute(command,local,generated,evidence,label,budget,m['processes'])
                row.update(exit=code,**analyze_round50_suite(name,out,err,code,target,frozen))
            except Exception as exc:
                code=m['processes'][-1].get('exit_code');out=(evidence/(label+'.stdout.log')).read_text(encoding='utf-8') if (evidence/(label+'.stdout.log')).exists() else '';err=(evidence/(label+'.stderr.log')).read_text(encoding='utf-8') if (evidence/(label+'.stderr.log')).exists() else ''
                row.update(exit=code,**analyze(out,err,code),execution_error=str(exc));row['passed']=False
            row['parallel_drift']=[p for p,sha in before.items() if digest(PROJECT/p)!=sha]
            row['current_vs_frozen']=list(row['parallel_drift']);row['frozen_drift']=[p for p,sha in frozen.items() if digest(target/p)!=sha]
            if row['parallel_drift'] or row['frozen_drift']:row['passed']=False;row['reasons'].append('source_or_frozen_drift')
            m['suites'].append(row);save(path,m)
            try:
                row['runtime_reclamation']=round61_reclaim_runtime(owner,m,row,target)
                m['worker_artifacts'].extend(row['runtime_reclamation']['artifacts'])
                m['worker_engine_errors'].extend(fixture_engine_errors(row['runtime_reclamation']['artifacts'],owner))
            except Exception as exc:
                row['runtime_reclamation']={'status':('recovery_required' if row.get('runtime_recycle_mutation_started')
                                                      else 'blocked_no_deletion'),'error':str(exc)}
                save(path,m)
                raise runner.SafetyError('continuation per-suite reclamation blocked: '+str(exc))
            save(path,m)
            if not round43_continue_after(row,m['processes'][-1],True):raise runner.SafetyError('continuation safety stop')
    except Exception as exc:m['continuation']['error']=type(exc).__name__+': '+str(exc);m['error']=m['continuation']['error']
    finally:
        for p in fixtures.rglob('*'):
            rel=p.relative_to(fixtures)
            if not p.is_file() or round61_protected(rel):continue
            if not round61_artifact_declared(rel):continue
            dest=owner/'worker'/rel;dest.parent.mkdir(parents=True,exist_ok=True)
            if dest.exists():raise runner.SafetyError('continuation cannot overwrite old worker evidence')
            shutil.copyfile(p,dest);item={'path':dest.relative_to(owner).as_posix(),'sha256':digest(dest),'verified':digest(dest)==digest(p)};m['worker_artifacts'].append(item)
            if p.suffix=='.log':
                lines=[l for l in p.read_text(encoding='utf-8',errors='replace').splitlines() if re.search(r'SCRIPT ERROR|SHADER ERROR|^\s*ERROR:',l)]
                if lines:m['worker_engine_errors'].append({'path':item['path'],'lines':lines})
        m['final_drift']=[p for p,sha in before.items() if digest(PROJECT/p)!=sha]
        m['continuation']['source_unchanged']=not m['final_drift']
        m['logs']=[{'path':p.relative_to(owner).as_posix(),'sha256':digest(p)} for p in evidence.rglob('*') if p.is_file()]+m['worker_artifacts']
        m['archive_verified']=all(digest(owner/i['path'])==i['sha256'] for i in m['logs']) and digest(original)==original_sha
        save(path,m)
        try:
            if not m['archive_verified'] or any(not p.get('exited') or p.get('active_owned_processes')!=0 or p.get('log_handles_released') is not True for p in m['processes']):raise runner.SafetyError('continuation archive/owned release unverified')
            retained=[p.relative_to(generated).as_posix() for p in generated.rglob('*') if p.is_file()
                      and round61_protected(p.relative_to(generated))
                      and not (p.is_relative_to(target) and p.relative_to(target).as_posix() in frozen)]
            if retained or any(r.get('runtime_reclamation',{}).get('status')!='removed'
                               for r in m['suites'] if r.get('continuation')):
                m['protected_runtime_retained']=retained
                raise runner.SafetyError('continuation retains protected/blocked runtime and shared freeze')
            runner.delete_owned(generated,owner);m['cleanup']='generated_removed';m['generated_exists_after_cleanup']=generated.exists()
        except Exception as exc:m['cleanup']='retained: '+str(exc)
        m['continuation']['original_red_rows_unchanged']=m['suites'][:len(load(original)['suites'])]==load(original)['suites']
        m['continuation']['completed']=[r['suite'] for r in m['suites'] if r.get('continuation')]
        m['summary']=summarize_round50_current(m);m['passed']=m['summary']['passed'];save(path,m)
        print(json.dumps({'manifest':path.as_posix(),**m['summary']},ensure_ascii=False),flush=True)
    return 0 if m['passed'] else 1


ROUND71_INTEGRATION_PRODUCERS = {
    'modal_regression': ['scripts/game_scene/battle_board_v2.gd'],
    'cardback_privacy': ['scripts/match/view_builder.gd', 'scripts/match/view_mirror.gd'],
}
ROUND71_EXECUTORS = ['tools/tests/test_round29_integrated_evidence.py',
    'tools/run_isolated_godot_test.py', 'tools/diagnostics/assembly_native_probe.py']


def round71_validate_selection(selection):
    names, headless = selection['names'], selection['headless']
    partition = [n for group in selection['categories'].values() for n in group]
    if (not names or len(names)!=len(set(names)) or len(headless)!=len(set(headless))
            or not set(headless).issubset(names) or sorted(partition)!=sorted(names)
            or selection['selected_count']!=len(names) or selection['headless_count']!=len(headless)
            or selection['program_count']!=len(names)+len(selection['native_standalone'])):
        raise runner.SafetyError('duplicate/omitted selection or derived count mismatch')
    semantics=selection.get('semantic_contracts',{})
    if any(type(selection['mandatory_checks'].get(n)) is not int
           or selection['mandatory_checks'][n]<=0 for n in headless if n not in semantics):
        raise runner.SafetyError('explicit mandatory check minimum missing')
    if any(n!='match_view_test' or row.get('schema')!='match-view-source-semantics/v1' for n,row in semantics.items()):
        raise runner.SafetyError('unknown source semantic contract')
    floors=round64_mandatory_checks()
    if any(selection['mandatory_checks'].get(n,0)<floor for n,floor in floors.items() if n in names and n not in semantics):
        raise runner.SafetyError('original mandatory coverage reduced')


def round71_verify_inputs(root, hashes):
    if not isinstance(hashes,dict) or not hashes:
        raise runner.SafetyError('explicit nonempty dependency hash map required')
    for rel, sha in hashes.items():
        if (not isinstance(rel,str) or Path(rel).as_posix()!=rel or Path(rel).is_absolute()
                or '..' in Path(rel).parts or round50_excluded(rel)
                or not isinstance(sha,str) or not re.fullmatch('[0-9a-f]{64}',sha)):
            raise runner.SafetyError('invalid explicit dependency: '+str(rel))
        path=runner.contained(Path(root)/rel,root)
        runner.no_links(path)
        if not path.is_file() or digest(path)!=sha:
            raise runner.SafetyError('producer/source dependency mismatch: '+rel)


def round71_bind_integrations(p, approved, rows):
    """Bind explicit owned test closures to their production source hashes."""
    if approved.get('schema')!='round71-approved-inputs/v1':
        raise runner.SafetyError('approved input schema required; packageartifacthash is not a source contract')
    contracts=approved.get('integrations',[])
    identities=[row.get('id') for row in contracts]
    if len(identities)!=len(set(identities)) or any(n not in ROUND71_INTEGRATION_PRODUCERS for n in identities):
        raise runner.SafetyError('duplicate or unknown integration declaration')
    combined=dict(p['freeze_hashes'])
    for contract in contracts:
        deps=contract.get('dependency_hashes',{})
        for rel,sha in deps.items():
            if rel in combined and combined[rel]!=sha:
                raise runner.SafetyError('conflicting dependency hash: '+rel)
            combined[rel]=sha
    if approved.get('dependency_hashes')!=combined:
        raise runner.SafetyError('approved producer/source hash map mismatch')
    round71_verify_inputs(p['source_root'],combined)
    selection=p['selection']
    selected_contracts=selection.setdefault('scene_contracts',{})
    for contract in contracts:
        identity=contract['id'];row=next(r for r in rows if r['id']==identity)
        expected={rel:p['freeze_hashes'].get(rel) for rel in ROUND71_INTEGRATION_PRODUCERS[identity]}
        if None in expected.values() or contract.get('producer_hashes')!=expected:
            raise runner.SafetyError('producer source mismatch for '+identity)
        count=contract.get('minimum_checks');mode=contract.get('mode');name=contract.get('suite','')
        if type(count) is not int or count<=1 or mode not in {'short_headless','gui_required'} or not re.fullmatch(r'[A-Za-z0-9_-]+_test',name):
            raise runner.SafetyError('explicit integration mode/positive non-placeholder coverage required')
        scene,script=contract.get('scene',''),contract.get('script','')
        missing=[rel for rel in [scene,script] if not rel or rel not in combined or not (Path(p['source_root'])/rel).is_file()]
        if missing:
            row.update(reason='approved test dependency not landed',missing=missing);continue
        if not scene.endswith('.tscn') or not script.endswith('.gd') or not scene.startswith(('tests/','newtests/')) or not script.startswith(('tests/','newtests/')):
            raise runner.SafetyError('owned test scene/script declaration required')
        # Every static resource of the newly supplied closure must already be an
        # explicit frozen input. No production implementation is copied here.
        todo=[scene,script];seen=set();protocol=False
        while todo:
            rel=todo.pop()
            if rel in seen:continue
            seen.add(rel)
            path=Path(p['source_root'])/rel
            if path.suffix not in {'.gd','.tscn','.tres'}:continue
            code='\n'.join(line for line in path.read_text(encoding='utf-8-sig').splitlines() if not line.lstrip().startswith(('#',';')))
            protocol=protocol or bool(re.search(r'print\(["\']RESULT\b',code))
            refs=set(re.findall(r'res://([^\s\"\'<>]+)',code))-round71_declared_outputs(code)
            for dep in refs:
                if '%' in dep or '{' in dep or not dep.endswith(('.gd','.tscn','.tres','.png','.svg','.json','.wav','.ogg','.dll')):continue
                if dep not in combined:
                    missing.append(dep)
                else:todo.append(dep)
        if missing or not protocol:
            row.update(reason='integration closure or RESULT producer NOTREADY',missing=sorted(set(missing)));continue
        if name in selected_contracts:
            raise runner.SafetyError('duplicate integration suite: '+name)
        if name in selection['names']:
            old_mode=next(k for k,v in selection['categories'].items() if name in v)
            if old_mode!=mode:
                raise runner.SafetyError('existing suite mode cannot change')
        else:
            selection['names'].append(name);selection['categories'].setdefault(mode,[]).append(name)
            if mode=='short_headless':selection['headless'].append(name)
        selection['mandatory_checks'][name]=max(count,selection['mandatory_checks'].get(name,0))
        selected_contracts[name]=dict(contract)
        row.update(status='READY',reason='approved source/test/count closure verified; behavior not run',contract=dict(contract))
    p.update(freeze_hashes=combined,freeze_files=sorted(combined),parent_source_fingerprint=round50_source_fingerprint(combined))
    selection.update(selected_count=len(selection['names']),headless_count=len(selection['headless']),
                     program_count=len(selection['names'])+len(selection['native_standalone']))
    round71_validate_selection(selection)


def round71_suite_command(engine,target,name,output,selection,window=False,user_root=None):
    contract=selection.get('scene_contracts',{}).get(name)
    if contract and contract['mode']=='gui_required' and not window:
        raise runner.SafetyError('GUI integration cannot run headless')
    command=round50_command(engine,target,name,output,window=window,user_root=user_root)
    invocation=selection.get('invocation_contracts',{}).get(name)
    if invocation:
        if name=='worker_content_environment_test' and (invocation['mode']!='no_receipt' or '--' in command):
            raise runner.SafetyError('worker45 explicit no-receipt mode mismatch')
        if name=='loader_error_boundary_test' and (invocation['mode']!='green' or command[-1]!='green'):
            raise runner.SafetyError('loader explicit green mode mismatch')
        if selection['mandatory_checks'].get(name)!=invocation['mandatory_checks']:
            raise runner.SafetyError('invocation mandatory mismatch')
    if contract:command[command.index('--scene')+1]='res://'+contract['scene']
    return command


def round71_analyze_suite(name,out,err,code,target,hashes,selection):
    row=analyze_round50_suite(name,out,err,code,target,hashes)
    minimum=selection['mandatory_checks'].get(name)
    count=(row.get('result') or {}).get('checks')
    if name=='match_view_test':
        bound=selection.get('semantic_contracts',{}).get(name)
        if bound!=round73_match_view_contract(target):
            row['passed']=False;row['reasons'].append('prepared_semantic_contract_mismatch')
    elif type(minimum) is not int or type(count) is not int or count<minimum:
        row['passed']=False;row['reasons'].append('prepared_mandatory_checks')
    if (name in selection.get('scene_contracts',{}) or
            (selection.get('round70_cardback_required') and name in ROUND70_REQUIRED_CHECKS)) and row['observed_checks']!=count:
        row['passed']=False;row['reasons'].append('integration_observed_checks')
    return row


def round71_current_preflight(project=PROJECT, approved_root=Path('E:/scratch')):
    p=round50_preflight(project,approved_root,current_approved=True)
    p['source_root']=Path(project).as_posix()
    return p


def round73_native_preflight(selection,env,target):
    scoped=dict(selection)
    if selection.get('execution_scope')=='current_headless_only':
        scoped['names']=list(selection['headless'])
    return round42_static_preflight(scoped,env,target)


def round73_origin_drift(preflight):
    origin=preflight.get('origin_source_root')
    if not origin:return []
    root=runner.physical_e(origin)
    return sorted(rel for rel,sha in preflight['freeze_hashes'].items()
        if not (root/rel).is_file() or digest(root/rel)!=sha)


def round73_headless_preflight(preflight):
    """Explicit headless scope keeps GUI NOTREADY; no GUI evidence substituted."""
    import copy
    p=copy.deepcopy(preflight);selection=p['selection']
    selection['execution_scope']='current_headless_only'
    selection['invocation_contracts']={
        'worker_content_environment_test':{'mode':'no_receipt','mandatory_checks':45,'quiet_checks':True,
            'unselected_receipt_mode_checks':56},
        'server_shutdown_close_handoff_test':{'mode':'current_close_handoff','mandatory_checks':86},
        'loader_error_boundary_test':{'mode':'green','mandatory_checks':62},
    }
    import subprocess
    identity={}
    for key,command in [('git_head',['git','rev-parse','HEAD']),('git_status',['git','status','--short'])]:
        result=subprocess.run(command,cwd=p['source_root'],capture_output=True,text=True,encoding='utf-8',timeout=30)
        if result.returncode:raise runner.SafetyError('repository identity read failed')
        identity[key]=result.stdout
    p['source_identity']=dict(identity,repository=Path(p['source_root']).as_posix(),
        project_sha256=p['freeze_hashes']['project.godot'],deployment_sha256=p['freeze_hashes']['assets/config/server.cfg'])
    dependencies=set().union(*(set(scene['test_dependencies']) for scene in p['scenes']
        if scene['suite'] in selection['headless']))
    dependencies.update(round42_explicit_dependencies())
    for item in selection['required_harness_steps']:
        dependencies.update([item['execution_contract']['runner'],'tests/'+item['suite']+'.gd','tests/'+item['suite']+'.tscn'])
    # Production resources can themselves directly load test helpers; preserve
    # every declared test dependency in their actual frozen textual inputs.
    for rel in p['freeze_hashes']:
        if not rel.startswith(('tests/','newtests/')) and Path(rel).suffix in {'.gd','.tscn','.tres','.godot'}:
            code=(Path(p['source_root'])/rel).read_text(encoding='utf-8-sig')
            dependencies.update(re.findall(r'res://(tests/[^\s\"\'<>]+)',code))
    removed={rel:sha for rel,sha in p['freeze_hashes'].items()
        if rel.startswith(('tests/','newtests/')) and rel not in dependencies}
    hashes={rel:sha for rel,sha in p['freeze_hashes'].items() if rel not in removed}
    p['excluded_test_hashes'].update(removed)
    for folder in ['tests','newtests']:
        for path in (Path(p['source_root'])/folder).rglob('*'):
            rel=path.relative_to(p['source_root']).as_posix()
            if path.is_file() and path.suffix in {'.gd','.tscn','.py'} and rel not in hashes and not round50_excluded(rel):
                p['excluded_test_hashes'][rel]=digest(path)
    p.update(freeze_hashes=hashes,freeze_files=sorted(hashes),parent_source_fingerprint=round50_source_fingerprint(hashes))
    return p


def round71_prepare(preflight, approved=None):
    """Thin serialized input adapter; no freeze, import, wait or child polling."""
    import copy
    p=copy.deepcopy(preflight)
    p.setdefault('source_root',PROJECT.as_posix())
    round71_validate_selection(p['selection'])
    if p['selection'].get('semantic_contracts'):
        if p['selection']['semantic_contracts']!={'match_view_test':round73_match_view_contract(p['source_root'])}:
            raise runner.SafetyError('source semantic contract forged or changed')
    round71_verify_inputs(p['source_root'],p['freeze_hashes'])
    rows=[{'id':name,'status':'NOTREADY','execution_status':'not_run',
           'required_producers':paths,'reason':'approved test/source/count contract absent'}
          for name,paths in ROUND71_INTEGRATION_PRODUCERS.items()]
    if p['selection'].get('round70_cardback_required') and not p['selection'].get('resource_proof'):
        row=next(r for r in rows if r['id']=='cardback_privacy')
        expected=dict(ROUND70_APPROVED_PRODUCERS,**ROUND70_APPROVED_TESTS)
        mismatch=[rel for rel,sha in expected.items() if p['freeze_hashes'].get(rel)!=sha]
        omitted=[n for n in ROUND70_REQUIRED_CHECKS if n not in p['selection']['headless']]
        if mismatch or omitted:
            row.update(reason='approved round70 producer/test contract NOTREADY',mismatch=mismatch,omitted_suites=omitted)
        else:
            row.update(status='READY',reason='main approved round70 source/test contract; current full behavior not run',
                required_suites=dict(ROUND70_REQUIRED_CHECKS),producer_hashes=dict(ROUND70_APPROVED_PRODUCERS))
    base=copy.deepcopy(p)
    if approved is not None:
        round71_bind_integrations(p,approved,rows)
    headless_only=p['selection'].get('execution_scope')=='current_headless_only'
    for row in rows:
        row['required_for_execution']=not (headless_only and row['id']=='modal_regression')
    executors={rel:digest(PROJECT/rel) for rel in ROUND71_EXECUTORS}
    return {'schema':'round71-frozen-candidate/v1','plan_id':uuid.uuid4().hex,'preflight':p,'base_preflight':base,
            'approved_inputs':copy.deepcopy(approved),
            'executor_hashes':executors,'integration_dependencies':rows,
            'ready_for_full':p['status']=='selection_ready' and not p['blockers'] and all(r['status']=='READY' for r in rows),
            'ready_for_headless':headless_only and p['status']=='selection_ready' and not p['blockers']
                and all(r['status']=='READY' for r in rows if r['required_for_execution']),
            'sourcePASS':False,'releasePASS':False,'execution_status':'not_run'}


def round71_validate_prepared(plan, proof=False):
    import copy
    if plan.get('schema')!='round71-frozen-candidate/v1':
        raise runner.SafetyError('frozen input schema required')
    rebuilt=round71_prepare(plan['base_preflight'],plan.get('approved_inputs'))
    if any(rebuilt[key]!=plan[key] for key in ['preflight','integration_dependencies','ready_for_full','ready_for_headless']):
        raise runner.SafetyError('prepared selection/integration contract changed')
    p=copy.deepcopy(plan['preflight'])
    round71_validate_selection(p['selection'])
    if sorted(p['freeze_hashes'])!=sorted(p['freeze_files']) or p['parent_source_fingerprint']!=round50_source_fingerprint(p['freeze_hashes']):
        raise runner.SafetyError('prepared dependency fingerprint mismatch')
    headless_only=p['selection'].get('execution_scope')=='current_headless_only'
    ready=plan.get('ready_for_headless') if headless_only else plan.get('ready_for_full')
    if (not proof and (not ready or p['status']!='selection_ready'
            or p['blockers'] or any(r['status']!='READY' for r in plan['integration_dependencies']
                                   if r.get('required_for_execution',True)))):
        raise runner.SafetyError('NOTREADY final integration dependencies; no Godot launched')
    round71_verify_inputs(p['source_root'],p['freeze_hashes'])
    if plan.get('executor_hashes')!={rel:digest(PROJECT/rel) for rel in ROUND71_EXECUTORS}:
        raise runner.SafetyError('prepared executor hash mismatch')
    p['prepared_contract']=plan
    return p


def round71_resource_preflight(preflight):
    import copy
    p=copy.deepcopy(preflight);selection=p['selection']
    if selection.get('resource_proof'):return p
    selected={'net_server_relay_cfg_test','worker_content_environment_test'}
    selection['parent_candidate_counts']={'headless':selection['headless_count'],
        'formal':selection['selected_count'],'programs':selection['program_count']}
    names=['net_server_relay_cfg_test']
    selection['semantic_contracts']={n:c for n,c in selection.get('semantic_contracts',{}).items() if n in names}
    selection.update(names=names,headless=list(names),selected_count=1,headless_count=1,program_count=1,
        required_harness_steps=[],extracted_harness_contracts=[],required_harness_count=0,
        native_standalone=[],supplementary_gui=[],supplementary_gui_invocation_count=0,
        blocked_not_landed=[r for r in selection['blocked_not_landed'] if r.get('suite') in selected],
        blocked_extracted_harness=[],independent_loader_modes=[],resource_proof=True)
    selection['categories']={k:[n for n in group if n in names] for k,group in selection['categories'].items()}
    dependencies=set().union(*(set(scene['test_dependencies']) for scene in p['scenes'] if scene['suite'] in selected))
    hashes={rel:sha for rel,sha in p['freeze_hashes'].items()
            if not rel.startswith(('tests/','newtests/')) or rel in dependencies}
    p.update(freeze_hashes=hashes,freeze_files=sorted(hashes),parent_source_fingerprint=round50_source_fingerprint(hashes),
             harness_preflight=[],scenes=[r for r in p['scenes'] if r['suite'] in selected])
    p['blockers']=[r for r in p['blockers'] if r.get('suite') in selected or r.get('path') in hashes
                   or ('suite' not in r and 'path' not in r)]
    p['status']='selection_blocked' if p['blockers'] else 'selection_ready'
    round71_validate_selection(selection)
    return p


def round71_freeze_prepared(plan):
    """Create explicit immutable inputs, with every copy hash verified."""
    import copy
    p=round71_validate_prepared(plan,proof=True)
    root=runner.physical_e(p['approved_root'])
    owner=root/('round71-input-'+plan['plan_id'])
    if owner.exists():raise runner.SafetyError('input freeze already allocated')
    owner.mkdir();target=owner/'project';target.mkdir()
    result=copy.deepcopy(plan)
    source=runner.physical_e(p['source_root'])
    save(owner/'input-manifest.json',{'status':'copying','source':source.as_posix(),
         'hashes':p['freeze_hashes'],'sourcePASS':False,'releasePASS':False})
    for rel,sha in p['freeze_hashes'].items():
        dest=target/rel;dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(source/rel,dest)
        if digest(dest)!=sha:raise runner.SafetyError('input copy dependency mismatch: '+rel)
    baseline=target/ROUND50_BASE_MANIFEST;baseline.parent.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(source/ROUND50_BASE_MANIFEST,baseline)
    if digest(baseline)!=p['baseline_manifest_sha256']:
        raise runner.SafetyError('input baseline copy mismatch')
    round71_verify_inputs(source,p['freeze_hashes'])
    round71_verify_inputs(target,p['freeze_hashes'])
    for key in ['preflight','base_preflight']:
        result[key]['source_root']=target.as_posix()
        if p['selection'].get('execution_scope')=='current_headless_only':
            result[key]['origin_source_root']=source.as_posix()
        else:result[key]['excluded_test_hashes']={}
    result.update(input_copy_verified=True,original_source_root=source.as_posix(),input_owner=owner.as_posix())
    result['preflight']['input_owner']=owner.as_posix()
    result['base_preflight']['input_owner']=owner.as_posix()
    save(owner/'input-manifest.json',{'status':'verified','source':source.as_posix(),
         'hashes':p['freeze_hashes'],'sourcePASS':False,'releasePASS':False})
    result['retained_input_bytes']=runner.tree_bytes(owner)
    return result


def round71_execute_prepared(plan, proof=False, collect_failures=False, scheduler_config=None):
    p=round71_validate_prepared(plan,proof=proof)
    identity=plan.get('plan_id','')
    if not re.fullmatch('[0-9a-f]{32}',identity):
        raise runner.SafetyError('exact prepared plan UUID required')
    root=runner.physical_e(p['approved_root'])
    attempt=root/('round71-attempt-'+identity+'.json')
    runner.no_links(root)
    # Exclusive creation refuses both a concurrent executor and every prior
    # started failure. Preparing a new freeze is not resuming a failed child.
    if attempt.exists():raise runner.SafetyError('prepared run already started; no continuation/retry')
    try:
        with attempt.open('x',encoding='utf-8') as handle:
            json.dump({'status':'started','plan_id':identity,'proof':bool(proof),
                       'scheduler_config':scheduler_config or {'jobs':1},
                       'sourcePASS':False,'releasePASS':False},handle)
    except FileExistsError as exc:
        raise runner.SafetyError('concurrent prepared execution refused') from exc
    try:
        if scheduler_config is None:
            code=run_round50_full(p,collect_failures,proof,False)
        else:
            code=run_round50_full(p,collect_failures,proof,False,
                                  scheduler_config=scheduler_config)
    except Exception as exc:
        save(attempt,{'status':'failed','plan_id':identity,'error':repr(exc)})
        raise
    save(attempt,{'status':'finished','plan_id':identity,'exit':code,'proof':bool(proof),
                  'sourcePASS':False,'releasePASS':False})
    return code


def round73_preserve_unknown_scope(owner,m,row,target,byte_budget=8*1024**3):
    """Retain unknown scope verbatim; continuation permission is not deletion."""
    owner=Path(owner);active=m.get('active_manifest_relative','manifest.json')
    if active!='manifest.json' and active!='round73-continuation-manifest.json' and not re.fullmatch(r'round73-continuation-[0-9a-f]{32}-manifest\.json',active):
        raise runner.SafetyError('unknown ownership receipt')
    if load(runner.no_links(owner/active))!=m or owner.name!='isolated-'+m['run_id'] or Path(m['generated']).parent!=owner:
        raise runner.SafetyError('unknown parent identity/receipt')
    reclamation=row.get('runtime_reclamation',{})
    if (reclamation.get('status')!='blocked_no_deletion' or row.get('runtime_recycle_mutation_started')
            or not re.match(r'^(?:SafetyError: )?undeclared runtime files; no deletion: \[',reclamation.get('error',''))):
        raise runner.SafetyError('only pre-mutation unknown-file refusal can retain/continue')
    for proc in m['processes']:
        if (proc.get('exited') is not True or proc.get('active_owned_processes')!=0
                or proc.get('log_handles_released') is not True or proc.get('budget_failure') not in (None,'timeout')):
            raise runner.SafetyError('Job/handles/budget safety stop')
    procs=[proc for proc in m['processes'] if proc['label']==row['phase']+'-'+row['suite'] and proc['command']==row['command']]
    if len(procs)!=1:raise runner.SafetyError('exact owned process missing')
    pairs=[pair for pair in m['suite_runtime_owners'] if pair[0]['generated']==str(Path(row['fixture_root']))]
    if len(pairs)!=1:raise runner.SafetyError('unknown runtime identity')
    for binding in pairs[0]:
        directory=runner.contained(Path(binding['generated']),m['generated']);stat=directory.stat()
        if ([stat.st_dev,stat.st_ino]!=binding['directory_identity'] or binding['parent_run_id']!=m['run_id']
                or binding['parent_generated']!=m['generated'] or binding['phase']!=row['phase'] or binding['suite']!=row['suite']
                or binding['frozen_fingerprint']!=round50_source_fingerprint(m['frozen_hashes'])):
            raise runner.SafetyError('runtime identity mismatch')
        receipt=load(runner.no_links(Path(binding['owner'])/'manifest.json'))
        if receipt!=dict(binding,processes=[procs[0]]):raise runner.SafetyError('runtime receipt mismatch')
        runner.tree_bytes(directory)  # recursive no-links, metadata only
    if snapshot_hashes([Path(rel) for rel in m['frozen_hashes']],Path(target))!=m['frozen_hashes']:
        raise runner.SafetyError('frozen drift')
    if m.get('prepared_contract') and round73_origin_drift(m['prepared_contract']['preflight']):
        raise runner.SafetyError('source drift')
    charged=runner.tree_bytes(owner)+m.get('retained_input_bytes',0)
    if charged>byte_budget:raise runner.SafetyError('byte_budget')
    if shutil.disk_usage(owner).free<1024**3:raise runner.SafetyError('min_free')
    output=Path(row['fixture_root']);metadata=[]
    for file in output.rglob('*'):
        runner.no_links(file)
        if file.is_file():
            stat=file.stat();metadata.append({'path':file.relative_to(output).as_posix(),'bytes':stat.st_size,
                'identity':[stat.st_dev,stat.st_ino],'content_read':False})
    return {'status':'retained_unknown_scope','retained':metadata,'retained_files_verified':True,
        'reclaimed_bytes':0,'artifacts':[],'original_refusal':reclamation['error'],'no_reads_moves_or_deletes':True,
        'charged_bytes':charged,'byte_budget':byte_budget,'quota_owner':m['generated']}


def round73_continuation_names(m):
    if not m.get('archive_verified') or m.get('final_drift'):
        raise runner.SafetyError('continuation archive/source drift')
    if any(p.get('exited') is not True or p.get('active_owned_processes')!=0 or p.get('log_handles_released') is not True for p in m['processes']):
        raise runner.SafetyError('continuation Job/handles unsafe')
    rows=[r['suite'] for r in m['suites']]
    launched=[p['label'][9:] for p in m['processes'] if p['label'].startswith('complete-')]
    if len(rows)!=len(set(rows)) or len(launched)!=len(set(launched)) or set(rows)!=set(launched):
        raise runner.SafetyError('started scene missing row; never retry')
    if not set(rows).issubset(m['selected_suites']):raise runner.SafetyError('unselected row')
    missing=[n for n in m['selected_suites'] if n not in rows]
    if not missing:raise runner.SafetyError('no unstarted scenes')
    return missing


def round73_continue_retained(manifest,approved_root):
    """Authorized same-owner continuation; original stop manifest is immutable."""
    import copy
    path=runner.contained(Path(manifest),runner.physical_e(approved_root));old=load(path);owner=path.parent
    names=round73_continuation_names(old);original_sha=digest(path)
    generated=Path(old['generated']);target=generated/'project';engine=generated/'Godot.exe';fixtures=generated/'f';evidence=owner/'evidence'
    if owner.name!='isolated-'+old['run_id'] or generated.parent!=owner or not generated.is_dir():
        raise runner.SafetyError('retained original owner required')
    p=copy.deepcopy(old['prepared_contract']['preflight'])
    before=old['freeze_before'];frozen=old['frozen_hashes'];files=[Path(rel) for rel in before]
    if p['freeze_hashes']!=before or p['selection']!=old['selection'] or round73_origin_drift(p):
        raise runner.SafetyError('continuation original source mismatch')
    if snapshot_hashes(files,Path(p['source_root']))!=before or snapshot_hashes(files,target)!=frozen or digest(engine)!=old['engine_sha256']:
        raise runner.SafetyError('retained freeze/engine drift')
    if any(digest(owner/i['path'])!=i['sha256'] for i in old['logs']):raise runner.SafetyError('parent raw archive drift')
    if any((evidence/('complete-'+name+'.'+role+'.log')).exists() for name in names for role in ['stdout','stderr']):
        raise runner.SafetyError('unstarted scene already has logs')
    current=owner/('round73-continuation-'+uuid.uuid4().hex+'-manifest.json')
    attempt=owner/('round73-continuation-attempt-'+original_sha+'.json')
    with attempt.open('x',encoding='utf-8') as handle:json.dump({'parent_sha256':original_sha,'requested':names,'sourcePASS':False},handle)
    contracts=round73_retention_contract(target,frozen)
    m=copy.deepcopy(old);m['active_manifest_relative']=current.name;m['retention_contracts']=contracts
    m['retain_unknown_no_delete']=True
    m['continuation_history']=copy.deepcopy(old.get('continuation_history',[]))+([copy.deepcopy(old['continuation'])] if old.get('continuation') else [])
    m['continuation']={'claim':'same_frozen_unstarted_only_not_new_full','parent_manifest':path.as_posix(),
        'parent_manifest_sha256':original_sha,'parent_source_fingerprint':old['parent_source_fingerprint'],
        'frozen_source_fingerprint':old['frozen_source_fingerprint'],'requested':names,'prior_executed':[r['suite'] for r in old['suites']],
        'original_stop':old.get('error'),'executor_hashes':{rel:digest(PROJECT/rel) for rel in ROUND71_EXECUTORS},
        'new_freeze':False,'import_repeated':False,'prerequisite_repeated':False,'harness_repeated':False}
    m.pop('error',None);m['cleanup']='retained_protected_no_shared_deletion';m['passed']=False
    # Finalize the old unknown refusal without reading or deleting its scope.
    last=m['suites'][-1]
    save(current,m)
    last['runtime_reclamation']=round73_preserve_unknown_scope(owner,m,last,target)
    save(owner/('round73-resource-finalized-'+current.stem+'.json'),{'parent_manifest_sha256':original_sha,'contracts':contracts,
        'suite':last['suite'],'runtime_reclamation':last['runtime_reclamation'],'sourcePASS':False})
    restart=next((r for r in m['suites'] if r['suite']=='net_server_gateway_restart_test'),None)
    if restart:
        log=evidence/'complete-net_server_gateway_restart_test.stdout.log'
        m['restart_current']={'runs':1,'correctness_budget_seconds':restart['budget']['seconds'],
            'correctness_passed':restart['passed'],'declared_checks':restart['result']['checks'],
            'observed_checks':restart['observed_checks'],'stdout_sha256':digest(log),'not_rerun':True,
            'performance_gate':[json.loads(line.split(' ',1)[1]) for line in log.read_text(encoding='utf-8').splitlines() if line.startswith('GATEWAY_PERFORMANCE_GATE ')]}
    save(current,m)
    env=os.environ.copy()
    for key,sub in [('APPDATA','appdata'),('LOCALAPPDATA','localappdata'),('TEMP','tmp'),('TMP','tmp'),('TMPDIR','tmp')]:env[key]=(generated/sub).as_posix()
    for key in list(env):
        if key.startswith(('HERMES_ASSEMBLY_','FATE_','FD_','ROUND47_')) or key=='HERMES_RECOVERY_VALIDATION_ROOT':env.pop(key,None)
    budgets={'seconds':180,'bytes':8*1024**3-old['retained_input_bytes'],'min_free':1024**3}
    print(json.dumps({'continuation_manifest':current.as_posix(),'parent':path.as_posix(),'requested_count':len(names),'same_frozen':True},ensure_ascii=False),flush=True)
    try:
        for name in names:
            if round73_origin_drift(p) or snapshot_hashes(files,Path(p['source_root']))!=before or snapshot_hashes(files,target)!=frozen:
                raise runner.SafetyError('continuation source/frozen drift; nextcandidate required')
            output=round61_allocate_runtime(fixtures,m,'complete',m['selected_suites'].index(name),name)
            local=env.copy()
            for key,sub in [('APPDATA','appdata'),('LOCALAPPDATA','localappdata')]:
                (output/sub).mkdir();local[key]=(output/sub).as_posix()
            (output/'localappdata/hermes/cache/scratch').mkdir(parents=True)
            local['FATE_TEST_SCRATCH_ROOT']=output.as_posix();local['ROUND47_ROUTE_ROOT']=output.as_posix()
            if name in ROUND50_CURRENT_CHECKS:local['ROUND56_HANDOFF_ROOT']=output.as_posix();local['HERMES_SHUTDOWN_TEST_ROOT']=output.as_posix()
            budget=dict(budgets)
            if name=='net_server_gateway_restart_test':local['FATE_R39_CORRECTNESS']='1';budget['seconds']=600
            if name in m['selection']['categories']['performance']:budget['seconds']=600
            command=round71_suite_command(engine,target,name,output,m['selection']);label='complete-'+name
            row={'suite':name,'phase':'complete','command':command,'fixture_root':output.as_posix(),'budget':budget,'continuation':True,
                'explicit_environment':{key:local[key] for key in ['APPDATA','LOCALAPPDATA','FATE_TEST_SCRATCH_ROOT']}}
            m['stage']='continuation-'+name;save(current,m)
            try:
                out,err,code=runner.execute(command,local,generated,evidence,label,budget,m['processes'])
                row.update(exit=code,**round71_analyze_suite(name,out,err,code,target,frozen,m['selection']))
            except Exception as exc:
                code=m['processes'][-1].get('exit_code');out=(evidence/(label+'.stdout.log')).read_text(encoding='utf-8');err=(evidence/(label+'.stderr.log')).read_text(encoding='utf-8')
                row.update(exit=code,**analyze(out,err,code),execution_error=str(exc));row['passed']=False
            row['parallel_drift']=round73_origin_drift(p);row['current_vs_frozen']=list(row['parallel_drift'])
            row['frozen_drift']=[rel for rel,sha in frozen.items() if digest(target/rel)!=sha]
            if row['parallel_drift'] or row['frozen_drift']:row['passed']=False;row['reasons'].append('source_or_frozen_drift')
            m['suites'].append(row);save(current,m)
            try:
                row['runtime_reclamation']=round61_reclaim_runtime(owner,m,row,target)
                artifacts=row['runtime_reclamation']['artifacts'];m['worker_artifacts'].extend(artifacts)
                m['worker_engine_errors'].extend(fixture_engine_errors(artifacts,owner))
            except Exception as exc:
                row['runtime_reclamation']={'status':'blocked_no_deletion','error':str(exc)};save(current,m)
                row['runtime_reclamation']=round73_preserve_unknown_scope(owner,m,row,target)
                save(current,m)
            save(current,m)
            if not round43_continue_after(row,m['processes'][-1],True):raise runner.SafetyError('continuation safety stop')
    except Exception as exc:m['error']=type(exc).__name__+': '+str(exc)
    finally:
        m['final_drift']=round73_origin_drift(p);m['continuation']['original_manifest_unchanged']=digest(path)==original_sha
        m['continuation']['completed']=[r['suite'] for r in m['suites'][len(old['suites']):]]
        m['continuation']['executor_unchanged']=all(digest(PROJECT/rel)==sha for rel,sha in m['continuation']['executor_hashes'].items())
        job0=all(proc.get('exited') is True and proc.get('active_owned_processes')==0 and proc.get('log_handles_released') is True for proc in m['processes'])
        if job0:
            for log in fixtures.rglob('*.log'):
                rel=log.relative_to(fixtures)
                if round61_protected(rel,contracts):continue
                runner.no_links(log)
                dest=owner/('round73-worker-'+current.stem)/rel;dest.parent.mkdir(parents=True,exist_ok=True)
                sha=digest(log);shutil.copyfile(log,dest)
                if digest(dest)!=sha:raise runner.SafetyError('continuation retained log archive mismatch')
                item={'path':dest.relative_to(owner).as_posix(),'sha256':sha,'verified':True};m['worker_artifacts'].append(item)
                errors=[line for line in log.read_text(encoding='utf-8').splitlines() if re.search(r'SCRIPT ERROR|SHADER ERROR|^\s*ERROR:',line)]
                if errors:m['worker_engine_errors'].append({'path':item['path'],'lines':errors})
        else:m['error']=m.get('error','')+'; owned_process_exit_or_log_release_unverified'
        m['logs']=[{'path':f.relative_to(owner).as_posix(),'sha256':digest(f)} for f in evidence.rglob('*') if f.is_file()]+m['worker_artifacts']
        m['archive_verified']=all(digest(owner/i['path'])==i['sha256'] for i in m['logs']) and digest(path)==original_sha
        m['aggregate_charged_bytes']=runner.tree_bytes(owner)+runner.tree_bytes(p['input_owner'])
        m['sourcePASS']=False;m['releasePASS']=False;m['summary']=summarize_round50_current(m);m['passed']=False
        save(current,m)
        print(json.dumps({'manifest':current.as_posix(),**m['summary']},ensure_ascii=False),flush=True)
    return 0 if not m.get('error') and all(r['passed'] for r in m['suites']) and len(m['suites'])==len(m['selected_suites']) else 1


def _add_scheduler_cli(parser):
    parser.add_argument('--jobs', type=int, choices=(1, 2, 4), default=1,
                        help='bounded suite jobs; default 1 preserves serial behavior')
    parser.add_argument('--cpu-budget', type=int,
                        help='explicit aggregate CPU reservation for jobs>1')
    parser.add_argument('--memory-budget-bytes', type=int,
                        help='explicit aggregate memory reservation for jobs>1')
    parser.add_argument('--disk-budget-bytes', type=int,
                        help='explicit aggregate disk reservation for jobs>1')
    parser.add_argument('--cancel-file',
                        help='existing file requests scheduler cancellation; no retry or continuation')


def _scheduler_cli_config(args):
    return {'jobs': args.jobs, 'cpu_budget': args.cpu_budget,
            'memory_budget_bytes': args.memory_budget_bytes,
            'disk_budget_bytes': args.disk_budget_bytes,
            'cancel_file': args.cancel_file}


def _scheduler_cli_is_nondefault(args):
    return (args.jobs != 1 or args.cpu_budget is not None or
            args.memory_budget_bytes is not None or args.disk_budget_bytes is not None or
            args.cancel_file is not None)


def round71_entry():
    parser=argparse.ArgumentParser(description='Thin staged adapter to the existing bounded scheduler.')
    parser.add_argument('--round71',action='store_true')
    mode=parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--prepare-candidate',metavar='OUTPUT_JSON')
    mode.add_argument('--execute-prepared',metavar='INPUT_JSON')
    mode.add_argument('--continue-retained',metavar='STOP_MANIFEST')
    parser.add_argument('--approved-root',required=True)
    parser.add_argument('--source-root',default=PROJECT.as_posix())
    parser.add_argument('--approved-inputs',metavar='MAIN_APPROVED_JSON')
    parser.add_argument('--freeze-inputs',action='store_true')
    parser.add_argument('--headless-only',action='store_true',help='Explicit current headless scope; GUI stays NOTREADY/not_run')
    parser.add_argument('--proof-two-scenes',action='store_true')
    parser.add_argument('--collect-failures',action='store_true')
    _add_scheduler_cli(parser)
    args=parser.parse_args()
    root=runner.physical_e(args.approved_root)
    if args.continue_retained:
        if (_scheduler_cli_is_nondefault(args) or args.prepare_candidate or args.execute_prepared
                or args.freeze_inputs or args.headless_only or args.proof_two_scenes or args.approved_inputs):
            parser.error('continuation cannot change scheduler, refreeze, retoken or change mode')
        return round73_continue_retained(args.continue_retained,root)
    if args.prepare_candidate:
        if args.collect_failures or _scheduler_cli_is_nondefault(args):
            parser.error('scheduler and collect-failures belong to execute-prepared stage')
        output=Path(args.prepare_candidate)
        if not output.is_absolute() or output.drive.upper()!='E:' or '..' in output.parts:
            parser.error('explicit physical E output required')
        runner.no_links(output.parent)
        if not output.parent.resolve().is_relative_to(root) or output.exists():
            parser.error('new output in approved root required')
        p=round71_current_preflight(Path(args.source_root),root)
        p['source_root']=Path(args.source_root).as_posix()
        if args.headless_only:p=round73_headless_preflight(p)
        if args.proof_two_scenes:p=round71_resource_preflight(p)
        plan=round71_prepare(p,load(args.approved_inputs) if args.approved_inputs else None)
        if args.freeze_inputs:plan=round71_freeze_prepared(plan)
        with output.open('x',encoding='utf-8') as handle:json.dump(plan,handle,ensure_ascii=False,indent=2)
        if load(output)!=plan:raise runner.SafetyError('prepared plan readback mismatch')
        print(json.dumps({'prepared':output.as_posix(),'ready_for_full':plan['ready_for_full'],
            'ready_for_headless':plan['ready_for_headless'],
            'formal':plan['preflight']['selection']['selected_count'],
            'headless':plan['preflight']['selection']['headless_count'],
            'dependencies':len(plan['preflight']['freeze_hashes']),
            'integration_dependencies':plan['integration_dependencies'],'godot_launch_count':0},ensure_ascii=False),flush=True)
        return 0
    if args.freeze_inputs or args.approved_inputs or args.headless_only:parser.error('freeze/approval/scope belongs to prepare stage')
    path=runner.contained(Path(args.execute_prepared),root)
    plan=load(path)
    if runner.physical_e(plan['preflight']['approved_root'])!=root:
        raise runner.SafetyError('prepared approved root mismatch')
    if bool(plan['preflight']['selection'].get('resource_proof'))!=bool(args.proof_two_scenes):
        raise runner.SafetyError('prepared full/proof mode mismatch')
    return round71_execute_prepared(plan, args.proof_two_scenes, args.collect_failures,
                                    _scheduler_cli_config(args))


def round50_preflight_entry():
    parser = argparse.ArgumentParser()
    parser.add_argument('--round50',action='store_true')
    mode=parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--preflight-only',action='store_true')
    mode.add_argument('--complete-candidate',action='store_true')
    mode.add_argument('--resource-proof-two-scenes',action='store_true')
    mode.add_argument('--contract-proof-seven-scenes',action='store_true')
    parser.add_argument('--collect-failures',action='store_true')
    parser.add_argument('--approved-root',required=True)
    parser.add_argument('--resume-current-manifest')
    _add_scheduler_cli(parser)
    args = parser.parse_args()
    if args.resume_current_manifest and not args.complete_candidate:parser.error('resume requires complete-candidate')
    if args.preflight_only and args.collect_failures: parser.error('collect-failures requires complete-candidate')
    if args.preflight_only and _scheduler_cli_is_nondefault(args):
        parser.error('scheduler options belong to complete-candidate execution')
    result = round50_preflight(PROJECT,Path(args.approved_root),contract_proof=args.contract_proof_seven_scenes)
    if args.preflight_only:
        print(json.dumps(result,ensure_ascii=False,indent=2),flush=True)
        return 0 if result['status'] == 'selection_ready' else 1
    if args.resume_current_manifest:
        if _scheduler_cli_is_nondefault(args):
            parser.error('resume-current-manifest is serial legacy continuation; scheduler belongs to prepared execution')
        manifest=runner.contained(Path(args.resume_current_manifest),Path(args.approved_root))
        return run_round50_missing(result,manifest)
    return run_round50_full(
        result, args.collect_failures, args.resource_proof_two_scenes,
        args.contract_proof_seven_scenes, scheduler_config=_scheduler_cli_config(args))


if __name__ == '__main__':
    if '--round71' in sys.argv:
        raise SystemExit(round71_entry())
    if '--round50' in sys.argv:
        raise SystemExit(round50_preflight_entry())
    if '--round43-reparse' in sys.argv:
        original=Path(sys.argv[sys.argv.index('--round43-reparse')+1])
        m=round43_reparse_archive(original)
        dest=original.parent/'reparsed-manifest.json'
        if dest.exists(): raise runner.SafetyError('derived manifest already exists; original bytes never overwritten')
        save(dest,m)
        print(json.dumps({'reparsed_manifest':str(dest),'original_manifest_unchanged':True,**m['summary']},ensure_ascii=False))
        raise SystemExit(0 if m['passed'] else 1)
    if '--round43' in sys.argv:
        raise SystemExit(run_round40(43))
    if '--round42' in sys.argv:
        raise SystemExit(run_round40(42))
    if '--round41' in sys.argv:
        raise SystemExit(run_round40(41))
    if '--round40' in sys.argv:
        raise SystemExit(run_round40())
    if '--summarize-from' in sys.argv:
        parser_tests()
        raise SystemExit(summarize_archived(sys.argv[sys.argv.index('--summarize-from') + 1]))
    if '--reparse-from' in sys.argv:
        parser_tests()
        raise SystemExit(reparse_archived(sys.argv[sys.argv.index('--reparse-from') + 1]))
    if '--finalize' in sys.argv:
        raise SystemExit(finalize(sys.argv[sys.argv.index('--finalize') + 1]))
    if '--resume' in sys.argv:
        raise SystemExit(resume(sys.argv[sys.argv.index('--resume') + 1]))
    if '--parser-only' in sys.argv:
        parser_tests()
        print('strict parser tests PASS')
    else:
        raise SystemExit(run())
