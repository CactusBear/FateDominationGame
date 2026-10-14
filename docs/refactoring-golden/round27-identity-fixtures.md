# Round27 — F08 旧身份夹具修复与真实复验

## 结论

四个指定专项在最终冻结下真实 headless GREEN：member binding 44 项、security regression 23 项、ENet resume 26 项、P2P resume 19 项；全部 exit 0、failures=[]。最终日志及错签名 RED 日志均无 SCRIPT ERROR、ERROR、WARNING 或 leaked。不是默认网关启动、独立 P2P worker、窗口或跨网整链验收。

生产文件只读；仅修改四个分配测试。保留同密钥恢复、错钥/被盗票据/伪造网关身份拒绝、原房主绑定、私有文件不泄露票据、ACK 撤销落盘及失败回滚、旧票据与旧视图重放拒绝、丢身份收据可再次重连等原断言。另跑未修改的 identity_inheritance_test（36 项）与 authenticated_key_reconnect_test（34 项），均 exit 0。

## 修改

- `tests/net_member_identity_binding_test.gd`：TestRooms 继承现有公开 manager，复用 resolve_room、instance_binding、valid_instance_id 和结构绑定规则；仅隔离路由 ready/process 验证与调度，不伪造原生所有权。房间/实例使用合法 32 位 ID，pending 使用完整 binding；独立真实 manager 验证同一登记缺原生句柄仍拒绝 ready。真实两把内存 RSA、网关 ENet 转发和专用 Session 权威保持；手工请求显式 seq/request_seq。正向恢复先通过公开 host 建立持久化资格，再等双方真实传输登记，确保票据能实际交付。
- `tests/net_identity_security_regression_test.gd`：原 `_initialize_host` 后向不存在连接发票据的夹具改为真实 host/join/RSA 前置；ACK 经正式 `Session.request` 分配递增 seq 并实际 ENet 传输。没有跳过恢复文件复读、旧 hash 不复活、落盘失败回滚。旧票据反例提供同密钥可信上下文且精确要求“恢复凭据无效”，不能靠缺认证上下文的拒绝凑通过。
- `tests/net_resume_identity_test.gd`：复用已有 `net_window_identity_fixture.gd` 的内存 RSA challenge factory；攻击连接持同密钥但错票据/在线票据仍须被拒绝。在线拒绝断言更新为当前精确文案“该认证身份已在房间在线”。进入 seq/effect 解引用前检查真实投影，要求生产双方 guard 完整，不替换空 guard。重连继续使用生产票据/ACK 协调器。
- `tests/net_p2p_resume_identity_test.gd`：原正式 signal driver.host 已改为独立 worker，不能再通过修改本进程 GameData/EffectManager 验该 worker。测试内 LocalAuthoritySignalDriver 明确组合公开 Session.host_peer 与现有信令 driver 的 _open，仍是真实 WebSocket 信令、WebRTC 数据通道、Session RSA、断线重新握手与恢复；仅权威拓扑限定为同进程，不声称正式独立 worker 通过。使用已有身份 factory，peer_disconnected 接现有 challenge.forget，避免复用连接编号后残留旧认证阻断新挑战。前置失败 stop_fixture 正常输出 RESULT 收尾。

四套都提供 `FD_GUARD_FIXTURE_REJECT_AUTH=1` 负向入口：公开 profile 不变，签名私钥替换为另一独立内存 RSA，真实生产验证拒绝；不读写用户密钥、不输出票据、密钥或指纹。成员夹具另提供 `FD_IDENTITY_DEFAULT_GATEWAY=1`，保留默认入房门的真实 RED。

## RED/GREEN 证据

日志/运行器全部在物理 E 盘：`E:/Caches/Hermes/cache/scratch/round27-identity-fixtures/`，pathlib.resolve 已核对。每进程最大 180 秒；无窗口。每个测试进程有独占 APPDATA，TMPDIR/FATE_TEST_SCRATCH_ROOT 均显式规范为该物理根。运行器只在看门狗超时时 kill 本次 Popen 的 PID，不进行按名杀进程。

| 套件 | 原始 red | 最终 final | reject-auth |
|---|---|---|---|
| net_member_identity_binding_test | exit 1，10 项；缺 manager API，并连带 request_seq SCRIPT ERROR | exit 0，44 项 | exit 1，10 项，私钥持有前置失败 RESULT |
| net_identity_security_regression_test | exit 1，19 项；正式加入及 ACK 撤销三项失败 | exit 0，23 项 | exit 1，15 项，正式成员前置失败 RESULT |
| net_resume_identity_test | 180 秒 timeout；缺 seq SCRIPT ERROR | exit 0，26 项 | exit 1，5 项，认证票据前置失败 RESULT |
| net_p2p_resume_identity_test | 180 秒 timeout；缺 effect SCRIPT ERROR | exit 0，19 项 | exit 1，6 项，直连票据前置失败 RESULT |

原始 `red-*.log` 未覆盖。中间轮为 `pass1/2/3-*.log`；加强断言后 `green-*.log` 与 `green-repeat-*.log` 连续通过；最后成员早退清理及默认网关开关补齐后再次 `final-*.log` 四套全绿。`reject-auth-*.log` 最后重跑，均正常 exit 1 且有 RESULT，无脚本错误或挂起；这才是有效前置负向行为，不把旧 parser/property 错误当鉴权 RED。

真实命令：

```text
python E:/Caches/Hermes/cache/scratch/round27-identity-fixtures/run.py red
python E:/Caches/Hermes/cache/scratch/round27-identity-fixtures/run.py green net_member_identity_binding net_identity_security_regression net_resume_identity net_p2p_resume_identity identity_inheritance authenticated_key_reconnect
python E:/Caches/Hermes/cache/scratch/round27-identity-fixtures/run.py green-repeat
FD_IDENTITY_DEFAULT_GATEWAY=1 python E:/Caches/Hermes/cache/scratch/round27-identity-fixtures/run.py gateway-default net_member_identity_binding
python E:/Caches/Hermes/cache/scratch/round27-identity-fixtures/run.py final
python E:/Caches/Hermes/cache/scratch/round27-identity-fixtures/run.py reject-auth
```

运行器实际调用：`D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path E:/Projects/Godot/FateDominationGame-master --scene res://tests/<name>_test.tscn`。运行器自身 exit 0 仅代表汇总完成，各专项退出码必须读对应 JSON/日志，不能混同。

## 生产只读根因交接：Session 唯一负责人

1. **Gateway listen/close 入房生命周期问题仍未修复。** 当前 `server_gateway.gd:41-47` 的 listen 先 close；close 在 511-512 将 accepting_rooms=false/_close_requested=true，listen 没有重新开启。`server_cli.gd:138` 调用 listen，扫描正式 server 消费者未发现重新设 true。`gateway-default-net_member_identity_binding.log` 在合法 RSA 与路由 binding 前置下，exit 1、checks=11、失败“通过真实网关附着回环工作连接”，无 SCRIPT ERROR。修复后的成员身份专项为了隔离身份链，显式设公开 accepting_rooms=true；因此它的 GREEN **不代表默认 Gateway listen 已修复**。请 Session 唯一负责人协调真正 gateway 拥有者，决定 listen 是重新开放新生命周期还是按调用方显式授权开启，保留 close/closing 拒绝语义，勿在测试中误写“正式 bootstrap 已开启”。
2. **P2P 权威拓扑边界。** 正式 `p2p_signal_client.gd:66-77` 走 host_authority_peer，独立权威规则不在 UI/test 进程。本轮明确改为同进程规则专项，未增加生产注入口。正式独立 worker 的双密钥认证、恢复与原 pending 完整链仍应由跨进程专项覆盖；不能用此项 GREEN 替代该证明。
3. **未发现需要放宽 F08 身份协调器鉴权的证据。** 本轮用合法前置即可使四套通过；ACK 真落盘及失败回滚保留。原生句柄生命周期、真实 kill/restart、窗口/真人/多机/跨网均未验收。

## 检查与冻结

四个 tests 被 gitignore 忽略，git diff/numstat 空不等于没有磁盘修改；`git check-ignore` 已确认。`git diff --check -- <四个文件>` exit 0 只作附加检查，真实 Godot 编译执行与日志才是主要验收。未提交，保留共享工作树其他改动。

最终源码 SHA256（终端实算）：

- member：`b59fc0b75757902b177ee0642075bc9381647d30de856fe7f46fa3cdcb761d7e`
- security：`f7364439ba8d15735eec4a20d026e2458c94f26a3d8c319271b983c8736240a8`
- resume：`214b4071f610867a7d4c9469e5f1fc9a3e6561f6483c481dc827c83f9e4f090c`
- p2p：`ead2314d12c1f051130c3515aad28cfac9512a3e24575af482ecf4b60fbd5b41`

四个 hash 均对应最后 `final` 及 `reject-auth` 执行时的源码；member hash 已再次实算确认。
