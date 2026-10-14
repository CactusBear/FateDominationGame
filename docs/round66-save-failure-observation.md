# Round66：真实保存失败出口的本机观测

## 结论与边界

**SOURCE_SAVE_FAILURE_OBSERVATION_GREEN；正式发行 EXE 验收未完成。**

已复用 Round64 纯投影器接入真实 `LobbySession._persist_recovery_state` 的失败出口。有效 RED→GREEN 证明错误信息改善，不修保存故障、不增加重试或回滚。旧历史保存失败原因仍 **unknown**，没有读取旧恢复档、keys、tickets、旧 saved receipt 或访问用户 PID28100。

唯一生产改动：`scripts/net/session/lobby_session.gd` 的 `_persist_recovery_state` 及单职责 `_report_recovery_save_failure`。纯投影器未修改；servercontrol/console/manager/shutdown/transport/native/规则保持只读。新文件为 `newtests/recovery_save_observation_test.gd/.tscn`、`newtests/run_recovery_save_observation.py` 与本文。没有导出、修改 DLL、修改恢复事务时序或新增保存公开 API。

## 状态与身份选择

选择**无持久状态的本机同步失败事件**，比 Callable 的长期注入字段或 last-diagnostic+attempt 序列更少状态。没有消费者需异步读取诊断，不增加 last-error、不伪造 request identity、不使用临时 RefCounted instance ID。LobbySession 无可信 request/process-instance 上下文，因此事件只能说明当前 PID 的一次同步保存失败，不能跨请求/进程重启关联。

固定事件名 `RECOVERY_SAVE_DIAGNOSTIC`；现有 projector 输出 `version/stage/native_stage/native_error/godot_error`，helper 仅追加即时 `pid`。没有路径、encoded、自由文本、seat、key、ticket 或任何恢复内容/哈希指纹。没有捕获到的错误为 null，不把 Godot Error 当 WinAPI errno。

成功及空 path/nonhost 未尝试分支无失败事件。没有可遗留的 last-error 状态；消费者不得把旧事件归给后来的成功。本轮不清除原业务 `session.error`：那会改变既有调用方行为；其原赋值保留。

## 顺序与短路

保留原 path→snapshot→seat→approved→journal/identity→open→encode/store/flush→get_error→close→授权/内容校验→发布→成功内存采用/失败 temp 清理顺序。

- 原授权及 seat/snapshot 失败前加白名单事件，bool/error 原值与原赋值不变。
- `write_json` 单次 Error 保存后比较；FileAccess.open 失败紧邻调用 `get_open_error`，不再次 open。
- 原 `result == OK and checked(temp) and checked(target) and matches_bytes` 拆为等价 if/elif；每个检查原顺序只执行一次，不重复检查推断。
- 已有 target：原 wrapper 单次真实 Dictionary 保存，仍仅依 `.get("ok",false)==true` 判断 committed；失败将同一结果投影。
- 首次创建：先原目录检查，再单次 rename 捕获同一 Error；目录阻断只有 stage、错误 null。
- 成功内存采用、最后 `checked(temp)` 后 remove 的原失败清理政策及 bool 保留。open/identity 等原提前返回不额外清理。报告失败不改错误原因、不作为业务控制流或 saved proof。

有效 RED 冻结与最终源码完整比较：保存函数之前及原后续所有函数逐字相同；新增 helper 之外没有其他生产改动。

## 真实测试与证据

命令（在项目根）：

```text
python -B newtests/run_recovery_save_observation.py recovery_save_observation_test --count-branches
python -B newtests/run_recovery_save_observation.py
python -B newtests/run_recovery_save_observation.py server_shutdown_close_handoff_test
python -B newtests/run_recovery_save_observation.py server_shutdown_close_handoff_pending_test
python -B newtests/run_recovery_save_observation.py net_server_shutdown_failure_test
```

证据均位于 `E:/scratch/round66-save-observation-<id>/evidence/`，保留 manifest、stdout、stderr；运行根/APPDATA/LOCALAPPDATA/TEMP/TMP/TMPDIR 为物理 E 普通目录。挂起启动根后纳入私有 Windows Job 再恢复，180 秒看门狗只管本次 Job；所有下表 import/test 及派生进程收尾 Job active=0。此诊断 Job 不冒充生产 Job 功能。

|阶段|id|结果|
|---|---|---|
|有效 RED|d6957b755b3d4751b11adb34b271592c|真实业务 36 CHECK/RESULT 全绿、无引擎错误；7 个真实失败缺少单次脱敏事件，runner exit1|
|同一初始夹具 GREEN，计数|3c4588ddeaa04a3882b4d359e04445cd|36 checks，runner exit0|
|同一初始夹具 GREEN，未插桩|0c1d2aec27f245d7ac640f2b15d36eb2|36 checks，runner exit0|
|原 shutdown86|1b8dabb964ab4855a715ceae3f5f6e6a|86 checks，exit0|
|原 pending36|2cd91d80d16c4c288eb79fe8a65303ee|36 checks，exit0|
|原 failure161|d421211e398d4c379a36d9a30edd7d75|161 checks，exit0|
|扩展最终接缝，计数|bfcb8f53a55b4463a093239d1b13b344|69 checks，exit0|
|扩展最终接缝，未插桩|77295b38cce541e8a4549991eab59a7e|69 checks，exit0|

最终未插桩接缝69 + 原86/36/161共 **352 checks**；不是将插桩重复或 Round64 wrapper56 充生产验收。所有通过记录严格解析唯一 RESULT、CHECK 数、exit、stderr；无 SCRIPT ERROR/ERROR，源码前后 SHA 未漂移。表中所有 GREEN 的 lobby/projector/wrapper/control/shutdown/manager/shared/DLL SHA 一致。

### 新接缝的实际行为

真实 ENet 回环临时端口→公开 `host_peer`，保存入口为原公开 `RoomControl.prepare_close()`→真实 Lobby 保存，无替身规则或保存 bool。

- 父进程仅锁新 `locked.old` 普通字节，CreateFileW GENERIC_READ/FILE_SHARE_READ、无共享删除。首次该 native_commit 调用实际 wrapper/DLL **一次**，结果 `native_replace/32`；公开关闭 false，无 saved proof；普通旧 target 独立读回完整，原 temp 清理仍执行。
- 父进程在 Godot 根挂起时创建并持有本次 PID 的普通 initial temp，允许 read/write 共享但拒绝 delete。真实首次 rename **一次**失败，捕获 Godot Error **1**，native_error=null；目标保持不存在。此案例只证明受控机制，不还原旧历史故障。
- 首次成功仅 initial rename 一次；已有成功仅 native wrapper 一次；目录冲突不调用二者；path/seat/snapshot/open 拒绝均不调用发布。插桩只在隔离副本打印 wrapper 入口，首次 rename 的小 wrapper 直接调用原 DirAccess.rename_absolute、不改结果；另跑未插桩冻结源码验证同一结果。
- temp 为目录时真实 open 失败，立即采集 Godot Error **12**；不推断 WinAPI Error。
- path、seat、snapshot 拒绝各仅一事件；seat/snapshot 在创建 target 前拒绝。
- 后续成功无失败事件，空 path/nonhost 无事件；成功采用解码后的整数键，失败保留原字符串键内存绑定。
- 每个 case 用原共享 projector 投影真实 close response，精确保持共享 `response_valid/ok[/pending]`；client view 不变。成功仍 `saved=false/room_state_saved=true/closing=true`，失败无 result，不扩展共享 output 或 saved proof。

原86实际创建生产 worker，并包含真实目录保存失败→不退出/不放行 stop/不建 closed proof→撤销故障后成功；原36覆盖 pending/retired；原161保留原保存失败、未知句柄、回执绑定与房主关闭的正负向链。未改三套原 fixture。各原套内部正常执行自身恢复/回执校验；执行器及人工没有读取、hash、复制或归档生成 recovery/temp payload。只有白名单日志及批准控制回执用于交付；Job0 后生成 fixture/user/runtime 树已消费（早期 runner 的树以独立 runtime-cleanup.json 记录），仅保留源码冻结和 evidence，不保留恢复 payload。

## 冻结 SHA256

|文件|SHA256|
|---|---|
|lobby_session.gd|9541688289a80f59677a396e24ac7e885eb6552558a3edf0ab16baacf72b9e3b|
|recovery_save_diagnostic.gd（未改）|96d66505708d7e2bd0980a2df3648a827bfe9eed9ee02bae2db72d919bc089a9|
|atomic wrapper（未改）|13decd6a6c40f92e90060f67c4fc8c10546d1d9a0a0fce8ae59f10677739273d|
|RoomControl（未改）|296edf36916d77d767e67fceeb33808554e8e487dabb92a43ac0fa5703630997|
|shutdown（未改）|7526d0b8fd7d427a04a67085f462425f845e883a3210ee8017a0a30963b60227|
|manager（未改）|fadbeb892cfce741d62b95ff1c452d86b883d9a39c811851318d4a97f3799d53|
|shared projector（未改）|4e24e40a526e152b10501ec5552b95a073e56f7e58b8333f45e2ee85eb5ce4fc|
|正式原 DLL（未改）|92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd|
|新 runner|2ffcb2f923e4e117df18e9f7824f66752fed3a3a39a54cd0a2dc53ade3e536cd|
|最终新 GDScript fixture|13d2e9d30a53fc8038d646796b2ad459b2e8c117fd0257a76f2753ed8cceeced|

逐文件 source SHA、原引擎 SHA、argv、PID、Job0、stdout/stderr SHA 详见各 manifest。最终未插桩 manifest SHA256：`2f47eb65b44a9b1076129f500b6b71c74b03e5e5ea7501bffcf0779973dcaee7`；计数 manifest：`df9b86f177e10257f4eff01ef3df46dae3a8e9b9c80a160297d885909b84fb4b`。两者 `runtime_consumed=true`；终末核对有效 RED 的全部只读源 SHA 与当前源一致，`git diff --check` 通过。

## 问题与未覆盖

初期新增 runner 调错不存在的 OwnedJob.wait_empty、冷 fixture cursor autoload 先于贴图导入、新 fixture 命名遮蔽原生 Control、OfflineMultiplayerPeer 不满足原 transport 契约及缺显式 selection_mode 均为夹具/执行器问题，不计有效 RED。已改为真实 Job active 等待、仅冷导入时延后 CursorReplace（运行阶段恢复原 autoload）、RoomControl 名称、真实 ENet/显式模式；保留相应失败日志，不改生产 transport/规则。隔离配置另记录删除未包含 main_scene、编辑器插件及切换 headless gl_compatibility；不改变原工程配置。

仍未动态故障覆盖 store/flush、flush 后授权失效、matches_bytes 内容故障或活动局 identity sidecar 写失败（相关出口仅源码顺序复核）。未跑完整恢复重放、用户窗口、多机或正式发行 EXE/PCK。新诊断没有跨 request 身份，不负责更新旧 saved receipt；正式包必须按本源码重新发行并真实验证保存/拒绝/关闭/stop/退出链后才完成发行验收。历史 failure 原因继续 unknown。
