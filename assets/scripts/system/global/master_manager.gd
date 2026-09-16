extends Node


#只管理御主效果与玩家的御主归属，不负责游戏开始、从者或技能。
#注册为autoload"MasterManager"，不能再带class_name(两者会重名冲突)。
func bind_master_effects(player_id:int):
	var player_data = GameDataManager.get_player_data(player_id) as Dictionary
	var master = player_data["master"]
	if master is BaseMaster:
		EffectManager.register_effects(master._effects, player_id)


#把玩家的令咒效果挂进效果池。令咒效果（三选一）此前从未被登记，
#JSON 写全了也不会被询问——开局绑定御主/从者效果时一并挂载。
#挂的是令咒模板卡的克隆体上的效果：模板是全体玩家共用的同一份 BaseCard，
#直接登记模板效果会让七个玩家共享同一个 BaseEffect 对象（谁的选项用量都记在一起）；
#克隆体各有一份效果实例，用量计数、消耗判定天然按玩家隔离。克隆出来的效果
#copy_effects 已把 from 指回克隆卡并重登数字，_trigger_player_id 由 register_effect 写入。
#克隆卡本身交给第一个玩家数据持有（out_of_game.command_spell 作登记处），重开一局随对象图释放
func bind_command_spell_effects(player_id:int):
	var player_data = GameDataManager.get_player_data(player_id) as Dictionary
	var template:BaseCard = LoadCommandSpell.resolve_player_command_spell(
		player_data.get("master"), player_data.get("servant"))
	if template == null:
		return
	var card = CloneObject.new().exec(template) as BaseCard
	(player_data["out_of_game"]["command_spell"] as Array).append(card)
	EffectManager.register_effects(card._effects, player_id)
