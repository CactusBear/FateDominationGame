# match_view：完整实测、有限预算与真实 RESULT

## 结论

- 单套件隔离实测完整完成 **35.084 秒**；按显式预算重跑完整完成 **35.669 秒**，真实 `RESULT checks=226 failures=[]`、Godot exit0、ERROR0、Job0，Python launcher 也 exit0。自然终局断言为 true。
- 本机高负载：实测场景 CPU 平均 **92.28%**（72.66–100%，7 个五秒采样）；重跑平均 **95.55%**（91.33–98.70%，8 个采样）；12 逻辑 CPU，内存占用最高分别 48%/46%。负载来自 GetSystemTimes 原始 idle/kernel/user 差值，完整样本在 manifest。
- 不把旧轮 602.768 秒误写成“完整耗时”。旧冻结没有 RESULT，仍是历史不可判定；本轮冻结与旧冻结有 7 个输入不同，**不能据新样本宣称旧冻结 35 秒能完成，也不能宣称已定位旧轮推进变长的产品首因**。本轮未出现新红或缺 RESULT。
- 本次只改有限测试预算、预算消费者与文档；未改生产/前端/golden/任何业务断言、种子、3000 步上限或自然终局条件。

## 实际命令与计时口径

执行器由 `E:/Caches/Hermes/cache/scratch/match-view-budget/run_measurement.py` 复用现有 `tools/run_isolated_godot_test.py` 的真实 Job 所有权、进程执行、物理路径探针及 RESULT 解析。所有 TMPDIR/TEMP/TMP 指向上述 E scratch；每次 APPDATA/LOCALAPPDATA 为独占 generated 子树。主/派生 user:// 探针、import 均 exit0、无 ERROR、Job0。没有操作保护 PID 17120/28100。

```bash
export TMPDIR='E:/Caches/Hermes/cache/scratch/match-view-budget' TEMP='E:/Caches/Hermes/cache/scratch/match-view-budget' TMP='E:/Caches/Hermes/cache/scratch/match-view-budget'
python -B E:/Caches/Hermes/cache/scratch/match-view-budget/run_measurement.py --phase measure --watchdog-seconds 7200 --fixture-seconds 3600
python -B E:/Caches/Hermes/cache/scratch/match-view-budget/run_measurement.py --phase verify --watchdog-seconds 1200 --fixture-seconds 120 --budget-file E:/Projects/Godot/FateDominationGame-master/tools/diagnostics/match_view_budget.json --frozen-source E:/Caches/Hermes/cache/scratch/match-view-budget/isolated-d8f35d7ad8474c0ba8cd3707d8cb71e8/generated/project
```

第一轮真实引擎命令：
```text
E:\scratch\round51-engine\Godot_v4.7.2-stable_win64.exe --headless --fixed-fps 60 --path E:\Caches\Hermes\cache\scratch\match-view-budget\isolated-d8f35d7ad8474c0ba8cd3707d8cb71e8\generated\project --scene res://tests/match_view_test.tscn
```
重跑同一 argv，仅 `--path` 换为 `isolated-ced6208cd6b94e2db4e0de951cefb60b\generated\project`。

35.084/35.669 秒是执行器 monotonic 的场景进程启动到退出及 Job0 回收观测时间，包含监控/调度观测间隔，不含冻结复制和 import；不是脚本单函数耗时。实测 import 38.994 秒、probe 1.507 秒；重跑 import 51.710 秒、probe 1.741 秒。日志句柄释放另行确认。测量前只在隔离夹具把计时值放到有限 3600 秒，外部上限有限 7200 秒；不是无限等待。

## 按证据声明预算

正式声明：`tools/diagnostics/match_view_budget.json`。

|预算|原值|新值|放宽量|依据|
|---|---:|---:|---:|---|
|外部 wall-clock 看门狗|600s|1200s|+600s，2 倍|`60*ceil(2*max(35.084,600)/60)`：完整实测值加 2 倍余量，同时不丢弃旧轮 600s 已耗尽的截断下界|
|Godot 夹具 timer|90s|120s|+30s，4/3 倍|`max(60*ceil(2*35.084/60),3000*2/60+20)=120`：原 3000 步、每步两帧，在 fixed-fps60 下最多 100 秒循环帧时间，另留 20 秒|

Godot timer 在 fixed-fps 下是模拟时间；外部看门狗是墙钟时间，两者不能直接互换。新完整样本明显短于原 600 秒，**本轮没有证明外部放宽是新冻结通过的必要条件**；1200 秒是兼顾历史截断的有限保守安全上限，不是典型耗时，不是性能优化。

`tests/match_view_test.gd:5` 只改 `create_timer(90.0)` 为 `create_timer(120.0)`；`:6-7` 的 watchdog false 断言及 finish 完全保留。与旧证据逐字核对，其他脚本文本、`:74` 的有限循环、`:78` 的每步断言、`:81` 的自然终局断言均未变。

旧 `fee-label-verification/run.py:17-27` 针对 match_view 读取同一声明，缺失/非法直接拒绝；其他套件仍是 600 秒，基础预算不变。实际重跑执行器检查传入数值必须等于 JSON 声明；不会回退默认值。原 launcher 的预算派发函数已单独执行验证 match_view=1200、其他=600；未因此再运行其他套件。

## 真实结果表

|运行|完整秒数|CHECK|false|RESULT|Godot exit|ERROR|Job active|launcher exit|
|---|---:|---:|---:|---|---:|---:|---:|---:|
|旧截断历史|无完整值（回收 602.768）|1209|0|缺失|125|0|0|0（旧异常分支；不代表通过）|
|本轮隔离实测|35.084|224|0|`RESULT checks=224 failures=[]`|0|0|0|0|
|按声明重跑|35.669|226|0|`RESULT checks=226 failures=[]`|0|0|0|0|

两轮真实末条业务检查均为：
```text
CHECK real AI match reaches end through view loopback true
```
实测 stdout:228 / 重跑 stdout:230 是各自唯一 RESULT；分析器核对 CHECK 数量一致、空 failures、exit0，无引擎/脚本错误。完整日志不可互相拼接。

证据根 `E:/Caches/Hermes/cache/scratch/match-view-budget/`：
- 实测：`isolated-d8f35d7ad8474c0ba8cd3707d8cb71e8/manifest.json`。
- 重跑：`isolated-ced6208cd6b94e2db4e0de951cefb60b/manifest.json`。
- 两轮 `evidence/match_view_test.stdout.log`、`.stderr.log` 与 `finalization.json`；原 manifest 不覆写，清理另存回执。
- 聚合：`aggregate.json`；历史计数对照：`count-audit.json`。
- 已在所有 owned Job0、日志句柄释放后按 owner/run_id 精确删除两轮唯一 generated 子树；日志、manifest、最小冻结夹具留存。上面 `--frozen-source` 命令是已执行历史命令，不再指向现存 generated。

## 为什么 ~225 变成 1209

不是套件扩写，也不是计数口径变化；是相同动态断言执行的 AI 循环步数不同。

- `tests/match_journal_test.gd:10-14` 每次 check 调用计一次并打印一条 CHECK；`:16-18` RESULT 使用同一个 checks。解析器不按标签去重。
- `tests/match_view_test.gd:73-80` 原本就会每循环一步打印 `loopback step N`，上限 3000；`:81` 另计一次自然终局检查。
- 历史 `reports/refactoring/round10-E02-match_view_test.log:453,455,457`：末步 134、终局 true、RESULT225；**90 固定前置 +134 循环 +1 终局=225**。
- 旧截断日志 `isolated-557128e9f8714a01a68f224b5f8d72c5/evidence/match_view_test.stdout.log:1212`：末步1119、未到终局；**90 固定前置 +1119 循环=1209**。
- 程序 Counter 对比两个日志的全部前置标签多重集完全相同，无新增/删除；当前夹具和旧保存夹具在修改预算前 SHA 相同。
- 本轮224=90+133+1，重跑226=90+135+1，再次证明 CHECK 总数随实际对局步数变化，不能设置固定225或1209作为必过数量。为什么旧冻结对局比新冻结长，单凭这些 CHECK 不足以定位；不得硬称随机或性能导致。

## 冻结与未验边界

- 两轮共有冻结输入只在夹具 timer 不同；生产脚本/数据共有输入 SHA 相同。重跑额外带入初次 import 生成的 5 个 `.uid` 元数据（完整清单在 aggregate）；不能称全文件集合逐字完全一致。两轮场景运行期间冻结漂移均为空。
- 测量过程中原工作树 `server_console_channel.gd`、`regular_play.gd` 被其他写者修改；没有混入冻结。本轮源快照相对旧轮有 7 文件差异：上述两文件、`server_room_manager.gd`、`effect_manager.gd`、`game_progress.gd`、`time_point_checker.gd`、`PlaySkill.gd`。不是本代理改动。
- 验收只绑定本轮固定生产输入，不能外推最新工作树/旧完整冻结/发行包；没有补跑 refactor_text_golden、reported_ui 或全量回归。
- 未验真实窗口、鼠标、跨机/跨网；独占空应用缓存及重建 .godot 不等于 OS 冷缓存；有限高负载样本不保证任意负载或永久 I/O 阻塞下完成。

## 改动文件 SHA256

|文件|SHA256|
|---|---|
|`tests/match_view_test.gd`|`ec654b2099433cf98e1166ddf35d4afe3bc4216e588883b110d697b7a126b5fe`|
|`tools/diagnostics/match_view_budget.json`（新增）|`aa524a075bd87bfb723b132d7a6af93ac6fef7443bf8491e086f2b968a610a6b`|
|`E:/Caches/Hermes/cache/scratch/fee-label-verification/run.py`|`bd52694cae35e1e241a55840ffd097cdd3b1b9e2a752b1f96d32d2feafdfd0a2`|
|`E:/Caches/Hermes/cache/scratch/match-view-budget/run_measurement.py`（新增）|`b7fe926c308660de3c0322533116845779f67abba8b464f47713da092053641a`|

重跑冻结夹具 SHA `5b33d7ed505f4c4a6697566945e72312c16da6c300d132aa8112cc75c4ca3215`：Python 写隔离文件使用 CRLF，源码为 LF；UTF-8 解码、换行规范化后全文相同，并非断言漂移。测量冻结临时3600秒夹具 SHA `ffa2f76bd34ec1ed34f632bc3bf4399d620cce31f2604b59e7012b475481cfa2`。

本报告、旧报告追加链接及上述证据文件的最终摘要统一存 `E:/Caches/Hermes/cache/scratch/match-view-budget/deliverable-sha256.json`，避免报告自引用 hash。
