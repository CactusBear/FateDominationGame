# Native 缺失必须 UNKNOWN / deny：真实 Godot 契约专项

## 交付与结论

新增且仅写 `newtests/`：
- 测试：`cleanup_native_failclosed_contract_test.gd`
- 场景：`cleanup_native_failclosed_contract_test.tscn`
- runner：`run_cleanup_native_failclosed_contract.py`
- 汇总证据：`cleanup_native_failclosed_contract_evidence.json`
- 本报告：`cleanup_native_failclosed_contract_report.md`

复用 `round74_cleanup_handoff_contract_test.gd` 的显式 TestRegistration / TestLease，真实调用现有 `ledger.preview_proven → Collector.collect → Policy.select → Collector.revalidate`。没有第二 registry，没有修改生产代码、编译/替换 DLL、硬编码 PID 集合、删除任何文件或启用生产清理。所有产物及环境重定向到独立 E:/scratch；Godot 实际 user_data_dir 也经过读回校验。未跑全量、测速或窗口，未操作外部进程。

## 同一冻结输入的真实运行

命令前缀：`python -B newtests/run_cleanup_native_failclosed_contract.py`。
每次实际 Godot 命令包含 `--headless --fixed-fps 60 --path <E 隔离项目> --scene res://newtests/cleanup_native_failclosed_contract_test.tscn`。看门狗为 300 秒，全部自然结束，未触发终止。

| 参数 | CHECK | Godot / runner exit | ERROR（含 SCRIPT ERROR） | 自有 fixture Job0 |
|---|---:|---:|---:|---|
| 无参数，正式旧 DLL 副本 | 27/27 | 0 / 0 | 0 | true，ActiveProcesses=0 |
| `--without-native`，不提供任何 native descriptor | 27/27 | 0 / 0 | 0 | true，ActiveProcesses=0 |
| `--mutation binding` | 23/27，四字段错配被抓住 | 1 / 1 | 0 | true |
| `--mutation unknown` | 23/27，四项 UNKNOWN 降级被抓住 | 1 / 1 | 0 | true |
| `--mutation active` | 26/27，漏计 active 被抓住 | 1 / 1 | 0 | true |
| `--mutation epoch` | 26/27，忽略 member epoch 被抓住 | 1 / 1 | 0 | true |

四个 RED 均只改冻结 collector 副本中的单个门，非生产缺陷、非解析失败；GREEN 用未改 collector。六次最终测试/场景/runner、collector/ledger/policy 来源 SHA 相同；逐次 source 前后 SHA 全部不变。被拒 artifact 与 ledger 独立重开并校验 SHA，removed_files=0。

最终原始证据根（每个都有 `freeze.json`、`godot.stdout.log`、`godot.stderr.log`、`verification.json`、`project/result.json`）：
- GREEN 旧 DLL：`E:/scratch/cleanup-native-failclosed-631425612e3a404391e7f0cf83b1df87/`
- GREEN 无 native：`E:/scratch/cleanup-native-failclosed-e5d9294b8ded46daa98e3f440291b080/`
- RED binding：`E:/scratch/cleanup-native-failclosed-5805581a8556424485e072d7419a06a7/`
- RED unknown：`E:/scratch/cleanup-native-failclosed-01534d55f9d64b0c87d6b07def38017f/`
- RED active：`E:/scratch/cleanup-native-failclosed-52fa7c5f020b42efbd33c51ff1b5c952/`
- RED epoch：`E:/scratch/cleanup-native-failclosed-7efd94e191ff441bab953be24ab7cffc/`

早期两版运行原件也完整保留；不拼入上述最终冻结验收，不清理任何目录。

## 四类错配与真实返回

1. **身份错配**：room / pid / instance_id / authority_host_mode 各自错配，返回 `ok=false, error=member_binding_or_generation_changed`，没有 candidates 或 lifecycle_proof。
2. **能力/状态缺失**：member identity/state UNKNOWN 与 missing_native 注入返回 `unknown_process_identity_or_state`；无 registrar 返回 `missing_registration_capability`；纯元数据对象返回 `missing_registration_capability:cleanup_registration_contract`；缺 lease 返回 `missing_deployment_lease`。全部 deny，未从 optional 缺失推导 RELEASED/安全。
3. **仍有 active 进程**：binding 使用运行中 Godot 自身的 `OS.get_process_id()`，并由真实 `OS.is_process_running` 确认；契约 member 的 RUNNING/HELD/ACTIVE 进入 current_instances，现有 Policy 拒选 `current_instance`，planned_files=0、candidates=[]。这是 **KNOWN_ACTIVE / deny**，不是把已知活跃篡改成 UNKNOWN。EXITED root 但 job ACTIVE 则返回 `exited_handles_not_released`。
4. **epoch 漂移**：member lease_epoch 错配直接拒绝；selection 与 revalidate 之间 lease epoch 漂移、registry generation 漂移返回 `lifecycle_proof_changed_between_steps`。同值但换 registrar 对象或 lease 对象也拒绝。

生产结果没有 `status=UNKNOWN` 字段：本报告的 UNKNOWN 表示“不可用于安全资格的未知证据”，实际断言的是上述生产 error / 无候选 / policy reject；未捏造新生产返回 schema。

## 哪个来源的证据才能进入既有 eligibility

唯一既有受证入口为 `ledger.preview_proven` 显式注入的可信本机能力与 lease，需全部满足 collector 现有合同：
- registrar 来源为 `authoritative_ownership_boundary`，登记边界为 `before_start_until_all_handles_released`。
- 完整 scope、registry_generation、独立 canonical 成员见证；枚举不能用自己的 entries 自证 expected 集合，无 unknown writers / pending registrations。
- 每个 member 精确绑定 room/pid/instance/mode、同 lease_id/epoch/generation，verified identity、已知 process/handle/job 状态。
- 所有 scope writers 受同一跨进程独占 lease 约束；selection 前后重新读取并比较 contract、enumeration、member、lease 及来源对象身份。
- 合格的 native release 证据还必须出自实际拥有该完整 binding 的原生所有者的可验证读回；方法存在、单 PID 的 state、closed history、旧 bool、字符串或 fixture Job0 均不可替代。

**这里不是在认证任意 provider。** collector 只检查合同/一致性，可信组合根仍须审计并提供真正的生产 registrar / native source / 跨进程 lease。测试中的正向 CLOSED/RELEASED/EMPTY_RELEASED、consumed 台账和成员见证都是显式契约夹具，不是生产事实。正向夹具只证明既有 eligibility 可达，且仍 `blocked=true, diagnostic_only=true, cleanup_execution_lease_unwired`，不证明删除授权。

## 实际 native 观察及尚缺口

真实旧 DLL 副本由隔离项目启动时加载：ClassDB 显示 FateProcessOwner 存在、state 存在、**tree_observe=false**；无 native 的对照项目则 class/state/tree 均不存在。两组观察都为 UNKNOWN，不可提供 release readback。观察器只查 ClassDB 元数据，不 instantiate、显式加载扩展、调用 native 方法、spawn、terminate 或 release。此前 state=-1 属历史专项结果，本轮未重新执行 state 查询，不将历史值写成新实测。

真实 native 元数据 → member UNKNOWN 采用显式测试注入，只验证现有 collector / eligibility 的 fail-closed 合同，**不宣称生产 native→registrar 适配链已验证**。

Job0 是 Python runner 在启动前登记自有 suspended Godot 进程的 Windows Job 的真实 ActiveProcesses=0；不是 FateProcessOwner 的生产 Job0，也不是 native 句柄释放证明。生产 Job0 保持 `UNKNOWN_NOT_OBSERVED`。

只读搜索 `scripts/` 未找到生产 `cleanup_registration_contract / cleanup_enumerate / cleanup_verify_member / cleanup_lease_observe` 实现；`preview_proven` 仅在 ledger 自身定义，正式 console 仍走普通 `_cleanup_ledger.preview(...)`。因此仍缺：
1. before-start 至全部句柄释放的生产 canonical 完整 registry 和独立成员见证；
2. 已绑定实际 native owner 的 release readback 及适配链（旧 DLL 缺 tree_observe，源代码有方法不等于 DLL 已部署）；
3. 覆盖所有 scope writers 的跨进程文件 lease；
4. 全程持租约、intent/recovery、执行器的生产接线。

生产清理继续禁用。本专项只验收负向契约与诊断资格边界，不能签收 F15/F16 全链路安全删除。
