class_name NotificationInbox
extends RefCounted
## ID-based receipt tracking for complete, already-validated notification snapshots.
## Receipt means handed to the caller, not displayed or acknowledged by authority.
## The caller owns its display backlog and all session/observer lifecycle decisions.

var _seen: Dictionary = {}

## Returns new records in snapshot order, without text-based deduplication.
## An ID absent from a snapshot is forgotten: reappearance is a new receipt.
## Input records are borrowed, not mutated; callers own any copies they require.
func ingest(notices: Array) -> Array:
	var current: Dictionary = _ids(notices)
	for id in _seen.keys():
		if not current.has(id):
			_seen.erase(id)
	var received: Array = []
	for notice in notices:
		var id: String = notice["id"]
		if not _seen.has(id):
			_seen[id] = true
			received.append(notice)
	return received

## Clears local receipt tracking; does not clear the caller's display backlog.
func reset() -> void:
	_seen.clear()

## Seeds receipt tracking without replaying baseline records.
## The caller must provide the actual lifecycle baseline and reset its own backlog.
## This does not establish an authority-side reconnect cutoff or delivery guarantee.
func reset_to_baseline(notices: Array) -> void:
	_seen = _ids(notices)

func _ids(notices: Array) -> Dictionary:
	var ids: Dictionary = {}
	for notice in notices:
		ids[notice["id"]] = true
	return ids
