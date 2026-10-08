# net_server_match_test 状态机只读追踪

## 结论

当前 save/close 两次失败的**第一个未满足转移是 `selecting → playing`：`match_authority.start(...)` 的录制开局没有成功返回，尚未建立网络对局绑定和可操作视图**。不是 ready/data barrier 卡住，也不是已进入第二回合后 target 表达式错误。

进一步定位到录制首帧：两次目标房间均已创建存档目录和 `match.log`，但文件只有 `FATEJNL1` 8 字节、零帧；`transactions.log` 已有 13 帧。按现有源码正常调用链，`MatchReplay.begin()` 已执行到 `journal.create()`，首个 header 的 `append` 未成功。现有日志没有保存该阶段的 `candidate.error` / `journal.error`，不能诚实地把具体失败分支断言成某一种类型校验或审计错误。

严格区分历史失败：23:05、23:09、23:14 的旧失败已进入 playing，存在事务审计身份/次数（其中 card_id 为负数）错误；最新 save/close 是 decisions=0,0、recovery.phase=selecting、bindings={}，属于更早的开局失败，不能拿旧局几千次 decisions 当成本次状态。

范围：只读源码及既有日志/产物，未运行 Godot，未改生产文件。路径中的批次目录不是测试开始时刻，依据 room/request ID 关联日志与产物。

## 实际证据

### save

- `E:/Projects/Godot/FateDomination/test/logs/godot2026-10-07T23.20.07.log:4–10`：网关、预算传递、两客户端清单接受/安装、双方 ack 后 can_start 全部 true。
- 同日志 `:11–12,22–24`：target=false、双方 gameplay=false、save 返回“当前对局未启用录制，不能声明存档成功”、`decisions=0,0 errors=请求无效/`。
- 返回 room=`0b61bf053c0211cf88950896b1c6659d`，对应 `tests/runtime_reports/server_match/4245097/workers/<room>/`。
- 此目录 `recovery.json`：phase=`selecting`，双方 connected=true、ready=true、spectator=false，bindings={}；`config.json` 的 record_matches=true、transaction_log=true。说明“未启用录制”是没有成功持有录制器，不是管理员开关没开。
- `matches/2026-10-07T23-14-44_80b2defc2648799e6c397b8e/match.log`：8 字节、零帧；同目录 transactions.log：10940 字节、13 帧。

### close

- `E:/Projects/Godot/FateDomination/test/logs/godot.log:4–15`：相同 ready/data barrier 全通过，target=false、双方 gameplay=false、存档内容断言=false。
- `:23,31–33`：先保存再关闭断言=false、最终保存回执断言=false、decisions=0,0。末尾连接/实例错误是在关闭以后，不能当成 play_agents 初始卡点。
- 目标房间 `tests/runtime_reports/server_match/5042475/workers/c2f87eed81d7313a6e61ec1bade4e90b/recovery.json`：phase=`selecting`，两成员 ready/connected=true，bindings={}。
- 另一房间 `253b3a0d887192e4dbe212d953844f87` 为 lobby，只有“另一房间玩家”；不能混用其状态。
- 目标房间 `matches/2026-10-07T23-20-47_24c020455ad5364743fb88aa/match.log`：8 字节、零帧；transactions.log：10936 字节、13 帧。

二进制帧计数用 Python 按源码格式读取：8 字节 magic 后，每帧为 4 字节 little-endian body 长度 + 32 字节 digest + body；没有借用 Godot 解码器，也没有把 ASCII 扫描冒充完整日志语义解析。

## 完整状态机及门槛

拓扑：两测试客户端 → 公共 server_gateway → 房间 ENet 路由 → 独立 server_room_worker；规则和存档由 worker 内的 LobbySession/NetworkMatchAuthority 计算，客户端仅镜像视图、提交指令。没有本机客户端规则计算，也没有 P2P 信令参与。

| 阶段 | 测试入口/发送 | 权威端转移门槛与输出 | 本次证据 |
|---|---|---|---|
| 创建房间 | `net_server_match_test.gd:23` 甲 join_server 创建；`:25–32` 等 room view，20s | gateway 创建/验证 worker，首真人成为 dedicated room.owner；加入后发布 room 和 room_files | 已通过，非 SERVER_JOIN_FAILURE |
| 乙加入 | `:34–41` 乙以甲的 server_room_id join，等待清单 5s | 成员加入，同 data_revision 清单发送给该成员 | 已通过后续两份安装断言 |
| 下载/安装 | `:42–56` sync.begin→poll，45s；sync.complete AND install_room_assets | 客户端接受实际服务端 manifest；全部文件验证后才组装资产 | 双方 true |
| ack/ready | `:57–62` data_ack(revision)、ready(true)，等 can_start 5s | LobbySession `:759–763` 要 revision 为 int 且等于当前；RoomState `:65–78` 要 lobby/成员在线/非观战、最低人数和全真人 ready；data_ready 要 rules revision 与 data revision 一致、在线成员 ack 当前版本 | can_start=true，已满足 |
| start | `:75` 甲发 start，一次 | LobbySession `:847–851`：owner + room.can_start + data_ready + _prepare_selection；RoomState `:80–85` 设 selecting；发布 selection | recovery.phase=selecting，已满足 |
| 选御主 | `:88–91` 两客户端选择 choices 首/末项，一次置 picked=true | selection_authority.gd `:34–39`：sender 控制 seat、御主存在且规则接受；成功后发布 selection | 开局审计和 match.log 创建表明已走到录制开局；不是纯等 choices |
| begin_match | `:102–104` 甲见 selection.complete 后发送一次，立即置 began=true | LobbySession `:774–781`：owner + selecting + data_ready + match_authority.start；仅 true 后设置 playing、bind、publish_match | **首个未满足转移**；仍 selecting，无 bindings，无 decisions |
| 建立客户端视图 | `:92–99` read_match 非空→group.bind_session→act | LobbySession `:1511–1529` 发 match_bind 和 match_view；客户端 `:617–630` 先绑定 observer，再 mirror.accept(state)，同时保存 pending/actions；read_match `:1442–1446` 从 mirror 读取 | 本次没到达 |
| 每帧推进 | `:83–106,112–116` gateway.poll→双方 session.poll→process_frame；每次 pump 后检查 target，再双方 act | worker/session 的 match_authority.step (`match_authority.gd:387–418`) 推动 driver、AI 待答、回合帧；变更发布视图 | 本次因 start 未成功不能正常推进 |
| 达成目标 | `:107` deadline 后再次 target 断言 | 见下一节，不检查 ready | false |

### 录制开局内部细化

1. `match_authority.gd:20–24` 拒绝已开始/选人未完成/预算非法；准备种子、分配姓名。
2. 录制开启走 `:45–52`：创建 MatchReplay，声明两 seat=`remote`，调用 `candidate.begin(...)`。只有成功后 `recorder=candidate`、driver=recorder.driver。
3. `match_replay.gd:31–67`：校验预算/不覆盖→复制数据→构造 header→begin_audit(transactions.log)→`_start` 启动真实 GameStart→initial_hash→`journal.create(match.log, header)`→最后 `_recording=true`。
4. `match_journal.gd:333–358`：打开 match.log、写 magic，随后 append(header)。`append :360–367` 先 flush_audit；`_append_record :369–419` 检查 error、文件、plain 结构、写入长度、帧大小等，成功才写首帧。
5. 本次 match.log 仅 magic，说明正常串行链至少执行到步骤 4；步骤 4 的首帧未成功。本次事务帧已经产生，不等于录制器成功启动。
6. 返回失败后 `match_authority.gd:49–50` 保存 candidate.error 到 authority.error；LobbySession 的 begin_match 没使用它，最终 `:870–872` 只发送 room.error 或“请求无效”。因此 save 客户端见“请求无效”丢失了真正的录制首帧错误。
7. `match_authority.gd:53–61` 的 flush/配置 controllers/started=true 尚未成功完成；大厅转为 playing 和网络绑定自然不会发生。

## 客户端 act 的全部推进/停滞条件（成功开局后的路径）

`tests/net_process_full_game_test.gd:11–76`：

1. view 空、game_over=true 或 sent_seq==view.seq：立即 return。
2. 有私有 pending：优先 cancel（允许取消）；否则 active_choice 选首个 available option，数量取下限；card_choice 先 required 再补至 min；player_choice 取前 min；location_choice 取首区域（空则 return）。pending 在 current_player 判定之前，因此对手回合也可答自己的效果。
3. 没 pending 且 current_player!=observer：return。
4. 有 deploy_areas：提交首区域。
5. actions.effects：每 round/phase/current_player/effect.id 只尝试一次 activate。
6. group.snapshot waiting/submitted：return；can_confirm 时确认并记录 sent_seq/decisions；否则有候选则 add 首牌/首 mode，等预览；最后提交 end_action。
7. send_command **发送时**就递增 decisions、设置 sent_seq，不代表权威接受。数千 decisions 可是拒绝重试，不是数千成功动作。
8. group_selection.gd:78–99 视图 seq 变化清选并请求 preview；:111–132 对应拒绝/预览回执释放 waiting/submitted；:65–76 只在 preview ok+can_submit 时确认。

权威提交：LobbySession `:782–795` 要 playing、非管理暂停、无玩家掉线、字段类型合法；NetworkMatchAuthority `:84–105` 要审计可刷新、seat/issued 存在、view seq/revision 最新、无 archive pulse、无 runtime guard 暂停。待答校验 effect 所属触发者，常规 deploy/play_group/end_action 则另要当前行动 seat（`:230–279`）。失败后仍 `_publish_match()`，不能以 client.sent_seq/decisions 断言提交成功。

## target reached 的真实定义与测试缺口

- 基类 `net_server_match_test.gd:131–132`：**双方 read_match.game_over=true**。
- 本次 save 继承 `console_save → recovery_midmatch → recovery_match → archive_match → server_match`；close 也沿 console_save 链继承。
- 实际动态派发到 `net_server_recovery_midmatch_test.gd:3–4`：**双方 decisions>0 AND round>=2 AND game_over=false**。这是中局目标，不是终局。
- archive_test `:3–4` 显式 record_matches=true，所以 play_agents 预算为 180000ms（基类 `:81`），不是 90000ms。
- play_agents 不因 target 失败提前返回：会继续 _after_baseline，故 console save/close 失败是对未成功开始的局执行管理保存的下游结果。
- picked/began 在“请求发出”时置 true，没有按拒绝回执重试；没有分别断言 start/selection complete/begin_match accepted/首次非空 mirror。唯一总体 target 断言把这些中间失败折叠到同一句话。
- 当前只读证据足够定位首个失败阶段，**不足以唯一识别 append(header) 的具体失败分支**。需要主代理后续在 worker 真实入口暴露 begin_match 的 authority.error/candidate.error/journal.error，并单独记录 playing、selection complete、match bound、首次 mirror、round；本次未添加埋点或运行测试。

## 交付边界

- 唯一新建文件：`scratch/net-batch-12/match-state.md`。
- 未运行任何 Godot 命令，未修改生产源码、测试源码、原日志或存档。
- 静态核对了 join/ready/start/selection/begin/recording/bind/mirror/act/authority submit/step/target 全链；既有失败日志和 room ID 对应磁盘产物已经交叉核对。
