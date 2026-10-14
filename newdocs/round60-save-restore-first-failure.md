# Round60：save/restore 首失败诊断（各一次，停止）

## 结果与严格边界

|case|执行次数|父退出码|唯一 RESULT / 实际 CHECK|耗时|当前首失败|
|---|---:|---:|---|---:|---|
|server_shutdown_close_handoff_test|1|0|86 / 86，failures=[]|23.033s|本次 PASS，未复现 round58 新 recover 实例重试 writefail|
|net_server_gateway_restart_test|1|1|22 / 22，一条 false|217.747s|`actual authority and network clients reach declared match target`，发生于 **baseline，尚未执行 restart/recover/continuation**|

不是“两套绿”，也不是旧 restart52 同因重现。原 shutdown86 两条红、旧 restart52 client_error 和旧 60 秒性能 RED 全部保留。当前性能门未到达，绝不算 GREEN。没有增加 seed、动作、target、规则预算或运行次数；外层 shutdown180 / restart600，完整正确性仍440秒、原性能60秒，未改默认模拟15秒。没有执行98套。

真实执行命令：

```text
python -B tools/diagnostics/round60_save_restore_first_failure.py --approved-root E:/scratch
python -B tools/diagnostics/round60_save_restore_first_failure.py --approved-root E:/scratch --readback-existing E:/scratch/isolated-6316b4f97e0a4ccb937fa0bf8d835590/manifest.json
```

第二条只有原件读回，不启动/import/重跑 Godot。实际 exit0。专属 runner 不写或调用 fulltools/test_round29 执行集；只复用只读通用隔离/Job/parser 原语。

## 同冻结原件索引

根：`E:/scratch/isolated-6316b4f97e0a4ccb937fa0bf8d835590/`。

- `manifest.json` SHA256：`914946cb1eed96a3f1e61447f30e6fcf3f2b2f93cdf777b408dff8c6beff6acf`。原执行 manifest 未重写。
- 2097份明确冻结输入；source 指纹 `ab45124b27e45398ea7dff87c1dfdffe2e33e9639cf2dbdd00eada44523ddc7e`。两套共用一次 freeze/import，`source_drift=[] / frozen_drift=[]`。
- `round60-first-failure-readback.json` SHA256：`8cc018cbe81038bcbbd9104005fbce2fe73d599aec67d0e5553aac72e55c4f5b`，含准确 target、两个客户端首失败字段、绑定回执、原 late 索引及证据缺口。
- `evidence/<suite>.stdout.log/.stderr.log`：各套未过滤原始输出；唯一 RESULT、CHECK 数量和退出码相等性已程序核验；两套零 SCRIPT ERROR/ERROR，不设错误豁免。
- `evidence/net_server_gateway_restart_test/restart-first-failure.json`：SHA256 `fc46331f6c6ea86e4103a0eba346ced010da1713384104326b5921c5957eb44c`。另有同失败时点的 `restart-event-0-*.json` 原件。
- `evidence/server_shutdown_close_handoff_test/shutdown-evidence.json`：失败/恢复/关闭前立即写入批准 E artifact，包含当前及提交时绑定、请求五个必要字段、路径类型/hash、脱敏 recovery 投影、停止状态和保存回执。`evidence/worker/` 还保留 fixture evidence 原件与 worker engine/logger 原件。
- `evidence/frozen-inputs/` 保存实际运行 GDScript/场景/扩展声明字节；`evidence/historical/` 是 round58 两套 stdout/stderr 原字节副本，不借本轮 PASS 改写历史。

当前运行夹具 SHA256：

|文件|source=frozen=current|
|---|---|
|`tests/server_shutdown_close_handoff_test.gd`|`43883d7c045e424fded389ec2359e5ef7416e063f84c7c4d185ab567bad83394`|
|`tests/net_server_gateway_restart_test.gd`|`ec0ee746359a369b786588b3d594867f612e9be8d226bd81b9897a051d5a18a3`|
|`tests/net_server_recovery_midmatch_test.gd`|`15098ec7cef370ebd5b37363969b44a678b8a7a9aec48a0dbe07b22687b2c0da`|

production manager/shutdown/console/lobby 源 hash 与 round58/修改前一致，见 manifest 和 readback。正式 DLL、原引擎未替换。隔离工程仅既有授权的 editor VCS 字段转换，threading20保留。4个实际执行 Job 均 `exited=true / active_owned_processes=0 / log_handles_released=true`；769份归档逐摘要读回完成后才删除本次 generated。未访问/强杀旧28100或用户进程。

## restart22 当前 first failure：非 client_error

原始失败阶段：`baseline`；`reason=assertion-failed:actual authority and network clients reach declared match target`。信号原件 `events=[]`，双方具体 `session.error=""`，不是错误字符串漏打印或被 ignore。

|client|seq|phase|round|game_over|observer/current_player|pending|can_end|
|---|---:|---|---:|---|---|---|---|
|0|41|action|1|false|0/0|{}|false|
|1|42|action|1|false|1/0|{}|false|

两者 `battle_broadcast.pending=false`、`batch_id=0`；客户端0仍有可用 card/move/effect 权威提示。实际 fixture poll127398次，最大调用间隔2314ms，因此不支持“fixture poll 整体卡死180秒”。前置 RSA/原生 ready、清单同步/data ACK 均实际 CHECK true；失败时没有 auth/root 拒绝信号或规则异常。只能确认基线动作链未达到声明目标，不能因此排除某个未观测的 agent 锁/候选处理分支。

冻结 target 精确为 `tests/net_server_recovery_midmatch_test.gd:4`：

```gdscript
return agents.all(func(agent): return agent.decisions > 0 and int(agent.session.read_match().get("round", 0)) >= 2 and not agent.session.read_match().get("game_over", true))
```

原基线 `net_server_match_test.gd:121` 在 record_matches 时预算180000ms，本次正常到该预算后自然失败，而不是600秒外部 watchdog。round1已足以证伪 target；失败时 decisions/sent_seq/group/attempted 未由继承基线传入诊断，明确是剩余观测缺口。没有证据证明 seed 或 selector 非确定性导致本次更早失败，不写成已证因果，也不换 seed/selector、延长预算或修改 target 来填旧业务覆盖。

下一窄假设只针对真实 `net_process_full_game_test.gd:24,71,86` 三个静默 return：`sent_seq==view.seq`、`group.waiting/submitted`、首候选与实际 held_cards 朝向不匹配。建议 main 先在基线同一 actor 记录每个退出分支及原 `sent_seq/last_request/decisions/attempted/group.snapshot/当前候选与held朝向`；若持续返回锁分支且 seq41/42不变，则支持 fixture动作门禁问题；若锁未阻断却收到实际规则 error，按原错误字符串转查权威。**本轮不再执行此 probe。当前无充分因果证据授权 production diff。**

## shutdown 当前绑定保存与仍缺的历史因果

本次新实例：room `bd4a8f08a23b5afc6a7c8aac2fd7c1d6`，PID35772，instance `e17c666264fc7849eb1f81220472f2e6`，mode dedicated。

- 自有目录冲突请求 `0847c1fdac5db70424fd637deacfd2a1` 实际返回 `ok=false / error="房间状态写入失败，未关闭"`。完整原 response：`evidence/server_shutdown_close_handoff_test/response-4-0847c1fdac5db70424fd637deacfd2a1.json`，SHA `ab7bf8b02e3e727413dca8af21f38d54ff69d7f90b3114f3e9967b1c0f93043c`。当前 request/room/PID/instance/mode 全绑定，真实原生 handle verify=true/state1；该失败是原夹具预期故障，不是旧的故障撤销后重试红。
- 撤销目录冲突后新请求 `d1f5c714f5c7d88e48dce9c0e49801c5` 成功：saved=false、room_state_saved=true、closing=true，真实退出/release。`response-6-*.json` 与 `response-7-*.json` 摘要同为 `26ce8fa67876ce501ea5ba1c9c60daa4069adf0f2e3f278a0471980f130b05ca`，复制时原control摘要和复制件相等；提交时正PID绑定独立复核通过。recover 目录没有迁移：观察到同一 room directory，只换 instance/PID。
- 必须区分 current live binding 退出后 pid=-1 和原 submitted binding 正PID。运行夹具的 `receipt_binding_matches` 以 live PID比较，成功退出后该flag为false；readback按已记录的 immutable submitted binding复验成功，不把它当异实例。
- 原执行器 `late_receipts` 在 Job0后仅独立重读了上述**目录冲突失败**的原control文件，摘要未变且绑定通过；成功关闭回执有退出/release后 fixture即时双hash复制与Job0归档读回，但没有额外Job0后的原control读取行。已修专属runner的late选择为 immutable submitted绑定，**未重跑Godot，不能追认原缺行已执行**。
- native errno仍不可观测：production `_persist_recovery_state` 返回bool且丢弃 atomic result。artifact明确 `native_errno=null` 与不可用原因；不把观察者事后打开文件的错误冒充 worker保存 errno。当前故障注入目录确实存在，路径、保存请求和恢复后普通文件hash均有原件，但不能用本次成功解释旧writefail。

round58原失败 request/receipt 已清理丢失，不可恢复；具体底层errno/句柄锁/短竞态因果均 **unknown / missing causality**。若 main 要补生产诊断，最小建议仅在 `_persist_recovery_state` 失败分支向可信本机诊断输出 `{stage,native_error,temporary,target,pid}` 及控制层当前request/instance关联，不记录encoded恢复体/config/identity/key，不改变关闭语义。是否真正生产修复必须等原分支/errno证据，不以历史猜测提交业务diff。

## 改动和未验收项

仅写入两套 `.gd` 夹具、新专属 `tools/diagnostics/round60_save_restore_first_failure.py`、本报告。夹具只增观察、立即归档和信号关联；原CHECK/动作/断言未删减。runner启动后做了archive选择修正和只读readback入口，未改变运行中的freeze或重跑，两套夹具最终hash仍等于实际运行hash。原执行manifest按旧loaded runner真实行为保留，最终runner的新归档恢复分支未实跑，不宣称它完整GREEN。

已知缺口：旧shutdown receipt不可补；worker errno未取得；旧restart client_error未到达；当前基线agent静默门禁缺原瞬时字段；原性能60秒仍RED；未跑GUI/release/full98。到此结束，不再盲重跑。
