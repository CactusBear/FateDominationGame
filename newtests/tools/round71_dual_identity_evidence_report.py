"""续用 round71_dual_identity_readonly_once.py 的回执，只读后处理，不新增启动尝试。

职责：非空身份判据、双保护 PID 核对、真实旧回执复核、当前元数据核对与报告。
只读公开日志、回执/源码/launcher；身份只枚举元数据与 SHA，绝不解析内容。
"""
import hashlib
import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path

REPO = Path('E:/Projects/Godot/FateDominationGame-master')
BASE = Path('E:/Caches/Hermes/cache/scratch/round71-dual-identity-once-12796')
CANDIDATE = Path('E:/Caches/Hermes/cache/scratch/round71-human-test-candidate-validation-v3/client')
PROTECTED = {17120, 28100}


def identity_verdict(snapshots):
    counts = {role: max((s['roles'].get(role, {}).get('identity_file_count', 0)
                         for s in snapshots), default=0) for role in ['host', 'guest']}
    pairs = [s['roles'] for s in snapshots if all(role in s['roles'] for role in counts)]
    disjoint = bool(pairs) and all(
        os.path.normcase(pair['host']['identity_dir']) != os.path.normcase(pair['guest']['identity_dir'])
        for pair in pairs)
    ready = [p for p in pairs if all(p[role]['identity_file_count'] > 0 for role in counts)]
    different = None
    unchanged = None
    if ready:
        fingerprints = []
        for pair in ready:
            fingerprints.append({role: {entry['name']: entry['sha256']
                                        for entry in pair[role]['identity_files']} for role in counts})
        different = all(p['host'] != p['guest'] for p in fingerprints)
        if len(fingerprints) > 1:
            unchanged = all(p == fingerprints[0] for p in fingerprints[1:])
    return {'generated_both': bool(ready), 'paths_disjoint': disjoint,
            'different_identity_sha': different, 'no_identity_overwrite': unchanged,
            'max_identity_file_counts': counts}


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def write_new(path, text):
    with path.open('x', encoding='utf-8', newline='\n') as stream:
        stream.write(text)


def main():
    assert BASE.resolve().drive.upper() == 'E:'
    source = BASE / 'evidence.json'
    r = json.loads(source.read_text(encoding='utf-8'))
    assert r['headless'] and not r['window_mode'] and r['attempts_per_check'] == 1
    assert r['old_artifact'] and r['nonfinal']
    assert r['Job0'] and r['job_accounting_final']['active'] == 0
    assert not r['watchdog_fired'] and r['artifact_hashes_unchanged']
    seen = {item['pid'] for item in r['observed_process_exit_codes']}
    seen.update(pid for s in r['snapshots'] for pid in s['job_pids'])
    assert not PROTECTED.intersection(seen)
    assert len(r['observed_process_exit_codes']) == r['job_accounting_final']['total']
    assert all(item['exit_code'] == 0 for item in r['observed_process_exit_codes'])
    current_hashes = {path: sha(Path(path)) for path in r['artifact_hashes_after']}
    assert current_hashes == r['artifact_hashes_after'], 'artifact changed since original run'
    launcher = CANDIDATE / 'START-CLIENT.cmd'
    launcher_lines = launcher.read_text(encoding='utf-8').splitlines()
    assert launcher_lines == [line['text'] for line in r['launcher_lines']]
    assert not any('APPDATA' in line.upper() for line in launcher_lines)
    # 仅读名字、PID/PPID 与 EXE 路径；不读 CommandLine、环境、票据或配置。
    command = ('Get-CimInstance Win32_Process | Where-Object { '
               '$_.Name -match "Godot|FateDomination|FateServer" -or '
               '$_.ProcessId -in 17120,28100 } | '
               'Select-Object ProcessId,ParentProcessId,Name,ExecutablePath | ConvertTo-Json -Depth 3')
    env = os.environ.copy()
    # 仅读核对进程也限定临时目录在本次已有 E 盘目录；不生成游戏数据。
    for variable in ['TEMP', 'TMP', 'TMPDIR']:
        env[variable] = str(BASE / 'test-users/host/temp')
    cp = subprocess.run(['powershell.exe', '-NoProfile', '-Command', command], env=env,
                        capture_output=True, text=True, timeout=30)
    assert cp.returncode == 0, 'readonly process census failed'
    census = json.loads(cp.stdout) if cp.stdout.strip() else []
    if isinstance(census, dict):
        census = [census]
    remaining = [p for p in census if os.path.normcase(p.get('ExecutablePath') or '') ==
                 os.path.normcase(str(CANDIDATE / 'FateDomination.exe'))]
    role_current = {}
    logs = {}
    for role, v in r['roles'].items():
        current = {}
        for var in ['APPDATA', 'LOCALAPPDATA']:
            root = Path(v[var])
            files = []
            for path in sorted(root.rglob('*')):
                if path.is_file():
                    # 只算 SHA，不解析私钥/资料；路径与数量来自实际文件系统。
                    files.append({'relative_path': str(path.relative_to(root)), 'name': path.name,
                                  'bytes': path.stat().st_size, 'sha256': sha(path)})
            current[var] = {'path': str(root), 'exists': root.exists(), 'file_count': len(files), 'files': files}
        identities = Path(v['APPDATA']) / 'FateDomination/net_identity'
        current['identity_dir'] = {'path': str(identities), 'exists': identities.exists(),
                                   'file_count': sum(p.is_file() for p in identities.rglob('*'))}
        role_current[role] = current
        checks = []
        for field in ['engine_log', 'stdout_log']:
            path = Path(v[field])
            lines = path.read_text(encoding='utf-8', errors='replace').splitlines()
            checks.append({'path': str(path), 'line_count': len(lines), 'sha256': sha(path),
                           'script_error_count': sum('SCRIPT ERROR' in line for line in lines),
                           'parse_error_count': sum('Parse Error' in line for line in lines),
                           'engine_error_count': sum(line.startswith('ERROR:') for line in lines),
                           'public_key_lines': [{'line': i+1, 'text': line} for i, line in enumerate(lines)
                                                if line.startswith('Godot Engine ')]})
        assert all(item['script_error_count'] == 0 and item['parse_error_count'] == 0 and
                   item['engine_error_count'] == 0 for item in checks)
        logs[role] = checks
    verdict = identity_verdict(r['snapshots'])
    coexisting = [s for s in r['snapshots'] if s['job']['active'] == 6]
    historical_census = r['process_census_coexisting']['processes']
    role_pids = {role: [p['ProcessId'] for p in historical_census
                        if p['ParentProcessId'] == v['launcher_pid'] and p['Name'] == 'FateDomination.exe']
                 for role, v in r['roles'].items()}
    final = r['final']
    summary = {'generated_at': datetime.now(timezone.utc).isoformat(), 'source_evidence': str(source),
               'source_sha256': sha(source), 'old_artifact': True, 'nonfinal': True,
               'additional_client_launches': 0, 'excluded_interrupted_attempt':
               'E:/Caches/Hermes/cache/scratch/round71-dual-identity-once-23212/evidence.json',
               'identity_verdict': verdict, 'overall_acceptance': False,
               'launcher_no_reset': {'static': True, 'APPDATA_runtime_userdirs_separate': True,
                                     'LOCALAPPDATA_runtime_inheritance_observed': False},
               'protected_pids': sorted(PROTECTED), 'protected_not_in_owned_job': True,
               'current_hashes_match_original': True, 'artifact_hashes': current_hashes,
               'binary_pids_by_role': role_pids, 'roles_commands': r['roles'],
               'observed_process_exit_codes': r['observed_process_exit_codes'],
               'job_final': r['job_accounting_final'], 'Job0': r['Job0'],
               'watchdog_fired': r['watchdog_fired'], 'snapshots_count': len(r['snapshots']),
               'coexist_first_elapsed': coexisting[0]['elapsed'],
               'coexist_last_elapsed': coexisting[-1]['elapsed'], 'final_elapsed': final['elapsed'],
               'original_final_directories': final['roles'], 'current_directories': role_current,
               'current_process_census': {'command': command, 'exit_code': cp.returncode, 'processes': census},
               'current_candidate_residuals': remaining, 'log_checks': logs,
               'launcher_lines': r['launcher_lines']}
    output = REPO / 'docs/round71-dual-identity-readonly-evidence.json'
    report = REPO / 'docs/round71-dual-identity-readonly.md'
    parts = [
        '# 同机双客户端身份隔离：只读证据复核', '',
        '**结论：完整身份隔离未通过验收（未生成身份，不能验证身份 SHA 不同/未覆盖）。**',
        '已确认双客户端真实启动、APPDATA 运行数据目录分离、先后启动并发共存、正常退出 Job0、日志无 SCRIPT ERROR。',
        '**old_artifact=true / nonfinal=true；不能写成最终包通过。**', '',
        '## 证据来源与本次边界',
        f'- 复用既有唯一完整 headless 回执：`{source}`；SHA `{summary["source_sha256"]}`。',
        '- 本次追加客户端启动次数 0；不是重新跑一轮。原脚本 `newtests/round71_dual_identity_readonly_once.py` 未改。',
        '- 前任还留有 `round71-dual-identity-once-23212` 的非 headless 中断回执，缺最终退出/Job0；排除，不能当成通过。历史整体并非只有一次尝试。',
        '- 本次只新增只读后处理器与其单测；无窗口输入、无开局/建房/联机、无全量/测速。只操作 E 盘文件。',
        '- 未读取打印身份内容、票据、口令；若需 SHA，仅读字节计算摘要，不解析。',
        '- PID 17120/28100 均不在原自有 Job 的观测 PID 集合；本次不终止任何进程。',
        f'- 原回执 {len(r["snapshots"])} 个快照，180s 看门狗未触发，最后耗时 {final["elapsed"]}s。', '',
        '## 验证点',
        '| 点 | 真实证据 | 结论 |', '|---|---|---|',
        '| ① launcher 不重置变量 | START-CLIENT.cmd 1–5 行仅 echo/setlocal/cd/rem/EXE %*；没有 APPDATA 或 LOCALAPPDATA 赋值。APPDATA 下两侧实际产生独立运行数据。 | 静态两变量保留；APPDATA 动态已证实。LOCALAPPDATA 为空，无子进程环境直接回执，不冒充动态已证实。 |',
        '| ② 不同身份目录/文件 | 全部快照 host=0、guest=0；最终两侧 net_identity 都不存在。 | 未验证，不通过；无身份文件名/SHA可对比。目录路径字符串不同不等于身份生成。 |',
        f'| ③ 先后与并发、不覆盖 | host 先启动，guest 后启动；自有 Job 在 {coexisting[0]["elapsed"]}–{coexisting[-1]["elapsed"]}s 的观测快照内 active=6；对应两个真实 EXE PID。 | 共存通过；身份覆盖检查未验证（不存在身份），不得空集判成功。未做“host完全退出后再开guest”的另一轮。 |',
        f'| ④ 退出、Job0、日志 | total={r["job_accounting_final"]["total"]}, active=0, terminated=0；6 个已观察进程退出码均0；两角色两份日志的 SCRIPT ERROR/Parse Error/ERROR: 均0。 | 原 headless 启动/退出专项通过；当前候选 EXE 残留数量={len(remaining)}。 |', '',
        '## 原始真实命令与 PID/退出码',
        '原调用给每个角色设置如下进程级环境；临时目录也在 E 盘。`--quit-after 180` 是迭代数，不是 180s，另有独立墙钟看门狗。额外 `--max-fps 10` 来自原真实命令。',
    ]
    for role, v in r['roles'].items():
        parts += ['', f'### {role}', '```bat']
        parts += [f'set "{var}={v[var]}"' for var in ['APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'TMPDIR']]
        parts += [v['native_command'], '```',
                  f'- CMD PID `{v["launcher_pid"]}`，退出码 `{v["launcher_exit_code"]}`；EXE PID `{role_pids[role]}`，退出码 0。']
    parts += ['', '所有被持有句柄的自有进程（含 CMD/EXE 与未命名辅助进程，不猜辅助角色）：',
              '```json', json.dumps(r['observed_process_exit_codes'], ensure_ascii=False, indent=2), '```', '',
              '## 目录/文件比对（本次文件系统读取）',
              '下表 SHA 是复核时的现存运行数据 SHA，不是运行时身份 SHA；原快照仅保存运行文件路径/大小。',
              '| 角色/变量 | 目录存在 | 文件数量 | 相对文件名与 SHA-256 |', '|---|---|---|---|']
    identity_notes = []
    for role, current in role_current.items():
        for var in ['APPDATA', 'LOCALAPPDATA']:
            item = current[var]
            details = '; '.join(f'`{f["relative_path"]}` ({f["bytes"]} bytes), `{f["sha256"]}`' for f in item['files']) or '无文件，SHA=N/A'
            parts += [f'| {role}/{var}: `{item["path"]}` | {item["exists"]} | {item["file_count"]} | {details} |']
        identity_notes += [f'- {role} 身份目录：`{current["identity_dir"]["path"]}`；存在={current["identity_dir"]["exists"]}，文件数={current["identity_dir"]["file_count"]}，文件名/SHA=N/A。']
    parts += ['', *identity_notes]
    parts += ['', '两个 stored_jsons.dat 是公共游戏数据缓存；相同 SHA 不意味着同一个身份。空身份集合也不能证明未覆盖。', '',
              '## 日志关键行（本次重新扫描）']
    for role, items in logs.items():
        for item in items:
            parts += [f'- `{item["path"]}`：{item["line_count"]} 行；SCRIPT ERROR={item["script_error_count"]}，Parse Error={item["parse_error_count"]}，ERROR:={item["engine_error_count"]}。']
            parts += [f'  - L{line["line"]}: `{line["text"]}`' for line in item['public_key_lines']]
    parts += ['', '## 来源核对、说明一致性与最小建议',
              '- launcher L2 `setlocal` 保留调用环境，L3 `cd /d "%~dp0"` 只改工作目录，L5 `"FateDomination.exe" %*` 透传参数。与 quickstart L25–29、L36–40 的隔离命令不冲突；**没有证据要求修 launcher**。',
              '- quickstart L43 明确还需进入联机大厅、填写合法用户名/昵称。不能把只启动主菜单的 headless 过程写成执行了这一条。',
              '- 当前源码 `scripts/net/ui/lobby_screen.gd:24–25` 声明身份文件路径；L42–44 在身份按钮调用 `_prepare_identity()`，L355–360 在合法用户名后调用 `configure_identity()`，L374–376 在创建房间前准备身份。这是源码解释线索，不冒充旧 PCK 行为已按此链验证。',
              '- 最小文档建议（只报告）：在 quickstart L19 后补“设置环境变量只隔离 user:// 落点；仅启动主菜单不会自动生成身份。身份须经大厅合法用户名/昵称及身份准备操作生成。headless 启动不能替代身份生成/覆盖验收。”',
              '- 真正补齐验收须另获批准：同一最终候选在两个隔离目录经正式身份准备入口各生成身份；只记录路径/数量/文件名/SHA；保留先后与共存时的非空 SHA 快照，再核对退出 Job0。不要伪造或复制身份文件，也不要用直接调用密钥生成替代 launcher/UI 链。',
              '- 当前候选 EXE 与旧诊断 EXE 的 SHA 相同；三个原追踪文件的运行前后 SHA 一致且本次复核仍一致。原运行未保存 PCK/DLL SHA，不能扩大成整个包未变或最新源码已打包。', '',
              '| 文件 | 原前/后/本次 SHA-256 |', '|---|---|']
    parts += [f'| `{path}` | `{digest}` |' for path, digest in current_hashes.items()]
    parts += ['', '## 本次只读核对命令（报告文件已存在时工具拒绝覆盖）', '```bash',
              'PYTHONDONTWRITEBYTECODE=1 python newtests/tools/test_round71_dual_identity_report.py',
              'PYTHONDONTWRITEBYTECODE=1 python newtests/tools/round71_dual_identity_evidence_report.py', '```',
              f'JSON 明细：`{output}`。只读后处理工具退出0表示报告生成成功，不表示身份验收通过。', '']
    write_new(output, json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
    write_new(report, '\n'.join(parts))
    print(json.dumps({'report': str(report), 'evidence': str(output), 'additional_client_launches': 0,
                      'overall_acceptance': False, 'identity_verdict': verdict,
                      'Job0': r['Job0'], 'current_candidate_residual_count': len(remaining),
                      'protected_not_in_owned_job': True}, ensure_ascii=False))


if __name__ == '__main__':
    main()
