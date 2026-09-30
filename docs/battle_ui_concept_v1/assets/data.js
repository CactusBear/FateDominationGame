window.FD={
 "masters": [
  {
   "id": "emiya_shirou",
   "name": "卫宫士郎",
   "header": "assets/cards/00001_emiya_shirou_header.jpg",
   "card": "assets/cards/00001_emiya_shirou_cd.jpg",
   "effects": [
    "未熟 - 你的魔力初始值为2",
    "投影 - 将【干将·莫邪】加入你的技能区",
    "远离尘世的理想乡 - 当你首次被淘汰时你将失去所有的魔力来继续游戏"
   ],
   "upgrade": {
    "name": "必胜黄金之剑",
    "cost": 6,
    "power": 8,
    "attributes": [
     "strength",
     "noble_phantasm"
    ],
    "img": "assets/cards/00001_emiya_shirou_caliburn.jpg",
    "effects": [
     "被动 - 你的力量和敏捷属性的基本牌威力+2",
     "战斗阶段：此攻击在高潮回合威力+4"
    ]
   },
   "things": [],
   "attacks": []
  },
  {
   "id": "tohsaka_rin",
   "name": "远坂凛",
   "header": "assets/cards/00002_tohsaka_rin_header.jpg",
   "card": "assets/cards/00002_tohsaka_rin_cd.jpg",
   "effects": [
    "宝石魔术·聚宝 - 游戏开始时获得【宝石】",
    "绝对服从的命令 - 你必须于第一回合使用一枚令咒。否则于该回合结束失去一枚令咒。",
    "绝对服从的命令 - 若你以该令咒获得了魔力，战斗阶段结束后，你失去4点魔力"
   ],
   "upgrade": {
    "name": "宝石剑泽尔里奇",
    "cost": 0,
    "power": 6,
    "attributes": [
     "magic"
    ],
    "img": "assets/cards/00002_tohsaka_rin_jewel_sword_zelretch.jpg",
    "effects": [
     "被动 - 你的魔术基础牌和【阴炁弹】的威力+2",
     "行动阶段 - 获得本回合所有玩家花费的魔力。战斗结束后，将此牌移除游戏",
     "战斗结束后 - 将此牌移除游戏"
    ]
   },
   "things": [
    {
     "name": "宝石",
     "img": "assets/cards/00002_tohsaka_rin_jewels.jpg",
     "effects": []
    }
   ],
   "attacks": [
    {
     "name": "阴炁弹",
     "cost": 0,
     "power": 1,
     "attributes": [
      "magic"
     ],
     "img": "assets/cards/00002_tohsaka_rin_yin_qi_bullet.jpg",
     "effects": [
      "每局游戏限一次，关闭后移除游戏"
     ]
    }
   ]
  },
  {
   "id": "matou_shinji",
   "name": "间桐慎二",
   "header": "assets/cards/00003_matou_shinji_header.jpg",
   "card": "assets/cards/00003_matou_shinji_cd.jpg",
   "effects": [
    "吸魔命令 - 进入深山町时，获得1点魔力",
    "无用之人 - 游戏开始时，获得【伪臣之书】",
    "小丑 - 当你战败时，失去一枚令咒"
   ],
   "upgrade": {
    "name": "圣杯核心",
    "cost": 0,
    "power": 0,
    "attributes": [],
    "img": "assets/cards/00003_matou_shinji_grail_core.jpg",
    "effects": [
     "此牌在第八回合结束后，并且莎士比亚是你的从者时生效。你失去【伪臣之书】",
     "若莎士比亚是你的第一名从者，你位于深山町时合计威力+12，当你获得X点战果时，所有位于深山町的对手失去X点战果",
     "若莎士比亚并非你的第一名从者，你获得8点战果"
    ]
   },
   "things": [
    {
     "name": "伪臣之书",
     "img": "assets/cards/00003_matou_shinji_false_servant_book.jpg",
     "effects": []
    }
   ],
   "attacks": []
  },
  {
   "id": "matou_sakura",
   "name": "间桐樱",
   "header": "assets/cards/00004_matou_sakura_header.jpg",
   "card": "assets/cards/00004_matou_sakura_cd.jpg",
   "effects": [
    "欠损容器 - 回合结束时，若你的战果低于所有其他玩家且你的第一名御主不是【间桐慎二】，激活【黑泥】",
    "此世全部之恶 - 第8回合结束时，若你的战果排名不为第一，激活【被污染的圣杯】"
   ],
   "upgrade": {
    "name": "腐蚀",
    "cost": 0,
    "power": 0,
    "attributes": [],
    "img": "assets/cards/00004_matou_sakura_corrosion.jpg",
    "effects": []
   },
   "things": [
    {
     "name": "黑泥",
     "img": "assets/cards/00004_matou_sakura_black_mud.jpg",
     "effects": []
    },
    {
     "name": "被污染的圣杯",
     "img": "assets/cards/00004_matou_sakura_corrupted_grail.jpg",
     "effects": []
    }
   ],
   "attacks": []
  },
  {
   "id": "illyasviel_von_einzbern",
   "name": "伊莉雅斯菲尔",
   "header": "assets/cards/00005_illyasviel_von_einzbern_header.jpg",
   "card": "assets/cards/00005_illyasviel_von_einzbern_cd.jpg",
   "effects": [
    "人工生命体 - 你的魔力初始值为6",
    "圣杯容器 - 第八回合开始时，激活【天之衣】",
    "小圣杯 - 你打出攻击时所需的魔力消耗-1",
    "小圣杯 - 回合结束时，若你本回合打出的攻击均为暗置，获得1点魔力"
   ],
   "upgrade": {
    "name": "第三法",
    "cost": 0,
    "power": 0,
    "attributes": [
     "magic",
     "special"
    ],
    "img": "assets/cards/00005_illyasviel_von_einzbern_third_magic.jpg",
    "effects": [
     "解锁此技能后立刻从牌库，弃牌堆及手牌中移除所有力量牌",
     "被动 - 魔术和特殊属性牌的基本威力+2",
     "当局势牌为【天之杯】时，未被淘汰的玩家全部获胜"
    ]
   },
   "things": [
    {
     "name": "天之衣",
     "img": "assets/cards/00005_illyasviel_von_einzbern_heavenly_robe.jpg",
     "effects": []
    }
   ],
   "attacks": []
  },
  {
   "id": "kotomine_kirei",
   "name": "言峰绮礼",
   "header": "assets/cards/00006_kotomine_kirei_header.jpg",
   "card": "assets/cards/00006_kotomine_kirei_cd.jpg",
   "effects": [
    "两幅面孔 - 当从者真名隐藏时，你是【监督者】；其他情况下，你是【执行者】（包括且不限于你没有从者）"
   ],
   "upgrade": {
    "name": "恶的庇护者",
    "cost": 0,
    "power": 0,
    "attributes": [],
    "img": "assets/cards/00006_kotomine_kirei_evil_protector.jpg",
    "effects": [
     "当你为【监督者】时，战斗阶段：可【真名解放】使与你位于同一战场的一名玩家【败北】",
     "当你为【执行者】时，你的所有基本攻击牌威力+2且无视【败北】"
    ]
   },
   "things": [
    {
     "name": "监督者",
     "img": "assets/cards/00006_kotomine_kirei_overseer.jpg",
     "effects": []
    },
    {
     "name": "执行者",
     "img": "assets/cards/00006_kotomine_kirei_executor.jpg",
     "effects": []
    }
   ],
   "attacks": []
  },
  {
   "id": "kuzuki_souichirou",
   "name": "葛木宗一郎",
   "header": "assets/cards/00007_kuzuki_souichirou_header.jpg",
   "card": "assets/cards/00007_kuzuki_souichirou_cd.jpg",
   "effects": [
    "暗杀术 - 游戏开始时，将两张【蛇】加入你的牌库",
    "局外人 - 你无法通过部署于魔术工房获得魔力",
    "局外人 - 你以常规移动从魔术工房离开时-1移动成本",
    "局外人 - 每回合战斗阶段结束后，若你于该回合未获得战果，获得1点战果，若你同时是位于魔术工房的唯一玩家，改为获得2点战果"
   ],
   "upgrade": {
    "name": "完美呼吸",
    "cost": 0,
    "power": 0,
    "attributes": [
     "agility"
    ],
    "img": "assets/cards/00007_kuzuki_souichirou_perfect_breathing.jpg",
    "effects": [
     "解锁此技能后立刻从牌库，弃牌堆及手牌中移除所有魔术牌",
     "被动 - 迅捷基础牌威力+3",
     "你的【蛇】获得以下效果 - 被动/战斗阶段：花费6点魔力，将此牌加入你的攻击中"
    ]
   },
   "things": [],
   "attacks": [
    {
     "name": "蛇",
     "cost": 0,
     "power": 5,
     "attributes": [
      "strength",
      "agility"
     ],
     "img": "assets/cards/00007_kuzuki_souichirou_snake.jpg",
     "effects": []
    }
   ]
  }
 ],
 "servants": [
  {
   "id": "artoria_pendragon",
   "name": "阿尔托莉雅·潘德拉贡",
   "cls": "saber",
   "card": "assets/cards/00001_artoria_pendragon_cd.jpg",
   "skills": [
    {
     "name": "对魔力",
     "cost": 3,
     "power": 3,
     "attributes": [
      "special"
     ],
     "img": "assets/cards/00001_artoria_pendragon_mana_resistance.jpg",
     "effects": [
      "宝具绽放 - 被动/战斗阶段：若你于本回合打出了你战斗中魔力消耗最高的宝具攻击，获得1点战果。若其消耗≥4，你额外获得1点战果",
      "魔术抗性 - 战斗阶段：将与你位于同一战场的交战对手控制的魔术属性攻击威力设置为0"
     ]
    },
    {
     "name": "风王结界",
     "cost": 4,
     "power": 4,
     "attributes": [
      "magic",
      "noble_phantasm"
     ],
     "img": "assets/cards/00001_artoria_pendragon_wind_barrier.jpg",
     "effects": [
      "若你的真名隐藏，此牌的魔力消耗-2",
      "战斗阶段：将与你进行战斗对手的力量攻击威力变为0"
     ]
    },
    {
     "name": "誓约胜利之剑",
     "cost": 8,
     "power": 12,
     "attributes": [
      "strength",
      "noble_phantasm"
     ],
     "img": "assets/cards/00001_artoria_pendragon_excalibur.jpg",
     "effects": [
      "【真名解放】战斗阶段：高潮回合时，合计威力+4",
      "若你赢得第11回合的战斗，获得游戏胜利"
     ]
    }
   ]
  },
  {
   "id": "emiya",
   "name": "卫宫",
   "cls": "archer",
   "card": "assets/cards/00002_emiya_cd.jpg",
   "skills": [
    {
     "name": "炽天覆七重圆环",
     "cost": 2,
     "power": 4,
     "attributes": [
      "special"
     ],
     "img": "assets/cards/00002_emiya_seven_rings_of_blazing_heaven.jpg",
     "effects": [
      "战斗阶段：将同一战场所有对手的迅捷属性攻击威力变为0"
     ]
    },
    {
     "name": "伪·螺旋剑",
     "cost": 2,
     "power": 4,
     "attributes": [
      "agility",
      "noble_phantasm"
     ],
     "img": "assets/cards/00002_emiya_pseudo_spiral_sword.jpg",
     "effects": [
      "【真名解放】<每局游戏限一次>行动阶段：将你的地利变为3倍",
      "战斗阶段：若赢得本场战斗，获得4战果"
     ]
    },
    {
     "name": "无限剑制",
     "cost": 8,
     "power": 0,
     "attributes": [
      "special"
     ],
     "img": "assets/cards/00002_emiya_unlimited_blade_works.jpg",
     "effects": [
      "【真名解放】打出时：以你打出的牌、手牌、牌库和弃牌堆任意组建一组至多12张牌的手牌",
      "残留：你的常规出牌改为打出0~4张牌，你不能抽牌，当你的手牌数为0时，关闭此牌"
     ]
    }
   ]
  },
  {
   "id": "cu_chulainn",
   "name": "库·丘林",
   "cls": "lancer",
   "card": "assets/cards/00003_cu_chulainn_cd.jpg",
   "skills": [
    {
     "name": "战斗续行",
     "cost": 3,
     "power": 5,
     "attributes": [
      "agility",
      "special"
     ],
     "img": "assets/cards/00003_cu_chulainn_battle_continuation.jpg",
     "effects": [
      "行动阶段：移动至除魔术工房外的任意地点"
     ]
    },
    {
     "name": "突穿死翔之枪",
     "cost": 7,
     "power": 10,
     "attributes": [
      "agility",
      "noble_phantasm"
     ],
     "img": "assets/cards/00003_cu_chulainn_gae_bolg_piercing.jpg",
     "effects": [
      "【真名解放】战斗阶段：战斗阶段结束后，每与一名对手进行了战斗便获得1点战果。若你获得胜利，每名交战对手失去该数量的战果"
     ]
    },
    {
     "name": "穿刺死棘之枪",
     "cost": 3,
     "power": 6,
     "attributes": [
      "agility",
      "noble_phantasm"
     ],
     "img": "assets/cards/00003_cu_chulainn_gae_bolg_piercing_heart.jpg",
     "effects": [
      "【真名解放】打出时：此牌+2魔力消耗（可叠加）直至游戏结束",
      "贯穿心脏-战斗阶段：若仅有一名对手与你位于同一战场，令其【败北】"
     ]
    }
   ]
  },
  {
   "id": "medusa",
   "name": "美杜莎",
   "cls": "rider",
   "card": "assets/cards/00004_medusa_cd.jpg",
   "skills": [
    {
     "name": "骑乘",
     "cost": 3,
     "power": 0,
     "attributes": [
      "special"
     ],
     "img": "assets/cards/00004_medusa_riding.jpg",
     "effects": [
      "打出时：若此牌与一张基础攻击一同打出，抽一张牌",
      "坐骑召唤 - 行动阶段：打出至多3张基本威力为3或更低的手牌"
     ]
    },
    {
     "name": "骑英之缰绳",
     "cost": 9,
     "power": 8,
     "attributes": [
      "noble_phantasm"
     ],
     "img": "assets/cards/00004_medusa_bellerophon.jpg",
     "effects": [
      "【真名解放】行动阶段：移动到任一地点，若为战场，重新部署于该地点的2个地利，原地利的占领者失去该地利"
     ]
    },
    {
     "name": "石化之魔眼",
     "cost": 4,
     "power": 1,
     "attributes": [
      "special"
     ],
     "img": "assets/cards/00004_medusa_eyes_of_petrification.jpg",
     "effects": [
      "【真名解放】行动阶段：在战斗阶段开始前，若与你进行战斗的对手本回合没有打出/加入魔术属性攻击，则其【败北】"
     ]
    }
   ]
  },
  {
   "id": "medea",
   "name": "美狄亚",
   "cls": "caster",
   "card": "assets/cards/00005_medea_cd.jpg",
   "skills": [
    {
     "name": "阵地建造",
     "cost": 16,
     "power": 2,
     "attributes": [
      "magic"
     ],
     "img": "assets/cards/00005_medea_base_construction.jpg",
     "effects": [
      "此牌费用为X，X为16-（当前回合数×2）",
      "残留：当你部署于魔术工房时，获得1点魔力和2点战果"
     ]
    },
    {
     "name": "万符必应破戒",
     "cost": 3,
     "power": 0,
     "attributes": [
      "strength",
      "noble_phantasm"
     ],
     "img": "assets/cards/00005_medea_rule_breaker.jpg",
     "effects": [
      "【真名解放】<每局游戏限一次>行动阶段：你所在战场的一名玩家失去一枚令咒，若其原本只有一枚或更少的令咒，令其【败北】。若其原本没有令咒，你总威力+10"
     ]
    },
    {
     "name": "神言魔术式",
     "cost": 5,
     "power": 8,
     "attributes": [
      "magic"
     ],
     "img": "assets/cards/00005_medea_divine_words.jpg",
     "effects": [
      "【真名解放】战斗阶段：若你在战斗中失败，将一张被移除的【万符必应破戒】加入你的技能区"
     ]
    }
   ]
  },
  {
   "id": "sasaki_kojirou",
   "name": "佐佐木小次郎",
   "cls": "assassin",
   "card": "assets/cards/00006_sasaki_kojirou_cd.jpg",
   "skills": [
    {
     "name": "一之太刀",
     "cost": 5,
     "power": 7,
     "attributes": [
      "agility"
     ],
     "img": "assets/cards/00006_sasaki_kojirou_ichi_no_tachi.jpg",
     "effects": [
      "你拥有的魔力少于8点也可打出此牌",
      "战斗阶段：关闭此牌，然后从手牌打出一张力量基本攻击。若如此，获得2点魔力",
      "战斗阶段：关闭一名交战玩家至多一张基础攻击"
     ]
    },
    {
     "name": "二之太刀",
     "cost": 3,
     "power": 5,
     "attributes": [
      "agility"
     ],
     "img": "assets/cards/00006_sasaki_kojirou_ni_no_tachi.jpg",
     "effects": [
      "行动阶段：与你位于同一战场的对手无法使用【行动阶段】和【战斗阶段】能力（令咒为行动阶段能力）"
     ]
    },
    {
     "name": "三之太刀",
     "cost": 2,
     "power": 3,
     "attributes": [
      "agility"
     ],
     "img": "assets/cards/00006_sasaki_kojirou_san_no_tachi.jpg",
     "effects": [
      "你可于打出2张迅捷攻击时追加打出此牌",
      "燕返 - 若【一之太刀】和【二之太刀】同时位于战场时，则【真名解放】并合计威力+3"
     ]
    }
   ]
  },
  {
   "id": "heracles",
   "name": "赫拉克勒斯",
   "cls": "berserker",
   "card": "assets/cards/00007_heracles_cd.jpg",
   "skills": [
    {
     "name": "十二试炼",
     "cost": 1,
     "power": 5,
     "attributes": [
      "noble_phantasm"
     ],
     "img": "assets/cards/00007_heracles_twelve_labors_1.jpg",
     "effects": [
      "【真名解放】若你战败，获得3点战果并令此战斗的所有胜者分别失去3点战果，然后将此牌移除游戏并令你的其他【十二试炼】获得+3威力直至游戏结束"
     ]
    },
    {
     "name": "十二试炼",
     "cost": 1,
     "power": 5,
     "attributes": [
      "noble_phantasm"
     ],
     "img": "assets/cards/00007_heracles_twelve_labors_2.jpg",
     "effects": [
      "【真名解放】若你战败，获得3点战果并令此战斗的所有胜者分别失去3点战果，然后将此牌移除游戏并令你的其他【十二试炼】获得+3威力直至游戏结束"
     ]
    },
    {
     "name": "十二试炼",
     "cost": 1,
     "power": 5,
     "attributes": [
      "noble_phantasm"
     ],
     "img": "assets/cards/00007_heracles_twelve_labors_3.jpg",
     "effects": [
      "【真名解放】若你战败，获得3点战果并令此战斗的所有胜者分别失去3点战果，然后将此牌移除游戏并令你的其他【十二试炼】获得+3威力直至游戏结束"
     ]
    }
   ]
  }
 ],
 "events": [
  {
   "name": "遏制第三方威胁",
   "score": 2,
   "img": "assets/cards/ev_contain_third_party.jpg",
   "effects": [
    "基本威力≥4的攻击威力+1",
    "此战场胜者可恢复1枚令咒"
   ]
  },
  {
   "name": "协同",
   "score": 2,
   "img": "assets/cards/ev_cooperation.jpg",
   "effects": [
    "于此战场玩家，其所有攻击若至少一种属性相同则合计威力+4"
   ]
  },
  {
   "name": "铤而走险",
   "score": 4,
   "img": "assets/cards/ev_desperate_measure.jpg",
   "effects": [
    "战果倒数第一+12、倒数第二+8、倒数第三+4"
   ]
  },
  {
   "name": "命运之战",
   "score": 3,
   "img": "assets/cards/ev_fate_battle.jpg",
   "effects": [
    "此战场上基本威力1和2的攻击基本威力增加至5"
   ]
  },
  {
   "name": "光荣的决斗",
   "score": 2,
   "img": "assets/cards/ev_glorious_duel.jpg",
   "effects": [
    "力量攻击于此战场获得威力+2"
   ]
  },
  {
   "name": "归零地",
   "score": 3,
   "img": "assets/cards/ev_ground_zero.jpg",
   "effects": [
    "此战场的各个地利位置不提供地利"
   ]
  },
  {
   "name": "圣地",
   "score": 3,
   "img": "assets/cards/ev_holy_ground.jpg",
   "effects": [
    "魔术攻击于此战场获得威力+3"
   ]
  },
  {
   "name": "地脉",
   "score": 2,
   "img": "assets/cards/ev_ley_line.jpg",
   "effects": [
    "位于此战场的玩家在此战场发生战斗后获得2点魔力"
   ]
  },
  {
   "name": "占领高地",
   "score": 3,
   "img": "assets/cards/ev_occupy_high_ground.jpg",
   "effects": [
    "于此战场玩家计算战力时地利翻倍"
   ]
  },
  {
   "name": "固有结界",
   "score": 2,
   "img": "assets/cards/ev_reality_marble.jpg",
   "effects": [
    "所有玩家不能移动至此地点也不能离开此地点",
    "特殊攻击禁止打出"
   ]
  },
  {
   "name": "夺回伊莉雅",
   "score": 5,
   "img": "assets/cards/ev_rescue_illya.jpg",
   "effects": []
  },
  {
   "name": "祭祀之地",
   "score": 2,
   "img": "assets/cards/ev_sacrifice_ground.jpg",
   "effects": [
    "魔术攻击于此战场获得威力+2"
   ]
  },
  {
   "name": "偷袭",
   "score": 2,
   "img": "assets/cards/ev_sneak_attack.jpg",
   "effects": [
    "从者真名隐藏的玩家于此战场合计威力+5"
   ]
  },
  {
   "name": "强度测验",
   "score": 3,
   "img": "assets/cards/ev_strength_test.jpg",
   "effects": [
    "力量攻击于此战场获得威力+3"
   ]
  },
  {
   "name": "火力压制",
   "score": 3,
   "img": "assets/cards/ev_suppressive_fire.jpg",
   "effects": [
    "迅捷攻击于此战场获得威力+3"
   ]
  },
  {
   "name": "险恶地形",
   "score": 2,
   "img": "assets/cards/ev_treacherous_terrain.jpg",
   "effects": [
    "迅捷攻击于此战场获得威力+2"
   ]
  }
 ],
 "situations": [
  {
   "name": "新都之战",
   "magic": 2,
   "climax": false,
   "climax_round": 0,
   "img": "assets/cards/si_battle_of_shinto.jpg",
   "effects": [
    "于新都增加一张正面事件牌"
   ]
  },
  {
   "name": "暴风雨前的宁静",
   "magic": 2,
   "climax": false,
   "climax_round": 0,
   "img": "assets/cards/si_calm_before_storm.jpg",
   "effects": [
    "迅捷攻击于深山町和新都获得威力+2"
   ]
  },
  {
   "name": "安哥拉·曼纽的诅咒",
   "magic": 0,
   "climax": false,
   "climax_round": 0,
   "img": "assets/cards/si_curse_of_angra_mainyu.jpg",
   "effects": [
    "力量攻击于深山町和新都获得威力+1",
    "宝具禁止使用"
   ]
  },
  {
   "name": "身处地狱之门",
   "magic": 4,
   "climax": true,
   "climax_round": 10,
   "img": "assets/cards/si_gate_of_hell.jpg",
   "effects": [
    "高潮：剩余3+人。无法部署与进入新都和侦察，魔术工房仅限一人部署",
    "于深山町增加一张正面事件牌"
   ]
  },
  {
   "name": "天之杯",
   "magic": 6,
   "climax": true,
   "climax_round": 11,
   "img": "assets/cards/si_heavens_feel.jpg",
   "effects": [
    "高潮：剩余2+人。无法部署与进入新都和侦察，魔术工房仅限一人部署",
    "于深山町增加两张正面事件牌"
   ]
  },
  {
   "name": "对未来的憧憬",
   "magic": 0,
   "climax": false,
   "climax_round": 0,
   "img": "assets/cards/si_hope_for_future.jpg",
   "effects": [
    "位于深山町和新都的玩家，若其所有攻击至少有一种属性相同，则合计威力+3"
   ]
  },
  {
   "name": "深山町的杀人魔",
   "magic": 2,
   "climax": false,
   "climax_round": 0,
   "img": "assets/cards/si_killer_in_miyama.jpg",
   "effects": [
    "于深山町增加一张正面事件牌"
   ]
  },
  {
   "name": "命运之夜",
   "magic": 4,
   "climax": true,
   "climax_round": 9,
   "img": "assets/cards/si_night_of_fate.jpg",
   "effects": [
    "高潮：剩余4+人。于深山町和新都增加一张正面事件牌"
   ]
  },
  {
   "name": "怒不可遏",
   "magic": 2,
   "climax": false,
   "climax_round": 0,
   "img": "assets/cards/si_outrage.jpg",
   "effects": [
    "力量攻击于深山町和新都获得威力+2"
   ]
  },
  {
   "name": "完美的流动",
   "magic": 2,
   "climax": false,
   "climax_round": 0,
   "img": "assets/cards/si_perfect_flow.jpg",
   "effects": [
    "魔术攻击于深山町和新都获得威力+2"
   ]
  },
  {
   "name": "安哥拉·曼纽的阴影",
   "magic": 0,
   "climax": false,
   "climax_round": 0,
   "img": "assets/cards/si_shadow_of_angra_mainyu.jpg",
   "effects": [
    "迅捷攻击于深山町和新都获得威力+1",
    "宝具禁止使用"
   ]
  },
  {
   "name": "安哥拉·曼纽的实质",
   "magic": 0,
   "climax": false,
   "climax_round": 0,
   "img": "assets/cards/si_substance_of_angra_mainyu.jpg",
   "effects": [
    "魔术攻击于深山町和新都获得威力+1",
    "宝具禁止使用"
   ]
  },
  {
   "name": "转机",
   "magic": 2,
   "climax": false,
   "climax_round": 0,
   "img": "assets/cards/si_turnaround.jpg",
   "effects": [
    "于深山町和新都各增加一张正面事件牌"
   ]
  }
 ],
 "basic_attacks": [
  {
   "id": "luck",
   "name": "幸运",
   "cost": 0,
   "power": 4,
   "attributes": [
    "special"
   ],
   "img": "assets/cards/atk_luck.jpg",
   "effects": [
    "战斗阶段：你本回合无视【直接败北】效果"
   ]
  },
  {
   "id": "magic_blast_0_2",
   "name": "低位魔术",
   "cost": 0,
   "power": 2,
   "attributes": [
    "magic"
   ],
   "img": "assets/cards/atk_magic_blast_0_2.jpg",
   "effects": []
  },
  {
   "id": "magic_blast_0_3",
   "name": "中位魔术",
   "cost": 0,
   "power": 3,
   "attributes": [
    "magic"
   ],
   "img": "assets/cards/atk_magic_blast_0_3.jpg",
   "effects": []
  },
  {
   "id": "magic_blast_0_4",
   "name": "高位魔术",
   "cost": 0,
   "power": 4,
   "attributes": [
    "magic"
   ],
   "img": "assets/cards/atk_magic_blast_0_4.jpg",
   "effects": []
  },
  {
   "id": "magic_blast_1_5",
   "name": "超高位魔术",
   "cost": 1,
   "power": 5,
   "attributes": [
    "magic"
   ],
   "img": "assets/cards/atk_magic_blast_1_5.jpg",
   "effects": []
  },
  {
   "id": "physical_attack_0_2",
   "name": "迫击",
   "cost": 0,
   "power": 2,
   "attributes": [
    "strength"
   ],
   "img": "assets/cards/atk_physical_attack_0_2.jpg",
   "effects": []
  },
  {
   "id": "physical_attack_0_3",
   "name": "强打",
   "cost": 0,
   "power": 3,
   "attributes": [
    "strength"
   ],
   "img": "assets/cards/atk_physical_attack_0_3.jpg",
   "effects": []
  },
  {
   "id": "physical_attack_0_4",
   "name": "浑身的一击",
   "cost": 0,
   "power": 4,
   "attributes": [
    "strength"
   ],
   "img": "assets/cards/atk_physical_attack_0_4.jpg",
   "effects": []
  },
  {
   "id": "physical_attack_1_5",
   "name": "会心的一击",
   "cost": 1,
   "power": 5,
   "attributes": [
    "strength"
   ],
   "img": "assets/cards/atk_physical_attack_1_5.jpg",
   "effects": []
  },
  {
   "id": "precision_strike_0_2",
   "name": "翻弄",
   "cost": 0,
   "power": 2,
   "attributes": [
    "agility"
   ],
   "img": "assets/cards/atk_precision_strike_0_2.jpg",
   "effects": []
  },
  {
   "id": "precision_strike_0_3",
   "name": "高速移动",
   "cost": 0,
   "power": 3,
   "attributes": [
    "agility"
   ],
   "img": "assets/cards/atk_precision_strike_0_3.jpg",
   "effects": []
  },
  {
   "id": "precision_strike_0_4",
   "name": "瞬间的一击",
   "cost": 0,
   "power": 4,
   "attributes": [
    "agility"
   ],
   "img": "assets/cards/atk_precision_strike_0_4.jpg",
   "effects": []
  },
  {
   "id": "precision_strike_1_5",
   "name": "刹那的一击",
   "cost": 1,
   "power": 5,
   "attributes": [
    "agility"
   ],
   "img": "assets/cards/atk_precision_strike_1_5.jpg",
   "effects": []
  },
  {
   "id": "preparation",
   "name": "远隔操作",
   "cost": 1,
   "power": 2,
   "attributes": [
    "special"
   ],
   "img": "assets/cards/atk_preparation.jpg",
   "effects": [
    "行动阶段：地利效果翻倍。",
    "战斗阶段：若你赢得战斗，获得2点战果。"
   ]
  },
  {
   "id": "surveil",
   "name": "急行",
   "cost": 1,
   "power": 3,
   "attributes": [
    "special"
   ],
   "img": "assets/cards/atk_surveil.jpg",
   "effects": [
    "行动阶段：无视交战状态，沿箭头移动至下一地点"
   ]
  }
 ],
 "command_spell": {
  "name": "令咒",
  "img": "assets/cards/command_spell.jpg",
  "options": [
   "行动阶段：获得4魔力",
   "行动阶段：合计威力+2\n获胜后获得2战果",
   "行动阶段：从新都或深山町移动至任意位置，无视交战状态"
  ]
 },
 "map": {
  "areas": [
   {
    "id": "workshop",
    "name": "魔术工房",
    "move_cost": 1,
    "seats": [
     {
      "magic": 2
     },
     {
      "magic": 1
     },
     {
      "magic": 1
     },
     {
      "magic": 1
     }
    ],
    "competition": 0,
    "img": "assets/area_workshop.jpg"
   },
   {
    "id": "miyama",
    "name": "深山町",
    "move_cost": 2,
    "seats": [
     {
      "terrain": 3
     },
     {
      "terrain": 1
     },
     {
      "terrain": 0,
      "unlimited": true
     }
    ],
    "competition": 2,
    "img": "assets/area_miyama.jpg"
   },
   {
    "id": "shinto",
    "name": "新都",
    "move_cost": 2,
    "seats": [
     {
      "terrain": 3
     },
     {
      "terrain": 1
     },
     {
      "terrain": 0,
      "unlimited": true
     }
    ],
    "competition": 3,
    "img": "assets/area_shinto.jpg"
   },
   {
    "id": "scout",
    "name": "侦察",
    "move_cost": 0,
    "seats": [
     {
      "scout": true
     }
    ],
    "competition": 2,
    "img": "assets/area_scout.jpg"
   }
  ]
 },
 "rules": {
  "magic_max": 12,
  "hand_limit": 3,
  "regular_play": 2,
  "skill_min_magic": 8,
  "rounds": 11,
  "command_spells": 3,
  "initial_magic": 4,
  "scout_score": 2,
  "phases": [
   {
    "id": "prepare",
    "name": "准备阶段",
    "en": "PREPARE"
   },
   {
    "id": "outpost",
    "name": "前哨阶段",
    "en": "OUTPOST"
   },
   {
    "id": "action",
    "name": "行动阶段",
    "en": "ACTION"
   },
   {
    "id": "battle",
    "name": "战斗阶段",
    "en": "BATTLE"
   }
  ],
  "elimination": {
   "8": 4,
   "9": 3,
   "10": 2
  }
 },
 "attr_names": {
  "strength": "力量",
  "agility": "迅捷",
  "magic": "魔术",
  "special": "特殊",
  "noble_phantasm": "宝具"
 },
 "class_names": {
  "saber": "Saber",
  "archer": "Archer",
  "lancer": "Lancer",
  "rider": "Rider",
  "caster": "Caster",
  "assassin": "Assassin",
  "berserker": "Berserker"
 },
 "backs": {
  "attack": "assets/cards/attack_card_back.jpg",
  "skill": "assets/cards/skill_card_back.jpg",
  "event": "assets/cards/event_card_back.jpg",
  "situation": "assets/cards/situation_card_back.jpg",
  "servant": "assets/cards/servant_card_back.jpg"
 }
};