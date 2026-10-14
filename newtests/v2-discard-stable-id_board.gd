extends "res://scripts/game_scene/battle_board_v2.gd"

# 仅创建边界保留 super 返回的同一实例；生产 ready 仍构造 query/source/commands。
var identity_builder: RefCounted
var builder_factory_calls: int = 0

func create_local_view_builder() -> RefCounted:
	builder_factory_calls += 1
	identity_builder = super.create_local_view_builder()
	return identity_builder
