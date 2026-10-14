# Round47：五套测试真正减少私有消费者

## 结果

- 只改 `command_spell_test.gd`、`ask_player_option_test.gd`、`requirement_null_test.gd`、`session_restart_test.gd`、`debug_console_pause_test.gd`；生产、source、gate 全只读，无新增公开 API 壳、无反射取私有字段。
- 同一最终冻结五套完整 headless GREEN：61 / 16 / 14 / 30 / 15 CHECK，共 **136**；每套 exit 0、唯一 RESULT、空 failures、真实 CHECK 数量一致、无 SCRIPT ERROR/ERROR。独立观察器专项另有 7 CHECK。
- **11 项有效夹具变异**各自完整 RED exit 1 → 恢复原字节 → 同套 GREEN；最后再次跑完整五套和观察器。所有有效 RED 没有脚本错误，失败保留在最终 RESULT。
- 最终冻结 51 条进程记录均 `exited=true`、`active_owned_processes=0`、日志句柄释放。OS `Get-CimInstance Win32_Process` 精确过滤本轮 E 冻结引擎路径，结果 `LIVE_OWNED_PROCESS_COUNT=0`。不按进程名杀任何其他实例。
- 源码与最终冻结逐文件 SHA256 无漂移；变异 harness 验证冻结生产文件没有变化。没有自行 stage/commit。

## 改动与实际语义

| 消费者 | 不再读取的内部观测 | 实际公开验证 |
|---|---|---|
| command_spell 来源 | `_effect_source_name` 两次 | 延迟对象保留原 `from` 身份；真实 BattleResolver 获胜、延迟 edit_score 后，effect facts 的非空 source_name 与原令咒一致；保留到 DAY_END 的到期与后续不加分覆盖 |
| command_spell 公告 | `_announce_effect` / `_flush_announcements` | 用 LoadHelper 保活真实 edit_score、登记效果、加入池、run_pipeline；战果确实 +1，公开广播 ticket 的 player_id=-1，非触发者实际 pop 得到御主/能力文案，不重复来源，第二次消费为空 |
| command_spell 排队 | `_queued_time_point_batches` 两处 | pending 期间 DAY_END、DAY_START 两个时点不执行、不推进 batch；提交后分别 +1/+10、各一次、按 FIFO，idle pipeline 不重放；完整 TRACE/FACTS 留证 |
| ask 中途选择 | `_paused_runs` | 选择及拒绝的完整操作序列、共享变量、父尾结果、子效果移除；idle pipeline 不多跑，重复拒绝不续行；不 reset 立即再开选择，验证新父变量/尾部独立 |
| null requirement | `_option_activation_requirements_met` | `is_option_available` 的 silent 查询保留原三项断言；真实手动选择提交、无 usage/activation、临时变量和当前 activating_eff 恢复；随后新请求合法分支；查询 trace 全部真实 null，最终只记合法选项 |
| session | `_session_serial` 两处 | 真正 end_round 挂在 DAY_END 选择；菜单结束使旧协程退出，重开后 round/trace 不被旧尾推进，旧选择不遗留；原地图/资源/模板/再开局覆盖全部保留 |
| console pause | `_wait_round_choices` | 合法末回合调用公开 end_round；暂停期间协程不完成、未终局，关 console 后才完成并终局；原 timer/tween/通知/debug 编辑/重复初始化/已有暂停恢复覆盖保留 |

必须按生产现有语义而非测试想象断言：

1. null requirement 的提交失败**按放弃处理**，`submit_option_choice` 返回 true 表示答复已处理，不表示发动成功。检查无 option_used/effect、零用量且待选清理，而非要求返回 false 并保留询问。
2. 排队时点在接受选择后的令咒支付时点进入管线，早于令咒分支 edit_magic 完成。因此验证“接受前不跑、接受后 FIFO 各一次”，不倒改生产成“令咒先完成”。
3. 公开公告是共享、消费式广播票据，不能让多个消费者重复 pop 同一条来证明广播。
4. script static 观察器不属于实例字段，效果描述符没有 Callable 指回测试 Node。专项真实预算暂停、公开 skip，规则分数从正数回滚为 0；回滚前故意 CHECK false 的副本仍在最终 RESULT 保留失败并 exit 1。

## 精确退休清单：仅 main 唯一 gate owner 操作

以下是亲读当前 `tools/check_layer_deps.py` 提取的原 ExceptionSite。规则均为 `private`；行号仅旧位置提示，以 path/target/anchor 的多重集合为准。**共 11 条许可，10 个不同锚点**。两个来源条目完全相同，不要只删一个。

| 文件 | target | 原词法锚点 | 旧行 | 次数 |
|---|---|---|---:|---:|
| tests/ask_player_option_test.gd | EffectManager._paused_runs | `check(EffectManager._paused_runs.is_empty(), "no paused run left behind")` | 78 | 1 |
| tests/command_spell_test.gd | EffectManager._effect_source_name | `check(scheduled != null and EffectManager._effect_source_name(scheduled) == EffectManager._effect_source_name(effect),` | 112 | 2 |
| tests/command_spell_test.gd | EffectManager._announce_effect | `EffectManager._announce_effect(effect)` | 130 | 1 |
| tests/command_spell_test.gd | EffectManager._flush_announcements | `EffectManager._flush_announcements()` | 131 | 1 |
| tests/command_spell_test.gd | EffectManager._queued_time_point_batches | `check(EffectManager.time_point_id == batch_before and EffectManager._queued_time_point_batches.size() == 1,` | 143 | 1 |
| tests/command_spell_test.gd | EffectManager._queued_time_point_batches | `check(EffectManager.waiting_effect == null and EffectManager._queued_time_point_batches.is_empty(),` | 146 | 1 |
| tests/debug_console_pause_test.gd | GameProgress._wait_round_choices | `await GameProgress._wait_round_choices()` | 8 | 1 |
| tests/requirement_null_test.gd | EffectManager._option_activation_requirements_met | `check(not EffectManager._option_activation_requirements_met(effect, {0: 1}, true), "missing query result rejects requirement")` | 7 | 1 |
| tests/session_restart_test.gd | GameProgress._session_serial | `var old_serial: int = GameProgress._session_serial` | 52 | 1 |
| tests/session_restart_test.gd | GameProgress._session_serial | `check(GameProgress._session_serial == old_serial + 1, "session serial advanced")` | 71 | 1 |

机器清单 `summary.json.retire_sites_with_duplicates` 保留重复条目。本子任务未执行全树 gate、未删许可、未扩 allowlist；main 必须退休后完整 gate 核验。五套指定的这些 EffectManager/GameProgress 私有观测均已真实消失，但**不宣称整个仓库私有调用清零**。既有 UI 私有驱动、GameStart 状态、卡牌模型字段仍在原测试职责内；未跨范围清理，也未增加豁免。

## RED/GREEN 与证据

有效变异名：`source-settlement`、`source-expiry`、`announcement-pipeline`、`announcement-broadcast`、`queued-missing`、`queued-replay`、`ask-tail`、`null-query`、`session-stale-tail`、`pause-missing-await`、`observer-rollback-false`。

这是**测试夹具/消费者敏感性验证，不是生产代码突变测试**。所有变异只写 E 独占副本测试文件；生产全只读。`valid-mutations.json` 保存精确替换、mutant SHA、恢复 SHA；`execution-manifest.json` 保存实际 argv/exit/PID/预算/Job 活动数；原始 stdout/stderr 保留完整 TRACE、FACTS、CHECK、RESULT 并逐份哈希。

- 仓库归档：`reports/refactoring/round47-public-test-consumers/summary.json`、`execution-manifest.json`、`valid-mutations.json`、`evidence/*.log`。
- 最终 E 所有权目录：`E:/scratch/round47-public-consumers-56be7066603e4bfe86b17ff57ec140e2/`。
- 最后完整执行标签：`retry1-final-selected-green`。
- 实际业务命令形状：`<独占E>/generated/Godot.exe --headless --rendering-method gl_compatibility --path <独占E>/generated/project --fixed-fps 60 --scene res://tests/<suite>_test.tscn`。
- 重建冻结：`python -B tests/round47_public_test_consumers_runner.py --prepare --stage <新标签> --import-project`。默认恰好五套；观察器另加 `--suite round47_public_test_observer`（显式 suite 会替代默认列表）。
- 负向：`python -B tests/round47_public_test_mutations.py --owner <本轮独占根> --tag <新标签前缀>`。
- 汇总归档实跑：`python -B tests/round47_public_test_report.py`，exit 0。

APPDATA/LOCALAPPDATA/TEMP/TMP/TMPDIR 仅对子进程设置在 E 所有权目录。每套真实 OS PID 和 user_data 回执由 runner核对，实际物理 user:// 为该目录的 `generated/appdata/FateDomination`。冻结只使用既有 release transform 移除开发 helper/plugins/VCS，没有改生产配置、native 扩展或规则；不继承 `.godot`。最终冻结生成树保留供 main/sa0 接管，日志另已归档；不把“保留证据/副本”称作已删除临时文件。

## 已遇到问题与范围边界

- 原 ask 业务 exit 0，但 `failures=0` 不是数组，被严格汇总拒绝；现在统一 observer JSON RESULT。原始基线在 `E:/scratch/round47-public-consumers-623446cdb55a4ab5b1671543fac7267f/evidence/` 保留。
- 早期夹具缺完整效果声明、误用 edit_score 参数、错误广播消费假设及新 trace 表达式缺括号都实跑判红；错误日志未覆盖。两次测试异常超时由 180 秒自有 Job 回收，不算有效 RED。初始 runner 预算字段错误也未掩盖。
- 首个 null 非空变异用了 String，触发现有 `bool(String)` 脚本错误，严格拒绝；原日志 `evidence/red-null-query-requirement_null.stderr.log` 保留。改成引擎已支持的 BaseNumber(1) 后是自然 exit 1 的有效 RED。该 String 路径生产未修，是否应支持非数值对象结果由 main 单独审查；本轮不改变规则。
- 本轮仅 headless。debug 截图/window 分支原样保留，未运行、未宣称鼠标窗口验收；GUI 唯一执行者 sa0。
- `/tests/` 被 .gitignore 忽略：三个既有 `requirement_null/session_restart/debug_console_pause` 以及全部新增文件真实已修改/创建，但普通 git status 不列；main 若纳入交付必须明确检查，不能仅看 command_spell/ask 的 diff。不擅自 git add -f。

## 文件交付

修改上述五份 `.gd`；原五套 `.tscn` 无修改。新增：

- `tests/round47_public_test_observer.gd`
- `tests/round47_public_test_observer_test.gd` / `.tscn`
- `tests/round47_public_test_consumers_runner.py`
- `tests/round47_public_test_mutations.py`
- `tests/round47_public_test_report.py`
- 本文及上述自有 reports 归档。
