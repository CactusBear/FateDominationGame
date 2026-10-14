"""Generate current prepared input + inventory; statically validate, never run Godot.

Existing selection, classification, dependency scanner, approval and scheduler
policies are the sole authorities. No synthetic approval or execution results.
"""
import argparse
from collections import Counter
import importlib.util
import json
import os
from pathlib import Path
import shlex
import sys

sys.dont_write_bytecode = True
PROJECT = Path(__file__).resolve().parents[1]
ENTRY = 'tools/tests/test_round29_integrated_evidence.py'
OWNER_BYTES = 8 * 1024 ** 3


def load_entry():
    spec = importlib.util.spec_from_file_location('regression_inventory_entry', PROJECT / ENTRY)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def inventory_rows(entry, selection):
    options = entry.round71_scheduler_options(2, 2, 2 * 1024 ** 3, 4 * 1024 ** 3, OWNER_BYTES)
    rows = []
    for name in selection['names']:
        category = next(k for k, group in selection['categories'].items() if name in group)
        contract = selection.get('scene_contracts', {}).get(name, {})
        policy = entry.round71_parallel_resource_policy(name, 'complete', selection, options)
        rows.append({'suite': name,
                     'scene': 'res://' + contract.get('scene', 'tests/' + name + '.tscn'),
                     'category': category, 'is_long_suite': category == 'long_correctness',
                     'parallel_allowed': policy['known_parallel'],
                     'parallel_condition': 'jobs>1; complete phase; short_headless; explicit caller allowlist',
                     'headless_selected': name in selection['headless'],
                     'minimum_checks': selection['mandatory_checks'].get(name),
                     'semantic_contract': selection.get('semantic_contracts', {}).get(name),
                     'status': 'planned', 'execution_status': 'notrun'})
    return rows


def install_static_guard():
    """Block process APIs except readonly git and Python import preflight."""
    allowed_python = 'import ctypes,json,sys; print(sys.executable)'
    events = []

    def audit(event, args):
        if event == 'subprocess.Popen':
            executable, argv = args[:2]
            allowed = [
                [sys.executable, '-B', '-c', allowed_python],
                ['git', 'rev-parse', 'HEAD'], ['git', 'status', '--short']]
            if isinstance(argv, str):
                import subprocess
                command = next((item for item in allowed if subprocess.list2cmdline(item) == argv), None)
            elif isinstance(argv, (list, tuple)):
                command = next((item for item in allowed if item == list(argv)), None)
            else:
                command = None
            if command is None:
                raise RuntimeError('static-only: subprocess rejected')
            if executable is not None and Path(str(executable)).name.lower() != Path(command[0]).name.lower():
                raise RuntimeError('static-only: executable/command mismatch')
            events.append(Path(command[0]).name.lower())
        if event in {'os.system', 'os.startfile', 'os.posix_spawn', 'os.posix_spawnp'}:
            raise RuntimeError('static-only: process API rejected')

    sys.addaudithook(audit)
    return events


def execution_argv(plan_path, root, cancel):
    return ['python', '-B', ENTRY, '--round71', '--execute-prepared', plan_path.as_posix(),
            '--approved-root', root.as_posix(), '--collect-failures', '--jobs', '2',
            '--cpu-budget', '2', '--memory-budget-bytes', str(2 * 1024 ** 3),
            '--disk-budget-bytes', str(4 * 1024 ** 3), '--cancel-file', cancel.as_posix()]


def validate(entry, path, plan, argv):
    """Use actual prepared validator and actual entry argparse without execution."""
    entry.round71_validate_prepared(plan, proof=True)  # structural/hash checks only, not proof execution
    rows = inventory_rows(entry, plan['preflight']['selection'])
    inv = plan['regression_inventory']
    if inv['suites'] != rows:
        raise ValueError('inventory does not match existing selection/policy')
    names = [r['suite'] for r in rows]
    if inv['counts'] != counts(plan['preflight']['selection'], rows):
        raise ValueError('inventory count mismatch')
    for row in rows:
        if not (Path(plan['preflight']['source_root']) / row['scene'][6:]).is_file():
            raise ValueError('selected scene not landed: ' + row['suite'])
    selection = plan['preflight']['selection']
    if selection.get('resource_proof') or plan.get('approved_inputs'):
        raise ValueError('inventory generator does not manufacture proof/approval')
    if len(names) != len(set(names)) or len(plan['plan_id']) != 32:
        raise ValueError('invalid inventory identity')
    gate_error = None
    try:
        entry.round71_validate_prepared(plan, proof=False)
    except entry.runner.SafetyError as exc:
        if not str(exc).startswith('NOTREADY final integration dependencies'):
            raise
        gate_error = str(exc)
    captured = {}

    def intercept(parsed_plan, proof=False, collect_failures=False, scheduler_config=None):
        if parsed_plan != plan or proof or not collect_failures:
            raise ValueError('actual entry mode/payload mismatch')
        options = entry.round71_scheduler_options(
            scheduler_config['jobs'], scheduler_config['cpu_budget'],
            scheduler_config['memory_budget_bytes'], scheduler_config['disk_budget_bytes'], OWNER_BYTES)
        captured.update(scheduler_config)
        if options['jobs'] != 2 or Path(scheduler_config['cancel_file']).exists():
            raise ValueError('cancel file must be absent before future execution')
        return 0

    old_executor, old_argv = entry.round71_execute_prepared, sys.argv
    try:
        entry.round71_execute_prepared = intercept
        sys.argv = [str(PROJECT / ENTRY)] + argv[3:]
        code = entry.round71_entry()
    finally:
        entry.round71_execute_prepared, sys.argv = old_executor, old_argv
    if code != 0 or not captured:
        raise ValueError('actual entry parser did not capture planned arguments')
    return {'parser_only_exit_code': code, 'schema_and_hashes_validated': True,
            'actual_entry_cli_parsed': True, 'scheduler_arguments': captured,
            'execution_gate_satisfied': gate_error is None, 'execution_gate_error': gate_error,
            'status': 'planned', 'execution_status': 'notrun',
            'godot_launch_count': 0, 'cold_import_count': 0, 'suite_execution_count': 0,
            'validation_boundary': 'No freeze copy, import, attempt receipt or suite execution. proof=True used only for structural validation; normal readiness gate reported separately.'}


def counts(selection, rows):
    return {'formal_scenes': len(rows), 'headless_scenes': len(selection['headless']),
            'native_standalone': len(selection['native_standalone']),
            'programs': selection['program_count'],
            'required_harness_steps': len(selection['required_harness_steps']),
            'supplementary_gui': len(selection['supplementary_gui']),
            'independent_loader_modes': len(selection['independent_loader_modes']),
            'parallel_allowed_suites': sum(r['parallel_allowed'] for r in rows),
            'categories': dict(Counter(r['category'] for r in rows))}


def provenance(entry, p):
    return {'baseline_manifest': {'path': entry.ROUND50_BASE_MANIFEST, 'sha256': p['baseline_manifest_sha256'],
                                  'fields_used': ['selected_suites', 'selection.names', 'selection.headless'],
                                  'historical_results_used': False},
            'entry': {'path': ENTRY, 'sha256': entry.digest(PROJECT / ENTRY),
                      'symbols': ['ROUND50_ADDITIONS', 'ROUND50_EXTRACTED_HARNESSES',
                                  'ROUND64_BASELINE_CHECKS', 'ROUND70_REQUIRED_CHECKS',
                                  'build_round50_selection', 'round71_validate_selection',
                                  'ROUND71_CALLER_PARALLEL_SAFE', 'round71_parallel_resource_policy',
                                  'round71_prepare', 'round71_validate_prepared', 'round73_headless_preflight']},
            'executor_hashes': {rel: entry.digest(PROJECT / rel) for rel in entry.ROUND71_EXECUTORS},
            'rules': [
                'Names/order: baseline original 70 headless + local_spell_restore GUI, then landed explicit ROUND50_ADDITIONS and current ROUND70_REQUIRED_CHECKS. Extracted harnesses separate; missing declared inputs are blockers.',
                'Categories: existing build_round50_selection explicit branches. Long flag means category long_correctness only, not a timeout prediction. performance separate; never classify from name.',
                'Parallel: existing complete-phase policy, jobs>1, short_headless and explicit five-name allowlist; prerequisite and all other suites exclusive.',
                'Production dependency scan: project.godot/scripts/assets/data/game_data/addons/json_maker/icon.svg; existing round50_excluded prunes generated outputs, logs, key/credential roots before byte reads.',
                'Tests: selected tests/<suite>.gd + .tscn, declared harness inputs, round42_explicit_dependencies; recursively resolve literal res loads, extends and static resources. Literal declared outputs excluded. No glob-all include of unrelated tests.',
                'tests recursive .gd/.tscn/.py excluded hashes are drift inventory only, not automatic selection.',
                'headless scope uses existing round73_headless_preflight: preserves formal inventory but excludes GUI-only inputs/requirements from the execution scope. Full GUI/native/loader/harness rows remain separately planned.'
            ]}


def human_report(path, plan, argv, result):
    inv = plan['regression_inventory']
    selection = plan['preflight']['selection']
    lines = ['# 当前仓库完整回归计划（静态生成）', '',
             '全部套件状态均为 **planned / notrun**。未启动 Godot、未导包、未导入、未执行任何业务套件。', '',
             '## 范围与可执行门', '',
             '- 本计划保留全部 formal scene 清单；最终命令只执行现有入口的完整 headless 选集，不代替 GUI、native standalone、独立 loader 或提取 harness。',
             '- scope: `' + inv['scope'] + '`；计数：`' + json.dumps(inv['counts'], ensure_ascii=False) + '`。',
             '- 正常 execution gate: `' + str(result['execution_gate_satisfied']).lower() + '`；原因：`' + str(result['execution_gate_error']) + '`。',
             '- 现有 schema 保留 sourcePASS=false / releasePASS=false；not_run 是原入口兼容值，新增清单只用 planned/notrun。',
             '- 源码或执行器改变后 hash 门会拒绝此计划，必须重新生成；本次未复制冻结输入。',
             '- 使用 jobs=2；CPU reservation=2、memory reservation=2147483648 bytes、disk reservation=4294967296 bytes。固定原 aggregate owner 上限8589934592 bytes不变；这些是调度 reservation，不是 OS 内存/CPU硬限额。',
             '- 长套标记只来自 long_correctness 分类；性能类单列，预算不代表测得耗时。',
             '- 必须先导包，等待用户通知后才能运行；不要现在执行下方命令。', '',
             '## 最终回归命令（等待用户通知）', '', '```bash', shlex.join(argv), '```', '',
             '取消：创建命令中的 --cancel-file 文件；运行前该文件必须不存在。未创建该文件，也未接触已有 runtime owner。', '',
             '## Parser-only 校验', '', '```bash',
             'TMPDIR=E:/scratch TEMP=E:/scratch TMP=E:/scratch python -B tools/generate_regression_plan_inventory.py --parser-only ' + path.as_posix(),
             '```', '', '静态校验记录：`' + json.dumps(result, ensure_ascii=False) + '`。', '',
             '## 套件来源与扫描规则', '', '```json', json.dumps(inv['sources'], ensure_ascii=False, indent=2), '```', '',
             '## 完整 formal scene 清单', '',
             '| # | suite | scene | 分类 | 长套 | 允许并行 | headless选中 | 状态 |',
             '|---:|---|---|---|---|---|---|---|']
    for i, row in enumerate(inv['suites'], 1):
        lines.append('| %s | `%s` | `%s` | %s | %s | %s | %s | planned/notrun |' % (
            i, row['suite'], row['scene'], row['category'], row['is_long_suite'], row['parallel_allowed'], row['headless_selected']))
    lines += ['', '## 独立与补充合同（不充 headless formal 数）', '', '```json', json.dumps({
        k: selection[k] for k in ['native_standalone', 'required_harness_steps',
                                  'supplementary_gui', 'independent_loader_modes']}, ensure_ascii=False, indent=2), '```', '',
        '## 阻断', '', '```json', json.dumps({'blockers': plan['preflight']['blockers'],
            'integration_dependencies': plan['integration_dependencies']}, ensure_ascii=False, indent=2), '```', '']
    return '\n'.join(lines)


def new_plan_path(entry, path, root):
    if not path.is_absolute() or path.drive.upper() != 'E:' or '..' in path.parts:
        raise entry.runner.SafetyError('explicit physical E plan path required')
    parent = entry.runner.no_links(path.parent).resolve(strict=True)
    approved = entry.runner.physical_e(root)
    if not parent.is_relative_to(approved):
        raise entry.runner.SafetyError('new plan parent outside approved root')
    entry.runner.no_links(path)
    return parent / path.name


def write_new(path, value):
    with path.open('x', encoding='utf-8', newline='\n') as handle:
        handle.write(value)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--generate', metavar='NEW_PLAN_JSON')
    mode.add_argument('--parser-only', metavar='PLAN_JSON')
    parser.add_argument('--report', metavar='NEW_DOC_MD')
    parser.add_argument('--scope', choices=['headless', 'full'], default='headless')
    args = parser.parse_args()
    root = Path('E:/scratch')
    os.environ.update(TMPDIR=root.as_posix(), TEMP=root.as_posix(), TMP=root.as_posix())
    events = install_static_guard()
    entry = load_entry()
    root = entry.runner.physical_e(root)
    path = (new_plan_path(entry, Path(args.generate), root) if args.generate
            else entry.runner.contained(Path(args.parser_only), root))
    entry.runner.no_links(path.parent)
    if args.generate:
        report = Path(args.report).resolve() if args.report else None
        if report is None or report.parent != PROJECT / 'docs' or report.exists() or path.exists():
            parser.error('new E:/scratch plan and new repository docs report required')
        preflight = entry.round71_current_preflight(PROJECT, root)
        if args.scope == 'headless':
            preflight = entry.round73_headless_preflight(preflight)
        plan = entry.round71_prepare(preflight)
        rows = inventory_rows(entry, plan['preflight']['selection'])
        argv = execution_argv(path, root, root / (path.stem + '.cancel'))
        plan['regression_inventory'] = {'schema': 'regression-inventory/v1',
            'scope': args.scope, 'status': 'planned', 'execution_status': 'notrun',
            'suites': rows, 'counts': counts(preflight['selection'], rows),
            'sources': provenance(entry, preflight), 'execution_argv': argv}
        write_new(path, json.dumps(plan, ensure_ascii=False, indent=2) + '\n')
        plan = entry.load(path)
    else:
        plan = entry.load(path)
        argv = plan['regression_inventory']['execution_argv']
    result = validate(entry, path, plan, argv)
    result['allowed_readonly_subprocesses'] = events
    if args.generate:
        write_new(report, human_report(path, plan, argv, result))
    print(json.dumps({'plan_path': path.as_posix(), 'sha256': entry.digest(path),
                      'counts': plan['regression_inventory']['counts'], 'validation': result,
                      'final_command': shlex.join(argv)}, ensure_ascii=False, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
