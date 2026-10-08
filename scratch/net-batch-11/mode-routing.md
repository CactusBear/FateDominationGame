# LAN/P2P 与 dedicated 模式路由审计

## 结论

**静态未发现 dedicated 房间操作失败被错误路由到 LAN/P2P 恢复阻断。** 当前“服务端房间操作失败，请联系管理员检查房间状态”是 `ServerGateway` 对管理器建房/重启失败的通用拒绝，不是 LAN/P2P 专用阻断文案。缺少本次失败时的 manager.error / 房间 engine 日志，因此不能把任一候选原因定为已复现根因。

本次只读审计生产代码并新增本文档，未修改生产代码，按要求未运行 Godot、未创建房间/子进程。Python 文本结构检查退出码 0，五项检查均为 True；这只是静态证据，不是运行验收。

## 三个平面的拓扑

- dedicated：客户端 → 服务端网关 → 服务端本机回环 worker；规则权威与存档在服务端机器。网关转发房间消息、身份上下文及数据管理请求。
- LAN：客机 → 房主机器的 authority_host_client / 内嵌 gateway → 房主本机回环 worker；房主 UI 也通过回环连接 worker，不在 UI 执行规则。
- P2P：客机与房主 WebRTC 直连 → 房主内嵌 gateway → 房主本机 worker；信令服务仅交换信令/辅助打洞，不承载对局流量。

## 路由证据

| 入口/阶段 | 源码位置 | 当前行为 |
|---|---|---|
| dedicated UI 建房 | `scripts/net/ui/lobby_screen.gd:381-384` | NetworkMode.selected == 1 调用 join_server，并立即 return，不落入 LAN host_authority |
| dedicated UI 加入 | 同文件 `:442-450` | 模式 1 调用 join_server；其他直连调用 join |
| 服务端会话初始化 | `scripts/net/session/lobby_session.gd:352-357` | join_server 调用 join → close，清理原 authority_host；设置 server_create/server_join 请求，不创建 authority_host_client |
| 会话清理 | 同文件 `:404-419,454-459` | 关闭且置空 authority_host / connection_driver，清空旧服务端请求和房间身份 |
| 服务端请求发送 | 同文件 `:371-389` | 认证后发 server_list 与 server_create/server_join；收到绑定后才发普通 join |
| LAN/P2P 本机监督器 | 同文件 `:18-38`；`scripts/net/session/authority_host_client.gd:22-32` | 只有 host_authority / host_authority_peer 显式传 lan / p2p；start 不接受 dedicated |
| dedicated 网关建房 | `scripts/net/server/server_gateway.gd:154-172` | 调用 manager.create_room；空 ID 在 :166 发通用“服务端房间操作失败” |
| dedicated 网关恢复加入 | 同文件 `:173-200` | 先验证旧成员凭据及实例；recover_room 返回 false 时在 :196 发同一通用文案 |
| 普通房间操作 | 同文件 `:117-139` | 经消息白名单与当前实例校验转发 route.link，不调用 authority_host_client.restore_local_match |
| 模式默认/落盘 | `scripts/net/server/server_room_manager.gd:12-13,29-42,183,195` | 默认 dedicated；本机主管配置决定模式，写入 config 和 rooms；公开 settings 不覆盖 authority_host_mode |
| CLI 策略 | `scripts/net/server/server_cli.gd:89-100`；`scripts/net/server/server_policy_config.gd:5,15-16` | CLI 校验器只接受 dedicated；传 lan/p2p 会拒绝启动，不会静默改模式 |
| 模式绑定 | `scripts/net/server/server_room_manager.gd:77-106,320-322` | 实例绑定、ready 报告、恢复磁盘配置均校验 authority_host_mode 相等，不按客户端自报重新选模式 |

## LAN/P2P 专用阻断是否会命中 dedicated

1. `authority_host_client.gd:104-110`：本机手工存档恢复始终返回 false 并报 LAN/P2P 阻断。但 dedicated UI 的 join_server 会清理 authority_host，网关也不依赖该类。UI 恢复入口 `lobby_screen.gd:406-410` 只在 authority_host 非空时调用它。
2. `server_room_worker.gd:88-90`：仅存在 recovery.json 且 `_authority_host_mode in ["lan", "p2p"]` 时阻断启动恢复，dedicated 明确不匹配。
3. 同文件 `:225-230`：自动对局恢复的防御分支也只拦 lan/p2p；dedicated 继续等待原成员、校验路径、复制崩溃档，再在 :260 调共享恢复。

注意：worker 在 `:158,165` 对所有部署位置设 `session.dedicated = true`。这是复用 worker 的房间/身份/数据契约标志，**不是 authority_host_mode**。反之 dedicated 客户端会话的 dedicated 变量初始化/close 后为 false，而公开 view.dedicated 来自 worker。不能拿客户端布尔字段或 worker 的共同布尔字段推断权威部署模式；目前上述 LAN/P2P 阻断实际检查的是配置模式或 authority_host 对象。

## 通用失败的真实候选来源（未复现）

- 最前置的共享门槛：`server_room_manager.gd:125-129` 建房及 `:292-296` 恢复都要求 process_ownership_available。
- `:57-63` 要求原生 `FateProcessOwner` 已注册且 available() == true，否则 manager.error 为 `PROCESS_OWNERSHIP_UNAVAILABLE`（:55）。此门槛适用于 **dedicated / LAN / P2P 全部模式**，不是 LAN/P2P 恢复阻断。
- 建房还可能因批准数据根/链接检查、存储路径、房间参数、端口范围、配置写盘、原生 spawn 失败返回空 ID（:130-194）。
- 恢复还可能因过期实例、进程仍运行、恢复配置/批准路径不匹配、端口占用、配置/ready 更新失败、spawn/令牌释放失败返回 false（:297-359）。
- 网关 :166 / :196 不向客户端附 manager.error，因此同一 UI 文案不足以区分这些原因；不要通过去掉共享安全校验或 dedicated 改走 LAN 来“修复”。

## 边界与后续定位

- 本文确认当前调用链没有 dedicated → LAN/P2P 专用阻断的静态边；不宣称现场失败已经定位，亦未验证原生扩展是否在实际服务端进程加载成功。
- 主代理下一步应在真实失败发生的 server_create/recover_room 分支读取当次 manager.error，或增加仅本机固定阶段/错误码诊断（不得泄漏认证、票据或消息载荷）；核对该房间 config.authority_host_mode、登记模式、ready 模式及对应实例 engine 日志。
- 不要把 room worker 共用 session.dedicated=true 误判为 LAN/P2P 成功具备恢复能力，也不要把 PROCESS_OWNERSHIP_UNAVAILABLE 误判为 dedicated 被 LAN 恢复策略拦住。
- 未执行：Godot 解析、专项套件、真实 dedicated 建房/恢复、LAN/P2P 多机与跨网验收。它们由主代理在允许运行时串行执行；本任务明确禁止运行 Godot。
