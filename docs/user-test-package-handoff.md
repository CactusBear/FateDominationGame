# 用户测试包交付边界（human-test-candidate）

## 目的

`human-test-candidate` 是真人测试交付状态，不是正式发行状态。它可以在未完成 full suite、未完成客户端 GUI 认证和完整联机验收时交付，但不能把未跑项写成 PASS。

交付 manifest 必须同时明确：

- `source_fingerprint`：build-only snapshot 的源码指纹；三角色保留同一指纹。
- `source_fingerprint_latest` 与 `source_comparison.drift`：构建快照和最后只读源码读回的 old → latest 差异，逐项保留 `added/removed/changed`。
- `build_acceptance`：真实 build 步骤、exit code、日志 SHA、三角色静态审计；这不是 runtime PASS。
- `minimum_smoke` 与 `phase-runformal.json`：复用 `round56_three_role_freeze.py --run-formal` 的真实阶段回执。`PASS`、`NOTRUN`、`FAIL` 原样保留。
- schema 3 的 `known_limitations`：每个限制项使用 `id/status/scope/evidence`，各正式阶段位于 `formal_phases` 下，同样使用结构化字段。
- 全量 `full_suite: NOTRUN`、GUI 双客户端 `NOTRUN`；保存恢复与 authority worker 就绪保留 `UNKNOWN`，不得改成 PASS 或用 NOTRUN 掩盖历史 unknown。
- `client-startup` 只表示正式客户端启动冒烟，不是 GUI/联机/保存恢复验收；专项绿只证明对应分支，不证明整包验收。
- 没有 full 回执时始终 `full_suite: NOTRUN`、`unrun_full: true`；本打包工具不支持凭空输入 full_suite PASS 回执。
- `source_pass: NOT_GRANTED`、`release_pass: NOT_GRANTED`、`ready_token: NOT_ISSUED`。

`round56_three_role_freeze.py` 的正式 `preflight`/ready-token/release 门没有降低；human-test 工具不生成 ready token，也不修改源码、GDScript、bin 或正式包目录。

## 目录和白名单

测试包目录和正式包目录必须分开，目录名必须含 `human-test-candidate`，不得含 `release`。压缩包只从这个新目录读取，且打包前逐文件回读 SHA-256；压缩后逐条读取 ZIP 并复核 SHA-256。

允许的内容只有：

- 选定角色的实际 EXE/PCK/native/data 文件（来源为 build manifest 的精确 package_files）；
- `START-CLIENT.cmd`、`START-SERVER.cmd`、`START-SIGNALING.cmd`（只透传参数）；
- `README-human-test.md`、`docs/human-test-quickstart.md`、`human-test-candidate-manifest.json`、`build-acceptance.json`、`source-diff.json`、`phase-runformal.json`、`known-limitations.json`、`SHA256SUMS.txt`。

任何路径含 `tests/`、`reports/`、`devmcp/`、`source/`、`savedkeys/` 都拒绝。不会额外复制 Godot 引擎、源码、开发数据或凭据。`--roles client` 可生成仅客户端包；README 会明确指出没有 server/signaling，不让用户寻找不存在的目录。

## 启动说明

- 只测 client：运行 `client/START-CLIENT.cmd`，客户端参数由用户/产品 UI 传入；不在包内猜服务器地址。
- server：运行 `server/START-SERVER.cmd`，仅在部署者提供明确配置后使用。
- signaling：运行 `signaling/START-SIGNALING.cmd`，仅在部署者提供明确配置后使用。
- 启动器不打开公网端口，不生成密钥，不携带 `savedkeys`；凭据只能通过正常 UI 生成。
- 默认交付口径保持：模拟预算 15 秒、worker pool 20、automatic cleanup disabled。没有在包内新增部署地址或清理开关。

## 本轮只做的旧诊断包验证

Round71 诊断包 `E:/FateCandidates/round71-build-only-4f7fb4194e19acdf-91306a82` 不是最新版，不得发布为最新版。主代理可把它作为 `--artifact-manifest` 和已有 `signaling-ready` `formal-runtime.json` 的输入，输出到 Hermes scratch 的临时目录；该目录只用于验证 manifest、白名单和 ZIP 读取，不能移动或覆盖现正式/候选目录。

验证命令（真实包读取；不导出、不启动 Godot、不发布）：

```bash
python -B tools/release/human_test_candidate.py \
  --artifact-manifest E:/FateCandidates/round71-build-only-4f7fb4194e19acdf-91306a82/manifest.json \
  --artifact-manifest-sha256 0ed4780f6c7291ee44dd8af1183de83bebc9d4b7b0ac14708b25fc9d62b45bb9 \
  --formal-runtime E:/FateCandidates/round71-signal-runtime-fdffbf9b47dbf9ff-91306a82/formal-runtime.json \
  --formal-runtime-sha256 67671db7d2d4ec04dd78665caa290a9f777564e217a4dc41f08657268ee06fd7 \
  --output-dir E:/Caches/Hermes/cache/scratch/round71-human-test-candidate-closeout-529d08bb-v1/human-test-candidate-validation
```

成功输出只能标 `HUMAN_TEST_CANDIDATE` / `published: false`；它不改变 Round71 的“非最新版”事实。

**该历史回执的实际缺口**：`formal-runtime.json` 仅含旧五阶段，缺 `client-startup`。当前交接工具要求原始回执含生产者声明的完整阶段集合，因此上述真实校验必须以退出码 `2`、`FORMAL_RECEIPT_EXACT_PHASES_REQUIRED` 拒绝；不回填、不改写旧回执，不启动 Godot 补跑。本次没有候选目录/ZIP，只有 E 盘 scratch 中的校验日志和退出码报告；不能把拒绝结果称打包成功。今后通过需取得同冻结的完整原始 formal 回执，不能仅添加 NOTRUN 字段冒充生产者输出。

若已有 ZIP 要单独复核，使用同一组 manifest/formal SHA 加 `--verify-zip <zip>`，工具会拒绝缺 handoff 文件、重复条目、禁入目录和 manifest 身份不一致。

### 本次收尾的实跑结果

- 上述旧包校验命令：退出码 `2`，原因 `FORMAL_RECEIPT_EXACT_PHASES_REQUIRED`，缺 `client-startup`；三角色实际包先经原 round56 的 PE/PCK/精确文件 SHA 门，再在 formal 阶段拒绝。
- 单测命令：`python -B -m unittest tools.tests.test_human_test_candidate tools.tests.test_human_test_candidate_boundaries -v`；21 项通过，退出码 `0`。执行环境 `TMPDIR/TEMP/TMP/HUMAN_TEST_SCRATCH` 均设为下述 E 盘 scratch 目录，未启动 Godot。
- 日志及完整命令/退出码报告：`E:/Caches/Hermes/cache/scratch/round71-human-test-candidate-closeout-529d08bb-v1/closeout-report.json`。
- 报告 SHA-256：`eea60bb839fe36f39870ba5a108a3acd218b6dceca53df4e50206ff0f04360c4`。
- manifest/formal 输入及 round56/round53 工具执行前后 SHA 不变。没有生成候选目录或 ZIP，没有发布，也没有授予 source/release PASS 或 ready token。

## 当前所有写者结束后的唯一真实执行序列

以下是给 main 的最终序列。它只使用真实 Godot build、真实 `--run-formal` 阶段执行和真实 ZIP；禁止替换成 stub/mock runtime。所有 E 盘根目录必须是全新独占目录，`SIGNAL_RUNNER` 必须是已核验的真实 runner 及其 SHA，不得猜新的部署地址。

```bash
BUILD_ROOT=E:/FateCandidates/<fresh>-build-only-diagnostic
RUNTIME_ROOT=E:/FateCandidates/<fresh>-signal-runtime
PACKAGE_ROOT=E:/FateCandidates/<fresh>-human-test-candidate
APPROVED_ROOT=E:/FateCandidates
GODOT=D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe
TEMPLATES=C:/Users/Administrator/AppData/Roaming/Godot/export_templates/4.7.2.stable
SIGNAL_RUNNER=E:/FateCandidates/<existing-verified-signal-runner>/runner.exe
SIGNAL_RUNNER_SHA256=<read-back-real-runner-sha256>

python -B tools/release/round56_three_role_freeze.py --build-only-diagnostic \
  --source E:/Projects/Godot/FateDominationGame-master \
  --root "$BUILD_ROOT" --approved-root "$APPROVED_ROOT" \
  --godot "$GODOT" --templates "$TEMPLATES" && \
MANIFEST_SHA256=$(python -c "import hashlib,sys; p=open(sys.argv[1],'rb'); print(hashlib.file_digest(p,'sha256').hexdigest())" "$BUILD_ROOT/manifest.json") && \
python -B tools/release/round56_three_role_freeze.py --run-formal \
  --artifact-manifest "$BUILD_ROOT/manifest.json" \
  --artifact-manifest-sha256 "$MANIFEST_SHA256" \
  --run-phase signaling-ready --root "$RUNTIME_ROOT" \
  --approved-root "$APPROVED_ROOT" \
  --signal-runner "$SIGNAL_RUNNER" \
  --signal-runner-sha256 "$SIGNAL_RUNNER_SHA256" && \
FORMAL_SHA256=$(python -c "import hashlib,sys; p=open(sys.argv[1],'rb'); print(hashlib.file_digest(p,'sha256').hexdigest())" "$RUNTIME_ROOT/formal-runtime.json") && \
python -B tools/release/human_test_candidate.py \
  --artifact-manifest "$BUILD_ROOT/manifest.json" \
  --artifact-manifest-sha256 "$MANIFEST_SHA256" \
  --formal-runtime "$RUNTIME_ROOT/formal-runtime.json" \
  --formal-runtime-sha256 "$FORMAL_SHA256" \
  --output-dir "$PACKAGE_ROOT"
```

`signaling-ready` 只是最小 smoke；`client-startup`/client/server/status/signaling-negative 未运行时必须继续 `NOTRUN`。原始 formal 回执的完整阶段声明（含未跑项）不等于阶段执行通过。如 main 选择 `--roles client`，只改变交付物内容，不改变 build manifest 的三角色同源核验。
