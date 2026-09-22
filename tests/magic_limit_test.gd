extends Node
# 魔力上下限回归：规则是"每个玩家通常拥有从 0 到 12 的魔力值"。
# 上限读数必须来自 GameData.magic_limit（效果可以改），不能写死 12；
# 夹取只在 EditMagic 一处做——获得魔力的来源（工房充能席、局势牌印刷魔力、令咒、效果）
# 全都经过它，任何一个来源各自 min/max 都会漏。
var failures:Array=[]
var checks:int=0
var _limit_backup=null

func check(ok:bool,label:String):
	checks+=1
	if not ok: failures.append(label)
	print("CHECK ",label," ",ok)

func _ready(): call_deferred("run")

func setup(magic:int) -> Dictionary:
	EffectManager.reset_runtime(); GameLog.reset(); GameLog.set_context(1,"action")
	GameProgress.is_game_over=false
	GameProgress.current_round=1
	GameProgress.current_phase_index=2
	GameProgress.current_player_id=0
	GameData.player_data_library.clear()
	GameData.player_data_library[0]=GameData.new_player_data()
	var d:Dictionary=GameData.player_data_library[0]
	d.is_out=false
	d.magic.number=magic
	return d

func run():
	_limit_backup=GameData.magic_limit.number
	GameData.magic_limit.number=12

	var d:Dictionary=setup(10)
	EditMagic.new().exec(null, BaseNumber.new(4), 0)
	check(d.magic.number==12,"a magic gain stops at the declared limit")
	var logs:Array=GameLog.query({"type":"magic_add","actor":0},0)
	check(not logs.is_empty() and int(logs[0].data.get("delta",0))==2,
		"the recorded change is what actually happened, not what was asked for")

	# 上限是数据：提高上限后同样的收益就能拿满，证明没有写死 12
	GameData.magic_limit.number=20
	EditMagic.new().exec(null, BaseNumber.new(4), 0)
	check(d.magic.number==16,"the cap follows GameData.magic_limit instead of a hard-coded 12")

	# 直接设值同样受约束：效果写 set 也不能把魔力顶到上限之上
	EditMagic.new().exec(BaseNumber.new(99), null, 0)
	check(d.magic.number==20,"setting a value above the limit is clamped")

	# 下限：扣减不会把魔力压成负数
	EditMagic.new().exec(null, BaseNumber.new(-50), 0)
	check(d.magic.number==0,"magic never drops below zero")

	# 真实来源之一：工房充能席的部署收益走的是同一条夹取
	GameData.magic_limit.number=12
	d=setup(11)
	var seat=MapData.magic_workshop0
	(seat._players as Array).clear()
	check(DeployRules.deploy_to_area(MapData.magic_workshop, 0)!=null,"deploy onto the charge seat")
	check(d.magic.number==12,"a seat benefit is capped as well")

	GameData.magic_limit.number=_limit_backup
	check(GameData.magic_limit.number==_limit_backup,"the limit is restored after the probe")
	print("RESULT checks=",checks," failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
