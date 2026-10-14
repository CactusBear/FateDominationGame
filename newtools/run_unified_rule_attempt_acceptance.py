#!/usr/bin/env python
"""RA-00 read-only discovery freeze. Integrity PASS is never admission.

freeze writes only the explicitly supplied evidence path outside the project.
verify reads bytes and real process receipts; it executes no game/session rules.
A1-04 proof is optional and must bind real scene receipts to this exact freeze.
Even a verified projection is partial evidence, never full support or admission.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

ROOTS = ('broadcast_requires_confirm players registry registered_effects game_data progress map effects '
         'time_points facts log_context restrictions attributes attack_templates event_templates '
         'situation_templates spell_templates ai_scope ai_attempts execution_context').split()
ADAPTERS = ('pure_fields collection_identity_abi callable_rebinding static_isolation rule_journal_trace '
            'metadata_lifo known_rng owned_continuations owned_delivery isolated_sinks a1_origin_validation').split()
TREES = ('scripts', 'assets', 'data', 'addons', 'tests', 'newtests', 'newtools', 'json_maker')
TOP_FILES = ('project.godot', 'icon.svg', 'export_presets.cfg', 'hermesWarning.txt')
ENTRY_WORDS = ('Move', 'MoveLocation', 'SetLocation', 'PayMagic', 'EditMagic', 'PlaySkill', 'Deploy',
               'submit_option_choice', 'submit_active_choice', 'submit_player_selection',
               'submit_card_selection', 'submit_location_selection', 'run_base_func',
               'run_func_descriptor', 'set_option_quantity')
DESCRIPTORS = {'move', 'move_location', 'set_location', 'edit_magic', 'pay_magic', 'play_skill',
               'deploy', 'activate_effect', 'forecast_rule_action', 'execute_rule_action'}
PROJECTION_FILES = ('scripts/match/rule_state.gd', 'scripts/match/rule_checkpoint.gd',
                    'scripts/system/session_token.gd', 'scripts/system/session_context.gd',
                    'scripts/system/session_generation.gd',
                    'newtests/session_checkpoint_generation_test.gd',
                    'newtests/session_checkpoint_generation_test.tscn')
PROJECTION_CHECKS = '''trusted_context_created
capture_real_indirect_graph
token_leaf_not_object_record
context_leaf_not_object_record
service_metadata_outside_graph
same_generation_rollback_allowed
rollback_values_and_collection_identity
rollback_declared_rng
signal_callable_bound_handles_and_target_rollback
context_internals_never_restored
rollback_preserves_current_eligibility
real_callable_preserves_bound_handle
real_weakref_preserves_handle
new_generation_old_checkpoint_rejected
cross_generation_zero_rule_rng_setter_writes
restore_cannot_revive_old_current
restore_cannot_erase_old_origin_binding
missing_capture_context_fail_closed
stale_capture_context_fail_closed
closed_generation_rejects_without_writes
projection_does_not_allocate_handle_ids
different_process_handle_history_same_projection
declared_origin_remains_in_projection
handle_alias_relation_remains_in_projection
projection_indirect_handles_and_service_are_leaves
same_graph_projection_recomputes
business_state_changes_projection
replay_snapshot_uses_same_handle_projection
ra00_invalid_budget_unknown_preserved
formal_two_player_graph_created
formal_registry_effects_nonempty
formal_capture_explicit_trusted_context
formal_checkpoint_capture_with_source
formal_passive_cannot_admit
formal_passive_export_no_error
formal_passive_export_recomputes
formal_passive_live_netids_unchanged
formal_passive_audit_unchanged
formal_passive_logs_trace_unchanged
formal_passive_declared_rng_and_global_sentinel
formal_passive_issuance_binding_current_unchanged
formal_passive_full_checkpoint_prestate_unchanged
formal_export_session_metadata_not_object_definitions'''.splitlines()
GAPS = [
    {'id': 'A1-04-projection', 'reason': 'A1-04 ABI已实现；缺本次冻结真实投影证明时仍未验',
     'blocks': ['session_leaf_exclusion', 'origin_support_graph', 'pre_restore_context_validation'],
     'owner': 'RA-00/A1-04', 'verification': 'unknown_not_run'},
    {'id': 'executable-fork', 'reason': '单向 NetIds 投影不证明可执行fork/Callable重绑定', 'owner': 'RA-05'},
    {'id': 'passive-state', 'reason': '全字段纯get/set、metadata、statics/等待/票据归属未完整证明', 'owner': 'RA-04'},
    {'id': 'random-closure', 'reason': '已知流快照不证明无原始全局随机可达路径', 'owner': 'RA-01'},
    {'id': 'sink-closure', 'reason': '同步recorded/业务I/O全闭包未认证', 'owner': 'RA-02/RA-06/RA-07'},
    {'id': 'whole-action-endpoint', 'reason': '费用pending/guard/选择/归属尾部不能等同completed', 'owner': 'RA-07/RA-12'},
    {'id': 'consumer-closure', 'reason': '文本库存含动态Callable/self_var，非全仓语义闭包', 'owner': 'RA-06/RA-16/RA-21'},
]


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def load(path: Path):
    return unique_json(path.read_text(encoding='utf-8-sig'))


def digest(value) -> str:
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                    separators=(',', ':')).encode()).hexdigest()


def project_files(project: Path) -> dict[str, str]:
    files = {}
    for tree in TREES:
        for path in sorted((project / tree).rglob('*')):
            if path.is_file() and not any(p in {'.godot', '__pycache__', 'runtime_reports'} for p in path.parts):
                if path.name.startswith('~') and path.suffix == '.dll':
                    continue  # Godot hot-reload clone, not the declared formal DLL.
                files[path.relative_to(project).as_posix()] = sha(path)
    for name in TOP_FILES:
        if (project / name).is_file():
            files[name] = sha(project / name)
    if not files or not any(p.startswith('data/') for p in files):
        raise ValueError('empty formal data/source inventory')
    return files


def declaration(text: str, key: str) -> list[str]:
    match = re.search(r'"' + re.escape(key) + r'"\s*:\s*\[(.*?)\]', text, re.S)
    if not match:
        raise ValueError('missing declaration ' + key)
    return re.findall(r'"([^"]+)"', match.group(1))


def entries(project: Path) -> dict:
    rows = []
    for path in sorted((project / 'scripts').rglob('*.gd')):
        for number, line in enumerate(path.read_text(encoding='utf-8-sig').splitlines(), 1):
            if line.lstrip().startswith('#'):
                continue
            found = [word for word in ENTRY_WORDS if re.search(r'\b' + word + r'\b', line)]
            if found:
                rows.append({'path': path.relative_to(project).as_posix(), 'line': number,
                             'symbols': found, 'text': line.strip(), 'support': 'unknown'})
    formal = []
    def visit(value, pointer, path):
        if isinstance(value, dict):
            if value.get('func_name') in DESCRIPTORS:
                formal.append({'path': path, 'pointer': pointer, 'operation': value['func_name'],
                               'descriptor': value, 'support': 'unknown'})
            for key, item in value.items():
                visit(item, pointer + '/' + str(key).replace('~', '~0').replace('/', '~1'), path)
        elif isinstance(value, list):
            for index, item in enumerate(value):
                visit(item, pointer + '/' + str(index), path)
    for path in sorted((project / 'data').rglob('*.json')):
        visit(load(path), '', path.relative_to(project).as_posix())
    return {'scan': 'literal production script lines + recursive formal JSON descriptors; not semantic closure',
            'script_calls': rows, 'formal_descriptors': formal, 'unresolved': ['aliases', 'dynamic_callable',
            'self_var_methods', 'bound_targets', 'reachable_getters_setters', 'listener_cascades']}


def freeze(project: Path, engine: Path, spec: Path, a1: Path, policies: Path,
           projection_proof: Path | None = None) -> dict:
    specification = load(spec)
    handoff = load(a1)
    state = (project / 'scripts/match/rule_state.gd').read_text(encoding='utf-8-sig')
    files = project_files(project)
    inventory = entries(project)
    dependencies = {str(path.resolve()): sha(path) for path in (engine, spec, a1, policies)}
    old = specification['read_source_sha256']
    drift = [{'path': path, 'spec_sha': expected, 'current_sha': files.get(path.removeprefix('res://'))}
             for path, expected in old.items() if files.get(path.removeprefix('res://')) != expected]
    manifest = {
        'schema': 'rule-attempt-discovery/v1', 'batch': 'RA-00', 'delivery': 'partial_full_graph_unknown',
        'project': str(project.resolve()), 'support': 'unknown', 'admission': None,
        'input_paths': {name: str(path.resolve()) for name, path in
                        [('engine', engine), ('spec', spec), ('a1', a1), ('policies', policies)]},
        'root_closure': declaration(state, 'required_roots'),
        'adapter_closure': declaration(state, 'required_adapters'),
        'source_data_engine_abi': {'files': files, 'external': dependencies,
                                   'project_fingerprint': digest(files)},
        'specification': specification,
        'a1_handoff': {'source': str(a1.resolve()), 'sha256': sha(a1), 'status': handoff['status'],
                       'interfaces': handoff['interfaces'], 'checkpoint_contract': handoff['checkpoint_contract'],
                       'root_propagation': handoff['root_propagation'], 'production_verified': False},
        'scope': {'parent': 'preserve pre-capture state/fact identities/tickets',
                  'child': 'restore only owned modifications, permanent abort only owned tickets',
                  'success': 'private release, never commit parent root',
                  'nonrollbackable': ['session_token/context/service_bindings', 'audit_identity',
                                     'transport_serial/broadcast_batch', 'delivered_external_observations']},
        'entry_inventory': inventory, 'spec_source_drift': drift,
        'capability_difference': [{'declaration': row, 'proof': 'unknown'} for row in specification['capabilities']],
        'state_contract': specification['state_manifest_contract'],
        'completion_contract': {'steps': specification['interface']['plan'],
            'endpoint': 'all declared steps + payment/LEAVE/ENTER listeners + owned continuations + pure postcondition',
            'excluded_endpoints': ['SetLocation=true', 'payment_pending', 'guard_pause', 'future_choice', 'unowned_tail']},
        'acceptance_matrix': [{**row, 'verification': 'unknown_not_run_RA00'} for row in specification['acceptance_matrix']],
        'legacy_success_baseline': {'kind': 'frozen_source_only_until_real_trace_receipt',
            'files': {p: h for p, h in files.items() if p in {
                'scripts/system/operations/Move.gd', 'scripts/system/operations/MoveLocation.gd',
                'scripts/system/operations/SetLocation.gd', 'scripts/system/global/effect_manager.gd',
                'data/masters/00006_kotomine_kirei/00006_kotomine_kirei.json'}},
            'runtime_trace': None, 'note': 'existing suite logs must be bound to these exact hashes, not prior wave totals'},
        'authorized_changes': [
            {'policy': 'B2', 'old': 'non-delayed usage/chosen/option_used before payment',
             'new': 'forecast then payment/listeners completed before any activation publication'},
            {'policy': 'B2/A9', 'old': 'placement/LEAVE/ENTER before payment',
             'new': 'payment/listeners completed then placement/LEAVE/ENTER and full cascade'},
            {'policy': 'B2', 'old': 'required choice may resume old unpaid tail',
             'new': 'failure prompt + cancel attempt; retry requires new scope'},
            {'policy': 'A4', 'old': 'LEAVE partial change before public rejection',
             'new': 'all public/free/deploy rejection prechecks before live changes'},
            {'policy': 'preserved', 'old': 'synchronous recorded/payload/identity/nonconflicting relative order',
             'new': 'unchanged; do not defer payment listeners or allocate savepoint audit identity'}],
        'named_difference': GAPS,
        'a1_followup': ['consume actual A1-04 projection and exact source/ABI hashes',
            'validate token/context leaves and nonrollbackable service metadata exclusion',
            'probe origin graph/metadata/Callable roots without binding or creating current origin',
            'validate context before any restoration writes and re-run graph export invariance',
            're-freeze full graph/closures and independently decide A9 feasibility; do not assume admitted'],
    }
    manifest['projection_evidence'] = {'status': 'unknown_not_run', 'source': None, 'sha256': None}
    if projection_proof is not None:
        manifest['projection_evidence'] = {'status': 'verified_partial',
            'source': str(projection_proof.resolve()), 'sha256': sha(projection_proof)}
        # A1-04 may unblock graph-kernel work, never the missing RA-04/fork/action proof.
        manifest['named_difference'] = [dict(row) for row in GAPS if row['id'] != 'A1-04-projection']
    else:
        manifest['named_difference'] = [dict(row) for row in GAPS]
    return manifest


def unique_json(text: str):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError('duplicate JSON field: ' + key)
            result[key] = value
        return result
    return json.loads(text, object_pairs_hook=pairs)


def parse_runtime(output: str, check_format: str = 'bool_last') -> tuple[list[tuple[str, str]], dict | None]:
    lines = output.splitlines()
    result_lines = [line[7:].strip() for line in lines if line.startswith('RESULT ')]
    checks = []
    for line in lines:
        if not line.startswith('CHECK '):
            continue
        tail = re.fullmatch(r'CHECK (.*?) (true|false)\s*', line)
        head = re.fullmatch(r'CHECK (true|false) (.*?)\s*', line)
        if check_format == 'bool_last' and tail:
            checks.append((tail[1], tail[2]))
        elif check_format == 'bool_first' and head:
            checks.append((head[2], head[1]))
        else:
            raise ValueError('unparseable CHECK: ' + line)
    if len(result_lines) != 1:
        return checks, None
    body = result_lines[0]
    if body.startswith('{'):
        return checks, unique_json(body)
    match = re.fullmatch(r'(?:(\S+)\s+)?checks=(\d+) failures=(\[.*\])', body)
    if not match:
        return checks, None
    return checks, {'suite': match[1], 'checks': int(match[2]), 'failures': unique_json(match[3])}


def check_log(receipt: dict, base: Path) -> list[str]:
    errors = []
    streams = []
    for name in ('stdout', 'stderr'):
        path = (base / receipt[name]).resolve()
        if sha(path) != receipt[name + '_sha256']:
            errors.append(name + '_fingerprint')
        streams.append(path.read_text(encoding='utf-8-sig', errors='replace'))
    output = '\n'.join(streams)
    if receipt.get('exit') != 0:
        errors.append('exit_nonzero')
    if re.search(r'SCRIPT ERROR|(?:^|\n)ERROR:', output):
        errors.append('script_or_engine_error')
    try:
        checks, result = parse_runtime(output, receipt.get('check_format', 'bool_last'))
    except (ValueError, TypeError) as exc:
        checks, result = [], None
        errors.append('runtime_parse:' + str(exc))
    if result is None:
        errors.append('RESULT_not_unique_or_invalid')
    elif (type(result.get('checks')) is not int or result['checks'] <= 0
          or result['checks'] != len(checks) or result.get('failures') != []):
        errors.append('RESULT_CHECK_mismatch_or_failures')
    if any(value == 'false' for _, value in checks):
        errors.append('CHECK_false')
    if not receipt.get('argv'):
        errors.append('argv_missing')
    for target in receipt.get('required_checks', []):
        if not any(label == target and value == 'true' for label, value in checks):
            errors.append('missing_CHECK:' + target)
    return errors


def verify_projection_proof(manifest: dict) -> list[str]:
    """Validate only A1-04's same-freeze projection, not a passive kernel or fork."""
    declaration = manifest.get('projection_evidence', {})
    if declaration.get('source') is None:
        return [] if declaration.get('status') == 'unknown_not_run' else ['projection_status_without_proof']
    path = Path(declaration['source'])
    if declaration.get('status') != 'verified_partial' or sha(path) != declaration.get('sha256'):
        return ['projection_proof_fingerprint_or_status']
    proof = load(path)
    frozen = manifest['source_data_engine_abi']
    errors = []
    if proof.get('schema') != 'a1-session-projection-proof/v1':
        errors.append('projection_proof_schema')
    if proof.get('project_fingerprint') != frozen['project_fingerprint']:
        errors.append('projection_mixed_freeze')
    for name in PROJECTION_FILES:
        if not frozen['files'].get(name) or proof.get('source_sha256', {}).get(name) != frozen['files'][name]:
            errors.append('projection_source_fingerprint:' + name)
    cases = proof.get('cases', [])
    if len(cases) != 2:
        return errors + ['projection_requires_two_independent_processes']
    pids, products, noise = [], [], []
    for index, row in enumerate(cases):
        prefix = 'projection_case:' + str(index) + ':'
        required = {**row, 'required_checks': PROJECTION_CHECKS}
        errors.extend(prefix + error for error in check_log(required, path.parent))
        if type(row.get('pid')) is not int or row['pid'] <= 0 or row.get('active_owned') != 0:
            errors.append(prefix + 'process_receipt')
        pids.append(row.get('pid'))
        argv = row.get('argv', [])
        if (not argv or Path(argv[0]).resolve() != Path(manifest['input_paths']['engine']).resolve()
                or '--headless' not in argv or '--scene' not in argv
                or '--script' in argv or '--import' in argv
                or argv[argv.index('--scene') + 1:argv.index('--scene') + 2]
                    != ['res://newtests/session_checkpoint_generation_test.tscn']
                or Path(row.get('cwd', '')).resolve() != Path(manifest['project']).resolve()):
            errors.append(prefix + 'engine_scene_or_cwd')
        noise.append('handle_noise' in argv)
        output = (path.parent / row['stdout']).read_text(encoding='utf-8-sig', errors='replace')
        def marker(name):
            found = [line[len(name) + 1:] for line in output.splitlines() if line.startswith(name + ' ')]
            if len(found) != 1:
                errors.append(prefix + 'missing_or_duplicate_marker:' + name)
                return None
            return found[0]
        graph_text, export_text = marker('REAL_GRAPH'), marker('PASSIVE_EXPORT')
        for name, value in [('REAL_GRAPH', graph_text), ('PASSIVE_EXPORT', export_text)]:
            if value is None:
                continue
            record = unique_json(value)
            valid = (record.get('support') == 'unknown'
                     and all(type(record.get(k)) is int and record[k] > 0 for k in ('objects', 'collections')))
            valid = valid and (record.get('captured') is True and record.get('error') == '' if name == 'REAL_GRAPH'
                               else record.get('first_error') == '' and record.get('second_error') == '')
            if not valid:
                errors.append(prefix + 'real_graph_not_proven:' + name)
        product = [marker(name) for name in ('PROCESS_PROJECTION', 'PROCESS_GRAPH_SHA', 'FORMAL_REPLAY_SHA')]
        if any(value is None or not re.fullmatch(r'[0-9a-f]+', value) for value in product):
            errors.append(prefix + 'projection_markers_invalid')
        if any(value is not None and len(value) != 64 for value in product[1:]):
            errors.append(prefix + 'projection_digest_invalid')
        products.append(product)
        marker('PROCESS_HANDLE')  # Handle values are observations, never authority.
    if pids[0] == pids[1] or sorted(noise) != [False, True]:
        errors.append('projection_independent_history_not_proven')
    if products[0] != products[1]:
        errors.append('projection_cross_process_mismatch')
    return errors


def verify(manifest: dict, receipts: Path | None = None, require_supported: bool = False,
           acceptance: bool = False) -> list[str]:
    errors = []
    for key, required in (('root_closure', ROOTS), ('adapter_closure', ADAPTERS)):
        actual = manifest.get(key, [])
        for name in required:
            if name not in actual:
                errors.append('missing_' + key + ':' + name)
        if len(actual) != len(set(actual)):
            errors.append('duplicate_' + key)
    project = Path(manifest['project'])
    frozen = manifest['source_data_engine_abi']
    current = project_files(project)
    for path in sorted(set(frozen['files']) | set(current)):
        if frozen['files'].get(path) != current.get(path):
            errors.append('source_or_data_fingerprint:' + path)
    if frozen['project_fingerprint'] != digest(frozen['files']):
        errors.append('project_fingerprint')
    for path, expected in frozen['external'].items():
        if not Path(path).is_file() or sha(Path(path)) != expected:
            errors.append('external_fingerprint:' + path)
    for name in ('engine', 'spec', 'a1', 'policies'):
        path = manifest['input_paths'][name]
        if path not in frozen['external']:
            errors.append('missing_frozen_input:' + name)
    actual_spec = load(Path(manifest['input_paths']['spec']))
    if manifest['specification'] != actual_spec:
        errors.append('spec_contract_mismatch')
    text = (project / 'scripts/match/rule_state.gd').read_text(encoding='utf-8-sig')
    for key, source_key in (('root_closure', 'required_roots'), ('adapter_closure', 'required_adapters')):
        if manifest[key] != declaration(text, source_key):
            errors.append('declaration_mismatch:' + key)
    contract = load(Path(manifest['a1_handoff']['source']))
    if manifest['a1_handoff']['interfaces'] != contract['interfaces']:
        errors.append('a1_public_ABI_mismatch')
    expected = manifest['specification']['acceptance_matrix']
    if len(expected) != 16 or [x['id'] for x in manifest['acceptance_matrix']] != [x['id'] for x in expected]:
        errors.append('acceptance_matrix_missing_or_reordered')
    if manifest.get('support') != 'unknown' or manifest.get('admission') is not None:
        errors.append('static_scan_cannot_admit')
    errors.extend(verify_projection_proof(manifest))
    differences = {x.get('id') for x in manifest.get('named_difference', [])}
    required_differences = {x['id'] for x in GAPS if x['id'] != 'A1-04-projection'}
    if manifest.get('projection_evidence', {}).get('source') is None:
        required_differences.add('A1-04-projection')
    for name in sorted(required_differences - differences):
        errors.append('missing_difference:' + name)
    if receipts:
        evidence = load(receipts)
        if evidence.get('project_fingerprint') != frozen['project_fingerprint']:
            errors.append('receipt_mixed_freeze')
        seen = set()
        for row in evidence.get('cases', []):
            case_id = row['id']
            if case_id in seen:
                errors.append('duplicate_receipt:' + case_id)
            seen.add(case_id)
            errors.extend(case_id + ':' + issue for issue in check_log(row, receipts.parent))
        if acceptance:
            for item in expected:
                if item['id'] not in seen:
                    errors.append('missing_acceptance_receipt:' + item['id'])
            # Downstream owns the actual per-gate red/green protocol; never substitute a boolean claim.
            errors.append('full_acceptance_blocked:per_gate_sensitivity_and_full_graph_closure_required')
    elif acceptance:
        errors.append('missing_acceptance_receipts')
    if require_supported:
        errors.append('unknown:full_graph/fork/passive_state/rng/sink/consumer/completion_proof_missing')
    return errors


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    f = sub.add_parser('freeze')
    for name in ('project', 'engine', 'spec', 'a1', 'policies', 'out'):
        f.add_argument('--' + name, type=Path, required=True)
    f.add_argument('--projection-proof', type=Path,
                   help='same-freeze A1-04 real scene proof; not full support')
    v = sub.add_parser('verify')
    v.add_argument('--manifest', type=Path, required=True)
    v.add_argument('--receipts', type=Path)
    v.add_argument('--require-supported', action='store_true')
    v.add_argument('--acceptance', action='store_true')
    args = parser.parse_args(argv)
    try:
        if args.command == 'freeze':
            if args.out.resolve().is_relative_to(args.project.resolve()):
                raise ValueError('evidence output must be outside project')
            if args.out.exists():
                raise ValueError('freeze output exists; use a fresh evidence path')
            manifest = freeze(args.project, args.engine, args.spec, args.a1, args.policies, args.projection_proof)
            args.out.parent.mkdir(parents=True, exist_ok=True)
            args.out.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
            errors = verify(manifest)
        else:
            errors = verify(load(args.manifest), args.receipts, args.require_supported, args.acceptance)
        for error in errors:
            print('CHECK ' + error + ' false')
        print('RESULT ' + json.dumps({'integrity': 'FAIL' if errors else 'PASS',
            'support': 'unknown', 'admission': None, 'errors': errors}, ensure_ascii=False))
        return int(bool(errors))
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print('ERROR input: ' + str(exc), file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
