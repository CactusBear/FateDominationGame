extends Node
class_name BaseObject


var from
var _name:String
var tags:Array
var tag:Dictionary = {
	"tag_name" : "",
	"from" : -1
}

var numbers:Array#[int]

func del():
	self.free()

func add_object():
	GameData.objects.append(self)

func set_numbers(nums:Array):
	numbers = nums

const MASTER_TAG = "master_tag"
const SERVANT_TAG = "servant_tag"
const SKILL_TAG = "skill_tag"
const ATTACK_TAG = "attack_tag"
const EFFECT_TAG = "effect_tag"
const SITUATION_TAG = "situation_tag"
const EVENT_TAG = "event_tag"
const BUFF_TAG = "buff_tag"
const OTHERS_TAG = "others_tag"
