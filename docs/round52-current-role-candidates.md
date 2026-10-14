# Round52：当前角色候选实际产物与停止回执

## 结果

本次**不是三角色完成，也不是最终整合人测包**。同一当前正式安全 snapshot 的首次冷导入通过；client/server 已实际导出且静态包审计通过。随后纯信令独立角色首次冷导入 native AV，按停止门保留原件、停止其导出及全部后续运行验收，没有暖重试。

- 单一主清单：`E:/FateCandidates/round52-current-roles-20261010-sa1/manifest.json`
- 当前客户端目录：`E:/FateCandidates/round52-current-roles-20261010-sa1/artifacts/client/`
- 当前服务端目录：`E:/FateCandidates/round52-current-roles-20261010-sa1/artifacts/server/`
- `artifacts/signaling/` 仅为预先建立的空目标，**没有可下载的信令 EXE/PCK**；不得报成第三个成功产物。

## 当前来源与真实执行

完整读取 `docs/round49-legal-native-control.md`；保留“旧正式冷2次、原DLL四能力23项通过”的独立事实，但不借作本次 runtime 验收。新 snapshot 1417 文件，不含继承 `.godot` 缓存、tests/reports/tools、开发 MCP/Git helper，保留 `.import` 资源元信息、正式主场景/autoload、原 Fate DLL 与 Windows WebRTC debug/release。源码、转换、DLL/descriptor/WebRTC、引擎和四个官方模板逐文件 SHA 都在主清单。

- 当前源 fingerprint：`20637af0701a4c8b734a9914d4d1f6d69072946261cdbdc7fe09b6e175d8e5ab`
- 转换后 snapshot fingerprint：`3b555fb591a3b81ce01fd76dd99f4c33cba5a1e15f212f09a75c020888559710`
- 引擎：官方4.7.2，SHA `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`
- 原DLL：`92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd`
- 官方 release 模板：`d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562`

|实际步骤|PID|exit|墙秒|ERROR|
|---|---:|---|---:|---|
|正式首次 fresh冷import|35588|0|16.8318547|无|
|client export-release|19600|0|12.5847191|无|
|client外置data复制|32712|0|0.9912889|无|
|server export-release|11156|0|12.6048199|无|
|server外置data复制|34896|0|0.8438324|无|
|纯信令首次 fresh冷import|16072|`0xC0000005`|3.2753843|无错误行，但native退出明确失败|

实际 import 参数统一：`--headless --verbose --rendering-method gl_compatibility --editor --path <独占project> --import --log-file <E证据路径>`；导出使用同引擎 `--headless --rendering-method gl_compatibility --path <隔离角色project> --export-release <显式preset> <EXE> --log-file <E证据路径>`。短进程180秒，导出600秒；未改引擎、exposed、descriptor、能力或加sleep。

每一步执行前后重验完整生产运行 inventory，最终 added/removed/changed 均为空。新 C++ core 不在运行 inventory，正式 bin 被 descriptor 精确选入并反复核对。不能把 ignored C++ 修改概括为正式源漂移，也不能漏查正式 DLL。报告中没有将生产源码复制夹带进 PCK 伪造新能力。

## 实际包读回

PCK索引、内容 MD5/SHA、descriptor原库映射、外置原DLL/WebRTC以及全部外置 data 逐文件核对。两包各有205个 `data/` 文件；精确完整集合在主清单与 `evidence/package-client.json`、`package-server.json`。

|产物|SHA256|
|---|---|
|client EXE|`8b30b9e04970272ed3d70a4c530838570922550208ae1e1817ccb30cc0458730`|
|client PCK|`e1a01aa3a8f510f16a4eb22c573178ba66c08b9fd7fa9a5b023bcb61c14bcf44`|
|server EXE|`d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562`|
|server PCK|`bb2d733b04e110c554c20f0035643a2ffea402637cdeaac269d172c882fe77b7`|

两包 PCK 内正式 `assets/config/server.cfg` SHA 与 snapshot相等：enabled=true、budget15；冻结 project保留pool20。**这些是静态配置核验，不是 actual runtime settings/user-root 回执。** 原DLL四类在本次只记录源码接口及历史Round49证据；本次导出EXE尚未 ClassDB 四注册/完整方法读回。

## 精确未发行能力

原正式DLL保留：FateServerSignals `enable/protect_worker/disable/take_request`；FateProcessOwner `available/spawn/state/verify/terminate/release`；FateAtomicFileReplace `replace_validated_file`；FateCollectionIdentity `is_supported/candidate_key`。

**本次未发行的新core：** WindowsJobLease `assign/observe/release`；TemporaryCleanupLease `acquire/verify_and_delete`；`delete_approved_temporary`。当前源码/SConstruct各自哈希单列在主清单，不能宣称原DLL是新core的sourcebuild或Job能力已发行。没有替换正式bin，也没有把这些C++源码塞进候选包。

## 首次失败与工具修复

1. client/server 已成功后，纯信令的静态 inventory 准备首次拒绝：无继承缓存的 snapshot仍含`.import`元信息，而旧选择器必须找到其指向的旧`.godot/imported/icon...ctex`。原完整失败清单存 `evidence/first-static-preparation-failure.json`。新增显式 `inventory(..., cold=True)` 仅跳过继承 cache 依赖扩展；默认严格行为不变。2项新单测先RED后GREEN；仅继续此前尚未执行的信令步骤，未重跑正式import/export。
2. 继续后的纯信令首次冷import真实AV，`evidence/fresh-signaling-cold-import.log`/`signaling-import-engine.log`保留。此失败不能被正式成功抹掉；也不将其简化成minimal控制失败而撤销已实测的正式路径。未继续export绕过这个已发生失败。
3. `runtime_audit.py`原判定将任意非零当作缺配置拒绝，并漏查READY后的ERROR。现在要求精确exit1及唯一指定原因、零未知ERROR、正常CtrlBreak方式，保留完整负向stdout。7项新审计单测通过；没有运行候选EXE来虚构通过。
4. 既有11项发行单测首次运行有1项夹具根拒绝：TMPDIR与显式LOCALAPPDATA下Hermes scratch不一致。只在本次自有E运行环境统一两者后11项通过，未修改既有测试或放宽边界。

当前纯信令生产 `_signal_fail` 明确 `quit(2)`，与用户要求的缺配置exit1仍不匹配；本次由于停止门未实际运行此负向，属于源码已证实的待生产负责人解决项。未改生产分支冒绿。

## 未验与停止边界

因信令首次冷失败而停止：signaling EXE READY/合法CTRL_BREAK退出、缺配置实际exit1、server EXE READY、本机认证client建房settings15、保存大厅安全关停、client正式入口最短headless启动、actual runtime user E根及注册读回均**未执行**。仅E环境变量配置不等于真实user根回执，主清单明确标NOT_RUN。

全当前headless、GUI（sa-2-c4f0f589唯一owner）、默认房间worker/settings事故、完整cleanup生产接线、多机跨网/完整对局仍分别开放；不可把这两份静态通过产物报成最终人测完成。

## 所有权与回收

六个当次自有PID最终OpenProcess查询均error87、不存活；不操作用户editor或按进程名终止其他进程。自有生成`.godot`/shadow DLL完整ZIP归档、CRC和逐文件SHA验证后回收1528文件、435520023字节，清单存主manifest；archive为 `evidence/owned-generated-cache-originals.zip`，SHA `3010bad5e2333f4b9ba91f14dd998e838a73bb67beba1d6f1a64dc8bce3d4dd1`。

保留source snapshot、角色源码、失败日志、client/server完整包、模板和E用户路径，未默认删除当前候选包。

## 修改范围

仅修改 `tools/release/freeze_prepare.py`、`runtime_audit.py`；新增 `tools/tests/round52_current_role_candidates.py`、`round52_candidate_receipts.py`、`test_round52_cold_inventory.py`、`test_round52_runtime_verdict.py`及本报告。production/native/bin/descriptor/SConstruct/既有tests/source/gate均只读，无提交。
