# Batch 38：自动信令真实 worker 崩溃恢复候选

## 交付和拓扑

仅新增测试候选，生产文件和现有 tests 均未写入；未运行 Godot、没有 NodeJS 投影。

- 信令面：生产 `p2p_signal_server` 在回环临时 TCP 端口监听；生产 `p2p_signal_client.host/join/reconnect` 通过 WebSocket 自动交换真实 SDP/ICE。
- 数据面：生产 WebRTC 直连，无 STUN/TURN（`iceServers:[]`）、无 ENet 替代外部 peer、无游戏信令转发。房主 UI 到 worker 仍是原回环传输。
- 权威面：生产 AuthorityHostClient/原生 owner 启动房主机器上的真实独立 worker；客户端只发送真人操作、安装展示数据，规则和录制恢复都在 worker。

## 新文件落位

将以下三个候选复制到主代理验收工程对应位置（`.gd.txt` 去掉 `.txt`）：

1. `tests/p2p_signal_worker_crash_live_test.gd.txt` → `tests/p2p_signal_worker_crash_live_test.gd`
2. `tests/helpers/p2p_signal_isolated_lobby.gd.txt` → `tests/helpers/p2p_signal_isolated_lobby.gd`
3. `tests/p2p_signal_worker_crash_live_test.tscn` → 同名路径

脚本没有 class_name；用 `.gd.txt` 避免项目内 scratch 被 Godot 全局扫描为另一份待接入脚本。场景引用的是接入后正式 tests 路径，直接运行 scratch 场景不会自动找到尚未落位的新脚本。

## 测试职责及最小注入边界

主测试继承 `lan_worker_crash_live_test`，复用其真实规则中局录制、原生 worker 崩溃、错票拒绝、错密钥盗票拒绝、缺原客机 restoring 屏障、缺当前数据 ACK 屏障、两观察者/共享对象 ID 双射/实际资产 SHA 等价、恢复后新规则操作至终局、副本续写尾哈希及原档不变。

不继承旧 `net_p2p_signal_match`，也不调用手工 `export_code/accept_offer/accept_answer`。

唯一隔离 seam：`p2p_signal_isolated_lobby.host_authority_peer` 保持生产 Lobby 同一启动与失败关闭顺序，改为使用预先创建的真实 Host，并向 `Host.start` 传入已支持的隔离 storage_root。用于避免生产公开 SignalClient.host 的默认 `user://authority_rooms` 写入用户目录，以及复用已探测 worker 端口；没有模拟 host、manager、规则、身份、存档或传输。生产 SignalClient.host 仍是真实被测入口。

### 故障顺序

1. 生产自动建连；等 worker 房主 IPC、客机新 RSA 身份和两成员清单；核对认证昵称和磁盘密钥绑定。
2. 两真人客户端驱动真实规则到非终局第二回合，原 worker 暂停存档并冻结双镜像与资产。
3. 只关闭客机真实 WebSocket socket。等待生产 poll 检测到错误，并在 800ms 墙钟区间确认原直连、稳定 member、冻结私有镜像无变化。此时房主信令仍存活。
4. 继承原链注入 worker 崩溃，原房主显式 recover_worker；盗票反例也通过生产自动信令建新连接。
5. 原客机调用公开 `Lobby.reconnect()`，实际委派 `SignalClient.reconnect()`；新自动 SDP/ICE 和 RSA 认证恢复原 member。继承原缺员/缺 ACK 屏障及镜像等价验证。
6. 恢复成功、两端 playing 后关闭**整个真实信令服务**。等待房主和客机均观察信令断开，确认 relay 监听/房间归零但 WebRTC 数据面存活。
7. 在全信令离线期间，沿继承的原 worker 管理 resume、两真人新操作到终局、save 与实际日志新增/尾哈希判据验收。

盗票夹具特别处理自动异步 join：`join()` 返回后还没有执行 `join_peer()`，不能立即向 `_hello.resume` 写票据，否则稍后生产 join_peer 的 reset 会清空它。测试只 poll 此新 driver 到 `_received_offer`，不提前 poll intruder Lobby；再交还父类注入票据并认证。不是生产缺陷修补，也不伪造认证标记。

## 主代理运行（这里未执行）

接入三个测试文件后，为每次运行选一个**不存在的 E 盘项目外物理目录**，继承原测试会拒绝已存在目录或项目内目录。运行密钥为测试内存中新建 RSA，不读取或持久化用户凭据。

```bash
HERMES_LAN_RESTORE_LIVE_ROOT='E:/Projects/Godot/FateDomination/test/net-batch-38-signal-live-run-01' \
'D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' \
 --headless --fixed-fps 60 \
 --path 'E:/Projects/Godot/FateDominationGame-master' \
 --scene res://tests/p2p_signal_worker_crash_live_test.tscn
```

exe 名称请主代理按本机已确认引擎使用；禁止本子代理启动。建议外层预算 900 秒，覆盖多个 180 秒恢复/规则阶段和清理；不套用 120 秒普通套件预算。实际 WebRTC 扩展或原生 owner 不可用必须失败，不换 ENet/桩或跳过为绿。

验收分别对账：引擎退出码、`P2P_SIGNAL_WORKER_LIVE_RESULT`、父类最终 `LAN_RESTORE_LIVE_RESULT`、最终 failures 与完整 SCRIPT ERROR/原生泄漏日志；不预设 checks 常数（继承链有按墙钟逐帧屏障检查）。信令断开产生 driver.error 是本测试预期观测，不应将所有会话/脚本错误一律忽略。

## 未验收及精确能力缺口

- 已做 gdtoolkit 语法及 Node 场景/路径静态检查；**Godot 语义编译、WebRTC、真实 worker、规则与恢复运行均未验收，由主代理串行执行**。
- 仅本机回环，不证明跨机器、NAT、跨公网、UI 按钮链或扩展发行包可用。
- 本链区分「客机信令断开后恢复重连」与「整个 relay 停机后已建对局续行」。不宣称整个 relay 丢失房间后还可通过旧 room_code 自动恢复。
- 静态确认生产能力缺口：`p2p_signal_client.gd` 的 `can_reconnect_session/reconnect` 只接受 guest；`host()` 会关闭 session/旧 invite 并重建 worker，因此没有不破坏既有权威的公开 host 信令重注册入口。若主代理需要覆盖“整个信令服务重启 + worker 恢复”，须单独设计保留 worker/直连并创建新房间码的 host 重注册行为以及对客机发布新码；不能在测试里私调 `_open()` 或恢复旧服务字典冒充真实恢复。这里仅报告静态缺口，没有生产补丁或运行复现结论。
