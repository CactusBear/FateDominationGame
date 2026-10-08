# 联机方案自主完成约定

## 执行边界

### 当前优先级：Windows先完成

- Windows自主执行批次deleg_ff2f5dbf已派10个独立子代理：窗口夹具、双包冻结导出、关服恢复、LAN入口、P2P入口、继承窗口、原生能力复验、交付说明、C盘清理准备、Windows验收对账。各自只写E盘batch58隔离目录，不运行Godot、不写生产。主代理串行验证，不把候选交接、测试启动或局部通过当作交付完成。
- 需决策事项先记录docs/multiplayer-open-questions.md；不依赖决策的Windows工作持续推进，不等待用户重复催动。Linux工作明确暂停。

- 用户最新决定：先完成Windows，Linux暂缓。停止新增Linux构建、性能定位及验收，不回退已有跨平台实现，不删除Linux已有证据与产物。
- 当前交付范围：修复Windows回滚窗口和同步素材窗口的接入前置，完成真实输入及原生画面复核；从最新生产源码导出Windows客户端、服务端；验证正式安全console wrapper、依赖、默认配置启动、联机及保存恢复/关服；交付Windows测试包和多机测试说明。
- Linux默认预算与后续实包验收明确延期，不作为Windows交付阻断。共享代码仍保留跨平台能力，但本轮不以Linux工作分散Windows收尾。

### 第51批自主收尾调度

- 用户再次要求按完整方案自主推进，尽可能使用10个独立子代理；阶段结果不作为结束条件，需决策事项只记待确认清单。
- deleg_7ac2d2f7 已派10项独立工作：batch48/50统一整合、四包发行脚本、验收条件对账、C盘安全清理准备、CLI共享stdout、恢复继承窗口专项、串行回归runner、审计锁内维护重入、真人多机说明、Linux启动预算与网关恢复保活。
- 子代理只读生产，不运行Godot、不清理文件；输出统一位于项目外E盘 test/agent-work/batch51 各自目录。主代理唯一负责生产合入、真实引擎串行验收与清理。
- batch48录制保活及batch50恢复尾部保活仍为隔离候选。Linux SIGTERM曾在显式120/120/30秒测试预算下41项通过，但SIGINT后续恢复断连仍在定位，不能宣称默认预算或Linux全链路稳定通过。
- 当前 proc_82e783d845ba 正在验证batch50候选。保持运行源冻结；返回后核对退出码、RESULT、脚本错误和恢复分段日志，再决定候选是否准入。
- 顺序：候选安全与真实恢复验收 → 统一合入并跑受影响回归 → 真实窗口与画面检查 → 冻结最新源码导出四包并复验 → 交付包及真人多机跨网清单 → 核验迁移后清理本项目C盘旧产物。既有测试成功不替代最新包复验。
- 已取消的信令重启无损重注册、密码增强不重新加入任务。真人跨网环境不可由本机模拟证明，交付时明确待验范围。

- 用户授权自主推进整个既定联机方案，不以阶段性修复、局部测试通过或审计完成作为交付终点。
- 尽可能维持最多 10 个有独立任务的子代理；当前批次 deleg_bac55657 已派出 10 个。子代理只读生产仓库，在各自隔离目录交付补丁和测试；主代理负责核对、冲突整合和生产修改。
- 修改前提供逐文件中文说明；所有 Godot 验收由主代理串行执行。静态检查、尝试计数、子代理自报均不能替代真实运行证据。
- 每批完成后对照剩余验收条件继续执行，不等待用户再次发送“继续”。异步代理工具要求的回合交接不表示任务完成，结果回传后继续实施。
- 需要用户决策的事项记录到 docs/multiplayer-open-questions.md，标明事实、选项、影响和被跳过范围；不在普通阶段汇报中追问。用户后续要求集中确认时统一提出。
- 不提交、不推送、不重置用户改动，不读取或输出凭证，不结束用户自己的 Godot 实例。

## 完成条件

1. 修复并验证当前恢复断线、原真人恢复屏障、身份票据持久化与恢复原子性。
2. 对照既定计划补齐 LAN/P2P 权威恢复入口、安全关服、缓存与数据授权、请求回执、身份继承等剩余代码任务。
3. 完成专项回归，并核对退出码、RESULT、脚本错误；测试失败不得因后续级联断言掩盖首个失败。
4. 完成涉及 UI 与规则行为的非 headless 实际运行及原生画面检查。
5. 构建并验证 Windows/Linux 原生扩展及导出包，确认包内依赖与过滤、真实启动及相应功能测试。
6. 交付导出包和明确的真人、多机、跨网测试清单；不得将无法在本机证明的 NAT、公网与真人体验标为已验收。

## 当前证据限制

- 保存专项曾通过中局、保存回执、日志哈希和种子检查，但继承的崩溃恢复阶段失败并超时，不能标记整套通过。
- 恢复客户端 accepted revision 仅证明客户端本地记录，不等于服务端 ACK 已接纳。
- 无凭据反例旧断言受 PID 退出后改为 -1 影响，不能单凭该断言判定权限绕过。
- 恢复断线根因仍待关联实例日志与真实复现；上轮所有成员必须在线的补丁需复核离线观战者边界。

## 隔离补丁整合队列

- 第 14 批产物位于 Hermes scratch/net-batch-14；尚未整体合并，静态 PASS 不算运行通过。
- 第 15 批 deleg_bd1a83dc：10 个子代理继续完善恢复屏障、原子恢复、Windows 缓存替换、Linux 实际构建、LAN/P2P 恢复 IPC、安全关服测试、票据持久化、请求重试、blob 授权和恢复测试。
- 已落地 match_journal.gd 浮点身份安全整数边界；新增 tests/match_journal_identity_regression_test.gd/.tscn。真实 Godot 测试先得到 46 checks、4 条预期失败，再应用生产修复后得到 46 checks、failures=[]、exit 0。覆盖正负 int64 落盘、审计链、续写、旧修订拒绝、各自独立的无穷/NaN/小数/越界反例。所有测试数据写 E:/Projects/Godot/FateDomination/test/audit-identity。
- 未采纳恢复屏障候选的“跳过缺失成员/观战身份”行为：可能遗漏必需座位；也不得无条件拒绝显式全 AI 存档，交代理依据存档原始座位声明修订。
- 未将 ENet 回调重入静态风险称为本次断线已证实根因；需实际回归和实例关联日志验证。

## 第 15 批回传后的执行记录

- 已合入候选 blob 下载授权：主机仅分发当前批准清单的哈希，provider 向主机上传仍可进行。新专项 net_blob_authorization_test 真实 ENet 红绿验证：旧生产代码 54 checks / 8 failures；修复后 54 checks / failures=[] / exit 0。测试临时数据显式写 E 盘。旧大厅测试同步改为未批准下载拒绝，net_lobby_test 32 checks / failures=[] / exit 0。
- 未将第 15 批 request-receipts 补丁直接合并：_attach() 中新引入 message 变量不在作用域，gdparse 语法通过不足以证明原生编译成功，已交后续代理修正。
- Linux 新库由子代理构建成功，但主代理尚未验证加载、替换正式库或导出包；不得标记 Linux 发行通过。
- 第 16 批 deleg_a06962cb 已派出 10 个隔离实现任务：原生原子文件替换、LAN/P2P 身份握手、主管身份 IPC、关服句柄监督、延迟断线清理、排队 blob 授权复核、恢复 loader 严格校验、已采用数据快照、发行准入、P2P 邀请超时。

## 第 16 批回传后的执行记录

- 已合入 gateway 延迟断线清理：路由通知前复核身份，重复通知合并。gateway_deferred_test 实跑 16 checks / 0 failures，清除夹具闭包循环后无退出资源错误。此为调度单元测试，不代表真实恢复断线根因已证实或修复。
- 第 16 批 blob-revocation 候选只有队列版本字段，缺发送检查；未直接采用。主代理补完整发送时授权并用真实 ENet 消息监听验证：旧代码 13 checks / 2 failures，修复后 13 checks / failures=[]；原 net_blob_authorization_test 再跑 54 checks / failures=[]。同哈希仍在批准清单时跨版本继续，已撤销哈希与掉线请求者停止发送。
- 第 16 批 P2P 超时补丁可能无条件关闭已连接 peer，暂不合入，要求补连接成功行为反例。
- 第 17 批 deleg_63819ba3 正在隔离整合五条存在跨文件冲突的主链：恢复、原生原子替换调用、LAN/P2P身份与主管IPC、关服、P2P超时。避免重复派人编辑同域；回传后统一合并和真实运行。

## 第 17 批回传后的执行记录

- P2P 邀请超时、连接成功记录退役、按邀请隔离错误、共享候选校验已合入；真实 Godot 行为测试 p2p_invite_timeout_test 55 checks / failures=[]，传输为测试替身。net_p2p_invite_test 真实 WebRTC 手动邀请码专项 13 checks / failures=[]。
- 原生 AtomicFileReplace 与 scripts/io 接线已合入，cache 修复、主管配置/心跳、recovery.json 均使用完整校验后的原生替换。原库先备份至 E:/Projects/Godot/FateDomination/test/native-library-backup；6 份关键原生源码与候选逐字节相同。双平台库已安装。Windows Godot native_atomic_integration_test 47 checks / failures=[]，覆盖锁冲突保留目标与 pin 缓存修复；Linux Godot 尚未运行，不宣称双平台验收完成。
- net_p2p_signal_client_test 首个 worker host 入口失败，后续夹具访问 nil.has_peer 并超时 exit124；不算通过，不以手动邀请码通过替代自动信令验收。
- 第 18 批 deleg_2f6750ed 四个隔离任务只处理最终集成冲突和信令真实worker夹具：恢复补丁适配最新原生发布；LAN身份在恢复补丁之后接线；关闭监督保持原生发布；信令测试首失败短路及入口契约。当前生产已写入的原子替换、blob与P2P代码不得被旧候选整文件覆盖。

## 第 18 批回传后的执行记录

- 已合入 shutdown-final：manager 原生监督、关闭请求回执与句柄双确认、释放后的历史回执绑定；真实 net_server_shutdown_failure_test 162 checks / failures=[] / exit0。测试子进程改为正常场景入口，避免 --script 的 Autoload 编译故障；看门狗改用单调时间，避免 fixed-fps 模拟计时过早清理。
- 已合入 recovery-final 的生产变更与 GDScript/场景测试；未安装两个 Python 跑批工具。真实 recovery_seat_bindings 27/0、recovery_barrier_session 13/0、resume_failure_atomic 56/0、recovery_json_loader 301/0；后者测试目录改为用户指定 E 盘。夹具 seed() 更名 seed_session() 避免内置函数冲突。
- Godot 大数浮点字面量在该运行中把 9007199254740991.0 读成相邻值，审计/恢复校验边界统一改 float(9007199254740991)，真实 loader301与journal46再次通过。
- net_server_recovery_midmatch 最初失败由日志证实为恢复人数 float 未归一化，现复用 Room.decode_json_settings；再次运行通过新实例/ready/config/旧实例拒绝，但仍内部房间断线，33 checks 有失败，exit1，清理确认所有权释放，不再300秒空等。整套恢复仍未通过。
- 第 19 批 deleg_b6cd325f：恢复断线精确源码链、LAN与已落关服补丁接线、无敏感载荷的实例关联诊断、关服失败监督生命周期。回传后继续，不将前述专项通过视为整案完成。

## 第 19 批回传后的执行记录

- 已装入环境变量 FD_RECOVERY_DIAGNOSTICS=1 控制的脱敏网络诊断和 recovery_diagnostics_test；未开启时不输出记录。临时阶段埋点位于 worker copy/replay 边界，定位后需清理或明确保留开关。
- 真实诊断主日志 E:/Projects/Godot/FateDomination/test/recovery-diagnostic-main/run.log，首次错误为恢复后内部 ENet disconnect。worker 在两peer连接后停止poll，网关仍持续轮询。
- 后续阶段运行超时110秒，不算验收通过；对应server_match/2920646/worker日志记录copy_begin7427ms、replay_begin13098ms、replay_return26392ms true。复制阶段没有网络维护，恢复本体同步耗时亦需贯穿保活；不能再把静态回调重入当作已证实唯一根因。仅按该次测试目录检查残留worker，未发现仍运行匹配进程。
- 第 20 批 deleg_2e2f93bb：副本分块复制保活、MatchReplay校验/另存维护、LAN补丁精确适配当前诊断。禁止扩大连接超时掩盖停顿。batch19 close-lifecycle候选尚未合入并待实际运行。

## 第 20 批回传后的执行记录

- 已合入worker64KiB复制/哈希保活、路径tree维护参数，以及Replay/Journal分块读/哈希/另存维护和重入保护。match_replay_maintenance真实39 checks / failures=[]，修复测试owner遮蔽Node属性及空前序哈希update引擎错误后重跑无该错误。
- 真实midmatch恢复外部命令120/180秒早于套件自身180秒恢复预算加启动耗时，曾超时；随后280秒上限运行正常返回exit1。33checks失败仅为恢复镜像不相等和相应中局短路，不再报告连接断开。最新server_match/3074805/workers/8630ab331d3eb9b8656bef350e1bacf3：磁盘phase=playing，两成员connected=true，data_revision=2。不能将磁盘playing等同于完整恢复通过。
- 第21批deleg_67201eec：恢复比较精确差异、LAN待合补丁适配确认、复制真实Node场景测试。尚未放宽恢复比较，尚未完成LAN认证/恢复或导出包。

## 第 21 批回传后的执行记录

- 已新增失败视图取证到E盘：真实midmatch运行exit1，33checks；E:/Projects/Godot/FateDomination/test/recovery-comparison-227912575/client-0.json、client-1.json保存expected/actual过滤视图，不保存会话凭据。程序逐字段差异94/97项，已看到会话NetIds及本地资产根目录变化；不得直接删除比较字段。deleg_45f11a70正在实现显式ID双射/内容哈希校验比较器及反例。
- 已合入batch21 lan-ready-current身份挑战、主管/worker桥及序号账本，保留手选存档恢复阻断。Node场景化后lan_integrated_ipc真实17checks/0失败/exit0。chain测试首次房主入房失败，随后测试Manager缺valid_instance_id及缺成员引发级联，未通过；deleg_6c420b3b负责首次失败定位与真正ENet/原生句柄入房专项。生产链路不能标已完成。
- batch21 copy-test子代理越过禁止运行Godot边界报告41checks通过，主代理尚未独立复验，不将其计入主代理验收结果。

## 第 22 批恢复比较验收

- 已合入显式字段路径的NetIds双射/资产内容哈希比较器，不删字段、不重排数组；两客户端共用映射，玩家身份仍逐值比较，崩溃前冻结真实文件哈希。测试转换为Node场景，临时文件使用E盘，大数边界使用float(9007199254740991)。
- 主代理真实运行recovery_equivalence：35checks、0失败、exit0，覆盖规则数值、缺字段、数组顺序、跨客户端引用错配、非双射及资产字节变化。
- 主代理真实net_server_recovery_midmatch：38checks、failures=[]、exit0；两名真人恢复同一中局后继续提交新规则操作至终局，决策计数96/109，客户端无错误，进程所有权释放通过。退出仍有26 ObjectDB实例与6资源残留错误，功能断言通过不等于无泄漏验收。
- LAN真实入房修复deleg_6c420b3b仍待回传；手选存档恢复、关服生命周期补丁及发行包仍未完成，不把本次中局恢复通过视为整案结束。

## 第 22 批 LAN 与关服验收

- 已合入JSON PID字段级绑定比较，覆盖观察快照、序号和账本重开，真实lan_json_binding22/0、lan_integrated_chain43/0。LAN live夹具修正数据声明模式、启动前数据根读取及误用4KiB管理序号读取器读取53KiB恢复文件。
- 主代理真实lan_live_join16checks/failures=[]/exit0：生产ENet、RSA、原生进程句柄、私有身份IPC、房主/客机入房和磁盘身份绑定、关闭回执+退出+release全部通过。退出27 ObjectDB/11资源残留仍未解决。
- 已合入batch19 close-lifecycle四文件补丁及测试，主代理真实144checks/failures=[]/exit0。覆盖拒绝后释放监督与重试、超时保留原请求、UNKNOWN恢复、晚到回执、单房间关闭、旧实例退出不冒充新实例关闭、LAN/P2P关闭发布失败。未用该通过替代系统信号窗口验收。
- deleg_31e4370e三个隔离任务：LAN/P2P本机手选存档恢复正式入口、退出引用清理、Windows/Linux发行准入；主代理已告知restore代理关服接口最新变更。仍待真人/多机/跨网与最终导出，不宣称整案完成。

## 第 23 批回传后的实施与验收

- 已合入路由闭包释放修复：仅对撤销/失败的内部link断开捕获route的信号，房主断线改命名方法。真实WeakRef7/0、LAN live16/0、dedicated中局恢复38/0，均exit0，后两套本轮不再输出ObjectDB/资源残留。未据此推断其他测试无泄漏。
- 已合入package-gate最小补丁：LAN/P2P与服务端统一在UI创建/加入前初始化身份，四导出预设排除编译中间产物。正式窗口及新导出尚未验收，旧包不准交付。
- 已合入lan-restore正式本机批准archive_id、可信身份/座位授权、隔离复制、独立worker恢复IPC与元数据保存。合入后真实LAN入房16/0、exit0、无资源残留；此结果只证明基础接线未回退，不代表手选重放已通过。
- deleg_a9eec1ca：真实LAN手选恢复GDScript/ENet/规则测试，显式跨新房间座位选择UI，系统信号窗口验收入口修补。拒绝用Node JS投影测试替代真实规则重放。

## 第 24 批回传后的实施与验收

- 真实LAN手选恢复测试已落并运行：首轮stale_revision来自发送ACK后未等待权威最新快照，夹具补等待data_ready，不放宽revision验证。另一次入房提前失败尚未定位，补脱敏诊断后复跑。最终70checks/failures=[]/exit0，无退出资源错误，覆盖原局录制→新大厅显式映射→实际IPC恢复→缺ACK阻断→双端等价→继续至终局→新档新增日志→原档不变。
- 已落逐座选择UI与tscn复用身份候选面板；修正候选中的房主认证判据为本机桥confirmed，不用客机专属identity_authenticated。窗口交互尚待Godot验收。
- 已落signals-ready测试修补，真实Windows窗口验收在建房阶段失败，未发送验收信号。root=E:/Projects/Godot/FateDomination/test/signal-match-windows-1791407937835293200，无rooms产物，服务日志仅READY。随后主代理经自有控制台probe发送CtrlBreak，查询确认本轮32048/13528进程均不存在，但无保存关服日志，不能计系统信号验收成功。
- deleg_8e1b4dce：外部CLI建房差异定位、真实恢复座位UI专项、四导出执行准备。主代理已告知signal-create上述进程已退出及证据缺口。

## 第 25 批回传后的实施与验收

- 已修外部信号夹具路径序列化为as_posix，保留严格路径检查；服务端建房失败只在管理员本机打印manager.error。真实重跑已能建房，第二客机清单仍未到，双方error为空。root=E:/Projects/Godot/FateDomination/test/signal-match-windows-1791408387524157800；本轮自有launcher29908/server33228/worker30328保留，未强杀；deleg_ec7f06bd正在精确定位。
- restore_seat_ui真实窗口49checks/18UI/5window通过。首次原生读图发现wrap_controls导致窗口长到2180px，关闭共享身份面板自动包裹后复跑仍49/0，原生查看E:/Projects/Godot/FateDomination/test/restore-ui-window-9479/screenshots/04-complete-selection.png确认680x480正常布局、文本和按钮可见。测试走控件信号，未宣称物理鼠标和端到端UI恢复已验。
- 四候选包已由Windows编辑器从冻结副本导出：E:/Projects/Godot/FateDomination/test/export-1791408687465711000/release。windows/client外部data205文件哈希集合通过，PCK条目校验及排除项通过；校验器按源码目录寻找原生DLL导致BLOCK，实际DLL由导出器放包根。其余三包外部data尚未净化，全部运行验收尚未做。deleg_5c4ccb1b核对真实PCK descriptor路径并修校验器，禁止盲猜basename放行。

## 第 26 批外部服务批准路径

- 已证实第二客机不是入房失败：两成员已登记，外部服务显式数据政策保持候选revision0；测试却在批准前等清单。基类改等第二成员view，再调用_after_room_joined；signals子类复用公开catalog/prepare/commit，保留随机模拟关闭及静态预检，不绕过批准。
- 真实重跑6checks失败于预检缓存复读，报告批准文件复读校验失败；没有进入信号发送。root=E:/Projects/Godot/FateDomination/test/signal-match-windows-1791409072080168100，测试自有launcher27912/server27160保留，未强杀。
- deleg_c745a7f4核对validation-cache失败及参数化安全临时目录，禁止放宽祖先链接检查；本机user目录联接是怀疑点而非已证实根因。发行校验deleg_5c4ccb1b尚待回传。

## 候选包初次运行

- 按实际PCK descriptor和Godot导出映射的校验器逐包复验；仅删除另外三包各134个外置data的.import侧车，四包均PACKAGE_STATIC_PASS_RUNTIME_PENDING，报告在net-batch-26/export-native-mapping/main-平台-角色.json。
- Linux server首启实际生成配置并exit0；Linux client --headless --quit-after 5实际exit0。未据此宣称Linux完整联机运行通过。
- Windows server虽打印配置生成，bash退出127；Windows client用Python subprocess再次实际启动，返回3221226356原生异常，仅输出Godot banner。四包禁止按静态通过交付，deleg_2f7b3bd0定位Windows发行崩溃，未动生产或用户进程。validation-cache任务仍待回传。

## 第 27 批预检修复验证

- 已合validation-cache五文件：服务端预检显式使用已校验房间preflight目录，保留默认user目录与所有祖先链接检查，复读错误附固定cache.error。真实外部窗口链确认目录、隔离加载/静态预检、显式批准、两端同步、真实中局和窗口渲染均通过。
- 本次root=E:/Projects/Godot/FateDomination/test/signal-match-windows-1791409694334257800，24checks唯一失败是保存式信号关闭未确认。server pid23412日志出现SERVER_SYSTEM_STOP_REQUEST 2，无STOP_COMPLETE/FAILED。不能据此认定安全关服成功，已将证据交给正在定位Windows原生退出异常的deleg_2f7b3bd0；尚未确认同源。
- 当前候选发行冻结副本早于本轮生产预检修复，修完Windows运行故障后必须重新导出，不能把旧包当最新交付。

## 第 28 批原生隔离

- 主代理实际创建并导出空场景四组release包，各运行两次，证据E:/Projects/Godot/FateDomination/test/release-isolation-28/results.json。无扩展、仅WebRTC均exit0；仅signals、signals+WebRTC均3221226356。无缺库/脚本错误，故障定位到当前signals DLL加载/类登记/退出释放路径，而非开场内容；尚未定位三个原生类中哪一处或构建ABI。
- 生产库未替换。deleg_8e0e284a并行：完整可追溯重建及三个注册变体，只编译不Godot；信号runner先收集真实engine/worker句柄退出事实再断言日志，独立记录launcher，不强杀。

## 第 28 批重建运行结论

- 主代理运行重建full/signals/processowner/atomic四组各两次，全部exit0；真实冻结client独立副本仅替换full库也exit0。证据release-isolation-28/rebuilt-results.json。不能据此指定旧构建哪项ABI有错，但旧二进制与完整可追溯重建结果明确不同。
- 旧生产DLL占用拒绝覆盖，未结束用户进程。新库以libfate_server_signals.windows.template_release.x86_64.dll新增，SHA256=61c49a2dc8e79f9acace840658c6b4367f8f7b2ca5a2a3d7438ac5a01c91921f；descriptor指向新路径，SConstruct Windows输出加入target。旧库保留及备份，不再是新启动的选用库。
- native_atomic_integration原生替换/缓存/配置前39checks通过，但旧恢复夹具首次写入失败后JSON nil，整套失败；deleg_39b58895负责测试契约修补与console lifetime取证。
- runner取证补丁已合。最新signal-match-windows-1791411384856575100：真实engine33804和worker33460退出码均0，但无保存式关闭日志；launcher21348退出3221225786。与heap崩溃不同，怀疑wrapper先退控制台寿命问题，尚未验证修复。不能用exit0放行关服。

## 第 29 批验证

- keeper仅在独立候选运行，未合入生产runner；真实root=signal-match-windows-1791412124184632600，keeper13728保留，engine15772及worker22668均exit0，仍无SYSTEM_STOP_REQUEST。该结果否定仅凭wrapper退出解释全部症状；deleg_3c29e9f5追Godot handler注册时序，禁止异步handler中日志/文件接口。
- 已合native_atomic_integration恢复声明夹具和首次失败短路，JSON往返比较显式编码归一化。主代理新库真实51checks/failures=[]/exit0，无脚本错误；不放宽生产恢复加载器。
- 新库发行空场景和实际client副本已通过，但完整新发行包仍待重导及目标运行；系统信号保存关闭未通过，不能交付为完成。

## 第 30 批信号根因收敛

- 主代理新增FATE_SIGNAL_TRACE主线程落盘取证，真实keeper场景仅ready，无request/exit_tree；空服务同样失败，首帧重新enable实验也失败，已立即撤销重注册实验，未改默认注册逻辑。
- 主代理直接核对Godot4.7.2 platform/windows/console_wrapper_windows.cpp：103–155创建Job并启用JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE，将engine纳入；wrapper无CtrlBreak handler。wrapper默认退出关闭job句柄会强杀其engine/worker，这与外部keeper仍活却engine无正常退出阶段一致。旧“只需keeper保控制台”方案不成立。
- deleg_990a6881隔离编译服务专用console wrapper：消费CtrlC/Break，保留等待engine和参数行为，禁止修改官方Godot安装；主代理回传后实际窗口信号验证。临时_signal_trace开关仍在生产待定位结束后清理。

## 第 31 批真实信号验收

- 安全wrapper在E:/Projects/Godot/FateDomination/test/safe-console-31中配独立Godot副本，不改官方安装。真实Windows窗口CtrlBreak正例29checks/failures=[]/exit0，root=signal-match-windows-1791413322145411000；服务31320/worker5872均真实句柄exit0，存档完整且重放到同一中局，wrapper退出0。
- 未录制拒绝分支真实24checks/failures=[]/exit0，root=signal-match-windows-1791413433796573500；服务404/worker28244保持running且能继续规则操作，自有wrapper11996按设计保留，不强杀。这不是资源清理完成记录。
- 已清除临时_signal_trace及首帧重注册实验；正式SERVER_SYSTEM_STOP_REQUEST/STOP_COMPLETE日志保留。safe-wrapper尚待正式导出自动接线。
- deleg_0e0b6cf0：正式wrapper可复现导出、Linux真实退出证据runner、原计划最多三项剩余阻断核对。候选包仍需从最新代码重导并逐平台运行。

## 第 32 批收束执行

- 已将安全wrapper源码/MIT头、已验证EXE、构建与安装说明落入tools/windows_server_console，安装工具落tools/replace_windows_server_console_wrapper.py；在旧候选Windows服务包实测安装并回读SHA通过，旧包仍不可当最新发布。
- 复核纠正交接断言：预设此前并未排除旧.windows.x86_64.dll，现四预设明确排除该未使用旧库和wrapper工具目录。新.template_release库保留。
- Linux交接runner发现Windows直接Path读取/mnt路径、向child发信号却等wrapper标志、未接完整对局等缺陷，未采用；deleg_d37717a7改为现有完整验收链+WSL父进程pidfd实际持有与退出回执，先跑非Godot真进程验证。
- deleg_c57ca212三个隔离实现：LAN/P2P已有档崩溃恢复守卫背后的正式接线、P2P现有身份门真实入口测试而非重复新模型、事务审计写失败权威提交闸。不得以已有专项通过数当整案完成。

## Linux pidfd 验收接线

- 已合batch33 integration.patch至现有信号验收runner及linux_owner_bridge/linux_pidfd_parent，保留完整窗口中局和保存断言。主代理三个Python脚本编译通过，并复跑交接的真实WSL非Godot dummy四例，exit0；证据E:/scratch/net-batch-33/linux-runner-fixed/1791414359136386100。该dummy使用交接候选模块，不能代替生产整合后的Linux游戏运行。
- Linux实际发行完整对局/信号仍待最新代码冻结导出后执行；deleg_c57ca212兄弟任务仍在运行，不将本次基础进程测试当作整案完成。

## 第 33 批合入与真实验收

- 审计提交闸四生产文件及故障测试已合；修正BaseEffect测试构造参数后，主代理audit_commit实际239checks/failures=[]/exit0。覆盖append/flush故障锁存、禁止恢复洗故障、动作/AI/保存/关闭成功回执阻断，不改审计格式。
- host-crash三个生产文件及LAN/WebRTC场景已合：原生旧实例退出后房主票据+密钥校验、新实例挑战和原成员重连、全原真人活认证后恢复。LAN真实46checks失败2；WebRTC P2P真实58checks失败2，均完成中局录制、新实例、缺员屏障、盗票拒绝、原客机重连及重放，随后同样在安装恢复数据失败，并影响关闭清理。完整崩溃恢复未通过。
- P2P-auth交接的23项是JS源码投影，不列Godot验收；本轮主代理真实WebRTC场景才证明入房/握手/身份/录制路径，公网NAT仍未测。
- deleg_6160690c定位两模式共用恢复同步失败与现有UI重连接入，不放宽认证/数据ACK。主体计划仍未完成，发行包须后续重导。

## 第 34 批真实首失败

- 已合install_data分阶段诊断并补恢复等待失败脱敏状态。最终真实LAN复现：同步仅poll1/completed_files1，未超时，房主仍连接且无error，客机error=房间连接已断开，身份快照pending。原“资产安装失败”是组合断言误导，实际尚未调用安装，文件哈希一致不构成修复。
- 期间另一次原局房主初始入房失败，未确认为同源；不按偶尔通过掩盖。最新完整失败46checks/2失败，所有权最终回收，正常关闭未确认。
- batch34 UI候选未合，需先核对recover_worker成功后不得再走普通session.reconnect破坏本机authority_host。deleg_370ec139分别处理客机断连精确分支和UI单一最终补丁，禁止继续盲调资产或网络超时。

## 第 35 批证据与修复

- 子代理未读取本轮日志，其deadline解释仅源码假设。主代理新增临时分支日志实际复现：lan-crash-21206 worker明确IDENTITY_DEADLINE_REJECT，member_mapped=true、pending_count=1、restoring=false。并非“尚未映射且恢复中”。
- 主代理改身份桥poll先核验当前消息认证，再对仍未认证的队列执行原deadline，不延长预算；已认证消息恢复期间不pop。临时deadline日志已撤掉。重跑转为双方revision2但guest报恢复凭据与当前认证密钥不匹配；完整恢复仍未通过。deleg_d5bbd3ff追排队旧join/连接与member映射。
- 已合重连UI单一替代：崩溃分支recover_worker成功直接等待loopback，不重复普通reconnect。主代理真实Godot Button测试7/0/exit0。子代理曾违反只读/禁Godot约束临时改生产，未采用其自报作为主代理验收。

## 第 36 批真实根因与恢复通过

- 未采用queued-identity世代补丁草稿，因为未证明旧join污染。主代理实测lan-crash-1563日志明确失败请求kind=data_ack/member_bound=true，旧revision被拒却复用盗票请求留下的room.error。非当前guest密钥错误。
- 已修每请求临时room.error隔离；旧非负ACK不确认新revision也不报错，未来/非法仍拒绝。移除临时ROOM_REQUEST_REJECT日志。真实LAN崩溃恢复70checks/0失败、WebRTC崩溃恢复82checks/0失败，均exit0且无脚本/退出资源错误，含原真人身份、缺ACK、同局等价、继续至终局、原档不变和安全关闭。
- deleg_37fa7b21补ACK/身份队列精准反例及最后受影响回归清单。发行仍需最新源码重导，Linux实际完整验收与真人多机跨网尚未完成。

## 第 37 批专项与 Linux 实包

### 用户新增收尾要求

### 第41批实际合入与验收

### 第44批Windows同包恢复实际通过

### 第46批公共视图与CLI共享摘要

- 已合view_builder未知属性/类别/phase/place不回退内部字符串，server_console显式--shared-log及固定类型摘要组件。默认私有管理员输出保持不变，不能分享默认完整stdout，也不宣称全系统日志均已脱敏。
- 真实match_view_privacy_test退出0，137checks/0失败，无脚本错误。首轮夹具误以为受控条目保留独立玩家行而索引空字典，按现有get_player_order_ids排除契约修正；不将该条当控制者可见性证明。覆盖隐藏卡背、未解放技能/BUFF跨区、own正例、说明及公共日志合成标记、CLI摘要与私有管理响应不变。补丁前红测、CLI整进程stdout及窗口/网络全链路仍需单列，不以组件测试外推。

- proc_c62b6252511f退出0，RESULT checks=41 failures=[]。保存前实际中局和双端资产证据、CtrlBreak保存式关闭、原engine/worker句柄exit0、同包重启与原密钥重连、缺第二端ACK屏障、中局等价、恢复后双方新操作与日志增长、原档SHA不变均通过。证据：E:/Projects/Godot/FateDomination/test/signal-match-windows-1791429290398513900/summary.json。
- recovery_service_preserved=true，恢复实例仍保留；不能以空本地gateway清理断言认作外部服务已退出。清理前须正常保存关闭并确认真实所有权。
- 第45批路径checked候选尚未合入，proc_9994b68a6030运行Linux真实安全/性能对照。默认30秒Linux启动、35秒预检及Linux完整信号仍未通过。

- 最新Windows发行拒绝关服分支：proc_177ef66dafe3退出0，RESULT checks=25 failures=[]；真实窗口中局发送CtrlBreak后服务及worker句柄均确认存活，原局继续提交操作。证据目录E:/Projects/Godot/FateDomination/test/signal-match-windows-1791427320837655100。service_preserved=true是反例预期，不得把测试cleanup断言当真实所有子进程已退出；运行目录暂不清理。
- Windows发行保存关服分支已实际保存并正常退出，但源码夹具重放编译包档被指纹拒绝，整套仍未通过；deleg_a097ae90修同包恢复验收。Linux隔离阶段日志catalog_begin8655ms/cache_begin12402ms，index0至196跨17558ms，末次29960ms仍在写缓存，未进入assemble；deleg_0d08d02a处理启动IO，不扩超时。

- ready-tests候选已局部合入9份测试，未覆盖生产认证。实际Godot发现辅助函数缺返回值，补失败返回；rooms退出等待改为主管登记pid=-1后才恢复。真实网关13/0、rooms25/0，退出码均0，末轮无脚本错误。
- 发行规则指纹修复先在E盘隔离工程运行：真实begin/restore反例25/0；Windows release探针392/0，381份编译脚本真实可读并被指纹覆盖。修复缺remap.path时ConfigFile日志错误后才合入生产match_replay。空清单、读取失败和版本不一致仍拒绝；新算法不自动迁移旧档，source与compiled载荷不豁免。
- 官方release模板禁止--scene覆盖，发行探针改为隔离project.godot主场景；生产主场景未修改。正式新包另从生产冻结至E:/Projects/Godot/FateDomination/test/release-41/project，不带探针。Windows服务端导出0，wrapper SHA校验通过；proc_f88b2f9a3936正在跑最新发行真实Windows信号完整验收，尚无最终结论。

- 最新范围：用户已取消房主信令重注册，batch39候选不合入。自动信令完整恢复运行已结束，退出码0，最终RESULT checks=383 failures=[]，包括信令停止后真实续局至终局；计数含重复屏障采样，不是383个独立功能。
- batch40已实际合入manager与lobby_session两处生产修复，启动时限专项15/0；其余测试候选未合入，不能声称旧rooms/gateway失败确定由夹具导致。batch41分别处理发行脚本指纹与测试契约，禁止用跳过校验或放宽规则换取通过。
- C盘空间不足处理：本轮package-gate已复制到E:/Projects/Godot/FateDomination/test/package-gate-41，4692文件逐一SHA256一致，证明保存在migration-proof.json。仅删除C盘不在运行的frozen-project副本；可能被占用的release-new及signal-dist暂保留，未终止任何服务。后续构建使用E盘。

- 测试结束后清理本项目放在 C 盘的旧文件。先盘点并区分运行占用、原生构建依赖、唯一候选补丁及可再生测试输出；有效补丁、验收证据和最终发行包先移至 E 盘并核验，再删除 C 盘冗余副本。不删除 Hermes 本体、技能、凭据或其他项目，不强杀用户进程；仍占用的目录保留并列出。后续本项目测试及发行产物统一放 E 盘，不再往 C 盘堆积。
- 当前 Windows 最新发行包已完成入房、批准与数据 ACK，但录制开局报“无法校验存档文件: res://scripts/main_menu/game_start.gd”；尚未走到信号发送与安全关服，不算发行验收通过。此阻断修复并完成测试后执行上述清理。

- ACK/队列Node专项已落；修正未认证夹具仍返回context及RoomState缺selection_mode的问题，输出E盘，主代理真实22checks PASS/exit0。
- 当前源码冻结于E:/Projects/Godot/FateDomination/test/export-current-38/project，Linux服务端导出exit0，外部data侧车清理。真实Windows窗口客户端→WSL Linux发行服务：gateway ready但worker仅banner无ready，3checks在入房失败，尚未发送SIGTERM。
- Linux现场root=signal-match-linux-1791418281788714000，engine411经pidfd观测仍alive，worker目录7b7499153c4dfd185663e6db6c8f9954；未强杀。deleg_e580a3cf定位导出版worker初始化；deleg_627031ff补自动信令真实入口场景。静态/dummy测试不冒充Linux实包通过。
