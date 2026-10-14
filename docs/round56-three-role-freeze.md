# Round56：同源三角色冻结准备（不是 source/runtime PASS）

## 本轮结果

- 新增 `tools/release/round56_three_role_freeze.py`，仅 Python inventory/preflight 与未来构建接线；未启动 Godot、未导出可变源码、未更换正式 DLL。
- `--build` 已调用真实现有 API，但**本轮没有执行 cold/import/export，尚无本轮新 EXE/PCK 生成证明**。完整正式三角色 runtime 编排明确 `NOTIMPLEMENTED`；`--run-formal` 退出 3，不伪造可运行验收命令。
- 主代理尚未签发 ready token。真实无 token 调用返回 `BLOCKED / READY_TOKEN_REQUIRED / exit2`，精确目标目录不存在。不得把本报告、inventory 或 Python unit GREEN 当成冻结许可。
- 原 DLL SHA 保持 `92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd`；新 core 始终 `production_blocked=true`、`claim_new_job=false`、`unreleased`。

## 耦合与作用范围

只新增独立编排器、单测和报告，不改 `release_prepare.py`、`freeze_prepare.py`、`runtime_audit.py`、`signaling_prepare.py`、游戏生产源码或 native source/bin。

复用已经亲读且 Python signature 绑定验证的实际接口：

- `freeze_prepare.inventory(..., cold=True)`、`transform`、`contract_text`；
- `round52_current_role_candidates.run/save/environment/transformed_presets`；
- `release_contract.copy_runtime`、`package_audit.audit/manifest`；
- `signaling_prepare.prepare/audit`。

没有调用旧 round52 `prepare()` 生成旧式自动发现 native 的信令包，没有把旧 client/server 产物复制进新总 manifest。

## Inventory 与生产闭包

运行闭包按真实三个角色 inventory 读取。每个文件独立 SHA；同一总 fingerprint 还绑定 native C++/头文件、SConstruct/build_profile 和实际复用的 Python 工具源码。**SDK/历史 build cache 不属于游戏运行闭包，也不要求 headless 把 SDK 当运行依赖。** `role_files` 与 `native_source_files` 分列，fingerprint 不等于“这份 C++ 已在正式 DLL 中”。

采样回执 `tools/tests/round56_preflight_inventory_evidence.json` 记录：client/server 各 1424 项，signaling 12 项，总来源 1450 项；正式配置 `enabled=true / budget=15.0 / pool=20`。这是采样，不是主代理最终冻结标记；并行源码/工具继续变化后必须重算。

真实 Round54 observation manifest 仍可读，但本次比较其 `server_room_manager.gd` 和 `assets/config/server.cfg` 与 current source 不同。不能按报告文件名、日期或过去 exit0 升级为当前来源已验。新 status view/关停 handoff 必须进入新导出。

## ready token 与自动前置

主代理在全部 owner 完成后显式提供 JSON token；模块不会自行生成批准：

- `schema: 1`、`approved_by: "main"`、`freeze_ready: true`、`claim_new_job: false`；
- `source`、`approved_root`、`root` 均为主代理明确批准路径；root 必须是尚不存在、无链接/junction 的物理 E 新独占子目录，不能重用旧失败 cache；
- `source_fingerprint` 精确等于当前 inventory；
- 必需 dependencies：`runtime_observation`、`shutdown_handoff`、`gui`、`current_headless`、`native_compile`。

每个 dependency 明确声明 `path`、`sha256`、`source_pointer` 与 `checks`。`source_pointer` 是实际 JSON Pointer，支持源 SHA 字典或隔离 runner 的 `[{path,sha256}]`；不凭 report 中字符串“完成”推断源码匹配。checks 每项为 `{pointer, equals}`，精确类型比较，普通依赖必须明确实际 exit0 及空 errors/failures/error_lines。报告缺失、摘要改变、必需源码不匹配或任一检查失败立即拒绝。主代理必须选择真实完整验收结果，不能挑一个 import exit0 冒充 GUI/host 链；完整报告摘要被 token 绑定。

`current_headless` 另外提供 `headless_steps`，恰含 `selection_ready` 和 `required`。每项声明 `exit_pointer / errors_pointer / freeze_pointer`，两个独立 exit 必须为 0、errors 空、freeze 绑定同一非空身份。不能仅有 selection-ready，也不以 tight fixture 不存在为忽略 required 的理由。普通源码覆盖检查采用完整 client 生产运行闭包，不含 SDK。

preflight 前后重验 source 与 token；build 开始重复 preflight，每一步前后重验 source/report/token。GUI/headless GREEN 不会令 import/export ERROR 被忽略。

## 原 DLL 与新编译产物分离

真实只读 native 编译回读见 `tools/tests/round56_native_compile_readback.json`：

- `E:/FateDiagnostics/round55-native-build-20261010-4/manifest.json`，SHA `9f4477278dcc71967adbb675db692b4b67ebfaae4e94da7b2cdb0fa5864c78ac`；
- 当前 8 个 cpp/4 个头文件 SHA 匹配；实际独立 DLL 452608 bytes，SHA `58b49cfc027bb292f7e335128f41a48213834eb84eb9745ed7034bfd063f5ca0`；
- 正式 bin 仍原 DLL，新 DLL 没推广。本回读不加载它；runtime 由主代理指定的唯一 actor 另验，不能混成候选新能力。

native dependency 使用真实 `/sources`，并明确提供 `compile_steps`（每个 cpp 相对路径 → 实际 commands 数组 index）和 `link_step`。必须覆盖所有实际 cpp、选取不同记录、exit0、实际输出 SHA/PE 声明一致；原始失败记录不删、不覆盖。原生源码/hash 未匹配就拒绝当前编译依赖，而不是声称新 Job 已发行。

本报告不是按 stage 名猜“最新成功”：readback 附完整显式选择，最终 link 指向 index22，而原 index17 `plugin-link` 是1120失败，不能拿它作成功。已验证记录的 raw log SHA；后补记录没有 raw_sha256 时按报告 `command_files` 摘要读回真实 cmd。独立 compile SDK 与旧包运行来源始终分开。

SConstruct/build_profile 保留在总来源 provenance 中，但不能伪称手工 cl 编译已消费它们；native 编译匹配范围仅 actual cpp/头文件。`source_to_production_bin_match=NOT_ESTABLISHED` 永不静默改成 true。

## 主代理稳定后的命令

先执行只读 inventory（输出完整源 SHA；不是批准）：

```bash
python -B tools/release/round56_three_role_freeze.py --inventory
```

以下环境变量必须由主代理显式填写，尤其新 approved E root 和 ready token；未设置时 shell 本身拒绝。**本轮不执行以下 build。**

```bash
python -B tools/release/round56_three_role_freeze.py \
  --source E:/Projects/Godot/FateDominationGame-master \
  --root "${NEW_E_ROOT:?main必须指定新独占E目录}" \
  --approved-root "${APPROVED_E_ROOT:?main必须明确批准根}" \
  --ready-token "${READY_TOKEN:?main必须签发当前冻结标记}" \
  --godot "${GODOT:?原官方editor路径}" \
  --templates "${TEMPLATES:?原官方四个Windows模板目录}"
```

该 preflight 成功才输出实际 `build_invocation` argv；附 `--build` 才会执行。构建还强验原官方 editor、四模板和原 DLL 摘要。没有通过 token 的可变树不会进入复制/import/export。

构建从一份逐文件原字节 `source-snapshot` 派生 client/server 和纯信令投影；记录变换及 SHA。game 两角色保留原 descriptor/editor 加载行为；signal 仅使用既有 external native descriptor/runtime supported 初始化，不提供诊断 PCK、不对正式 EXE 使用 `--script/--path` 覆盖。三套 EXE/PCK 各自静态审计、强制 native 部署资产和新 status/handoff 脚本入包检查；总 manifest 要求相同 sourcefingerprint、三个不同 PCK。首次 cold 或 export 任一非零/ERROR 即保存原件停止，无暖重试。

复用 round52 的有界 import/export 子进程执行器；它不是新 C++ Job runtime 树证明。未来运行验收必须另用真正 owned runner，不能从构建退出推认 worker 树归零。

## 实际 Python 验证与限制

最终命令/原始 stdout/退出码在 `tools/tests/round56_python_verification_final.json`（15 tests，exit0）；前一阶段14项记录在 `round56_python_verification.json`。全部仅 Python、fixture 根为已 resolve 的 `E:/Caches/Hermes/cache/scratch`，fixture 随测试退出回收。

```bash
TMPDIR='E:/Caches/Hermes/cache/scratch' TEMP='E:/Caches/Hermes/cache/scratch' TMP='E:/Caches/Hermes/cache/scratch' \
python -B -m unittest tools.tests.test_round56_three_role_freeze -v
```

有效 RED 记录：最初 missing-ready 拒绝实现不存在时1项断言失败；后续 source/dependency inventory 缺失时10项断言失败（不能冒称十个分支逐一 mutation RED）；same-source plan 缺失时1项断言失败；已实现 gate 对缺编译产物的反例曾“ValueError not raised”真实 RED；headless 两步错冻结也曾“ValueError not raised”真实 RED。修复后全套 GREEN。wrong sourcehash、旧 DLL 冒称新 Job、不可读 status、缺 handoff、旧根复用、缺 mandatory native 均有独立拒绝单测。

不做本轮 EXE runtime PASS：正式 client RSA/本机 status 四类13方法及15/20/真实 room save-close-stop/signal handshake/negative exit2 尚无本轮整条执行器。旧 `runtime_audit.py` 对 signaling 缺配置仍假设 exit1，未调用它来伪造 exit2 验收。已有 round54 runner 固定旧 parent 且使用 editor fixture client，不能直接重命名成正式客户端验收。

## 后续仍需主代理完成

等待 owner 交付后亲读 GUI tight-event、shutdown handoff、两步同冻结 headless 的真实报告和 declared SHA；据 current source 重算并签发 token，再执行新构建。新 native actor 自己的 runtime 证明独立保留，不更换此次原 DLL 候选。新导出与完整正式运行验收都未在本轮执行，故没有整体 PASS。
