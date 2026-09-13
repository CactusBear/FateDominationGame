extends RefCounted
class_name BaseObject


#游戏对象是纯数据，不进场景树，所以用RefCounted而不是Node，
#否则每个对象都会成为无人释放的孤立节点

#所属对象(卡牌的御主、效果的卡牌等)。所有者反过来也持有本对象(_effects等)，
#两边都用强引用就会形成循环引用，RefCounted永远不释放，所以这里存弱引用。
#外部照常用 obj.from 读写，弱引用由下面的setter/getter透明处理
var from : set = set_from, get = get_from
var _from_ref:WeakRef
#非Object的from(如id、字符串)没法做弱引用，直接存
var _from_value
#这个对象的展示图属于哪一类：card/avatar/token（取值见 LoadHelper.ZOOM_KINDS）。
#由 JSON 里紧跟图片路径的 zoom_kind 声明，空串表示未声明——UI 据此不给放大。
#放在最基类：卡、御主、从者、buff 都要被展示，各子类无需重复定义
var _zoom_kind:String = ""
#多图对象(御主同时有头像/御主卡/令咒卡)按图片字段各记一档：{图片字段名:分类}。
#UI 展示某张图时用 get_zoom_kind(该图片字段) 取，取不到再回退到 _zoom_kind
var _zoom_kinds:Dictionary = {}


#取某张展示图的放大分类。img_field 传该图在 JSON/运行时的字段名（如 "_header_img"）；
#不传则取对象默认分类。返回空串表示未声明，UI 不应给它放大
func get_zoom_kind(img_field:String = "") -> String:
	if img_field != "" and _zoom_kinds.has(img_field):
		return str(_zoom_kinds[img_field])
	return _zoom_kind


func set_from(value):
	if value is Object:
		_from_ref = weakref(value)
		_from_value = null
	else:
		_from_ref = null
		_from_value = value


func get_from():
	if _from_ref != null:
		return _from_ref.get_ref()
	return _from_value


var _name:String
#用于界面显示的名称，为空时回退到_name
var _shown_name:String
var tags:Array
var tag:Dictionary = {
	"tag_name" : "",
	"from" : -1
}

var numbers:Array#[BaseNumber]
#本对象上各效果自带的数字，{效果名 : [BaseNumber]}。
#下标只在单个效果内部有意义，所以增删效果不会让已有的引用错位
var effect_numbers:Dictionary#{String : Array}

#RefCounted在没人引用时自动释放，所以del()只需把对象从各登记表里摘掉
func del():
	GameData.objects.erase(self)
	if self is BaseEffect:
		GameData.effects.erase(self)
		EffectManager.unregister_effect(self)

func add_object():
	GameData.objects.append(self)

func set_numbers(nums:Array):
	numbers = nums

func get_shown_name() -> String:
	if _shown_name == "":
		return _name
	return _shown_name


#按效果名+下标取出本对象上某个效果自带的数字，取不到返回null
func get_effect_number(effect_name:String, index:int = 0):
	if !effect_numbers.has(effect_name):
		return null
	var nums = effect_numbers[effect_name] as Array
	if index < 0 or index >= nums.size():
		return null
	return nums[index]

const MASTER_TAG = "master_tag"
const SERVANT_TAG = "servant_tag"
const SKILL_TAG = "skill_tag"
const ATTACK_TAG = "attack_tag"
const EFFECT_TAG = "effect_tag"
const SITUATION_TAG = "situation_tag"
const EVENT_TAG = "event_tag"
const BUFF_TAG = "buff_tag"
const OTHERS_TAG = "others_tag"
