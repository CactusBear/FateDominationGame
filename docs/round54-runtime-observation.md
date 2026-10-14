# Round54：可信本机 status 的真实只读运行观察

## 结果与边界

- 修改既有 `scripts/net/server/server_console_channel.gd`，新增 `scripts/io/native_capability_view.gd`。未修改 bootstrap、manager、CLI、shutdown、native source/bin、release gate 或旧测试。
- 使用原命令 `status`，七个旧字段保持原表达式和值，额外仅 `native_capabilities`、`validation_policy`、`worker_pool` 三个字段。
- 真正生产 CLI 在独占 E 盘隔离源码项目内启动，原 console 文件 IPC 返回四个已注册且可实例化的类、十三个存在的方法；已应用 manager data 分别读回 15 与合法 61.25。两个 CLI 均通过正式 `stop` exit 0；自有 Job 的 ActiveProcesses 均为 0，生成树已回收，原始日志/回执保留。
- **这是源码 headless 运行证明，不是 release 包运行证明。父代理若要采集候选 artifact 的 runtime，必须重新导出此源码再通过同一个原生入口采集。旧 PCK 不含本改动，不能追认。** 没有为 release 放宽 `--script`/`--path`，没有新增正式 PCK 测试入口；没有 GUI 验收。

## 耦合与合同

`NativeCapabilityView.observe(method_contract)` 仅接收调用方明确声明的合同，调用 ClassDB 的 `class_exists`、`can_instantiate`、`class_has_method`。不创建 native 对象、不加载扩展、不调用被观察方法、不接管信号、不 spawn/terminate，不读取 manager/GlobalRoom，也不写 data。

bootstrap 的 `_load_signaling_native` 将四类十三方法保存在局部变量，不能不修改 bootstrap 就从其他脚本直接读局部变量。本轮采用允许的**显式注入**：console 单处声明该合同；纯组件不含名单。测试执行器亲读冻结 bootstrap 与 console 源码并比较字典完全相等，防止列表漂移。生产观察不解析源码。

已亲读 `server_signals.cpp`、`process_owner_binding.cpp`、`atomic_file_replace_binding.cpp`、`collection_identity_binding.cpp` 的正式类与 `_bind_methods`。bootstrap 的十三方法均由 wrapper 声明；当前 C++ source 的额外 `tree_observe`/`remove_verified` 不属于该合同，本轮不宣称旧 DLL 已包含它们，也不更换 DLL。

`validation_policy` 只读取 `gateway.manager.data_settings` 中 `random_sim_enabled` 与 `random_sim_budget_sec`，返回仅 `enabled`/`budget`。缺失或类型畸形为字符串 `unknown`，没有默认 15、配置文件 dump、密钥或额外字段。数字原样保留，0 也是现有合法声明，观察不再施加重复政策限制。15 来自 CLI 真正已应用的 JSON data，不是观察器默认值。

`worker_pool.max_threads` 读取 ProjectSettings 声明，本冻结值为 20；不声称实时线程数、利用率或实际占满池。

`status` 加入既有 trusted-local 拒绝门。gateway 既有网络管理员转发使用 `admin_console.execute(command,false)`，因此不能执行本机诊断；实例绑定的 console IPC 才走本机可信路径。未开放新网络消息种类。测试覆盖真实 `execute("status",false)` 拒绝，未将其称为完整网络管理员认证握手。

观察不是授权 proof：没有输出 `complete_registry`、`exclusive_files` 等虚假的能力布尔。已消费保存台账的两个候选依然 `blocked=true, removed_files=0`，缺登记全集与跨进程文件互斥能力仍明确缺失；ledger SHA、请求和回执均保留。

## 有效 RED → GREEN

最初有效 RED 位于 `E:/scratch/isolated-6786fcbeca574999ae3026ad26b1fa4f/manifest.json`：新合同只因缺 native/policy/pool 与未拒绝非可信 status 三项失败，exit 1。该轮旧 channel 因隔离夹具漏 WebRTC 依赖超时，**不**作为旧回归通过依据。

随后在隔离副本恢复与首次 RED **字节 SHA 完全一致**的旧 channel，保持正式源码不回退，补齐真实 WebRTC 依赖后复验：

- `E:/scratch/isolated-cf97016f9a184b0dbcbed94b971c7596/manifest.json`
- 原 channel 25/25，exit 0；新合同 20 checks、恰好三项预期失败、exit 1。恢复不是近似旧实现，隔离写入前强验 SHA。
- 合法零预算另有有效 RED：`E:/scratch/isolated-851252d6b02f4dd68b0ce596e45aab81/manifest.json`，41 checks，仅零预算限制失败，原 channel 25/25。

最终同一冻结：`E:/scratch/isolated-0e410d7575e24a6e954f3e7e05c7ac01/manifest.json`。

| 阶段 | 实际结果 |
|---|---|
| cold resource import | exit 0，无 SCRIPT ERROR/ERROR |
| 新 runtime observation contract | 47 checks，failures=[]，exit 0 |
| 原 net_server_console_channel_test | 25 checks，failures=[]，exit 0 |
| 真正生产 CLI / console IPC，data=15 | registered 四类、十三方法存在，budget=15.0，旧七字段等价，错实例拒绝，stop 后 exit 0 |
| 真正生产 CLI / console IPC，data=61.25 | 同样通过，budget=61.25，stop 后 exit 0 |
| 所有自有 Job 收尾 | ActiveProcesses=0、日志句柄释放、generated_removed |

新合同还验证：空合同不猜类名；ClassDB 真实内置类/缺类/缺方法；缺策略为 unknown；半声明不补齐；非法布尔/非有限数不强转；额外 secret 哨兵不外泄；旧 saved/room_state_saved 判断不变、文本 true 不作为保存证明；错误 binding 仍 UNKNOWN；未配置 cleanup 不启用；已消费台账仍被阻断且 SHA 不变。

窄 saved/UNKNOWN/台账检查与零房间 CLI 正式 stop，不等价于重新跑全部真实 authority worker 保存失败/恢复/多人网络专项。

## 命令与精确证据

```bash
PYTHONDONTWRITEBYTECODE=1 python tests/runtime_observation_runner.py --phase exact-old-red --baseline-channel-sha 91ebbc0632def2a5a0b537e75752b23dd1547eb72c77aa868fae98c27715a240
PYTHONDONTWRITEBYTECODE=1 python tests/runtime_observation_runner.py --phase final-locked --ipc
PYTHONDONTWRITEBYTECODE=1 python tests/runtime_observation_source_proof.py --red-manifest E:/scratch/isolated-6786fcbeca574999ae3026ad26b1fa4f/manifest.json --green-manifest E:/scratch/isolated-0e410d7575e24a6e954f3e7e05c7ac01/manifest.json
```

执行器复用只读 `tools/run_isolated_godot_test.py` 的挂起创建/Job 拥有/预算/退出归零/清理原语，每进程 180 秒，上层 tool 600 秒。独占生成根、APPDATA/LOCALAPPDATA 与夹具均位于物理 E，正式 data 只作为已批准只读根，所有 storage/console 在独占根内。没有名称扫杀或全局环境修改。

隔离副本转换显式记录：移除 MCP helper/VCS 自动启动/编辑器插件，渲染器改 gl_compatibility，删未包含主场景；先无 autoload 导入资源，再恢复真实业务 autoload，场景运行携带已有 `--server-gateway` 抑制游戏数据自动加载。保留 application user-dir 与 threading 设置。不是发行导出设置。

最终 evidence 中：

- `production-ipc-15.status.json` SHA-256 `e256c2351ceea49b1f97e6b2b2c158fb298fd99179ee9a674514bd2a400f2c35`
- `production-ipc-61.25.status.json` SHA-256 `9f4f83180b7ad35a7dceddb3858966ad95a6a343d9bf4f4e26196a995246afab`
- `readonly-source-proof.json`、`readonly-source.diff`：逆向恢复原 channel 后 SHA 与有效 RED 完全一致，证明除 import/显式合同、trusted-local status 门与 `_status` 三处外所有 channel 字节不变；最终冻结所有来源 SHA 与当前源码一致，drift=[]。

| 来源 | SHA-256 |
|---|---|
| 观察前 channel | `91ebbc0632def2a5a0b537e75752b23dd1547eb72c77aa868fae98c27715a240` |
| 当前 channel | `9eea95ad15fc0f4e04c3d9edfe0071a523e1f44a23558b324ceab818de16da02` |
| 新 native_capability_view.gd | `e24b24228589e9cf68b59b91dae7fa1b80b6586f618726be26e37325964671ba` |
| bootstrap（只读） | `77b86fec2477de5ccddcd8e95cc6556cbadf872b67f5b4eca1d251a68be2f56b` |
| manager（只读） | `65a19312d7e3afbeed6dd238d03bf4437613ad9e915555c4316a58f8091cdddb` |
| CLI（只读） | `8ecc943bd496ef2c85e16e66c3495a6b37b63818d56e94e2e398c0a94ddfaf6a` |
| shutdown（只读） | `620b9c7ff62f02cbb25a45f18a6db626f23d720ea987baf277e9a78018efaa76` |
| 原 release DLL | `92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd` |
| 原 editor DLL | `a5990f5eeb5023c9f624e505c50cb989e66ab32e4f85b43436bb751aab6d0730` |

Godot 实测为 `4.7.2.stable.official.ed1daf0bf` 编辑器引擎，原 DLL 没有替换；本报告不把编辑器 descriptor 映射的加载证明升级为 release template DLL/PCK 加载证明。

新增测试交付为 `tests/runtime_observation_contract_test.gd/.tscn`、`tests/runtime_observation_runner.py`、`tests/runtime_observation_source_proof.py`。仓库现有 `.gitignore:47` 忽略整个 `/tests/`，这些文件真实存在且已执行，但不会出现在默认 `git status`；本轮未改 ignore 或暂存，后续提交测试需显式处理该既有忽略规则。

首轮失败归档与处理：冷 autoload PNG/无关 shader 导入问题、夹具退出清理回执缺 run_id、漏 WebRTC、测试文案末尾 false 被旧解析器误读、配置夹具使用反斜线被正式路径合同拒绝。修正均限于新测试执行器/夹具，未放宽生产门或旧结果解析器。最初独占树在保留日志后按精确所有权与退出证明回收，额外回执 `E:/scratch/round54-observation-red-75ab022fe2db4a5ba3826ddfa7c7d154/cleanup-readback.json`。