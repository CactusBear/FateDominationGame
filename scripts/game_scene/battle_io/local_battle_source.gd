class_name LocalBattleSource
extends RefCounted

## 调用方显式注入座位、同一个 builder 及 MatchSeatQuery(builder)。
## 只有展示快照缓存；规则动作和待答必须每次重新查询。
signal changed

var _seat: int
var _builder: RefCounted
var _query: RefCounted
var _payment: Dictionary = {}
var _view: Dictionary = {}
var _view_valid := false
var _notifying := false

func _init(seat: int, view_builder: RefCounted, seat_query: RefCounted) -> void:
	_seat = seat
	_builder = view_builder
	_query = seat_query
	# 仅保存查询创建时捕获的原报价，不在 UI 读预览时创建来源。
	_payment = _query.payment_quote(_seat) if _query.has_method("payment_quote") else {}

func read_view() -> Dictionary:
	if not _view_valid:
		_view = _builder.build(_seat)
		_view_valid = true
	return _view.duplicate(true)

## 不发信号，供主动刷新调用方使用，避免通知与渲染互相递归。
func invalidate() -> void:
	_view_valid = false
	_view.clear()

## 显式开始新的刷新周期；同一周期的多次 read_view 只 build 一次。
## 通知回调内再次 refresh 仍会失效，但不会嵌套发出 changed。
func refresh() -> void:
	invalidate()
	if _notifying:
		return
	_notifying = true
	changed.emit()
	_notifying = false

func set_seat(seat: int) -> void:
	if _seat == seat:
		return
	_seat = seat
	_payment = _query.payment_quote(_seat) if _query.has_method("payment_quote") else {}
	refresh()

func read_actions() -> Dictionary:
	return _query.actions(_seat)

func read_pending() -> Dictionary:
	return _query.pending(_seat)

## 规则对象交给既有 query；快照中的 ID 仅用于展示身份比较。
func read_group_preview(cards: Array, hidden: Array) -> Dictionary:
	if not RegularPlay.payment_quote_is_current(_seat, _payment):
		return {"cards": [], "hidden": hidden.duplicate(), "waiting": false, "submitted": false,
			"preview": {"ok": false}}
	var ids: Array = []
	for card in cards:
		ids.append(_builder.ids.id_for(card))
	return {"cards": ids, "hidden": hidden.duplicate(), "waiting": false, "submitted": false,
		"preview": _query.preview(_seat, cards, hidden, _payment).duplicate(true)}
