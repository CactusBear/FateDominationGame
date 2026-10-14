# Round 28 — F09 主机房间管理收件闭包

## 实施结果与边界

本轮唯一生产写入者仅修改 `scripts/net/session/lobby_session.gd`，新增 `scripts/net/session/host_room_inbox.gd`；新增 `tests/host_room_inbox_contract_test.gd/.tscn`。其余生产只读，未改部署声明、F06/F07/F08、D14、E07d 的生产模块。

先读 hermesWarning、方案 F09、Room、F06 客户端收件、F07 blob 接收与 F08 无状态身份/ACK 源码。方案“22 种 kind”为旧库存；按实施前当前 `_receive` 主机请求 switch 的字面分支程序化枚举为 **27 kind、20 case**。原始 blob 数据帧及 catalog 分片预处理不在此请求 switch 库存内。

| 职责簇 | 全部 kind | 本轮处理 |
|---|---|---|
| 房间管理（4） | ready, settings, transfer, kick | 全部迁出 |
| 内容（7） | server_data_catalog, server_data_prepare, server_data_commit, server_data_cancel, catalog, data_ack, blob_request | 留 Session |
| 选人/对局（7） | start, choose_master, begin_match, preview_group, match_command, broadcast_confirm_absent, match_finished_lobby | 留 Session |
| guard（4） | guard_continue, guard_skip, guard_restart, guard_lobby | 留 Session |
| 身份/凭据（5） | join, identity_candidates, identity_inherit, identity_ack, room_password | 留 Session |

实施后请求 switch 剩 **23 kind**。`room_password` 虽是房间 UI 行为，却涉及 verifier 与恢复落盘失败回滚，因此本轮明确归凭据，不将第二职责硬塞入 RoomInbox。`join` 保留来源认证、私有票据与稳定 member 绑定；`start/choose_master` 保留选人与引擎初始化顺序。此报告不把 F09 其余四簇标记为完成。

## 中文代码说明与解耦审查

- `host_room_inbox.handles(kind)`：固定声明四种房间管理消息，未知 kind 不接管。
- `receive(...)`：请求作用域注入具体 Room、稳定 actor、args、内容就绪与采用状态、已有选人配置/模式/御主/从者以及两个具名具体能力。ready 的 bool/内容门、settings 的 Dictionary 输入、transfer/kick 的整数 target 随整个闭包迁移；实际规则仍唯一调用 Room 的 set_ready/set_settings/transfer_owner/kick，不复制房主鉴权。
- `set_settings(...)`：原 `_set_room_settings` 候选事务完整迁出。普通字段直接走 Room 原语；变更模式时复制临时候选 Room，先验证房主/阶段/字段，再要求本机唯一配置、调用已有规则容量入口、验证容量，最后安装选人配置并提交 settings/members/revision。不存在半提交的新模式与旧规则。候选快照仅当次事务使用，不新增长期状态。
- Session `_host_room_selection_rules`：复用已有 `_selection_rules` 并保持旧错误投影。传入的规则解析与 `configure_selection` Callable 只在同步调用栈使用，模块没有保存字段或反向 Session 强引用；没有 lambda 捕获 Session、泛用总线、属性字符串反查或服务定位器。
- Session 先保持生命周期拒绝、LAN 来源门、connection→member、协议字段、旧 seq、在线 member 检查及 seq 消费顺序；之后才分派四 kind。失败按原 seq 回执，成功的 transfer 在 playing 先重发布权限；kick 撤销 resume_hashes/resume_previous/member_identity，再断开当前映射的真实连接；最后 `_publish` 持久化/发布房间快照。
- 修复本闭包已实证旧问题：离线 kick 原本将无映射稳定 member 当成 peer 调用 ENet disconnect，产生原生 ERROR。现在只对仍存在 `_peer_by_member` 映射的 target 调用 disconnect，成员移除与凭据撤销不变；不改变 Transport 或身份规则。
- 修改采用 V4A 锚定补丁，不覆盖共享 Session 文件全篇；未动已有大范围未提交改动，未提交 Git。

## RED / GREEN：真实运行证据

Godot：`D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`。

通用命令（每套实际命令/PID/exit 见 JSON）：

```
Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path E:/Fate-F09-room-agent/project --scene res://tests/<name>.tscn
```

验证路径为本代理独占 E 盘副本；APPDATA/LOCALAPPDATA 显式设为 `E:/Fate-F09-room-agent/profile/roaming`、`.../local`。脚本使用 180 秒前台看门狗，超时只 kill 本次 Popen PID；本轮全部自然退出、无超时、未开窗口。静态素材/已导入缓存仅硬链接只读，脚本与测试为独立复制。

| 运行 | RESULT | exit | 错误 |
|---|---|---|---|
| red-corrected | 24 checks，独立模块不存在一项失败 | 1 | 原离线 kick 原生 ERROR另存 |
| red-owner-mutant | 34 checks，owner 发布及旧 owner 失权两项失败 | 1 | 仅预期 CHECK false，无 SCRIPT ERROR |
| green-final / host_room_inbox_contract | 34 checks，无失败 | 0 | 无 |
| net_selection_settings | 7 checks，无失败 | 0 | 无 |
| net_runtime_guard | 34 checks，无失败 | 0 | 无 |
| client_identity_inbox_contract（F08/部署） | 58 checks，无失败 | 0 | 无 |
| client_match_inbox_contract（F06） | 原契约34、最终45 checks，无失败 | 0 | 无 |
| broadcast_absent_confirmation（E07d） | 56 checks，无失败 | 0 | 无 |
| client_blob_inbox（F07） | 112 checks，无失败 | 0 | 无 |
| net_resume_identity | 26 checks，无失败 | 0 | 无 |

新专项实际经过 ENet UDP + 正式 RSA 挑战前置，覆盖远端 ready、伪造 actor 设置被拒、真实 owner 转移/旧 owner 失权/新 owner 设置、可靠旧 seq、断线席位保留、离线转让拒绝、原成员认证重连及稳定 member、自报 actor 不替换真实身份、内容 ready 门、离线 kick 能力撤销、D14/restore/begin 生命周期拒绝、关闭后不可操作及 WeakRef 释放。settings 专项补足未声明模式/容量不足原子拒绝与真实模式容量成功提交；guard 专项验证 playing 转让后实际权限变化。

行为反证不修改主仓库：仅在独占副本把模块 transfer 原语临时替换为 false，真实 ENet owner 与旧房主失权断言变红；随后由主仓库恢复副本再跑最终 GREEN。

初次 RED 的 WeakRef 假阳性已定位为 test run 的 await predicate 闭包尚在栈上；改在 run 返回后的 deferred 检查后通过，不改生产释放机制。

## 证据、回收与交接

完整日志与命令/PID/退出码 JSON 归档：`E:/Fate-F09-room-agent/reports/`；运行器：`C:/Users/Administrator/AppData/Local/hermes/cache/scratch/f09_run.py`（一份复制亦归档于 reports）。`git diff --check -- scripts/net/session/lobby_session.gd` exit 0。

8 套最终成功运行经 JSON 聚合验证，全部 exit 0、timeout=false、errors=[]。F06 的原契约与最终 RESULT 是同一次运行，不重复相加冒充总套数。

最终核心文件 SHA256：

- lobby_session.gd: `0cb12ae8eabc0922dd9d244b22012ad235e87bf1040a4197115c1ebb21b69135`
- host_room_inbox.gd: `5a5b41713c5c2eaee08242e1c4c56a2970b946009ca2ea57c18c18f69c275cca`
- host_room_inbox_contract_test.gd: `8ac1eadcb353ac360cbc0ea5fbe1e6975466ce8e74949e494b8fda3c28e08d94`
- host_room_inbox_contract_test.tscn: `881cc7139971d045ded45f68ecc66c5a9a192a929d850143cfb24ab71c3140a2`

归档 reports 后已回收本代理的 project/profile 副本，读回确认 reports/运行器仍在、project/profile 已不存在；保留 reports，不触碰正式存档或其他代理 PID/路径。主 worker 可用当前源码重新建立自己的独占 E 路径复验。

两份新测试落盘存在，但 `.gitignore:47:/tests/` 将其忽略，因此普通 `git status` 不显示；没有擅自 git add，主代理交付时须显式纳入测试文件。

**验收边界：**这里是真实同进程 ENet/RSA，不是独立主管/worker IPC 或实际进程崩溃；独立 worker 拓扑、最终冻结全量/依赖 gate、窗口与实包验收由主代理串行负责。本轮未启动独立 worker 或 GUI，不将已有纯策略/同进程测试说成整链部署验收。
