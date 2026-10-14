# 保存/恢复链：阶段观测契约（真实空大厅 + 一次 save）

## 结论

**观测边界可用；生产保存阶段/整份日志脱敏契约仍 RED。不是保存或恢复通过。**

- 真实 manager/native worker 到 READY，经原 `room <id> save` 管理入口只提交一次 save，随后只轮询对应 result。实例绑定回执为 `ok=false`、`saved=false`；原因精确对应“当前对局未启用录制，不能声明存档成功”。拒绝后原 worker 仍活。
- 18 CHECK：16 true / 2 false；测试和 runner exit1。父/worker ERROR、SCRIPT ERROR 均0；导入 exit0；两个自有 Job 均 ActiveProcesses=0，日志句柄释放后才归档。
- 测试侧固定边界序列采集完整、单调；失败位于 `save_receipt`，仅从真实回执定位到 recording gate。不冒充内部阶段成功，也不声称持久化/恢复已执行。
- RED 1：`ServerRoomControl.save()` 在 `server_room_control.gd:117-120` 的审计/录制门之前没有阶段输出；本次生产保存阶段采集数0。空大厅在录制门早退，未进入 flush、恢复状态落盘或 restore。缺口是阶段发射点缺失，不是未知内部调用已经失败的证明。
- RED 2：原 `server_room_worker.gd:312` 的 `SERVER_ROOM_READY <room-id>` 带房间身份，故**整份真实 engine 日志**不满足“不含身份”。未复述具体ID。严格阶段白名单投影视图不含配置、路径、身份、票据或数据载荷；不能拿投影视图替整份原日志宣称脱敏通过。

## 交付

- 测试：`newtests/save_restore_stage_observation_test.gd`
- 场景：`newtests/save_restore_stage_observation_test.tscn`
- runner：`newtests/run_save_restore_stage_observation.py`
- 退出后证据复核/严格白名单投影：`newtests/verify_save_restore_stage_evidence.py`
- 本报告：`newtests/save_restore_stage_observation_report.md`

仅上述 newtests 文件由本任务写入。生产源码/配置/原生 DLL 未改；无新 IPC、控制协议、规则替身、全量、测速或窗口运行，不触碰 PID17120/28100。不读取、打印、哈希、归档生成的恢复文件、密钥或票据内容。

## 实际命令与证据

```text
python newtests/run_save_restore_stage_observation.py
python newtests/run_save_restore_stage_observation.py --diagnostic-startup
python newtests/verify_save_restore_stage_evidence.py E:/scratch/isolated-55ea4403076347c0a269cf3ed269c61f
```

每个引擎进程均 `--headless --audio-driver Dummy --fixed-fps 60 --path <独占E冻结工程>`，外层看门狗360s。无重试保存请求。

### 默认启动观察（未发送 save）

- `E:/scratch/isolated-b07913083a1c4956a4341ebe35f65af3/manifest.json`
- 父日志：同根 `evidence/test.stdout.log` / `evidence/test.stderr.log`
- worker原始日志：同根 `evidence/worker-engine.log`
- 4 CHECK，3 true / 1 false，exit1，ERROR0，导入及测试 Job0。
- 原30s启动门内未见 READY：最后完成 `cache_policy result=0`，随后 `cache_population result=1`，未见完成/拒绝标记。没有据此宣称死锁或缓存失败；保存目标未触达。

### 显式隔离诊断启动观察（实际一次 save）

仅测试 manager 以300s启动观察预算触达 save；生产默认30s未改。不能追认默认启动通过。

证据根：`E:/scratch/isolated-55ea4403076347c0a269cf3ed269c61f/`

- `manifest.json`：真实 argv、引擎/源码指纹、进程退出/Job0/日志句柄释放记录。
- `evidence/test.stdout.log` / `evidence/test.stderr.log`：父原始日志。
- `evidence/worker-engine.log`：真实 worker 原始日志，保留历史 READY 身份行。
- `evidence/observation-evidence.json`：安全报告，实际阶段数组、失败分类，不含配置、身份或票据值。
- `evidence/boundary-stages.log`：从实际 stdout 严格全行正则投影的12条边界记录。
- `evidence/startup-stages.log`：从实际 worker 日志严格全行正则投影的52条启动记录。

复核工具 exit0 仅表示证据计数/冻结一致性复核成功，**没有将测试 exit1 改成通过**。原 manifest/日志没有覆盖。

## 实际阶段序列

语义：1=进入、0=返回/完成、-1=拒绝；可选调用的完成不等于其业务被执行。

### 测试侧边界（12条，原stdout精确顺序）

```text
worker_start   1 → 0
worker_ready   1 → 0
save_request   1 → 0
save_receipt   1 → -1
worker_release 1 → 0
log_collection 1 → 0
```

这是测试侧观测边界，不是生产保存内部阶段。collector 的未知阶段、逆序/重复、缺完成、附加 ticket 字段四组反例均被拒绝；实际 stdout 由独立 Python 再次核对固定名称和完整序列。

### 生产启动（52条，嵌套保持真实顺序）

除显式括号外，以下每阶段均 `1 → 0`：

```text
signal_protection → launch_arguments → configuration → settings
→ selection_mode → catalog_scan → data_plan → cache_policy
→ cache_population → data_assembly → data_validation
→ fixed_source_registration
→ process_content(1)
  → content_environment(1 → 0) → rules_reload(1 → 0)
→ process_content(0)
→ roster → host → recovery_binding → selection_configuration
→ blob_publication → room_asset_installation → startup_pin_release
→ identity_bridge → data_approval → transaction_audit → ready_publication
```

生产保存阶段序列：`[]`。恢复：未执行。历史 unknown 继续 UNKNOWN。

## 冻结及未验收边界

- 已核对本次冻结输入与 manifest 哈希一致，差异0；worker/control/manager/console 的当前源码仍与本次冻结相同。
- 冻结 worker SHA256：`a1d935675ce6d6a3f804ac9000104b15d95c2c279c8cf13c459acdd3920107eb`。
- 冻结 control SHA256：`296edf36916d77d767e67fceeb33808554e8e487dabb92a43ac0fa5703630997`。
- 本机并行任务使仓库相对冻结发生4个源码漂移：`scripts/net/authority/match_authority.gd`、`scripts/net/validation/room_data_validation_worker.gd`、`scripts/system/global/fact_delivery.gd`、`scripts/system/global/game_log.gd`。原 manifest 的 `source_unchanged=false` 如实保留；本结果只属于该冻结，不是当前整个工作树整合通过。
- 未验收录制对局、journal flush、恢复状态落盘、身份恢复、重放、ACK、续局或正常保存关闭。自有空大厅 `manager.close()` 仅用于测试释放，不能作为正常安全关停证明。
