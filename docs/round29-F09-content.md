# Round 29 — F09 主机内容消息闭包

## 结果与所有权

本轮只迁移客户端内容上报、数据确认、批准内容下载这一簇：`catalog / data_ack / blob_request`。新增无状态 `scripts/net/session/host_content_inbox.gd`，仅修改 `scripts/net/session/lobby_session.gd`，新增 `tests/host_content_inbox_contract_test.gd/.tscn`。不修改 authority/gateway/manager/blob_receiver 或既有房间 inbox；未提交 Git。

按实际 `_receive` 主机请求 switch 的字面分支程序化扫描：本轮开始剩 **23 kind**，本轮迁出 **3 kind**，现在剩 **20 kind**。旧方案中的 `request_manifest` 在实际源码中不存在，不新增协议冒充迁移。manifest 发布和原始 blob/provider 数据帧位于请求 switch 外，不计入 kind 总数。

| 簇 | 全部 kind | 状态 |
|---|---|---|
| 房间管理（4） | ready, settings, transfer, kick | Round28 已迁出，原模块保留 |
| 本轮客户端内容（3） | catalog, data_ack, blob_request | 完整收件闭包迁出 |
| 服务端内容管理（4） | server_data_catalog, server_data_prepare, server_data_commit, server_data_cancel | 剩余；独立服务端管理信号职责，不混迁 |
| 选人/对局（7） | start, choose_master, begin_match, preview_group, match_command, broadcast_confirm_absent, match_finished_lobby | 剩余 |
| guard（4） | guard_continue, guard_skip, guard_restart, guard_lobby | 剩余 |
| 身份/凭据（5） | join, identity_candidates, identity_inherit, identity_ack, room_password | 剩余 |

累计请求 kind 迁出为房间4+内容3，剩余为服务端内容4+选人/对局7+guard4+身份5。没有将 F09 整项标为完成。

## 前置发布顺序与中文 V4A 说明

先追读实际生产链：`publish_blob` 仅发布候选字节；`_can_publish_room_files` 使用真实 assembler 校验清单，检查各批准 hash 已发布且尺寸匹配，并预编码 manifest；`_commit_room_files` 安装原清单和资产对象、递增 data_revision、清原确认表、确认主机、撤销全部 ready，再按真实 member 发送 manifest，最后 `_publish`。客户端 `_accept_room_files` 清资产安装态；RoomDataSync 使用原 receiver/cache 下载、校验和 assembler 组装；`install_room_assets` 真实安装后才发送当前 ACK。join 的身份绑定/恢复票据、先发清单再发 selecting/playing 投影及最终房间发布顺序不变。

- `HostContentInbox.handles` 只声明本轮三种 kind；`receive` 是完整同步请求作用域，不保留任何字段或 Session。
- 注入的是当前真实 Room、稳定 actor、原 catalogs/确认 Dictionary 引用、当前 revision/目录消息预算、原 `_queue_blob` Callable；没有复制长期状态，没有 lambda 捕获 Session，没有服务定位器、总线或反向引用。
- catalog 的大厅/Array/累计消息预算检查及 DataCatalog.accept 验证和原目录写入迁入模块；成功仅通知 catalogs_changed，不发布房间。
- data_ack 的非负旧 revision 静默忽略，seq 已由 Session 消费，不改确认表、房间 revision 或身份状态；当前 revision 写原确认表、递增房间 revision，然后由 Session `_publish`；未来/畸形 revision 保持原请求失败回执。
- blob_request 的类型检查与原队列能力调用迁入；下载批准白名单、在线成员、offset、重复任务、请求预算和 revision 绑定仍唯一由既有 `_queue_blob/_pump_blobs` 执行。排队失败保持原 `blob_error`；畸形字段保持原无入队、无房间发布行为。不复制鉴权/分片/缓存。
- Session 的生命周期拒绝、LAN/RSA 来源 gate、connection→稳定 member、协议、在线检查、旧 seq 拒绝和 seq 消费全部保留在两个 host inbox 之前。所有错误保留原 seq 关联。
- 新增客户端当前 ACK 发送门：`request` 在 seq 增长/发送前检查原 `_assets.is_installed()`，未装资产返回 ERR_UNAVAILABLE；新清单清安装态后必须重新真实安装。它保护正式客户端 API，不声称主机能远程证明恶意客户端的本地磁盘安装；直接绕过 API 的远端不可信声明仍受既有来源/seq/revision 协议约束。
- 恢复批准根先验、恢复数据屏障、require_room_data/rules revision 门和默认能力声明 false 均未修改。未改 validator/project 并发池20配置。
- 编辑使用 V4A 锚定补丁，不覆盖共享 Session 全篇，不改其他代理未提交文件。

## 真实执行证据

Godot：`D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`。

实际通用命令：

```
Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path E:/Fate-F09-content-r29-agent/project --scene res://tests/<name>.tscn
```

使用独占、无符号链接/目录 junction 的 E 盘工程完整副本（静态文件也实际复制），APPDATA/LOCALAPPDATA 为该根 profile/roaming、profile/local；新专项断言真实 `user://` 解析到 E。180秒前台看门狗仅能 kill 本次 Popen PID；所有运行自然退出、timeout=false，不修改系统 TEMP 或正式用户存档。

| 运行/专项 | RESULT | exit |
|---|---|---|
| red（初始夹具） | 缺 selection_mode 导致真实主机失败；已修新夹具 | 1 |
| red-corrected | 10 checks；模块缺失、未装资产 ACK 未拒绝两项预期失败 | 1 |
| green-first | 18 checks，无失败 | 0 |
| green-full（夹具修正前） | 50 checks；blob 错误断言误期待“拒绝”，真实原语为“请求的文件不可用” | 1 |
| mutant-ack（仅副本） | 55 checks；删除当前 ACK 确认表写入后，屏障发布/稳定 member 确认两项变红 | 1 |
| green-frozen / host_content_inbox_contract | **55 checks，无失败** | 0 |
| client_match_inbox_contract（F06） | 最终45 checks，无失败；原34是同一次运行的中间 RESULT | 0 |
| client_blob_inbox（F07） | 112 checks，无失败 | 0 |
| client_identity_inbox_contract（F08） | 58 checks，无失败 | 0 |
| host_room_inbox_contract（F09房间） | 34 checks，无失败 | 0 |
| ack_identity_regression | 22 checks，PASS | 0 |

上述最终成功六套由 JSON 聚合确认全部 exit=0、timeout=false、errors=[]，没有 SCRIPT ERROR/原生 ERROR。`git diff --check -- scripts/net/session/lobby_session.gd` exit=0。

新专项实际执行 RSA 挑战+ENet UDP：认证稳定 member 入房、已发布字节/批准 manifest、未装资产 ACK 拒绝、真实 blob 下载/cache/assembler/RoomAssets 安装、当前 ACK 房间发布、替换 revision 清确认及资产态、旧 ACK 不污染身份/确认/房间 revision、未来 ACK 拒绝、旧 seq 拒绝、自报 actor 不替代稳定 member、空/非空目录及真实文件扫描、实际 provider_blob_request 上传与 hash 校验、上传不授予批准下载权、畸形目录/累计消息预算、owner 转移后上报、非大厅目录拒绝、非批准/越界/畸形 blob 不入队、全部生命周期门、关闭清原状态与 WeakRef 释放。没有 mock RSA/receiver/cache/assembler 结果。

## 明确保留的红记录与验收边界

额外补跑旧 `net_blob_authorization / net_catalog_exchange / net_data_sync`，实际 exit=1：分别停在三端入房、目录/提供者传输、下载组装；没有 SCRIPT ERROR。其夹具没有安装当前生产 LAN/RSA 身份前置（直接 host/join），blob 夹具后续还保留旧 `prep.session` 配置方式。未修改这些非本轮拥有的测试、未降级认证、未把它们算成功；保留日志供其唯一写入者修正。不以未运行的修正夹具声称回归通过。

本轮验收是真实同进程 RSA/ENet，不是独立主管/worker IPC、崩溃恢复、GUI 窗口或发行包整链。恢复批准根/默认 false 能力仅保证本轮未动并由原回归覆盖相应契约，不声称重新执行全部恢复窗口链。

## 归档、回收、交接

报告/真实命令/PID/exit/日志、成功聚合 `summary.json`、全生产脚本冻结 SHA256 清单、四个本轮源码副本、运行器/归档脚本：`E:/Fate-F09-content-r29-agent/reports/`。

已归档并按自身独占目录预扫无 reparse/link 后回收 project/profile，读回确认二者不存在、reports 保留；未停止其他 PID，未触碰正式存档或其他代理根。不需用户决定回收。

最终本轮文件 SHA256：

- lobby_session.gd：`e313108f496d9e127f8a622a3f8510e6348adbad2dd9cbeec78eec127f18ddd4`
- host_content_inbox.gd：`c0adf22f1d09d0b19b69f0a0f6b5ca0b1d7e304405226fb009b836924128f5ce`
- host_content_inbox_contract_test.gd：`0168745c5ee75a2c56663c0c30f40e529eb9b29f1e52c487ec357aad2be74349`
- host_content_inbox_contract_test.tscn：`a5157e36014a1a80beab713b8cc614193e2d249cc172385498d111495b7ad114`

`/tests/` 受项目 gitignore 忽略，新测试确已落盘但普通 status 不显示；未擅自 git add，主代理纳入交付时需显式处理。技能 godot-content-capability-injection 已补充此次无状态内容闭包与 ACK/旧 RSA 夹具教训。
