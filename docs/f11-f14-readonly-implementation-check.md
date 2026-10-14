# F11–F14 逐项核对（只读）

本次未启动 Godot、未操作任何进程、未读密钥/恢复票据。以下判定针对**当前工作树的完整交付**；“部分”区分实际缺实现与缺当前冻结验收，不把 unknown 当失败，也不把历史绿追认为当前绿。

路径简写：`M=scripts/net/server/server_room_manager.gd`；`C=同目录/server_console_channel.gd`；`G=同目录/server_gateway.gd`；`S=同目录/server_shutdown.gd`；`W=同目录/server_room_worker.gd`；`H=scripts/net/session/authority_host_client.gd`。

| 项 | 结论 | 实际源码、测试与运行证据 | 缺什么才能算完成 |
|---|---|---|---|
| F11 运行配额与恢复准入 | **部分实现：代码已落地；当前冻结运行验收 unknown** | `M:_active_runtime_count:196–203` 不计已释放休眠登记，PID/token 未释放仍计；`runtime_admission_error:205–225` 校验当前配额、端口、模式、监督/恢复政策、批准根；`create_room:418–431,474` 不隐式授权，`recover_room:713–753,782–788` 拒绝 UNKNOWN/关闭未决，重新准入、保档。`server_cli.gd:80–101,246–250` 本机显式注入。`server_runtime_admission_test:36–86,125–166` 含政策拒绝保档及真实 create→退出/release→recover→READY；历史 **E1：53 checks，exit0**。批准根测试为 `deployment_approved_root_test`。 | 未发现这些核心门禁缺接线；需当前冻结复跑准入矩阵及真实 worker，不能用 E1 的旧版本替代。此处不把整局恢复 F16 混算为 F11 缺代码。 |
| F12 安全关闭与紧急停止分离 | **部分实现：正常关闭链已有；紧急入口和消费者一致性缺失** | `C:saved_close_receipt:291–295,_poll_room_closes:307–322`、`S:poll:72–125` 已区分保存/绑定/EXITED/release；超时不强杀。`M:poll_idle_rooms:144–190` 复用 close_empty；`G:_detach:442–468,close:538–572` 不因创建者断线杀已就绪/UNKNOWN。但 `H:_drain_close:326–338` 只检查 ok/closing，**未要求 saved/room_state_saved**；`M:stop_room/close/_notification:844–876` 仍可强清理，console/CLI 命令注册中未见独立紧急强停、风险确认和结果记录。`round11_safe_close`/`gateway_disconnect_safe_close` 是替身测试；E3 的真实 owned-worker `pending` **36绿**、`failure` **161绿**，未覆盖 H“closing但无保存”反例；E2 的生产-worker handoff **7项/exit1，卡 READY，未执行保存链**。 | 补独立显式紧急入口与风险/结果；统一 H 保存判据并加缺保存反例；明确析构强清理不冒充正常关闭。当前冻结跑生产 worker 单房/全服/无人关闭→保存回执→EXITED→release→gateway close，含恢复新实例与活动对局；E2 原因仍 unknown。 |
| F13 启动与监督状态分离 | **部分实现：状态分离已落地；当前冻结组合验收 unknown** | `M:poll:511–562` 能力丢失标 supervision_unknown，不清 ever_ready；恢复先验证当前身份，同 ready_binding 不再走旧 deadline；`recover_room:818–827` 真正新实例清历史并新 deadline。`server_runtime_admission_test:7–19,89–119` 的能力丢失/关闭组合使用 FixtureManager；`:168–186` 用真实原生 owner 的错 token 制造 UNKNOWN，再恢复同绑定；`:125–166` 真生产 worker 创建/替换。E1 的 **53绿**实际涵盖上述范围，不等于全组合都是真 worker。 | 当前冻结补能力丢失→恢复、实例替换、关闭监督相互组合的真实 worker 验收；不要把 FixtureManager 的 capability=false 称原生能力真实丢失。未发现核心状态分离缺实现。 |
| F14 心跳故障策略 | **部分实现：策略及生产消费者已接；当前冻结运行验收 unknown** | `heartbeat_publication_policy.gd:29–52` 重试/持续失败；`M:_poll_heartbeat:65–121,_write_supervisor:831–842` 采真实发布 bool，故障不写致命 room.error，保存回执+EXITED/release 才完成；`W:_process/_close_after_supervisor_loss:337–382` 真 prepare_close 结果、发布失败保留等待，不伪造请求回执。`server_deployment_validation.gd:45–59`、CLI`:80–82` 只用本机声明，无缺省新期限。`heartbeat_runtime_integration_test` E4：**90 checks/exit0**，含写失败→成功、双实例隔离、新实例恢复、持续故障安全 close、保存拒绝、请求/结果发布失败、无配置与真 CLI。 | 未发现核心策略缺接线。需当前冻结重跑 E4 并保留父/全部子日志；E4 原 worker 证据目录已不存在，当前 manager/worker/CLI/host SHA 均不同于其冻结。运行中活动对局 recorder/journal 保存边界未由此 lobby 专项证明，仍 unknown。 |

## 证据路径（已读原日志，不采用旧矩阵状态作结论）

- **E1** `reports/refactoring/round14-server_runtime_admission-verified.log:4–58`；exit0 来源 `round14-heartbeat-verification.json:74–82`。原测试确有真实 owner/production_worker，不是全部纯策略。
- **E2** `E:/scratch/isolated-b3cc1bfe631149fa94f6a7c789f25491/evidence/server_shutdown_close_handoff_test.stdout.log:7–10`；同根 `manifest.json` 记录 exit1。READY 首红，不是已证实保存失败。
- **E3** `E:/scratch/isolated-ed9fd487c32d490087e239301371f838/evidence/{server_shutdown_close_handoff_pending_test,net_server_shutdown_failure_test}.stdout.log`；同根 `manifest.json`：两套 exit0、36/161 checks、Job0。对应生产控制/真实原生子进程，但不是全部正式 production_worker 启动链。
- **E4** `reports/refactoring/round14-heartbeat_runtime_integration-verified.log:6–95`；exit0/子日志旧索引见 `round14-heartbeat-verification.json:3–72`；旧冻结见 `round14-heartbeat-source-fingerprint.json`。`E:/Caches/Hermes/cache/scratch/heartbeat-28000` 本次检查不存在，故子日志不能重新核验。
- E3 的 console/shutdown/host/CLI 与当前 SHA 相同，但 manager/worker/gateway 不同；只能证明对应旧冻结，不拼成当前整链绿。`recovery_save_diagnostic.gd:16–40` 只是失败白名单投影，不是修复或保存成功证据。

## 实际读取文件及 SHA256

以下 SHA 是本次读取核对末时原字节。全读或注明局部；检索仅偶然命中的其它文件不作为已审读文件。manifest 仅取 suite/process/source-hash 元数据；日志仅取 CHECK/RESULT/错误行，不读取 recovery/config/key/ticket 载荷。

| 文件 | 阅读范围 | SHA256 |
|---|---|---|
| `hermesWarning.txt` | 全读 | `779ff6091ec874a56964ed69a36089a5fedbd7ffba9ae2a373bb4be4b0d51303` |
| `CLAUDE.md` | 全读 | `6df9fa5947e456fdf2e67d25a66a66850bda45ab2f62de2b031591be66c0412f` |
| `scripts/net/server/server_room_manager.gd` | 全读 | `ea4f181aacb86400ec4c46143298cf7edab3ceed952a1ba12ba78ef81f9123e4` |
| `scripts/net/server/server_console_channel.gd` | 全读 | `afbfd5a071a2fcb062555f00fcd9ac08dbe476a04ad3fd6efc2c7142373af3c3` |
| `scripts/net/server/server_gateway.gd` | 417–593及相关检索片段 | `6c37eb25356bb1bbea22b7c0abf1c270c542745a2460f7d503bba740d6532cc1` |
| `scripts/net/server/server_shutdown.gd` | 全读 | `7526d0b8fd7d427a04a67085f462425f845e883a3210ee8017a0a30963b60227` |
| `scripts/net/server/server_room_control.gd` | 全读 | `296edf36916d77d767e67fceeb33808554e8e487dabb92a43ac0fa5703630997` |
| `scripts/net/server/server_room_worker.gd` | 190–409 | `a1d935675ce6d6a3f804ac9000104b15d95c2c279c8cf13c459acdd3920107eb` |
| `scripts/net/server/server_cli.gd` | 1–244、262–306；246–250片段 | `8ecc943bd496ef2c85e16e66c3495a6b37b63818d56e94e2e398c0a94ddfaf6a` |
| `scripts/net/server/server_deployment_validation.gd` | 全读 | `7396c12aebfec92c1e1ae56c507ad052ed4b9c1619f11c7b102af1831c4f7af3` |
| `scripts/net/server/heartbeat_publication_policy.gd` | 全读 | `b45b13235d422711cdece9d4af79e315a85d69fb7614fd4519747ff9871fc4ab` |
| `scripts/net/server/recovery_save_diagnostic.gd` | 全读 | `96d66505708d7e2bd0980a2df3648a827bfe9eed9ee02bae2db72d919bc089a9` |
| `scripts/net/session/authority_host_client.gd` | 253–346、72–81及相关片段 | `74d79bf1ee5fc08a61555ad722a49aca9189e8c1760290604e787e7cfe00c746` |
| `tests/server_runtime_admission_test.gd` | 全读 | `f7125fed8e6bc673bf842a8856bcee15862b7eb5b4ae9f0c466c586286a20a5b` |
| `tests/deployment_approved_root_test.gd` | 全读 | `e21a2ed74e7aee7616c712c51e142eb58f1d94c0168545002700d195042d5742` |
| `tests/heartbeat_runtime_integration_test.gd` | 全读 | `f2b6891949968bba66154ddde20667107b69a4eba31776a0768e0d65dad061ae` |
| `tests/round11_safe_close_test.gd` | 全读 | `231d9e284b5c58aa440f4f908f13508d032be15039bbe2188af30b99ab9b5407` |
| `tests/gateway_disconnect_safe_close_test.gd` | 全读 | `9754309448eeb68d5e249c638dd6c896eb66a2affdcf9fd2f684013a25e65389` |
| `tests/server_shutdown_close_handoff_test.gd` | 全读 | `43883d7c045e424fded389ec2359e5ef7416e063f84c7c4d185ab567bad83394` |
| `tests/server_shutdown_close_handoff_pending_test.gd` | 全读 | `346c320b4e6be2f6d39c6f620de1f4aba79686071e4b91f29c1cff1b4b7f18a0` |
| `tests/net_server_shutdown_failure_test.gd` | 全读 | `dcae086ea696d5193dd9e183a06ce5c4df9cd03c4d84356b1ded0ed8a52ae932` |
| `reports/refactoring/round14-heartbeat-runtime.md` | 全读 | `81324c014e510816e675f48cfaa98a9b4fea46e1db299a34f5700e12e7add392` |
| `reports/refactoring/round14-heartbeat-verification.json` | 全读 | `f548070c005fd4c5574eb11d4bb4e804d378e445efed4e6cfc2decf2a9a83ace` |
| `reports/refactoring/round14-heartbeat-source-fingerprint.json` | 全读 | `d833317342c2cb7b314a8d5922dc39bebe071cab02ed155069ac52094b59639b` |
| `reports/refactoring/round14-heartbeat_runtime_integration-verified.log` | 全读 | `32168dc1904f4793d1baffb87304756b01962be82c128af309b3798acfaf1d8b` |
| `reports/refactoring/round14-server_runtime_admission-verified.log` | 全读 | `5324d5fc7e1b4a2247a83d0fc03482b5079cebe8e5213d8d7c50c1a4c0fc312a` |
| `docs/round71-publish-save-reliability.md` | 全读 | `ab2d491ec6649d586f3273a8298f6917325c1c64e995ca1df458c1946a0e293c` |
| `docs/refactoring-plan.md` | F11–F14需求片段257–260 | `aeb65eb24433893b70e0e58a81aef3fc28dc2655369a52d7771d7eb66dfe7c44` |
| `docs/refactoring-delivery-matrix.md` | 检索片段，仅定位，不采信结论 | `93410d937d40ac6abf50c17554dee5fee6ef44cf66ed209033611c4be25360a7` |
| `docs/refactoring-execution.md` | 检索片段，仅定位历史产物 | `14617f79896c636e2e028f32549698cbbc73cedbb1bb71a2c9f0578c4834822f` |
| `E:/scratch/isolated-b3cc1bfe631149fa94f6a7c789f25491/manifest.json` | 元数据投影读取 | `4b76b2d85bef24ec2443f3ae835ca2e0b7117976a92bbba25108dff52a19d4cd` |
| `E:/scratch/isolated-b3cc1bfe631149fa94f6a7c789f25491/evidence/server_shutdown_close_handoff_test.stdout.log` | 全读 | `df2c7b78d93c4a748307428d61ef4dfdaeba256a44f633b9ede7b480ef12f18d` |
| `E:/scratch/isolated-b3cc1bfe631149fa94f6a7c789f25491/evidence/server_shutdown_close_handoff_test.stderr.log` | 全读 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-ed9fd487c32d490087e239301371f838/manifest.json` | 元数据投影读取 | `3fe0e659cee9c97850805779026548d1aa04a193098d772302beb8fc48efb14f` |
| `E:/scratch/isolated-ed9fd487c32d490087e239301371f838/evidence/server_shutdown_close_handoff_pending_test.stdout.log` | CHECK/RESULT/错误行投影读取 | `2d830acbd7b0611fbddfd0e82871ff0a3489613746ece8c4c249e6a0c66e389a` |
| `E:/scratch/isolated-ed9fd487c32d490087e239301371f838/evidence/server_shutdown_close_handoff_pending_test.stderr.log` | CHECK/RESULT/错误行投影读取 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `E:/scratch/isolated-ed9fd487c32d490087e239301371f838/evidence/net_server_shutdown_failure_test.stdout.log` | CHECK/RESULT/错误行投影读取 | `17eb69aab0b59f2ec951abf791f460cfe620c2a21970e6bb08f7cc77f919b874` |
| `E:/scratch/isolated-ed9fd487c32d490087e239301371f838/evidence/net_server_shutdown_failure_test.stderr.log` | CHECK/RESULT/错误行投影读取 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
