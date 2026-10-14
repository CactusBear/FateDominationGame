# 重构执行记录

依据：`docs/refactoring-plan.md` v2。用户要求持续推进，不以阶段完成为整体结束；需要用户决策的问题先记录，收到指令后统一询问。

## 执行约束

- 保留当前全部未提交修改，不使用整文件 git checkout 回退。
- 同时最多 10 个子代理，每个写入文件具有唯一负责人。
- 基线采集期间禁止修改生产代码；通过阶段闸门后再推进生产迁移。
- 子代理交付须由主代理检查产物及真实运行证据，不能直接依据其总结标记完成。
- headless 与窗口验收分别记录；不可将启动成功当通过。
- 不能原生检查画面时明确保留验收缺口，不调用 vision_analyze。

## 首轮分工

|任务|负责范围|状态|
|---|---|---|
|A01|源码漂移工具与基线报告|主代理复核通过，后续迁移使用独立变更记录|
|A04/A05|跨层及私有成员依赖闸门|工具已验，迁移后逐项退休例外|
|A06|文本 golden 与 capture/compare|主代理 compare 通过|
|A07|位置规则 golden 与负向检测|主代理 compare 通过，负向证据已交付|
|A08|展示模型构建成本探针|已交付并发数据，待独占复测|
|A02|24 个 headless 基线套件|报告已核验，21绿3红，修复继续推进|
|A03|6 个窗口基线套件|子代理报告已交付，主代理画面复验待完成|
|C02|展示器私有成员只读分组|静态报告已交付|
|B24|玩家数据查询只读分类|分类缺口继续审阅|
|F10|服务端房间生命周期只读分析|报告已读，政策问题已汇总|

C02、B24、F10 提前进行分析，不代表其所属生产迁移批次完成。各子代理报告写入 `reports/refactoring/`，主代理汇总后更新方案任务状态。

## 首轮主代理复核

- 重新执行源码漂移工具：383 个生产脚本，new/gone/drift 均为空。
- 重新执行依赖闸门：PASS，129 个精确计数例外，新增与过期例外均为 0；15 项闸门测试通过。实际例外为跨层 13 次、私有访问 116 次，原计划的 6/16 不是完整访问计数，不能直接作为清零标准。
- 核验 headless JSON：24 套中 21 PASS、3 RED。红项是 net_pending 身份夹具、net_cards 生产类型错误、mana_spend 退出资源泄漏；已经分别分派追踪。
- 文本与位置 golden 产物已确认存在。主代理实际独立复跑：text checks=11、area checks=25，failures=[]，退出码均为 0，日志在 reports/refactoring/main-review/。
- 窗口首轮报告称 6 套通过；尚未由主代理复跑，因此不把子代理视觉总结视为最终画面验收。
- B24 分类尚有 303 个调用未判定，不能标记语义分类全部完成。
- tests/ 与 reports/ 受现有忽略规则影响；文件真实落盘，但普通 git status 不完整展示，不擅自改变仓库忽略政策。

## 第二轮分工

10 个代理分别负责 B01、B08、B09、B10、B11 的独立模块、B18 纯查询、B25 玩家名 golden，以及 net_cards 类型修复、net_pending 身份夹具修复、mana_spend 引用诊断。独立模块先不替换共同生产调用方；共享调用方待主代理串行接线。该轮不是 B 批整体完成。

## 后续推进

### 第二轮交付与第三轮执行

独立位置、卡面、费用、日志、选择文本模块及纯查询入口已交付。net_cards 的混合类型投影及 net_pending 的认证夹具已提交专项证据，尚需主代理最终统一复跑。玩家名旧行为 golden 已落盘；不得用重新 capture 抹掉已批准迁移造成的差异。

第三轮 10 个代理按唯一文件写入者拆分：旧 UI 兼容转发、权威端位置/文本/纯查询迁移、v2 界面迁移、driver 与 debug 魔力预检、renderer 与 view_builder 文本接线、内核显示名统一、未知席位纯度测试、mana 类型边界根因修复、独立 ContentEnvironment 模块、玩家查询分类补充。共享生产调用方不重复分配。

已发现新增玩家名 golden 测试直接访问 GameProgress 私有函数，闸门正确返回失败。显示名迁移任务负责消除该访问；不扩充生产白名单、不以反射规避检查。所有迁移落盘后主代理再退休已消失的旧例外并统一复验。

先核验 A 批与问题归因，再依赖顺序实施 B 至 G；共享生产文件的迁移由单一写入者串行处理，独立模块和测试继续并行。

## 验收风险

### 第四轮执行

已进行 A08 主代理独占复测并更新 C01；第三轮旧 UI/权威/v2 文本与位置迁移已交付，仍需整合验收。第四轮使用 10 个代理处理：B 例外退休及测试私有访问纠正、唯一窗口验收者、EffectManager 公开包装、C04–C06 座位查询、独立命令分派器、C07/C08 数据源、lobby 内容环境、worker 内容环境、自然终局红绿回归基线、G03 显式导出目标脚本。

原基线三红项的修复均已提交真实证据，最终当前合并源码复验尚未全部完成，不宣称全量已绿。D 分派器与 C 数据源仍先独立验证，不视为生产接线完成。G03 仅脚本边界任务，不代表已构建发行包。

### 第四轮复核与第五轮执行

主代理已读取并聚合 B-integrated-headless/integrated-headless.json：10 套均 PASS，对应 stdout/stderr 日志全部存在。窗口报告为 5 PASS、1 RED；战区部署/客户端快照/合法移动三个失败已交唯一窗口诊断代理冻结复现。自然终局测试的联机自动日志窗红项与 8 条效果执行错误分开处理，不以 28 条断言通过掩盖脚本错误。

C03 公开包装、C04–C06 查询、C07/C08 数据源及 D 分派器模块已交付。E 内容切换生产接线已交付，但 net_recovery_state 与 net_validation_task 出现新的夹具/运行缺口；不放宽目录安全门或身份授权以过测试。主代理现场 gate 为无新增违规、两条已退休 C03 旧许可尚待删除，整体闸门仍未绿。

第五轮仍是 10 个唯一文件写入者：C09/C10 board样板与返回接线、D01–D12权威端分派接线、D13/D14命令适配器、D20日志窗与结算按钮、终局效果错误根因、E15内容准备依赖注入、恢复/校验夹具根因、C闸门退休、唯一战区窗口诊断、F05 DummyBot公开状态API。board与场景/presenter写入边界独立；同名按钮节点由场景代理创建，board代理负责既有入口接线。

仍未完成：C11–C15统一渲染、D15–D18输入统一、D20c/d完整终局大厅链、E消息与播报、F事务状态与会话拆分、G完整发行构建。阶段成果不代表这些验收项已完成。

### 第五轮复核与第六轮执行

主代理实际复跑自然终局测试：退出码 0、29 checks、failures=[]，无 SCRIPT ERROR；日志为 reports/refactoring/main-review/natural-game-over-after-fifth-round.log。确认此前自动日志窗与稀疏变量 bool(null) 两个问题在该执行路径已消除，不替代终局返回大厅、多机或窗口验收。

第五轮公开状态API、十二类权威分派及 BUFF 样板已交付。E15两个旧消费者仍用已删除session属性，必须立即补接。网络命令模块只能确认发送，尚无请求关联成功回执，因此第六轮先补协议和适配器，再允许D15输入迁移。战区窗口诊断证实旧确认版本被权威拒绝，要求取消旧确认、重新点击，不自动重发。

第六轮10个代理按文件所有权推进：board统一投影、presenter削减与旧确认失效、lobby真实命令结果协议、网络适配器完成回执、内容准备两个消费者、EffectManager事务公开API、checkpoint/rule_state/replay消费者、闸门冻结副本归档和测试纠正、唯一窗口验收、release脚本迁移。冻结工程一律放Hermes scratch，reports只保留报告/日志/截图，以免历史源码污染扫描。

禁止将状态API模块完成视作消费者全接线，禁止发送OK推断执行成功，禁止丢弃旧证据以让闸门变绿。G04只在全新scratch目标准备构建，不覆盖用户现有发行包。

首轮有多个 headless Godot 进程并发，A08 性能测量可能受资源竞争影响。最终刷新策略需要独占进程复测，不以并发数据单独决定。

### 第七轮：当前工作树复核与继续实施

用户再次要求持续重构、尽量使用 10 个子代理，需决策事项先记录不逐项询问。本轮先启动 10 个只读生产源码的核验任务，分别覆盖 board 投影与命令接线、命令回执、事务状态、内容恢复验证、依赖闸门、消息播报、自然终局、发行工具、待答候选、剩余纯查询及服务拆分。独立报告写入 `reports/refactoring/round7-*.md`；随后依据真实结果分配唯一生产文件写入者，不把审计交付视为重构完成。

主代理已重新检查 git 状态，保留当前全部未提交修改。已读取上一轮 `C-D-integrated-window/REPORT.md`：该次冻结工程因战板 Variant 类型推断错误未产生完整 RESULT，八套窗口运行均不能计为验收通过，截图只显示启动图或空画面。冻结指纹期间源码继续变化，因此必须先核对当前代码，再修复和重新窗口验证，不能把冻结失败直接认定为当前结果。

本轮暂不并行运行窗口或性能探针；headless 专项结果与窗口验收分别记录。所有子代理的成功自述仍须主代理复核产物及关键运行证据。

### 第八轮：缩小并行任务并继续修改

上一批无存活子代理后，重新分派 10 个范围受限的任务。board D16 与网络命令适配器分别为唯一生产文件写入者，其余负责独立专项或下一步精确调用闭包，避免重复全面审计。暂不将已有报告的成功表述作为当前工作树通过证据。

主代理现场复现 `rule_guard_chain_rollback_test` 回滚后 `choices[0]` 越界：35 秒内未产生 RESULT，自有进程终止，日志 `reports/refactoring/main-review/round8-chain-before.log`。仅修改测试，在回滚前保存函数局部 `original_choice`，保留所有撤销与拒绝旧答复断言，不改生产回滚语义。

修改后真实复跑，前八条跨玩家回滚检查均为 true；随后延迟尾部链的“子效果再次暂停”检查为 false，并在读取缺失事务 root 时脚本错误，90 秒内未产生 RESULT。日志 `reports/refactoring/main-review/round8-chain-after.log`。因此本专项仍未通过，后续需追踪延迟尾部实际执行与事务归属，不能把数组越界修正视为整体修复完成。

第七轮迟到完成消息已收到：10 个任务中仅命令协议与状态核验正常完成，其余 8 个中断，不能计作完成。主代理实际读取两份原始聚合 JSON，确认命令三套退出 0、39/29/313 checks、failures=[]；状态日志保留三个超时与延迟续行红项。这些结果仅代表旧执行指纹，不覆盖第八轮修改，也不替代窗口验收。当前第八轮继续推进，不依据迟到消息重新派重复任务。

### 第九轮：生产接线与真实红项修复

第八轮 10 个任务均交付报告，生产修改仅 D16；D14 新增生命周期 RED 仍有六条失败。主代理已读详细报告，确认不能把独立 actions.cards 候选与当前组合可加入候选等同，也不能据静态删函数报告宣布 presenter 完成。E15 消费者真实采用仍红，恢复单项通过不覆盖采用；发行 audit 不存在/空包误通过与 `.import` 契约冲突是实际阻断。

第九轮继续使用 10 个唯一写入边界：D17 board/source 组合投影、D14 session/网络命令生命周期、E01 内核消息 serial 及快照排除、发行工具准入、E15 消费者与夹具根因、D20d 权威终局收尾入口、独立通知 inbox、网络待答 source 薄接线、延迟尾部测试与诊断、唯一冻结窗口执行者。D20d session/gateway/board 完整编排在权威接口交付后由主代理接线，不提前声称回大厅已完成。窗口冻结版本与并行生产版本分别记录，不能将旧冻结通过自动归给当前代码。

### 第十轮：完成跨文件消费者接线并消除整合阻断

主代理已读取第九轮 D17、D14、权威终局、延迟续行及窗口详细报告，原生加载网络输入和 local-terminal 两张截图。网络截图可见选牌及费用浮窗；local-terminal 截图仍为战局、BUFF 描述层未关闭，不是成功主菜单。第九轮窗口网络专项有完整 RESULT；BUFF/返回没有 RESULT，不计通过。

主代理实际运行当前依赖闸门：FAIL，findings=86、allowlist=100、new=3、stale=17。新增访问为 message_identity 的两次私有 serial 及独立 continuation fixture 的私有 scope；需消除新增并退休过期许可，不扩白名单或借反射规避。第九轮两套延迟续行虽已交绿证据，邻近 rollback 测试发现 CHECK false 被检查点回滚吞掉，必须修断言宿主隔离并做负向复验。

第十轮 10 个任务继续生产实施：D20d session/board/gateway完整编排、D17 presenter共同费用渲染与旧夹具迁移、E02权威epoch/stable投影、E03面板inbox、rollback夹具根因、BUFF/返回唯一窗口诊断、闸门及私有访问根治、G04安全完整冻结、长replay恢复诊断、D15准确命令迁移闭包。共享文件唯一负责人，协议和公共接口按实际产物接线；核心模块完成仍不算消费者链完成。

### 第十一轮：已确认生命周期政策进入实施

用户已逐项确认 Q01：运行资源配额、恢复服从当前政策与部署入口显式批准根、安全关闭/紧急停止分离、曾就绪与首次启动区分、心跳可重试并明确持续故障、存档和未知证据保留且允许保守自动清理。已同步待确认文档及方案新增 F11–F16，不把政策确认写成生产完成。

确认后现场检查第十轮仍有 3 个存活任务，新增 7 个独立任务以保持最多 10 并行：manager准入/启动状态、部署批准根、独立心跳故障策略、独立保守清理策略、安全关闭消费者、生命周期公开行为测试、结果汇总器防假绿。manager、CLI/hostclient、console/shutdown各有唯一写入者，心跳与清理模块先独立验证再接消费者；期限/预算未声明不猜值，未知保存证据与正式存档不得自动删除。

### 第十二轮：第十轮交付复核与后续推进

第十轮已完整返回。主代理读取 D15 逐点交接及长 replay 计时报告，并现场重新执行依赖闸门：PASS，findings=83、allowlist=83、new=0、stale=0，仍包含 layer=8/private=75，不称私有依赖清零。

主代理实际读取 `round10-freeze-candidate-v8/actual-artifact-audit.json` 并检查精确 EXE/PCK 路径存在：状态为 STATIC_ONLY_RUNTIME_PENDING；PCK 1073 项、禁止资源为空、导出日志门禁通过。该证据只属于冻结候选，executed_gui=false，不能宣布 G05 或当前并行源码已发行验收。

长 replay 明确仍红：完整 141 动作录制后恢复持续推进到 130，主要耗时为完整 state_hash，尚无死锁证据；正常退出失败不算恢复通过。native choices 仍访问已移除 `_seen_messages`，即使打印绿色 RESULT 也有脚本错误，不能计绿。BUFF/返回独立冻结套件报告已交 24 checks，通过证据待主代理完整复验。

新增 3 个唯一边界任务继续工作：D15结束行动共同命令壳（board/presenter）、原生选择夹具迁移及唯一窗口验收、完整状态哈希精确计时/等价优化（replay/NetIds/RuleState）。与第十一轮7项生命周期任务互不重叠，不缩状态根、不删前后哈希、不延长180秒预算换绿。

### 第十三轮：补齐并行能力，推进播报与剩余边界

用户再次要求持续按方案使用10代理。现场存活4项（manager、D15、回放性能、唯一窗口），新增6项不重叠任务：GameProgress/EffectCheckpoint显式播报等待与快照边界、共享播报命令与批次身份校验、权威消息重连基线、LoadGame角色路由移交bootstrap、生命周期新策略公开组合契约测试、客户端五类收件箱可执行拆分契约。需要交叉接线的公开接口已向相应所有者发送说明，不以猜测字段先行实现；RuleState仍由回放所有者独占。

主代理读取保守清理交付报告：独立策略及执行器已存在，但无生产台账/部署调度接线，不记F15整体完成。其GDScript路径/摘要复验不等于原生原子删除，外部替换竞争仍为已知边界；正式存档、未知保存证据均继续保护，不能直接按目录年龄接自动清理。

### 第十四轮：生命周期整合与主代理真实复验

第十一轮交付完整返回后，主代理读取manager准入/曾就绪、心跳与安全关闭报告。manager已迁移，心跳/清理仍是独立组件；gateway创建者断线直接stop_room及manager析构链尚不能视作安全关闭。继续分配唯一manager/worker/部署入口写入者实施F14真实采样、故障投影与worker安全保存路径，不以策略GREEN替代消费者接线。

主代理复跑独立 `round11_lifecycle_contract_test`：首次漏传 `ROUND11_LIFECYCLE_SCRATCH` 导致相对夹具路径被安全门拒绝，已将仅本次生成的 `round11-lifecycle-3701887` 精确移动到Hermes scratch保留，不放宽生产安全门。按物理scratch显式配置复跑后仅剩旧错误文案断言失败；检查生产确返回“运行资源配额不足”，故仅修改测试断言并加入缺绝对scratch时正常失败前置保护。

最终主代理真实运行：配置正确时 exit=0、32 checks、failures=[]，包括真实原生owner自有子进程EXITED/release；缺配置反例 exit=1、1 check、明确失败RESULT，无脚本异常、未超时。日志 `reports/refactoring/main-review/round14-lifecycle-configured.log` 与 `round14-lifecycle-missing.log`。此证据覆盖该32项契约，不替代有对局存档恢复、完整心跳安全关闭或发行验收。

### 第十五轮：结束命令复验与后续小簇实施

第十二轮三项交付返回，主代理读取详细报告，不将长回放第一次恢复通过当作两次恢复完成；原141动作、两次完整恢复在原预算下仍红。窗口冻结两套有有效RESULT，但另发现连续toast被前一隐藏tween提前关闭，提示寿命问题仍需生产修复。

主代理在当前工作树真实复跑 `battle_board_end_command_test`：exit=0、38 checks、failures=[]，没有SCRIPT ERROR；证据 `reports/refactoring/main-review/round15-end-command-current.log`。覆盖真实本地/ENet结束推进、同步结果、在途拒绝/旧视图、close未知、旧adapter隔离和显式重建，不替代窗口或完整认证成功恢复。

新增3项唯一写入任务继续落地：board/presenter主动发动与令咒命令小簇及toast寿命、gateway断线/正常关闭安全收尾、console可信消费清理台账。其余任务保持原文件所有权。F15台账仅授权已消费且同实例保存/退出已证实的临时产物，缺完整实例集/互斥证明不执行删除，不擅删存档/未知证据。

### 第十六轮：播报公共契约后接线与客户端收件箱实施

第十三轮6项返回。主代理读播报核心、E04、E14与F06详细报告：GameProgress公共batch接口现已存在，而dispatcher代理早于该接口落盘交RED，不能继续把缺接口视为永久阻断。E04真实RSA/ENet重连专项已交，但authority集中读取私有消息分配器水位仍须公开接口替换；独立worker恢复与旧跨进程seed红项未闭环。

E14移除LoadGame场景反向依赖已交，需退休精确旧许可，不新增放宽。RuleState单调播报序号排除及成功Replay恢复换发仍需当前版本接线，旧consumer测试必须迁到显式bool，不能删除其资源/事务断言。F06现有34项契约GREEN仅是迁移前边界，新客户端收件箱生产模块尚未建成。

现场4个任务存活，补6个唯一边界任务：F06真实session/inbox迁移、E07权威投影/共享确认命令、E06规则哈希与成功恢复batch接线、消息公开只读水位与闸门退休、唯一结束行动/toast窗口、旧播报/恢复夹具契约迁移。跨文件接口按实际落盘产物接线，未接调用方不算功能完成。长回放仍需保持141动作两次恢复及原预算，不为GREEN放宽引擎指纹或缩减状态。

### 第十七轮：F06与播报视图合并验收阻断

第十六轮交付返回后主代理实际运行gate：FAIL，findings=95、allowlist=80、new=15、stale=0。15项均为 `replay_restore_batch_test` 新增私有GameProgress字段访问；公共水位已被authority接线，不能再按旧报告认为其私有读取尚存在。安排测试唯一写入者改公开行为覆盖，不增许可。

继续6个独立任务：E07d认证房主显式代断线确认及正式开局声明、恢复批次测试/闸门根治、窗口资源泄漏根因、稳定冻结长回放性能、实际新导出EXE角色运行、旧服务端测试公开接口与批准根迁移。现有board主动发动/toast、gateway安全关闭、manager心跳接线维持独占。

主代理当前源码复跑F06契约，先因旧手造view缺E07全部四字段被mirror拒绝后读取stamp脚本错误，175秒无RESULT终止。只修测试state显式声明无pending播报、首份view失败正常退出，不改mirror。复跑45项行为检查通过exit0，但仍有74 ObjectDB泄漏警告和24resources ERROR，不能记干净GREEN。日志 `main-review/round17-client-inbox-current.log` / `round17-client-inbox-after.log`。已将此与窗口泄漏相近的证据交窗口诊断者，需追是否Session/Inbox共享闭包生命周期根因，不先假定仅夹具问题。

### 第十八轮：引用环实证交接与player待答迁移

第十五轮返回。主代理读取activation/toast详细报告，Session泄漏已有真实weakref探针因果证据：四个Inbox lambda强捕获Session，close后仍存活，断开四回调即释放。已把精确报告行与探针日志交当前Session唯一写入者根治，并通知窗口诊断者避免重复猜测；不得把正式测试teardown断开代替生产生命周期修复。

board/presenter生产所有权释放后继续D18 player_choice source声明与D15答复/取消命令迁移，保留AI控制域和同声明选择状态，不重算规则、不复制网络锁。主代理当前源码独立复跑toast专项：exit=0、4 checks、failures=[]、无脚本/退出ERROR，日志 `main-review/round18-toast-current.log`。该结果仅证明四项寿命边界，非冻结窗口GREEN。

gateway报告已移除创建者断线直接强停，但close的pending/pumpable上层编排和既有gateway ready/成员快照红项仍需整合。清理台账已交200项证据，CLI配置/调度与跨进程互斥适配仍未完成，不能宣布自动清理全链完成。

### 第十九轮：心跳交付证据复核与清理调度接线

心跳运行时交付返回后主代理读取详细报告、verification.json及其中五份实际日志，确认心跳90项、准入53项、部署47项、策略58项及安全关闭PASS均有真实RESULT，未发现CHECK false或SCRIPT ERROR/ERROR。该证据属于交付执行版本；worker日志中的timeout标记表示监督超时故障场景，不等于测试进程被外部限时终止。活跃真人对局档案flush/恢复未在本专项覆盖，不能据lobby保存测试关闭整链验收。

释放CLI/console写入边界后，继续F15本机配置与调度：参数显式声明，可信完整实例和跨进程互斥不能常量true；缺证明只输出候选诊断不删除。保留heartbeat配置与安全close语义，正式存档和未知证据始终保护，不新增默认期限。新任务只拥有CLI/console/ledger，不碰仍由其他代理负责的Session/UI/authority及当前窗口。

### 第二十轮：区分长回放功能正确性与性能门槛

第十七轮交付返回：引用环已由Session所有者修复；窗口end/toast在其冻结版本干净通过。长回放固定170秒软维护截止仍取消，不能称恢复功能已证实错误，也不能把超时变绿冒称优化完成。主代理新增独立正确性探针，不修改生产工程或原性能测试。

从 `round17-replay-exclusive/project` 完整复制到全新Hermes scratch `round20-replay-correctness/project`，仅隔离副本测试看门狗改540秒、进程硬限560秒；所有生产源码、141动作、两次恢复、完整前后/终局hash及规则预算不变。实际运行238.968秒自然exit0，10 checks、failures=[]；两次恢复均到自然终局且完整状态hash相等，无SCRIPT ERROR/ERROR/CHECK false，生产源码前后SHA漂移为空。证据 `C:/Users/Administrator/AppData/Local/hermes/cache/scratch/round20-replay-correctness/{result.json,correctness.log}`。

该结果证明旧冻结版本的完整恢复正确性，不证明当前并行代码版本通过，更不关闭原180秒性能门槛。最终包须对最终冻结重新运行完整正确性；性能问题单独保留，不能把延长诊断限时称为加速，也不再无区分地描述为“回放无法完整恢复”。

### 第二十一轮：真人包主链优先与剩余生产拆分

清理调度交付返回，主代理读取报告：本机配置及只读preview已接，真实跨进程排他/完整实例登记仍不足，生产保持blocked不删除。不得将59项调度GREEN解释成生产自动删除已完成；正式存档、UNKNOWN和未决意图继续保留。

当前player迁移仍独占board/panel，新增7项实际实施/验证：F07 blobs接收迁移、F03/F04内核公开审计入口、worker/gateway播报声明及授权路由、纯信令发行编排修复、活跃对局save-stop-restore、唯一正式一回合窗口、24套核心整合回归。只读工作限定为实际执行验收，不再重复全仓审计；共享生产文件均唯一写入者。最终包仍须基于最终冻结重新导出，不拿已运行的旧冻结EXE验收后续源码。

### 第二十二轮：player主代理复验与播报UI接线

player交付后主代理读取详细报告并独立复跑当前 `player_choice_source_command_test`：exit0、65 checks、failed=0，无SCRIPT ERROR/ERROR/WARNING，日志 `main-review/round22-player-current.log`。验证同声明保持、A-B-A旧按钮、adapter重建、本地与ENet真实支付/取消不支付和生命周期锁；不是窗口验收。

释放board/presenter后继续E07e：source播报声明消费、本人批次确认共用命令、LocalBattleCommands显式AI名单/节拍、正式大厅开局前能力声明、房主显式代断线入口。后者候选必须权威明确授权投影，缺字段先交接，不在UI猜身份或在线状态。唯一写入者拥有board场景/脚本、presenter和lobby_screen，不改仍属其他任务的session/authority/worker/gateway。保持已迁移player/end/activate及结算/组合提示行为。

### 第二十三轮：代确认授权生产投影与active待答迁移

播报UI交付后主代理读取详细报告：本人/AI接线已落地，代断线按钮仍因生产actions缺授权声明而安全隐藏，不能据587项headless将房主按钮判为可用。继续唯一session/authority写入者补四字段can_confirm/view_seq/batch_id/seats纯查询投影，复用最终授权并与同次签发视图关联；board/panel/renderer另一负责人迁移active/options待答与本地命令，不重算规则或先写数量。

主代理读取整合回归报告及归档 evidence.json，再逐份解析 `round21-integrated-evidence/logs` 中24套stdout/stderr：实际套数24、RESULT checks合计1190、无缺结果、无SCRIPT ERROR/ERROR/CHECK false，与声明24PASS一致。首次核对路径误指归档根而非logs子目录，工具明确失败后已按实际路径重验，未遗漏日志。结果仍绑定该冻结，后续播报UI与active等变更需复验。

同一报告保留原性能RED与独立正确性probe通过，不能将24核心GREEN称所有门槛通过。当前优先继续真实active-save/restore与最终角色发行验收，自动清理blocked和剩余完整会话拆分均保持明确状态。

### 第二十四轮：活局保存恢复证据复核与正式窗口阻断修复

第二十一轮整批返回。主代理读取活局、窗口、worker播报详细报告，实际解析 `round21-active-save-restore-logs/verified-summary.json` 及verified-1/2原始日志：两次均exit0、35 checks、failures=[]、真实saved=true、ACK/revision=2、playing、恢复后规则命令续写与SERVER_STOP_COMPLETE，无SCRIPT ERROR/ERROR/CHECK false。这是源码真实双身份/独立worker活局链，仍不等同最终发行EXE或跨机真人验收。当前gate主代理复跑PASS：80/80、new=0、stale=0。

窗口交付保留server一回合49项和v2一回合35项有效通过，但native旧请求字典缺键、正式大厅数据准备/开局与旧私有注册字段访问仍RED，整体不通过。另worker已有顶层能力接收契约，manager尚未生产该字段，LAN true明确拒绝；不能把同进程worker确认专项当独立进程能力贯通。

新增3个直接修复任务：manager/CLI/LAN本机播报能力spawn注入；唯一native+正式大厅GUI根因修复复验；遗留gateway binding/runtime guard夹具公开行为迁移。仍在跑的代确认授权投影与active待答保持session/authority和board/panel唯一写入边界。优先清真人包主链阻断，不用旧冻结包覆盖新源码。

### 第二十五轮：主代理修复quantity网络声明并继续card/身份拆分

active交付明确有query数量StringName键阻断，不能计为全GREEN。主代理读取实际query及旧activation测试，最小修改 `item["quantity_range"]` 显式String键，保持mirror严格校验；旧activation raw身份断言改为可见面板与实际source声明相等，保留规则真实pending身份断言。

主代理真实串行复跑：active_choice_source_command=65/0、battle_board_activation_command=21/0、match_seat_query=33/0，三套exit0，无SCRIPT ERROR/ERROR/CHECK false/超时。日志与汇总 `main-review/round25-*.log`、`round25-active-results.json`。带零数量的真实网络业务已能继续执行，不再依手造prompt绕过投影。

按已释放文件边界继续D18 card声明/本地答复取消迁移及F08客户端身份完整闭包拆分。card与regular出牌入口必须分离；身份协调器不得反向强捕获Session或混淆member与connection。代断线actions投影已交，正式窗口仍待唯一窗口者复验，不能据纯查询10项算按钮全链通过。

### 第二十六轮：正式UI与独立worker能力最后组合根缺口

第二十四轮返回后主代理读取spawn及窗口详细报告，并解析final-results.json：实际9次运行、checks合计677、全部exit0且errors为空。真实manager顶层配置→独立worker→Session→authority本人/代离线确认已验证；不能拿此替代正式UI的start前注入。窗口native59项、大厅11项自然退出且无资源ERROR，但该冻结实际worker配置为false，仅source四字段结构检查不能证明屏障政策启用。

当前F08 Session唯一写入者已收到精确交接：host_authority/host_authority_peer创建host client后start前，必须按明确本机部署能力参数调用已有公开configure接口，默认false且生命周期拒绝门不变；UI Session后期declare不能被当作独立worker已收到。保持文件单写者，未由主代理越界修改Session。

完成的测试binding20/guard34及窗口修复不代表后续并行树验收；card/F08仍在实施，最终正式大厅须按显式true配置与真实pending确认业务重新冻结复验。入房偶发断线证据保留，不把重跑成功称为根治。

### 第二十七轮：card/F08接收后补真正消费者与失败隔离

主代理读取round25-card与F08详细报告。card声明消费已落地，主代理复跑card专项18项exit0、无错误；依赖闸门仍80/80、new=0、stale=0。card网络独立业务尚无专属ENet证明，不借active/player网络通过冒充。

F08八种客户端身份收件已迁入无状态协调器。Session新增显式本机部署API并在两个host start之前向具体Host配置；正式lobby组合根还未调用。报告同时明确真实活局恢复两观察者投影比较失败、true第二批播报未到达、四套旧身份夹具失败/超时。之前冻结的保存恢复通过不覆盖此次生产树；不推定所有红项都是旧夹具。

派出4个唯一写入任务：正式lobby声明及唯一GUI复验；Session/authority真实恢复投影与两批播报隔离修复；card独立ENet加location声明迁移；四套旧身份夹具契约迁移与鉴权负向复验。不共享生产写入者，不降低隐私/票据/规则哈希/屏障断言。当前离最终冻结仍有上述明确缺口。

### 第二十八轮：十边界并行继续与产物及时回收

用户重新明确要求最多10子代理连续推进。本轮主代理重读警告、方案与round27恢复/身份报告，复核master工作树及依赖门：80/80、new=0、stale=0。此前正式大厅16项与native59项不是新路径完整worker验收；恢复比较契约已修、true两批通过，但恢复至终局与管理save尾hash仍缺。Gateway.listen成功后未重开accepting_rooms的生产根因尚未修。

按文件独占分配10任务：board/panel七处旧命令；gateway监听生命周期；authority/Agent恢复停滞；Session F09房间收件；presenter资源阶段重复路径；release生产工具；通用E盘隔离运行器；replay/hash等价短探针优化；依赖闸门工具；唯一正式窗口执行者。各任务独占报告与新增测试，共享接口缺口交主代理串行接线，不扩allowlist掩盖新增违规。

旧test与scratch历史副本已按用户指令删除，必要日志压缩留在reports/refactoring/scratch-cleanup/historical-evidence.zip。旧报告中的scratch运行器路径已不存在，不能再当现存执行入口。新输出必须E物理根并实证主/子进程路径；冻结只复制必要输入、禁止复制历史产物，结束后保留最小证据及时回收自有大副本。疑问按独占报告交主代理汇入统一待确认文档，不中途询问。

### 第二十九轮：二十八轮接收与完整闭包继续

主代理读取D15/presenter/隔离运行器实际报告，再扫描当前board：桥外旧命令调用0，桥内显式13个方法，不用文字_commands为0假清零；层门80/80通过。用户新增20线程需求已改validator默认20及project共享pool20，主代理专项9项exit0；旧候选冻结不覆盖该改动。

十任务交付中gateway默认入房已修、F09四房间kind已迁、候选真实导出已审计但不是最终包；presenter完整令咒/抽屉/阶段仍有真实旧消费路径不能先删除。恢复180秒内推进round7仍无终局/save尾hash证明，不能将活跃推进叫整套通过。最终统一冻结、实际发行EXE与桌面裁切仍待验收。

继续4个文件独占任务：board/presenter共享展示真正消费闭包；Session F09内容收件；恢复终局一次可观测完整正确性运行并与性能门区分；原始证据核验及当前树聚焦回归。运行器E路径与及时产物回收继续执行。regular独立浮层没有正式producer，联机任意draft缺预览API，保持失败关闭不猜测引入新交互。

### 第三十/三十一轮：补满后整合红项与恢复正确性接收

用户要求补满后安排七个独占任务：网关正负场景隔离、F09 guard、过滤令咒view契约、候选发行EXE真实运行、纯信令、generic RESULT兼容、唯一GUI。补充13场景返回红项后主代理读回manifest确认副本回收，不拼原39与新13为同冻结通过；再用释放的两个名额修blob/sync真实前置与脚本错误，以及validation前置/整合duplicate_check误判。CHECK文案重复不等于重复事件ID；错误/false/RESULT计数仍须严格校验。

第二十九轮恢复完整正确性交付后主代理读取报告及run-complete/result.json、原stdout、正式terminal-save.response.json：exit0、288.096秒、77项空失败、189进度样本、无SCRIPT ERROR/ERROR、自有Job活动0。真实管理回执result.saved=true、records=200、state_hash明确；未把顶层缺saved误判，也未读取/输出身份秘密。该PASS绑定冻结与最终Agent/比较器测试补丁，不是180秒性能通过，不覆盖后续Session/board漂移。

共享展示闭包报告已交完整令咒/抽屉/阶段迁移，御主定制令咒图与zoom未进view是明确缺口；source/view独占者处理现有契约，不让UI猜图。发行客户端候选导出exit0但仍待EXE实际验证，信令import异常139由独占发行者分阶段复现，不能用旧包替代。当前继续处理真实失败与最终一致冻结，不把十任务或阶段报告完成当交付。

### 第四十七至五十轮：真实消费者收口与许可退休

用户再次明确要求尽可能10子代理，默认模拟预算最新为15秒，引擎保持不变。Round47八任务独占交付后，主代理读取host、presenter、worker route三份具体接线报告并重扫：62 findings、80 allowlist、NEW=0、STALE=18。逐个核对失去调用点的2项manager场景引用、5项acceptance和11项公开测试消费者许可，主代理精确删除18项；实际gate PASS 62/62，layer=5/private=57，NEW=0/STALE=0，闸门自身18项单元通过。剩余私有例外来自测试/诊断夹具，不笼统称为生产内核私有访问。

模块成功未等同生产完成：host组件33项通过，但正式终局14项两红，Session未为match_finished_lobby交真实accepted回执；presenter威力闭包23项通过，board基础威力段仍重复绘制；validation_task仍待消费新的bootstrap角色参数builder。以上分别交唯一Session、board、validation_task写者收口，不注入假回执、不凭大厅快照冒请求成功、不扩闸门。

Round48主代理读回GUI原manifest SHA、72项exit0及panel/approval当前hash；15秒完成→等待风险确认→实际确认→applied/check_finished，取消倒计时残留已修。GUI执行后Session/statusinbox漂移未被覆盖，Round49唯一窗口执行者串行复验。原生合法CABI对照与正式安全项目冷导入由唯一native执行者继续，不换Godot。受控/定点assembly66成功只证明本次成功，原Round43目录发布失败仍未根治。

cleanup同HANDLE验证删除原语18通过/1权限SKIP，只是能力模块；生产跨进程台账事务、完整实例registry和Job子树退出证明仍缺，自动删除保持blocked。后续独占实现Job lease原语，不能靠manager.rooms或新bool伪造完整性。同步安排console请求codec、CLI只读部署校验闭包、三套guard公共观察器和最终候选选择前置；不在生产写入期间再次全70回归。每次独占冻结保存真实日志/退出/源码hash，回收已消费自有generated，接口稳定后主代理统一退休新许可并串行完整验收。

### 第五十轮接线交付与第五十一轮核验

主代理已读取Round50验证/guard交接及确切manifest，校验task六套162项manifest摘要与passed=true，Session/board/task当前hash与交付相等，正式终局board14真实manifest通过。本人威力重复网络绘制2→1、本地1→1的15套778项为独立冻结，不与其它专项相加冒完整候选；终局GUI尚待唯一窗口执行者。本轮唯一剩task场景层引用与11项guard观察私有许可均确实消失，主代理精确退休12项，实际gate PASS findings=50 allowlist=50 NEW=0 STALE=0（layer=4，仅bootstrap角色声明；private=46，遗留测试/诊断），自身18项单元全通过。保留3项必要fault-injection许可，不为清零新增生产getter或删负向覆盖。

新候选选择仍存在三项执行前置：抽取式tight诊断helper不是常规工程依赖、服务批准测试继承硬编码输出根、worker生命周期测试猜engine兄弟目录。独占写者修正分类与显式参数契约，先聚焦真实fixture及preflight，不捏helper、不提前全97。默认15 CLI首次设置同步的真实失败另交只读trace，不能用核心六套成功掩盖。最终唯一GUI新冻结验证终局真实点击/大厅转交、威力费用预览与15秒完整状态链。

WindowsJobLease五项真实独立probe通过，但尚未接生产。native唯一源码集成人仅连接现ProcessOwner/Atomic类、编译隔离DLL并记录构建溯源，不新增第二spawn/不覆盖正式DLL、不启动Godot抢冷导入执行者；同Job active=0、同HANDLE原子删除及原有四能力须随后真实runtime验收才能采用。完整registry/跨进程台账仍阻断生产自动清理。现原引擎与正式DLL保持不变，native合法对照执行者有界追因；不把最小对照失败直接当正式包不可交付，也不抹历史原生失败证据。

### 第五十二轮：实际两角色候选与信令独立阻断

主代理已读回E:/FateCandidates/round52-current-roles-20261010-sa1/单一manifest并对真实client/server EXE/PCK逐SHA核验，分别与docs/round52-current-role-candidates.md相等；信令目标目录确为空。正式fresh冷import及两个角色导出通过，信令首次fresh冷import PID16072却返回0xC0000005；该次执行按门停止，没有信令产物、没有后续EXE运行/READY/用户E根/建房预算/关停验证，不能报三角色完成或最终人测包。

下一步分别授权独立新执行：两已导出角色只读包、同hash实际EXE runtime；信令唯一执行者验证角色专属原生加载职责，只有官方支持的运行前显式加载且全原生能力与两次fresh cold+READY/合法退出真实通过，才接最小生产修复。禁止隐藏exposed/删类、暖重试或加sleep；正式游戏两角色行为不随纯信令变更。源码信令缺配置exit2与执行器固定exit1是待核实的调用契约，不直接改生产2迁就错误断言；实际negative须精确指定exit/reason/错误scope，不能任意非零通过。保持现原引擎/正式DLL，新Job/cleanup原语未发行；所有新结果仍独立绑定hash。

### 第五十三至五十六轮：信令运行入口通过与发行关停接缝

纯信令已沿官方GDExtensionManager显式运行入口加载外置本机声明descriptor，原DLL/四类13方法保持。主代理读回两fresh cold/export/runtime退出0及缺配置exit2，核对实际EXE/PCK/descriptor/DLL摘要，候选E:/FateCandidates/round53-signaling-runtime-entry-sa1/artifacts/signaling/；不是旧minimal底层竞态修复，也不是三角色同冻结完成。

原client/server发行包独立运行得到正式opening、空网关JSON/CFG READY/consoleStop正常；release模板禁用--script覆盖，因此停止包外探针，不改模板去测。随后以真实source-editor认证客户端连不可变发行server，RSA建房→workerREADY→settings15→空大厅保存room_state_saved=true/saved=false→workerEXITED→原handle释放均通过，但gateway.stop未消费此前console关闭历史，PID28100保留，错误为“原生进程句柄不可用，无法确认本次保存”。此现象不由半条成功覆盖；不强杀或重复stop盖原失败。唯一shutdown/manager写者修current同实例闭合历史+同请求保存回执交接，未知/缺证/旧实例继续拒绝；旧PCK必须新导出后复验。

可信本机status新只读观察47及旧channel25通过，真实CLI/consoleIPC读回15/61.25、四类13方法、pool声明；只作观察不授cleanup或完整registry proof，需新PCK发行才算包运行读回。统一三角色sourcefingerprint制作前置已安排，不拼旧game2PCK/新signalPCK。

### 第五十六轮关停修复读回与第五十八轮完整执行

主代理精确读回shutdown handoff两生产hash、final-main86/final-pending36/原regression161的原始result.json，均exit0/无失败且本次Job0，总283项；current两生产hash相等。旧gateway28100仍活不在本次回收范围，旧包无受支持unregister-saved入口，禁止room forget删回执冒撤登记；只记录缺口，不强杀、不重复stop盖旧失败。

三角色同源工具目前仅15项Pythonpreflight有效，build未执行，run-formal明确NOTIMPLEMENTED/exit3；主代理尚未签发readytoken，不拿stage名字或新工具存在当实际导出。其sourcefingerprint/dependency gate需要currentGUI/currentheadless真实证据，旧manager/config观察不能追认。当前所有生产GD写者完成，主代理启动一次完整当前headless及同冻结extracted-harness requiredstep，补真实已落盘shutdown/status场景后按程序对账实际selected/unique/executed/pass/red/blocked，严格保留assembly66及性能门，不在出现红后整批盲重跑。GUI和新DLLruntime分别独占执行，正式原DLL未替；得到真实一致结果后才签新三角色冻结。

最新统一GUI冻结host17通过，但net46有13连锁失败、countdown71有3失败，主代理读回真实manifest并亲看completed图显示“校验完成，正在请求应用所选数据”，非仍模拟；唯一GUI写者追第一命中→seq→权威pending及风险/自动应用分支，不为了72假设强制造risk。native binding构建失败先比较MSVC官方TYPED_METHOD_BIND/NOMINMAX/utf8合同，不直接把缺宏误称SDK ABI；正式DLL仍未替换。抽取tight诊断required步骤由独占候选owner真实生成执行并归档，不造res helper/不直接跳覆盖。GUI/native/preflight分别绑定本次证据，仍未完成最终人测。
