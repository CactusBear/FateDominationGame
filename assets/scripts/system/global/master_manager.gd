extends Node


#游戏开始时把各玩家已确定的御主/从者/技能的效果登记进效果池并绑定归属。
#效果只有绑定了归属玩家，才会在时点检查时被查到(检查的是归属玩家的时点表)
func _on_game_start():
	for id in GameData.player_data_library.keys():
		bind_player_effects(id)
	GameProgress.start_game()


func bind_player_effects(player_id:int):
	var player_data = GameDataManager.get_player_data(player_id) as Dictionary

	var master = player_data["master"]
	if master is BaseMaster:
		EffectManager.register_effects(master._effects, player_id)
		#升级技能要等实际进入技能区才登记，这里只登记御主本体的效果

	var servant = player_data["servant"]
	if servant != null and "_effects" in servant:
		EffectManager.register_effects(servant._effects, player_id)

	#已经在场上的技能卡
	for skill in player_data["side"]["skills"]:
		if skill is BaseSkill:
			EffectManager.register_effects(skill._effects, player_id)
