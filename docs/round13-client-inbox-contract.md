# Round13 — F06 ClientMatchInbox 可执行契约

## 实跑结论

GREEN：`RESULT client_match_inbox_contract_test checks=34 failures=0 status=GREEN`，Godot 4.7.2，退出码 0，无 SCRIPT ERROR。首次 32 项通过后补充手牌隐私正负对照，最终 34 项通过。

实际命令（仓库根目录）：

```bash
'D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --fixed-fps 60 --path . --scene res://tests/client_match_inbox_contract_test.tscn
```

仅新增 `tests/client_match_inbox_contract_test.gd`、`.tscn` 与本报告。生产 Session/Mirror/Selection 均只读；没有私有字段访问、私有函数调用或新增许可。消息通过真实 Session 已订阅的公开 `transport.message_received` 信号进入；这是边界注入测试，不冒称每个消息都经过 ENet 编解码。请求锁部分使用真正 loopback Transport listen/connect、公开 request 登记并实际成功发送，锁为公开信号驱动的测试观察模型，不冒称已经测试 UI 的锁实现。全程无窗口。

## 已冻结的行为

- 五 kind 非房主来源全部拒绝；绑定前 view 丢弃，畸形 bind 不授权，重复 bind 不改变观察者，bind 不发 changed。
- match_view 同步接受三投影；重放、回退、错误观察者、pending/actions 畸形拒绝且不部分提交、不发 changed；先新后旧保持新状态。
- 输入和 read_match/read_pending/read_actions 均深拷贝。未知 actions 字典内容目前透传，不擅自升级验证协议。
- 他人私人通知与他人手牌拒绝；手牌夹具去掉私人手牌后同一玩家公开视图实际接受，避免格式无效造成假阳性。
- group_preview 按到达次数发布（同请求重放两次仍两次 signal）；结果深拷贝，不发 changed；畸形预览拒绝。不把 F06 偷换成请求去重修复。
- selection 输入深拷贝、按到达顺序覆盖，旧 revision 当前仍覆盖新 revision。不在拆分中暗加乱序门槛。
- match_reset 清四状态并清 selection；未重新 bind 的旧 view 不恢复状态；重新 bind 可换观察者，视图 seq 从 1 重新接受。
- 五 kind 均不完成/解除已登记 match_command 请求；错误来源回执不解锁，正确回执只消费一次，重放/迟到 error 不二次完成；close 用 request_associations_invalidated 清关联且清投影。

## 新 ClientMatchInbox 唯一拥有的四状态

| 状态 | 所有权与语义 |
|---|---|
| `_mirror` | 唯一视图副本、观察者身份与 seq 验证；复用现有 MatchViewMirror，禁止复制其隐私规则 |
| `_pending_view` | 最近一次原子接受的 pending 深副本；公开 read 返回隔离副本 |
| `_action_view` | 与同批 state/pending 一起发布的 actions 深副本；公开 read 返回隔离副本 |
| `_match_bound` | 仅首次有效 bind 设 true；reset/close 清 false；不能从 view 猜身份 |

不能迁入 selection_view、request 序号/结果/代际登记、transport、identity、blobs、assets、authority、room。选择消息必须产生无状态输出供 Session 保存 selection_view，reset 输出通知 Session 清 selection_view；预览也只产生无状态输出。新模块可以有信号/方法/常量，不增加第五个持久状态或 session 反向引用。

## Session 精确转发边界与实施次序

1. `_receive` 保留原有 reset/restore/begin 禁入、客户端/房主分流与 `sender == 1` 来源门槛。只在普通客户端分支转发上述五 kind；F07 blob 与 F08 identity 原逻辑保持原位，F09 主机请求 switch 不改变。
2. Inbox 提供同步 `receive(message) -> bool`（是否识别其 kind），内部完成格式检查及原子接受；用 `changed`、`group_preview_received`、`selection_received`、`selection_reset` 无状态输出。Session 将前两者转发原公开信号，将后两者保存/清空原公开 selection_view。识别但无效的消息仍消费，不能落入其他分支。
3. Session 原公开 read_match/read_pending/read_actions 保留签名：读 Inbox；read_match/read_pending 的 `_map_assets(..., false)` 仍由 Session 执行，assets/data_revision 不入 Inbox。
4. `_clear_match_views` 与 close 调 Inbox 完整 reset；Session 自己清 selection_view。保持 match_reset 的 changed 次数，不因双层转发重复发布。
5. `_prepare_reconnect` 当前仅清绑定并 reset mirror，未清 pending/actions。需 Inbox 暴露专用 reconnect_reset 保持原语义；不能盲用完整 reset。此恢复入口本专项未动态覆盖，接线后必须补恢复专项。
6. 主机本地 `_bind_match`、`_publish_match` 也使用相同四状态，不能把客户端迁走后又在 Session 留影子副本。改成 Inbox 明确本地 bind/accept 入口；主机生产 state/pending/actions、资源编码、错误文案及对 peer 发送仍属于 Session。本地发布旧顺序与客户端首 bind 忽略重放语义不同，不强迫两者共享不适用的限制。
7. request / match_command_result / error / close 关联失效留 Session，Inbox 不碰请求锁登记。请求锁依赖 request_completed/request_associations_invalidated，而不是 view seq 前进或 match_reset。

## 文件所有权释放后的直接实施门槛

释放 E04 的 session 写入权后，由唯一写入者创建 `scripts/net/session/client_match_inbox.gd` 并串行接上述调用方；Mirror/Selection 无需修改。先保留本测试 GREEN，然后实际执行 net_server_one_round_test 与 net_v2 系列、恢复/重连专项；不得将本专项通过当成权威开局、资源路径、恢复全链或窗口验收已通过。

已读 hermesWarning、refactoring-plan F06–F09 和当前 Session。发现的重要边界不是额外审计问题：主机本地投影共享四状态、selection 不可成为第五状态、reconnect 的局部复位语义，以及请求回执与视图更新的独立性。生产拆分本轮未实施，按授权保持只读。
