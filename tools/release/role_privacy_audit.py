"""Static evidence harness. No Godot, export, package or secret-content reads."""
import ast
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import fnmatch

if not __debug__:
    raise RuntimeError('Run without -O / PYTHONOPTIMIZE: original assertion checks must execute')

SOURCE = Path(__file__).resolve().parents[2]
# Dry-run targets must be disjoint from source; nothing is written there.
RUN = SOURCE.parent / (SOURCE.name + '-role-privacy-dry-run-only')
EVIDENCE = SOURCE / 'tools/release/evidence/role-privacy'
EVIDENCE.mkdir(parents=True, exist_ok=True)
FIXTURES = SOURCE / 'tools/release/fixtures/role-privacy'
sys.path.insert(0, str(SOURCE / 'tools/release'))
import freeze_prepare as freeze
import release_contract as contract
import package_audit


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command(label, args, expected):
    env = dict(os.environ)
    env.update({key: str(EVIDENCE) for key in ('TMPDIR', 'TEMP', 'TMP')})
    env['PYTHONDONTWRITEBYTECODE'] = '1'
    result = subprocess.run(args, cwd=SOURCE, env=env, capture_output=True, text=True, encoding='utf-8', errors='replace')
    (EVIDENCE / (label + '.stdout.txt')).write_text(result.stdout, encoding='utf-8')
    (EVIDENCE / (label + '.stderr.txt')).write_text(result.stderr, encoding='utf-8')
    row = {'label': label, 'argv': args, 'exit_code': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr, 'expected_exit': expected}
    assert result.returncode == expected, row
    return row


policy_path = SOURCE / 'tools/release/release_privacy_policy.json'
policy = json.loads(policy_path.read_text(encoding='utf-8'))
assert set(policy['freeze']['deny_components']) == freeze.EXCLUDED
for name in ('release_contract.json', 'tools/release/release_privacy_policy.json'):
    json.loads((SOURCE / name).read_text(encoding='utf-8'))
ast.parse((SOURCE / 'tools/release/freeze_prepare.py').read_text(encoding='utf-8'))
targets = contract.declarations(SOURCE)
assert {(t['preset'], t['platform'], t['role']) for t in targets} == {
    ('FateDomination_demo_v1', 'windows', 'client'),
    ('FateServer Windows', 'windows', 'server'),
    ('FateServer Windows', 'windows', 'signaling'),
}
rows = []
for target in targets:
    role = target['role']
    script = ('import json,sys; from pathlib import Path; sys.path.insert(0,"tools/release"); from release_contract import select;\n'
              'try: print(json.dumps(select(Path.cwd(),sys.argv[1],"windows",sys.argv[2]),ensure_ascii=False))\n'
              'except (OSError,ValueError) as e: print("BLOCK:",e); sys.exit(2)')
    row = command('select-' + role, [sys.executable, '-B', '-c', script, target['preset'], role], 2 if role == 'signaling' else 0)
    if role == 'signaling':
        assert '纯信令工程禁止游戏/其他 autoload' in row['stdout']
    rows.append(row)
    rows.append(command('dry-run-' + role, [sys.executable, '-B', str(SOURCE / 'tools/release/freeze_prepare.py'),
        '--source', str(SOURCE), '--target', str(RUN / ('freeze-' + role)), '--manifest', str(RUN / ('freeze-' + role + '.json')),
        '--preset', target['preset'], '--role', role, '--executable', target['executable'],
        '--runtime-files', json.dumps(target['runtime_files']), '--allowed-root', str(RUN)], 0))
    assert not (RUN / ('freeze-' + role)).exists()
    assert not (RUN / ('freeze-' + role + '.json')).exists()

inventories = {}
project_checks = {}
for target in targets:
    role = target['role']
    names = freeze.inventory(SOURCE, target['runtime_files'], role, cold=True)
    forbidden = [name for name in names if set(p.lower() for p in Path(name).parts) & freeze.EXCLUDED]
    assert not forbidden, forbidden
    assert not [name for name in names if name.lower().endswith(('.pem', '.key', '.log', '.dmp'))]
    transformed = freeze.transform(SOURCE, target['preset'], names, role)
    text = transformed['project.godot']
    assert '_mcp_game_helper=' not in text
    assert 'enabled=PackedStringArray()' in text
    assert 'version_control/autoload_on_startup=false' in text
    if role == 'signaling':
        assert '[autoload]' not in text
        assert re.search(r'(?m)^signaling_only=true$', text)
    else:
        assert '[autoload]' in text
        assert any(name.startswith('scripts/net/identity/') for name in names)
    inventories[role] = {'cold_files': len(names), 'denied_components_in_selected_inventory': forbidden,
                         'names_sha256': hashlib.sha256(json.dumps(names, ensure_ascii=False).encode()).hexdigest()}
    project_checks[role] = {'in_memory_only': True, 'helper_removed': True, 'editor_plugins_disabled': True,
                            'all_autoloads_removed': role == 'signaling', 'signaling_only': role == 'signaling'}

# Exercise the real inventory consumer on explicit fixtures; no secret files.
fixture = FIXTURES / 'inventory-fixture'
fixture.mkdir(exist_ok=True)
for name in freeze.FILES:
    (fixture / name).write_text('STATIC_TEST_FIXTURE\n', encoding='utf-8')
cases = json.loads((FIXTURES / 'inventory-cases.json').read_text(encoding='utf-8'))
for name in cases:
    path = fixture / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('TEST_FIXTURE_NOT_A_SECRET\n', encoding='utf-8')
selected = set(freeze.inventory(fixture, runtime_files=[], cold=True))
case_results = []
for name, expected_included in cases.items():
    assert (name in selected) == expected_included, name
    case_results.append({'path': name, 'included_by_real_inventory': name in selected,
                         'status': 'SOURCE_CODE_RETAINED' if name.startswith('scripts/') else 'NOT_COVERED' if expected_included else 'COVERED'})

# Declaration evaluation and the production package-audit consumer use the same policy.
package = policy['package']
def policy_denies(name):
    path = Path(name)
    return bool(set(p.lower() for p in path.parts) & set(package['deny_components'])
                or path.name.lower() in package['deny_filenames']
                or path.suffix.lower() in package['deny_suffixes']
                or any(fnmatch.fnmatchcase(path.name.lower(), pattern) for pattern in package['deny_filename_patterns']))
for name in cases:
    assert policy_denies(name) == (not name.startswith('scripts/')), name

package_consumer_results = []
for name in cases:
    expected_rejected = not name.startswith('scripts/')
    rejected = package_audit.privacy_denies(name, package)
    assert rejected == expected_rejected, name
    package_consumer_results.append({
        'path': name,
        'package_audit_rejects': rejected,
        'status': 'WIRED_REJECT' if rejected else 'ALLOWED_SOURCE_CODE',
    })

bypass_selected = set(freeze.inventory(fixture, runtime_files=[{'source':'data/savedkeys/example.json','target':'example.json'}], cold=True))
assert 'data/savedkeys/example.json' in bypass_selected
try:
    contract.select(SOURCE, 'FateServer Windows', 'windows', None)
except ValueError as exc:
    assert '不存在或不唯一' in str(exc)
else:
    raise AssertionError('Explicit role required for shared preset')

report = {
    'status': 'PRIVACY_PACKAGE_CONSUMER_WIRED_AUDIT_NOTRUN',
    'privacy_consumer': {
        'module': 'tools/release/package_audit.py',
        'policy_integration_status': package['integration_status'],
        'hard_blockers': True,
        'fixture_results': package_consumer_results,
    },
    'explicit_runtime_bypass_confirmed': True,
    'shared_preset_without_role_rejected': True,
    'selected_inventory_sensitive_suffix_matches': [],
    'godot_invoked': False, 'freeze_copied': False, 'exported': False, 'native_loaded': False,
    'source_presets_sha256': sha(SOURCE / 'export_presets.cfg'),
    'credential_free_approval': {'status': 'APPROVED_BY_USER', 'evidence': 'docs/credential-free-evidence.md section 6', 'scope': 'sections 1-5; not content scanning or final manifest validation'},
    'files_sha256': {name: sha(SOURCE / name) for name in ('release_contract.json', 'tools/release/release_privacy_policy.json', 'tools/release/freeze_prepare.py')},
    'tool_sha256': {name: sha(SOURCE / name) for name in ('tools/release/release_contract.py', 'tools/release/package_audit.py', 'tools/copy_data_after_export.py', 'project.godot')},
    'commands': rows, 'inventories': inventories, 'project_checks': project_checks,
    'real_consumer_fixture_results': case_results,
    'package_consumer_fixture_count': len(package_consumer_results),
    'fixture_case_count': len(case_results),
    'policy_fixture_case_count': len(cases),
    'not_covered': ['freeze inventory still selects arbitrary secret/log/diagnostic suffix or pattern in data; final package audit now hard-blocks it',
                    'runtime_files/descriptor/import explicit dependency exclusion still needs a real final package inventory audit',
                    'whole external package whitelist remains outside this privacy wiring',
                    'specialized signaling_prepare external-native layout contract'],
    'not_run': ['real frozen copy', 'Godot import/export', 'real EXE/PCK/ZIP audit', 'runtime readiness', 'GUI or cross-network verification'],
}
# The candidate declaration is now applied; package_audit is its production consumer.
candidate_path = SOURCE / 'tools/release/candidates/role-privacy-final-inventory-declaration.patch'
candidate_patch = candidate_path.read_text(encoding='utf-8')
added = '\n'.join(line[1:] for line in candidate_patch.splitlines() if line.startswith('+') and not line.startswith('+++'))
candidate = json.loads('{' + added.rstrip().removesuffix(',') + '}')['final_inventory_candidate']
assert policy['freeze']['final_inventory_candidate']['deny_suffixes'] == candidate['deny_suffixes']
assert policy['freeze']['final_inventory_candidate']['deny_filename_patterns'] == candidate['deny_filename_patterns']
assert package['integration_status'].startswith('WIRED:')
four = [row for row in case_results if row['status'] == 'NOT_COVERED']
for row in four:
    name = Path(row['path'])
    if not (name.suffix.lower() in candidate['deny_suffixes'] or any(fnmatch.fnmatchcase(name.name.lower(), pattern) for pattern in candidate['deny_filename_patterns'])):
        raise AssertionError('Candidate declaration does not cover original negative fixture: ' + row['path'])
report['four_uncovered_items'] = [{**row,
    'status_now': 'WIRED_TO_PACKAGE_AUDIT',
    'wiring_consumer': 'tools/release/package_audit.py:privacy_denies/ privacy_blockers',
    'package_audit_rejects': package_audit.privacy_denies(row['path'], package),
    'still_missing': 'real final package inventory/PCK/ZIP audit',
    'unknown': 'actual private content and arbitrary runtime location',
} for row in four]
report['candidate_patch_sha256'] = sha(candidate_path)
report['candidate_applied'] = True

# Compare every original assertion expression, command and fixture outcome.
# The archived checklist comes from the original script/report, not new expectations.
from collections import Counter
baseline = json.loads((FIXTURES / 'original-checklist.json').read_text(encoding='utf-8'))
current_assertions = [ast.unparse(node.test) for node in ast.walk(ast.parse(Path(__file__).read_text(encoding='utf-8'))) if isinstance(node, ast.Assert)]
previous = Counter(item['expression'] for item in baseline['assertions'])
current = Counter(current_assertions)
removed = list((previous - current).elements())
comparison = {
    'original_audit_sha256': baseline['source_audit_sha256'],
    'assertions_before': baseline['assertions'],
    'assertions_after': [{'expression': expr, 'occurrences': count} for expr, count in sorted(current.items())],
    'assertions_removed': removed,
    'fixture_cases_before': baseline['fixture_cases'],
    'fixture_cases_after': cases,
    'fixture_cases_identical': baseline['fixture_cases'] == cases,
    'fixture_results_before': baseline['fixture_results'],
    'fixture_results_after': case_results,
    'fixture_results_identical': baseline['fixture_results'] == case_results,
    'policy_cases_before': len(baseline['fixture_cases']),
    'policy_cases_after': len(cases),
    'commands_before': baseline['commands'],
    'commands_after': [{'label': row['label'], 'expected_exit': row['expected_exit']} for row in rows],
    'additional_checks_retained': baseline['additional_checks'],
}
if removed or not comparison['fixture_cases_identical'] or not comparison['fixture_results_identical'] or comparison['commands_before'] != comparison['commands_after']:
    raise AssertionError('Audit migration lost or altered original checks: ' + json.dumps(comparison, ensure_ascii=False))
approval_text = (SOURCE / 'docs/credential-free-evidence.md').read_text(encoding='utf-8')
if '## 6. 审批状态' not in approval_text or '**已批准' not in approval_text:
    raise AssertionError('User credential-free approval evidence missing')
if '已由用户批准' not in policy['package']['content_approval']:
    raise AssertionError('Policy must reflect existing user approval')
(EVIDENCE / 'checklist-comparison.json').write_text(json.dumps(comparison, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
report['checklist_comparison'] = {'assertion_expressions_before': sum(previous.values()), 'assertion_expressions_after': sum(current.values()), 'removed': removed, 'fixture_cases_identical': True, 'fixture_results_identical': True, 'commands_identical': True, 'additional_checks_retained': baseline['additional_checks']}
report['audit_script_sha256'] = sha(Path(__file__))
report['fixture_declaration_sha256'] = sha(FIXTURES / 'inventory-cases.json')
(EVIDENCE / 'audit.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'status': report['status'], 'fixture_case_count': len(cases), 'evidence': str(EVIDENCE.relative_to(SOURCE)), 'godot_invoked': False, 'checks_removed': []}, ensure_ascii=False))
