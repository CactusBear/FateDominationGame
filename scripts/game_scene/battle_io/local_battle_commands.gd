class_name LocalBattleCommands
extends RefCounted

## 本地命令适配；创建处交接原成功开局 context。
## ids 与视图必须共享同一 NetIds；run 接收 method、argv、原 context 三参。
signal result(request_id: int, ok: bool, reason: String)
var _seat: int
var _ids
var _dispatcher
var _run: Callable
# 创建处交接的成功开局原值；提交与延期只递送，不领取当前来源。
var _context: SessionContext = null
var _request_id: int = 0
var _broadcast_confirmation: bool = false
var _broadcast_ai_seats: Array = []
var _broadcast_batch: int = 0
var _broadcast_ai_elapsed: float = 0.0
const BROADCAST_AI_CONFIRM_STEP: float = 0.28

## 由本地开局调用方明确声明；不得按 headless/AI 名称推断屏障或控制权。
## ai_seats 来自调用方控制声明，不得包含本适配器绑定的真人本人。
func declare_broadcast_confirmation(enabled: bool, ai_seats: Array = []) -> bool:
	if GameProgress.is_battle_broadcast_pending(): return false
	var checked: Array = []
	for seat in ai_seats:
		if not seat is int or seat < 0 or seat == _seat or checked.has(seat): return false
		checked.append(seat)
	_broadcast_confirmation = enabled
	_broadcast_ai_seats = checked
	_broadcast_batch = 0
	_broadcast_ai_elapsed = 0.0
	GameProgress.battle_broadcast_requires_confirm = enabled
	return true

## 本地渲染循环显式调用；每个节拍只提交一席，复用严格共享分派。
func tick_broadcast_confirmation(delta: float) -> bool:
	if not _broadcast_confirmation or not GameProgress.is_battle_broadcast_pending(): return false
	var batch: int = GameProgress.battle_broadcast_batch_id()
	if batch != _broadcast_batch:
		_broadcast_batch = batch
		_broadcast_ai_elapsed = 0.0
	_broadcast_ai_elapsed += maxf(0.0, delta)
	if _broadcast_ai_elapsed < BROADCAST_AI_CONFIRM_STEP: return false
	for seat in _broadcast_ai_seats:
		if not GameProgress.can_confirm_battle_broadcast(seat, batch): continue
		_broadcast_ai_elapsed = 0.0
		var reply: Dictionary = _dispatcher.dispatch(seat, "confirm_broadcast", {"batch_id": batch}, _ids, _run, _context)
		return reply.ok
	return false

func _init(seat: int, ids, dispatcher, run: Callable, original_context: SessionContext = null) -> void:
	_seat = seat
	_ids = ids
	_dispatcher = dispatcher
	_run = run
	_context = original_context

func submit(kind: String, args: Dictionary) -> int:
	_request_id += 1
	var request_id: int = _request_id
	# 稳定 ID 仅由共享 dispatcher 解析；不在适配层重复分派或执行。
	var reply: Dictionary = _dispatcher.dispatch(_seat, kind, args, _ids, _run, _context)
	result.emit(request_id, reply.ok, reply.reason)
	return request_id
