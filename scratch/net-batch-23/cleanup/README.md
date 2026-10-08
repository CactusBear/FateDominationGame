# 退出引用环清理交接

## 结论与范围
生产文件未修改；只在 scratch/net-batch-23/cleanup 落盘。未运行任何 Godot、监听、worker、凭据操作或生产状态写入。
cleanup.patch 修改 2 个生产脚本；regression.patch 新增独立 GDScript 回归场景。
所有候选以 .gd.txt/.tscn.txt 存放，避免项目扫描候选 class_name。

## 继承链及真实清理入口
- LAN: lan_live_join_test → net_server_recovery_lifecycle_test → match_journal_test → Node。
  LAN run 覆盖祖先 run；cleanup 先 guest.close，再 host.close + _drain_close 回执/句柄等待，清 test_owner.authority_host 后 test_owner.close，调用继承 _close_and_check，最后 finish。
- Dedicated: net_server_recovery_midmatch_test → net_server_recovery_match_test → net_server_archive_match_test → net_server_match_test → match_journal_test → Node。
  继承 net_server_match.run/cleanup，覆盖 _match_target_reached 与 _after_baseline；archive 提供 _recover_match。
  _recover_match 中先关闭旧 session.transport、杀已拥有 worker、泵 gateway 路由退出、拒绝无票 intruder、原 session 重连；最终 cleanup 解绑 group、关闭 session、释放测试 agent Node、gateway.close。
  midmatch 覆盖的是局面终点与恢复后继续操作，不改变共有清理路径。

## 已静态确认的环（两套共有）
server_gateway._attach 创建 route，其中 route.link 是 ENet transport；message_received / packet_rejected / peer_disconnected 三个 lambda 都捕获 route。
引用链：link → signal connection → lambda Callable → captured route Dictionary → route.link → link。
Callable 还引用脚本/调用上下文；保留 gateway 上下文时会连带 manager、外部 transport、identity_registry 等，故泄漏对象数不能只按内部 links 数计算。
- 正常/崩溃路径 _detach_route 仅 routes.erase + link.close，没有断开三个应用层 signal。
- _attach 连接失败或实例过期两个 return 分支同样只 link.close，未登记 routes 的闭包环也无法被后续 gateway.close 找回。
- LAN authority_host_client.close 自己遍历 link.close + routes.clear，绕开 _detach_route，因此只修 gateway 常规 detach 不够。
- enet_transport.close 已正确断开原生 peer_connected/peer_disconnected，释放 _peer；它不会也不应清理上层订阅：LobbySession 会复用同一 transport 重连。

## 房主附加持有关系
host → gateway → public transport.peer_disconnected → 匿名 Callable（使用 _pending_joins/lan_identity 的房主上下文）。
把匿名回调换成命名 _peer_disconnected，保持清理内容完全一致，移除不必要闭包上下文/脚本保留；其是否对应 verbose 中 LAN 多出的对象，仍待主代理实测。
_session 是 WeakRef，不是 host↔session 强引用环；test_owner.authority_host 会在 cleanup 明确置空。
SceneTree.process_frame → host._drain_close 是有意保留的安全退出泵送，必须等回执与原生 EXITED/release 才断开，补丁不碰这个边界。

## 其他已核对关系（不扩大补丁）
- LobbySession transport 的命名回调是标准对象方法 Callable；不是捕获含自身 link Dictionary 的闭包，close 不能永久删掉这些订阅，否则 reconnect 失效。
- GroupSelection 强持有 session，但 cleanup 已 bind_session(null)，断开 changed/preview/rejected 并清引用。
- RoomDataSync.cancel 会清 _session；无信号闭包捕获自身。局部成功 sync 生命周期不构成本次已确认环。
- LAN identity bridge submit 的快照 lambda 为同步调用用途；不是本次路由 Signal 长期持有路径。
- 测试 agent 原有 free() 只处理未入树的测试 Node；本补丁不新增 free/queue_free，也不强制销毁任何活生产对象。

## 补丁语义
1. gateway 新增 _close_route_link：仅用于 gateway 独占的内部 route transport；断开三个上层应用 Signal 的连接，再执行既有 link.close。
2. 上述 3 处 gateway 退出点与 1 处 LAN 关闭点都改走此入口。活路由接线、路由身份校验、延后一轮重连、子进程保存和退出回执行为完全保留。
3. 房主匿名断线回调等价替换为命名方法。
该 helper 不可用于 LobbySession public transport：它故意断开内部路由独占的三个 Signal 上全部订阅，路由退出后不存在需要保留的订阅者。

## 静态验证
- 三个候选 .gd.txt：已有 inheritance-v6/parser-env 的 gdtoolkit parser 全部 PARSE_OK。
- cleanup.patch 和 regression.patch：git apply --check 均成功，命令退出码 0。
- baseline.json 保存 2 个生产文件 SHA-256；交付前再次比较一致，确认未写生产源文件。
- 默认 python 无 gdtoolkit，已切换现有 parser-env，不安装依赖。
- 未做 Godot 类型解析/运行验收；不能据此宣称 27/11、26/6 已归零。

## 主代理统一验收建议（这里均未执行）
先合并 cleanup.patch，再合并 regression.patch。新增场景 tests/net_route_cleanup_test.tscn 不启监听或 worker，验证失败 attach 同型闭包、gateway.close、host.close 与命名断线回调；WeakRef 检查自然释放，不强制 free。
1. --headless --verbose --fixed-fps 60 --path <测试副本> --scene res://tests/net_route_cleanup_test.tscn
2. 同条件跑 lan_live_join_test（HERMES_LAN_LIVE_ROOT 必须全新项目外目录），保留 worker 回执/句柄断言。
3. 同条件跑 net_server_recovery_midmatch_test，外部预算必须覆盖套件墙钟等待及清理，勿统一短超时。
记录每套退出码、RESULT、SCRIPT ERROR，以及 verbose 的 Leaked instance/Resource still in use 路径。新增 probe 应临时去掉 cleanup 修复确认 WeakRef 断言红（仅隔离副本），再恢复补丁。
本批提供最小候选，不逐项臆测残留 ID；如仍有泄漏，应按 verbose 具体对象继续定位，而不是清空活状态或 ObjectDB 强制 free。
