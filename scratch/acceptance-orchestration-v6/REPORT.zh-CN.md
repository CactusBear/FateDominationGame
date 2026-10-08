# 联机验收编排审计 v6

## 结论与边界

旧跑批器不能作联机发布通过门禁：六个合成反例均被旧判定接纳，其中包含明确失败、未知结果及未执行窗口段。本轮只读生产仓库和技能脚本；新增内容全部位于 `scratch/acceptance-orchestration-v6`，未运行 Godot、未访问凭证、未执行 commit、未改旧跑批器。自测日志是合成输入，不是游戏结果。

信令面：客户端 ↔ 独立信令节点（交换 offer/answer/candidate，辅助打洞）。数据面：P2P 客端 ↔ 房主端直接传输，不允许 TURN 或任何对局流量中继；LAN 为真实物理网卡上的 ENet UDP。权威面：LAN/P2P 仅房主机器规则工作进程；独立服务端为 Linux 网关路由至房间工作进程，规则仅工作进程执行。Linux 网关转发不能被表述为 P2P 直连。

静态代码只能证明实现约束，不证明真实窗口输入、物理链路、选中 ICE pair、NAT 可达或服务器保存恢复。

## 已证实问题与修复建议

### P0 误报通过

1. 技能 `scripts/run_all_tests.py:37,104–106,120–122`：失败数组正则不匹配 `failures=1 [bad]` 或 JSON 数字失败数，却默认空数组。`RESULT checks=2` 同样被认为成功；`RESULT arbitrary`、`checks=null` 等未知协议没有门禁。修复：JSON优先解析；文本明确支持数字和列表；字段缺失/错误类型/非法数值为 INCOMPLETE，不能填0。专用无 checks 结果应有逐套协议，而非全局放行。
2. `:96–97` 只取最后 RESULT，前面的失败可被后面的绿行覆盖。修复：全日志失败优先；一般套件仅允许一个最终 RESULT；多角色输出须按run/scene/role/instance显式聚合，重复或冲突不能取最后一个掩盖。
3. `:45–47,120–122` 全量固定 headless，不看 `window_only=true`、`external_pair_only=true` 或 skipped。`RESULT checks=0 failures=[] window_only=true` 被接纳。修复：按显式矩阵分别调度 headless、窗口、外部多进程/物理设备；跳过记 NOT_RUN，并保留原因；窗口参数须读取实际源码门控，有的要求 `-- window`。窗口自动输入回归与真人UI验收也是两种独立证据。
4. `:83` 顶层 glob 扫到340个场景，但漏掉两条嵌套验收入口：`tests/authority_worker_acceptance_v4/ready_contract_test.tscn`、`tests/server_signal_acceptance_v3/signal_window_test.tscn`。修复：冻结明确入口清单和完整res路径；不能仅改 rglob 然后沿用scene.name（会丢目录/发生重名）。`--only` 子串不得当精确任务选择；请求任务缺失必须报错。

### P0/P1 进程安全、退出及中断账本

5. `:40–42,80–81` 默认 `taskkill -F -IM` 杀所有同名编辑器/游戏，不区分用户或本轮。立刻仅允许 `--no-kill`；最终移除此全局清理，改为本轮持有的进程句柄与PID+creation/start time+instance+绝对project路径。核验身份不匹配则拒绝清理。不要从端口占用或进程名倒推出所有权。
6. `:49–56` timeout仅处理直接子进程，不能证明其规则孙进程被清理；KeyboardInterrupt/启动异常缺少持久结果，下一套可能受旧工作进程污染。Windows建议受控Job Object且只包含本轮子树（窗口/服务器不同生命周期显式分组）；Linux使用本轮独立进程组/cgroup并核验 `/proc` 启动身份。这是改进建议，本轮没有真实故障注入验证。先保留日志和存档，再定向收尾；成功退出路径需要强杀即FAIL。
7. `:91–117` 只登记完成行；批次中断时未跑项不存在，容易按“已记录都绿”误报全量通过。同out覆盖旧summary/log，可混合旧新结果；写summary非原子。修复：开跑前完整任务表全部NOT_RUN；启动前RUNNING；超时FAIL，runner中断后本项INCOMPLETE，后续NOT_RUN；终止后的退出观察、清理事实另记，不能用清理成功改变FAIL。每批随机run_id和新目录；临时文件+原子替换；最后要求expected集合=实际集合、无重复、全部required PASS。跨批重新跑成功保留原失败，不悄悄覆盖。
8. source revision不足以冻结当前大量忽略/未跟踪测试；`tests/`被忽略的事实已有任务包README记录。冻结应覆盖实际工作树源、测试、资源、扩展、数据、构建配置和显式套件清单的逐文件摘要；执行期间变化使该批证据失效，不能以旧git HEAD补证。单机窗口多进程需要独立副本；同一副本不得并发Godot导入。

### v5任务包已有保障与缺口

- RW01–RW24均显式NOT_RUN，LAN16项全部pending_user_test，CN12项全部pending_user_test。这些不是通过记录。现有矩阵明确排除回环/同机/静态哈希充当LAN，CN将行为与直连结果分开，这些口径保留。
- `prepare.ps1:19–31` 防写源/拒绝重用run/检查reparse/不启动Godot，合理；但没有复制前后清单冻结核验。
- `:39` 复制排除tests/docs却未排除scratch及其他回归输出；这是正式UI副本，不是可运行所有测试场景的副本。需按批准白名单复制构建必要文件，另做测试副本保留测试入口。不能直接对这五份副本运行缺失测试。
- `:41–43` 为角色生成自定义user目录，隔离合理，但默认Windows用户目录位于C盘，不满足用户游戏测试数据固定E盘的约定。正式运行前在真人批准下解析每角色实际user路径并指向独立E盘测试存储；不假设原FateDomination联接能覆盖新名字。本轮未建立联接。
- `:62–65` 全部启动后才写PID表，第二/第三窗口启动失败会留下无持久登记的前几个进程。每次启动后立即保存句柄和PID/start time/role/project/run_id/instance；失败也保留已启动清单，不全局清理。
- 启动/准备脚本不聚合CSV、LAN、CN和Linux账本，不负责签收证据；说明写得正确，但没有机器强制门禁。CSV粗粒度 prerequisite不能作可执行依赖图。负例（错密码/阻断/拒绝relay）通过不能增加直连成功次数。
- 只读 `scratch/test-harness-audit/preflight.py:11–45` 比旧跑批器安全：数字失败、所有RESULT及跳过均检查，干净日志只称LOG_CLEAN_NOT_RUNTIME_VERIFIED。但checks=0/缺checks/布尔值未严格拒绝，也没有物理设备/跨网门禁；它的0退出码不能被CI解释为真人通过。

## 冻结后分层编排

`dependencies.mmd` 给出65个节点、机器校验无环；`manifest.json`复用24个RW、16个LAN、12个CN，加冻结/静态/窗口/P2P包/Linux节点；`ledger-template.json`全部NOT_RUN。节点只表示任务，不表示实际执行。

1. FREEZE → STATIC：主代理冻结全部写入者和实际文件清单；语法、资源路径、权限/身份绑定、传输入口、数据安装屏障静态检查。失败阻断依赖，不启动Godot代替静态门禁。
2. STATIC → WINDOW → RW：独立用户/缓存、真实可见正式入口、真人鼠标键盘、H/G/S/X和权威工作进程分别记录；预览取消、实际出牌/扣费、私有待答、观战、掉线和异常逐分支签收。loopback仅此层；自动化窗口脚本不能签成人类。
3. WINDOW → LAN-01，继而按原LAN depends_on展开：LAN-01使用两台物理机器和真实网卡/IP；LAN-09/13/16需三台，LAN-15需四台。两机子集不能称完整LAN通过。回环、本机连接自身LAN IP、同宿主VM/容器均不合格。网络/防火墙变更只针对本次测试程序/IP/UDP，禁止全局关闭。
4. STATIC → P2P-BUILD；LAN-01+P2P-BUILD → CN01 → CN02–CN12：验证实际导出扩展加载，两端不同公网出口、两种模式、交换主客、规定重复次数与场景变体。独立抓包和选中candidate pair验证直连；仅STUN配置/候选列表/ICE connected都不充分。CN08在已业务就绪后只关信令，保留直连至少60秒且两端各3次合法业务操作；不等同新会话无需信令。负例拒绝通过只计behavior_result；CGNAT拓扑穿透失败不能伪造成功，须记录首个失败阶段与用户可理解超时。缺selected pair观测列INCOMPLETE，不删该条件。
5. STATIC → LINUX-PREFLIGHT；加RW10 → LINUX-MATCH：真实Linux包、so依赖、实际help、隔离存储、端口权限、Windows真人客户端到Linux权威完整局。工作进程重新就绪 → 大厅恢复 → 原局恢复是三条独立节点，ready只证就绪。RW17依赖Linux真人基线，再进入原局恢复门禁；保存→重启→重连→恢复严格串行。
6. Linux SIGINT/SIGTERM、保存失败、网关重启、负载隔离分别留证。关闭回执绑定request_id/PID/instance且本次新建，核对saved/records/state_hash、实际退出、ready清理、磁盘重放。父进程不能观察到退出码时填null，不能填0；保存完成不等于进程已退出。

## 使用交付门禁与后续接入

- `strict_gate.py` 是只读证据结构门禁参考实现，不是Godot启动器，不具备进程清理。`reconcile()`修补本次已证实RESULT误判；自动日志PASS只限AUTOMATED_LOG_ONLY，不授予LAN/CN/真人通过。
- `validate()`只接受准确任务集合、run/build绑定、断言全集为true、证据存在、依赖PASS、真人窗口标记；LAN增加设备数/物理确认/无loopback；P2P增加不同出口和直接candidate/禁止relay字段；Linux增加实际运行标记。结构字段仍可能被人工伪填，必须由reviewer看完整证据内容后签收，程序不能证明录像真实性或日志语义。
- manifest中 `all_declared_branches_observed` 等断言是聚合签收项，不是已展开的分支协议。实际开跑前将RW多分支、CN mode×方向×次数×故障变体拆成独立row，冻结扩展manifest；缺分支记录不可签聚合断言。本轮不伪造尝试记录。CN05/06/07负例行为通过不代表全拓扑直连；发布报告分别给出direct成功/失败/不可观察次数和行为通过数。
- 证据落私人目录，白名单脱敏后共享；不收集私钥、密码、原始恢复票据或整份user目录。旧日志/旧ready不可补本次证据。
- 状态为NOT_RUN/RUNNING/BLOCKED/INCOMPLETE/FAIL/PASS。BLOCKED是真实环境/入口/安全夹具缺失；缺证据是INCOMPLETE；实际行为违背预期为FAIL。SKIP规范化为NOT_RUN并保留skip_reason；不减少发布分母。报告逐层完整/子集，不用一个绿数字掩盖未测层。

## 本轮真实执行返回

- `audit_probe.py`：六个合成误判反例复现；静态扫描顶层340套及嵌套漏选2套。
- `build_plan.py`：65任务，依赖闭合、无环、全NOT_RUN。
- `test_strict_gate.py`：3组单元测试通过（日志协议、多机证据拒绝、完整未执行账本）；仅判定器自测。
- 原始模板门禁：exit=2，overall=INCOMPLETE，expected=65，NOT_RUN=65，PASS=0，符合“未执行不得通过”。
- Godot、真人、多机、跨网、Linux运行：本轮全部未执行。旧跑批器的生产修复仍待主代理授权实施和真实引擎/进程故障验收。
