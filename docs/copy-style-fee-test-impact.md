# 单独资源标签改动：现有测试与 golden 真实影响

## 结论

- 原轮整体未通过：match_view 外部看门狗截断，refactor_text_golden / reported_ui 未运行。后续仅 match_view 隔离实测 35.084s、按声明重跑 35.669s，真实 RESULT226、exit0、ERROR0、Job0；详见 [match-view-budget-measurement.md](match-view-budget-measurement.md)。后续只改有限测试预算，生产/前端/业务断言/golden 未改；旧轮记录不覆写。
- 三个已通过套件只绑定本次独立冻结。运行结束时原工作树有四个引擎文件漂移；不是冻结执行时混用源文件，也不能升级成最新工作树通过。
- 公开说明改动范围：`view_builder.gd:355,379` 的 `own=false` 分支进入 `public_description():407`。本人说明仍走 `CardDescText.card_desc()`，`FIELD_LABELS._cost` 原本就是「魔力消耗」。
- `refactor_text_golden_test.gd:6` 真正读取 `docs/refactoring-golden/text.json`；其 `collect_text():52` 使用旧本地完整 formatter，不经过本次公开说明分支。
- 完整静态逐条列表（文件:行、原文、分类）见同名 JSON；超长历史快照行列出逐个资源原文，完整原始行留在批准 E scratch 索引。

## 实跑（同一独立 E 冻结）

|套件|CHECK|false|exit|ERROR|Job active|判定|
|---|---:|---:|---:|---:|---:|---|
|`newtests/round74_public_battle_text_test.tscn`|19|0|0|0|0|PASS|
|`tests/match_view_privacy_test.tscn`|137|0|0|0|0|PASS|
|`newtests/current_card_info_ui_contract_test.tscn`|6269|0|0|0|0|PASS|
|`tests/match_view_test.tscn`|1209|0|125|0|0|FAIL（停止）|
|`tests/refactor_text_golden_test.tscn`|—|—|—|—|—|NOT_RUN（首红后停止）|
|`tests/reported_ui_test.tscn`|—|—|—|—|—|NOT_RUN（首红后停止）|

所有原始 RESULT：
```text
RESULT {"checks":19,"failures":[],"passed":true,"test":"round74_public_battle_text"}
RESULT checks=137 failures=[]
RESULT current_card_info_ui_contract checks=6269 failures=[]
```

冻结、命令、进程 PID、真实退出码、物理 user:// 探针和 source SHA 清单：`E:\Caches\Hermes\cache\scratch\fee-label-verification\isolated-557128e9f8714a01a68f224b5f8d72c5\manifest.json`。
外部看门狗每进程 600s；标准 argv `--headless --fixed-fps 60 --path <独立副本> --scene res://<套件>`。所有 TMPDIR/TEMP/TMP 指 E；未操作保护 PID 17120/28100。隔离副本只关闭编辑器 VCS 自动启动；原工程配置未动。

## 逐条资源标签断言与场景文字

### `tests/board_requested_ui_test.gd:108`
```gdscript
		check(preview.get_node("Box/Cost").text == "魔力消耗 3", "preview reuses discounted regular-play cost")
```
不应受影响：复合词/诊断标签/注释/其他资源生产者

### `tests/board_requested_ui_test.gd:121`
```gdscript
		check(preview.get_node("Box/Cost").text == "魔力消耗 0", "mana immunity has zero preview cost")
```
不应受影响：复合词/诊断标签/注释/其他资源生产者

### `tests/json_maker_tutorial_test.gd:109`
```gdscript
	# 「取最大」保持默认不写出 true：学员不动它时「取魔力消耗最大的」也要能过
```
不应受影响：复合词/诊断标签/注释/其他资源生产者

### `tests/json_maker_tutorial_test.gd:121`
```gdscript
		if str(c.text) == "取魔力消耗最大的":
```
不应受影响：复合词/诊断标签/注释/其他资源生产者

### `tests/json_maker_tutorial_test.gd:233`
```gdscript
			if (edit as LineEdit).text == "本回合未打出魔力消耗最高的宝具攻击":
```
不应受影响：复合词/诊断标签/注释/其他资源生产者

### `tests/json_maker_tutorial_test.gd:244`
```gdscript
				if (edit as LineEdit).text == "本回合未打出魔力消耗最高的宝具攻击":
```
不应受影响：复合词/诊断标签/注释/其他资源生产者

### `tests/native_choices_window_test.gd:99`
```gdscript
	return {"kind":"active_choice","effect":10,"label":"原生效果","allow_cancel":cancel,"options":options,"multi":multi,"cost_text":"魔力消耗 2"}
```
不应受影响：复合词/诊断标签/注释/其他资源生产者

### `tests/native_choices_window_test.gd:114`
```gdscript
	check(board._effect_modal.get_node("Box/Desc").text.contains("魔力消耗 2"),"authoritative cost line")
```
不应受影响：复合词/诊断标签/注释/其他资源生产者

### `tests/net_v2_hand_window_test.gd:130`
```gdscript
		check(str(played_slot.get_meta("zoom_desc", "")).contains("魔力消耗：2"), "network card uses full authoritative card description")
```
不应受影响：本人卡牌完整说明断言（own=true，既已期望新标签）

### `tests/net_v2_ui_input_parity_window_test.gd:150`
```gdscript
	check(board.get_node("ManaCostPreview/Box/Cost").text == "魔力消耗 4", "native cost float displays authority cost without decimal zero")
```
不应受影响：复合词/诊断标签/注释/其他资源生产者

### `tests/net_v2_ui_input_parity_window_test.gd:205`
```gdscript
		check(str(played_slot.get_meta("zoom_desc", "")).contains("魔力消耗：2"), "network card uses full authoritative card description")
```
不应受影响：本人卡牌完整说明断言（own=true，既已期望新标签）

### `tests/net_v2_ui_parity_remaining_red_window_test.gd:124`
```gdscript
	check(board.get_node("ManaCostPreview/Box/Cost").text == "魔力消耗 4", "native cost float displays authority cost without decimal zero")
```
不应受影响：复合词/诊断标签/注释/其他资源生产者

### `tests/net_v2_ui_parity_remaining_red_window_test.gd:175`
```gdscript
		check(str(played_slot.get_meta("zoom_desc", "")).contains("魔力消耗：2"), "network card uses full authoritative card description")
```
不应受影响：本人卡牌完整说明断言（own=true，既已期望新标签）

### `tests/refactor_group_projection_test.gd:59`
```gdscript
	check(ui.get_node("ManaCostPreview/Box/Cost").text == "魔力消耗 7.5", "费用直接消费预览真实小数")
```
不应受影响：复合词/诊断标签/注释/其他资源生产者

### `tests/reported_ui_test.gd:408`
```gdscript
	check(ui.tactical_confirm_modal.visible and mod_desc != null and mod_desc.text.contains("魔力消耗"), "clicking the modification badge opens the change detail")
```
不应受影响：复合词/诊断标签/注释/其他资源生产者

### `tests/self_power_single_render_test.gd:104`
```gdscript
	check(ui.get_node("ManaCostPreview/Box/Cost").text == "魔力消耗 4" and ui.get_node("ManaCostPreview/Box/Remaining").text == "剩余魔力 6", "network实际费用浮窗4与6")
```
不应受影响：复合词/诊断标签/注释/其他资源生产者

### `tests/zoom_and_desc_test.gd:143`
```gdscript
	check(desc_text.contains("魔力消耗"), "description lists magic cost")
```
不应受影响：复合词/诊断标签/注释/其他资源生产者

### `assets/scenes/debug/debug_console.tscn:353`
```text
text = "改卡牌费用"
```
不应受影响：独立场景资源标签 / 保留的复合词 / 调试文案。

### `assets/scenes/game_scene/battle_board_v2.tscn:1490`
```text
text = "移动路线 · 魔力消耗"
```
不应受影响：独立场景资源标签 / 保留的复合词 / 调试文案。

### `assets/scenes/game_scene/battle_board_v2.tscn:1511`
```text
text = "悬浮右侧竖条切换主图 · 令咒可代替移动费用"
```
不应受影响：独立场景资源标签 / 保留的复合词 / 调试文案。

## 动态期望入口（不含标签字面量，补充沿调用链定位）

`newtests/current_card_info_ui_contract_test.gd:51`：`require_item(desc == text.card_desc(card), card, "builder description exact formatter")`。
`newtests/current_card_info_ui_contract_test.gd:55`：`var expected: String = text.FIELD_LABELS[prop] + "：" + BaseNumber.display_text(value.number)`。
`newtests/current_card_info_ui_contract_test.gd:56`：`require_item(desc.contains(expected), card, "number " + prop, expected)`。
三项均为 `card_view(card,true)` 的本人说明契约，不应受此次 own=false 公开说明标签影响；既有 contains 保持原样，未作放宽。
`tests/refactor_text_golden_test.gd:52`：`row["text"] = Text._build_card_desc(obj)`；`:131`：`check(compare(expected, actual, "$"), "golden matches exactly")`。完全精确比较仍保留，不应受影响。
`tests/match_view_privacy_test.gd:105-108`：真实调用 public 说明，但其五个正例词为公开卡面说明、公开效果说明、公开选项、公开打出条件、力量；没有资源标签 literal golden，均不应受影响。

## golden / 历史报告分类

- 现有可执行 golden/断言未发现旧 `费用：` 标签；不需要任何 golden 文本替换。
- `docs/refactoring-golden/text.json` 的 960 行资源说明已经期望 `魔力消耗：`，全部文件:行与完整原文已在 JSON 逐行列出；不可因其他数值/步骤/日志差异刷新此 golden。
- `reports/refactoring/` 的 32 个旧 `费用：` 命中行是已冻结的历史日志/恢复快照，不是本轮测试读取的 golden，不改写历史证据。完整列表见 JSON（按 `category` 过滤历史）。
- 其他含「费用」的复合词、检查标签、注释、规则/数据副本全部判定不应受影响，逐条原文亦在 JSON。

## 首红 / 阻断与未验边界

套件 `tests/match_view_test.tscn`：
```text
```
该结果没有授权修改非相关期望；按用户要求停下。
执行阻断：`SafetyError('timeout')`。最小观测因果：外部 600s 看门狗触发 owned Job 终止，Godot 最终 exit125；602.768s 完成回收，最后输出 `CHECK loopback step 1119 true`，1209 CHECK 全真且 ERROR=0，但无 RESULT / 未证明自然终局。不得从这个截断记录推定文案导致停滞或声称预存问题。诊断 launcher 实际 exit0 只是异常分支未显式退出非零，不是套件通过；整体按真实 Godot exit125 和缺 RESULT 拒绝。
- 本次只验证 headless。未验真实窗口可视/鼠标、OCR/卡图印字、三机/跨网和全量回归。
- 卡牌信息契约目前逐牌检验的是 own 完整 formatter / 正式 v2 绑定；它不是对公开资源标签的一份独立逐卡人工真值表。
- 源漂移：`["scripts/system/global/effect_manager.gd", "scripts/system/global/game_progress.gd", "scripts/system/global/time_point_checker.gd", "scripts/system/operations/PlaySkill.gd"]`；全部日志保留，绝不拼接历史绿值补未运行项。

## 改动文件和 SHA256

生产文件（本次未改）：`scripts/match/view_builder.gd` SHA256 `78607bec727a0698e81370e33e988caa0b41def226a04f5e13bd4b8e6567ca8e`。
golden 改动清单：**空**（前后原文无变更）。
本次新增本报告与同名 JSON；JSON SHA256 `4539244b9be97e95e7864695f56925d0f18068da4b4799c663b589ddf7d6304b`。
