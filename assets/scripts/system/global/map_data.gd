extends Node



const MAGIC_WORKSHOP_0 = {"magic_workshop" : 0}
const MAGIC_WORKSHOP_1 = {"magic_workshop" : 1}
const MAGIC_WORKSHOP_2 = {"magic_workshop" : 2}
const MAGIC_WORKSHOP_3 = {"magic_workshop" : 3}
const MAGIC_WORKSHOP_4 = {"magic_workshop" : 4}

const MIYAMA_0 = {"miyama" : 0}
const MIYAMA_1 = {"miyama" : 1}
const MIYAMA_2 = {"miyama" : 2}

const SHINTO_0 = {"shinto" : 0}
const SHINTO_1 = {"shinto" : 1}
const SHINTO_2 = {"shinto" : 2}

const SCOUT_0 = {"scout" : 0}
const SCOUT_1 = {"scout" : 1}

const MOON_CELL_0 = {"moon_cell" : 0}
const MOON_CELL_1 = {"moon_cell" : 1}
const MOON_CELL_2 = {"moon_cell" : 2}
const MOON_CELL_3 = {"moon_cell" : 3}

const MAGIC_WORKSHOP = "magic_workshop"
const MIYAMA = "miyama"
const SHINTO = "shinto"
const SCOUT = "scout"
const MOON_CELL = "moon_cell"

const MA_TO_MI = "ma_to_mi"
const MI_TO_SH = "mi_to_sh"
const SH_TO_SC = "sh_to_sc"

var location_data:Dictionary = {
	MAGIC_WORKSHOP : [
		-1,-1,-1,-1,[]
	],
	MIYAMA : [
		-1,-1,[]
	],
	SHINTO : [
		-1,-1,[]
	],
	SCOUT : [
		-1,[]
	],
	MOON_CELL : [
		-1,-1,-1,[]
	]
}

#地点魔力
var magic_workshop_magic = [
	2,1,1,1,0
]

var miyama_magic = [
	0,0,0
]

var shinto_magic = [
	0,0,0
]

var scout_magic = [
	0,0
]

var moon_cell_magic = [
	0,0,0,0
]

var location_magic:Dictionary


#地利
var magic_workshop_benefit = [
	0,0,0,0,0
]

var miyama_benefit = [
	3,1,0
]

var shinto_benefit = [
	3,1,0	
]

var scout_benefit = [
	0,0
]

var moon_cell_benefit = [
	4,2,1,0
]

var location_benefit:Dictionary


#地点战果
var magic_workshop_score =0
var miyama_score = 2
var shinto_score = 3
var scout_score = 2
var moon_cell_score = 3

var location_score:Dictionary

var score_need_win = {
	MAGIC_WORKSHOP : true,
	MIYAMA : true,
	SHINTO : true,
	SCOUT : false,
	MOON_CELL : true
}

#局势牌
var situation_cards = []

#事件牌
var event_cards = {
	MAGIC_WORKSHOP : [],
	MIYAMA : [],
	SHINTO : [],
	SCOUT : [],
	MOON_CELL : []
}

#移动cost
var move_cost = {
	MA_TO_MI : 1,
	MI_TO_SH : 2,
	SH_TO_SC : 2
}


#场地buff
var area_buffs = {
	MAGIC_WORKSHOP : [],
	MIYAMA : [],
	SHINTO : [],
	SCOUT : [],
	MOON_CELL : []
}


func _init():
	location_magic = {
		MAGIC_WORKSHOP : magic_workshop_magic,
		MIYAMA : miyama_magic,
		SHINTO : shinto_magic,
		SCOUT : scout_magic,
		MOON_CELL : moon_cell_magic
	}
	
	location_benefit = {
		MAGIC_WORKSHOP : magic_workshop_benefit,
		MIYAMA : miyama_benefit,
		SHINTO : shinto_benefit,
		SCOUT : scout_benefit,
		MOON_CELL : moon_cell_benefit
	}
	
	location_score = {
		MAGIC_WORKSHOP : magic_workshop_score,
		MIYAMA : miyama_score,
		SHINTO : shinto_score,
		SCOUT : scout_score,
		MOON_CELL : moon_cell_score
	}
	
