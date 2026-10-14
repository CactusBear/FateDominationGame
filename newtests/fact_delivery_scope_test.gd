extends Node

const Delivery = preload("res://scripts/system/global/fact_delivery.gd")
var checks:int = 0
var failures:Array = []
var received:Array = []

func _check(label:String, ok:bool) -> void:
	checks += 1
	print("CHECK ", label, " ", str(ok))
	if not ok:
		failures.append(label)

func _observe(entry:Dictionary) -> void:
	received.append(entry["id"])

func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func _fresh():
	received.clear()
	var delivery = Delivery.new()
	delivery.observe(_observe)
	return delivery

func _ready() -> void:
	await _run()
	print("RESULT ", JSON.stringify({"suite":"fact_delivery_scope", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

func _run() -> void:
	var delivery = _fresh()
	# 旧公开入口业务反例：两个根被当作父/子时，全局依赖误吞无关兄弟。
	# 缺接口不触发解析/调用错误，也不伪造 owned 能力；同一交付 oracle 保持。
	if not delivery.has_method("begin_owned"):
		delivery.begin(101)
		delivery.enqueue({"id":"parent"})
		delivery.begin(102)
		delivery.enqueue({"id":"child"})
		delivery.enqueue({"id":"sibling"})
		delivery.abort(102)
		delivery.commit(101)
		await _settle()
		_check("parent_survives_child_abort", received.has("parent"))
		_check("failed_child_never_delivered", not received.has("child"))
		_check("sibling_survives_child_abort", received.has("sibling"))
		print("CAPABILITY owned=false legacy_business_counterexample=true")
		return

	delivery.begin(101)
	var root_before:Dictionary = delivery.transaction_status(101)
	delivery.enqueue({"id":"parent"})
	var child = delivery.begin_owned()
	_check("owned_begin_pending", delivery.owned_status(child).status == Delivery.TransactionStatus.PENDING)
	_check("owned_enqueue_accepts_current", delivery.enqueue_owned({"id":"child"}, child))
	delivery.enqueue({"id":"sibling"})
	_check("child_abort_accepted", delivery.abort_owned(child))
	_check("parent_token_unchanged", delivery.transaction_status(101) == root_before)
	delivery.commit(101)
	await _settle()
	_check("parent_survives_child_abort", received.has("parent"))
	_check("failed_child_never_delivered", not received.has("child"))
	_check("sibling_survives_child_abort", received.has("sibling"))
	_check("failed_handle_not_pending", delivery.owned_status(child).status == Delivery.TransactionStatus.NOT_PENDING)
	_check("failed_handle_cannot_release", not delivery.release_owned(child))
	_check("failed_handle_cannot_enqueue", not delivery.enqueue_owned({"id":"late_child"}, child))
	delivery = _fresh()
	delivery.begin(201)
	root_before = delivery.transaction_status(201)
	delivery.enqueue({"id":"parent_success"})
	child = delivery.begin_owned()
	delivery.enqueue_owned({"id":"child_success"}, child)
	_check("child_release_accepted", delivery.release_owned(child))
	_check("child_success_preserves_parent_token", delivery.transaction_status(201) == root_before)
	await _settle()
	_check("child_success_does_not_commit_parent", received.is_empty())
	delivery.commit(201)
	await _settle()
	_check("success_delivers_once_in_order", received == ["parent_success", "child_success"])
	_check("released_handle_cannot_abort", not delivery.abort_owned(child))
	_check("released_handle_cannot_parent", delivery.begin_owned(child) == null)
	_check("released_handle_cannot_enqueue", not delivery.enqueue_owned({"id":"late_success"}, child))

	delivery = _fresh()
	delivery.begin(301)
	var parent = delivery.begin_owned()
	child = delivery.begin_owned(parent)
	var grandchild = delivery.begin_owned(child)
	delivery.enqueue_owned({"id":"parent_owned"}, parent)
	delivery.enqueue_owned({"id":"child_owned"}, child)
	delivery.enqueue_owned({"id":"grandchild"}, grandchild)
	_check("nested_child_release", delivery.release_owned(child))
	_check("nested_parent_abort", delivery.abort_owned(parent))
	_check("aborted_descendant_invalidated", delivery.owned_status(grandchild).status == Delivery.TransactionStatus.NOT_PENDING)
	_check("aborted_descendant_cannot_release", not delivery.release_owned(grandchild))
	_check("aborted_descendant_cannot_abort_again", not delivery.abort_owned(grandchild))
	delivery.enqueue({"id":"unowned_sibling"})
	delivery.commit(301)
	await _settle()
	_check("ancestor_abort_cancels_released_child", received == ["unowned_sibling"])
	_check("foreign_parent_rejected", delivery.begin_owned(RefCounted.new()) == null)

	delivery = _fresh()
	delivery.begin(401)
	var old = delivery.begin_owned()
	var old_generation:int = delivery.owned_status(old).generation
	delivery.enqueue_owned({"id":"old_attempt"}, old)
	delivery.abort_owned(old)
	var retry = delivery.begin_owned()
	_check("retry_generation_increases", delivery.owned_status(retry).generation > old_generation)
	delivery.enqueue_owned({"id":"retry"}, retry)
	_check("old_abort_rejected", not delivery.abort_owned(old))
	_check("old_release_rejected", not delivery.release_owned(old))
	_check("old_parent_rejected", delivery.begin_owned(old) == null)
	_check("retry_still_pending", delivery.owned_status(retry).status == Delivery.TransactionStatus.PENDING)
	delivery.release_owned(retry)
	delivery.commit(401)
	await _settle()
	_check("old_token_does_not_cancel_retry", received == ["retry"])

	delivery = _fresh()
	old = delivery.begin_owned()
	old_generation = delivery.owned_status(old).generation
	delivery.enqueue_owned({"id":"before_reset"}, old)
	delivery.reset()
	_check("reset_invalidates_old_handle", delivery.owned_status(old).status == Delivery.TransactionStatus.NOT_PENDING)
	_check("reset_old_abort_rejected", not delivery.abort_owned(old))
	_check("reset_old_parent_rejected", delivery.begin_owned(old) == null)
	retry = delivery.begin_owned()
	_check("reset_does_not_restore_generation", delivery.owned_status(retry).generation > old_generation)
	delivery.enqueue_owned({"id":"after_reset"}, retry)
	delivery.release_owned(retry)
	await _settle()
	_check("old_deferred_drain_cannot_take_new_scope", received == ["after_reset"])

	delivery = _fresh()
	delivery.begin(501)
	child = delivery.begin_owned()
	delivery.enqueue_owned({"id":"aborted_root_child"}, child)
	delivery.abort(501)
	_check("aborted_root_cannot_release_child", not delivery.release_owned(child))
	_check("aborted_root_cannot_extend_child", delivery.begin_owned(child) == null)
	_check("aborted_root_cannot_enqueue_child", not delivery.enqueue_owned({"id":"late_root_child"}, child))
	delivery.abort_owned(child)
	delivery.begin(501)
	delivery.enqueue({"id":"new_root"})
	delivery.commit(501)
	await _settle()
	_check("root_id_reuse_does_not_revive_old_ticket", received == ["new_root"])

	delivery = _fresh()
	var other = Delivery.new()
	child = delivery.begin_owned()
	_check("foreign_delivery_cannot_abort", not other.abort_owned(child))
	_check("foreign_delivery_cannot_release", not other.release_owned(child))
	_check("foreign_delivery_cannot_parent", other.begin_owned(child) == null)
	_check("null_enqueue_rejected", not delivery.enqueue_owned({"id":"null"}, null))
	delivery.abort_owned(child)

	delivery = _fresh()
	child = delivery.begin_owned()
	var fact:Dictionary = {"id":"frozen_fact", "payload":{"value":"before"}}
	delivery.enqueue_owned(fact, child)
	fact.id = "mutated_fact"
	fact.payload.value = "after"
	delivery.release_owned(child)
	await _settle()
	_check("owned_fact_copied_before_delivery", received == ["frozen_fact"])
	_check("default_unknown_transaction_status_compatible", delivery.transaction_status(999).status == Delivery.TransactionStatus.NOT_PENDING)

	delivery = _fresh()
	delivery.begin(601)
	parent = delivery.begin_owned()
	child = delivery.begin_owned(parent)
	var child_projection:Dictionary = delivery.owned_status(child)
	var saved_projection:Dictionary = child_projection.duplicate()
	child_projection.state = "aborted"
	child_projection.generation = -1
	_check("owned_status_projection_is_private", delivery.owned_status(child) == saved_projection)
	delivery.enqueue_owned({"id":"nested_success"}, child)
	delivery.release_owned(parent)
	delivery.commit(601)
	await _settle()
	_check("parent_success_still_waits_child", received.is_empty())
	delivery.release_owned(child)
	await _settle()
	_check("nested_success_released_once", received == ["nested_success"])

	delivery = _fresh()
	delivery.begin(701)
	parent = delivery.begin_owned()
	child = delivery.begin_owned(parent)
	var sibling = delivery.begin_owned(parent)
	delivery.enqueue_owned({"id":"owned_failed_sibling"}, child)
	delivery.enqueue_owned({"id":"owned_surviving_sibling"}, sibling)
	delivery.abort_owned(child)
	_check("owned_sibling_preserved_pending", delivery.owned_status(sibling).status == Delivery.TransactionStatus.PENDING)
	delivery.release_owned(sibling)
	delivery.release_owned(parent)
	delivery.commit(701)
	await _settle()
	_check("owned_sibling_survives_child_abort", received == ["owned_surviving_sibling"])

	delivery = _fresh()
	delivery.begin(801)
	delivery.enqueue({"id":"stale_subscription"})
	delivery.unobserve(_observe)
	delivery.observe(_observe)
	delivery.commit(801)
	await _settle()
	_check("default_subscription_generation_compatible", received.is_empty())
	delivery.enqueue({"id":"new_subscription"})
	await _settle()
	_check("default_enqueue_remains_compatible", received == ["new_subscription"])
