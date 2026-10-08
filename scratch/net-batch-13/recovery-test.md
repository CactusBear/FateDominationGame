# 恢复测试断言顺序静态核对

## 结论

- **确定的旧状态断言**：`net_server_archive_match_test.gd:65` 要求无凭据请求后 `pid == old_pid`，与生产 manager 确认退出后释放进程所有权、置 `pid=-1` 的契约冲突。该项 false 不能证明无凭据触发了新进程，也不能证明恢复权限失守。
- **本次真实恢复链阻断**：既有 `E:/Projects/Godot/FateDomination/test/logs/godot.log:25–27` 显示甲已到 `playing/data_revision=3`，乙仍保留 `restoring/data_revision=2` 的大厅视图且报“房间连接已断开”；accepted 为 `[3,2]`。这是恢复期间第二客户端断线/未完成新版本屏障，不能归为上面 PID 断言的级联（check 不中止执行）。其具体断线源尚不能由现有日志唯一定位。
- **下游级联**：`midmatch:8` 的“可继续操作的真实中局”在 `_recover_match()` 未成功后仍执行；此时失败是未恢复成功的下游结果，不是另一条独立终局恢复缺陷。后续终局与双方新增操作断言亦须先满足恢复门槛才有独立诊断价值。
- **另一批真实生产阻断，不混作当前恢复失败**：旧 save/close 产物 `4245097`、`5042475` 的目标房间停在 `selecting`、bindings=0、match.log 仅 8 字节/零帧，属于录制开局失败，根本未到恢复中局。当前 godot.log 的前置目标、录制、绑定断言已通过，不能沿用上一批“尚未开局”结论。

本报告只读静态源码及现存日志/磁盘产物；未运行 Godot，未改生产或测试源码。日志是可覆盖文件，以本次读取内容为证据，不把旧报告对 godot.log 的引用当成当前内容。

## 1. 实际动态派发与断言顺序

继承链：`recovery_midmatch → recovery_match → archive_match → server_match → match_journal`。`recovery_match` 只转发 `_after_baseline()`；中局子类覆写该钩子，故不会执行 archive 默认的“重放完整终局”断言（archive:28–42）。

| 顺序 | 位置 | 条件/实际含义 | 失败后的行为 |
|---|---|---|---|
| 1 | server_match:42–62 | 两端同步数据、安装、ack/ready、can_start | 安装失败会清理退出；can_start 的 check 自身不退出 |
| 2 | server_match:74–110；midmatch:3–4 | 发送 start/选人/begin；目标为双方 decisions>0、round>=2、game_over=false | 总目标或双方操作断言失败后仍返回 board |
| 3 | archive:12–25 | 只有一个 matches 目录；read_all 可读、未截断、records>1；首记录 remote 座位/int64预算 | check 失败仍进入后续 baseline/recovery；parsed.ok 不等于非空记录，records[0] 另有潜在越界 |
| 4 | server_match:64–65 | 本地规则状态未改变，然后 await 动态 `_after_baseline` | check 不阻止恢复 |
| 5 | archive:45–50 | 保存客户端五字段 expected；读 recovery.json，断言 bindings.size()==2 | 失败仍关闭传输并 kill；JSON 非 Dictionary 另可能造成脚本错误 |
| 6 | archive:51–57 | 关闭双方 transport、kill(old_pid)、poll 至 worker 不 ready | 不 ready 不是完整退出/所有权释放断言；失败仍继续 |
| 7 | archive:58–66 | intruder 发无凭据 join，等 error；要求 error 非空且 PID 保持 old_pid | 旧 PID 条件错误；false 不终止，intruder.close 后继续 |
| 8 | archive:67–73 | 两端 reconnect() 返回 OK；等待新 worker ready | OK 只表示发起连接，不表示凭据接受、match bind 或恢复成功；ready 不等于已恢复对局 |
| 9 | archive:74–103 | 每端依 data_revision 同步/安装并 ack；等 `_recovery_matches` | 同步 begin 失败有 return，但函数无成功返回值；超时仅诊断+check，仍返回调用方 |
| 10 | midmatch:8–14 | 再检查非空/非终局；记录 previous、重绑 group、清发送去重状态 | 不检查恢复成功结果，仍继续 act |
| 11 | midmatch:15–21 | poll/act 至双方 game_over；双方 decisions 比 previous 大 | 上游未成功时是级联；decisions 仅提交计数，不等于权威成功执行 |

`match_journal_test.gd:10–14` 的 check 只计数、收集失败、打印，不抛异常、不终止。`finish:16–18` 才汇总退出；本次 godot.log 没有 RESULT，不能宣称本套已执行完成或终局续行已验收。

## 2. 无凭据断言：生产契约与旧状态

- `server_room_manager.gd:217–224`：进程确实退出且释放自己的 ownership 成功后，设 `room.ready=false`、`room.pid=-1`、清 process_token，保留目录与登记。
- `server_gateway.gd:186–198`：未就绪实例先验证 `_valid_room_resume`；无凭据先 `_fail` 返回；只有凭据有效且 binding.pid<=0 才 recover_room。
- 因此 archive:65 的 `pid==old_pid` 与正常死亡登记相斥。本次日志第21行的复合 false 不能拆解为“intruder 没被拒”或“intruder 启动了 worker”；日志没有打印 intruder.error/PID/instance_id。
- 建议主代理把死亡阶段与权限阶段分开：先确认进程退出、ownership 释放、保留 room；捕获**死亡登记后的**完整 instance binding；再发 intruder，请求被明确拒绝且 binding 未产生新实例/PID、没有新 spawn。不能通过要求旧裸 PID 恒定来证明无未授权恢复；PID 本身也不能作为实例身份。

## 3. 当前既有运行证据与生产阻断边界

读取的 `E:/Projects/Godot/FateDomination/test/logs/godot.log` 共28行：

- :11–18：中局目标、双方 gameplay、录制目录/可读日志/首帧、无本地规则污染、两座位 bindings 全部 true。
- :19–24：退出 true；无凭据实际 join true；复合 PID 断言 false；两次 reconnect 发起 true；恢复 worker ready true。
- :25：甲大厅 phase=playing、revision=22、data_revision=3、乙 connected=false；甲 error为空，accepted=[3,2]。
- :26：乙大厅 phase=restoring、revision=15、data_revision=2、error=“房间连接已断开”；乙视图中的 connected=true 是断线前保留状态，不是当前在线证明。
- :27–28：五字段恢复一致 false、可操作中局 false。没有后续终局、双方新增操作或 RESULT。

使用成员ID（甲1208567934、乙1864658225）与磁盘 recovery.json 交叉关联到：
`tests/runtime_reports/server_match/3092128/workers/34350fbb69fd083670b40cbf60cb7d69/`。

该产物 recovery.phase=playing、data_revision=3、bindings=2、乙connected=false，与日志一致；包含两份独立 engine.<instance>.log 和 restore-<instance> 目录。两个 matches 子目录各 match.log=56972字节、结构帧18、无尾部残余。这里只按 journal 帧长格式检查结构，没有 Godot 解码/摘要校验，不能称18个操作成功或完整日志语义通过。恢复后多一个存档目录也不违反 archive:18 的初始断言，因为该断言发生在崩溃前，恢复后并未再次要求只有一个。

**分类**：第二客户端在恢复版本2→3期间掉线，是需要排查的真实生产恢复链阻断；甲 playing 不能替代双客户端恢复验收。现有信息不足以断言是网关旧路由误 detach、新清单同步导致断线、worker重启还是另一个原因。建议记录每端 server attachment 的实例绑定、disconnect理由、match_bind观察者、mirror是否非空与seq、同步revision切换及各阶段时间点，再定位；不应先改五字段比较或删除终局断言掩盖阻断。

## 4. 恢复比较的覆盖缺口与“旧镜像”边界

`archive:121–130` 只比较 round、phase、current_player、game_over、observer，不比较牌区、资源、地图、待答效果、日志/存档哈希、room实例或数据屏障。它不是“同一完整局面”的充分证明。

- 初始 play_agents target失败仍允许恢复；expected 可为 `{}`。`_recovery_matches` 会允许两个空镜像与两个空expected相等，形成假恢复成功。
- 恢复匹配本身未显式要求 accepted_revisions 等于当前revision、phase=playing、所有原成员connected、新实例match_bind完成。因此五字段碰巧相同仍可能过早 break。
- **不能笼统声称重连继续使用旧 match 镜像**：`lobby_session.gd:188–215` 的真实 reconnect准备会 `_mirror.reset(-1)`；`view_mirror.gd:14–17` 清镜像。read_match（lobby_session:1446–1447）读取的就是镜像。相反，大厅 `session.view`、room_files等没有在该 prepare 中清空；诊断里的大厅旧视图确实可能保留。这两个对象必须分开。
- 重连等待 ready循环只调用session.poll，不做 RoomDataSync；之后同步循环才安装ack，所以 ready只证明worker入口就绪，不能证明对局恢复。
- midmatch:21 的 decisions 增量只证明客户端发送活动；需新增权威接受/提交存档推进等证据，不能仅凭新decisions宣称新真实规则操作成功。

## 5. 旧 save/close 证据只作独立问题

本次实际重新读取产物，而非照抄旧报告：

| 批次/目标room | recovery.phase | bindings | match.log字节/结构帧 |
|---|---|---|---|
| 4245097 / 0b61bf053c0211cf88950896b1c6659d | selecting | 0 | 8 / 0 |
| 5042475 / c2f87eed81d7313a6e61ec1bade4e90b | selecting | 0 | 8 / 0 |

5042475另一房间253b3a0d887192e4dbe212d953844f87是lobby，成员“另一房间玩家”，不能混入目标局。

这些空日志证明旧批次没有有效首帧与成功开局绑定；具体首帧失败分支需读取对应 authority/journal error才能确认。它们不能反驳本次godot.log中已通过的开局/存档前置断言，也不能把当前恢复失败降格为未开局级联。

## 6. 给主代理的最小修正顺序（本代理未实施）

1. 修复旧PID安全断言，以退出后的instance binding不变与明确拒绝作负例；保留生产拒绝逻辑。
2. 给 play_agents/录制前置/退出/reconnect/_recover_match 引入明确成功门槛及失败后清理退出；使恢复函数返回bool，midmatch仅在true时续行。失败门槛不能只吞掉已有失败统计。
3. 恢复比较增加非空新镜像、新实例binding、双方在线、当前revision同步ack成功、权威同局状态证据；避免空expected和五字段假绿。
4. 保留终局/双方操作要求，但以权威接受或提交记录补强计数；把其失败与恢复阶段失败分开记账。
5. 查乙在恢复期间的断线源；现有ready=true不等于此生产阻断已解决。主代理后续串行Godot验收需分别核对退出码、RESULT、SCRIPT ERROR，当前报告不提供运行通过结论。

## 修改与验证范围

- 唯一写入：`scratch/net-batch-13/recovery-test.md`。
- 静态核对继承/动态派发、check语义、恢复断言顺序、manager退出登记、gateway恢复权限入口、session重连清镜像契约；读取当前既有godot.log并用成员ID关联runtime_reports状态；程序检查指定journal结构帧。
- 未改任何.gd/.tscn、恢复文件或原日志；未运行Godot、未解码Godot二进制日志语义、未验收窗口/终局。
