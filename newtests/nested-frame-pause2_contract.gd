extends "res://newtests/c0-observer_fixture.gd"

func settle(root:BaseEffect = null) -> void:
	var attempts:int = 0
	while EffectManager.runtime_guard_status().paused and attempts < 20:
		if root != null: check(root._self_vars.is_empty(), "任何子监听待续时父返回值仍未发布")
		check(EffectManager.resume_runtime_guard(), "原预算片真实恢复")
		await get_tree().process_frame
		attempts += 1
	check(not EffectManager.runtime_guard_status().paused, "二十次原上限内完成")
	print("SETTLE_TRACE ",JSON.stringify({"source":EffectManager.execution_source_status(),"calls":GameLog.all_func_calls()}))

func called(name:String, status:String) -> int:
	var count:int = 0
	for entry in GameLog.all_func_calls():
		if entry.get("func_name") == name and entry.get("status") == status: count += 1
	return count

func facts(kind:String, point:String = "") -> int:
	var count:int = 0
	for entry in GameLog.query({}, null):
		if entry.get("type") == kind and (point == "" or entry.get("tags", []).has(point)): count += 1
	return count

func event_chain() -> void:
	fresh_observation([0], {"enabled":true,"steps":2,"seconds":0.0})
	var area := BaseMapArea.new("native-parent-two-events")
	var declaration:Dictionary = sampling_declaration([{"func_name":"get_events","parameters":[area],"var_index":1},{"func_name":"array_length","parameters":[{"self_var":1}]}], [TimePoints.SELF_CARD_REVEALED])
	var template := LoadEvent.build_event(event_data("native-parent-template", [declaration]), "", observer_source)
	check(template != null, "真实 runtime 事件工厂")
	template._effects[0]._remove_after_trigger = true
	MapData.event_deck = [template]
	var operation:Dictionary = GameProgress.start_progress_operation("add_event_from_deck", [area,2,false], observer_source)
	check(operation.ok, "真实父函数根")
	var root:BaseEffect = operation.root
	check(EffectManager.runtime_guard_status().paused, "事件父子真实待续")
	check(area._events.size() == 1, "当前事件已提交但不提前第二张")
	check(root._self_vars.is_empty(), "暂停不写部分 placed 返回值")
	var frames:Array = []
	for frame in EffectManager.execution_runtime_snapshot().suspended_functions:
		frames.append({"name":frame.function._name,"stage":frame.stage,"control":frame.get("control",{}).get("status"),"has_tail":frame.has("native_tail"),"has_child":frame.has("child_run")})
	print("NATIVE_SCOPE ",JSON.stringify(frames))
	await settle(root)
	check(root._self_vars == [2], "最终 placed 只在整段尾部完成后写回")
	check(area._events.size() == 2 and area._events[0] != area._events[1], "两张独立克隆且不重放")
	check(MapData.event_deck.size() == 1 and is_same(MapData.event_deck[0],template), "牌堆旋转不重放")
	check(called("add_event_from_deck","executed") == 1, "原生父返回恰好一次")
	check(called("array_length","executed") == 6, "两张事件三轮体各恰好一次")
	var values:Array = []
	for entry in GameLog.all_func_calls():
		if entry.get("func_name") == "array_length" and entry.get("status") == "executed": values.append(entry.return_value)
	check(values == [1,1,1,2,2,2], "每张事件监听先完成才落下一张")
	check(facts("time_point",TimePoints.CARD_REVEALED) == 2, "亮出时点恰好每张一次")
	check(not EffectManager.resume_runtime_guard(), "已消费暂停不能复活")

func magic_chain() -> void:
	fresh_observation([0], {"enabled":true,"steps":2,"seconds":0.0})
	var declaration:Dictionary = sampling_declaration([{"func_name":"get_data_number","parameters":["magic",0]}], [TimePoints.MAGIC_ADD])
	var listeners:Array = LoadHelper.load_effects([declaration], null, observer_source)
	check(listeners.size() == 1 and EffectManager.register_effect(listeners[0],0), "真实原来源魔力监听")
	var magic:BaseNumber = GameData.player_data_library[0].magic
	var before = magic.number
	var operation:Dictionary = GameProgress.start_progress_operation("edit_magic", [null,BaseNumber.new(2),0], observer_source)
	var root:BaseEffect = operation.root
	check(EffectManager.runtime_guard_status().paused, "魔力父子真实待续")
	check(magic.number == before + 2 and root._self_vars.is_empty(), "已提交魔力而父结果仍待续")
	var scope:Dictionary = {}
	for frame in EffectManager.execution_runtime_snapshot().suspended_functions:
		if frame.get("control", {}).get("status") == "PENDING": scope = frame.control
	check(scope.get("continuation") is RefCounted and is_same(scope.get("original_context"), root.runtime_context()), "PENDING 使用独立续行身份与原 context")
	var old = scope.get("continuation")
	if EffectManager.runtime_guard_status().paused:
		check(EffectManager.resume_runtime_guard(), "消费当前身份而不重跑原生主体")
		if EffectManager.runtime_guard_status().paused:
			var next:Dictionary = {}
			for frame in EffectManager.execution_runtime_snapshot().suspended_functions:
				if frame.get("control", {}).get("status") == "PENDING": next = frame.control
			check(next.get("continuation") is RefCounted and not is_same(next.get("continuation"),old), "再次待续使用新单次身份")
	await settle()
	check(magic.number == before + 2 and root._self_vars == [null], "恢复保留原 null 且不重复加魔力")
	check(called("edit_magic","executed") == 1 and called("get_data_number","executed") == 3, "父返回与三轮子体恰好一次")
	check(facts("time_point",TimePoints.MAGIC_ADD) == 1, "魔力 AFTER 时点不重派")
	check(not EffectManager.resume_runtime_guard(), "魔力已消费续行不能复活")

func stale_chain() -> void:
	fresh_observation([0], {"enabled":true,"steps":2,"seconds":0.0})
	var declaration:Dictionary = sampling_declaration([{"func_name":"get_data_number","parameters":["magic",0]}], [TimePoints.MAGIC_ADD])
	var listeners:Array = LoadHelper.load_effects([declaration], null, observer_source)
	check(EffectManager.register_effect(listeners[0],0), "失效反例监听同源")
	var operation:Dictionary = GameProgress.start_progress_operation("edit_magic", [null,BaseNumber.new(2),0], observer_source)
	check(EffectManager.runtime_guard_status().paused, "失效反例先真实待续")
	GameStart.end_session()
	var fresh:Dictionary = GameData.reset_game_session([0])
	check(fresh.ok, "换局不补旧票")
	var magic:BaseNumber = GameData.player_data_library[0].magic
	var before = magic.number
	check(not EffectManager.resume_runtime_guard(), "换局旧子父续行拒绝")
	check(magic.number == before and operation.root._self_vars.is_empty(), "拒绝不写新局或旧父返回")

func synchronous_boundaries() -> void:
	fresh_observation([0], {"enabled":true,"steps":2,"seconds":0.0})
	var before_decl:Dictionary = sampling_declaration([{"func_name":"get_data_number","parameters":["magic",0]}], [TimePoints.BEFORE_MAGIC_ADD])
	var listeners:Array = LoadHelper.load_effects([before_decl], null, observer_source)
	check(EffectManager.register_effect(listeners[0],0), "同步 BEFORE 监听真实登记")
	var operation:Dictionary = GameProgress.start_progress_operation("edit_magic", [null,BaseNumber.new(2),0], observer_source)
	check(not EffectManager.runtime_guard_status().paused, "BEFORE 原生区间仍不可预算中断")
	check(operation.root._self_vars == [null] and called("get_data_number","executed") == 3, "BEFORE 同步完成不被静默取消")
	fresh_observation([0], {"enabled":true,"steps":2,"seconds":0.0})
	var declaration:Dictionary = sampling_declaration([{"func_name":"array_length","parameters":[[1]]}], [TimePoints.SELF_CARD_REVEALED])
	var event := LoadAttack.resolve("strength:2", observer_source)
	check(event != null, "未知原生帧反例仍用合法 runtime 卡")
	listeners = LoadHelper.load_effects([declaration], event, observer_source)
	check(EffectManager.register_effect(listeners[0],0), "未知原生父亮出监听真实登记")
	GameData.player_data_library[0].played_cards.append(event)
	event.set_concealed(true)
	operation = GameProgress.start_progress_operation("set_card_concealed", [event,false,0,observer_source], observer_source)
	check(not EffectManager.runtime_guard_status().paused, "未声明恢复的 SetCardConcealed 父仍不在内部暂停")
	check(operation.root._self_vars == [true] and called("array_length","executed") == 3, "非受支持原生父同步完成未改语义")

func run() -> void:
	await event_chain()
	await magic_chain()
	await stale_chain()
	synchronous_boundaries()
	GameStart.end_session()
	finish()
