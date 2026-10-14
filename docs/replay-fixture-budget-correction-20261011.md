# 完整重放夹具预算修正（只放宽测试预算）

## 结果与边界

- `tests/match_replay_test.gd` 仅两处修改：共享 deadline `170000 → 600000` 毫秒；对应 watchdog 断言文案 `170-second → 600-second`。不重置 deadline、不取消 maintenance、不改轮询、种子8181、2000步guard、自然终局、两次恢复和原10条断言。
- 本次未修改生产GD、前端、业务配置或生产超时。生产 `scripts/match/match_replay.gd` SHA256 保持 `851f77f939974d3f51eea51b70feda9c2593c0ee700e265bb4e090b78419d175`。
- 完整专项复跑：141动作、142条记录、两次完整恢复，CHECK=10、failures=[]、Godot exit=0、ERROR/SCRIPT ERROR=0、Job0=true；source_drift=[]、frozen_drift=[]。隔离generated树已删除，原日志保留。
- **本次仅在夹具上放宽正确性预算，不是性能优化。170秒性能门仍未通过；其他RED、窗口、LAN、发行和生产管理保存链未验收。**

## 实测与声明依据

先在独立E盘副本内将deadline临时设600秒（原仓库未改），保持其余重放代码和断言，完整实测Godot进程耗时 **369.558秒**。该次业务exit0、10 CHECK全绿、ERROR0、Job0；冻结本身未漂移。但运行期间其他写者改变了4个源文件，顶层执行器诚实返回exit1，因此本次只用其冻结副本耗时作为预算依据，不作为当前工作树通过。

预算公式：`ceil(369.558 × 1.5 / 60) × 60 = 600秒`。明确留50%运行余量，再向上整分钟；外部执行器watchdog设660秒（内预算+60秒启动/退出余量）。夹具从170到600秒，**增加430秒，约3.529倍**；外部从600到660秒，增加60秒。

随后源夹具正式两行修改后，重新冻结当前工作树、真实冷导入并重跑，完整业务进程实测 **383.427秒**。原有trace的setup/end绝对ticks为133993、263042、263818、381033毫秒；两次恢复都推进至index141自然终局。trace是checkpoint时刻，不冒充精确restore函数入口/出口耗时。总耗时使用执行器monotonic观测（包括进程启动、退出/Job归零检测），不是state_hash累计时间。

## 六条原红逐条核对

最终原始 `evidence/match_replay-1.stdout.log`：

```text
CHECK replay succeeds 0:  true
CHECK replay complete state agrees 0 true
CHECK replay restores game end true
CHECK replay succeeds 1:  true
CHECK replay complete state agrees 1 true
CHECK replay restores game end true
REPLAY actions=141
RESULT checks=10 failures=[]
```

全部转绿；未吞掉任何“维护回调取消了存档操作”或错误。原10条CHECK数量与RESULT一致。

## 文件与SHA256

| 文件 | SHA256 |
|---|---|
| `tests/match_replay_test.gd` 修改后 | `01b339c7aea542d280637b91b7e15a2293262699daeb6d5de14bfe6bffaa65be` |
| 同文件修改前 | `c65919215e6ab6cba7d65b0689c59a776278949e6056eab4ffc800a8c9615253` |
| `E:/scratch/run_match_replay_measure.py` 最终执行脚本 | `62e8b61a78af77412d08129f2f329d55156376f821febce110c5673896c318bf` |
| `E:/scratch/finalize_match_replay_budget.py` 原证据收尾脚本 | `c2720e327c73c45a48121642a8d073e2dfd2e3ad32aed4e24d256bd089b46d45` |

仓库另新增本报告。runner均在E scratch，不修改通用执行器。执行脚本复用既有Windows Job和隔离复制流程；为当前新增生产依赖只显式include `PayMagic.gd`，未写该文件。副本project的开发VCS、插件、main_scene隔离转换沿用旧runner，不改源project；正式autoload和threading保留。最终验证没有GDScript副本转换。

本文件不在HEAD，`git diff`不能显示两行差异；已与原证据保留的完整字节（其sha等于修改前sha）做Python unified_diff，确认只有上述两行变化。

## 命令与证据

cwd：`E:/Projects/Godot/FateDominationGame-master`

```text
python -B E:/scratch/run_match_replay_measure.py
python -B E:/scratch/finalize_match_replay_budget.py
```

实际完整专项argv（原manifest保存精确Windows字符串）：

```text
E:/scratch/broadcast-headless-5bc5e8ea2bbf47108d5a6ebae227403f/isolated-4fbb8fd606c64d2cb9a7b1153bde658f/generated/Godot.exe --headless --fixed-fps 60 --path E:/scratch/broadcast-headless-5bc5e8ea2bbf47108d5a6ebae227403f/isolated-4fbb8fd606c64d2cb9a7b1153bde658f/generated/project --scene res://tests/match_replay_test.tscn
```

最终证据根：`E:/scratch/broadcast-headless-5bc5e8ea2bbf47108d5a6ebae227403f/isolated-4fbb8fd606c64d2cb9a7b1153bde658f/`
- `manifest.json`：实际probe/import/scene argv、退出码、耗时、所有Job进程ActiveProcesses=0、输入source_hashes/frozen_hashes。
- `budget-finalization.json`：读回原日志重新分析、10条逐条CHECK、exit0、ERROR0、Job0、source/frozen drift空、预算依据、清理、passed=true；收尾命令实际exit0。
- `evidence/match_replay-1.stdout.log`、`.stderr.log`：原业务日志，stderr空。
- `evidence/source/tests/match_replay_test.gd`：修改后夹具原字节归档。

测量证据根同父目录下 `isolated-0f38d86cee914b4c962afed079a3dcef/`。它的复制脚本沿用了旧runner，manifest `retry_scope`文案仍写170秒，**该文案过期且不是执行证据**：实际测量脚本副本deadline为600000、fixture frozen sha与source sha不同；本报告明确标为临时测量副本，不将其170秒文案引用为性能通过。

## 遇到的非业务问题（原证据保留）

1. 初次scratch脚本ROOT错误，读不到旧freeze清单，未启动Godot；修正为明确E路径。
2. 旧source清单哈希与当前已有` tactical_board_ui.tscn`不一致，freeze前拒绝，无Godot；改用当前源字节建立新哈希，不删除漂移门。
3. 初次测量业务全绿，但运行中他人改`all_operations.gd/EditMagic.gd/PlayAttack.gd/regular_play.gd`，顶层exit1；只当实测值，不冒充当前验收。
4. 正式第一次复跑cold import报`PayMagic not declared`，首因是旧隔离include清单没含刚新增`PayMagic.gd`，**不是超时**。补显式依赖，不改生产，另次真实cold import错误0。
5. 最终完整运行已业务exit0且Job0，工具前台420秒上限在runner清理阶段截断。manifest已落盘上述完整结果，未重跑业务或篡改旧manifest；确认执行脚本进程已不存在，收尾脚本用原所有权回执/Job0检查删除generated，独立`budget-finalization.json`读回确认passed=true、generated不存在。旧manifest仍保留not_started/passed=false，最终收尾回执才是完整验收结果。

PID17120/28100未操作；引擎D盘只读复制到E执行，生成、副本、APPDATA/LOCALAPPDATA/TEMP均在本次E隔离树。
