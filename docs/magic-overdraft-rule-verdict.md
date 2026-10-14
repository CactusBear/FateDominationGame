# 常规出牌负魔力：规则声明与真实 Godot 诊断

## 判定

**报为疑似缺陷，不是有声明依据的“允许透支”设计。**

在当前仓库可读数据/规则声明与基础规则文档中，未找到允许魔力透支、负魔力、借贷魔力的显式例外。反而有明确的 0 到上限资源声明。真实 Godot 再次复现：魔力 2、事件把费用 2 改为 3 时，`RegularPlay.submit_group` 成功、两张牌入场、魔力变为 -1；`PlayAttack` 拒绝，魔力保留 2、牌不入场。

这是诊断结论，不是已修复或产品验收通过。未改生产、未删现有断言。费用 +1 是专项显式声明的测试效果，不冒称已证实某张正式卡数据在可达对局中一定触发同样的 -1。

## 1. 声明证据

### 基础规则原文

文件：`E:/Users/Administrator/Downloads/Fate_Domination 基础规则【墨水修订1版】.docx`。

- 「魔力标记」：**“每个玩家通常拥有从 0 到 12 的魔力值。”**
- 「常规出牌」：**“然后，同时花费这些牌的魔力消耗，你无法同时打出超过你魔力上限消耗的攻击”**；紧接着解释分段花费可以先回复魔力再使用其他效果、免费打出的例外。不等于允许当前支付超出余额，也没有允许负魔力的文字。
- 暗置说明：**“暗置牌处于未被激活的状态，它们不消耗魔力”**。免费模式不同于付费透支。

### 规则脚本显式声明及执行

- `scripts/system/operations/EditMagic.gd:25-33`：原注释 **“规则：魔力是 0 到上限之间的资源（上限本身是数据、效果可以改）。”**；实际按 `GameData.player_magic_limit(id)` 夹上限，并把小于 0 的值设为 0。本专项真实调用也确认了 0 下限、全局 12 上限、玩家覆盖 16 上限。
- `scripts/system/global/game_data.gd:9-12,88-100,129-139`：技能区门槛为可变数据 8，魔力全局上限为可变数据 12；玩家 `magic_limit` 覆盖缺省 null，`is_magic_immune`、`ignore_skill_zone_magic_limit` 是独立例外开关；未声明魔力借贷/负数许可。`score_min` 的声明属于战果，不能挪作魔力规则。
- `RegularPlay.faceup_allowed:104-112`：普通明置费用须不高于 `min(当前魔力, 玩家魔力上限)`；`_mode_basic:119` 还检查待选组剩余魔力。说明常规路径预检本来就不允许不够钱，事件后漏检不能当成有意规则。
- `PlayAttack.gd:55-67`：费用事件后重算费用，魔力不足返回 false，支付发生在该门之后。
- `BaseNumber.minus:45-50`：通用数值对象只做减法，无资源夹限。通用数值可以是负值，不是魔力透支的授权。

### 数据/费用 JSON 搜索范围与例外

`docs/magic-overdraft-declaration-scan.json` 保存搜索模式、逐文件 SHA256 和命中位置：

- `data/**` 全部 **71 个 JSON**；另读 `json_maker/**` **2 个 JSON**，合计 **73**，解析错误 **0**；`game_data/**` 无 JSON。
- `scripts/system/**` **276 个 GDScript** 全文搜索；基础规则 DOCX 全部段落搜索。
- 透支/负魔力/魔力借贷/允许负资源类显式声明命中 **0**；声明为负数的卡牌 `cost.number` **0**。此为有边界的文本/结构搜索，不把“未命中”夸大为任意外部规则或卡面图片的穷尽证明。
- `data/**` 其余文件为 PNG 与 `.import`；本次没有做卡图 OCR，也不使用卡图猜测规则。
- 樱 `data/masters/00004_matou_sakura/00004_matou_sakura.json:470-478,614-615` 的例外是 `is_magic_immune=true` 和 **“你拥有无限魔力（此状态下无法获得或失去魔力）”**。两个入口均对此不扣费，不是扣成负数的声明；本专项明确未开启免疫。
- 风王结界 `data/servants/00001_artoria_pendragon/00001_artoria_pendragon.json:345-397` 声明真名隐藏减费，监听 `self_card_cost_calculated` 并设置费用；美狄亚 `00005_medea.json:30-100` 声明 **“此牌费用为X，X为16-（当前回合数×2）”** 并在同一时点改费。库丘林 `00003_cu_chulainn.json:340` 存在 `edit_card_cost` 调用。费用可改变不等于支付可以透支，负费用公式也不等于负资源许可。
- JSON 声明扫描指纹与本次运行冻结源逐文件一致，漂移 **0**。

## 2. 组提交为什么未拦住

正式命令 `MatchCommandDispatcher:187-201` 将 `play_group` 经规则桥调用 `submit_group`，并靠其布尔返回决定拒绝。它不调用 `PlayAttack`。

`RegularPlay.submit_group:304-322`：

1. 调用 `can_submit_group`（239-267），用**事件前**费用逐张预减预算，检查当前余额/上限、牌区、明暗、数量等。
2. 成功后记录 `regular_play_start`，预结算同批真名解放，再进入 `_resume_group`。
3. `_resume_group` 的 `cost` 阶段（335-341）派发真实 `CARD_COST_CALCULATED`，费用效果可修改 `_cost`。
4. `enter` 阶段（342-355）重新读取**事件后** `cost(card,d)`，但**没有再次检查余额、玩家上限或整组最终预算**，直接 `d.magic.minus(...)`；不经过 `EditMagic` 的资源夹限。随后激活、移出来源、入场、写日志。
5. `submit_group` 返回 true；完成游标还记录 `regular_play`。`_resume_group` 返回 void，当前也没有把“事件后支付失败”传播到调用方的合同。

因此这是典型的“预检价格与支付价格不同”漏门，而不是开始就允许透支。双牌专项还证明：仅最后拒绝第二张而不做事务恢复，会留下第一张已付费/入场；必须保留整组原子性。

对照 `PlayAttack` 是**显式特殊单卡入口**；本次用 `ignore_limit=true, activating_eff=null` 才能到达支付门，仍保留阶段/行动者门。不把其默认调用或单卡结果当常规整组规则。它派发费用事件后先检查 `pl_magic < final_cost`，所以拒绝本次涨价后的短款。它不独立检查玩家魔力上限，不能替代常规整组上限合同。

## 3. 真实小专项观测

常规路径维持基础规则两张整组，第一张被测攻击、第二张零费支持；双牌溢出用两张均有费用攻击。费用变化通过真实 `BaseEffect` / `SELF_CARD_COST_CALCULATED` / `LoadHelper.load_funcs` / `EditCardCost` 执行，不用 Python 重写规则。

| 类别 | 初始魔力 / 上限 | 费用变化 | 常规整组 | PlayAttack 特殊单卡 |
|---|---:|---:|---|---|
| 静态恰好 | 2 / 12 | 2 | 成功，余量 0，入场 2 张 | 成功，余量 0，入场 1 张 |
| 静态差一点 | 1 / 12 | 2 | 拒绝，余量 1，入场 0 | 拒绝，余量 1，入场 0 |
| 静态超上限 | 12 / 12 | 13 | 拒绝，余量 12，入场 0 | 拒绝，余量 12，入场 0 |
| 事件后恰好 | 3 / 12 | 2→3 | 成功，余量 0，入场 2 | 成功，余量 0，入场 1 |
| 事件后差一点 | 2 / 12 | 2→3 | **成功，余量 -1，入场 2，流程已完成** | **拒绝，余量 2，入场 0** |
| 事件后超上限 | 12 / 12 | 12→13 | **成功，余量 -1，入场 2** | 拒绝，余量 12，入场 0 |
| 双牌合计超上限 | 12 / 12 | 两张各 6→7 | **成功，实际合计 14，余量 -2，入场 2** | 单卡付 7 成功，余量 5；不是整组对照 |
| 注入超上限余额的额外合同探针 | 20 / 1 | 2 | 拒绝，余量 20，入场 0 | 成功，余量 18，入场 1 |

最后一行是显式注入的非常规状态，用来隔离两个入口的 cap 合同差别；不声称规则允许“20/1”，也不用于证明常规对局的负魔力缺陷。正常余额不超过 cap 时，静态“超 cap”同时也是余额不足，须与此合同探针区分。

### 执行回执

命令：`python -B newtests/run_magic_overdraft_declaration.py --label focused-01`。

引擎真实 argv：独占物理 E 引擎副本，`--headless --fixed-fps 60 --path <E冻结工程> --scene res://newtests/magic_overdraft_declaration_test.tscn`。每个进程 600 秒看门狗；主/派生 user-dir 探针均读回物理 E 路径；未动 PID 17120/28100，没有全量、测速或窗口。

- 专项 **CHECK=148**，实际日志计数同为 **148**，失败 CHECK **0**；唯一 `RESULT magic_overdraft_declaration checks=148 failures=[]`。
- 专项 Godot **exit=0**；探针与导入也均 **exit=0**。
- 所有探针/导入/专项日志合计 **ERROR/SCRIPT ERROR/SHADER ERROR=0，WARNING=0**。
- 三个已启动自有 Job 记录均 `active_owned_processes=0`（**Job0**）、`exited=true`、日志句柄释放；派生 worker 探针回执已核验。
- 冻结树漂移 `{}`，证据摘要读回 true，自有 generated 树已按所有权删除。
- **顶层 runner exit=1**：运行期间其他写入者改动 `scripts/system/global/effect_manager.gd`，源指纹由 `1755ff077e675105844d3d6ec33645bc3f701a48aa1cdf8dc2b11c8a6b5340c1` 变为 `4af166bd7d5f71732af924d963ab4f632840917742ae2e68a308b623756e20d3`。没有错误放行；上述 CHECK 只证明该冻结版本的诊断，不宣称当前活工程一致性门通过。不争用热文件重复复制，交主代理等写者冻结后复验。

manifest：`E:/scratch/magic-overdraft-declaration-focused-01/isolated-0bf332d1ddf7476cada0064814bd2f7c/manifest.json`。

精简机器证据：`docs/magic-overdraft-runtime-evidence.json`，包含 16 条真实两路径记录、argv、退出码、Job0、日志错误数、关键冻结源码 hash、声明扫描与冻结对照。

## 4. 最小修法候选（不实施）

1. 在 `_resume_group` 的 `enter` 扣费前，基于**事件后的真实费用和当前资源**再检查支付能力；尊重已有 `is_magic_immune` 与暗置免费例外，复用既有费用计算原语。费用须不超过当前余额和声明上限。
2. 维护这次同批的实际累计付费预算，保证不突破声明的同时支付 cap；不把单卡门当整组门，也不自行补充新的透支/最低魔力政策。
3. 组开始任何副作用（start 日志、真名解放、费用事件、入场）前取得可用的完整规则/效果检查点；任一最终支付失败，恢复整组魔力、来源/入场、激活状态、费用变化、日志及效果/continuation 状态，而不是只退第二张牌或补几项数值。`scripts/match/effect_checkpoint.gd:34-61,63-95` 已有完整规则/随机/事务捕获恢复设施，但它是效果上下文合同；如何接入整组需要主写者验证，不能盲目调用 `.new(null)` 或假称现成可用。
4. 让失败传播至 `submit_group` 和命令桥；当前 `return true` 与延迟 continuation 需要显式结果合同，不能只在 void 恢复函数加一个 `return`。无法取得完整检查点时失败关闭，不冒充回滚成功。
5. **不把魔力 clamp 到 0 当修复**：它会让无力支付的牌免费入场，仍违背支付规则；也不在只读 UI 查询中派发费用事件，不重排现有同时出牌时点作未经确认的规则变更。

若用户另有允许透支的规则版本，必须先提供并加入明确数据/统一契约后再讨论例外。本次没有这类依据，因此不能把 -1 解释成设计如此。

## 产物与边界

新增：`newtests/magic_overdraft_declaration_test.gd`、同名 `.tscn`、`newtests/run_magic_overdraft_declaration.py`、`newtests/scan_magic_overdraft_declarations.py`；`docs/magic-overdraft-declaration-scan.json`、`docs/magic-overdraft-runtime-evidence.json`、本报告。

只写本人新增测试/报告；生产 GD/JSON/现有测试未修改。本次覆盖规则声明、受控费用事件与小集合真实执行，不覆盖正式卡牌全部可达组合、生产 UI、联机端到端或全量回归；并行源码漂移的活树复验由主代理串行排队。
