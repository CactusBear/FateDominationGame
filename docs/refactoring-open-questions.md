# 重构待统一确认事项

用户要求：中途不逐项询问，需要决策的问题记在本文，等用户发出指令后统一询问。

## 已确认、不再询问

D1–D6 按 `docs/refactoring-plan.md` 第 6 节执行：播报真人确认与掉线显式处置、保留结算页面、在线消息不重不漏、本地共用命令校验、golden 后合并玩家名、位置规则独立模块且不改移动 operation。

## Q01 已确认：服务端生命周期政策

用户本次逐项确认以下政策，后续不重复询问。确认政策不代表代码已经实施或动态验收通过。

1. 配额限制运行资源，不限制休眠存档登记。启动中、运行中、关闭中尚未释放的自有进程计入；不能证明已退出并释放的 UNKNOWN 状态不得视为免费名额。恢复须重新申请当前资源配额，不删除超额旧档。
2. 恢复遵守当前安全与资源政策；批准数据根由本机部署入口显式设置。历史配置不得提升自身授权，不自动改端口、目录、部署模式以绕过当前政策；不合规旧档保留并给出明确迁移诊断。
3. 正常关房、全服关闭和无人回收先保存、取得绑定回执并确认退出；保存超时或状态未知不自动强杀。无对局的启动失败可清理自有进程；紧急强停必须是显式管理员操作并提示未保存风险、留记录。析构资源回收不能宣称存档成功。
4. 首次启动与曾就绪实例的监督能力失效必须区分。同一已就绪实例不因旧启动期限到期而被终止；能力未知期间禁止依赖可靠身份验证的操作，恢复时复验同一实例身份。真正新实例重新计算启动期限。
5. 心跳短暂发布失败允许重试，持续失败进入明确监督故障，不保持健康假象；重试/失效期限来自显式部署配置。不能首次失败即强杀，尽可能走安全关闭；未有保存回执只能报告结果未知。
6. 默认保留存档，未确认关闭证据不静默删除；允许自动清理已确认、可回收的临时证据及经过安全证明的孤立启动产物。正式存档删除仍是独立显式操作。保留期限、预算与清理条件由部署配置声明；未声明不猜值、不以容量压力淘汰未消费/未知证据，也不按目录名或年龄直接删除。

第六项“能自动清理”按前述存档与未知证据保护边界实施，不解释为允许自动删除正式存档。具体期限、预算尚无用户指定值，优先复用现有合法配置；缺配置时保持不自动清理，不在中途追问。

源码证据、失败补偿与候选拆分详见 reports/refactoring/server-room-lifecycle.md 第 6 节。该报告是静态分析，不代表风险已经动态复现；实施前按当前源码重新核查。

## A 项裁定（2026-10-10/11 用户逐条答复）

| 项 | 用户答复 | 落地口径 |
|---|---|---|
| A1 | "特殊效果可以用 operation 组合来实现" | 透支许可**由 operation 组合表达**（调用方显式传入许可，不用效果名查询、不用玩家数据字段）；扣费的单一职责原语照旧，`RegularPlay`/`PlayAttack` 合并口径 |
| A2 | "接受，除隐私最终门" | 人测包**接受**上表已知限制清单，**但隐私最终门必须先接线**（即 A3 要做） |
| A2 附加 | "前端那一点是过时信息，自行检查现有前端实现，并修改相应记录为现有前端实现" | 台账里至少一项前端记录**已过时**：须**按当前源码复核前端真实实现**并**只改正记录**（不改前端代码） |
| A3 | "前面的选项是①，然后挪模板位置" | ①把隐私声明接到实际消费者（不改导出过滤语义）→ **消费者已接线**：`role_privacy_audit.py` 状态串已变为 **`PRIVACY_PACKAGE_CONSUMER_WIRED_AUDIT_NOTRUN`**、真实 exit 0、`checks_removed=[]`（**剩余"审计未跑"一面，等冻结包生成时随正式审计完成**；注意 exit 0 ≠ 隐私门全完，状态串才是判据）；②把启动模板**移出 `tools/`** → **已完成并核验**：现于 `release/human-test/`（旧目录已清空、原字节不变、新路径不在 freeze/package `deny_components` 内），冻结按角色显式声明纳入，cold 清单 1442/1442/16、严格 1901/1901/17 |
| A4 | **"保留"（2026-10-11 用户答复）** | `server_bootstrap.gd:76–79` 的 4 处场景路径引用**作为组合根正当声明保留**；闸门以 `findings=4 / allowlist=4 / new=0 / stale=0` 为**接受的稳态**，**不再列为待清项**；不改冻结/导出语义，不把这些搬进配置数据 |
| A5 | "测试不传到 github" | 测试**不进 GitHub**：不移动位置、不改 `.gitignore`、不提交；本地落盘即可 |
| A6 | "按建议来，然后复合词不改" | 范围按建议（**游戏内可见文案 + 时点显示名**统一「魔力消耗」；debug/编辑器/注册表不动），**但复合词一律不改**（`印刷费用`/`区域移动费用`/`费用上限`/`费用减一`/`费用为 X`/`令咒可代替移动费用` 等保留原文） |
| A7 | "接operation，新增recordlog，补派发，走注册表" | 四步都做：①把 `RegularPlay` 里**已有但未用**的等价 operation 接上；②新增 **`RecordLog`** operation；③**补派发**（50 个空心时点：补派发而非删声明）；④**走注册表**（A 档 28 处双轨统一经注册表）。**注意写者冲突**：`regular_play.gd`/`PlayAttack.gd` 正被魔力修法任务占用，须排在其后；`all_operations.gd` 亦为共享追加点，串行。**2026-10-11 用户裁定：「做」——注册表统一在出包前完成**；口径修正：**不是 28 个调用点，而是 59 个直连执行站点、32 个调用文件**（另 15 个静态查询不动），批次表 `B01–B32` 见 `E:/scratch/registry-routing-plan/report.md`。**前置**：`operation_router.gd` 已存在（`exec_registered(func_name, parameters)`），但 `_SCRIPTS_BY_CLASS` 只覆盖首批 → 先由单一写者把路由表扩到 28 个目标类（显式 `preload` 字面量），冻结接口后再并行铺开消费者接线；每批实施前须按 `hermesWarning.txt` 第 4 条论证「能否用现有 operation 组合替代」；`B02`/`B08` 须等 A9 写者释放，`B29–B32` 须等各自写者释放。 |
| **A9**（新，已裁定） | 用户："**规则本意是2**" | **移动的支付先于落位**：慎二满魔力 12、工房→深山町、费用 1 → **正确结果应为 12**（先付 1 到 11，再入区 +1 到 12），现行 11（12 →+1 被上限截回 12 →-1）属**次序写反**。实现须：①在 `MoveLocation` 增**只读计划入口**，**保留 `exec` 原语义**（`data/attacks/basic/surveil/surveil.json:127` 直接调它做免费效果移动）；②`Move` 改为"只读计划（含落位可拒性前置）→ 支付（`PayMagic` 缺省不透支）→ 支付成功后落位一次"；③**支付与落位之间必须有原子边界**（落位被拒不得白扣费）；④找出并**只改**断言旧值 11 的测试/golden（逐条列前后原文，不删断言不放宽）；⑤Kirei data 按规则 2 做最小改动并逐字交前后差异。**证据**：`E:/scratch/move-payment-order-blocker/report.md`。**2026-10-11 进展与追加裁定**：按「只改次序」直接实现**不合格**——实测 `PayMagic` 派发 `MAGIC_DECREASE` 后 `SetLocation` 仍可因容量/常规禁入/出发落点锁拒绝，得到「已付 1 点、未落位、支付事实 1 条、目标禁入状态残留」；Kirei 最小数据重排同样打破「落位拒绝不得白扣费」。已按停止条件**停下、未改生产**（`E:/scratch/move-payment-rule2-atomicity/report.md`）。**用户追加裁定（逐字）：「先付后移，如果付不起或无法完成动作，提示玩家，然后不扣代价」** = 验收三条：①成功路径必须先支付后落位（慎二满魔力 12→12）；②**付不起**或**落位不可完成**（现有全部拒绝门）→ **提示玩家 + 不扣代价**（无魔力变化、无位置变化、无支付事实、不派时点、无部分状态）；③支付后仍被拒（如支付副作用改了目标合法性）同样提示 + 不扣代价。实现优先用**只读预检**把②③在支付前拦掉；④旧值断言迁移与⑤Kirei 数据差异仍须逐条列前后原文，不删断言、不放宽。**2026-10-11 追加裁定（逐字）：「选择后先测算能不能完成效果，能才执行先付后移等效果和时点」** → 即**可行性测算前置**：选定目标后**先测算整个动作（含支付会派发的效果与时点）能否完成**；**能**才执行「先付后移 + 效果 + 时点」；**不能**则提示玩家且不扣代价。**不采用**延后 `MAGIC_DECREASE`、支付后强制落位、仅回填魔力、改断言接受残留事实。**第四次尝试（新裁定批次）已按停止条件停下**：阻断＝`PayMagic.gd:25–28` 扣款后派 `MAGIC_DECREASE`，其 `self_magic_decrease` 效果可把预检通过的目标改为 `_can_move_to=false`（实测 `PREFLIGHT_ATOMICITY {"admitted":true,"after":3,"before":4.0,"moved":false,"paid":true,"payment_facts":1,"target_can_move_to":false}`）；且**现有检查点不可用于此处**（`effect_checkpoint.gd:44–50` 需 RuleRandom 已知，而 `rule_random.gd:3–5,52–56` 保留旧未跟踪全局随机 → 探针 `{"random":{"known":false},"ready":false,"rollback_available":false}`、`restore()` 返回 false）。**状态**：已按「测算前置」重新派单（单写者 `Move.gd`/`MoveLocation.gd`/`SetLocation.gd`；需新原语必须停下报最小设计）。 |
| **A8**（已完成并核验） | 用户："1a2改" | **(1A)** ✅ `release_contract.json:51–52` server→`server.cfg`、`:75–76` signaling→`signaling.json`；新增 `assets/config/signaling.json`（`port:24680` **取自 `multiplayer_lobby.tscn:111`**、`bind_address:127.0.0.1`，SHA `1ec13ce7…`）；`round56_three_role_freeze.py:477–481` 信令目标集合 3 项；三角色 dry-run 全 exit 0、`server.cfg` 走 include_filter、`signaling.json` 不进 PCK（隐私语义未变，主代理独立跑审计 exit 0）。**(2改)** ✅ quickstart `:63/:66/:67` 与 `human_test_candidate.py:308/:316` 五处已改。**未验**：未导出/未启 Godot/未执行启动脚本、包内最终哈希与真人联机待后续。 |

## 待用户确认

当前 Q01、Q04 均已确认。后续确需新增政策的事项继续记录，收到统一询问指令后再询问。

后续条目记录任务编号、源码证据、影响、选项及建议；未确认前不擅自新增规则或数据字段。

### Q02 已确认：默认服务器随机模拟预算15秒

用户最新确认默认改为15秒，替代此前30秒决定。修改正式模板assets/config/server.cfg的[data]声明，保持random_sim_enabled=true、20线程、完整校验及批准顺序；不自动覆盖现有管理员部署配置，也不将减少模拟覆盖称为同工作量的性能优化。新模板与实际读取、传输、模拟预算消费须专项复验。另收到倒计时结束似乎不能正常宣布成功的反馈，须核对进程退出/最终报告/服务端ready/风险确认和UI完成通知，不能以归零直接赋予批准。

历史决策依据：修改前正式 `assets/config/server.cfg:45-49` 声明 random_sim_enabled=true、random_sim_budget_sec=60.0。Round34同一次真实准备计时83.783秒，其中模拟60.113秒；20线程文件初检0.087532秒。没有固定种子列表时，现有模拟按时间预算持续建立案例，不是一局完成就提前批准。

这不是继续增加文件线程能解决的等待。现已选择15秒默认，不再等待统一询问；未选择关闭或后台模拟。其他复制、重复读写和目录发布缺陷继续自行修复，不依赖此决策。

### Q03 已决定：保持引擎不变，继续自行排查错误根因

用户要求引擎不变、自行排查。撤销把修补或更换引擎列为用户决策的前提；不升级、替换或修改Godot宿主。历史second-chance及回调顺序原件保留作为故障位置证据，不把崩溃位置等同完整归因。下一步从项目真实入口、CLI参数、插件初始化/反初始化级别、DLL/ABI/导出模板对应关系与干净最小项目对照重新核查；只有因果对照及真实修复验证才能关闭发行红项。

Round39已通过准确进程second-chance及生命周期断点证实，Godot 4.7.2 ed1daf0bf的EditorHelp在cleanup_doc后仍执行延迟文档回调，空doc触发0xC0000005。Round40正常编辑器首次扫描与官方退出路径的五个有效反证仍触发相同故障；没有可证明完整doc-ready的公开契约，增加帧数或等待首扫不能作为可靠修复。删除扩展类、暖缓存重试、放宽非零退出门均不可接受。

此前提出的修改/更换宿主路线不实施。当前发行故障继续自行诊断，不再等待用户批准引擎变更。证据docs/round39-native-cold-import.md、docs/round40-editor-import-lifecycle.md。

Round49主代理已读回新的合法对照原件：完整mandatory callbacks及真实实例化/释放的registered最小控制仍AV，无注册同DLL正常；正式安全1417文件工程两次全新缓存cold import均exit0，原DLL四native能力23项通过。故不能把minimal失败自动升级为该正式产品入口BLOCKED，更不能用旧不完整控制证明插件ABI完全排除。宿主完整动态doc时序仍有缺口，根因继续单列未知。当前源码已变化，实际3角色候选交独占发行者重新冻结/冷导入/导出/EXE实测，不借此旧freeze为新包背书；仍不改引擎、不删除能力、不暖重试盖冷失败。

### Q04 已确认：所有牌使用各自声明的牌背

Round68实际窗口证实，非持有者的暗置牌投影为visible=false、back_image为空，真实TextureRect.texture=null。现有隐私过滤有意不发专属背面，防止角色/职阶/来源泄露；正式卡背目录目前只有按牌种分类的资源，不能默认用attack卡背或从本地对象推断隐藏类型。详见docs/round68-play-groups-final-visibility.md。

用户先确认：“牌种是可以泄露的，技能牌和攻击牌就用自己的牌背即可”，随后追加：“其他牌也是，用自己的牌背就行”。最终统一所有牌类，沿用每张牌现有数据声明的卡背，经既有back_image字段投影，不加攻击牌/技能牌类型特判。镜像同步接受隐藏牌的合法牌背字符串，渲染器不从本地对象、尺寸或路径猜类型。不新增中性图片、展示政策字段或额外kind字段，缺少牌背声明时不猜替代资源。授权公开牌背不等于公开暗置牌正面、名称、费用、威力、效果或说明，这些过滤继续保留。

此前中性牌背A/B建议撤回，不再等待资源决策。按此新合同补权威投影、mirror及隐私正负测试，真实窗口确认卡背纹理；尚未通过这些验收前不把确认政策等同代码已完成。模态输入和恢复调查继续独立推进。

### Q06 已确认：可见文案规则边界（2026-10-10 用户答复）

用户答复：①**括号不需要处理**；②**量词也不需要处理**；③资源标签与正文费用**统一成「魔力消耗」**；④多条效果的**分行用换行符**判定。

据此收窄口径：扫描中 ②括号 26 项与 ③量词 49 项**不算违例、不修改**（工具改为仅记录/标注「本口径不处理」）；需要动手的只有 ④资源标签及正文「费用/降费」统一为「魔力消耗」、以及 ①「效果：」前缀 1 项。复合词（如「降费」）的最小一致写法由执行者列出候选交 main，不自行发明新规则。工具 `tools/scan_visible_copy_style.py`（SHA `d08db264…9d74c`），报告 `docs/copy-style-static-scan.md` + 同名 `.json`；真实扫描 520 个文件，原报 77 项违例（①1 ②26 ③49 ④1）+66 项待人工确认、0 解析错误。

### Q05 已确认：先交真人测试包，用户通知后才全量回归

用户明确要求：“等会实现完先导出包给我，我测试后通知你你再全量回归”。执行顺序更新为：完成剩余实现及必要的局部验证，冻结源码并导出真人测试包，执行最小导出/启动/基本交互与保存安全冒烟检查后交付，明确标注未完成全量回归及已知限制。收到用户测试后的明确通知之前，不自动启动、恢复或补跑完整回归。当前已启动的一套允许在原预算内安全结束，后续不再派发，保存现有证据与未执行清单。

真人测试包不冒称正式发行认证通过。旧工具对最终发行要求全量报告的门继续保留，测试包使用明确独立的候选交付流程；不得伪造ready token/sourcePASS/releasePASS。此顺序调整不授权隐瞒已知数据损坏风险或跳过必要安全验证。

### Q07 前端问题台账（用户指示：先记录，不立即改动）

用户指示（2026-10-10）："现有前端暂时不做更改"；随后细化为"**不回退 D15，前端不改顺位和玩家名即可，后面的前端改动先记录到问题里**"。据此本节只登记事实与最小修法候选，未改动源码、未写成已修或待修。

1. **D15 翻面半接线 → 已完成接线**：`scripts/net/ui/v2_view_presenter.gd`（hash `81285a18…`）的 `card_input(event, slot, submit_command: Callable = Callable())` 已获真实能力——board 侧 `battle_board_v2.gd` 现传 `_battle_commands.submit if _battle_command_input_available("set_concealed") else Callable()`（仅一行；board SHA `9f1cece2…` → `1e183b3d…`）。历史验证（不作为本轮当前树重新运行的结果）：RED 4/5 exit1（准确抓到第三参未绑定）→ GREEN **25/25 exit0、ERROR0、Job0**；含真实能力注入、presenter→共享适配器→ENet 权威翻面、生命周期退位/关闭不发送、右键连点仅一次在途、拒绝不扣费且 toast 非静默、人工重试可恢复。测试已入仓：`tests/d15_board_flip_wiring_test.gd/.tscn`。**边界：窗口真实点击仍未验收；presenter/顺位/玩家名/其它输入路径未改。**
2. **行动顺位表无展开/折叠入口（仍成立）**：当前正式 v2 有 `Rivals` 横向顺位列与 `Templates/RivalCard`、`Templates/SelfSlot` 的 `Order` 编号节点；`OrderBadge` 实属对手抽屉标题，不是顺位表开关。`Rivals` 显隐按视图非空决定；战果榜按钮仅切换并按战果排序 `Board`，不能充当顺位表折叠入口。源码未找到独立顺位表面板或对应开合输入绑定，不能把自动轮转/交接动画算作展开折叠。历史旧概括为「仅有 OrderBadge 与 RivalCard/SelfSlot 的 Order 编号节点」。用户界面要求含"行动顺位表可随时伸缩折叠"，该特定要求仍未实现；**用户已指示不改顺位，本轮只订正节点归属与证据**。
3. **玩家名展示须区分本方面板与顶栏顺位格（旧概括已过时）**：当前 `Self/Me/PlayerName` 已消费真实 `player_name`，与御主名 `Self/Me/Name` 分开；本地与网络均调用共同 `_bind_self()`。顶栏 `SelfSlot` 仍显示「我方」与顺位编号，不绑定玩家名。因此不能再概括为「我方未显示真实玩家名」或「玩家名功能未实现」；若要求的是**顶栏自身顺位格**展示真实玩家名，该位置仍未实现，不等于整套 UI 无展示路径。历史：旧台账概括为"本方未显示玩家名"，但原窗口报告 `newtests/round75_order_resources_window_report.md:33` 的失败 CHECK 原文实际是 `A 顺位1显示真实玩家名`，`:56` 的节点观察是 `我方` / 没有 Name 节点；34 CHECK = 31 通过 / 3 失败、exit1 保留为旧冻结结果，不据此否定当前本方面板绑定。**用户已指示不改玩家名；本轮只订正记录，不重跑或改断言。**
4. **缺省总威力仍显示假定值 0（仍成立，限定字段与位置）**：顶栏 `Stats/PowerStat/V` 仍读取 `player.get("total_power", 0)`；协议允许缺省 `total_power`，因此合法缺省投影仍会被该处显示成零。共同本方威力显示优先用 `breakdown.total`，其次 `total_power`，两者都缺才回退 0；不能把仅缺 `total_power` 的结论无条件推广到所有展示位。魔力/战果/普通令咒在 mirror 中为必需数值字段，缺失会拒收，不属于同一合法缺省用例。历史旧概括「缺总威力字段仍显示假定值 0」保留；原窗口 CHECK 原文实际是 `newtests/round75_order_resources_window_report.md:34` 的 `B 缺字段不显示占位垃圾数值`，`:8` 描述顶栏仍显示「合计威力 0」。**缺声明时不应猜**的要求在该顶栏缺省路径仍未满足；本轮只记录，不改实现。
5. **同批已通过项（写清以免误读为整体失败）**：敌方四项资源随正式快照刷新（魔力 5→9、总威力 7.5→12.75、战果 3→11、令咒 2→1）、单路输入 motion/down/up 各 2 与 GUI down/up 各 2、Job0=true、引擎日志无错误；原生亲看 initial/updated/missing 三张截图且与节点证据一致。结论仅适用于该冻结版本（运行期间 presenter 有外部漂移），ENet/权威命令与在场可读性未验。

以上保留的窗口结果属于原冻结版本；本轮第 1–4 项的当前结论来自源码复核，第 5 项仍仅为同批历史**已通过**项。本台账只登记事实与边界，不把静态绑定存在写成新窗口验收通过，未改动源码。

6. **出牌可用性与执行路径复核（保留历史对照表 `newtests/play_affordance_rule_audit_report.md`、专项 438 CHECK 全过，不作为当前树动态回执）**：①正式常规出牌走 `RegularPlay.submit_group`、**不走** `PlayAttack`，两者阶段映射/来源/张数/暗置条件/资源上限合同不同——提示与金框判据应对齐前者；②**历史规则层缺陷及已裁定修法（非本轮前端修复）**：旧冻结观察为费用 2→3 而魔力 2 时，组提交仍入场并扣到 `-1`，`PlayAttack` 则拒绝且不扣费。**用户口径（2026-10-10）：「魔力通常情况不能为负，除非有特殊效果」** → 默认不得为负，透支必须由**显式声明的特殊效果**开启，缺声明即不允许。历史修法要求（当时已派工；当前静态接线见下表 6②，未以本轮记录订正冒称动态修复完成）：扣费走**单一职责原语**（优先复用 `edit_magic`/`EditMagic`，否则新增 operation；参数由调用方传入、不写死规则数字）；`RegularPlay` 扣费前按**当时**魔力复核，不足不得扣成负值、不得留下部分状态（沿用现有 runtime guard/事务回滚）、不得二次扣费；`PlayAttack` 与 `RegularPlay` 的扣费口径必须合并成一处（消除两份实现）；③**当前前端事实（旧「未接明暗模式条」的缺功能结论已过时）**：卡顶悬浮控件是 `EffectButton`「发动效果」及其 `Effects` 选项菜单，仅在可发动能力存在时出现；常规出牌不靠这组控件，而是**右键按 `flip_cards/modes` 声明翻面、左键选牌/撤回、右侧 `Ops/PlayButton` 按当前组合预览统一确认**。旧记录「未接合法明置/暗置模式条」作为**字面控件不存在**的观察保留，但它来自旧概念交互，不能等同当前 v2 的明暗操作未实现；技能仅允许已暗置且觉醒时翻明，不能为满足旧模式条假定所有牌皆可翻暗。当前常规出牌候选已消费组合 `preview.candidates` / `can_submit`，不是 `PlayAttack` 或独立动作候选；但持有牌呼吸金框仍用「组合可出 **或** 主动能力可发动」，故「金框混入主动效果可用性」**仍成立**，不能写成金框与纯常规出牌合法性已完全一致。对照新的 v2 交互契约，明暗操作已有其它实现方式；纯出牌金框要求仍有差异。**本轮不改前端，不新增明暗条，不改断言**。

#### Q07 当前源码逐条复核（2026-10-11，仅订正台账）

范围：读取**当前工作树**而非 HEAD 或历史冻结。正式联机入口依据 `scripts/net/ui/lobby_screen.gd:666` 原文 `var scene := load("res://assets/scenes/game_scene/battle_board_v2.tscn") as PackedScene`；单人入口 `scripts/selection/selection_screen.gd:4` 原文 `const BATTLE_SCENE := "res://assets/scenes/game_scene/battle_board_v2.tscn"`。本轮仅修改本文 Q07；不改前端、规则、golden、测试或断言，不启动 Godot，不碰常驻进程。表中「仍成立」与「已过时」是源码结论，**不是新动态验收回执**。

| 原条目 / 子项 | 判定及当前事实 | 当前文件:行 + 原文依据 |
|---|---|---|
| 1 D15 命令注入 | **仍成立**：第三参已注入，不能再登记为 presenter 只有接口没有能力。当前 board 的右键分支还在转交 presenter 前统一处理翻面；「已接线」不等于本轮真实窗口翻面已验。 | `scripts/game_scene/battle_board_v2.gd:2740` — `_network_presenter.card_input(event, slot, _battle_commands.submit if _battle_command_input_available("set_concealed") else Callable())`；`:2728` — `if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:`；`:2735` — `_submit_battle_command("set_concealed", {"card": card_id, "concealed": not concealed})`；`scripts/net/ui/v2_view_presenter.gd:513` — `if not submit_command.is_valid():`；`:517` — `submit_command.call("set_concealed", {"card": card.id, "concealed": not card.concealed})`。 |
| 2 顺位表展开/折叠 | **仍成立**：顺位横列存在，独立开合入口未实现。`OrderBadge` 是抽屉标题；战果榜按战果排序，不能算顺位折叠的替代满足。 | `assets/scenes/game_scene/battle_board_v2.tscn:1039` — `[node name="Rivals" type="HBoxContainer" parent="." unique_id=1922141861]`；`:3622` — `[node name="OrderBadge" type="Label" parent="ModalLayer/OpponentDrawer/VBox/HeaderBar" unique_id=1569270243]`；`:4256` — `[node name="Order" type="PanelContainer" parent="Templates/SelfSlot" unique_id=1868585665]`；`scripts/game_scene/battle_board_v2.gd:1169` — `_rivals.visible = not view.is_empty()`；`:367` — `_top.get_node("BoardButton").pressed.connect(_toggle_scoreboard)`；`:3160` — `_board.visible = not _board.visible`；`:3170` — `players.sort_custom(func(a, b): return a.get("score", 0) > b.get("score", 0))`。已核对该场景节点、顺位绑定/输入及脚本中 Rivals 显隐引用，未发现顺位开合输入；不以名称关键词零命中单独作证明。 |
| 3 「我方未显示真实玩家名」 | **已过时（概括范围错误）**：本方面板已有真实玩家名展示路径；顶栏我方顺位格仍只显示「我方」。若要求只是显示本人玩家名，已有实现满足；若明确要求顶栏该格显示，仍有位置差异。不能据历史顶栏 CHECK 宣称本方面板没有功能，也不宣称本轮亲看过当前文字。 | `assets/scenes/game_scene/battle_board_v2.tscn:2162` — `[node name="PlayerName" type="Label" parent="Self/Me" unique_id=1720416935]`；`:2171` — `[node name="Name" type="Label" parent="Self/Me" unique_id=1224904099]`；`:4284` — `text = "我方"`；`scripts/game_scene/battle_board_v2.gd:2393` — `me.show()`；`:2395` — `_set_text(me, "PlayerName", str(player.get("player_name", "")))`；`:2396` — `_set_text(me, "Name", str(player.get("master", {}).get("name", "")))`；`:629` — `_bind_self()`；`scripts/net/ui/v2_view_presenter.gd:241` — `board._bind_self()`；`scripts/match/view_builder.gd:39` — `var player := {"id": pid, "controller": int(data.get("controller", -1)), "player_name": str(data.get("player_name", "")), "own": own}`；`scripts/main_menu/game_start.gd:62` — `player_data["player_name"] = GameData.default_player_name_pattern % (i + 1)`。 |
| 4 缺字段显示假定零 | **仍成立（限定顶栏可缺省总威力）**：合法缺省 `total_power` 仍在对手顺位卡变为 0；本方面板有构成 total 的优先路径。正式 builder 通常写出总威力，不意味着接收端的合法缺省被禁止；必需资源字段缺失则拒收。 | `scripts/game_scene/battle_board_v2.gd:1270` — `_set_text(card, "Stats/PowerStat/V", BaseNumber.display_text(player.get("total_power", 0)))`；`scripts/match/view_mirror.gd:98` — `if player.has("total_power") and (typeof(player.total_power) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(player.total_power))):`；`:95` — `for key in ["magic", "magic_limit", "score", "lives", "power", "order", "command_spell_count"]:`；`:96` — `if typeof(player.get(key)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(player[key])):`；`scripts/game_scene/battle_io/shared_view_sections.gd:15` — `power.text = BaseNumber.display_text(breakdown.get("total", player.get("total_power", 0)))`；`scripts/match/view_builder.gd:53` — `player["total_power"] = player["power_breakdown"]["total"]`。 |
| 5 旧冻结资源/输入/截图通过项 | **无法静态判定当前动态结果**：四类资源的绑定仍在，但具体刷新数值、motion/down/up 计数、截图观感、Job0 及无引擎错误属于运行证据，不能从源码重建为当前通过。原历史记录保留，不扩展到 ENet 权威结算。 | `scripts/net/ui/v2_view_presenter.gd:222` — `board._bind_rivals()`；`scripts/game_scene/battle_board_v2.gd:1269` — `card.get_node("MagicSigil").set_value(player.get("magic", 0), player.get("magic_limit", 0))`；`:1270` — `_set_text(card, "Stats/PowerStat/V", BaseNumber.display_text(player.get("total_power", 0)))`；`:1271` — `_set_text(card, "Stats/ScoreStat/V", BaseNumber.display_text(player.get("score", 0)))`；`:1272` — `_bind_sigils(card.get_node("Stats/Spells"), int(player.get("command_spell_count", 0)), player.get("special_command_spells", []))`。历史依据 `newtests/round75_order_resources_window_report.md:6` 的快照刷新记录、`:43` 的输入计数 JSON、`:96` 的冻结漂移边界。缺少当前同冻结窗口/输入/进程日志，本轮不补跑。 |
| 6① 常规出牌入口与候选来源 | **仍成立（执行入口区别）**：常规出牌走 RegularPlay，不用 PlayAttack。当前常规出牌可用性部分已从同一组合 preview 读取，不能再描述成完全没有规则接线、只查独立候选。金框整体仍有 6③-金框的额外 OR 分支。 | `scripts/game_scene/battle_board_v2.gd:2881` — `## 已选牌看整组可提交；未选牌只看当前组 preview.candidates，绝不回退独立候选。`；`:2892` — `return bool(preview.get("can_submit", false))`；`:2893` — `for candidate in preview.get("candidates", []):`；`:3133` — `_submit_battle_command("play_group", {"cards": group.get("cards", []).duplicate(), "hidden": group.get("hidden", []).duplicate()})`；`scripts/match/match_seat_query.gd:74` — `var modes: Array = RegularPlay.pending_modes(seat, cards, flags, card)`；`:88` — `return {"ok": true, "candidates": candidates, "can_submit": RegularPlay.can_submit_group(seat, cards, flags), "mana_cost": cost, "remaining_magic": data.magic.number - cost, "power_breakdown": breakdown}`；`scripts/match/match_commands.gd:6` — `return RegularPlay.submit_group(player_id, cards, hidden)`。 |
| 6② 历史负魔力缺陷 / 共享支付要求（附带规则记录） | **已过时（源码仍是两份扣费实现的理解）**：当前两条路径已使用共同 PayMagic 原语、实际支付前复核余额；旧「仍扣到 -1」只保留为历史冻结观察，不能直接套给当前。**是否完整修复不可静态验收**：尚缺当前同冻结费用时点变更、整组回滚、重复续行/无二次扣费的运行结果；此项不作为前端修复或规则验收结案。 | `scripts/system/operations/PayMagic.gd:17` — `func exec(amount:BaseNumber, player_id:int = -1, purpose:String = "", source = null, dispatch_time_points:bool = true, allow_overdraft:bool = false) -> bool:`；`:19` — `if not can_pay(amount, id, null, allow_overdraft):`；`:13` — `var balance:float = d.magic.number if available == null else float(available)`；`:14` — `return is_finite(balance) and is_finite(balance - amount.number) and (allow_overdraft or balance >= amount.number)`；`scripts/system/regular_play.gd:380` — `if not PayMagic.new().exec(BaseNumber.new(paid), id, "regular_play", card, false, state.allow_magic_overdraft):`；`:381` — `_reject_group(state)`；`scripts/system/operations/PlayAttack.gd:61` — `if not PayMagic.new().exec(BaseNumber.new(final_cost), id, "effect_attack", attack, false, allow_magic_overdraft):`。上述是并行任务正在修改的规则文件的读取事实，本轮不改这些文件、不借其静态接线宣称动态通过。 |
| 6③-卡顶控件与明暗操作 | **已过时（把没有旧按钮条等同功能缺失）**：卡顶依然是发动效果按钮/多效果菜单；明暗操作已有规则声明驱动的右键入口，左键选择/撤回、右侧统一确认。旧式「明置/暗置按钮条」字面上不存在，但当前 v2 契约不要求回迁，不应列为当前未实现。翻面结构资格与当前组可提交性分别查询，右键不是对所有牌无条件翻暗，也不是保证翻后的组可提交。 | `assets/scenes/game_scene/battle_board_v2.tscn:5338` — `text = "发动效果"`；`:5345` — `[node name="Effects" type="PopupMenu" parent="Templates/EffectButton" unique_id=205786909]`；`scripts/game_scene/battle_board_v2.gd:2723` — `button.pressed.connect(_on_held_effect_pressed.bind(slot))`；`:2724` — `(button.get_node("Effects") as PopupMenu).id_pressed.connect(_on_held_effect_choice.bind(slot))`；`:2775` — `var available := _held_input_available() and not (slot.get_meta("manual_effects", []) as Array).is_empty()`；`:2734` — `if entry.get("id") == card_id and entry.get("modes", []).has(not concealed):`；`:2735` — `_submit_battle_command("set_concealed", {"card": card_id, "concealed": not concealed})`；`:2758` — `if event.button_index == MOUSE_BUTTON_LEFT:`；`scripts/net/ui/v2_view_presenter.gd:503` — `selection.add(card.id, card.concealed)`；`scripts/game_scene/battle_board_v2.gd:3126` — `return _held_input_available() and _group_preview_ready(group) and bool(group.get("preview", {}).get("can_submit", false))`；`scripts/match/match_seat_query.gd:130-133` — `if card is BaseAttack and RegularPlay.in_play_zone(data, card):` / `return [false, true]` / `if card is BaseSkill and card._is_concealed and card._is_awakened:` / `return [false]`。 |
| 6③-金框混入主动效果 | **仍成立**：本地和网络持有牌使用同一「可出牌 OR 可发动能力」判据；周期更新也保留 OR。金框未严格限定为常规出牌合法性。主动入口本身已有独立效果候选来源，不能把效果存在误称为可出牌。 | `scripts/game_scene/battle_board_v2.gd:2964` — `var actionable := playable or not manual_effects.is_empty()`；`:2982` — `node.set_meta("held_playable", actionable)`；`:2986-2987` — `if actionable:` / `_breathe(node.get_node("Breath"))`；`:2655` — `slot.set_meta("held_playable", _held_card_playable(_meta_or(slot, "card", null), actions, group) or not effects.is_empty())`；`:2666` — `breath.visible = playable and not selected.visible`；`scripts/net/ui/v2_view_presenter.gd:526` — `var usable: bool = board._held_card_playable(card) or not effects.is_empty()`；`scripts/match/match_seat_query.gd:99` — `for effect in EffectManager.manual_activations(seat):`；`scripts/game_scene/battle_board_v2.gd:2869` — `if id <= 0 or seen.has(id) or not card_view.get("effects", []).has(id):`；`scripts/system/global/effect_manager.gd:2047` — `if can_manual_activate(effect, player_id):`；`:2024` — `if !can_pay_effect_cost(effect):`；`:2026` — `return !get_matched_time_points(effect).is_empty()`。 |

**交互要求与历史的区分**：旧卡顶条要求出处 `docs/battle_ui_concept_v2/README.md:26` 原文 `悬浮卡顶只显示规则允许的「明置/暗置」。`；本轮已加载的 `fate-domination-engine/references/ui-implementation-rules.md:20` 明确写「旧 tactical_board 的卡顶明置/暗置按钮不适用于 v2；v2 只保留右键翻面、左键选牌、右侧统一确认，不新增明暗按钮」，`:184` 明确旧版条不回迁。因此是**原交互要求已由当前认可的其它实现方式满足**，不是授权新增按钮。玩家名则分别记录「本方面板满足显示路径」与「顶栏位置未绑定」，不擅自把位置约束改成任意位置均算满足。顺位折叠要求、缺省总威力不猜值要求与纯常规出牌金框要求仍有实现差异，保持记录，不动前端。

**仍无法静态判定**：①第 5 项的当前快照刷新数值、GUI 输入计数、无错误/Job0、正常在场可读性及截图观感；②D15 当前窗口真实点击、拒绝提示可见与网络回执全链（旧 headless/ENet结果不自动升级为当前窗口结果）；③本方面板玩家名的实际可读性/裁切/遮挡（源码有绑定，不等于本轮画面已验）；④6②当前规则变价、整组回滚和重复续行的完整运行正确性；⑤金框/按钮在当前真实窗口中的呼吸、命中与生命周期表现。源码足以判定本表中的节点/绑定/条件分支，不足以替代这些运行证据。

本轮关键前端依据 SHA256（用于识别所读版本，非导出/发行认证）：

- `assets/scenes/game_scene/battle_board_v2.tscn`：`819c08a3db6a88c943849d328dbd0e2bfca0c51bdac9c71f910c89e2451bf512`
- `scripts/game_scene/battle_board_v2.gd`：`1e183b3dda933944a45d7161053554e6477b4f25e0d436bc892c08d21ea620ee`
- `scripts/net/ui/v2_view_presenter.gd`：`81285a188f225449e7bdac8f3f955a8a3c196d83c79152e0888afd98d94d55f6`
- `scripts/game_scene/battle_io/shared_view_sections.gd`：`da6882e21ad24ecd43bc9d52dd8821dd462e281b6634c2fd425e0526ab0295c8`
- `scripts/match/match_seat_query.gd`：`f7688104a9c0f51a998a2c6637a556563fd40e62025cdf8acd92ad9a827718be`
- `scripts/match/view_builder.gd`：`78607bec727a0698e81370e33e988caa0b41def226a04f5e13bd4b8e6567ca8e`
- `scripts/match/view_mirror.gd`：`8007a3cc6e2e1ed0bb319ba3e1b3bd21fb825e7b9bc24f3f212a724c514eef20`

## 执行中可自行处理的事项

- 原生冷导入故障继续自行排查：保留Round39/40崩溃位置原件；按最新Q03保持引擎不变，重新核对项目启动、扩展构建/初始化契约及最小因果对照。禁止修改宿主、删除原生能力或拿暖缓存重试冒冷导入通过；历史报告不作为停止调查的理由。

- 方案提供的整文件 `git checkout` 回退可能覆盖用户未提交修改，因此不采用；仅回退本轮精确补丁。
- 性能探针并发测量存在资源竞争，主代理在依赖完成后独占复测，不需要用户决策。

各子代理报告中的疑问由主代理核查后合并到本文；报告中的疑问不自动视为规则变更授权。

## 技术缺口：继续自行核查，不向用户逐项询问

- B 整合窗口战区套件出现部署、快照及移动目标三失败；先冻结复现确定根因，不先更改规则。
- 自然终局联机额外日志窗按已批准 D2 删除；另外 8 条效果执行脚本错误独立追踪。
- net_validation_task 默认目录/缓存根被安全检查拒绝，优先纠正测试批准根与启动参数；不得以放宽生产目录门解决。
- net_recovery_state 脚本错误及超时优先追认证与恢复夹具契约；如需变更规则政策再升格为待确认事项。
- G03 外部 batch51 的 AST 单函数提取测试出现 NameError: os，G04 迁移打包入口时需要更新其真实调用契约；尚未构建发行包。
- 新增 tests 与 reports 被现有 Git 忽略，当前只保证文件已落盘；未暂存或提交，不将子代理建议的 force-add 当用户授权。
- 第八轮 D16 暂以独立动作候选代替组合候选，尚不满足金框与真实出牌合法性一致的既定要求；第九轮复用现有 preview 契约纠正，不把这一偏差当作需要重新决定规则的问题。
- D14 close/reconnect 后旧 pending 悬挂与 seq 复用已通过显式 RED 模式复现；第九轮由 session 唯一写入者补公共请求关联失效通知，复用适配器 close 的“执行结果未知”语义，不自动重发。
- E15 真实采用前置仍红，恢复单项通过不代表准备/采用全链通过；继续核对目录、身份及依赖契约，不放宽安全门。
- 消息 serial 必须不进入规则哈希、不随事务回滚回退；第九轮只落地 E01 基础，权威 epoch、重连基线与提示撤回尚未完成。通知队列实际有界性未获证明，不加固定截断以冒充不漏提示。
- 发行审计已复现不存在包、空包误通过及 `.import` 集合与真实复制器不一致；第九轮修准入与显式工程来源，尚未构建发行包。
- 第九轮 E15 在独占物理用户目录下通过，但默认 `user://` 指向链接目录仍被现有安全门拒绝；这是环境与批准根契约问题，暂不放宽链接策略。是否允许这类用户目录仅在确有政策变更需要时统一提问。
- 第九轮窗口 BUFF/返回失败含未关闭描述层、按钮实际不可见、稀疏 session.view 缺 settings 与转场后已释放节点访问；先修真实夹具/输入路径与生产根因，不将三项失败归为无关而跳过。
- 第九轮新增专项引入三处私有访问，当前闸门红；第十轮要求消除新增且退休旧许可，不能扩白名单或反射规避。
- 回滚测试宿主若进入规则对象图，checks/failures 会被回滚吞掉；发现日志 CHECK false 与 RESULT failures=[] 矛盾，相关绿结果需负向复核，不按退出 0 单独计绿。
- 自动清理当前已接配置、可信台账和只读调度，但缺真实跨进程排他及完整实例登记能力，生产明确blocked不删除。后续优先完成真人测试包主链；不以“用户允许自动清理”解释为可以伪造exclusive_files证明。原生协调能力实现或受限部署契约需进一步明确时再集中询问，暂不默认放宽安全要求。
- 长回放正确性与性能分开：主代理对旧稳定冻结执行完整141动作加两次恢复，238.968秒全部hash/终局检查通过；原180秒性能门仍未过。该结果不覆盖最终当前源码，最终冻结须重新验；不再把维护截止取消直接称作恢复功能错误。
- Round38目录发布：6套1976项冻结复验通过，但Round34原生rename FAILED=1的历史占锁者仍未确认。受控自有/外部文件锁能产生同症状，枚举句柄存活不必然阻止rename；不能据成功复跑称根治，不能猜杀毒软件或自动加重试。若新现场再现，需记录该次Win32错误和绑定实例；确需有界重试才另提具体政策。
- Round37特殊令咒中断任务由主代理接管，撤回未授权的“所有声明卡自动登记效果”生产补丁，保留现有仅主令咒绑定口径。多卡布局/持有测试改用既有克隆及登记原语：13项headless状态、25项非headless鼠标、54项发动回归通过。headless鼠标展开仍不能当窗口输入验收，不跳断言假通过。
