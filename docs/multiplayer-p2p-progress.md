# P2P 直连与信令实施进度

## 已实现并实测

- 官方 `webrtc-native` 1.2.2-stable 原生扩展，邀请码与信令两种握手入口。
- WebRTC 复用既有权威会话、数据清单、JSON 与卡图下载、数据确认屏障、选人、私有视图及 v2 战局。
- 信令服务仅交换经过邀请码协议验证的 offer/answer，不接受游戏指令；隔离不同房间，绑定真实连接与握手 nonce，拒绝重复应答。
- CLI 配置可显式设置 `p2p_signaling: true`。UDP ENet 与 TCP WebSocket 使用同一对外端口，旧配置不声明时不启动信令入口。
- 大厅明确区分 `P2P 邀请码` 与 `P2P 信令`。后者输入服务器 URL 和房间码，由会话持有握手驱动，进入战局后不会丢失驱动。
- 信令停止后，已建立的 WebRTC 通道仍实际收到数据与准备指令；没有 TURN 或游戏流量转发兜底。
- 不应答客机超时仅取消该次邀请、释放原生 peer 与候选，不中断已连接客机；已接受应答的连接不能通过取消邀请关闭。
- 修复房间数据切换清空地图的问题：数据采用与恢复复用 `GameStart.end_session()`，完整复位进度、地图、玩家和启动标记。

## 执行证据

- `net_p2p_match_test -- window`：邀请码握手后真实同步 204 个批准文件，选人、对局、终局及正式窗口通过。
- `net_p2p_signal_match_test -- window`：信令自动握手后真实同步 204 个批准文件，19 条断言通过，双方实际提交 90 与 101 次决策，退出恢复下一局地图。
- `net_server_match_test -- window`：11 条断言通过，原服务端正式完整对局未回退。
- `net_p2p_signal_lobby_window_test -- window`：6 条断言通过，真实鼠标点击创建与加入按钮，原生查看 `tests/runtime_reports/p2p_signal_lobby.png`。
- `net_p2p_signal_client_test`：11 条断言通过，覆盖自动握手、独立取消、超时回收、信令停机后继续通信及活动客机断线资源回收。
- `docs/p2p-lifecycle-regression/summary.json`：6 套，66 条断言，无引擎错误，覆盖最新连接清理和新旧 CLI。原生退出警告不计入 error_count，不能据此宣称零警告。
- `docs/p2p-full-game-regression/summary.json`：6 套，88 条断言，无引擎错误。该批早于信令驱动与后续测试扩展，不作为最新全部代码的回归证据。
- `docs/p2p-signaling-regression/summary.json`：3 套，28 条断言，无引擎错误。覆盖信令核心、新旧 CLI。
- 原生检查完整对局截图：`net_p2p_match.png`、`net_p2p_signal_match.png`。
- WebRTC 底层消息分帧先复现原生单消息上限拒绝，再修复为传输层透明分帧。真实信令关闭后仍直连传输超过默认应用层单包预算的批准清单与真实卡图，30 条专项通过；正式窗口完整对局 19 条、身份恢复窗口 19 条再次通过。详见 `docs/multiplayer-transfer-progress.md`，不升级为公网或 Linux 验收。

## 使用与边界

- 同机测试使用 `ws://127.0.0.1:端口`。公网应使用可信 WSS 入口；当前 CLI 提供明文 WebSocket，WSS 证书部署未实测，不能把填写 `wss://` 当作服务端 TLS 已实现。
- STUN 由大厅显式填写。留空只收集直接地址；只支持 STUN，不支持 TURN。
- 房间码只用于信令配对；房主仍执行权威规则，客机只接收过滤视图并发送意图。

## 未验收或仍需推进

- 异地 NAT、公网直连、Linux 原生库与跨平台导出尚无实机证据。
- 原生库在部分测试退出时会产生 SCTP reset `errno=2` 警告。功能断言通过不等于退出日志完全干净，仍需定位原生关闭时序。
- 活动客机掉线后的原生连接及邀请码回收已有红绿测试；长时间反复加入、多人并发与网络中断矩阵仍需覆盖。
- 死循环预检与运行时保护、完整存档菜单以及方案中的其他未完成入口继续推进；本文件不是整案完成声明。
