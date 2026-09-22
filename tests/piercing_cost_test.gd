extends "res://tests/regular_play_test.gd"

func run():
	LoadGame.load_game()
	var template:BaseSkill=null
	for servant in GameData.loaded_servants:
		for skill in servant._specials.get("SKILLS",[]):
			if skill._name=="gae_bolg_piercing_heart": template=skill
	check(template!=null,"real piercing card loaded")
	if template==null:
		get_tree().quit(1)
		return
	var d=setup(5,12)
	var spear:BaseSkill=CloneObject.new().exec(template)
	var sibling:BaseSkill=CloneObject.new().exec(template)
	d.servant_skills=[spear]
	RegisterObjectEffects.new().exec(spear,0)
	var c=d.hand_cards.duplicate()
	var initial:float=spear._cost.number
	check(RegularPlay.submit_group(0,[c[0],c[1]],[false,false]),"other ordinary pair submitted")
	check(spear._cost.number==initial,"other ordinary cards never increase unused spear cost")
	check(PlaySkill.new().exec(spear,0,true),"spear actually played as extra")
	check(spear._cost.number==initial+2,"own play increases cost once")
	var after_own:float=spear._cost.number
	check(PlayAttack.new().exec(c[2],0,null,null,true),"another extra attack played")
	check(spear._cost.number==after_own,"later extra attack leaves spear cost unchanged")
	check(template._cost.number==initial and sibling._cost.number==initial,"template and other clone remain unchanged")
	CloseCard.new().exec(spear,0)
	GameProgress.current_round=2; GameLog.set_context(2,"action")
	d.magic.number=12
	check(spear._cost.number==after_own,"increase persists into next round")
	check(PlaySkill.new().exec(spear,0,true),"spear played again next round")
	check(spear._cost.number==initial+4,"next own play stacks exactly one increase")
	print("RESULT checks=",checks," failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
