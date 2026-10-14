# Round64 — F15 可选原生删除接缝（生产仍 blocked）

## 结论与写入范围

已移除 `temporary_cleanup_executor.gd` 的 `DirAccess.remove_absolute` 路径，新增单职责 `scripts/io/temporary_cleanup_native_delete.gd`。现 ledger 保持四参数调用、不传能力和批准身份，因此即使已有候选也返回 `native_delete_adapter_missing`，不会删除。没有接 manager 调度、没有扩大启动必需合同、没有改正式 DLL、ledger/policy/manager/CLI/console/bootstrap/native 源码。

这不是“自动清理完成”：完整当前实例登记、跨进程部署排他、历史批准身份生产者、持久化意图与不确定回执恢复均不在本轮接线范围。

测试新增 `tests/round64_temporary_cleanup_default.gd`、`tests/round64_temporary_cleanup_native.gd`、`tests/round64_temporary_cleanup_runtime.py`。仓库 `.gitignore:47:/tests/` 忽略这些测试；已保留本地及 E 冻结，未 force-add、未提交。

## 真实 API 与责任边界

- `FateAtomicFileReplace.remove_verified(approved_root_absolute_path, file_absolute_path, approved_root_identity, parent_identity, file_identity, validated_size, sha256)`：7 参数。identity 为严格 int 的 `{volume,file_index}`。返回 `ok/stage/native_error/removed_bytes/recovery_required`。
- 当前 core 在 NTFS 上固定全部非 reparse 祖先，绑定批准根/父身份；以同一 `GENERIC_READ|DELETE`, share=0 文件句柄验证单链接普通文件身份、大小、完整 SHA，再提交 disposition，关闭并在祖先 pin 未释放时读回。成功 stage 必须是 `deleted_absence_confirmed`。
- `FateProcessOwner.tree_observe(token,pid)` 只查此 owner 已登记的对应 lease；回执包括 token/root_pid/creation_time/local_owner_pid/root_state/active_known/active_processes/total_processes/root_exit_code_known/root_exit_code/release_complete/handles_released。`active_processes=0` 不证明部署全实例完整性，也不证明文件排他。本适配器不调用它、不生成任何 complete_registry/current_instances_complete 许可。
- policy 只选候选与预算；ledger 保留可信来源/消费/保存退出证据及意图；executor 匹配当前候选、显式 native evidence、批准根，再调用注入能力；adapter 只做参数合同和可选 ClassDB 调用。

## 明确可接线接口（未在生产启用）

```gdscript
const Delete = preload("res://scripts/io/temporary_cleanup_native_delete.gd")
# evidence 由 caller 已有历史授权产生，不能在删除前临时 stat 自证。
var evidence = {
    artifact_id: {
        "artifact_kind":"temporary_file",
        "approved_root":approved_root, # 原始规范绝对物理路径，使用 /
        "path":target_path,
        "approved_root_identity":approved_root_identity,
        "parent_identity":approved_parent_identity,
        "file_identity":approved_file_identity,
        "bytes":approved_bytes,
        "sha256":approved_sha256
    }
}
# caller 必须先解决完整登记、部署协调、持久化意图；不是授权生成接口。
var result = Executor.execute(candidates, current_records, config, now,
    Delete.remove_verified, evidence)
```

`execute` 新增可选第五个 Callable 与第六个 evidence 字典，旧四参数调用兼容且阻断。evidence 用完整 artifact_id 索引；path/bytes/hash/kind 必须逐字段等于当前候选，approved_root 必须精确属于 config.approved_roots。缺 evidence、身份非 int、未知种类、非规范/越界路径都在调用前拒绝。adapter 缺 class 返回 `native_extension_unavailable`；旧 DLL 缺 method 返回 `native_interface_unavailable`。没有 remove/rmtree/shell/rename fallback。

adapter 先拒绝 caller 的非法原始输入，再把已验证的 `/` 表示转换为 Win32 `\` 表示，不调用 simplify/resolve。真实 DLL 的 root pin 比较需要 preferred separator；直接传 `/` 曾真实返回 `approved_root_not_pinned`，修的是此消费者接缝，不是 native core。

原生拒绝保留 stage/native_error/recovery_required；未知或非法调用后回执一律 recovery_required，executor 停止本批。原生 false + 缺文件不能追认成功；原生声称成功也须核对 stage/实际字节及再次精确读回。现 ledger 不支持传入这些证据，且其既有完成落账分支尚未接不确定结果恢复，**禁止只补第五参数便启用自动删除**。

## 真实 RED → GREEN 与原始证据

正式引擎：`D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe`；每套 headless/fixed-fps=60，独占物理 E 最小工程与 APPDATA/LOCALAPPDATA/TMP/TEMP/TMPDIR，180 秒等待。复用只读 diagnostics 的精确 Job+GO gate，不触碰其他 actor/observer/锁测试范围。

运行器：`python -B tests/round64_temporary_cleanup_runtime.py --root <fresh E root> --mode green|old|missing`。默认阻断测试的 RED 在改生产前已执行，`--mode red` 仅对应该旧冻结；不能对当前源码使用 red 并伪造通过。

| 阶段 | E:/FateDiagnostics/ 子目录 | Godot 主专项退出码 | 默认专项退出码 | Job 最终 active |
|---|---|---:|---:|---:|
| 有效业务 RED | round64-cleanup-own-red-2 | 1 | 同一专项 | 0 |
| 新 DLL GREEN | round64-cleanup-own-green-6 | 0 | 0 | 0 |
| 旧 DLL blocked | round64-cleanup-own-old-3 | 0 | 0 | 0 |
| 无扩展 blocked | round64-cleanup-own-missing-3 | 0 | 0 | 0 |

RED 是同一 `round64_temporary_cleanup_default.gd` 断言失败：旧 executor 实际删除自建普通 fixture（removed_files=1，33 bytes，读回不存在），期望默认 blocked。GREEN 的同一测试重新执行，默认不删、reason=`native_delete_adapter_missing`，退出 0。不是解析错误或缺 DLL 冒充 RED。

GREEN 原生专项 65 项 CHECK，全部通过；普通 leaf symlink 因 `CreateSymbolicLinkW error 1314` 明确 SKIP，不用 junction 冒充 symlink 通过。旧 DLL 65 CHECK、缺扩展 64 CHECK 均通过各自 blocked 断言。每组独立外部 exact-target readback 16 项均通过：身份/类型/摘要不变；正例 exact target 不存在。Job 最终 active=0、handles_released=true；未终止其他进程。所有有效阶段无 SCRIPT ERROR。

新 DLL 真正删除且仅删除两个自建普通文件：adapter 正例与 executor 注入正例，各 35 bytes；不存在性由 native pinned readback、GDScript 与独立 Python exact-target readback 三处记录。反例真实返回：

- hash 原始证据后同长度内容变化：`sha256_changed`，文件保持变更后的同一摘要；size 错：`size_changed`。
- 根/父/目标身份错误：`approved_root_identity_changed` / `parent_identity_changed` / `file_identity_changed`。
- 自有 Python READ handle 与 DELETE 排他争用：`exclusive_open`、native_error=32，同 target 可打开且摘要不变。
- 硬链接/目录：`regular_single_link_required`；祖先 junction：`ancestor_not_plain_directory`，exact target 及普通子文件都保留。
- 越界、dotdot、未知 kind、缺身份：显式拒绝并读回保留。
- 缺大小/hash/root/三种 identity、非 int identity/size、非 String kind、未知候选、当前实例、evidence mismatch 均拒绝。

`receipt_contract_*` 三项是明确的注入回执合同单测（uncertain、格式错误、假声称成功但 target 仍存在），不是伪造 native 系统调用或真实 disposition 失败证据。

各目录保留 `result.json`、`stdout.raw`、最终三个阶段的 `default-stdout.raw`、`native-report.json`、`fixtures/default-report.json`、`setup.json` 和自建拒绝 fixtures。`result.json` 含真实 argv/退出码/Job、源码 SHA、DLL 前后 SHA、独立 exact-target identity/hash/type readback。失败诊断 red-1（反斜线 fixture 导致错误配置）、green-1（错误 entry symbol）、green-2（真实 separator 接缝失败）、green-3（两个夹具预期错误）保留，但不计有效验收。

## SHA-256 冻结

正式 DLL 前后始终 `92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd`；隔离候选 DLL 前后 `9c14b69f1ccd859b91658e3333ccfd55c51d5d6055ff3861a702bacc75480895`；引擎前后 `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`。

| 文件/回执 | SHA-256 |
|---|---|
| executor GREEN | 2619e8131365435a27f2862a86588aa55b7defa4e592e9bf8e2617a4a3c4acea |
| native delete adapter | 5b8b404ade4af5942977d1af352d67ac3db01ba9ec01b4776c1b04ee81659396 |
| default test | cbbe10bce7a07a3016c5950ac86a9f5c4b5c93d8b21096551125ba4f07da703e |
| native test | d163aeb3ba271a255aeaa6358ddd20d367b89483ca2e5b9628796f6de56443d9 |
| runtime runner | 41b8e4865c021c6c4b45561ddbb031483009f69631eca1b9d153079bfd75d6d7 |
| red-2/result.json | d8f77588103f9df4fc8700d018949751c5da397dac188a682d1f6a6ff070c139 |
| green-6/result.json | b5a9898fc93f5cf2ba6714c76bf5a899bbb5ff28d312de2ed857e07152d736f7 |
| old-3/result.json | 75542d485ea8544fd9e2926fc52a2f495e24005415bee0e47e8c3fe72d25bbfd |
| missing-3/result.json | bc8b4f52d0ee5a828f01667ed59be6de116e51faf5378967b4f543d82a4bf394 |

## 未验收 / 保留阻断

不宣称全实例登记、跨进程部署协调、生产历史身份采集、真实台账/manager 自动清理、真实用户/存档/身份/records 清理、断电事务、窗口或发行整链通过；未访问 28100。没有新增 startup 必需方法。leaf symlink 未获权限；不确定 native disposition 实际失败未注入系统环境证明。拒绝 fixtures 与失败诊断冻结作为证据保留，未扩大删除授权到项目或其他任务产物。
