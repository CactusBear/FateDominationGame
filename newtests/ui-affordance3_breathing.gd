extends "res://newtests/ui-affordance3_contract.gd"

# 同一真实资格与模板上的呼吸时钟/技能区展示合同；只读，不造候选。
func ui_run() -> void:
	await ui_wait(160)
	ui_check(_held_card_playable(ui_cards[3]) and _manual_effects_of(ui_cards[3]).size() == 1, "real authority dual eligibility before clock sampling")
	var hand := ui_slot(ui_cards[3])
	var inner: Control = hand.get_node("Breath")
	var outer: Control = hand.get_node("EffectBreath")
	ui_check(_breathing.has(inner) and _breathing.has(outer), "both real ring nodes registered with production breathing clock")
	_update_breathing()
	var alpha := inner.modulate.a
	OS.delay_msec(100)
	_update_breathing()
	ui_check(not is_equal_approx(alpha, inner.modulate.a) and is_equal_approx(inner.modulate.a,outer.modulate.a), "both nodes breathe on same production phase without third node")
	# ZoneCard绑定复用同一个source和真实runtime牌，仅检查模板消费者，不伪造技能区资格。
	for i in range(4):
		var node: Control = _spawn("ZoneCard", _hand)
		node.set_meta("card", ui_cards[i])
		_bind_hand_card(node,ui_cards[i],"技能",1,true,false)
		ui_check(node.get_node("Breath").visible == (i in [1,3]), "zone template gold from same authoritative preview %d" % i)
		ui_check(node.get_node("EffectBreath").visible == (i in [2,3]), "zone template purple from same effect candidates %d" % i)
		ui_check(not node.get_node("Selected").visible, "zone template no third white node %d" % i)
		ui_check(node.get_node("Breath").get_meta("selected_outline").border_color == Color.WHITE, "zone original-node selected style declaration %d" % i)
	print("RESULT ",JSON.stringify({"suite":"ui-affordance3-breathing-zone","checks":ui_checks,"failures":ui_failures}))
	get_tree().quit(0 if ui_failures.is_empty() else 1)
