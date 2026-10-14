# round74：旧诊断包 client 默认邻接 PCK 单次 headless 实跑

## 结论与边界

**旧包 client 在默认邻接 PCK 方式下完成正式主场景 headless 加载与正常退出：已证实（日志 Completed load + EXE exit 0 + 私有 Job0）。**

但原 round53 API 回执保持 **FAIL**，不能作为正式准入 PASS：`official_main_load_observed=false` 是唯一为假的 checks 字段。加载检查仅匹配 `Loading resource: res://assets/scenes/main_menu/opening_background.(tscn|scn)`；真实导出日志 Loading 行使用 remap 后 `.godot/exported/...opening_background.scn`，随后 Completed 行明确报告原正式主场景加载完成。已向 main 报告此判据漏匹配；本 owner 未改接口、判据或回执，也未重试。

回执明确 `old_artifact=true`、`nonfinal=true`、`stage=client-startup`，仅此 stage。GUI、联机、认证、保存、恢复、跨机及原生方法能力读回均未验收，不给 PASS。旧 DLL 本次启动未报告加载错误，但不据此宣称所有原生方法或后续 worker 能力通过。

## 真实调用与退出

仓库工作目录：`E:/Projects/Godot/FateDominationGame-master`。

一次性调用器的真实终端命令：

```bash
TMPDIR='E:/Caches/Hermes/cache/scratch' TEMP='E:/Caches/Hermes/cache/scratch' TMP='E:/Caches/Hermes/cache/scratch' python -B newtests/round74_old_client_adjacent_once.py
```

调用器只调用一次 `run_client_startup(ROOT, MANIFEST, MANIFEST_SHA, old_artifact=True)`，随后分别调用原 `validate_client_startup_receipt(..., require_current=False)` 与 `require_current=True` 做只读验证。二者均拒绝：`CLIENT_STARTUP_PASS_PROOF_REQUIRED`，未执行新的 EXE。调用器终端 exit **1**；原回执顶层 runner exit **1**；真实 EXE exit **0 / 0x00000000**。不能混淆三者。

回执记录的真实 EXE 命令：

```text
E:\FateCandidates\round71-build-only-4f7fb4194e19acdf-91306a82\artifacts\client\FateDomination.exe --headless --audio-driver Dummy --rendering-method gl_compatibility --verbose --fixed-fps 60 --quit-after 180 --log-file E:\Caches\Hermes\cache\scratch\g05-client-startup-round74-adjacent-once-sa53\logs\client-startup.engine.log
```

未传 `--main-pack`、`--script`、`--path`、`--scene` 或任何生产 user argv。执行 cwd 是本次新隔离输出根。180 秒为既有看门狗；`--quit-after 180` 为引擎正常退出帧数。未测速、未导出、未换引擎或 DLL、未暖重试。

- 实际启动次数：1；PID **33896**，不触及用户 PID 28100。
- `job_attached_before_resume=true`；`active_owned_processes=0`（真实 Job accounting）；`exited=true`。
- `normal_exit=true`、`private_job_exited=true`、`logs_released=true`，无 forced termination 或 bounded timeout 标记。
- APPDATA、LOCALAPPDATA、TEMP、TMP、TMPDIR 都绑定新 E 盘根下 `users/client-startup/`；日志也在该根内。
- API 原文件启动前后 SHA 一致：`2d44be0e63653659efeda81b846d2fd64516c0f75a6b924efc38935f6a926bf8`。

## 回执与哈希

新回执（不覆盖原 runtime.json）：

`E:/Caches/Hermes/cache/scratch/g05-client-startup-round74-adjacent-once-sa53/runtime.json`

SHA256：`8250d8d75077af3fb9ab5e14a2126fe03175307584e5b0e8c538ed6d8a6e16c6`

调用/验证旁证：

`E:/Caches/Hermes/cache/scratch/g05-client-startup-round74-adjacent-once-sa53/caller-evidence.json`

SHA256：`d1e0e120405ddf87a8c867cc60a854db7c1138d138b06af130e0ce403076d7de`

旧 manifest：`E:/FateCandidates/round71-build-only-4f7fb4194e19acdf-91306a82/manifest.json`。

SHA256：`0ed4780f6c7291ee44dd8af1183de83bebc9d4b7b0ac14708b25fc9d62b45bb9`

- 冻结 source fingerprint：`4f7fb4194e19acdfefd4bde3142bb876dab99f2d9aa3a361f217e65cdf31329c`。
- EXE SHA256：`8b30b9e04970272ed3d70a4c530838570922550208ae1e1817ccb30cc0458730`。
- 邻接 PCK SHA256：`bce3390ad25a54d71b5362f1f74d85e02be9b788d1c86493bc3ce1075478a7d6`。
- 原 signals DLL SHA256：`92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd`。
- 原 WebRTC DLL SHA256：`3a8053d325a874493f596630b0f165f3a83e265c61d9fd87d82da6cb4c2a81fd`。
- API 已核对旧包运行前后完整文件哈希，当前源码差异保存在 source_observations；不是当前候选验收。
- 原首次拒绝回执 `E:/Caches/Hermes/cache/scratch/g05-client-startup-round71-once-sa53/runtime.json` 前后 SHA 均为 `0a3c83d03b9ec7f42659ba07ebc0b4b50ea56d2d99e40e72b52dd0be849c4a44`，未改写。

## 全日志检查及关键原文

日志根：`E:/Caches/Hermes/cache/scratch/g05-client-startup-round74-adjacent-once-sa53/logs/`。

| 文件 | SHA256 |
|---|---|
| client-startup.stdout.log | `96290c6551d618912bad002fe42a0fba5ec7da404e16b80fb80362be8e29eb4b` |
| client-startup.stderr.log | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| client-startup.engine.log | `8d74aa763a14236839bf1a9f3ddd29f94d778f304ea712fec385347da6bae62f` |

只读复核三个完整日志并匹配 SHA；未发现 SCRIPT ERROR、SHADER ERROR、ERROR/FATAL 或 DLL/GDExtension/dynamic library 加载失败行，stderr 为空，runs[0].errors=[]。

stdout 关键原文（同样的主场景加载证据在 engine 第 24、47 行）：

```text
[stdout:2] Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org
[stdout:25] Loading resource: res://.godot/exported/133200997/export-4d3a4d0cc13c47e82d99fa168bc1f161-opening_background.scn remapped: res://.godot/exported/133200997/export-4d3a4d0cc13c47e82d99fa168bc1f161-opening_background.scn
[stdout:48] Completed load for: 'res://assets/scenes/main_menu/opening_background.tscn' remapped 'res://.godot/exported/133200997/export-4d3a4d0cc13c47e82d99fa168bc1f161-opening_background.scn' at thread -1
[stdout:193] XR: Clearing primary interface
[stdout:194] XR: Removed interface "Native mobile"
[stdout:195] XR: Removed interface "OpenXR"
```

## 本 owner 新增文件

- `newtests/round74_old_client_adjacent_once.py`：薄调用器；新根已存在即拒绝，不可重跑。
- `docs/round74-old-client-adjacent-startup.md`：本报告。
- 本次专用 E 根下原 API runtime.json、完整日志、隔离 user 环境及 caller-evidence.json。未改生产源、round53、round56、human_test_candidate.py 或旧 EXE/PCK/DLL。
