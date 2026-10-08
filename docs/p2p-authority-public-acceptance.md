# P2P/relay 权威位置与公网证据验收

本批未运行 Godot；以下是验收夹具与现场步骤，不是公网通过报告。

## 不可变边界

| 模式 | 权威机器 | relay 职责 |
|---|---|---|
| LAN 房主 | 房主机器，隔离规则子进程也在房主机器 | 不参与 |
| P2P 邀请码/信令 | 房主机器，隔离规则子进程也在房主机器 | 仅交换 offer/answer 和 STUN 辅助；不运算、不转发游戏 |
| 独立服务端 | 独立 server 机器 | 可在同服务启用信令角色，但不能据此将 P2P 权威放在 relay |

`p2p_signal_client.diagnostics().authority_host_mode=p2p_host_machine` 和服务端 `disabled_on_relay` 是显式边界声明，不是 PID/机器测量，也不会自行启动子进程。当前已有 P2P 运算会话在房主进程；实际隔离规则子进程接线由权威 worker 模块专项负责，须在其完成后核对 LAN、邀请码和信令全部 host 入口。运算位置不随房间管理权转让；密钥不匹配的继承须由已认证房主明确指定，不允许信令房间码或先到者取得权威。

## 静态及未来 Godot 专项

新增 `tests/net_p2p_authority_boundary_test.tscn`：拒绝 game_intent/relay/forward，拒绝回复夹带游戏数据、重复 created/offer、TURN 配置、relay 候选；未连接发送不能报成功；直接设置非法码长也不能启动监听。无网络的反例专项不能代替真实直连。

允许启动 Godot 后还需串行跑 `net_p2p_signal_client_test`、`net_p2p_expiry_direct_test`、`net_p2p_guard_rollback_test` 和新增边界专项，核对退出码、RESULT、SCRIPT ERROR。旧测试报告不证明本批修改通过。

## 现场异地公网夹具

1. 三台实际机器：房主 H、异地客机 G、独立信令 R；记录经人工脱敏的网络标签（例如不同运营商/路由器），不要记录密码、恢复票据、私有密钥或完整 SDP。
2. 复用正式大厅 P2P 信令入口，配置现场 STUN 和可信 WSS；当前 CLI 明文 WS 不是 TLS 支持证明。未知 NAT 类型照常尝试 ICE，不根据路由器品牌或两个 STUN 端口猜测并拒绝。
3. 用系统进程树记录 H 的实际规则 PID 与父进程，证明不是 R 或 G 启动。确认 G `GameStart._started=false`；独立 server 模式另测 server 机器 worker，不能混用本夹具的 P2P 通过结论。
4. 收集完整 ICE/抓包证据，记录实际 selected candidate（host/srflx/prflx）；没有公开 selected-pair API 时标为不可观测并保留未验收，不编造。TURN URL、relay candidate 一律反例拒绝，不自动兜底。
5. 建立实际会话并完成批准数据同步；记录双方接收的有序业务消息编号。关闭 R 的信令服务（不得关闭 H/G 的会话 driver 或游戏传输）；双方继续 poll 并发送真实准备/意图/权威过滤快照，记录关闭后的双向业务接收。
6. 在 R 抓包及应用日志核对没有对局数据转发；STUN 包和信令 SDP/ICE 不算游戏包。只看到 WebSocket 关闭或 peer connected 不足以证明直连游戏流量。
7. 再尝试新握手应失败并明确提示，不影响旧局；另断开 G 并验证凭据恢复只有信令恢复后才可新握手，不能把旧直连存活冒充重新建连。
8. 覆盖不同 NAT/IPv4/IPv6/网络限制组合：失败保留原因、超时与流量证据，禁止以换 TURN 求通过。多人/长期及 Linux 仍独立验收。

复制 `tests/fixtures/p2p_public_evidence.template.json` 到独立现场报告目录，填入真实观察值；保持 `status=unverified` 直到逐项复核。`logs` 为四条 `{role,path,sha256}`，role 分别 host、guest、relay、network_capture，路径相对该报告目录。脱敏后计算哈希，原始敏感抓包受限保存，不公开上传。

`python tests/validate_p2p_public_evidence.py <现场报告.json>` 只检查证据文件存在、SHA-256 及必填断言；它不证明标签真实、日志可信或网络实际直连。模板应返回失败，这是“未验收不得报通过”的负例。

## 当前诊断结论

- 保留直连游戏流量与 STUN-only 配置；没有新增 relay 游戏转发或 NAT 拒连逻辑。
- 新诊断只读真实信令/传输状态，已应答握手数量不等同 WebRTC 成功连接。
- 本批修复信令发送失败仍置 sent、客机回复缺少字段白名单、重复握手重建入口、未直连时错误断开文案、客机配置延迟校验与直接 TTL/码长未校验。
- Godot 运行、实际子进程位置、关闭信令后的本批直连回归、公网/异地均未验收。
