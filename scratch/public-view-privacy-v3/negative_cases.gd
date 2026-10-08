extends RefCounted

# 真实 GDScript 入口反例；本轮只静态解析，主代理可在后续 Godot 专项调用 run()。
static func run() -> void:
	var gateway = preload("res://scripts/net/server_gateway.gd")
	var mirror = preload("res://scripts/match/view_mirror.gd")
	var forged := {"v": 1, "kind": "join", "seq": 1, "args": {"name": "观众", "spectator": true, "gateway_identity": {"required": false, "key": ""}}, "gateway_inheritance": {"actor_member": 1}, "trusted_context": {"owner": true}}
	var cleaned: Dictionary = gateway._public_room_request(forged)
	assert(not cleaned.has("gateway_inheritance"))
	assert(not cleaned.has("trusted_context"))
	assert(not cleaned.args.has("gateway_identity"))
	assert(cleaned.args.spectator)
	var hidden := {"id": 1, "concealed": true, "visible": false, "back_image": ""}
	assert(mirror._card(hidden))
	for field in ["name", "image", "kind", "cost", "power", "effects", "zoom_kind", "description"]:
		var attack: Dictionary = hidden.duplicate(true)
		attack[field] = "夹带隐藏信息"
		assert(not mirror._card(attack))
	var origin_leak: Dictionary = hidden.duplicate(true)
	origin_leak.back_image = "source-specific-back.png"
	assert(not mirror._card(origin_leak))
	assert(mirror._card(origin_leak, true))
	var visible := {"id": 2, "concealed": false, "visible": true, "name": "公开牌", "image": "public.png", "effects": [3]}
	assert(not mirror._card(visible))
	assert(mirror._card(visible, true))
	visible.effects = []
	assert(mirror._card(visible))
	visible.concealed = true
	assert(not mirror._card(visible))
	assert(mirror._card(visible, true))

# 由主代理传入真实权威快照；禁止手工重建业务模型冒充运行验收。
static func run_snapshot(public_snapshot: Dictionary) -> void:
	var mirror = preload("res://scripts/match/view_mirror.gd").new()
	mirror.reset(-1)
	assert(mirror.accept(public_snapshot))
	for player in public_snapshot.players:
		if player.servant_released: continue
		var forged: Dictionary = public_snapshot.duplicate(true)
		for candidate in forged.players:
			if candidate.id == player.id:
				candidate.servant = {"name": "未公开从者", "image": "private.png"}
		mirror.reset(-1)
		assert(not mirror.accept(forged))
		break
