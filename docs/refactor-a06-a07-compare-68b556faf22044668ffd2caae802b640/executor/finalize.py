import sys
sys.dont_write_bytecode=True
import os,re,json,hashlib,shutil,datetime,importlib.util
from pathlib import Path
P=Path('E:/Projects/Godot/FateDominationGame-master'); owner=Path('E:/scratch/isolated-68b556faf22044668ffd2caae802b640'); gen=owner/'generated'; ev=owner/'evidence'
spec=importlib.util.spec_from_file_location('isolated_runner',P/'tools/run_isolated_godot_test.py'); r=importlib.util.module_from_spec(spec); spec.loader.exec_module(r)
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,v): p.write_text(json.dumps(v,ensure_ascii=False,indent=2),encoding='utf-8')
m=json.loads((owner/'manifest.json').read_text(encoding='utf-8'))
if not m['all_job0'] or not m['mutation']['restored_original_bytes']: raise RuntimeError('Job0 or restore not proven')
# Read exact archived process/log targets, check RESULT and CHECK counts again.
snapshots=[owner/'snapshot1/manifest.json',owner/'snapshot2/manifest.json',owner/'manifest.json']
verification=[]
for mp in snapshots:
    sm=json.loads(mp.read_text(encoding='utf-8')); logroot=mp.parent if mp.parent!=owner else ev
    if not sm['all_job0']: raise RuntimeError('prior Job not zero')
    for s in sm['suites']:
        out=(logroot/(s['label']+'.stdout.log')).read_bytes().decode('utf-8'); err=(logroot/(s['label']+'.stderr.log')).read_bytes().decode('utf-8')
        a=r.analyze(out,err,s['exit_code'])
        observed=len([x for x in out.splitlines() if x.startswith('CHECK ')])
        if a['result']['checks']!=observed: raise RuntimeError('CHECK count mismatch')
        if s['label']=='A07-empty-lock-negative':
            if s['exit_code']!=1 or a['result']['failures']!=['locked target rejection text','locked origin rejection text'] or 'engine_error' in a['reasons']: raise RuntimeError('negative mismatch')
        elif not a['passed']: raise RuntimeError('compare not passed')
        verification.append({'snapshot':mp.parent.name,'label':s['label'],'checks':observed,'exit':s['exit_code'],'result':a['result']})
    for log in sm['logs']:
        if digest(logroot/log['path'])!=log['sha256']: raise RuntimeError('log drift '+str(log))
changes=[{'path':n,'tested_sha256':h,'current_sha256':digest(P/n)} for n,h in m['source_hashes'].items() if digest(P/n)!=h]
frozen_drift=[n for n,h in m['source_hashes'].items() if n!='project.godot' and digest(gen/'project'/n)!=h]
if frozen_drift: raise RuntimeError('frozen restored copy drift '+str(frozen_drift))
if digest(gen/'project/project.godot')!=m['config_transform']['isolated_sha256']: raise RuntimeError('isolated config drift')
for n in ['docs/refactoring-golden/text.json','docs/refactoring-golden/areas.json']:
    if digest(P/n)!=m['source_hashes'][n] or digest(gen/'project'/n)!=m['source_hashes'][n]: raise RuntimeError('golden changed')
m['final_readback']={'timestamp':datetime.datetime.now().astimezone().isoformat(),'current_repository_drift':changes,'frozen_restored_input_drift':frozen_drift,'all_archived_checks_verified':verification,'claims':{'tested_frozen_A06_compare':True,'tested_frozen_A07_compare':True,'A07_negative_lock_red_and_restore':True,'final_live_tree_same_as_tested_freeze':not changes,'clean_cold_import':False}}
folder=P/'docs/refactor-a06-a07-compare-68b556faf22044668ffd2caae802b640'; folder.mkdir(exist_ok=False)
for snap in ('snapshot1','snapshot2'):
    shutil.copytree(owner/snap,folder/snap)
shutil.copytree(ev,folder/'evidence')
runner_archive=folder/'executor'; runner_archive.mkdir()
for n in ('run.py','resume.py','refreeze.py','finalize.py'): shutil.copyfile(Path('E:/scratch/a06-a07-compare-executor')/n,runner_archive/n)
save(owner/'manifest.json',m)
# Archive owner manifest before cleanup; only this exact UUID-owned generated tree is removed.
r.delete_owned(gen,owner)
m['cleanup']='generated_removed'; m['generated_exists_after_cleanup']=gen.exists()
save(owner/'manifest.json',m); save(folder/'manifest.json',m)
important=['tests/refactor_text_golden_test.gd','tests/refactor_text_golden_test.tscn','tests/refactor_area_golden_test.gd','tests/refactor_area_golden_test.tscn','docs/refactoring-golden/text.json','docs/refactoring-golden/areas.json','scripts/game_scene/tactical_board_ui.gd','scripts/system/area_action_rules.gd','scripts/match/match_driver.gd','scripts/system/global/effect_manager.gd','scripts/net/ui/v2_view_presenter.gd','project.godot']
lines=['# A06 / A07 compare 与 A07 负向证据','', '## 结论','', '- 已证实：最后测试冻结的 A06 compare 11/11、A07 compare 25/25 全绿；正常 compare 无 golden 差异。', '- 已证实：同一冻结中把 AreaActionRules.move_lock_reason 函数体仅改为 return ""，A07 为 exit 1、22 CHECK、两条锁拒绝断言失败；无引擎 ERROR。副本恢复原字节和 SHA 后 A07 compare 再次 25/25 全绿。', '- 未证实：测试期间其他并行写入者改变了源码，所以最后测试冻结不等于交付时活体仓库终态；不得据此把整个当前终态或矩阵无条件标成通过。见“源码并行漂移”。', '- 未证实：干净冷导入/全量/窗口/真人输入/发行门；本轮仅指定两个 headless golden 专项。', '- 未使用 capture，未改任何测试断言、生产仓库或 golden；新建本报告及证据目录。日志中的 godot_ai game_helper “registered mcp capture”是既有运行时插件启动信息，不是 golden capture 分支。', '', '## 环境与冻结','', '- Godot: 4.7.2.stable.official.ed1daf0bf；仅执行独占 E 盘非 console 引擎副本。', '- 源目录：`'+str(P)+'`', '- 唯一隔离根：`'+str(owner)+'`；generated 已在 Job0、日志解锁、证据归档后删除。', '- 实际 user:// 主/派生探针落于本 UUID 的 generated/appdata/FateDomination，实读回执、worker exit 0；首轮 probe 证据见 snapshot1。', '- 每进程执行器看门狗 600s；本次无执行器超时。原测试自己的 180s 约束/断言保持原字节且均通过。', '- 子进程 APPDATA/LOCALAPPDATA/TEMP/TMP/TMPDIR 显式指向 E 盘生成子树；未修改全局环境。PID 17120/28100 未被纳入或操作。', '- 副本只有 project.godot 的编辑器设置最小转换：关闭 VCS 自动启动和编辑器 MCP 插件；application/autoload/threading 与测试逻辑未改。原工程 config SHA 与副本转换 SHA 分列于 manifest。', '- 源码清单包含 '+str(len(m['source_hashes']))+' 个显式依赖，完整逐文件 SHA 在 evidence/source-before.json 与 manifest.json；非硬链接副本。', '- 最后冻结源码 SHA256：`'+m['source_fingerprint']+'`', '- 编码：按 path->sha 的字典以 json.dumps(sort_keys=True,separators=(",",":")) 序列化为 UTF-8，再 SHA256。该值标识测试冻结，不是 Git 提交。', '- 引擎 SHA256：`'+m['engine_sha256']+'`', '', '## 两个原套件与真实命令','']
for s in m['suites']:
    proc=next(x for x in m['processes'] if x['label']==s['label'])
    lines.extend(['### '+s['label'],'', '- 原套件：`'+s['suite']+'`','- 命令：`'+__import__('subprocess').list2cmdline(s['command'])+'`','- 结果：'+s['status']+'；exit='+str(s['exit_code'])+'；CHECK='+str(len(s['checks']))+'；ERROR='+str(len(s['errors']))+'；Job ActiveProcesses='+str(proc['active_owned_processes'])+'；日志句柄已释放。','- RESULT：`'+s['result_lines'][0]+'`','- 原 stdout/stderr：`evidence/'+s['label']+'.stdout.log` / `evidence/'+s['label']+'.stderr.log`','', '```text',*s['checks'],'```',''])
lines.extend(['## 差异逐项判定','', '| 情形 | 证据 | 判定 |','|---|---|---|','| A06 正常 compare | `golden matches exactly true`，11 CHECK，exit 0 | 无差异；没有批准差异/夹具漂移/产品缺陷需要归类 |','| A07 正常 compare | `baseline equals actual queries: true`，25 CHECK，exit 0 | 无差异；完整局 steps=272、round=11、game_end=1；548 样本、15344 查询行 |','| A07 负向：锁定目标拒绝文案 | 原 tests/refactor_area_golden_test.gd:99；`CHECK locked target rejection text false` | 副本中故意注入的产品规则缺陷，成功被原断言捕获；不是批准差异，不是夹具漂移，不表示未注入的生产存在缺陷 |','| A07 负向：锁定出发地拒绝文案 | 原 tests/refactor_area_golden_test.gd:105；`CHECK locked origin rejection text false` | 同上；自然终局及真实 area_locked 识别断言仍绿 |','', '负向运行在 locked_fixtures 后因两条原断言失败提前 finish，未走最终 golden 比较（22 而非 25 CHECK）。这是现有测试的失败关闭路径，并非删断言；负向不冒称产生了完整 GOLDEN_DIFF。stdout 未打印失败值，不推造实际文本值。恢复运行重新执行了完整 golden 比较。', '', '## 注入与恢复字节证明','', '- 改动唯一位置：副本 `scripts/system/area_action_rules.gd` 的 `static func move_lock_reason(player_id: int, target_area: BaseMapArea) -> String` 函数体；签名、调用方、golden、断言均未改。现有 tactical_board_ui.gd:3151–3152 转发到此函数。', '- 注入前 SHA：`'+m['mutation']['before_sha256']+'`', '- 注入后 SHA：`'+m['mutation']['mutated_sha256']+'`', '- 立即 finally 恢复后 SHA：`'+m['mutation']['restored_sha256']+'`', '- 原字节比较：true；恢复副本全部原始输入 SHA 无漂移（project.godot 记录的编辑器设置转换除外）。仓库 area_action_rules.gd 注入前后 SHA 相同。', '- 原始函数文件备份：`evidence/area_action_rules.original.gd`。', '', '## golden 与关键源码 SHA256','', '| 文件 | 测试冻结 SHA256 |','|---|---|'])
for n in important: lines.append('| `'+n+'` | `'+m['source_hashes'][n]+'` |')
lines.extend(['', '两份 golden 在原仓库和隔离副本的运行后 SHA 均等于运行前 SHA。', '', '## 源码并行漂移','', '保留三轮独立快照，不拼接为同一冻结通过：snapshot1 首轮后 lobby_session.gd 漂移；snapshot2 重冻结后 effect_manager.gd 漂移；最后冻结含其更新，运行后 v2_view_presenter.gd 又发生并行写入。每轮四个运行的原日志、源码清单、manifest 均保留，全部实际 Job0。', '', '| 路径 | 最后已测试 SHA | 报告生成时活体 SHA |','|---|---|---|'])
for d in changes: lines.append('| `'+d['path']+'` | `'+d['tested_sha256']+'` | `'+d['current_sha256']+'` |')
lines.extend(['', '因此“两个指定测试在标明 SHA 的冻结上通过”已证实；“测试后的活体终态也通过”未证实。需要主代理停止相关生产写入后再冻结时，不能把本报告的旧 SHA 冒充该新终态。', '', '## 实际遇到的问题','', '- 首轮干净冷导入 exit 0 但存在 CursorReplace 三张 PNG preload 的真实 SCRIPT ERROR（autoload 先于图像资源导入）；完整原 ERROR 在 snapshot1/import.stderr.log。此首轮不判干净导入通过。', '- 原资源完成真实导入后，同一冻结第二次真实 import exit 0、无 ERROR；最后更新冻结的 import 亦 exit 0、无 ERROR。没有复制 .godot 缓存，没有忽略 ERROR，没有修改 autoload 或测试断言。', '- 上述属于本次冷导入准备顺序问题，不是 golden 值差异；本任务的套件 compare / 负向 / 恢复阶段全部无 ERROR。不据暖导入宣称冷启动发行门通过。', '- 并行源码漂移已经精确记录，未由本执行器修改、回滚或覆盖仓库文件。', '', '## 完整证据与清理','', '- 当前：manifest.json、evidence/source-before.json、四次 stdout/stderr、import stdout/stderr、恢复原始函数文件。', '- 旧冻结：snapshot1/、snapshot2/；真实主/派生 user:// 探针、首轮冷导入 ERROR 原样保留。', '- 执行配方：executor/run.py、resume.py、refreeze.py、finalize.py。', '- 所有自有 Job ActiveProcesses=0 后，按 owner run_id/generated/processes 回执与无 reparse-point 扫描删除本 UUID generated；正式仓库、正式存档、其他 scratch 与 protected PID 未作为清理目标。'])
(folder/'report.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
receipts=[{'path':q.relative_to(folder).as_posix(),'sha256':digest(q),'bytes':q.stat().st_size} for q in sorted(folder.rglob('*')) if q.is_file()]
save(folder/'artifact-sha256.json',receipts)
print(json.dumps({'report':str(folder/'report.md'),'manifest':str(folder/'manifest.json'),'fingerprint':m['source_fingerprint'],'current_repository_drift':changes,'verification':verification,'cleanup':m['cleanup'],'generated_exists':gen.exists(),'artifact_count':len(receipts)},ensure_ascii=False,indent=2))
