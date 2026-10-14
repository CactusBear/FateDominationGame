# Round25 — F08 客户端身份协调器真实拆分

## 交付结论

生产 Session 已接入 `scripts/net/identity/client_identity_inbox.gd`，迁出全部八种身份客户端收件分支，不是 stub。协调器无实例业务状态、无 Session/transport 引用或回调，接收明确状态快照与具体 PlayerIdentity；输出状态安装、请求及发布意图。真实契约完成 RED→GREEN，最终 58 项、exit 0、无 SCRIPT ERROR/泄漏；真实 LAN 独立 worker/RSA/ENet/私有身份 IPC 入房 16 项通过。跨进程认证恢复 seed/resume 分别 5/13 项通过。

追加用户指令：普通 `host_authority` 与 `host_authority_peer` 在具体 Host 的 `start` 之前调用已存在的 `configure_deployment_broadcast_confirmation`。新增可在创建前显式注入的 Session 公共契约，默认 false；没有用 `_broadcast_confirmation_capable` 猜 UI 存在。

**不是所有身份/恢复专项全绿**：旧绑定/恢复夹具、完整活局投影比较、true 部署第二批播报及服务端长对局仍有失败或超时，详见下表；不把这些声明为通过，不修改未分配测试。

## 状态及执行归属

- Session 唯一持有 `identity_profile`、`identity_authenticated`、`identity_is_admin`、`_identity_sent`、`_lan_identity_context`、`_resume_ticket`、`_resume_inflight`、`_inheritance_ticket` 与请求序号。无第二份长期状态。
- 协调器复用 `PlayerIdentity.sign_challenge/fingerprint`、`LanIdentityChallenge.context`、`IdentityInheritanceInput.accept`、`PlayerRegistry.valid_id`。不复制 RSA 验证、白名单、主机成员绑定或继承授权。
- LAN challenge 的 `peer` 校验取 **transport connection**；identity/继承票据保存 **稳定 member**。契约明确覆盖 connection=41/member=3 的不可互换性。
- Session 的 reset/restore/begin 禁入、主机 LAN 来源门、普通客户端 sender==1 来源门均先于协调器。F06/F07 顺位及 E07d 主机授权/执行/审计/发布链不变。
- Session 先安装协调器的认证上下文/成员票据与序号，再按输出顺序发送 proof 或 `identity_ack`→有批准安装及同 revision 时 `data_ack`，最后发原 candidates/ticket/changed 信号。继承接收不提前切换席位，仍须现有离线 `activate_inheritance_ticket`。
- `_join_identity`、`_accept_identity`、`_inherit_identity`、主机身份 ACK 持久化/轮换/回滚未修改；E04 已认证密钥绑定不降级，D14 请求代际与 reset 来源门保留。

## 完整迁出与精确剩余

八种收件消息全部由协调器解释：
`lan_identity_challenge`、`lan_identity_ready`、`server_identity_challenge`、`server_identity_ready`、`server_identity_permissions`、`inheritance_candidates`、`inheritance_ticket`、`identity`。

仍属于 Session 生命周期/网络适配而非本轮收件闭包：
1. `configure_identity`、poll 中 `lan_identity_begin/server_identity_begin` 启动及认证后 join 发起。
2. reconnect/close/disconnect 中身份状态清理与离线继承票据启用。
3. 主机 `identity_candidates/identity_inherit/identity_ack/join`、持久化与审计。
4. 非身份命名空间的 `server_admin_result/server_notice/server_attached/server_rooms` 展示和路由消息。

没有增加服务定位器、动态属性 set/get、字串反查 Session 或反向强引用环。输出包含私有协议票据时只在内存供原 ACK/恢复链消费，测试和报告不打印票据、密钥或指纹。

## UI 组合根的新公共契约

```gdscript
# 仅在本机组合根明确具备真实播报确认消费者时声明；须在创建房主之前。
if not session.configure_deployment_broadcast_confirmation(true):
    return
# 然后调用原 host_authority(...) 或 host_authority_peer(...)。
```

- 签名：`configure_deployment_broadcast_confirmation(value:Variant) -> bool`；严格 bool，默认 false。
- 拒绝条件：现有 authority_host、普通 host、连接/连接中、已开局、失败关闭/恢复/开局/reset 阶段。拒绝不改变原声明。
- `_new_configured_authority_host_client` 只构造具体 AuthorityHostClient，并调用其已存在的公开部署 API；拒绝则 close/null，两个 host 入口均不 start。
- 部署策略独立于规则侧 `declare_broadcast_confirmation`，不读取 settings、旧存档或 UI Node。close 结束连接但不清组合根声明；空闲期可以显式重新设置 false。
- 本代理不拥有 UI 文件，**UI 组合根还须由其唯一写入者调用上述 API**。不能把新增契约本身称作真人包已经启用。
- 契约直接观察两条生产 host 入口：真实 start 因空名字在副作用前返回 ERR_INVALID_PARAMETER，实际具体 Host 的 manager 已收到 true；并覆盖生命周期在创建之前拒绝。这是接线/顺序验收，不冒充真实启动验收。

## RED/GREEN 与命令

Godot：`D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`。
统一命令：`--headless --fixed-fps 60 --path E:/Projects/Godot/FateDominationGame-master --scene res://tests/<name>.tscn`。每个进程最大 180 秒，无窗口。

日志/运行器物理根：`E:/Caches/Hermes/cache/scratch/round25-F08/`；别名为 Hermes 已批准 scratch，不改变默认用户目录。测试子进程使用此根独占 APPDATA，FATE_TEST_SCRATCH_ROOT 必须是 forward-slash 规范物理路径。

- `red.log`：新增生产模块尚未存在，exit 1，checks=1，明确失败 independent production inbox exists。
- 最初测试 request override 签名不匹配导致 180 秒超时；修正测试签名后才获得有效 RED，不能将 parser 失败算契约 RED。
- `green.log`：42 项中弱引用失败，原因是新夹具强捕获 Session 的 changed lambda。改为实例方法连接，不放宽析构断言。
- `deployment-red.log`：原 F08 42 项通过，新增公共契约不存在这一项失败，exit 1、checks=43。
- `client_identity_inbox_contract_test.log`：最终 exit 0，checks=58、failures=[]，无错误/泄漏。

### 干净通过的真实专项

| 套件 | checks | exit |
|---|---:|---:|
| client_identity_inbox_contract_test | 58 | 0 |
| net_gateway_identity_test（真实 RSA/ENet） | 17 | 0 |
| identity_inheritance_test | 36 | 0 |
| authenticated_key_reconnect_test | 34 | 0 |
| authenticated_restart_reconnect_test seed / resume（两个独立进程） | 5 / 13 | 0 / 0 |
| lan_live_join_test（独立 worker/RSA/ENet/身份 IPC） | 16 | 0 |
| client_match_inbox_contract_test（保留原34项） | 45 | 0 |
| client_blob_inbox_test | 112 | 0 |
| match_command_result_protocol_test | 39 | 0 |
| broadcast_absent_confirmation_test | 56 | 0 |
| broadcast_absent_actions_projection_test（round23 absent） | 10 | 0 |
| match_finished_lobby_test | 41 | 0 |
| broadcast_spawn_capability_test，显式 false | 37 | 0 |

seed/resume 参数：`-- seed E:/Caches/Hermes/cache/scratch/round25-F08/restart` 和同根 `-- resume ...`。
LAN 入房环境：`HERMES_LAN_LIVE_ROOT=E:/Caches/Hermes/cache/scratch/round25-F08/lan-live`。
部署 false 环境：`HERMES_LAN_RESTORE_LIVE_ROOT=.../spawn-false FD_SPAWN_CAPABILITY=false`。

### 失败、限制与未验收

| 套件 | 实际结果/边界 |
|---|---|
| net_player_identity_test | exit 0，5 项通过；损坏密钥反例打印三个 Godot len==0 ERROR，不能称干净通过 |
| net_member_identity_binding_test | exit 1，旧 TestRooms 缺 resolve_room/valid_instance_id/instance_binding，另缺 request_seq；10项含真实网关附着与原房主票据失败 |
| net_identity_security_regression_test | exit 1，19项；旧正式主机 join 前置及恢复档 ACK 持久化4项失败；未修改该夹具 |
| net_resume_identity_test | 180秒超时，旧消息夹具直接访问缺失 seq |
| net_p2p_resume_identity_test | 180秒超时，直接访问缺失 effect |
| broadcast_worker_capability_test | exit 1，24项；旧 LAN root 预期不符合新公开 API，且未提供独立测试端口；未修改此其他测试 |
| broadcast_spawn_capability_test，true | exit 1，41项；第一批真实规则屏障与两真人确认已越过，下一批规则屏障45秒未到达。实际失败由本轮工具 stdout 返回；同名原始log及汇总后来被重跑覆盖，因此不伪称原始日志仍独立保留 |
| lan_restore_live_test | exit 1，58项；最后两观察者原局/恢复局投影逐字段等价失败，日志仍保存；不得把真实身份恢复前置通过称完整恢复通过 |
| net_server_resume_identity_test | 先缺/非规范 scratch fail-fast；补目录并规范环境后180秒无RESULT超时。父进程被看门狗结束，随后精确 ready.json PID=36104 的 CIM 查询为空，未遗留该 worker；不称自然完成/正常保存关闭 |

失败尚未在冻结原始 Session 上做隔离对照，故不武断归因全部是基线；主代理按唯一测试文件拥有者继续处理。未运行任何窗口，未进行真人/多机/跨网验收。

## 修改文件及检查

- 修改：`scripts/net/session/lobby_session.gd`。
- 新增：`scripts/net/identity/client_identity_inbox.gd`。
- 新增：`tests/client_identity_inbox_contract_test.gd/.tscn`。
- 报告：本文件。
- 未修改 authority、registry、transport、UI、worker、gateway 或其他测试；保留共享工作树既有改动，无提交。
- `git diff --check -- scripts/net/session/lobby_session.gd scripts/net/identity/client_identity_inbox.gd tests/client_identity_inbox_contract_test.gd tests/client_identity_inbox_contract_test.tscn` exit 0。Session 全工作树 diff 包含此前 D14/F06/E04/E07d 等轮次，不能全部归于本轮。
