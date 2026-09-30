# 项目 bug 审计（静态 + 运行时）

用户说「分析一下项目的 bug」「审查一遍」时按这个顺序做，交付的是**分档清单**，不是逐条流水账。
每条结论都要能指到 `文件:行号` 或探针实测值；**没复现的只能写「疑似」，并写清缺什么证据**。

## 1. 先定范围

    git show --stat HEAD

引擎侧看 `assets/scripts/system/**`，数据看 `data/**`；`addons/godot_ai/**` 是 MCP 插件，不属于业务代码，跳过。最近一个提交改过的文件就是重点。

## 2. 全量卡图核对时先建立覆盖清单

1. 沿实际加载入口枚举 JSON 对象，给每项保存稳定 ID、类别、JSON 路径及对象位置、实际图片路径；分别标记实际进入牌库/技能区的卡、仅加载缓存的模板、重复展示实例与皮肤。按用户指定范围排除升华技等对象，不用目录总数代替游戏使用范围。
2. 按真实图片路径去重后分批看图，把每批结果追加到 JSON/CSV，再映射回所有清单项。分别统计条目数、不同图片数、已看图数与缺失图片；同名不同版本不能靠名字合并。
3. 对牌名、费用、威力、属性、类别、词条及效果逐项比对数据；图标或版本不确定时回到原图和权威素材确认，不把视觉工具的猜测当规则证据。
4. 单独记录效果语义覆盖：继续追踪 JSON 参数、operation、时点、克隆与真实 UI/AI 入口。**图片全部看过不等于所有效果已验证**；原语测试通过也不等于入口接线完成。
5. 交付时区分卡图覆盖、静态调用链覆盖和运行覆盖，列出未核实项。不要把 `do_nothing` 搜索命中全部判成缺功能，先检查该规则是否由结构化字段或其他入口承担。

## 3. 静态读一圈（按这个优先级，不要从 UI 开始）

1. `global/` 的管理器：`effect_manager.gd`、`game_progress.gd`、`time_point_checker.gd`、`load_game.gd`、`load_helper.gd`、`battle_resolver.gd`、各 resolver（event / situation / climax / victory）。
2. 被 JSON 高频调用的搬运/改写类 operation：`PlayAttack`、`PlaySkill`、`DrawCardByCard`、`DrawCardByIndex`、`DrawCardFromPlDeckToHand`、`DiscardPlayedCards`、`SyncPower`、`SetCardConcealed`、`CardCountsPower`、`Move`、`MoveLocation`、`SetLocation`、`Deploy`、`CloseCard`、`AddSkillToSkillZone`。
3. `base_*.gd` 与 `CloneObject.gd` **成对读**（字段漏克隆是本项目第一大类 bug）。
4. UI 控制器只读入口：`_ready()` 的开局链、`_process()` 的节流刷新与 AI 步进、点击回调、弹窗提交函数。

## 4. 运行时基线（先跑一次，不改状态）

`project_run(mode="main")` 后单次 `game_eval` 数一遍实例，再 `GameStart.game_start([0,1,2,3,4,5,6])` 数第二遍：

    var out = {}
    out["attack_datas"] = LoadAttack._attack_datas.size()
    out["events"] = LoadEvent.events.size()
    out["masters"] = GameData.loaded_masters.size()
    out["servants"] = GameData.loaded_servants.size()
    out["objects"] = GameData.objects.size()
    out["effects"] = GameData.effects.size()
    out["pool"] = EffectManager.effect_pool.size()

按 `o is BaseAttack / BaseEvent / BaseSituation / BaseEffect` 分段计数。已知基线见 SKILL.md「验证」一节；`BaseEvent`/`BaseSituation` 记得算上牌堆克隆那一段。
各玩家 `deck` / `servant_skills` 的实际条数随数据迭代会漂移（SKILL.md 里的「每人 9」是快照），**以当次 JSON 的 `specials.ATTACKS` 长度为准**，别拿旧快照当 bug。

## 5. 候选 bug 的常见类型（逐类 grep，别靠记忆）

- **先删后校验 / 只删不加**：`grep -n "pop_at\|erase(" operations/*.gd`，看下标校验是不是在移除之后。
- **空引用**：遍历 `MapData.areas` 找归属的代码、`player_data["location"]`、`get_node_or_null` 的静默 null。
- **参数语义错配**：所有 `Xxx.new().exec(` 的转发型 operation，逐位对形参名（`Deploy` → `SetLocation` 是一例）。
- **写死的规则/身份/下标**：`_local_player_id`、`preferred_areas := [1, 2, 0]` 这类下标数组、`curr_id > 0`。
- **字段漏克隆**：`base_*.gd` 的 `var _xxx` 与 `CloneObject._clone_*` 逐字段对照。
- **UI 静默失败**：`queue_free()` 回收卡位、`connect(func.bind(obj))`、`has_meta` 缺守卫、同一 metadata 键既当配置又当幂等标记、`clip_contents` 漏设。
- **一次性状态**：用资源数值反推「第一次」、`used_once_effects` 漏记名。
- **按卡面逐类扫 JSON 声明**（比读引擎更快出结果）：① 卡上的「XX阶段：」能力如果没用「单选项 + max_total_uses:1 + reset_counts_each_round」，同一回合可以反复发动（`max_total_uses` 只在有 options 时才加载）；② 技能牌上的 `is_pure_passive` 效果没写 `need_activate:true`，牌留在技能区也会生效（残留/打出时/无前缀文本都属于这一类）；③ 挂上时 `is_active:false` 的 buff，效果照样结算（要核对 `card_state_allows` 有没有检查 `_is_active`）；④ 卡面写“本回合/此攻击”的加成用了 `edit_card_power`，回合结束后不会还原；⑤ 按回合公式计算的费用可能变成负数，要逐个出牌入口核对是否下限取 0。
- **占位**：数据里还剩多少条只有 `do_nothing` 的选项/效果（这些是「未实现」，要和 bug 分开报）。

## 6. 每个候选都要用探针复现；复现不了就明确标注未复现

- 把新增缺陷审计与修复回归分开：审计逐项输出 `reproduced` / `not_reproduced` / `error`、期望值、实际值及前置条件。探针自身报错或没执行不能记成“未复现”；发现预期中的业务缺陷也不能冒充回归通过。
- 对“重复结算”验证完整生命周期和精确次数：局势进场后继续放置、翻开事件，再检查原局势效果次数和各区准确牌数；只断言数量增加会漏掉重复触发。补同名不同实例的对照，避免按名字去重掩盖来源错误。
- 对“连续使用”不在两次操作之间重置管线、补时点或重建效果对象；这些准备动作会恰好清掉故障状态。分别验证真实入口、取消后重试、资源耗尽、窗口关闭与换玩家。
- 对“真名公开”分别断言权威状态、真实技能实例及 UI 展示。先经实际常规出牌入口触发，再检查 release/hidden 最后记录；用技能区为空、技能已明置但尚未解放作反例，不能靠技能数组猜概览可见性。普通暗置攻击的费用、激活、计入威力与所在区域必须保持不变。
- 对“一次性效果”用连续状态序列验证：先令条件不满足并经过真实效果管线，再令条件满足尝试使用；同时用未经过失败检查的新鲜实例作正例对照。只直接调用末端 operation 会绕开无条件效果日志，漏掉失败检查提前消耗一次资格的问题。


只读/可控改状态的复现模板（单次 `game_eval`）：

    # 「静默挪走/丢牌」类：先记前后数量，再断言对象还在不在任一数组里
    var pd = GameDataManager.get_player_data(6)
    var deck = pd["deck"]
    var hand = pd["hand_cards"]
    var card = deck[0]
    var d0 = deck.size()
    DrawCardByCard.new().exec(card, deck, hand, BaseNumber.new(999))
    return {"deck_before": d0, "deck_after": deck.size(),
            "card_in_deck": deck.has(card), "card_in_hand": hand.has(card)}

- **会抛运行时错误的探针单独发一条 `game_eval`**（抛错会中断后面的语句），返回的错误原文就是证据，直接抄进报告。
- 探针污染过状态后要么当场还原，要么 `project_manage(op="stop")` 重跑，别在污染的状态上继续判定。
- 模拟整条流程用循环推进（`end_current_player_action()` + 遇 `waiting_effect` 就 `submit_active_choice(eff, false)`），**每一步都 append 到日志数组**再去读统计，否则会误读循环进度。

## 独立命令行探针

**优先用临时测试场景**：在 `tests/` 下写 `zz_*_probe.gd` + `.tscn`（`extends Node`，写法同现有套件，可直接用 autoload 标识符），用 `--headless --fixed-fps 60 --scene` 跑，验完删除 `.gd/.tscn/.uid`。实测 `--script` 方式会因 `base_object.gd` 等业务脚本引用 `GameData` 而编译失败（Identifier not found），然后卡住直到超时。

只在不需要加载业务类时，才在系统临时目录写 `extends SceneTree` 的 GDScript，通过 Godot `--headless --path <项目> --script <临时脚本>` 执行。`_initialize()` 用 `call_deferred` 调探针入口，入口以 `root.get_node("GameData")` 等方式取得 autoload；不要在外部启动脚本直接使用 autoload 标识符，否则可能在编译阶段报 Identifier not found。operation 用真实资源路径 `load(...).new()` 调用，结束时 `quit()`，同时检查标准输出中的 SCRIPT ERROR，不能只看进程退出码：业务脚本报错后调用者仍可能继续执行且退出码为 0。临时文件验完删除。

对子代理结果逐条复核前置条件与现有守卫；例如 `MoveLocation` 已提前排除满员位置，不能把“目标满员仍收费”直接认定为已复现，应另找能通过前置筛选但被 `SetLocation` 拒绝的状态。

## 7. 交付形态

分三档，每条写「`文件:行号` → 现象 → 机制 → 建议修法」；修法优先「用现有原语组合」，其次才是新增单一职责 operation，并说明为什么否掉别的方案。

1. **已复现的缺陷**（附探针实测值：前后数量、返回值、错误原文）。
2. **静态可判、未复现**（写明缺什么证据、怎么才能复现）。
3. **未实现 / 占位**（`do_nothing`、缺 `func_name`），与 bug 分开列，不要混为一谈。

最后补一段「这次没覆盖到的部分」（哪个阶段、哪个角色、哪条时点没跑到），避免用户以为已全量审过。
