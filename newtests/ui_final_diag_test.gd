extends Node
func _ready() -> void:
	var fixture = preload("res://newtests/ui_final_fixture.gd").setup()
	var builder = preload("res://scripts/match/view_builder.gd").new()
	var query = MatchSeatQuery.new(builder)
	for card in fixture.cards:
		print("DIAG ",card._name," awakened=",card._is_awakened," extra=",card._need_extra_play," modes=",RegularPlay.pending_modes(0,[],[],card)," canplay=",PlayRules.can_play(card,fixture.data)," magic=",fixture.data.magic.number," limit=",GameData.player_magic_limit(0).number)
	print("DIAG_MORE prefix=",RegularPlay.can_play_group_prefix(0,[],[])," candidates=",RegularPlay.candidates(0)," completed=",RegularPlay.completed(0)," out=",fixture.data.is_out)
	for card in fixture.cards:
		print("DIAG_CARD ",card._name," activating=",card._is_activating," faceup=",RegularPlay.faceup_allowed(card,0)," board=",PlayRules.board_allows(card,fixture.data)," in=",RegularPlay.in_play_zone(fixture.data,card)," modes=",RegularPlay.pending_modes(0,[],[],card))
	print("DIAG_PREVIEW ",query.preview(0,[],[]))
	print("RESULT ",JSON.stringify({"suite":"ui_final_diagnostic","checks":1,"failures":[]}))
	get_tree().quit()
