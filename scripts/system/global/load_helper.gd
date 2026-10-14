class_name LoadHelper
extends RefCounted


#卡牌 JSON 加载的共享工具类：数字解析、效果解析、func_name 转类名、卡背解析。
#独立成 class_name 供 LoadGame / LoadAttack / LoadEvent / LoadSituation 复用，
#避免 LoadAttack / LoadEvent 直接引用 LoadGame autoload 造成编译期循环依赖。
#本类通过 class_name 复用来源服务；不读取 current_token，不新增 autoload。


#卡数据根目录。编辑器使用项目内的 data/；导出后使用可执行文件同级的外部 data/。
#data 不进入 pck，由导出插件复制到 exe 旁，玩家可以直接替换 JSON 与图片。
const DATA_DIR_NAME := "data"

# TABLE 是唯一入口登记；本表只冻结已登记脚本的具体依赖，不按字符串拼路径。
const _REGISTERED_SCRIPTS := {
	"ActivateEffect": preload("res://scripts/system/operations/ActivateEffect.gd"),
	"AddAttack": preload("res://scripts/system/operations/AddAttack.gd"),
	"AddEventFromDeck": preload("res://scripts/system/operations/AddEventFromDeck.gd"),
	"AddMapArea": preload("res://scripts/system/operations/AddMapArea.gd"),
	"AddMapAreaBuff": preload("res://scripts/system/operations/AddMapAreaBuff.gd"),
	"AddMapAreaEvents": preload("res://scripts/system/operations/AddMapAreaEvents.gd"),
	"AddPlayer": preload("res://scripts/system/operations/AddPlayer.gd"),
	"AddSituations": preload("res://scripts/system/operations/AddSituations.gd"),
	"AddSkill": preload("res://scripts/system/operations/AddSkill.gd"),
	"AddSkillToSkillZone": preload("res://scripts/system/operations/AddSkillToSkillZone.gd"),
	"AddToArray": preload("res://scripts/system/operations/AddToArray.gd"),
	"AndFunc": preload("res://scripts/system/operations/AndFunc.gd"),
	"ApplyCardKeywords": preload("res://scripts/system/operations/ApplyCardKeywords.gd"),
	"ArrayDifference": preload("res://scripts/system/operations/ArrayDifference.gd"),
	"ArrayLength": preload("res://scripts/system/operations/ArrayLength.gd"),
	"AskPlayerNumber": preload("res://scripts/system/operations/AskPlayerNumber.gd"),
	"AskPlayerOption": preload("res://scripts/system/operations/AskPlayerOption.gd"),
	"AskPlayersSecretOption": preload("res://scripts/system/operations/AskPlayersSecretOption.gd"),
	"AwakenSkill": preload("res://scripts/system/operations/AwakenSkill.gd"),
	"BoardHasEffect": preload("res://scripts/system/operations/BoardHasEffect.gd"),
	"BuildCard": preload("res://scripts/system/operations/BuildCard.gd"),
	"BuildEffect": preload("res://scripts/system/operations/BuildEffect.gd"),
	"CalculateNumber": preload("res://scripts/system/operations/CalculateNumber.gd"),
	"CanGainMagic": preload("res://scripts/system/operations/CanGainMagic.gd"),
	"CancelPendingAction": preload("res://scripts/system/operations/CancelPendingAction.gd"),
	"CardCountsPower": preload("res://scripts/system/operations/CardCountsPower.gd"),
	"CardHasEffect": preload("res://scripts/system/operations/CardHasEffect.gd"),
	"ChangePlOrder": preload("res://scripts/system/operations/ChangePlOrder.gd"),
	"CloneObject": preload("res://scripts/system/operations/CloneObject.gd"),
	"CloseCard": preload("res://scripts/system/operations/CloseCard.gd"),
	"CloseTimePoint": preload("res://scripts/system/operations/CloseTimePoint.gd"),
	"CompareNumber": preload("res://scripts/system/operations/CompareNumber.gd"),
	"Counter": preload("res://scripts/system/operations/Counter.gd"),
	"CreateBaseNumber": preload("res://scripts/system/operations/CreateBaseNumber.gd"),
	"CreateBuff": preload("res://scripts/system/operations/CreateBuff.gd"),
	"CreateCard": preload("res://scripts/system/operations/CreateCard.gd"),
	"CreateFunc": preload("res://scripts/system/operations/CreateFunc.gd"),
	"DealPlayerCards": preload("res://scripts/system/operations/DealPlayerCards.gd"),
	"Defeat": preload("res://scripts/system/operations/Defeat.gd"),
	"Deploy": preload("res://scripts/system/operations/Deploy.gd"),
	"DiscardPlayedCards": preload("res://scripts/system/operations/DiscardPlayedCards.gd"),
	"DoNothing": preload("res://scripts/system/operations/DoNothing.gd"),
	"DrawCardByCard": preload("res://scripts/system/operations/DrawCardByCard.gd"),
	"DrawCardByIndex": preload("res://scripts/system/operations/DrawCardByIndex.gd"),
	"DrawCardFromPlDeckToHand": preload("res://scripts/system/operations/DrawCardFromPlDeckToHand.gd"),
	"EditCardAttributes": preload("res://scripts/system/operations/EditCardAttributes.gd"),
	"EditCardCost": preload("res://scripts/system/operations/EditCardCost.gd"),
	"EditCardPower": preload("res://scripts/system/operations/EditCardPower.gd"),
	"EditDataNumber": preload("res://scripts/system/operations/EditDataNumber.gd"),
	"EditLives": preload("res://scripts/system/operations/EditLives.gd"),
	"EditLocationBenefit": preload("res://scripts/system/operations/EditLocationBenefit.gd"),
	"EditLocationMagic": preload("res://scripts/system/operations/EditLocationMagic.gd"),
	"EditMagic": preload("res://scripts/system/operations/EditMagic.gd"),
	"EditMapAreaMoveCost": preload("res://scripts/system/operations/EditMapAreaMoveCost.gd"),
	"EditMapAreaScore": preload("res://scripts/system/operations/EditMapAreaScore.gd"),
	"EditNumAndReturn": preload("res://scripts/system/operations/EditNumAndReturn.gd"),
	"EditPendingAction": preload("res://scripts/system/operations/EditPendingAction.gd"),
	"EditPower": preload("res://scripts/system/operations/EditPower.gd"),
	"EditScore": preload("res://scripts/system/operations/EditScore.gd"),
	"EmitTimePoint": preload("res://scripts/system/operations/EmitTimePoint.gd"),
	"EndGame": preload("res://scripts/system/operations/EndGame.gd"),
	"FilterByProperty": preload("res://scripts/system/operations/FilterByProperty.gd"),
	"FindPlayerArrayContaining": preload("res://scripts/system/operations/FindPlayerArrayContaining.gd"),
	"FlipCardFace": preload("res://scripts/system/operations/FlipCardFace.gd"),
	"ForFunc": preload("res://scripts/system/operations/ForFunc.gd"),
	"ForeachFunc": preload("res://scripts/system/operations/ForeachFunc.gd"),
	"GetActivatingEff": preload("res://scripts/system/operations/GetActivatingEff.gd"),
	"GetActivePlayersId": preload("res://scripts/system/operations/GetActivePlayersId.gd"),
	"GetAllPlayersId": preload("res://scripts/system/operations/GetAllPlayersId.gd"),
	"GetAreaRoundParticipants": preload("res://scripts/system/operations/GetAreaRoundParticipants.gd"),
	"GetAreaRoundWinners": preload("res://scripts/system/operations/GetAreaRoundWinners.gd"),
	"GetAttackPrintedCost": preload("res://scripts/system/operations/GetAttackPrintedCost.gd"),
	"GetAttackPrintedPower": preload("res://scripts/system/operations/GetAttackPrintedPower.gd"),
	"GetBuffByNameFrArr": preload("res://scripts/system/operations/GetBuffByNameFrArr.gd"),
	"GetByTag": preload("res://scripts/system/operations/GetByTag.gd"),
	"GetCardAttributes": preload("res://scripts/system/operations/GetCardAttributes.gd"),
	"GetCardByIndexFrArr": preload("res://scripts/system/operations/GetCardByIndexFrArr.gd"),
	"GetCardsByAttributesFrArr": preload("res://scripts/system/operations/GetCardsByAttributesFrArr.gd"),
	"GetCardsByNameFrArr": preload("res://scripts/system/operations/GetCardsByNameFrArr.gd"),
	"GetCardsByTagFrArr": preload("res://scripts/system/operations/GetCardsByTagFrArr.gd"),
	"GetCurrentRound": preload("res://scripts/system/operations/GetCurrentRound.gd"),
	"GetDataNumber": preload("res://scripts/system/operations/GetDataNumber.gd"),
	"GetDictionaryValue": preload("res://scripts/system/operations/GetDictionaryValue.gd"),
	"GetEffSourceCard": preload("res://scripts/system/operations/GetEffSourceCard.gd"),
	"GetEffectNumber": preload("res://scripts/system/operations/GetEffectNumber.gd"),
	"GetEffectUsingNums": preload("res://scripts/system/operations/GetEffectUsingNums.gd"),
	"GetEffectiveLocationBenefit": preload("res://scripts/system/operations/GetEffectiveLocationBenefit.gd"),
	"GetEventPrintedScore": preload("res://scripts/system/operations/GetEventPrintedScore.gd"),
	"GetEvents": preload("res://scripts/system/operations/GetEvents.gd"),
	"GetExtremeByProperty": preload("res://scripts/system/operations/GetExtremeByProperty.gd"),
	"GetGameDataValue": preload("res://scripts/system/operations/GetGameDataValue.gd"),
	"GetLocation": preload("res://scripts/system/operations/GetLocation.gd"),
	"GetLocationBenefit": preload("res://scripts/system/operations/GetLocationBenefit.gd"),
	"GetLocationMagic": preload("res://scripts/system/operations/GetLocationMagic.gd"),
	"GetLocationMapArea": preload("res://scripts/system/operations/GetLocationMapArea.gd"),
	"GetMapAreaBuffs": preload("res://scripts/system/operations/GetMapAreaBuffs.gd"),
	"GetMapAreaByName": preload("res://scripts/system/operations/GetMapAreaByName.gd"),
	"GetMapAreaScore": preload("res://scripts/system/operations/GetMapAreaScore.gd"),
	"GetMapAreaScoreNeedWin": preload("res://scripts/system/operations/GetMapAreaScoreNeedWin.gd"),
	"GetMapDataValue": preload("res://scripts/system/operations/GetMapDataValue.gd"),
	"GetMoveCost": preload("res://scripts/system/operations/GetMoveCost.gd"),
	"GetMoveTargetLocation": preload("res://scripts/system/operations/GetMoveTargetLocation.gd"),
	"GetNumOfPlInMapArea": preload("res://scripts/system/operations/GetNumOfPlInMapArea.gd"),
	"GetObjectsByNameFrArr": preload("res://scripts/system/operations/GetObjectsByNameFrArr.gd"),
	"GetPendingActionValue": preload("res://scripts/system/operations/GetPendingActionValue.gd"),
	"GetPhaseOrder": preload("res://scripts/system/operations/GetPhaseOrder.gd"),
	"GetPlAttacksOutGame": preload("res://scripts/system/operations/GetPlAttacksOutGame.gd"),
	"GetPlBuffsOutGame": preload("res://scripts/system/operations/GetPlBuffsOutGame.gd"),
	"GetPlBuffsSide": preload("res://scripts/system/operations/GetPlBuffsSide.gd"),
	"GetPlCommandSpellOutGame": preload("res://scripts/system/operations/GetPlCommandSpellOutGame.gd"),
	"GetPlCommandSpellSide": preload("res://scripts/system/operations/GetPlCommandSpellSide.gd"),
	"GetPlDeckSide": preload("res://scripts/system/operations/GetPlDeckSide.gd"),
	"GetPlDiscardSide": preload("res://scripts/system/operations/GetPlDiscardSide.gd"),
	"GetPlIdUsingEff": preload("res://scripts/system/operations/GetPlIdUsingEff.gd"),
	"GetPlMasterOutGame": preload("res://scripts/system/operations/GetPlMasterOutGame.gd"),
	"GetPlMasterSide": preload("res://scripts/system/operations/GetPlMasterSide.gd"),
	"GetPlOthersOutGame": preload("res://scripts/system/operations/GetPlOthersOutGame.gd"),
	"GetPlOthersSide": preload("res://scripts/system/operations/GetPlOthersSide.gd"),
	"GetPlServantOutGame": preload("res://scripts/system/operations/GetPlServantOutGame.gd"),
	"GetPlServantSide": preload("res://scripts/system/operations/GetPlServantSide.gd"),
	"GetPlSkillsOutGame": preload("res://scripts/system/operations/GetPlSkillsOutGame.gd"),
	"GetPlSkillsSide": preload("res://scripts/system/operations/GetPlSkillsSide.gd"),
	"GetPlayerBuffs": preload("res://scripts/system/operations/GetPlayerBuffs.gd"),
	"GetPlayerCommandSpell": preload("res://scripts/system/operations/GetPlayerCommandSpell.gd"),
	"GetPlayerDataValue": preload("res://scripts/system/operations/GetPlayerDataValue.gd"),
	"GetPlayerDeck": preload("res://scripts/system/operations/GetPlayerDeck.gd"),
	"GetPlayerDiscard": preload("res://scripts/system/operations/GetPlayerDiscard.gd"),
	"GetPlayerHandCards": preload("res://scripts/system/operations/GetPlayerHandCards.gd"),
	"GetPlayerIdsByDataValue": preload("res://scripts/system/operations/GetPlayerIdsByDataValue.gd"),
	"GetPlayerLives": preload("res://scripts/system/operations/GetPlayerLives.gd"),
	"GetPlayerLocationBenefit": preload("res://scripts/system/operations/GetPlayerLocationBenefit.gd"),
	"GetPlayerMaster": preload("res://scripts/system/operations/GetPlayerMaster.gd"),
	"GetPlayerMasterSkills": preload("res://scripts/system/operations/GetPlayerMasterSkills.gd"),
	"GetPlayerName": preload("res://scripts/system/operations/GetPlayerName.gd"),
	"GetPlayerPlayedCards": preload("res://scripts/system/operations/GetPlayerPlayedCards.gd"),
	"GetPlayerPowerBreakdown": preload("res://scripts/system/operations/GetPlayerPowerBreakdown.gd"),
	"GetPlayerServant": preload("res://scripts/system/operations/GetPlayerServant.gd"),
	"GetPlayerServantSkills": preload("res://scripts/system/operations/GetPlayerServantSkills.gd"),
	"GetPlayerTimePoints": preload("res://scripts/system/operations/GetPlayerTimePoints.gd"),
	"GetPlayerTotalPower": preload("res://scripts/system/operations/GetPlayerTotalPower.gd"),
	"GetPlayersField": preload("res://scripts/system/operations/GetPlayersField.gd"),
	"GetPlayersInMapArea": preload("res://scripts/system/operations/GetPlayersInMapArea.gd"),
	"GetPlayersInSameArea": preload("res://scripts/system/operations/GetPlayersInSameArea.gd"),
	"GetPlsInLocation": preload("res://scripts/system/operations/GetPlsInLocation.gd"),
	"GetPrintedNum": preload("res://scripts/system/operations/GetPrintedNum.gd"),
	"GetPrintedNums": preload("res://scripts/system/operations/GetPrintedNums.gd"),
	"GetProperty": preload("res://scripts/system/operations/GetProperty.gd"),
	"GetRankByDataNumber": preload("res://scripts/system/operations/GetRankByDataNumber.gd"),
	"GetRoundBattleWins": preload("res://scripts/system/operations/GetRoundBattleWins.gd"),
	"GetSharedAttackAttribute": preload("res://scripts/system/operations/GetSharedAttackAttribute.gd"),
	"GetSituationPrintedMagic": preload("res://scripts/system/operations/GetSituationPrintedMagic.gd"),
	"GetSituations": preload("res://scripts/system/operations/GetSituations.gd"),
	"GetSkillPrintedCost": preload("res://scripts/system/operations/GetSkillPrintedCost.gd"),
	"GetSkillPrintedPower": preload("res://scripts/system/operations/GetSkillPrintedPower.gd"),
	"Has": preload("res://scripts/system/operations/Has.gd"),
	"HasAttribute": preload("res://scripts/system/operations/HasAttribute.gd"),
	"HideTrueName": preload("res://scripts/system/operations/HideTrueName.gd"),
	"IfElseFunc": preload("res://scripts/system/operations/IfElseFunc.gd"),
	"IfFunc": preload("res://scripts/system/operations/IfFunc.gd"),
	"IsEngaged": preload("res://scripts/system/operations/IsEngaged.gd"),
	"IsInArray": preload("res://scripts/system/operations/IsInArray.gd"),
	"IsNull": preload("res://scripts/system/operations/IsNull.gd"),
	"IsTrueNameReleased": preload("res://scripts/system/operations/IsTrueNameReleased.gd"),
	"Location": preload("res://scripts/system/operations/Location.gd"),
	"LogExists": preload("res://scripts/system/operations/LogExists.gd"),
	"LogFieldValues": preload("res://scripts/system/operations/LogFieldValues.gd"),
	"ManageBuff": preload("res://scripts/system/operations/ManageBuff.gd"),
	"MapAreaHasEffect": preload("res://scripts/system/operations/MapAreaHasEffect.gd"),
	"MatchFunc": preload("res://scripts/system/operations/MatchFunc.gd"),
	"MergeArrays": preload("res://scripts/system/operations/MergeArrays.gd"),
	"ModifyAttackPowerByAttribute": preload("res://scripts/system/operations/ModifyAttackPowerByAttribute.gd"),
	"Move": preload("res://scripts/system/operations/Move.gd"),
	"MoveLocation": preload("res://scripts/system/operations/MoveLocation.gd"),
	"NotFunc": preload("res://scripts/system/operations/NotFunc.gd"),
	"OrFunc": preload("res://scripts/system/operations/OrFunc.gd"),
	"PayMagic": preload("res://scripts/system/operations/PayMagic.gd"),
	"PlayAttack": preload("res://scripts/system/operations/PlayAttack.gd"),
	"PlaySkill": preload("res://scripts/system/operations/PlaySkill.gd"),
	"PlayedCards": preload("res://scripts/system/operations/PlayedCards.gd"),
	"PlayerBuffsHaveEffect": preload("res://scripts/system/operations/PlayerBuffsHaveEffect.gd"),
	"QueryLog": preload("res://scripts/system/operations/QueryLog.gd"),
	"QueueOptionalEffectForPlayers": preload("res://scripts/system/operations/QueueOptionalEffectForPlayers.gd"),
	"RandomFloat": preload("res://scripts/system/operations/RandomFloat.gd"),
	"RandomInt": preload("res://scripts/system/operations/RandomInt.gd"),
	"RecordLog": preload("res://scripts/system/operations/RecordLog.gd"),
	"RefillHand": preload("res://scripts/system/operations/RefillHand.gd"),
	"RegisterObjectEffects": preload("res://scripts/system/operations/RegisterObjectEffects.gd"),
	"ReleaseTrueName": preload("res://scripts/system/operations/ReleaseTrueName.gd"),
	"RemoveDefeat": preload("res://scripts/system/operations/RemoveDefeat.gd"),
	"RemoveFromArray": preload("res://scripts/system/operations/RemoveFromArray.gd"),
	"RemoveFromBoard": preload("res://scripts/system/operations/RemoveFromBoard.gd"),
	"ReshuffleDiscard": preload("res://scripts/system/operations/ReshuffleDiscard.gd"),
	"RestoreLocationBenefits": preload("res://scripts/system/operations/RestoreLocationBenefits.gd"),
	"RestoreLocationPlNumLimits": preload("res://scripts/system/operations/RestoreLocationPlNumLimits.gd"),
	"RestoreMapAreaMoveFlags": preload("res://scripts/system/operations/RestoreMapAreaMoveFlags.gd"),
	"RestrictAbilities": preload("res://scripts/system/operations/RestrictAbilities.gd"),
	"ScheduleEffectOnTimePoint": preload("res://scripts/system/operations/ScheduleEffectOnTimePoint.gd"),
	"SetBattleResult": preload("res://scripts/system/operations/SetBattleResult.gd"),
	"SetCardConcealed": preload("res://scripts/system/operations/SetCardConcealed.gd"),
	"SetDictionaryValue": preload("res://scripts/system/operations/SetDictionaryValue.gd"),
	"SetLocation": preload("res://scripts/system/operations/SetLocation.gd"),
	"SetLocationPlNumLimit": preload("res://scripts/system/operations/SetLocationPlNumLimit.gd"),
	"SetMapAreaCanMoveTo": preload("res://scripts/system/operations/SetMapAreaCanMoveTo.gd"),
	"SetPlayerData": preload("res://scripts/system/operations/SetPlayerData.gd"),
	"SetProperty": preload("res://scripts/system/operations/SetProperty.gd"),
	"ShowCards": preload("res://scripts/system/operations/ShowCards.gd"),
	"ShowMessage": preload("res://scripts/system/operations/ShowMessage.gd"),
	"ShuffleArray": preload("res://scripts/system/operations/ShuffleArray.gd"),
	"StoreValue": preload("res://scripts/system/operations/StoreValue.gd"),
	"SumLogData": preload("res://scripts/system/operations/SumLogData.gd"),
	"SyncPower": preload("res://scripts/system/operations/SyncPower.gd"),
	"Tag": preload("res://scripts/system/operations/Tag.gd"),
	"UnregisterObjectEffects": preload("res://scripts/system/operations/UnregisterObjectEffects.gd"),
	"TransferObjectEffects": preload("res://scripts/system/operations/TransferObjectEffects.gd"),
	"When": preload("res://scripts/system/operations/When.gd"),
	"WhileFunc": preload("res://scripts/system/operations/WhileFunc.gd"),
	"ZeroAttributePower": preload("res://scripts/system/operations/ZeroAttributePower.gd")
}

static func registered_script(key:Variant):
	if not key is String or not AllOperations.TABLE.has(key):
		return null
	return _REGISTERED_SCRIPTS.get(AllOperations.TABLE[key].get("class", ""))

# Script identity 而非文件名/类名相似度；派生脚本覆盖 exec 也不获得权限。
static func registered_callable_script(callback:Callable):
	if not callback.is_valid() or callback.get_method() != &"exec" or callback.get_unbound_arguments_count() != 0:
		return null
	var receiver = callback.get_object()
	if receiver == null:
		return null
	var script = receiver.get_script()
	for key in AllOperations.TABLE:
		if is_same(registered_script(key), script):
			return script
	return null



# 录制/恢复会话使用独立副本；空字符串保留原有单机路径。
static var session_data_dir: String = ""


#外部文件的根目录：编辑器里是项目根 res://，导出后是可执行文件所在目录
static func get_base_dir() -> String:
	if OS.has_feature("editor"):
		return "res://"
	return OS.get_executable_path().get_base_dir()


#把相对路径(如 data/masters)解析到外部根目录下；res:// user:// 与绝对路径原样返回
static func resolve_path(p:String) -> String:
	if p.begins_with("res://") or p.begins_with("user://") or p.is_absolute_path():
		return p
	return get_base_dir().path_join(p)


#resolve_path 的反向：把完整路径还原成相对外部根目录的路径(如 data/masters/...)
static func relative_path(p:String) -> String:
	var base := get_base_dir()
	if p.begins_with(base):
		return p.substr(base.length()).trim_prefix("/")
	return ProjectSettings.localize_path(p).trim_prefix("res://")


static func get_data_dir() -> String:
	if not session_data_dir.is_empty():
		return session_data_dir
	return resolve_path(DATA_DIR_NAME)


static func get_card_backs_dir() -> String:
	return get_data_dir().path_join("card_backs")

#图片缓存，避免同一张图反复读盘解码。{路径 : Texture2D}
static var _texture_cache:Dictionary = {}


#统一的图片加载入口。外部 data 里新丢进来的图没有 .import 记录，
#load() 在导出后会失败，所以先试 load()(命中编辑器导入缓存/包内资源)，
#失败再用 Image 运行时读盘。两条路都失败返回 null，调用方自行决定是否留空。
static func load_texture(path:String) -> Texture2D:
	if path == "":
		return null
	if _texture_cache.has(path):
		return _texture_cache[path]
	var tex:Texture2D = null
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			tex = res
	if tex == null:
		#运行时读盘：支持玩家自行放入的、未经 Godot 导入的图片
		var img := Image.new()
		if img.load(path) == OK:
			tex = ImageTexture.create_from_image(img)
	if tex != null:
		_texture_cache[path] = tex
	return tex


#图片是否可用。取代散落各处的 ResourceLoader.exists()——
#外部未导入的图 ResourceLoader.exists() 为 false 但实际能读，只看它会漏掉玩家自加的图
static func texture_exists(path:String) -> bool:
	if path == "":
		return false
	if _texture_cache.has(path):
		return true
	if ResourceLoader.exists(path):
		return true
	return FileAccess.file_exists(path)


#把下划线命名的 func_name 转成 PascalCase 类名（如 get_location -> GetLocation）。
static func func_name_to_class_name(func_name:String) -> String:
	var parts = func_name.split("_")
	var _class_name = ""
	for part in parts:
		if part == "":
			continue
		_class_name += part.substr(0, 1).to_upper() + part.substr(1)
	return _class_name


#把 JSON 数字字典解析成 BaseNumber。JSON 里的数字一律解析成 float，
#整数值要还原成 int，否则 is_float 会全部判成 true。
static func load_number(number:Dictionary):
	var raw = number["number"]
	if raw is float and raw == floor(raw) and !number.get("is_float", false):
		raw = int(raw)
	var num = BaseNumber.new(raw, number["can_change"], number["is_pure_number"])
	return num


#各类对象共有的可选声明，所有建对象的加载入口都调用这一处，字段支持不会在各类卡之间分叉：
#  values       对象的命名数据（{名字: 数字声明 或 普通值}，数字声明按 load_number 解析）
#  alias_names  "同时名为/视为"的别名
#  faces        双面卡各面的数据（只对卡牌有意义），格式与这类牌单张的 JSON 相同
static func load_object_extras(obj, data:Dictionary) -> void:
	if obj == null or data == null:
		return
	if data.get("values") is Dictionary:
		var values:Dictionary = {}
		for key in data["values"].keys():
			var raw = data["values"][key]
			values[key] = load_number(raw) if raw is Dictionary and raw.has("number") else raw
		obj._values = values
	if data.get("alias_names") is Array:
		obj._alias_names = (data["alias_names"] as Array).duplicate()
	if obj is BaseCard and data.get("faces") is Array:
		obj._faces = (data["faces"] as Array).duplicate(true)
	#词条(如真名解放)与初始区域：卡自己显式声明，没声明就没有；牌库引用、内联卡、御主附带卡共用这一处。
	if obj is BaseCard:
		if data.has("keywords"):
			obj._keywords = (data["keywords"] as Array).duplicate()
		if data.has("initial_zone"):
			obj._initial_zone = str(data["initial_zone"])
		if data.has("initial_count"):
			obj._initial_count = maxi(0, int(data["initial_count"]))
	#打出规则与卡面提示属于手牌（攻击/技能）的声明。
	if obj is BaseCard and "_play_requirements" in obj:
		if data.has("play_requirements"):
			obj._play_requirements = (data["play_requirements"] as Array).duplicate(true)
		if data.has("shown_notes"):
			obj._shown_notes = (data["shown_notes"] as Array).duplicate(true)
		if data.has("need_extra_play"):
			obj._need_extra_play = bool(data["need_extra_play"])

# 校验加载器收到的动作来源。模板加载传 null；runtime 加载必须传服务登记的句柄。
# 这里不读取 current_token，也不把缺失来源升级成当前局来源。
static func validate_source_context(source_context:Variant) -> Dictionary:
	if source_context == null:
		return {"ok":true, "context":null, "reason":&"template"}
	if not source_context is SessionContext:
		return {"ok":false, "context":null, "reason":&"unbound_origin"}
	var status:Dictionary = SessionGeneration.validate_context(source_context)
	if not status.get("ok", false):
		return {"ok":false, "context":null, "reason":status.get("reason", &"stale_session")}
	return {"ok":true, "context":source_context, "reason":&"current"}


# 将已完成字段/效果的卡发布到对象表。模板保持未绑定，runtime 卡及其 effect/func
# 必须属于同一 token；发布前不允许出现半合法卡。
static func finalize_loaded_card(card:BaseCard, source_context:Variant = null) -> bool:
	if card == null:
		return false
	var source:Dictionary = validate_source_context(source_context)
	if not source.ok:
		_discard_loaded_card(card)
		return false
	if source.context == null:
		if not GameData.objects.has(card):
			card.add_object()
		return true
	var context:SessionContext = source.context
	var binding:Dictionary = SessionGeneration.bind_origin(card, context.token(), context.origin())
	if not binding.get("ok", false):
		_discard_loaded_card(card)
		return false
	for effect in card._effects:
		if not effect is BaseEffect:
			_discard_loaded_card(card)
			return false
		var effect_status:Dictionary = effect.runtime_source_status()
		if not effect_status.get("ok", false) or effect.runtime_context() == null or not is_same(effect.runtime_context().token(), context.token()):
			_discard_loaded_card(card)
			return false
		effect.from = card
		effect.register_numbers_to_source()
	card.add_object()
	return true


static func _discard_loaded_card(card:BaseCard) -> void:
	if card == null:
		return
	GameData.objects.erase(card)
	for effect in card._effects:
		if effect is BaseEffect:
			GameData.objects.erase(effect)
			GameData.effects.erase(effect)

# source_context 缺省时仅加载模板；显式已验来源才新建本局 runtime。
static func load_effects(effects:Array, from, source_context:Variant = null) -> Array:
	# power_query 是另一只读解释器的数据，不把它误当本解释器的 func_name。
	for descriptor in effects:
		if not descriptor is Dictionary or not _func_list_supported(descriptor.get("funcs", [])) or not _options_supported(descriptor.get("options", [])):
			return []
	var source:Dictionary = validate_source_context(source_context)
	if not source.ok:
		return []
	if source.context != null:
		if not _runtime_descriptors_supported(effects, []) or not BaseFunc._value_source_valid(effects, source.context, []) or not BaseFunc._value_source_valid(from, source.context, []):
			return []
	var eff_arr:Array
	for eff:Dictionary in effects:
		var priority = eff["priority"] as int
		var is_pure_passive = eff["is_pure_passive"] as bool
		var is_residue = eff["is_residue"] as bool
		var numbers = eff["effect_numbers"] as Array
		var nums:Array
		for number:Dictionary in numbers:
			var num = load_number(number)
			nums.append(num)
		
		var effect = BaseEffect.new(eff["effect_name"], eff["time_points"], priority, is_pure_passive, is_residue)
		if source_context != null:
			var binding:Dictionary = SessionGeneration.bind_origin(effect, source.context.token(), source.context.origin())
			if not binding.get("ok", false) or not effect.bind_runtime_context(binding.get("context")):
				return []
		#强制结算与来源牌激活是独立条件；未声明时保持原有纯被动语义。
		effect._need_activate = bool(eff.get("need_activate", not is_pure_passive))
		effect._allow_while_concealed = bool(eff.get("allow_while_concealed", false))
		effect._source_bound = bool(eff.get("source_bound", false))
		effect._expire_time_points = (eff.get("expire_time_points", []) as Array).duplicate()
		effect._shown_name = eff.get("shown_effect_name", "")
		effect._power_query = eff.get("power_query", []).duplicate(true)
		#time_points默认OR(命中任一即触发)；写 require_all_time_points:true 改为AND，
		#要求列出的时点全部同时成立（如"高潮回合"且"自己的行动阶段"）
		effect._time_points_require_all = eff.get("require_all_time_points", false)
		effect.from = from
		effect.set_numbers(nums)
		effect._using_numbers = nums
		#效果级消耗：数字形状(有number键)解析成BaseNumber；其他资源形状(有type键，如令咒
		#{"type":"command_spell","amount":1})原样保留字典，由EffectManager.pay_effect_cost
		#按type解释。两种都不匹配视为没声明，不在加载期报错
		var cost_data = eff.get("cost")
		if cost_data is Dictionary and cost_data.has("number"):
			effect._cost = load_number(cost_data)
		elif cost_data is Dictionary and cost_data.has("type"):
			effect._cost = cost_data
		#每局限一次的声明(触发记录由EffectManager写进玩家的used_once_effects)
		effect._once_per_game = bool(eff.get("once_per_game", false))
		#手动发动的声明(如令咒)：不自动询问，由玩家主动点击发动；
		#这类效果的 time_points 是"允许发动的时机窗口"
		effect._is_manual = bool(eff.get("is_manual", false))
		#from 和 numbers 都已就绪，此时才能把数字登记到所属对象上
		effect.register_numbers_to_source()
		#多选效果(如令咒三选一、宝石魔术选项)：options非空时每个选项自带一套funcs，
		#写法与效果的funcs完全一致，玩家选中哪几个才结算哪几个，效果自身的_funcs留空不用。
		#max_choices不写默认1(单选)；填>1限定一次提交最多用几次(次数加总)；填-1不限数量随便选。
		#reset_counts_each_round/consumes_source_resource声明这组用量限制的生命周期与资源绑定，
		#quantity_range让某个选项在选中的同时还要求玩家额外选一个范围内的数量(如"弃1-3张")
		if eff.has("options"):
			effect._options = load_effect_options(eff["options"], effect)
			effect._max_choices = eff.get("max_choices", 1) as int
			effect._max_total_uses = eff.get("max_total_uses", -1) as int
			effect._reset_counts_each_round = eff.get("reset_counts_each_round", false) as bool
			effect._consumes_source_resource = eff.get("consumes_source_resource", false) as bool
		else:
			for f in load_funcs(eff["funcs"], effect):
				effect.add_func(f)
	
		eff_arr.append(effect)
	
	return eff_arr


#解析一组选项声明为运行时选项数组。效果的 options 与"给玩家排队可选效果"共用这一份解析：
#两份实现会让字段支持范围慢慢分叉（一边认 select_location、另一边不认），所以只留一条路径。
#option 的每个字段都是数据声明的能力，解析器不解释规则含义、也不给默认行为
static func load_effect_options(options_data:Array, effect:BaseEffect, source_context:Variant = null) -> Array:
	var source:Dictionary = _func_factory_source(effect, source_context)
	if not source.ok or not _options_supported(options_data) or (source.context != null and not BaseFunc._value_source_valid(options_data, source.context, [])):
		return []
	var opts:Array = []
	for opt:Dictionary in options_data:
		var opt_dict := {
			"shown_option_name": opt.get("shown_option_name", ""),
			"funcs": load_funcs(opt.get("funcs", []), effect, source.context),
			"max_uses": opt.get("max_uses", -1) as int
		}
		if opt.has("quantity_range"):
			opt_dict["quantity_range"] = opt["quantity_range"]
		if opt.has("allow_cancel"):
			opt_dict["allow_cancel"] = bool(opt["allow_cancel"])
		#选项声明"还要玩家挑几张具体的牌"：source 是取牌的玩家区域键名(如 hand_cards)，
		#min/max 是可挑张数范围。挑哪几张属于玩家输入，不写死在数据里
		if opt.has("select_cards"):
			opt_dict["select_cards"] = opt["select_cards"]
		# 位置选择同样是选项级声明：起点筛选和落点容量由数据/UI提供，不污染常规移动规则。
		if opt.has("select_location"):
			opt_dict["select_location"] = opt["select_location"]
		# 选择玩家目标：candidates 是一段 func 描述（求值得到候选玩家id数组），
		# min/max 是可选人数。候选集由数据算出来，引擎不写死"同战区/在场"这类范围
		if opt.has("select_players"):
			opt_dict["select_players"] = opt["select_players"]
		# 选项标签：供"某选项被用过"这类事实查询匹配（如令咒的获得魔力选项）。
		# 用标签而不是选项下标，避免选项顺序/文案变动后规则静默失效
		if opt.has("tags"):
			opt_dict["tags"] = opt["tags"]
		#发动前置条件：每项的 funcs 仍用与效果体完全相同的解析器，message 仅在失败时提示发动者。
		if opt.has("activation_requirements"):
			var requirements:Array = []
			for requirement:Dictionary in opt["activation_requirements"]:
				requirements.append({
					"message": str(requirement.get("message", "")),
					"funcs": load_funcs(requirement.get("funcs", []), effect, source.context)
				})
			opt_dict["activation_requirements"] = requirements
		opts.append(opt_dict)
	return opts


#把 JSON 的 funcs 数组解析成 BaseFunc 数组，不挂到任何效果上。
#load_effects 解析效果自身的 funcs 与每个多选一选项的 funcs 都复用这一份逻辑
static func load_funcs(funcs:Array, effect:BaseEffect, source_context:Variant = null) -> Array:
	if not _func_list_supported(funcs):
		return []
	var source:Dictionary = _func_factory_source(effect, source_context)
	if not source.ok or not _runtime_descriptors_supported(funcs, []) or (source.context != null and not BaseFunc._value_source_valid(funcs, source.context, [])):
		return []
	var result:Array = []
	for _func:Dictionary in funcs:
		var condition = _func.get("condition", null)
		var var_index = _func.get("var_index", -1)
		var paras = _func.get("parameters", []) as Array

		if _func.has("func_name"):
			var key = _func["func_name"] as String
			var script = registered_script(key)
			if script == null:
				return []
			var func_instance = script.new()
			var main_callable = Callable(func_instance, "exec")
			var eff_func = BaseFunc.new(main_callable, paras, var_index, condition)
			#Callable 不会保活实例，必须由 func 自己持有引用，否则加载完就被释放
			eff_func._instance = func_instance
			eff_func._name = key
			if source.context != null:
				var binding:Dictionary = SessionGeneration.bind_origin(eff_func, source.context.token(), source.context.origin())
				if not binding.get("ok", false) or not eff_func.bind_runtime_context(binding.get("context")):
					return []
			result.append(eff_func)

		else:
			# 未登记方法没有兼容回退；整个批次已在构造之前预检。
			return []
	return result


# 子函数/选项只能继承已验 effect 来源；显式参数不能为旧/未绑定 effect 补票。
static func _func_factory_source(effect:BaseEffect, source_context:Variant) -> Dictionary:
	if effect == null:
		return {"ok":false, "context":null}
	var parent:SessionContext = effect.runtime_context()
	if source_context == null and parent == null:
		return {"ok":true, "context":null}
	if not effect.runtime_source_status().get("ok", false):
		return {"ok":false, "context":null}
	if source_context != null:
		if not SessionGeneration.validate_context(source_context).get("ok", false):
			return {"ok":false, "context":null}
		if not is_same(source_context.token(), parent.token()):
			return {"ok":false, "context":null}
	return {"ok":true, "context":parent}

# 只认现有 TABLE 已声明的 operation；不从相邻接口或方法名字猜能力。
# 原生 self_var/sub_func 尚无具名能力声明，模板可保存，runtime 不开放。
# 递归检查循环/选项/前置条件中的描述符；不 preload 尚不存在的类。
static func _options_supported(options:Variant) -> bool:
	if not options is Array:
		return false
	for option in options:
		if not option is Dictionary or not _func_list_supported(option.get("funcs", [])):
			return false
		var requirements = option.get("activation_requirements", [])
		if not requirements is Array:
			return false
		for requirement in requirements:
			if not requirement is Dictionary or not _func_list_supported(requirement.get("funcs", [])):
				return false
	return _runtime_descriptors_supported(options, [])

static func _func_list_supported(funcs:Variant) -> bool:
	if not funcs is Array:
		return false
	for descriptor in funcs:
		if not descriptor is Dictionary or not descriptor.has("func_name") or not descriptor.get("parameters", []) is Array:
			return false
	return _runtime_descriptors_supported(funcs, [])

static func _runtime_descriptors_supported(value, visited:Array) -> bool:
	if value is Callable:
		return BaseFunc._callable_capability_valid(value, visited)
	if value is BaseFunc:
		return value.execution_capability_status().get("ok", false)
	if value is Array or value is Dictionary:
		for seen in visited:
			if is_same(seen, value):
				return true
		visited.append(value)
	if value is Array:
		for item in value:
			if not _runtime_descriptors_supported(item, visited):
				return false
	elif value is Dictionary:
		if value.has("sub_func"):
			return false
		if value.has("func_name"):
			var key = value["func_name"]
			if registered_script(key) == null or not BaseFunc.interpreter_entry_status(key).get("ok", false):
				return false
		for key in value:
			if key is Callable or not _runtime_descriptors_supported(key, visited) or not _runtime_descriptors_supported(value[key], visited):
				return false
	return true


#卡类型 → 通用卡背文件名。卡背是通用的，按类型分类放在 data/card_backs 里
static var CARD_BACK_FILES = {
	"master" : "master_card_back.png",
	"servant" : "servant_card_back.png",
	"attack" : "attack_card_back.png",
	"skill" : "skill_card_back.png",
	"event" : "event_card_back.png",
	"situation" : "situation_card_back.png",
	"climax_situation" : "climax_situation_card_back.png",
	"command_spell" : "command_spell_card_back.png",
	"upgrade_skill" : "upgrade_skill_card_back.png"
}


#真正把卡"放进"某个数组的 operation，以及该数组在 parameters 里的位置。
#只有这些才算放入动作：get_player_deck 之类的查询只是把数组取进变量表，取来也可能是为了
#抽牌/数张数/查牌，出现它本身不代表往里放（阴炁弹就是取数组后把自己移出游戏）
static var ARRAY_INSERT_FUNCS := {
	"add_to_array": 1,        # exec(item, arr, index)        -> arr 是目标
	"draw_card_by_card": 2,   # exec(card, from, to, to_index)-> to 是目标
	"draw_card_by_index": 1,  # exec(from, to, ...)           -> to 是目标
}
#把玩家牌库取进变量表的查询 operation
static var DECK_QUERY_FUNCS := ["get_player_deck"]


#某张卡（按 JSON 里的名字）是否会被 effects_data 里的某条效果放进玩家牌库。
#判据是数据流追踪而不是"出现了某个函数名"：
#  ① 先找出 get_player_deck 把牌库存进了哪些 var_index；
#  ② 再看是否有放入型 operation 的【目标数组参数位】引用了这些 var_index。
#两者都满足才算入牌库。循环体（for_func）里的放入动作要递归进去看（葛木的蛇就在 for_func 内）。
#"要加入牌库会在效果中说明"是本项目既有约定，这里只读效果声明，不在数据里另加冗余字段。
#只能在加载阶段用原始 JSON 调用：BaseFunc 现在也保留 _name，但数据流追踪仍只看 JSON 声明
#（运行时 _name 只用于执行日志，不参与「是否会放进牌库」的判断）
static func is_card_inserted_to_deck(card_name:String, effects_data:Array) -> bool:
	if card_name == "":
		return false
	for eff in effects_data:
		if not (eff is Dictionary):
			continue
		var funcs = eff.get("funcs", [])
		if not (funcs is Array):
			continue
		#这条效果是否提到了这张卡；不提就不是搬它
		if not _funcs_mention_name(funcs, card_name):
			continue
		var deck_vars := {}
		_collect_deck_vars(funcs, deck_vars)
		if deck_vars.is_empty():
			continue
		if _funcs_insert_into_vars(funcs, deck_vars):
			return true
	return false


#递归收集"把玩家牌库存进变量表"的 var_index
static func _collect_deck_vars(funcs:Array, out:Dictionary) -> void:
	for f in funcs:
		if not (f is Dictionary):
			continue
		if DECK_QUERY_FUNCS.has(str(f.get("func_name", ""))):
			var vi = f.get("var_index", -1)
			if typeof(vi) == TYPE_FLOAT or typeof(vi) == TYPE_INT:
				if int(vi) != -1:
					out[int(vi)] = true
		for nested in _nested_func_lists(f):
			_collect_deck_vars(nested, out)


#递归判断是否有放入型 operation 的目标数组参数位指向 deck_vars 里的变量
static func _funcs_insert_into_vars(funcs:Array, deck_vars:Dictionary) -> bool:
	for f in funcs:
		if not (f is Dictionary):
			continue
		var fname := str(f.get("func_name", ""))
		if ARRAY_INSERT_FUNCS.has(fname):
			var target_pos:int = ARRAY_INSERT_FUNCS[fname]
			var ps = f.get("parameters", [])
			if ps is Array and target_pos < ps.size():
				var target = ps[target_pos]
				if target is Dictionary and target.has("self_var"):
					if deck_vars.has(int(target["self_var"])):
						return true
		for nested in _nested_func_lists(f):
			if _funcs_insert_into_vars(nested, deck_vars):
				return true
	return false


#递归判断这批 func 描述里是否出现过某个名字字面量
static func _funcs_mention_name(funcs:Array, target_name:String) -> bool:
	for f in funcs:
		if not (f is Dictionary):
			continue
		for p in (f.get("parameters", []) if f.get("parameters") is Array else []):
			if typeof(p) == TYPE_STRING and str(p) == target_name:
				return true
		for nested in _nested_func_lists(f):
			if _funcs_mention_name(nested, target_name):
				return true
	return false


#取出一个 func 描述的参数里嵌套的 func 描述数组（如 for_func / if_func 的循环体、分支体）
static func _nested_func_lists(f:Dictionary) -> Array:
	var result:Array = []
	for p in (f.get("parameters", []) if f.get("parameters") is Array else []):
		if p is Array:
			var only_func_descs := true
			for item in p:
				if not (item is Dictionary and item.has("func_name")):
					only_func_descs = false
					break
			if only_func_descs and not p.is_empty():
				result.append(p)
		elif p is Dictionary and p.has("func_name"):
			result.append([p])
	return result


#放大分类的三档取值。card=可放大+完整卡牌说明；avatar=可放大但只显示名字；
#token=可放大该小图标，只显示名字与层数，不走卡牌式说明
const ZOOM_KIND_CARD := "card"
const ZOOM_KIND_AVATAR := "avatar"
const ZOOM_KIND_TOKEN := "token"
static var ZOOM_KINDS := [ZOOM_KIND_CARD, ZOOM_KIND_AVATAR, ZOOM_KIND_TOKEN]


#解析某张图片的放大分类。每条图片路径旁边自带一条 zoom_kind 声明它是什么：
#  多图对象(御主同时有头像/御主卡/令咒卡)写 "<图片字段>_zoom_kind"，
#  单图对象直接写同级 "zoom_kind"。
#刻意不做兜底猜测：声明缺失就返回空串，UI 据此不给放大——
#靠字段名或尺寸去猜会在外部玩家新增卡时静默猜错，宁可不放大也不要错分类。
static func resolve_zoom_kind(data:Dictionary, img_field:String) -> String:
	var kind := str(data.get(img_field + "_zoom_kind", ""))
	if kind == "":
		kind = str(data.get("zoom_kind", ""))
	if !ZOOM_KINDS.has(kind):
		return ""
	return kind


#解析卡背路径：JSON里card_back_img非空就用同目录的特殊卡背，否则用data/card_backs里的通用卡背。
#每个json都可以写card_back_img覆盖通用卡背，不写就用类型对应的通用卡背
static func resolve_card_back(card_back_img:String, dir_path:String, type_name:String) -> String:
	if card_back_img != "":
		return dir_path + "/" + card_back_img
	if !CARD_BACK_FILES.has(type_name):
		return ""
	#与其余卡数据一致，走外部 data 目录：导出后玩家能看到并替换卡背
	return get_card_backs_dir().path_join(CARD_BACK_FILES[type_name])


#附带物数据声明的份数：缺省 1；0 表示一张都不生成；负数或非整数是数据错误，报错并按 0 处理（不猜）
static func thing_count(thing) -> int:
	if not thing is Dictionary or not thing.has("count"):
		return 1
	var raw = thing["count"]
	if (raw is int or (raw is float and raw == floor(raw))) and int(raw) >= 0:
		return int(raw)
	push_error("附带物 count 必须是非负整数：" + str(thing.get("thing_name", "")) + " = " + str(raw))
	return 0


#把御主物品卡(黑泥、宝石、天之衣等)接上它展示的那个buff。对应关系写在数据里
#(物品卡的relate_buff字段)，没声明就不关联——不靠名字后缀之类的猜法，
#猜错会让"未激活"的遮罩静默盖到错误的卡上，比不盖更难发现。
#存的是buff实例引用：激活状态会变，渲染时读的必须是此刻的值
static func bind_things_to_buffs(things_data:Array, thing_objs:Array, buffs:Array) -> void:
	#数据按 count 展开成与加载结果一一对应的列表（加载器同口径）
	var expanded:Array = []
	for data in things_data:
		for copy_i in thing_count(data):
			expanded.append(data)
	things_data = expanded
	for i in range(mini(things_data.size(), thing_objs.size())):
		var buff_name: String = str((things_data[i] as Dictionary).get("relate_buff", ""))
		if buff_name == "":
			continue
		for buff in buffs:
			if str(buff._name) == buff_name:
				thing_objs[i]._relate_buff = buff
				break
