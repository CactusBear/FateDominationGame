# Round64：显式三角色 artifact 运行入口

## 交付及边界

`tools/release/round56_three_role_freeze.py --run-formal` 不再直接返回 NOTIMPLEMENTED：现有真实执行器已接线，支持 `client`、`server`、`status`、`signaling-ready`、`signaling-negative` 和 `all`。不导出、不生成 ready token、不替换 PCK/DLL，不读取 dotenv 或身份凭据。

- artifact manifest 必须显式给定文件和 SHA256。每阶段前后核对整个包文件集合及 SHA；核对实际 EXE/DLL PE x64、独立 PCK 索引/内容完整性、角色声明及角色入口资源、完整外置 data/native 清单。链接/junction、缺角色、缺 EXE/PCK/data/native、漂移均拒绝；完整运行要求三角色同 source_fingerprint、三个不同 PCK。
- `client` 直接运行 manifest 中的正式 EXE 主入口，窗口模式、原 opening；无 `--script/--path/--scene`，自然 `--quit-after 180`。只证明启动/正常退出，不等于 GUI 操作或正式客户端 RSA 验收。
- `server` 复用 round53 的独占 Windows Job/console IPC、round54 的 RSA 客户端、READY、空大厅状态保存关闭、worker exit0、原网关进程句柄释放、正式 stop、网关 exit0/owned Job active0。先读取原始可信本机 `status`，保留七个旧字段，严格检查四类十三方法、已应用 enabled=true/budget15、pool20。旧包缺这些字段就红，不向旧包注入新源码。只有新冻结包才应运行整链。
- RSA 仍是**既有 editor 场景诊断器**，不是 release client；`all` 也不将其冒充正式客户端 GUI/RSA。未来 build 成功时会从同一导入副本生成独立 `rsa-fixture` 和绑定其源文件 SHA 的 manifest；不写正式源码，不将诊断器装入 PCK。只允许该独立夹具的 `.godot` 缓存变化，源文件集合保持严格相等。
- `status` 仅对显式既存 console_dir 发正式 `status`；不接管既存 gateway、不 stop、不建立 worker、不赋予既存 PID Job 所有权。
- 信令复用 round53 的 `traffic/negative_contract/run` 和 `signaling_prepare.production_ready`。缺配置要求精确 exit2、两条已知 ERROR 和真实 core scope、无 READY；配置运行要求真实 create/join/offer/answer、四种游戏消息拒绝、native READY、精确自有控制台 CtrlBreak、自然 exit0、完整尾日志无 ERROR。不是另造协议。
- `NOTRUN` 永不升级成 PASS；未知 phase exit2。失败保存原始 exit_code/raw_exit_code、日志、精确 PID/绑定；不重试失败阶段。READY/未知 server 不强杀，失败后保留新自有 PID。既存 28100 完全未接触。空自有 gateway 的 status 前置检查失败时，只有正式 rooms=[] 才尝试正常 stop。
- 不宣称新 Job/cleanup DLL 发布。原生产 DLL 仍为 `92a42bd...`；新编译候选未推广，temporary_cleanup=false。

结果分类区分阶段成功与整链准入：本入口最多 `PARTIAL_NOT_THREE_ROLE_PASS`；失败为 `FAIL_OR_PRESERVED_PROCESS`，未完成为 `INCOMPLETE_NOTRUN`。legacy inventory/build_plan 中完整正式客户端验收的 NOTIMPLEMENTED/false 保留作兼容准入边界，并新增 `executor_status=IMPLEMENTED_NOTRUN`；它不再阻止实际 phase 执行。

## artifact manifest schema

未来此工具 build 成功生成的 `manifest.json` 可直接作为运行输入；每个 role 行增加 `native_files`、`data_files`，signaling 行增加显式 declaration。文件映射都是包内 POSIX 相对路径→小写64位 SHA256：

```text
roles.<client|server|signaling>:
  package: 实际物理 E 盘目录
  declaration: {role, platform: windows, preset, executable}
  source_fingerprint: 同一获批冻结来源 SHA256
  package_files: 包内全部文件的精确集合和 SHA256（含 exe/pck/data/native）
  native_files: 全部外置 DLL，以及信令外置 gdextension 的精确子集
  data_files: client/server 全部 data/ 文件；signaling 必须 {}
rsa_fixture:                         # server/all 必需，build 自动产生
  project: 独立同冻结 editor 夹具路径
  manifest: rsa-fixture-manifest.json
  manifest_sha256: 精确文件 SHA256
  files_fingerprint: 源文件集合 fingerprint
```

`rsa-fixture-manifest.json` 为 `{source_fingerprint, files, kind}`。fixture 的源文件（排除 `.godot/`）与 files 完全一致；既有 `round54_authenticated_client.gd/.tscn` 必须匹配原诊断文件。`--rsa-project/--rsa-manifest/--rsa-manifest-sha256` 可显式传入，但不能覆盖 artifact manifest 的绑定；省略时仅消费 manifest 声明，不猜目录。

单项诊断允许 manifest 仅含所选 role，因此不将旧 client/server 与不同来源 signaling 拼成同冻结三角色。本轮单角色 manifest 明确标为 `EXISTING_IMMUTABLE_SIGNAL_ONLY_NOT_SAME_THREE_ROLE_FREEZE`。

## 本轮仅一次真实运行

输入：`E:/Caches/Hermes/cache/scratch/round64-runtime-inputs-sa1/artifact-manifest.json`，SHA256 `74d365b52c787b4a163093056701d02dd5ee2d8573c69e1669b1978c08a6f349`。

只读复用 round53 已有不可变 signaling 候选（未重导出）：EXE SHA `d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562`；PCK SHA `c0d37d2e400db1ae0c23b6bc29bc37047f8a01721d2d236d1ae2551cd34c2119`；原 DLL SHA `92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd`。只在独占 E runtime 根生成无凭据本机信令配置，没有改包内 signaling.json。

```bash
python -B tools/release/round56_three_role_freeze.py --run-formal \
  --artifact-manifest E:/Caches/Hermes/cache/scratch/round64-runtime-inputs-sa1/artifact-manifest.json \
  --artifact-manifest-sha256 74d365b52c787b4a163093056701d02dd5ee2d8573c69e1669b1978c08a6f349 \
  --run-phase signaling-ready \
  --root E:/Caches/Hermes/cache/scratch/round64-signaling-runner-proof-sa1 \
  --approved-root E:/Caches/Hermes/cache/scratch \
  --signal-runner E:/FateCandidates/round53-signaling-runtime-entry-sa1/diagnostic-tools/runner.exe \
  --signal-runner-sha256 6d4e5e6bb6ada3020513c3159660aee824435b15e09249cf920074a40ae75ded
```

真实退出码0；仅 signaling-ready=PASS，其余四阶段 NOTRUN，formal_exported_client_RSA=NOTRUN；总体 `PARTIAL_NOT_THREE_ROLE_PASS`。create/join/offer/answer 全真，game/save/rules/match_command 全拒绝，CtrlBreak sender=0，engine PID22124 正常 exit0，keeper PID31456 正常返回，无 timeout/ERROR；完整包读回仍精确一致。后置两 PID 均 OpenProcess error87/不存活；这只是后置观察，正常退出由自有调试器 EXIT_PROCESS 回执证明，不倒推不存在的 Job active0。

证据：
- `E:/Caches/Hermes/cache/scratch/round64-signaling-runner-proof-sa1/formal-runtime.json`，SHA `a81a9f47e0ebc4e998005517724b1db881959621667b29e67da9a74bf14ee72e`。
- 同根 `signaling-ready/actual-exported.log`，SHA `31d598f14c22589900fb49c59a8791b11401ac41c27bb534eda3d4b97dceb273`，及实际 sender/result/readback.json。

此命令是已执行记录，原 root 已存在，不可原地重跑。只证明 runner 路线可用，不是新 source 的最终冻结、三角色整链或所有后续编辑字节的运行证明。之后的清单/前置门强化由 Python 单测覆盖，没有追加第二次真实阶段。

## 主代理最终冻结、真实 build 后的可执行命令

本轮没有稳定的新 source/完整 headless 依赖/ready token，**没有执行 build/export**。主代理应先按原有五依赖 ready-token gate 完成新冻结和真实 build，不能复用旧报告或失效 token；build 成功会产生上述可直接消费的三角色 manifest 及 RSA 夹具。以下 Bash 命令要求调用者显式设置真实已生成的 `FREEZE_MANIFEST`，不是伪造报告或自动批准：

```bash
: "${FREEZE_MANIFEST:?请设为主代理最终获批build生成的实际manifest.json}"
MANIFEST_SHA=$(python -B -c 'import hashlib,sys; print(hashlib.file_digest(open(sys.argv[1],"rb"),"sha256").hexdigest())' "$FREEZE_MANIFEST")
python -B tools/release/round56_three_role_freeze.py --run-formal \
  --artifact-manifest "$FREEZE_MANIFEST" --artifact-manifest-sha256 "$MANIFEST_SHA" \
  --run-phase all \
  --root E:/Caches/Hermes/cache/scratch/round64-main-formal-after-final-freeze \
  --approved-root E:/Caches/Hermes/cache/scratch \
  --godot D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe \
  --signal-runner E:/FateCandidates/round53-signaling-runtime-entry-sa1/diagnostic-tools/runner.exe \
  --signal-runner-sha256 6d4e5e6bb6ada3020513c3159660aee824435b15e09249cf920074a40ae75ded
```

信令 helper 只读复用已存在的自有控制台诊断执行器，不重新编译、不替换发行 DLL。每个子进程预算为既有180秒；完整 all 外层预算至少保留多个子进程及归档余量，不用180秒外层截断整链。首次非零/READY/stop失败立即停后续阶段，不能加预算重跑或强杀旧gateway。

安全只读 status 可单独用 `--run-phase status --console-dir <显式既存console目录>`；新输出仍必须是未存在独占 E 子目录。旧包没有新 native/status 字段应 FAIL，不会自动补源码。

## Python 验证

显式 TEMP/TMP/TMPDIR=物理 E scratch，执行：

```bash
python -B -m unittest tools.tests.test_round64_release_runtime_entry tools.tests.test_round56_three_role_freeze tools.tests.test_round53_signaling_initialization -v
```

34/34 PASS，exit0。其中新增专属10项覆盖缺显式 manifest、假 artifact、缺 role、SHA 漂移、同fingerprint下跨角色native漂移、不支持 phase、非零原值保留/NOTRUN不可PASS、原 status/native/15/20、正式 client 无覆盖参数，以及信令非零执行边界。单测的合成数据和 mock 均仅用于 Python 断言，不作为运行时证据。

尚未验收：新冻结 client opening、server新status及RSA→workerREADY→room_state_saved→stop、新信令缺配置exit2、同冻结三角色实际运行、正式release客户端认证/GUI、对局save/恢复、跨机跨网、新native生产推广。旧包 stop 接缝红项仍以 round54 原证据为准，未新建一个可能无法关闭的旧server。
