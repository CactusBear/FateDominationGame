# net-batch-12：完整对局未推进的 P0/P1 与下一轮门槛

## 结论与范围

**当前不能宣称完整联机对局、原局恢复或安全保存关闭通过。建房/数据同步已在较新输出走过，新的首要阻断是事务审计/开局失败与失败后仍继续跑保存关闭的夹具。不要沿用 batch-11 的“save 尚未执行”作为当前结论。**

本次只读源码、既有日志及 `docs/real-world-multiplayer-test-plan.md`，只写本文件；未启动 Godot、未运行场景/导入/导出、未修改生产代码、未操作进程或凭证。日志是既有运行证据，不是本轮新验收。源码与旧日志可能来自不同工作树快照；以下明确区分“日志确认失败”“当前静态已改”“待新运行验证”。

### 固定拓扑

- 信令面：P2P 信令仅握手、交换候选和辅助打洞，不加载规则、不保存对局、不转发游戏流量。
- 数据面：LAN 客机直连房主内嵌网关；P2P 客机与房主 WebRTC 直连；dedicated 客户端经服务端网关；网关再路由至所在机器的 worker。
- 权威面：规则与存档只在房主机器或独立服务端机器的 worker，客机/观战 UI 不执行权威规则。管理房主转移不等于权威迁移；真人掉线不交 AI 托管。

## 1. 既有输出对账：先分运行，再谈根因

日志根：`E:/Projects/Godot/FateDomination/test/logs/`。下表只摘实际输出，不把轮转文件名当独立 run_id，也不假定命令、退出码或当次提交号。

| 证据文件/行 | 已证实 | 不能推出 |
|---|---|---|
| `godot2026-10-07T23.05.56.log:10–25` | 数据屏障为 true；目标未达到；决策 `3,3555`；save pending 后 result=false；事务审计整数拒绝；RESULT checks=17，列出目标及保存两个失败 | 有决策不等于双方完成回合；不证明真人输入或终局 |
| `godot2026-10-07T23.09.58.log:10–25` | 同类失败，错误定位到 `card_id:int`；决策 `4164,3` | 不是存储目录污染的证明 |
| `godot2026-10-07T23.14.11.log:10–25` | `ROOM_SAVE_ERROR` 明示 `card_id:int:-9223371112111405033`；目标未达到，保存拒绝；决策 `4105,3` | 不能把负 ObjectID 当损坏玩家 ID，也不能把大量尝试当成功动作 |
| `godot2026-10-07T23.20.07.log:10–24` | 屏障通过，但目标/双方决策/连续日志失败；决策 `0,0`、错误“请求无效”；save 返回“当前对局未启用录制，不能声明存档成功”；RESULT checks=16，列出四项失败 | manager 开启录制不代表 recorder 已成功初始化；不能仅凭此认定用户录制开关丢失 |
| `godot.log:10–33`（本次读取快照） | 目标失败，决策 `0,0`；close 仅 pending；进程退出和目录保留为 true，但保存关闭/退出后保存回执为 false；RESULT checks=24，列出五项失败 | 进程退出不等于先保存后关闭；目录存在不等于完整中局已保存 |

实例旁证（仓库 `tests/runtime_reports/server_match/`）：

- `3185955/workers/666f82a78629e11a87a4bb31520b18ad/engine.b82fdb6fb08a718f6bf4d93ffc5c74b2.log:4` 与 23.14 输出房间/实例相符，只证明该 worker 曾 READY。
- `4245097/workers/0b61bf053c0211cf88950896b1c6659d/engine.c13fbfe6a3411de1e1491a99b9a8abd8.log:4` 与 23.20 输出相符，也只有 READY；没有当次开局拒绝详情。
- batch-11 `test-data.md` 所述旧探针 READY→SUPERVISOR_LOST 与早期 SERVER_JOIN_FAILURE 是另外的运行。不得拼接为上述审计/开局失败的同一因果链。

**测试源码中的“真人”是座位类别，不是操作证据**：`tests/net_server_match_test.gd:15–20,99` 实例化并调用 `net_process_full_game_test.gd` 的自动策略；后者 `send_command():11–14` 在收到确认前累计 decisions。其 `checks` 和文字均不能自动填 RW 真人 PASS。

## 2. P0：先解除推进/持久化阻断，且不削弱安全拒绝

### P0-A 事务审计对象标识与整数边界：已有修订，尚未运行闭环

- **依据**：23.09/23.14 的 save 与动作拒绝可直接关联事务审计。`scripts/match/effect_checkpoint.gd:18–27` 的 `card_id` 来自 `source.get_instance_id()`；它不是成员/player_id。`match_journal.gd:237–248` 当前已经只对 root/effect/parent/ticket/consumption 拒绝负数，card/player 不再统一按非负处理。
- **状态**：日志失败已确认；当前审计校验存在修订，因此不要继续报“当前 card_id 一律拒绝负数”或重复实现同一修复。现有输出仍无修订后完整目标+保存成功证据。
- **可修复/补验**：沿所有 audit_event 生产者与消费者核对标识类型，ObjectID 允许的有符号表示与稳定审计身份分开；审计/存档不得经 JSON float 丢失 int64 精度。未知字段、非整数、NaN/越界、非法 root/ticket/次数仍失败关闭，不能用 abs/int 截断、关审计或吞错让对局通过。
- **门槛**：正/负 ObjectID、int64 边界、合法整值 float 与非整值 float、事务生命周期去重和重放一致性；真实 worker 的双方确认动作→到达声明目标→save 完成回执→日志记录/状态哈希一致。对应 RW10、RW17、RW21、RW23–24。审计写失败保持明确未确认，不自动重做已可能执行的动作。

### P0-B 开局事务失败与录制状态不一致：先暴露真正拒绝原因

- **依据**：23.20 决策为零，只有“请求无效”，随后 recorder 不可用。`scripts/net/authority/match_authority.gd:20–61` 在 `candidate.begin()` 或启动后 flush_audit 失败时返回 false；后者可能发生在 recorder/driver 已赋值后，但 `started` 尚未置 true。`scripts/net/session/lobby_session.gd:774–778,870–871` 的 begin_match 条件失败落到通用 room.error/“请求无效”，未保证传出 match_authority.error。`server_room_control.gd:80–85` 将 not started 与 recorder==null 合并成同一句“未启用录制”。
- **状态**：失败表征已确认；哪个启动阶段失败、是否有部分规则状态留存尚未获当次证据，不能把原因定为录制设置丢失。
- **可修复**：复用已有检查点/录制初始化入口，明确启动 prepare/commit/abort；失败恢复启动前的规则、随机流、recorder/driver 和房间相位，不能在 selecting 留一个部分启动的权威。向当前请求返回可脱敏的 authority.error 与阶段；区分“未开局”“录制未开启”“录制初始化失败”“审计失败”，权威状态回读后才显示开始成功。事务无法完整回退时明确暂停/失败关闭，不继续假装可重试。
- **门槛**：注入 candidate.begin 失败、初始化后审计/flush 失败、存档建立失败；核对旧状态不变/失败现场保留、请求只终结一次、成功路径双方首次已确认动作。对应 RW08–10、RW20、RW23–24。

### P0-C 本机权威安全关闭回执仍按清空后的房间号校验

- **依据**：当前 `scripts/net/session/authority_host_client.gd:126–138` 保存 `_closing_target` 后清空 `room_id`，`:152` 仍用空 room_id 校验 response.room；`:143` 使用裸 PID 存活检测。此项与 dedicated console_close 的失败是不同消费链，不作为后者根因。
- **可修复**：以不可变关闭请求绑定 room/PID/instance/mode/request_id 校验，使用已有原生进程所有权接口确认退出；重复 close 不覆盖 pending；写请求失败/拒绝/成功/退出未确认分别可读。UI 退出后的拒绝要留可查询渠道；不以超时/失心跳杀未保存 worker。
- **门槛**：未录制拒绝、写失败、重复关闭、旧实例/旧请求晚到、场景移交后排空、其他房间隔离；成功必须 saved 回执及原实例退出双证据。对应 RW16/RW23–24。

### P0-D 恢复/配置落盘的失败原子性仍须闭合

- **依据**：batch-11 `next-gates.md` P0-2 记录 recovery/config 的 tmp+rename 覆盖与失败回滚不足；它是既有静态风险，不是当前 card_id/零决策日志根因。主代理须核对实施中的实际 diff，不凭旧报告直接判未改。
- **可修复**：复用现有平台安全替换能力，检查写入/flush/替换；失败保持旧字节及旧内存权限状态，不提前发布密码/继承/暂停/恢复成功，不先删原档。保存关闭失败不得继续退出；身份继承与认证绑定保存失败不能轮换凭据。
- **门槛**：首次建立、覆盖失败、ACL/只读/磁盘写失败、旧档缺绑定失败关闭；逐字节/逐字段对账。对应 RW17–19/RW23–24。Windows 实际替换结果不能由静态解析推定。

## 3. P1：修夹具与请求闭环，消除假推进/级联误报

| 项 | 可修复缺口及具体动作 | 退出门槛/对应真人项 |
|---|---|---|
| P1-A 基线失败后仍做中局保存/关闭 | `net_server_match_test.gd:63–65` 即便 `play_agents()` 目标断言失败仍调用子类 `_after_baseline()`；save/close 的“中局”前置因此不存在。将基线返回明确阶段结果；未进入 playing、未到目标或录制未初始化时跳过依赖分支并记 BLOCKED/前置失败。保留专门“未开局关闭”用例，不让其冒充中局保存。 | 故意让 begin_match 失败，保存/恢复分支不执行且只记录原失败；正常基线后才核对 saved=true。RW17/RW23–24 |
| P1-B 自动驱动统计提交次数而非确认动作 | `net_process_full_game_test.gd:11–14,67–70` 提交前加 decisions；`:18` 按 view.seq 锁定。一次拒绝/过期视图可卡在旧 seq；大量拒绝也可能累计为几千 decisions。复用 request registered/request_rejected 和组合提交回执，分别统计 submitted/accepted/rejected；只解除对应请求，按新权威视图决策，不无限重发或把发送成功当执行成功。 | 过期/拒绝/发送失败/待答/异步归档，双方均有已确认动作，拒绝不会假累计推进；自动策略不替真人 RW10–11 |
| P1-C 开始/选人请求的先置位无回执 | `net_server_match_test.gd:88–104` 发 choose_master 后立即 picked=true，发 begin_match 后 began=true。若拒绝就不再尝试，也缺实际选人/开局终态关联。按请求编号与权威相位推进；明确失败停止依赖流程，而非盲重发。 | 选择冲突、开始拒绝、旧回执、发送失败各有终态及真实原因；RW08–09 |
| P1-D 启动请求关联不闭合 | batch-11 ready-chain/next-gates 已发现 server_create/server_join 的 pending 未绑定原请求 seq、server_attached 不足以区分 ready/路由/成员加入；request_seq 与客户端 seq 消费不一致。复用现有请求/实例绑定，分开受理、ready、attach、join，按当次 room/PID/instance/mode 回读并终结失败。 | 旧/坏 ready、路由失败、超时、创建者断线、重复/乱序请求、发送失败；RW04/RW08，不以 READY 当入局 |
| P1-E close 生命周期断言不完整 | 当前 console_close 测试只查询 response，没有 request 删除、forget 后 response 删除且 recovery/matches 保留的断言；未覆盖 response 写失败。`server_room_control.gd:24–26` 见同名 response 就删 request，未校验归属。加真实消费点校验和故障注入。 | request 删除→response 可读→显式 forget→重复 result/forget 拒绝；回执写失败 request 保留、不退出；RW23–24 |
| P1-F 录制/恢复与密码 UI 契约 | batch-11 报告中的大厅录制只改本地字段、Archives 沿用旧 `_host`、建房前密码非创建保护事务需核对。显示实际 worker 录制/目录；已建房不允许本地假切换；能力不可用给明确原因；区分加入密码与房主大厅设置密码。不得改 `_host=true` 或取消 LAN/P2P 恢复安全阻断。 | 权威回读、管理房主转移、默认无密码/设置/清空/越权拒绝，RW05/RW15/RW23 |
| P1-G 心跳共享阻塞 | batch-11 process-owner F2 静态确认 Windows PowerShell Replace fallback 同步无期限、多房间串行；原生 terminate 等待也阻塞共享 owner。收敛为短原生替换或受控异步/明确期限与实例隔离；不延长超时掩盖主管饥饿。 | 条件触发 helper 延迟/停止等待，多房间活性与错误隔离；独立探针 READY 后 supervisor version 持续递增，RW16–17；本轮未复现此风险 |
| P1-H 发行与审计入口可重复性 | batch-11 api.md 的 Python 旧网络路径、export.md 的客户端服务端扩展污染/库构建一致性需按当前文件复核。用本轮独立日志、配置、阶段/request 标识，失败保留白名单现场；包过滤与原生库/PCK 清单分开验。 | 无缺失 Python 入口；实际四预设 PCK/库/外置数据核验与新包运行另记 NOT_RUN，不能凭 cfg/PE/ELF 静态头宣称通过 |

### 不重复列为当前阻断

- manager 当前 `create_room():137–146` 已增加向上寻找存在的批准父目录，再安全建立 storage_root。batch-11 的“新父目录必然拒绝”静态缺口已有源码修订；较新日志也走过建房/数据屏障，但不证明所有路径负测通过。
- `match_journal` 的 card_id 负数检查已有修订，必须接着验证全链路而非再次把同一旧代码当当前缺陷。
- bytes_to_var 第二参数、Object.is_connected 同名辅助方法、scratch 类名扫描隔离及导出 scratch 过滤不按历史报告重复新增修复；实际解析/包核验尚不能省。
- dedicated 失败没有证据来自 LAN/P2P 恢复阻断；worker 共用 session.dedicated 与 authority_host_mode 不是一个概念。不得换模式或去掉进程所有权/认证校验让测试绿。

## 4. 必须保留的真人、多机、跨网与完整对局门槛

`docs/real-world-multiplayer-test-plan.md` 明确全部 NOT_RUN。本文不改它、不替任何用例填 PASS；缺环境/入口/安全夹具记 BLOCKED，预期冲突记 FAIL。所有分支保留独立 run_id、角色/PID、room/instance/mode、源码快照及工作树说明、权威日志、真人输入录屏、公开状态和受限隐私证据。

| 门槛 | 执行内容与不可替代的证据 |
|---|---|
| RW01–07：真人单机隔离/大厅 | H/G/S/X 独立真实窗与身份目录；H 正式开场→主菜单→联机；用户名/重复昵称/服务端登记、密码、按玩家条目批准数据与依赖、修订/缓存/哈希。回环不是多机 LAN。 |
| RW08–12：真实输入与隐私 | 真人选人/随机职阶隐私、顺位沿用及轮转；真实卡位选牌/取消/技能+攻击/移动/扣费/入场闭环；非当前行动者 G 亲自答复、H/S 不可代答；观战及中途加入无私有数据泄漏。自动 agent 或仅窗口出现不替代。 |
| RW13–19：断线与恢复分账 | 原进程重连、跨进程恢复、管理转让、房主 UI 与 worker 分别退出、dedicated 原局恢复及继承/过期/错认证/旧档拒绝分别验。先保存→崩溃→新实例→逐文件校验→原真人认证重连→数据屏障→同中局续行；ready/大厅恢复不等于原局恢复。LAN/P2P 未安全贯通时保留 BLOCKED。 |
| RW20–24：异常与保存 | 独立模拟/执行预算、0秒语义、后台计算响应、疑似异常文案；整个根效果及连锁回退或明确安全不可用；重开/回大厅与预算保留；成功保存后关闭、保存失败旧档不变。无安全异常/权限夹具不伪造结果。 |
| 完整终局补充门槛 | RW10 仅要求至少一整回合，不足以证明“完整对局”。另外建立独立 full-match case：真人 H/G、AI=0，从正式入口经数据/选人/开局，多回合到合法 game_over；双方已确认动作、资源/归属/顺位/待答连续对账，终局结果与权威 game_end/存档一致。再单独跑真实中局恢复后到终局。达到 round>=2 的 save/close 子类只能算中局目标，不能算终局。 |
| 真正多机 LAN | 至少两台真实设备、非回环地址、独立身份/缓存，实际端口/防火墙，权威在房主机器；网络断线/重连与数据/隐私复核。单机四窗、WSL 不补此项。 |
| 跨网 P2P/NAT | 不同真实网络/设备；邀请码/信令/ICE，直连成功与不可达、超时/掉线/重连负例；核验游戏流量不经信令转发，不可直连就明确失败，不暗加游戏中继。 |
| Windows/Linux 发行与跨系统 | 当前源码在全新空 release 导出真实四包，逐包哈希/PCK/ABI、服务端库装载、外置 data/无关 cwd、首次配置、stdin/信号/安全关服；再跨系统连真实服务端、恢复原中局并继续。旧包、静态配置、本机跨系统均不能替代目标场景。 |

证据白名单：公开/脱敏日志、清单、存档必要片段、权限与文件哈希对照。不得收集整个 user/profile、私钥、密码、票据或认证库；UI 不显示密钥/指纹。破坏性操作只作用本轮已确认 PID/原生实例，禁止按进程名全杀，保留失败目录直到复现结束。

## 5. 下一轮执行顺序（本子任务不运行）

1. 主代理核对全部并发交接与实际工作树；先处理 P0-A/B 和 P1-A/B/C，让首次已确认动作与真实失败原因可观察，不能从几千 decisions 推定推进。
2. 所有生产写入者退出后，获准才串行执行受影响 Godot 专项：审计→开局/双端推进→真实中局 save→保存 close→崩溃恢复→终局。每套独立日志，分别对账退出码、RESULT、SCRIPT ERROR、相位与实例；失败只继续不依赖其前置的项。
3. P0-C/D、P1-D/E/G 的失败与多房间隔离分支单独跑，不将安全拒绝改成成功，也不将 worker 退出解释为 saved=true。
4. 再执行正式 RW 真人计划、补完整终局用例；多机 LAN、跨网 P2P、目标发行/跨系统仍各自留门槛。静态检查或自动测试全绿只关闭内部代码项。

本次交付：仅 `scratch/net-batch-12/next-gates.md`。当前完成的是证据对账与可修复缺口归类，不是修复或联机验收通过。
