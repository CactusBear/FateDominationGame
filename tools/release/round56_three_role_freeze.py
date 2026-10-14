"""Three-role same-source preparation; preflight never starts Godot.

Ready token = explicit main approval, not a signature or a runtime attestation.
Owner reports stay separately hash-bound. New C++ stays unreleased.

G05 uses this same entry, not a second release framework:
  --run-formal --run-phase client-startup --artifact-manifest <manifest.json>
  --artifact-manifest-sha256 <SHA> --root <fresh-E-scratch-child>
  --approved-root E:/Caches/Hermes/cache/scratch
This delegates exactly once to round53_exported_runtime.run_client_startup.
To consume an already executed same-manifest receipt without another EXE launch,
add --client-startup-receipt <runtime.json> --client-startup-receipt-sha256 <SHA>.
Old-artifact evidence additionally requires --client-startup-old-artifact and is
always nonfinal/ineligible for current-candidate admission. PASS requires the
producer's exact EXE/PCK/source identity, normal exit, private Job0 and clean
hash-bound logs; FAIL retains the original stage/exit/proof. The original client,
GUI/RSA, two-machine, save/recovery and full-suite gates are not upgraded.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import sys

sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import freeze_prepare as freeze
from path_safety import checked, new_output

DLL = 'addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll'
WEBRTC = 'addons/webrtc_native/lib/libwebrtc_native.windows.template_release.x86_64.dll'
EXT = 'addons/fate_server_signals/fate_server_signals.gdextension'
NATIVE_ROOT = 'addons/fate_server_signals/'
TOOLS = ('tools/release/round56_three_role_freeze.py', 'tools/release/freeze_prepare.py',
         'tools/release/path_safety.py', 'tools/release/release_contract.py', 'tools/release/package_audit.py',
         'tools/release/signaling_prepare.py', 'tools/copy_data_after_export.py',
         'tools/tests/round52_current_role_candidates.py', 'tools/diagnostics/round53_signaling_initialization.py',
         'tools/diagnostics/project_extension_lifecycle_probe.py', 'tools/diagnostics/legal_extension_control.py',
         'tools/diagnostics/native_cold_import_debug.py',
         'tools/diagnostics/round53_exported_runtime.py',
         'tools/diagnostics/round54_packaged_server_protocol.py',
         'tools/diagnostics/round54_authenticated_client.gd',
         'tools/diagnostics/round54_authenticated_client.tscn')
DEPENDENCIES = ('runtime_observation', 'shutdown_handoff', 'gui', 'current_headless', 'native_compile')
SCOPES = {
    'runtime_observation': ('scripts/net/server/server_console_channel.gd', 'scripts/io/native_capability_view.gd',
        'scripts/net/server/server_bootstrap.gd', 'scripts/net/server/server_room_manager.gd',
        'scripts/net/server/server_cli.gd', 'project.godot', 'assets/config/server.cfg', DLL),
    'shutdown_handoff': ('scripts/net/server/server_shutdown.gd', 'scripts/net/server/server_room_manager.gd',
        'scripts/net/server/server_console_channel.gd'),
    'gui': ('scripts/game_scene/battle_board_v2.gd', 'scripts/net/ui/v2_view_presenter.gd',
        'scripts/net/ui/room_data_panel.gd', 'scripts/net/server/server_data_approval.gd'),
}
RUNTIME_PENDING = {
    'status': 'NOTIMPLEMENTED',
    'executor_status': 'IMPLEMENTED_NOTRUN',
    'reason': 'Explicit artifact-manifest phase executor exists; full exported-client RSA/GUI acceptance remains separate from the R54 editor RSA diagnostic.',
    'required': ['formal exported client RSA authentication', 'server trusted-local status: four classes/13 methods/budget15/pool20',
                 'real room save-close then gateway stop exit0 and exact owned-tree accounting',
                 'same-freeze signaling create/join/offer/answer and forbidden game messages',
                 'signaling missing-config exact exit2 and complete allowed ERROR scopes'],
    'forbidden_substitutions': ['old client/server pack plus new signaling pack', 'diagnostic PCK as formal client',
                                'release --script/--path overrides', 'source headless/GUI report as package runtime PASS'],
}


def sha(path):
    return freeze.sha(Path(path))


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()).hexdigest()


def current_inventory(source):
    """Actual cold production closure plus native source/build-contract provenance."""
    source = checked(source)
    for rel in (DLL, WEBRTC, EXT, 'addons/webrtc_native/webrtc_native.gdextension'):
        if not checked(source / rel).is_file(): raise ValueError('MANDATORY_NATIVE_ASSET: ' + rel)
    roles = {role: freeze.inventory(source, role=role, cold=True) for role in ('client', 'server', 'signaling')}
    native = [NATIVE_ROOT + 'SConstruct']
    native += sorted(p.relative_to(source).as_posix() for p in (source / NATIVE_ROOT / 'src').rglob('*')
                     if p.is_file() and p.suffix in {'.cpp', '.hpp', '.h'})
    if len(native) == 1: raise ValueError('NATIVE_SOURCE_MANIFEST_REQUIRED')
    optional = source / NATIVE_ROOT / 'build_profile.json'
    if optional.is_file(): native.append(optional.relative_to(source).as_posix())
    rels = sorted(set(native).union(TOOLS, *roles.values()))
    hashes = {r: sha(checked(source / r)) for r in rels}
    cfg = (source / 'assets/config/server.cfg').read_text(encoding='utf-8-sig')
    project = (source / 'project.godot').read_text(encoding='utf-8-sig')
    budget = re.findall(r'(?m)^random_sim_budget_sec\s*=\s*([0-9.]+)\s*$', cfg)
    enabled = re.findall(r'(?m)^random_sim_enabled\s*=\s*(true|false)\s*$', cfg)
    pool = re.findall(r'(?m)^worker_pool/max_threads\s*=\s*([0-9]+)\s*$', project)
    declarations = {'budget': float(budget[0]) if len(budget) == 1 else 'unknown',
                    'enabled': enabled[0] == 'true' if len(enabled) == 1 else 'unknown',
                    'pool': int(pool[0]) if len(pool) == 1 else 'unknown'}
    return {'source': str(source), 'source_files': hashes, 'source_fingerprint': fingerprint(hashes),
            'role_files': roles, 'native_source_files': {r: hashes[r] for r in native},
            'native_source_fingerprint': fingerprint({r: hashes[r] for r in native}),
            'declarations': declarations, 'runtime': RUNTIME_PENDING,
            'classification': 'INVENTORY_ONLY_NOT_SOURCE_PASS'}


def file_drift(before, after):
    return {'added': sorted(after.keys() - before.keys()),
            'removed': sorted(before.keys() - after.keys()),
            'changed': {r: {'before': before[r], 'after': after[r]}
                        for r in sorted(before.keys() & after.keys()) if before[r] != after[r]}}


def diagnostic_snapshot(source, attempts_root):
    """Two bounded acquisitions; preserve rejected inputs, never run failed cold twice."""
    import package_audit as audit
    source = checked(source); attempts_root = checked(attempts_root)
    attempts_root.mkdir(parents=True, exist_ok=False)
    result = {'classification': 'BUILD_ONLY_DIAGNOSTIC_NOT_RELEASE_APPROVAL', 'attempts': []}
    for number in (1, 2):
        attempt = attempts_root / str(number); attempt.mkdir()
        snap = attempt / 'source-snapshot'; snap.mkdir()
        inventory = current_inventory(source)
        row = {'inventory': inventory, 'snapshot': str(snap)}; result['attempts'].append(row)
        try:
            for rel, digest in inventory['source_files'].items():
                src = checked(source / rel); dst = snap / rel
                dst.parent.mkdir(parents=True, exist_ok=True)
                if sha(src) != digest: raise ValueError('SOURCE_COPY_BEFORE_DRIFT: ' + rel)
                shutil.copyfile(src, dst)
                if sha(dst) != digest or sha(src) != digest:
                    raise ValueError('SOURCE_COPY_AFTER_DRIFT: ' + rel)
            after = current_inventory(source)
            row['drift'] = file_drift(inventory['source_files'], after['source_files'])
            if any(row['drift'].values()): raise ValueError('SOURCE_COPY_CLOSURE_DRIFT')
            if audit.manifest(snap) != inventory['source_files']: raise ValueError('EXACT_SNAPSHOT_REQUIRED')
            row['status'] = 'EXACT_COPY_VERIFIED'
            result.update(snapshot=str(snap), inventory=inventory)
        except (OSError, ValueError) as exc:
            row['status'] = 'REJECTED'; row['reason'] = str(exc)
            row['copied_files'] = audit.manifest(snap)
            try: row['drift'] = file_drift(inventory['source_files'], current_inventory(source)['source_files'])
            except (OSError, ValueError) as observation: row['drift_observation_error'] = str(observation)
        (attempts_root / 'acquisition.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
        if row['status'] == 'EXACT_COPY_VERIFIED': return result
    raise ValueError('SOURCE_DRIFT_AFTER_ONE_REACQUISITION: ' + str(attempts_root / 'acquisition.json'))


def pointer(document, path):
    if not isinstance(path, str) or not path.startswith('/'): raise ValueError('JSON_POINTER_REQUIRED')
    for item in path[1:].split('/'):
        item = item.replace('~1', '/').replace('~0', '~')
        document = document[int(item)] if isinstance(document, list) else document[item]
    return document


def source_map(value, source):
    """Accept real dict or isolated-runner [{path,sha256}] manifests."""
    if isinstance(value, list): rows = [(r['path'], r['sha256']) for r in value]
    elif isinstance(value, dict): rows = list(value.items())
    else: raise ValueError('DECLARED_SOURCE_MAP_REQUIRED')
    result = {}
    for path, digest in rows:
        path = str(path).replace('\\', '/')
        if Path(path).is_absolute():
            absolute = Path(path).resolve()
            if not absolute.is_relative_to(source): continue
            path = absolute.relative_to(source).as_posix()
        if Path(path).is_absolute() or '..' in Path(path).parts or ':' in path: raise ValueError('DECLARED_SOURCE_PATH_INVALID')
        if path in result or not isinstance(digest, str) or not re.fullmatch('[0-9a-f]{64}', digest): raise ValueError('DECLARED_SOURCE_HASH_INVALID')
        result[path] = digest
    return result


def dependency(name, declaration, inventory, source):
    try:
        path = checked(Path(declaration['path'])); raw = path.read_bytes(); report = json.loads(raw)
    except (OSError, ValueError, KeyError, TypeError) as exc:
        raise ValueError('DEPENDENCY_UNREADABLE: ' + name) from exc
    if hashlib.sha256(raw).hexdigest() != declaration.get('sha256'): raise ValueError('DEPENDENCY_HASH_MISMATCH: ' + name)
    try:
        declared = source_map(pointer(report, declaration['source_pointer']), source)
        required = (inventory['role_files']['client'] if name == 'current_headless' else
                    {r: h for r, h in inventory['native_source_files'].items() if r.endswith(('.cpp', '.hpp', '.h'))}
                    if name == 'native_compile' else SCOPES[name])
        mismatches = [r for r in required if r not in inventory['source_files'] or declared.get(r) != inventory['source_files'][r]]
        if mismatches: raise ValueError('DEPENDENCY_SOURCE_MISMATCH: ' + name + ': ' + ','.join(mismatches))
        if name == 'current_headless':
            bindings = declaration.get('headless_steps', {})
            if set(bindings) != {'selection_ready', 'required'}: raise ValueError('HEADLESS_BOTH_STEPS_REQUIRED')
            freezes = []; exits = []
            for binding in bindings.values():
                exits.append(binding['exit_pointer'])
                code = pointer(report, binding['exit_pointer'])
                errors = pointer(report, binding['errors_pointer'])
                if type(code) is not int or code != 0 or errors != []: raise ValueError('HEADLESS_STEP_FAILED')
                freezes.append(pointer(report, binding['freeze_pointer']))
            if len(set(exits)) != 2: raise ValueError('HEADLESS_DISTINCT_STEPS_REQUIRED')
            if not all(isinstance(v, str) and v for v in freezes) or freezes[0] != freezes[1]:
                raise ValueError('HEADLESS_STEP_FREEZE_MISMATCH')
        if name == 'native_compile':
            try:
                artifact = report['dll']; artifact_path = checked(artifact['path'])
                units = {str(checked(source / r)) for r in required if r.endswith('.cpp')}
                reported_units = {str(checked(p)) for p in report['translation_units']}
                steps = declaration['compile_steps']
                cpp = {r for r in required if r.endswith('.cpp')}
                if set(steps) != cpp: raise ValueError('NATIVE_COMPILE_OUTPUT_UNPROVEN')
                indices = list(steps.values()) + [declaration['link_step']]
                if any(type(n) is not int or n < 0 for n in indices) or len(set(indices)) != len(indices):
                    raise ValueError('NATIVE_COMPILE_OUTPUT_UNPROVEN')
                commands = [report['commands'][n] for n in indices]
                if (units != reported_units or
                    any(type(row.get('exit')) is not int or row['exit'] != 0 for row in commands) or
                    artifact.get('checks', artifact).get('pe_x64') is not True or sha(artifact_path) != artifact['sha256'] or
                    artifact['sha256'] == inventory['source_files'][DLL]):
                    raise ValueError('NATIVE_COMPILE_OUTPUT_UNPROVEN')
                output = checked(report['output'])
                for command in commands:
                    stage = command['stage']
                    if 'raw_sha256' in command:
                        if sha(checked(output / (stage + '.raw.log'))) != command['raw_sha256']:
                            raise ValueError('NATIVE_COMPILE_LOG_HASH_MISMATCH: ' + stage)
                    else:
                        cmd = checked(command['argv'][-1])
                        if cmd.parent != output or sha(cmd) != report['command_files'][cmd.name]['sha256']:
                            raise ValueError('NATIVE_COMMAND_HASH_MISMATCH: ' + stage)
            except (OSError, KeyError, IndexError, TypeError) as exc:
                raise ValueError('NATIVE_COMPILE_OUTPUT_UNPROVEN') from exc
        checks = declaration.get('checks')
        if not isinstance(checks, list) or len(checks) < 2: raise ValueError('DEPENDENCY_CHECKS_REQUIRED: ' + name)
        if not any(type(c.get('equals')) is int and c['equals'] == 0 and c.get('pointer', '').split('/')[-1] in {'exit', 'exit_code'} for c in checks):
            raise ValueError('DEPENDENCY_EXIT_CHECK_REQUIRED: ' + name)
        if name != 'native_compile' and not any(c.get('equals') == [] and c.get('pointer', '').split('/')[-1] in {'errors', 'failures', 'error_lines'} for c in checks):
            raise ValueError('DEPENDENCY_ERROR_CHECK_REQUIRED: ' + name)
        for check in checks:
            if fingerprint(pointer(report, check['pointer'])) != fingerprint(check['equals']):
                raise ValueError('DEPENDENCY_CHECK_FAILED: ' + name + ': ' + check['pointer'])
    except (KeyError, IndexError, TypeError) as exc:
        raise ValueError('DEPENDENCY_SCHEMA_INVALID: ' + name) from exc
    return {'path': str(path), 'sha256': declaration['sha256'], 'required_sources_checked': len(required),
            'checks': checks, 'source_files': {r: declared[r] for r in required}}


def preflight(source, ready_token, root, approved_root):
    if ready_token is None: raise ValueError('READY_TOKEN_REQUIRED: main must explicitly approve frozen source')
    source = checked(source); root = checked(root); approved_root = checked(approved_root)
    if root.exists(): raise ValueError('FRESH_ROOT_REQUIRED: never reuse failed import/export cache')
    if root.drive.upper() != 'E:' or approved_root.drive.upper() != 'E:':
        raise ValueError('PHYSICAL_APPROVED_E_ROOT_REQUIRED')
    new_output(root, protected=(source,), allowed_root=approved_root)
    try:
        token_path = checked(ready_token); raw = token_path.read_bytes(); token = json.loads(raw)
    except (OSError, ValueError) as exc: raise ValueError('READY_TOKEN_UNREADABLE') from exc
    if token.get('schema') != 1 or token.get('approved_by') != 'main' or token.get('freeze_ready') is not True:
        raise ValueError('EXPLICIT_MAIN_FREEZE_APPROVAL_REQUIRED')
    for key, value in (('source', source), ('root', root), ('approved_root', approved_root)):
        if key not in token or checked(token[key]) != value: raise ValueError('APPROVAL_PATH_MISMATCH: ' + key)
    if token.get('claim_new_job') is not False: raise ValueError('NEW_NATIVE_PRODUCTION_BLOCKED: original DLL is not new C++ proof')
    inventory = current_inventory(source)
    if token.get('source_fingerprint') != inventory['source_fingerprint']: raise ValueError('SOURCE_FINGERPRINT_MISMATCH')
    if inventory['declarations'] != {'budget': 15.0, 'enabled': True, 'pool': 20}: raise ValueError('DEFAULT15_POOL20_DECLARATION_MISMATCH')
    deps = token.get('dependencies', {}); verified = {}
    for name in DEPENDENCIES:
        if name not in deps: raise ValueError('MISSING_DEPENDENCY: ' + name)
        verified[name] = dependency(name, deps[name], inventory, source)
    if current_inventory(source)['source_files'] != inventory['source_files']:
        raise ValueError('SOURCE_DRIFT_DURING_PREFLIGHT')
    if sha(token_path) != hashlib.sha256(raw).hexdigest(): raise ValueError('TOKEN_DRIFT_DURING_PREFLIGHT')
    return {**inventory, 'allow_build': True, 'classification': 'PREFLIGHT_ALLOWED_NOT_SOURCE_PASS',
            'root': str(root), 'approved_root': str(approved_root),
            'ready_token': {'path': str(token_path), 'sha256': hashlib.sha256(raw).hexdigest()},
            'dependencies': verified, 'native': {'production_blocked': True, 'claim_new_job': False,
                'release_dll_sha256': inventory['source_files'][DLL], 'compile_source_checked': True,
                'unreleased': ['process_tree_owner_core', 'temporary_cleanup_core'],
                'compiled_dll_promoted': False, 'source_to_production_bin_match': 'NOT_ESTABLISHED'}}


def role_declaration(source, preset, role, executable):
    """Consume the exact source contract, rather than rebuild a DLL-only target."""
    from release_contract import declarations
    matches = [target for target in declarations(source)
               if (target['preset'], target['platform'], target['role']) == (preset, 'windows', role)]
    if len(matches) != 1 or matches[0]['executable'] != executable:
        raise ValueError('EXPLICIT_ROLE_DECLARATION_MISMATCH: ' + role)
    return matches[0]


def build_plan(approved):
    fp = approved['source_fingerprint']
    return {'formal_runtime_implemented': False, 'roles': {
        'client': {'source_fingerprint': fp, 'preset': 'FateDomination_demo_v1', 'executable': 'FateDomination.exe',
                   'native_deployment': 'unchanged-editor-discovered', 'preparer': 'freeze_prepare.transform'},
        'server': {'source_fingerprint': fp, 'preset': 'FateServer Windows', 'executable': 'FateServer.exe',
                   'native_deployment': 'unchanged-editor-discovered', 'preparer': 'freeze_prepare.transform'},
        'signaling': {'source_fingerprint': fp, 'preset': 'FateServer Windows', 'executable': 'FateSignaling.exe',
                      'native_deployment': 'external-supported-runtime', 'preparer': 'tools.release.signaling_prepare.prepare'},
    }}


def diagnostic_build(source, root, approved_root, godot, templates, *, authorized=False):
    """Explicit build-only snapshot authorization is NOT a final ready token."""
    if authorized is not True: raise ValueError('BUILD_ONLY_AUTHORIZATION_REQUIRED')
    source = checked(source); root = checked(root); approved_root = checked(approved_root)
    if root.drive.upper() != 'E:' or approved_root.drive.upper() != 'E:':
        raise ValueError('PHYSICAL_APPROVED_E_ROOT_REQUIRED')
    new_output(root, protected=(source,), allowed_root=approved_root)
    root.mkdir(parents=True, exist_ok=False)
    acquisition = diagnostic_snapshot(source, root / 'snapshot-attempts')
    inventory = acquisition['inventory']
    if inventory['declarations'] != {'budget': 15.0, 'enabled': True, 'pool': 20}:
        raise ValueError('DEFAULT15_POOL20_DECLARATION_MISMATCH')
    approved = {**inventory, 'root': str(root), 'approved_root': str(approved_root),
                'classification': 'BUILD_ONLY_DIAGNOSTIC_NOT_RELEASE_APPROVAL',
                'build_only_authorized': True, 'snapshot_acquisition': acquisition,
                'native': {'production_blocked': True, 'claim_new_job': False,
                           'compiled_dll_promoted': False, 'release_dll_sha256': inventory['source_files'][DLL],
                           'source_to_production_bin_match': 'NOT_ESTABLISHED'},
                'acceptance': {'two_client_save_recover_GUI': 'NOTRUN', 'GUI_opening': 'NOTRUN',
                               'release_admission': 'NOT_GRANTED', 'source_PASS': 'NOT_GRANTED'}}
    try:
        return _build_packages(approved, godot, templates, diagnostic_snapshot_path=Path(acquisition['snapshot']))
    finally:
        target = root / 'source-readback.json'
        observation = {'snapshot_fingerprint': inventory['source_fingerprint'], 'source': str(source),
                       'classification': 'LATER_SOURCE_COMPARISON_NOT_RELEASE_APPROVAL'}
        try:
            after = current_inventory(source)
            observation.update(current_fingerprint=after['source_fingerprint'],
                               drift=file_drift(inventory['source_files'], after['source_files']))
        except (OSError, ValueError) as exc: observation['readback_error'] = str(exc)
        target.write_text(json.dumps(observation, ensure_ascii=False, indent=2), encoding='utf-8')


def build(approved, godot, templates):
    return _build_packages(approved, godot, templates)


def _build_packages(approved, godot, templates, *, diagnostic_snapshot_path=None):
    """Shared actual exporters; diagnostic mode cannot mint final admission."""
    from tools.tests import round52_current_role_candidates as runner
    from tools.release import signaling_prepare as signaling
    import package_audit as audit
    import release_contract as contract
    root = checked(approved['root']); source = checked(approved['source'])
    godot = checked(godot); templates = checked(templates)
    if root.drive.upper() != 'E:' or checked(approved['approved_root']).drive.upper() != 'E:':
        raise ValueError('BUILD_REQUIRES_PHYSICAL_APPROVED_E_ROOT')
    if sha(godot) != 'ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424':
        raise ValueError('ORIGINAL_OFFICIAL_ENGINE_REQUIRED')
    if approved['source_files'][DLL] != '92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd':
        raise ValueError('ORIGINAL_PRODUCTION_DLL_REQUIRED')
    expected_templates = {
        'windows_debug_x86_64.exe': '51498b72b3a237f882ebd7d1787f06a4bc1eaf0572daab93837adcfd3cfdc107',
        'windows_debug_x86_64_console.exe': '5514c7645ee897a01f540d3cf22ede5badf92394521a08bfab66a54d7369e6e6',
        'windows_release_x86_64.exe': 'd34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562',
        'windows_release_x86_64_console.exe': '52bdcae9068e8d23b840e5c63b0c1798ffe2cb66144e5c4bc7af11fb8c8600df',
    }
    for name, digest in expected_templates.items():
        if sha(checked(templates / name)) != digest: raise ValueError('ORIGINAL_TEMPLATE_REQUIRED: ' + name)
    diagnostic = diagnostic_snapshot_path is not None
    if diagnostic:
        if (approved.get('classification') != 'BUILD_ONLY_DIAGNOSTIC_NOT_RELEASE_APPROVAL' or
            approved.get('build_only_authorized') is not True or 'ready_token' in approved):
            raise ValueError('INVALID_DIAGNOSTIC_ADMISSION')
        snap = checked(diagnostic_snapshot_path)
        if not snap.is_relative_to(root) or audit.manifest(snap) != approved['source_files']:
            raise ValueError('DIAGNOSTIC_SNAPSHOT_HASH_MISMATCH')
    else:
        # Do not treat an earlier preflight receipt as a reusable permission.
        repeated = preflight(source, Path(approved['ready_token']['path']), root, Path(approved['approved_root']))
        if repeated['source_fingerprint'] != approved['source_fingerprint'] or repeated['ready_token'] != approved['ready_token']:
            raise ValueError('APPROVAL_DRIFT_BEFORE_BUILD')
        root.mkdir(parents=True, exist_ok=False)
    m = {**approved, 'status': 'BUILDING_NOT_RUNTIME_PASS', 'steps': [], 'roles': {},
         'build_plan': build_plan(approved), 'engine': {'path': str(godot), 'sha256': sha(godot)},
         'templates': expected_templates, 'classification': ('BUILD_ONLY_DIAGNOSTIC_NOT_RELEASE_APPROVAL'
             if diagnostic else 'CANDIDATE_NOT_RUNTIME_VERIFIED')}
    runner.save(root, m)

    def unchanged():
        if diagnostic:
            if audit.manifest(snap) != approved['source_files']:
                raise ValueError('DIAGNOSTIC_SNAPSHOT_DRIFT_STOP_NO_RETRY')
            return
        now = current_inventory(source)
        if now['source_files'] != approved['source_files']: raise ValueError('SOURCE_DRIFT_STOP_NO_RETRY')
        if sha(Path(approved['ready_token']['path'])) != approved['ready_token']['sha256']:
            raise ValueError('READY_TOKEN_DRIFT_STOP_NO_RETRY')
        for dep in approved['dependencies'].values():
            if sha(Path(dep['path'])) != dep['sha256']: raise ValueError('DEPENDENCY_DRIFT_STOP_NO_RETRY')

    def execute(label, argv, cwd, timeout=180):
        unchanged()
        row = runner.run(root, m, label, argv, cwd, timeout=timeout)
        unchanged()
        return row

    try:
        if not diagnostic:
            snap = root / 'source-snapshot'; snap.mkdir()
            for rel, digest in approved['source_files'].items():
                src = checked(source / rel); dst = snap / rel; dst.parent.mkdir(parents=True, exist_ok=True)
                if sha(src) != digest: raise ValueError('SOURCE_COPY_DRIFT: ' + rel)
                shutil.copyfile(src, dst)
                if sha(dst) != digest or sha(src) != digest: raise ValueError('SNAPSHOT_COPY_MISMATCH: ' + rel)
        unchanged()
        if audit.manifest(snap) != approved['source_files']: raise ValueError('EXACT_SNAPSHOT_MANIFEST_REQUIRED')
        env = runner.environment(root)
        dest = Path(env['APPDATA']) / 'Godot/export_templates/4.7.2.stable'; dest.mkdir(parents=True)
        for name, digest in expected_templates.items():
            shutil.copyfile(templates / name, dest / name)
            if sha(dest / name) != digest: raise ValueError('TEMPLATE_COPY_MISMATCH')
        formal = root / 'imported-formal'; formal.mkdir()
        for rel in approved['role_files']['client']:
            dst = formal / rel; dst.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(snap / rel, dst)
        transforms = freeze.transform(snap, None, approved['role_files']['client'])
        for rel, text in transforms.items(): (formal / rel).write_text(text, encoding='utf-8', newline='\n')
        m['formal_transform'] = {r: {'source_sha256': approved['source_files'][r], 'target_sha256': sha(formal / r)} for r in transforms}
        runner.save(root, m)
        execute('first-game-cold-import', [godot, '--headless', '--verbose', '--rendering-method', 'gl_compatibility',
                '--editor', '--path', formal, '--import'], formal)
        for role in ('client', 'server'):
            plan = m['build_plan']['roles'][role]; project = root / ('project-' + role)
            shutil.copytree(formal, project)
            text = runner.transformed_presets(snap, role, list(audit.manifest(project)))
            (project / 'export_presets.cfg').write_text(text, encoding='utf-8', newline='\n')
            declaration = role_declaration(snap, plan['preset'], role, plan['executable'])
            client_plan = m['build_plan']['roles']['client']
            for item in role_declaration(snap, client_plan['preset'], 'client', client_plan['executable'])['runtime_files']:
                rel = item['source']
                if rel not in approved['role_files'][role] and (project / rel).is_file():
                    (project / rel).unlink()
            # formal starts from the client closure; add only this role's declared
            # external inputs, without scanning tools or changing PCK filters.
            for item in declaration['runtime_files']:
                rel = item['source']; dst = project / rel
                if dst.exists():
                    if sha(dst) != approved['source_files'][rel]: raise ValueError('ROLE_RUNTIME_SOURCE_MISMATCH: ' + rel)
                else:
                    dst.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(snap / rel, dst)
                    if sha(dst) != approved['source_files'][rel]: raise ValueError('ROLE_RUNTIME_COPY_MISMATCH: ' + rel)
            (project / contract.NAME).write_text(freeze.contract_text(declaration), encoding='utf-8', newline='\n')
            package = root / 'artifacts' / role; package.mkdir(parents=True)
            row = {'source_fingerprint': approved['source_fingerprint'], 'project': str(project), 'package': str(package), 'declaration': declaration}
            m['roles'][role] = row; runner.save(root, m)
            execute('export-' + role, [godot, '--headless', '--rendering-method', 'gl_compatibility', '--path', project,
                    '--export-release', plan['preset'], package / plan['executable']], project, 600)
            execute('copy-data-' + role, [sys.executable, '-B', snap / 'tools/copy_data_after_export.py',
                    '--project', project, '--output-dir', package], project)
            contract.copy_runtime(project, package, plan['preset'], 'windows', role)
            out = root / 'evidence' / ('package-' + role + '.json')
            row['static_exit_code'] = audit.audit(project, package, out, plan['preset'], 'windows', role)
            row['static_audit'] = str(out); row['package_files'] = audit.manifest(package); runner.save(root, m)
            if row['static_exit_code']: raise ValueError('STATIC_PACKAGE_AUDIT_FAILED: ' + role)
            packed = json.loads(out.read_text(encoding='utf-8'))['pck_index']['files']
            for rel in (EXT, 'addons/webrtc_native/webrtc_native.gdextension'):
                if 'res://' + rel not in packed: raise ValueError('MANDATORY_PACKED_NATIVE_DESCRIPTOR: ' + role + ':' + rel)
            if role == 'server':
                for rel in ('scripts/io/native_capability_view.gd', 'scripts/net/server/server_console_channel.gd',
                            'scripts/net/server/server_shutdown.gd', 'scripts/net/server/server_room_manager.gd'):
                    if not any('res://' + rel + suffix in packed for suffix in ('', '.remap')):
                        raise ValueError('CURRENT_STATUS_HANDOFF_NOT_PACKED: ' + rel)
        unchanged()
        sample = root / 'project-signaling'; sample.mkdir()
        receipt = signaling.prepare(sample, snap); project = sample / 'project'
        # The trimmed manifest is a projection of this snapshot, not a second source version.
        if any(approved['source_files'].get(r) != h for r, h in receipt['source_files'].items()):
            raise ValueError('SIGNALING_SOURCE_PROJECTION_MISMATCH')
        package = root / 'artifacts/signaling'; package.mkdir(parents=True)
        plan = m['build_plan']['roles']['signaling']
        declared = role_declaration(snap, plan['preset'], 'signaling', plan['executable'])
        # Native placement stays governed by signaling's external-native receipt.
        # Only these three explicitly named launcher/config destinations use copy_runtime.
        launcher_targets = ('START-SIGNALING.cmd', 'Launch-HumanTest.ps1', 'signaling.json')
        declaration = {**declared, 'runtime_files': [item for item in declared['runtime_files']
                                                   if item['target'] in launcher_targets]}
        if {item['target'] for item in declaration['runtime_files']} != set(launcher_targets):
            raise ValueError('SIGNALING_LAUNCHER_DECLARATION_REQUIRED')
        (project / contract.NAME).write_text(freeze.contract_text(declaration), encoding='utf-8', newline='\n')
        receipt['files']['project/' + contract.NAME] = sha(project / contract.NAME)
        (sample / 'input-manifest.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
        row = {'source_fingerprint': approved['source_fingerprint'], 'project': str(project), 'package': str(package),
               'declaration': declaration, 'input_manifest': str(sample / 'input-manifest.json'), 'native_deployment': 'external-supported-runtime'}
        m['roles']['signaling'] = row; runner.save(root, m)
        execute('first-signaling-cold-import', [godot, '--headless', '--verbose', '--rendering-method', 'gl_compatibility',
                '--editor', '--path', project, '--import'], project)
        extension_list = project / '.godot/extension_list.cfg'
        if extension_list.exists() and extension_list.read_text().strip(): raise ValueError('SIGNALING_EDITOR_DISCOVERED_NATIVE')
        execute('export-signaling', [godot, '--headless', '--rendering-method', 'gl_compatibility', '--path', project,
                '--export-release', signaling.PRESET, package / 'FateSignaling.exe'], project, 600)
        shutil.copytree(sample / 'native', package / 'native')
        contract.copy_runtime(project, package, plan['preset'], 'windows', 'signaling')
        row['static_audit'] = signaling.audit(package, sample); row['package_files'] = audit.manifest(package)
        unchanged()
        for role, row in m['roles'].items():
            exe = row['package_files']; name = m['build_plan']['roles'][role]['executable']
            if name not in exe or Path(name).with_suffix('.pck').name not in exe: raise ValueError('MISSING_EXE_PCK: ' + role)
        if len({r['source_fingerprint'] for r in m['roles'].values()}) != 1: raise ValueError('MIXED_SOURCE_ROLE_MANIFESTS')
        pcks = [r['package_files'][Path(m['build_plan']['roles'][role]['executable']).with_suffix('.pck').name] for role, r in m['roles'].items()]
        if len(set(pcks)) != 3: raise ValueError('THREE_DISTINCT_ROLE_PCKS_REQUIRED')
        for role, row in m['roles'].items():
            row['declaration'] = row.get('declaration', {'role': role, 'platform': 'windows',
                'preset': m['build_plan']['roles'][role]['preset'], 'executable': m['build_plan']['roles'][role]['executable']})
            row['native_files'] = {r: h for r, h in row['package_files'].items() if r.endswith(('.dll', '.gdextension'))}
            row['data_files'] = {r: h for r, h in row['package_files'].items() if r.startswith('data/')}
        harness = root / 'rsa-fixture'
        shutil.copytree(formal, harness)
        for name in ('round54_authenticated_client.gd', 'round54_authenticated_client.tscn'):
            rel = 'tools/diagnostics/' + name
            target = harness / rel; target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(snap / rel, target)
        harness_files = {r: h for r, h in audit.manifest(harness).items() if not r.startswith('.godot/')}
        harness_manifest = root / 'rsa-fixture-manifest.json'
        harness_manifest.write_text(json.dumps({'source_fingerprint': approved['source_fingerprint'],
            'files': harness_files, 'kind': 'existing_round54_editor_RSA_fixture_not_release_client'}, indent=2), encoding='utf-8')
        m['rsa_fixture'] = {'project': str(harness), 'manifest': str(harness_manifest),
                            'manifest_sha256': sha(harness_manifest), 'files_fingerprint': fingerprint(harness_files)}
        m['status'] = ('BUILD_ONLY_DIAGNOSTIC_THREE_ARTIFACTS_RUNTIME_NOTRUN' if diagnostic
                       else 'THREE_ARTIFACTS_STATIC_PASS_RUNTIME_NOTRUN')
        m['artifact_identity_sha256'] = fingerprint({r: v['package_files'] for r, v in m['roles'].items()})
        validate_roles(m, ['client', 'server', 'signaling'])
    except BaseException as exc:
        m['status'] = 'STOPPED_WITH_ORIGINAL_EVIDENCE'; m['error'] = repr(exc); runner.save(root, m)
        raise
    runner.save(root, m)
    return {'status': m['status'], 'manifest': str(root / 'manifest.json'), 'runtime': RUNTIME_PENDING}


RUN_PHASES = ('client-startup', 'client', 'server', 'status', 'signaling-ready', 'signaling-negative')
ALL_RUN_PHASES = ('client-startup', 'client', 'server', 'signaling-ready', 'signaling-negative')


def digest_map(value):
    if not isinstance(value, dict) or not value: raise ValueError('NONEMPTY_FILE_MANIFEST_REQUIRED')
    for rel, digest in value.items():
        if (not isinstance(rel, str) or '\\' in rel or ':' in rel or
            Path(rel).is_absolute() or '..' in Path(rel).parts or
            not isinstance(digest, str) or not re.fullmatch('[0-9a-f]{64}', digest)):
            raise ValueError('INVALID_ARTIFACT_HASH_MAP')
    return value


def pe_x64(path):
    import struct
    with Path(path).open('rb') as f:
        header = f.read(64)
        if len(header) != 64 or header[:2] != b'MZ': raise ValueError('INVALID_PE: ' + str(path))
        offset = struct.unpack_from('<I', header, 60)[0]
        f.seek(offset); signature = f.read(6)
        if signature != b'PE\x00\x00\x64\x86': raise ValueError('INVALID_PE: ' + str(path))


def validate_artifact(role, row):
    """Hash exact immutable package, then parse actual PE/PCK; no runtime loading."""
    import package_audit as audit
    if role not in ('client', 'server', 'signaling'): raise ValueError('UNSUPPORTED_ROLE')
    declaration = row.get('declaration', {})
    if declaration.get('role') != role or declaration.get('platform') != 'windows':
        raise ValueError('EXPLICIT_ROLE_PLATFORM_REQUIRED: ' + role)
    package = checked(row['package'])
    if package.drive.upper() != 'E:' or not package.is_dir(): raise ValueError('PHYSICAL_E_PACKAGE_REQUIRED')
    expected = digest_map(row['package_files'])
    for child in package.rglob('*'): checked(child)
    actual = audit.manifest(package)
    if actual != expected: raise ValueError('PACKAGE_HASH_DRIFT: ' + role)
    exe = declaration.get('executable', '')
    if not exe or Path(exe).name != exe or not exe.endswith('.exe'): raise ValueError('EXPLICIT_EXE_REQUIRED')
    pck = Path(exe).with_suffix('.pck').name
    if exe not in actual or pck not in actual: raise ValueError('EXE_PCK_REQUIRED: ' + role)
    pe_x64(package / exe)
    index = audit.pck_index(package / pck)
    if not index['files']: raise ValueError('EMPTY_PCK')
    entrypoint = ('assets/scenes/main_menu/opening_background.tscn' if role == 'client'
                  else 'assets/scenes/main_menu/server_bootstrap.tscn')
    if not any('res://' + entrypoint + suffix in index['files'] for suffix in ('', '.remap')):
        raise ValueError('PACKED_ROLE_ENTRYPOINT_REQUIRED: ' + role)
    natives = digest_map(row.get('native_files'))
    dlls = {r: h for r, h in actual.items() if r.lower().endswith('.dll')}
    if not dlls or any(natives.get(r) != h for r, h in dlls.items()) or any(actual.get(r) != h for r, h in natives.items()):
        raise ValueError('EXACT_NATIVE_HASH_MANIFEST_REQUIRED: ' + role)
    for rel in dlls: pe_x64(package / rel)
    if not any(Path(r).name == Path(DLL).name for r in dlls): raise ValueError('SIGNALS_NATIVE_REQUIRED')
    data = {r: h for r, h in actual.items() if r.startswith('data/')}
    if role in ('client', 'server'):
        if not data or row.get('data_files') != data: raise ValueError('EXACT_NONEMPTY_DATA_REQUIRED: ' + role)
        for descriptor in (EXT, 'addons/webrtc_native/webrtc_native.gdextension'):
            if 'res://' + descriptor not in index['files']: raise ValueError('PACKED_NATIVE_DESCRIPTOR_REQUIRED')
    else:
        if data or row.get('data_files') != {}: raise ValueError('SIGNALING_MUST_NOT_HAVE_DATA')
        required = 'native/fate_server_signals.gdextension'
        if required not in natives: raise ValueError('EXTERNAL_SIGNAL_DESCRIPTOR_REQUIRED')
        forbidden = ('res://data/', 'res://scripts/system/', 'res://scripts/match/', 'res://tests/', 'res://tools/')
        if any(r.startswith(forbidden) or r.endswith(('.dll', '.gdextension')) for r in index['files']):
            raise ValueError('SIGNALING_PCK_ROLE_MISMATCH')
    if not re.fullmatch('[0-9a-f]{64}', row.get('source_fingerprint', '')): raise ValueError('SOURCE_FINGERPRINT_REQUIRED')
    return {'package': str(package), 'executable': exe, 'files': actual, 'pck_sha256': actual[pck],
            'native_files': natives, 'data_files': data, 'source_fingerprint': row['source_fingerprint']}


def validate_roles(document, roles):
    result = {}
    for role in roles:
        if role not in document.get('roles', {}): raise ValueError('MISSING_ROLE: ' + role)
        result[role] = validate_artifact(role, document['roles'][role])
    if len(result) > 1:
        if len({r['source_fingerprint'] for r in result.values()}) != 1: raise ValueError('MIXED_FREEZE_ROLES')
        if len({r['pck_sha256'] for r in result.values()}) != len(result): raise ValueError('ROLE_PCK_REUSED')
    native_hashes = {}
    for row in result.values():
        for rel, digest in row['native_files'].items():
            if rel.lower().endswith('.dll'):
                native_hashes.setdefault(Path(rel).name.lower(), set()).add(digest)
    if any(len(values) != 1 for values in native_hashes.values()): raise ValueError('CROSS_ROLE_NATIVE_HASH_DRIFT')
    return result


def runtime_verdict(phase, stages):
    if phase not in (*RUN_PHASES, 'all'): raise ValueError('UNSUPPORTED_RUN_PHASE: ' + phase)
    for row in stages.values():
        if row.get('status') == 'FAIL': return 'FAIL_OR_PRESERVED_PROCESS', row.get('exit_code') or 1
    required = ALL_RUN_PHASES if phase == 'all' else (phase,)
    if any(stages.get(p, {}).get('status') != 'PASS' for p in required): return 'INCOMPLETE_NOTRUN', 3
    # RSA executor is an explicitly identified editor fixture, not release-client authentication.
    return 'PARTIAL_NOT_THREE_ROLE_PASS', 0


def load_client_startup_proof(path, digest, artifact_manifest, artifact_manifest_sha256, *, allow_old=False):
    """Consume the producer's persisted receipt without launching or inventing evidence."""
    from tools.diagnostics import round53_exported_runtime as probe
    if path is None or not isinstance(digest, str) or not re.fullmatch('[0-9a-f]{64}', digest):
        raise ValueError('CLIENT_STARTUP_PROOF_REQUIRED')
    path = checked(path)
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != digest: raise ValueError('CLIENT_STARTUP_PROOF_HASH_MISMATCH')
    receipt = json.loads(raw)
    manifest = checked(artifact_manifest)
    if sha(manifest) != artifact_manifest_sha256: raise ValueError('CLIENT_STARTUP_MANIFEST_HASH_MISMATCH')
    document = json.loads(manifest.read_text(encoding='utf-8'))
    identity = probe.startup_identity(document)
    if (receipt.get('schema') != 'round53-client-startup-v1' or receipt.get('stage') != 'client-startup'
        or receipt.get('nonfinal') is not True or type(receipt.get('old_artifact')) is not bool
        or set(receipt.get('stages', {})) != {'client-startup'}):
        raise ValueError('CLIENT_STARTUP_RECEIPT_SCOPE_MISMATCH')
    if (checked(receipt['artifact_manifest']) != manifest or receipt.get('artifact_manifest_sha256') != artifact_manifest_sha256
        or receipt.get('identity') != identity):
        raise ValueError('CLIENT_STARTUP_RECEIPT_IDENTITY_MISMATCH')
    if checked(receipt['root']) / 'runtime.json' != path: raise ValueError('CLIENT_STARTUP_PROOF_PATH_MISMATCH')
    if receipt['old_artifact'] and not allow_old: raise ValueError('CLIENT_STARTUP_EXPLICIT_OLD_ARTIFACT_REQUIRED')
    stage = receipt['stages']['client-startup']
    if not isinstance(stage, dict) or stage.get('status') not in {'PASS', 'FAIL'}:
        raise ValueError('CLIENT_STARTUP_COMPLETED_RECEIPT_REQUIRED')
    validated = {}
    if stage['status'] == 'PASS':
        validated = probe.validate_client_startup_receipt(receipt, manifest, artifact_manifest_sha256,
                                                        require_current=not allow_old)
    raw_exit = stage.get('exit_code')
    if raw_exit is not None and type(raw_exit) is not int: raise ValueError('CLIENT_STARTUP_RAW_EXIT_INVALID')
    if stage['status'] == 'FAIL' and receipt.get('exit_code') != 1:
        raise ValueError('CLIENT_STARTUP_FAILURE_EXIT_MISMATCH')
    if sha(path) != digest: raise ValueError('CLIENT_STARTUP_PROOF_DRIFT')
    return {'status': stage['status'], 'exit_code': 0 if stage['status'] == 'PASS' else (raw_exit or 1),
            'raw_exit_code': raw_exit, 'probe_exit_code': receipt['exit_code'],
            'proof': {'path': str(path), 'sha256': digest}, 'producer_stage': stage,
            'identity': identity, 'old_artifact': receipt['old_artifact'], 'nonfinal': True,
            'eligible_for_current_candidate': validated.get('eligible_for_current_candidate', False),
            'boundary': 'official exported headless startup only; no GUI/two-client/save/recovery/release claim'}


def validate_formal_receipt(receipt, artifact_manifest, artifact_manifest_sha256):
    """Validate a phase-runformal receipt without upgrading it to release approval."""
    if not isinstance(receipt, dict) or receipt.get('schema') != 1:
        raise ValueError('FORMAL_RECEIPT_SCHEMA_REQUIRED')
    manifest = checked(artifact_manifest)
    if not isinstance(artifact_manifest_sha256, str) or sha(manifest) != artifact_manifest_sha256:
        raise ValueError('FORMAL_RECEIPT_ARTIFACT_HASH_MISMATCH')
    declared_path = receipt.get('artifact_manifest')
    if not isinstance(declared_path, str) or checked(declared_path) != manifest:
        raise ValueError('FORMAL_RECEIPT_ARTIFACT_BINDING_MISMATCH')
    if receipt.get('artifact_manifest_sha256') != artifact_manifest_sha256:
        raise ValueError('FORMAL_RECEIPT_ARTIFACT_HASH_BINDING_MISMATCH')
    phase = receipt.get('run_phase')
    stages = receipt.get('stages')
    if not isinstance(stages, dict):
        raise ValueError('FORMAL_RECEIPT_STAGES_REQUIRED')
    # Receipts predating this independent phase remain readable as NOTRUN, never PASS.
    stages = dict(stages)
    if phase not in {'client-startup', 'all'}: stages.setdefault('client-startup', {'status': 'NOTRUN'})
    if phase == 'client-startup' and (
        any(row.get('status') != 'NOTRUN' for name, row in stages.items() if name != 'client-startup')
        or receipt.get('formal_exported_client_RSA', 'NOTRUN') != 'NOTRUN'):
        raise ValueError('CLIENT_STARTUP_CANNOT_UPGRADE_OTHER_STAGES')
    for name in RUN_PHASES:
        row = stages.get(name)
        if not isinstance(row, dict) or row.get('status') not in {'NOTRUN', 'PASS', 'FAIL'}:
            raise ValueError('FORMAL_RECEIPT_STAGE_INVALID: ' + name)
        if row.get('status') == 'PASS' and (type(row.get('exit_code')) is not int or row['exit_code'] != 0):
            raise ValueError('FORMAL_RECEIPT_PASS_EXIT_MISMATCH: ' + name)
        if name == 'client-startup' and row['status'] == 'PASS':
            proof = row.get('proof', {})
            validated = load_client_startup_proof(proof.get('path'), proof.get('sha256'), manifest,
                artifact_manifest_sha256, allow_old=row.get('old_artifact') is True)
            if fingerprint(row) != fingerprint(validated): raise ValueError('CLIENT_STARTUP_FORMAL_PROOF_MISMATCH')
    expected, expected_code = runtime_verdict(phase, stages)
    if receipt.get('classification') != expected:
        raise ValueError('FORMAL_RECEIPT_CLASSIFICATION_MISMATCH')
    if receipt.get('exit_code') != expected_code:
        raise ValueError('FORMAL_RECEIPT_EXIT_MISMATCH')
    forbidden = ('SOURCE_PASS', 'RELEASE_PASS', 'READY')
    final_values = (receipt.get('classification'), receipt.get('formal_exported_client_RSA'),
                    receipt.get('status'), receipt.get('source_PASS'), receipt.get('release_PASS'),
                    receipt.get('ready_token'))
    if any(token in str(value).upper() for value in final_values for token in forbidden):
        raise ValueError('FORMAL_RECEIPT_FALSE_FINAL_STATUS')
    return {'run_phase': phase, 'classification': expected, 'exit_code': receipt.get('exit_code'),
            'stages': {name: stages[name] for name in RUN_PHASES},
            'formal_exported_client_RSA': receipt.get('formal_exported_client_RSA', 'NOTRUN')}


def validate_status(receipt):
    old = {'game_port', 'rooms', 'attached_clients', 'pending_clients', 'relay_port', 'server_name', 'motd'}
    result = receipt.get('result', {})
    if receipt.get('ok') is not True or not old.issubset(result): raise ValueError('STATUS_ORIGINAL_FIELDS_REQUIRED')
    from tools.diagnostics.round53_signaling_initialization import METHODS
    observed = result.get('native_capabilities', {})
    if set(observed) != set(METHODS): raise ValueError('STATUS_NATIVE_CLASSES_MISSING')
    for name, methods in METHODS.items():
        row = observed[name]
        if row.get('exists') is not True or row.get('can_instantiate') is not True or row.get('methods') != dict.fromkeys(methods, True):
            raise ValueError('STATUS_NATIVE_METHODS_MISMATCH: ' + name)
    if result.get('validation_policy') != {'enabled': True, 'budget': 15} or result.get('worker_pool') != {'max_threads': 20}:
        raise ValueError('STATUS_APPLIED_DEFAULT15_POOL20_REQUIRED')
    return receipt


def formal_runner(root, document, manifest_path, args):
    """Only adapt paths and verification. Reuse R53 Job/IPC + R54 RSA/close APIs."""
    diagnostics = REPO / 'tools/diagnostics'
    sys.path.insert(0, str(diagnostics))
    from round54_packaged_server_protocol import ProtocolRunner
    from round53_exported_runtime import Runner

    class FormalRunner(ProtocolRunner):
        def __init__(self):
            self.root = root; self.mpath = root / 'process-runtime.json'
            self.parent = document; self.live = []
            self.state = {'owner': 'round64-formal-artifact-entry', 'runs': [],
                          'parent_manifest_sha256': sha(manifest_path), 'verdict': 'NOT_COMPLETE'}
            self.save()

        def verify(self, label):
            if sha(manifest_path) != self.state['parent_manifest_sha256']: raise ValueError('ARTIFACT_MANIFEST_DRIFT')
            checked_roles = validate_roles(document, list(document['roles']))
            if args.rsa_project is not None:
                verify_rsa_fixture(args, document['roles']['server']['source_fingerprint'])
            self.state.setdefault('package_verifications', {})[label] = {r: fingerprint(v['files']) for r, v in checked_roles.items()}
            self.save()

        def command(self, role, argv):
            if role == 'fixture':
                verify_rsa_fixture(args, document['roles']['server']['source_fingerprint'])
                return [str(args.godot), '--headless', '--audio-driver', 'Dummy', '--rendering-method',
                        'gl_compatibility', '--path', str(args.rsa_project), *map(str, argv)]
            if role == 'client':
                entry = self.parent['roles'][role]
                return [str(Path(entry['package']) / entry['declaration']['executable']),
                        '--audio-driver', 'Dummy', '--rendering-method', 'gl_compatibility', *map(str, argv)]
            return Runner.command(self, role, argv)

        def wait_ready(self, item, cfg):
            Runner.wait_ready(self, item, cfg)
            status = self.console('trusted-local-status', cfg, 'status')
            self.state['trusted_local_status_original'] = status; self.save()
            try: validate_status(status)
            except ValueError:
                # No RSA/create has happened yet. Only an actually empty own gateway may stop.
                empty = self.console('status-failure-empty-rooms', cfg, 'rooms')
                if empty == {'ok': True, 'result': []}:
                    stop = self.console('status-failure-empty-stop', cfg, 'stop')
                    if stop.get('ok') and not stop.get('result', {}).get('failures'): self.finish(item)
                raise

    return FormalRunner()


def verify_rsa_fixture(args, source_fingerprint):
    """An explicit pre-existing immutable editor harness; never inject it into release PCK."""
    import package_audit as audit
    if any(v is None for v in (args.godot, args.rsa_project, args.rsa_manifest, args.rsa_manifest_sha256)):
        raise ValueError('EXPLICIT_IMMUTABLE_RSA_FIXTURE_AND_ENGINE_REQUIRED')
    if sha(checked(args.godot)) != 'ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424':
        raise ValueError('ORIGINAL_RSA_EDITOR_REQUIRED')
    if sha(checked(args.rsa_manifest)) != args.rsa_manifest_sha256: raise ValueError('RSA_MANIFEST_HASH_DRIFT')
    fixture = json.loads(args.rsa_manifest.read_text(encoding='utf-8'))
    project = checked(args.rsa_project)
    if project.drive.upper() != 'E:' or project == checked(REPO): raise ValueError('IMMUTABLE_RSA_PROJECT_REQUIRED')
    if fixture.get('source_fingerprint') != source_fingerprint: raise ValueError('RSA_FIXTURE_FREEZE_MISMATCH')
    files = digest_map(fixture['files'])
    current = {r: h for r, h in audit.manifest(project).items() if not r.startswith('.godot/')}
    if current != files: raise ValueError('RSA_FIXTURE_HASH_DRIFT')
    for name in ('round54_authenticated_client.gd', 'round54_authenticated_client.tscn'):
        rel = 'tools/diagnostics/' + name
        if files.get(rel) != sha(REPO / rel): raise ValueError('EXISTING_RSA_EXECUTOR_REQUIRED')
    return fixture


def validate_signal_runner(args):
    if args.signal_runner is None or args.signal_runner_sha256 is None: raise ValueError('EXPLICIT_OWNED_SIGNAL_RUNNER_REQUIRED')
    runner = checked(args.signal_runner)
    if runner.drive.upper() != 'E:' or sha(runner) != args.signal_runner_sha256: raise ValueError('SIGNAL_RUNNER_HASH_MISMATCH')
    pe_x64(runner)
    return runner


def signal_phase(root, row, args, negative):
    """Use the already implemented exact-console owner and real websocket executor."""
    from tools.diagnostics import round53_signaling_initialization as probe
    from tools.release import signaling_prepare as signaling
    import socket
    runner = validate_signal_runner(args)
    sample = root / ('signaling-negative' if negative else 'signaling-ready'); sample.mkdir()
    (sample / 'project').mkdir()  # runner cwd only; no Godot --path/--script.
    env = probe.child_env(sample)
    config = sample / 'missing.json'
    if not negative:
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0)); port = sock.getsockname()[1]
        probe.save(sample / 'signaling.json', {'roles': ['relay'], 'p2p_signaling': True,
                                             'port': port, 'bind_address': '127.0.0.1'})
        config = sample / 'signaling.json'
    executable = Path(row['package']) / row['declaration']['executable']
    result, text = probe.run(sample, runner, executable,
        ['--headless', '--', '--server-signaling', '--config', str(config)], env, 'actual-exported',
        interaction=None if negative else lambda ready: probe.traffic(ready['port']))
    passed = (probe.negative_contract(result, text, require_script_backtrace=False) if negative
              else signaling.production_ready(text, result))
    return {'status': 'PASS' if passed else 'FAIL', 'exit_code': 0 if passed else (result['exit'] or 1),
            'raw_exit_code': result['exit'], 'result': result,
            'expected_exit': 2 if negative else 0, 'config_sha256': None if negative else sha(config)}


def client_startup_phase(root, manifest_path, args):
    """One producer call for new artifacts, or exact read-only prior receipt consumption."""
    proof = args.client_startup_receipt
    digest = args.client_startup_receipt_sha256
    if proof is None:
        from tools.diagnostics import round53_exported_runtime as probe
        owned = root / 'client-startup'
        probe.run_client_startup(owned, manifest_path, args.artifact_manifest_sha256,
                                old_artifact=args.client_startup_old_artifact)
        proof = owned / 'runtime.json'; digest = sha(proof)
    return load_client_startup_proof(proof, digest, manifest_path, args.artifact_manifest_sha256,
                                    allow_old=args.client_startup_old_artifact)


def run_formal(args):
    if args.run_phase not in (*RUN_PHASES, 'all'): raise ValueError('UNSUPPORTED_RUN_PHASE: ' + args.run_phase)
    if args.build or args.inventory or args.ready_token is not None: raise ValueError('RUNTIME_CANNOT_BUILD_OR_APPROVE')
    manifest_path = checked(args.artifact_manifest)
    if not args.artifact_manifest_sha256 or sha(manifest_path) != args.artifact_manifest_sha256:
        raise ValueError('PINNED_ARTIFACT_MANIFEST_HASH_REQUIRED')
    document = json.loads(manifest_path.read_text(encoding='utf-8'))
    selected = list(ALL_RUN_PHASES) if args.run_phase == 'all' else [args.run_phase]
    if (args.client_startup_receipt is None) != (args.client_startup_receipt_sha256 is None):
        raise ValueError('CLIENT_STARTUP_RECEIPT_PATH_AND_HASH_REQUIRED')
    if 'client-startup' not in selected and (args.client_startup_receipt is not None or args.client_startup_old_artifact):
        raise ValueError('CLIENT_STARTUP_OPTIONS_REQUIRE_STAGE')
    roles = list(dict.fromkeys('signaling' if p.startswith('signaling-') else 'server' if p == 'status'
                              else 'client' if p == 'client-startup' else p for p in selected))
    verified = validate_roles(document, roles)
    if args.run_phase == 'all' and set(document['roles']) != {'client', 'server', 'signaling'}: raise ValueError('EXACT_THREE_ROLES_REQUIRED')
    if 'server' in selected:
        binding = document.get('rsa_fixture', {})
        for name, key in (('rsa_project', 'project'), ('rsa_manifest', 'manifest'), ('rsa_manifest_sha256', 'manifest_sha256')):
            value = binding.get(key)
            if value is None: raise ValueError('BUILD_BOUND_RSA_FIXTURE_REQUIRED')
            if getattr(args, name) is None: setattr(args, name, Path(value) if name != 'rsa_manifest_sha256' else value)
            if (str(checked(getattr(args, name))) != str(checked(value)) if name != 'rsa_manifest_sha256'
                else getattr(args, name) != value): raise ValueError('RSA_FIXTURE_BINDING_MISMATCH')
        fixture = verify_rsa_fixture(args, document['roles']['server']['source_fingerprint'])
        if fingerprint(fixture['files']) != binding.get('files_fingerprint'): raise ValueError('RSA_CLOSURE_BINDING_MISMATCH')
    if any(p.startswith('signaling-') for p in selected): validate_signal_runner(args)
    if 'status' in selected:
        if args.console_dir is None: raise ValueError('EXPLICIT_EXISTING_CONSOLE_DIR_REQUIRED')
        console = checked(args.console_dir)
        if console.drive.upper() != 'E:' or not console.is_dir(): raise ValueError('EXISTING_PHYSICAL_E_CONSOLE_REQUIRED')
    if args.root is None or args.approved_root is None: raise ValueError('EXPLICIT_RUNTIME_ROOT_REQUIRED')
    root = checked(args.root); approved = checked(args.approved_root)
    if root.drive.upper() != 'E:' or approved.drive.upper() != 'E:': raise ValueError('PHYSICAL_E_RUNTIME_ROOT_REQUIRED')
    if any(root.is_relative_to(checked(r['package'])) or checked(r['package']).is_relative_to(root) for r in document['roles'].values()):
        raise ValueError('RUNTIME_PACKAGE_OVERLAP')
    new_output(root, protected=(REPO, manifest_path.parent), allowed_root=approved)
    if root.exists(): raise ValueError('FRESH_RUNTIME_ROOT_REQUIRED')
    root.mkdir(parents=True)
    state = {'schema': 1, 'artifact_manifest': str(manifest_path), 'artifact_manifest_sha256': sha(manifest_path),
             'classification': 'NOTRUN', 'run_phase': args.run_phase,
             'stages': {p: {'status': 'NOTRUN'} for p in RUN_PHASES},
             'artifact_verification': verified, 'formal_exported_client_RSA': 'NOTRUN',
             'limitations': ['RSA stage uses declared existing editor diagnostic, not release client GUI authentication',
                             'no match save/restore, multi-host or new native production capability claim']}
    target = root / 'formal-runtime.json'
    def save(): target.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding='utf-8')
    save(); runner = None
    try:
        for phase in selected:
            if sha(manifest_path) != args.artifact_manifest_sha256: raise ValueError('ARTIFACT_MANIFEST_DRIFT')
            validate_roles(document, roles)
            state['stages'][phase] = {'status': 'RUNNING'}; save()
            if phase == 'client-startup':
                result = client_startup_phase(root, manifest_path, args)
            elif phase.startswith('signaling-'):
                result = signal_phase(root, document['roles']['signaling'], args, phase.endswith('negative'))
            else:
                if runner is None: runner = formal_runner(root, document, manifest_path, args)
                if phase == 'client':
                    row, text = runner.run('client-official-opening', 'client', ['--verbose', '--fixed-fps', '60', '--quit-after', '180'])
                    ok = row['exit_code'] == 0 and not row['errors'] and row['active_owned_processes'] == 0
                    result = {'status': 'PASS' if ok else 'FAIL', 'exit_code': row['exit_code'] or (0 if ok else 1),
                              'raw_exit_code': row['exit_code'], 'run': row, 'boundary': 'unaltered official opening, no script/scene override; no GUI interaction claim'}
                elif phase == 'status':
                    if args.console_dir is None: raise ValueError('EXPLICIT_EXISTING_CONSOLE_DIR_REQUIRED')
                    console = checked(args.console_dir)
                    if console.drive.upper() != 'E:': raise ValueError('PHYSICAL_E_CONSOLE_REQUIRED')
                    receipt = runner.console('read-only-existing-status', {'console_dir': str(console)}, 'status')
                    validate_status(receipt)
                    result = {'status': 'PASS', 'exit_code': 0, 'receipt': receipt, 'boundary': 'existing PID read-only; no stop/ownership adoption'}
                else:
                    runner.execute()
                    result = {'status': 'PASS', 'exit_code': 0, 'process_manifest': str(runner.mpath),
                              'boundary': 'R54 RSA editor fixture, worker READY, empty-lobby room_state_saved (not match save), close then stop'}
            state['stages'][phase] = result; save()
            validate_roles(document, roles)
            if result['status'] != 'PASS': break
    except Exception as exc:
        state['stages'][phase] = {'status': 'FAIL', 'exit_code': 1, 'reason': str(exc)}
        if runner is not None:
            failed = next((r for r in runner.state['runs'] if r.get('exit_code', 0) != 0), None)
            if failed: state['stages'][phase].update(exit_code=failed['exit_code'], raw_exit_code=failed['exit_code'])
        state['error'] = str(exc)
    finally:
        if runner is not None:
            state['owned_processes_unresolved'] = [item[4] for item in runner.live]
            runner.state['preserved_unsaved_or_unknown_process'] = bool(runner.live); runner.save()
            # No TerminateJobObject and no KILL_ON_JOB_CLOSE; preserve failed/unknown server.
            for process, job, out, err, record, started in runner.live:
                out.close(); err.close(); job.close()
        try:
            if sha(manifest_path) != args.artifact_manifest_sha256: raise ValueError('ARTIFACT_MANIFEST_DRIFT')
            validate_roles(document, roles)
        except Exception as exc:
            state.setdefault('verification_failures', []).append(str(exc))
            if state['stages'].get(phase, {}).get('status') != 'FAIL':
                state['stages'][phase] = {'status': 'FAIL', 'exit_code': 1, 'reason': str(exc)}
        state['classification'], code = runtime_verdict(args.run_phase, state['stages'])
        state['exit_code'] = code; save()
    return {'classification': state['classification'], 'exit_code': code, 'report': str(target),
            'stages': state['stages'], 'formal_exported_client_RSA': 'NOTRUN'}, code


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--source', type=Path, default=REPO); ap.add_argument('--root', type=Path)
    ap.add_argument('--approved-root', type=Path); ap.add_argument('--ready-token', type=Path)
    ap.add_argument('--inventory', action='store_true'); ap.add_argument('--build', action='store_true')
    ap.add_argument('--build-only-diagnostic', action='store_true',
                    help='Explicitly authorize independent diagnostic snapshot/export, never final admission')
    ap.add_argument('--godot', type=Path); ap.add_argument('--templates', type=Path)
    ap.add_argument('--run-formal', action='store_true')
    ap.add_argument('--artifact-manifest', type=Path)
    ap.add_argument('--artifact-manifest-sha256')
    ap.add_argument('--run-phase', default='all', help='Independent client-startup never attests original client GUI/RSA stage')
    ap.add_argument('--client-startup-receipt', type=Path, help='Reuse exact producer runtime.json; do not relaunch EXE')
    ap.add_argument('--client-startup-receipt-sha256')
    ap.add_argument('--client-startup-old-artifact', action='store_true',
                    help='Explicitly label old-artifact startup proof nonfinal; never current candidate acceptance')
    ap.add_argument('--console-dir', type=Path)
    ap.add_argument('--signal-runner', type=Path)
    ap.add_argument('--signal-runner-sha256')
    ap.add_argument('--rsa-project', type=Path)
    ap.add_argument('--rsa-manifest', type=Path)
    ap.add_argument('--rsa-manifest-sha256')
    args = ap.parse_args(argv)
    try:
        if args.build_only_diagnostic:
            if args.build or args.inventory or args.run_formal or args.ready_token is not None:
                raise ValueError('DIAGNOSTIC_STAGE_CANNOT_BUILD_APPROVE_OR_RUN_FORMAL')
            if any(v is None for v in (args.root, args.approved_root, args.godot, args.templates)):
                raise ValueError('EXPLICIT_DIAGNOSTIC_PATHS_REQUIRED')
            result = diagnostic_build(args.source, args.root, args.approved_root, args.godot, args.templates, authorized=True)
            print(json.dumps(result, ensure_ascii=False, indent=2)); return 0
        if args.run_formal:
            if args.artifact_manifest is None: raise ValueError('ARTIFACT_MANIFEST_REQUIRED')
            result, code = run_formal(args)
            print(json.dumps(result, ensure_ascii=False, indent=2)); return code
        if args.inventory:
            if args.build: raise ValueError('INVENTORY_CANNOT_BUILD')
            print(json.dumps(current_inventory(args.source), ensure_ascii=False, indent=2)); return 0
        if args.ready_token is None: raise ValueError('READY_TOKEN_REQUIRED')
        if args.root is None or args.approved_root is None: raise ValueError('EXPLICIT_FRESH_ROOT_AND_APPROVED_ROOT_REQUIRED')
        result = preflight(args.source, args.ready_token, args.root, args.approved_root)
        result['build_plan'] = build_plan(result)
        if args.godot is not None and args.templates is not None:
            result['build_invocation'] = [sys.executable, '-B', str(Path(__file__).resolve()), '--source', str(checked(args.source)),
                '--root', result['root'], '--approved-root', result['approved_root'], '--ready-token', str(checked(args.ready_token)),
                '--godot', str(checked(args.godot)), '--templates', str(checked(args.templates)), '--build']
        if args.build:
            if args.godot is None or args.templates is None: raise ValueError('EXPLICIT_GODOT_AND_TEMPLATES_REQUIRED')
            result = build(result, args.godot, args.templates)
        print(json.dumps(result, ensure_ascii=False, indent=2)); return 0
    except (OSError, ValueError, KeyError, TypeError, IndexError) as exc:
        print(json.dumps({'allow_build': False, 'status': 'BLOCKED', 'reason': str(exc)}, ensure_ascii=False)); return 2


if __name__ == '__main__': raise SystemExit(main())
