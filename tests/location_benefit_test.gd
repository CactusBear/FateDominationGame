extends Node
#地利修正的回归测试。
#用户现象："远隔操作的地利翻倍没有结算"。
#机制：效果链用 edit_location_benefit 改席位的 _benefit，而地利查询原先只读
#_printed_benefit（印刷值），两个字段互不相干 → 修正对结算毫无影响。
#另一半问题：_benefit 被改后回合结束从不还原，跨回合会越乘越大，
#且它是共享的地图数据，会连带影响之后占据该席位的其他玩家。
var failures:Array=[]
var checks:=0
func check(ok:bool,label:String):
	checks+=1
	if not ok: failures.append(label)
	print("CHECK ",label," ",ok)
func setup() -> void:
	EffectManager.reset_runtime(); GameLog.reset(); GameLog.set_context(1,"action")
	GameData.player_data_library.clear()
	for i in range(3):
		GameData.player_data_library[i]=GameData.new_player_data()
		GameData.player_data_library[i].is_out=false
	for loc in [MapData.miyama0, MapData.miyama1, MapData.miyama2]:
		(loc._players as Array).clear()
	RestoreLocationBenefits.new().exec()
func _ready(): call_deferred("run")
func run():
	setup()
	var loc:BaseLocation = MapData.miyama0
	var printed:int = int((loc._printed_benefit as BaseNumber).number)
	check(printed > 0,"the seat has printed terrain benefit")

	#部署到地利位：拿到印刷地利
	Deploy.new().exec(loc, 0)
	check(GetLocation.new().exec(0) == loc,"deployed onto the terrain seat")
	check(GetEffectiveLocationBenefit.new().exec(0) == printed,"printed benefit counts after deploy")

	#地利翻倍：效果改当前值，查询必须跟着变（这条原先是失效的）
	EditLocationBenefit.new().exec(loc, BaseNumber.new(printed * 2))
	check(GetEffectiveLocationBenefit.new().exec(0) == printed * 2,"doubled benefit is counted")
	#印刷基线不能被改掉，否则再也还原不回去
	check(int((loc._printed_benefit as BaseNumber).number) == printed,"printed baseline untouched by the edit")

	#结算与界面共用同一个查询：BattleResolver 记的威力构成里地利也应是翻倍后的值
	var res:Dictionary = BattleResolver.new().exec([0,1,2], BaseNumber.new(1))
	var detail:Dictionary = res.get("details_by_area",{}).get(MapData.miyama._area_name,{})
	var powers:Dictionary = detail.get("powers",{})
	check(powers.has(0),"battle detail records the player")
	if powers.has(0):
		check(int(powers[0].get("location_benefit",-1)) == printed * 2,"settlement uses the doubled benefit")

	#倍率也能用加减表达（vary_num），同样纳入结算
	EditLocationBenefit.new().exec(loc, null, BaseNumber.new(1))
	check(GetEffectiveLocationBenefit.new().exec(0) == printed * 2 + 1,"relative adjustment is counted")

	#回合结束还原：跨回合不能越乘越大
	check(RestoreLocationBenefits.new().exec() >= 1,"restore reports the touched seats")
	check(int((loc._benefit as BaseNumber).number) == printed,"benefit restored to the printed baseline")
	check(GetEffectiveLocationBenefit.new().exec(0) == printed,"benefit back to printed value after restore")

	#反例一：没有部署、只是移动过去的玩家不享有地利（修正也不该让他拿到）
	setup()
	EditLocationBenefit.new().exec(loc, BaseNumber.new(printed * 2))
	SetLocation.new().exec(loc, 1, false)
	check(GetLocation.new().exec(1) == loc,"player placed without deploying")
	check(GetEffectiveLocationBenefit.new().exec(1) == 0,"arriving without deploy grants no benefit even when doubled")
	RestoreLocationBenefits.new().exec()

	#反例二：战区声明不提供地利时，倍率也无效
	setup()
	Deploy.new().exec(loc, 0)
	EditLocationBenefit.new().exec(loc, BaseNumber.new(printed * 2))
	var blocker := NoLocationBenefitEffect.new()
	#BaseBuff 的构造只收 名字 + 图；层数/效果/激活状态是构造后再设的字段
	var buff := BaseBuff.new("test_no_benefit","")
	buff._effects = [blocker]
	buff._is_active = true
	(MapData.miyama._buffs as Array).append(buff)
	check(GetEffectiveLocationBenefit.new().exec(0) == 0,"area that grants no benefit overrides the multiplier")
	(MapData.miyama._buffs as Array).erase(buff)
	RestoreLocationBenefits.new().exec()
	check(GetEffectiveLocationBenefit.new().exec(0) == printed,"benefit returns once the blocker is gone")

	print("RESULT checks=",checks," failures=",failures)
	var f=FileAccess.open("res://location_benefit_result.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures})); f.close()
	get_tree().quit(0 if failures.is_empty() else 1)
