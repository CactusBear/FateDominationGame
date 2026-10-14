# Round71：三角色实产出，仅 build-only 诊断候选

## 结论及不变门槛

本轮已完成一次自足 snapshot 的真实 client/server/signaling 构建，不再只有构建计划。状态为 `BUILD_ONLY_DIAGNOSTIC_THREE_ARTIFACTS_RUNTIME_NOTRUN`，**不是最终发行，也不是 source PASS**。随后仅实际运行同候选的 signaling READY/握手/normal stop；总体 `PARTIAL_NOT_THREE_ROLE_PASS`。

完整阅读并复用 `round56_three_role_freeze.py` 的 ready-token/report/source/native 编译门，以及 `freeze_prepare`、`round52_current_role_candidates`、`signaling_prepare`、`release_contract`、`package_audit` 的真实 API。正式门合理要求同源码五类真实 owner 报告，不能将未完成报告伪造成审批。因此只新增显式 `--build-only-diagnostic`，不生成 ready token、不绕过或改写 `preflight` 的最终门；不改生产脚本、bin、用户引擎或其它 release 工具。

### 修改的实现边界

- `diagnostic_snapshot`：最多初次及一次重取，不轮询其它 owner。每文件核对复制前源 SHA、复制后源及副本 SHA，再比较完整来源集合与副本集合。拒绝的 snapshot/精确 drift 保留；两次仍漂移则停止，不启动 Godot。
- `diagnostic_build`：明确 build-only 授权、全新物理 E 根、默认15/pool20、原生产 DLL及原官方引擎/四个模板哈希；不接受混用 `--build/--inventory/--run-formal/--ready-token`。复制成功后仅依赖自足 snapshot，不因其它 owner 后续合法修改而等待或拼接新源码。
- `_build_packages`：原 `build` 和独立诊断调用同一导出实现；正式调用仍重新执行原 `preflight`。复用 client/server export、data copier、runtime copier、PCK审计；信令复用现有 external-supported-runtime prepare/audit，无 editor-discovered descriptor、autoload、data或游戏规则。首次 cold import/export 非零立即保留原退出码、十六进制、完整日志并停止，不暖重试。
- 三角色清单均有同 `source_fingerprint`、EXE/PCK、完整包文件/data/native SHA；新增真实 `artifact_identity_sha256`，最后再次验证实际 PE/PCK/跨角色 native 一致。
- finally 将 snapshot 与后来生产树差异写 `source-readback.json`。构建之后另有 `post-runtime-readback.json`，不改已有 manifest 或包字节。

## 实际产物与身份

构建根：

`E:/FateCandidates/round71-build-only-4f7fb4194e19acdf-91306a82`

- 来源 fingerprint：`4f7fb4194e19acdfefd4bde3142bb876dab99f2d9aa3a361f217e65cdf31329c`
- artifact identity：`fdffbf9b47dbf9ff71a40e101ff208ecbb3f487ba5d0fb4f70305c8944c86294`
- `manifest.json` SHA：`0ed4780f6c7291ee44dd8af1183de83bebc9d4b7b0ac14708b25fc9d62b45bb9`
- `snapshot-attempts/1/source-snapshot` 为精确原件；本次一次采集即通过，无二次取得或失败 cache 复用。

| role | 实际入口，位于构建根 artifacts/ | 包文件数 | 外置 data文件数 | PCK SHA256 |
|---|---|---:|---:|---|
| client | `client/FateDomination.exe` | 209 | 205 | `bce3390ad25a54d71b5362f1f74d85e02be9b788d1c86493bc3ce1075478a7d6` |
| server | `server/FateServer.exe` | 210 | 205 | `d6898bd7ee71ce504afdc6e91f8d5cbab1d8dd0d451db10bda5f5c3d6fc26951` |
| signaling | `signaling/FateSignaling.exe` | 5 | 0 | `5f18d2cbe965fe36fb45a85abd01aa0511c92e873b38d5302716f3180bc5b5c5` |

client EXE SHA：`8b30b9e04970272ed3d70a4c530838570922550208ae1e1817ccb30cc0458730`；server/signaling EXE SHA：`d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562`。三个不同 PCK，未拼旧候选。

三角色原 signals DLL SHA均为 `92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd`。client/server WebRTC SHA均为 `3a8053d325a874493f596630b0f165f3a83e265c61d9fd87d82da6cb4c2a81fd`。signaling 外置 descriptor SHA为 `441a1d645d3728105e7f7cf20303146d3e630d57a43a741cee67031d1fa91b62`。新9c14 DLL未发布，旧 DLL不能承接新 C++ Job/cleanup能力 claim。

原官方引擎 SHA仍为 `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`。构建后再次只读核对引擎与生产 DLL未变；没有切换模板或引擎。

## 实际命令及退出

实际调用 `main` 的构建参数如下（root已经存在，禁止原地重跑）：

```bash
python -B tools/release/round56_three_role_freeze.py --build-only-diagnostic \
  --source E:/Projects/Godot/FateDominationGame-master \
  --root E:/FateCandidates/round71-build-only-4f7fb4194e19acdf-91306a82 \
  --approved-root E:/FateCandidates \
  --godot D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe \
  --templates C:/Users/Administrator/AppData/Roaming/Godot/export_templates/4.7.2.stable
```

外层 exit0。`first-game-cold-import`、`export-client`、`copy-data-client`、`export-server`、`copy-data-server`、`first-signaling-cold-import`、`export-signaling` 共7步均真实 exit0/`0x00000000`，无 ERROR/SCRIPT ERROR、无超时。cold首次分别约22.82秒与3.66秒。完整 PID/命令/日志SHA/错误行保存在 manifest.steps。client/server 静态包审计 exit0；信令 prepare/audit与最后三角色实际索引/hash审计通过。

## 仅安全信令实际运行

```bash
python -B tools/release/round56_three_role_freeze.py --run-formal \
  --artifact-manifest E:/FateCandidates/round71-build-only-4f7fb4194e19acdf-91306a82/manifest.json \
  --artifact-manifest-sha256 0ed4780f6c7291ee44dd8af1183de83bebc9d4b7b0ac14708b25fc9d62b45bb9 \
  --run-phase signaling-ready \
  --root E:/FateCandidates/round71-signal-runtime-fdffbf9b47dbf9ff-91306a82 \
  --approved-root E:/FateCandidates \
  --signal-runner E:/FateCandidates/round53-signaling-runtime-entry-sa1/diagnostic-tools/runner.exe \
  --signal-runner-sha256 6d4e5e6bb6ada3020513c3159660aee824435b15e09249cf920074a40ae75ded
```

实际 exit0，仅 signaling-ready PASS；`client/server/status/signaling-negative`及正式exported client RSA仍 NOTRUN。正式 EXE入口无外部 `--script/--path/scene`覆盖。真实 native READY四类/方法检查、127.0.0.1动态端口14725的create/join/offer/answer全部真，game/save/rules/match_command全部拒绝，没有游戏payload转发。精确自有CtrlBreak sender exit0，engine PID31372正常exit0、无timeout、完整尾日志errors=[]；keeper PID36140。后置OpenProcess两PID均error87仅证明后置不存活，正常退出依据原runner EXIT_PROCESS回执，不冒称Job active0。

- runtime `formal-runtime.json` SHA：`67671db7d2d4ec04dd78665caa290a9f777564e217a4dc41f08657268ee06fd7`
- `signaling-ready/actual-exported.log` SHA：`5a745c717303d45511ea613fd2b7049eef7f85500b0f1cc8494e179ac7c4b3dd`
- 构建根 `post-runtime-readback.json` SHA：`0bfda4f3ba9e73790c4b3234df06a460924d9205d4bcf3150eba063ca7e5582a`

运行后重新验证三角色完整包集合/PE/PCK/data/native SHA仍一致，未修改发行包。未启动游戏client/server、不抢GUI、不创建可能卡住的网关或房间；未触碰用户28100、未删除用户包或失败证据。

## 精确后来源码差异与留开验收

构建末次读回：新增 `scripts/net/server/temporary_cleanup_proof_collector.gd`。运行后读回fingerprint已变为 `ec926546f08aef5531a9ec89a28ae60a8551a40cfa1074d36dc85eed0b3e65d8`：

- 新增 `scripts/net/server/temporary_cleanup_proof_collector.gd`、`scripts/net/session/host_match_request_inbox.gd`；
- `scripts/net/session/lobby_session.gd`：snapshot SHA `9541688289a80f59677a396e24ac7e885eb6552558a3edf0ab16baacf72b9e3b`，后来源码 SHA `8b02621c55f94746e41780ddd77025e85a7ccb88e4aa0ab2ec5f8c10d1ed88dd`；
- 无删除；以上是该次真实读回，不保证其它owner此后停止修改。

这些后来字节不在候选里，不能把本候选叫最终集成包。GUI opening留给原唯一GUI owner后验；两个真实exported客户端、认证/创建加入/内容审批、save/close/recover界面整链、server新status/stop、信令missing-config、多机跨网、新native生产推广均未由本轮证明，继续 NOTRUN/未准入。editor RSA fixture虽然同snapshot生成，未实跑且不可冒称正式客户端。

## Python验证

`python -B -m unittest tools.tests.test_round71_three_role_build_candidate tools.tests.test_round56_three_role_freeze tools.tests.test_round64_release_runtime_entry tools.tests.test_round53_signaling_initialization -v` 实际40/40 PASS，exit0。新增6项覆盖精确copy无审批、显式诊断授权、CLI混合阶段拒绝、一次重取成功、持续漂移两次即停且保留证据、精确hash对照；其合成夹具仅是单测，不是发行runtime证据。正式旧门/原native/原runtime回归仍通过。
