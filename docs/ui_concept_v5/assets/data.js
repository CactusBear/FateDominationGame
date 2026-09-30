window.FD_DATA={
 "cards": {
  "physical_attack_0_3": {
   "name": "强打",
   "kind": "攻击",
   "img": "assets/c_physical_attack_0_3.jpg",
   "cost": 0,
   "power": 3,
   "attrs": [
    "力量"
   ],
   "effects": [],
   "back": "b_attack"
  },
  "magic_blast_0_3": {
   "name": "中位魔术",
   "kind": "攻击",
   "img": "assets/c_magic_blast_0_3.jpg",
   "cost": 0,
   "power": 3,
   "attrs": [
    "魔术"
   ],
   "effects": [],
   "back": "b_attack"
  },
  "luck": {
   "name": "幸运",
   "kind": "攻击",
   "img": "assets/c_luck.jpg",
   "cost": 0,
   "power": 4,
   "attrs": [
    "特殊"
   ],
   "effects": [
    "战斗阶段：你本回合无视【直接败北】效果"
   ],
   "back": "b_attack"
  },
  "mana_resistance": {
   "name": "对魔力",
   "kind": "技能",
   "img": "assets/c_mana_resistance.jpg",
   "cost": 3,
   "power": 3,
   "attrs": [
    "特殊"
   ],
   "effects": [
    "宝具绽放 - 被动/战斗阶段：若你于本回合打出了你战斗中魔力消耗最高的宝具攻击，获得1点战果。若其消耗≥4，你额外获得1点战果",
    "魔术抗性 - 战斗阶段：将与你位于同一战场的交战对手控制的魔术属性攻击威力设置为0"
   ],
   "back": "b_skill"
  },
  "wind_barrier": {
   "name": "风王结界",
   "kind": "技能",
   "img": "assets/c_wind_barrier.jpg",
   "cost": 4,
   "power": 4,
   "attrs": [
    "魔术",
    "宝具"
   ],
   "effects": [
    "若你的真名隐藏，此牌的魔力消耗-2",
    "战斗阶段：将与你进行战斗对手的力量攻击威力变为0"
   ],
   "back": "b_skill"
  },
  "excalibur": {
   "name": "誓约胜利之剑",
   "kind": "技能",
   "img": "assets/c_excalibur.jpg",
   "cost": 8,
   "power": 12,
   "attrs": [
    "力量",
    "宝具"
   ],
   "effects": [
    "【真名解放】战斗阶段：高潮回合时，合计威力+4",
    "若你赢得第11回合的战斗，获得游戏胜利"
   ],
   "back": "b_skill"
  },
  "sv_artoria": {
   "name": "阿尔托莉雅·潘德拉贡",
   "kind": "从者概览",
   "img": "assets/c_sv_artoria.jpg",
   "attrs": [],
   "effects": [],
   "cls": "Saber"
  },
  "ms_rin": {
   "name": "远坂凛",
   "kind": "御主",
   "img": "assets/c_ms_rin.jpg",
   "effects": [
    "宝石魔术·聚宝 - 游戏开始时获得【宝石】",
    "绝对服从的命令 - 你必须于第一回合使用一枚令咒。",
    "绝对服从的命令 - 若你以该令咒获得了魔力，战斗阶段结束后，你失去4点魔力"
   ],
   "attrs": []
  },
  "jewel_sword_zelretch": {
   "name": "宝石剑泽尔里奇",
   "kind": "升华技",
   "img": "assets/c_jewel_sword_zelretch.jpg",
   "cost": 0,
   "power": 6,
   "attrs": [
    "魔术"
   ],
   "effects": [
    "被动 - 你的魔术基础牌和【阴炁弹】的威力+2",
    "行动阶段 - 获得本回合所有玩家花费的魔力。战斗结束后，将此牌移除游戏",
    "战斗结束后 - 将此牌移除游戏"
   ],
   "back": "b_skill"
  },
  "yin": {
   "name": "阴炁弹",
   "kind": "御主附加牌",
   "img": "assets/c_yin.jpg",
   "cost": 0,
   "power": 1,
   "attrs": [
    "魔术"
   ],
   "effects": [
    "每局游戏限一次，关闭后移除游戏"
   ],
   "need_extra_play": true
  },
  "jewel": {
   "name": "宝石",
   "kind": "御主附加牌",
   "img": "assets/c_jewel.jpg",
   "attrs": [],
   "effects": [
    "行动阶段：选择一项本回合没有选择过的选项",
    "高潮回合的行动阶段：可以选择相同的选项，每个选项至多3次，共计9次"
   ],
   "level": 10
  },
  "cs": {
   "name": "令咒",
   "kind": "令咒",
   "img": "assets/c_cs.jpg",
   "attrs": [],
   "effects": [
    "行动阶段：获得4魔力",
    "行动阶段：合计威力+2\n获胜后获得2战果",
    "行动阶段：从新都或深山町移动至任意位置，无视交战状态"
   ],
   "options": [
    {
     "text": "行动阶段：获得4魔力",
     "magic": 4
    },
    {
     "text": "行动阶段：合计威力+2\n获胜后获得2战果",
     "power": 2
    },
    {
     "text": "行动阶段：从新都或深山町移动至任意位置，无视交战状态",
     "allowed_origin_areas": [
      "新都",
      "深山町"
     ]
    }
   ]
  },
  "ley_line": {
   "name": "地脉",
   "kind": "事件",
   "img": "assets/c_ley_line.jpg",
   "score": 2,
   "attrs": [],
   "effects": [
    "位于此战场的玩家在此战场发生战斗后获得2点魔力"
   ]
  },
  "strength_test": {
   "name": "强度测验",
   "kind": "事件",
   "img": "assets/c_strength_test.jpg",
   "score": 3,
   "attrs": [],
   "effects": [
    "力量攻击于此战场获得威力+3"
   ]
  },
  "outrage": {
   "name": "怒不可遏",
   "kind": "局势",
   "img": "assets/c_outrage.jpg",
   "magic": 2,
   "attrs": [],
   "effects": [
    "力量攻击于深山町和新都获得威力+2"
   ]
  }
 },
 "heads": {
  "emiya_shirou": {
   "name": "卫宫士郎",
   "img": "assets/h_emiya_shirou.png"
  },
  "tohsaka_rin": {
   "name": "远坂凛",
   "img": "assets/h_tohsaka_rin.png"
  },
  "matou_shinji": {
   "name": "间桐慎二",
   "img": "assets/h_matou_shinji.png"
  },
  "matou_sakura": {
   "name": "间桐樱",
   "img": "assets/h_matou_sakura.png"
  },
  "illyasviel_von_einzbern": {
   "name": "伊莉雅斯菲尔",
   "img": "assets/h_illyasviel_von_einzbern.png"
  },
  "kotomine_kirei": {
   "name": "言峰绮礼",
   "img": "assets/h_kotomine_kirei.png"
  },
  "kuzuki_souichirou": {
   "name": "葛木宗一郎",
   "img": "assets/h_kuzuki_souichirou.png"
  }
 },
 "servants": {
  "artoria_pendragon": {
   "name": "阿尔托莉雅·潘德拉贡",
   "cls": "saber",
   "img": "assets/s_artoria_pendragon.jpg"
  },
  "emiya": {
   "name": "卫宫",
   "cls": "archer",
   "img": "assets/s_emiya.jpg"
  },
  "cu_chulainn": {
   "name": "库·丘林",
   "cls": "lancer",
   "img": "assets/s_cu_chulainn.jpg"
  },
  "medusa": {
   "name": "美杜莎",
   "cls": "rider",
   "img": "assets/s_medusa.jpg"
  },
  "medea": {
   "name": "美狄亚",
   "cls": "caster",
   "img": "assets/s_medea.jpg"
  },
  "sasaki_kojirou": {
   "name": "佐佐木小次郎",
   "cls": "assassin",
   "img": "assets/s_sasaki_kojirou.jpg"
  },
  "heracles": {
   "name": "赫拉克勒斯",
   "cls": "berserker",
   "img": "assets/s_heracles.jpg"
  }
 },
 "map": {
  "areas": [
   {
    "id": "workshop",
    "name": "魔术工房",
    "bg": "assets/z_workshop.jpg",
    "score": 0,
    "move": 1,
    "battle": false,
    "seats": [
     {
      "magic": 2,
      "benefit": 0,
      "limit": 1
     },
     {
      "magic": 1,
      "benefit": 0,
      "limit": 1
     },
     {
      "magic": 1,
      "benefit": 0,
      "limit": 1
     },
     {
      "magic": 1,
      "benefit": 0,
      "limit": 1
     },
     {
      "magic": 0,
      "benefit": 0,
      "limit": -1,
      "extra": true
     }
    ]
   },
   {
    "id": "miyama",
    "name": "深山町",
    "bg": "assets/z_miyama.jpg",
    "score": 2,
    "move": 2,
    "battle": true,
    "seats": [
     {
      "magic": 0,
      "benefit": 3,
      "limit": 1
     },
     {
      "magic": 0,
      "benefit": 1,
      "limit": 1
     },
     {
      "magic": 0,
      "benefit": 0,
      "limit": -1
     }
    ]
   },
   {
    "id": "shinto",
    "name": "新都",
    "bg": "assets/z_shinto.jpg",
    "score": 3,
    "move": 2,
    "battle": true,
    "seats": [
     {
      "magic": 0,
      "benefit": 3,
      "limit": 1
     },
     {
      "magic": 0,
      "benefit": 1,
      "limit": 1
     },
     {
      "magic": 0,
      "benefit": 0,
      "limit": -1
     }
    ]
   },
   {
    "id": "scout",
    "name": "侦察",
    "bg": "assets/z_scout.jpg",
    "score": 2,
    "move": 0,
    "battle": false,
    "seats": [
     {
      "magic": 0,
      "benefit": 0,
      "limit": 1
     },
     {
      "magic": 0,
      "benefit": 0,
      "limit": -1,
      "extra": true
     }
    ]
   }
  ]
 },
 "skills": [
  "mana_resistance",
  "wind_barrier",
  "excalibur"
 ],
 "upgrade": "jewel_sword_zelretch",
 "rules": {
  "magic_limit": 12,
  "hand_limit": 3,
  "skill_zone_magic_limit": 8,
  "play_limit": 2,
  "regular_play_min": 2,
  "total_rounds": 11,
  "command_spell_limit": 3,
  "concealable_kinds": [
   "攻击"
  ],
  "event_placements": [
   {
    "area": "深山町",
    "concealed": false
   },
   {
    "area": "新都",
    "concealed": true
   }
  ],
  "phases": [
   {
    "id": "prepare",
    "name": "准备阶段"
   },
   {
    "id": "outpost",
    "name": "前哨阶段"
   },
   {
    "id": "action",
    "name": "行动阶段"
   },
   {
    "id": "battle",
    "name": "战斗阶段"
   }
  ],
  "climax_keep": {
   "8": 4,
   "9": 3,
   "10": 2
  }
 },
 "_source": "由 data/** JSON 与 map_data.gd / game_data.gd / game_progress.gd 的数值导出，改数据后重新生成"
};
