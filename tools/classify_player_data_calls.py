#!/usr/bin/env python
"""B24: inventory player lookups; apply explicit, source-bound human reviews.

No Godot execution or production writes. Default scan ignores hidden directories
(including historical worktrees) and includes ignored/untracked project .gd files.
Only JSON/Markdown report paths are written. Unknown is a valid review outcome.
"""
from __future__ import annotations

import argparse
from bisect import bisect_right
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re

LABELS = ('只读', '需创建', '无法判定')
HASHES = {
    'scripts/system/global/game_data.gd': '6d7c4f67a05cbc8da61f831cc32253e23565f510e7b7b7ca838e7ed460aafbe2',
    'scripts/system/global/game_data_manager.gd': 'd8cb5112300a319c64eee3da6eb008bf2cc98631a39f4916cfd972327833b1c1',
    'scripts/main_menu/game_start.gd': '4535d1729fdfeb9cb5223738019f244a844de9327a4726ba084e3d156c2faf50',
    'scripts/system/global/effect_manager.gd': '5077f81104e4235bea5142173529fa17c6d28746ce39f6f92daf60f1a65655f1',
    'scripts/system/global/game_progress.gd': 'b5b527a248c74c1db4623ec4340f0a10e63fa617846ddbbb81cf4e67f6222f80',
    'scripts/system/global/climax_resolver.gd': '0aab398b99a56f6014203ef99199b802671dbf22aa628e4944ee86718f6b8c37',
    'scripts/game_scene/battle_board_v2.gd': '51a85f0ae215627127b380224507598b6875ac370a8670aab6c337d3cf607ca0',
    'scripts/game_scene/tactical_board_ui.gd': '3063aca824df5c4561cf08588c4e77d14588a3777e48397d33823e5b6a15acda',
    'tests/net_round_identity_feedback_test.gd': '158b517d643fc9f7966098152cf5ef8ec34b2f7125175fa70cd39be8d00b39af',
    'scripts/system/regular_play.gd': 'f6fce80464730c6a259bc188b5d252efe7da5ab70cafecb9901cbabfdb825d27',
}
# Current-source snapshots for files whose earlier reviews were line-accurate but
# whose source moved after the previous scan.  These are evidence bindings, not
# a filename/prefix classifier.
HASHES.update({
    'scripts/game_scene/battle_board_v2.gd': '1e183b3dda933944a45d7161053554e6477b4f25e0d436bc892c08d21ea620ee',
    'scripts/system/global/battle_resolver.gd': '6751276a7c00ba0ab9070076e539704d1a28a256b468778582f1d91ecf911e57',
    'scripts/system/global/effect_manager.gd': '1755ff077e675105844d3d6ec33645bc3f701a48aa1cdf8dc2b11c8a6b5340c1',
    'scripts/system/global/game_progress.gd': '0db25f9e17b9da91c248201d6be5c67eb7081b58295d49142b3824286cac4978',
    'scripts/system/global/master_manager.gd': '3520e6a380d1da087e391fc26c972ed64e1c3bef21d644b7e31d6e187c6bd174',
    'scripts/system/global/servant_manager.gd': '226712df89daadaa8786ff3fdb131f29cd96caa925cf8eedb6c5cb0d330de15a',
    'scripts/system/global/time_point_checker.gd': '289cba0dc5dae96e5fdfccfa33d8ed2d5d835038008b09a4ae253253267a48e1',
    'scripts/system/global/victory_resolver.gd': 'b57f218a88ce0e2914f4adeedd40a4758860248118df0e989ef2451e07d22c94',
    'scripts/system/operations/ChangePlOrder.gd': 'f779d276aa2301890e15f878e7efd64ac025497bdcec1b3b744e28f055c91635',
    'scripts/system/operations/HideTrueName.gd': '98b933393b8ede0c3c1d08d17a3e823c2692cdfe7b682ff1bc2a71fed8d0ccea',
    'scripts/system/operations/IsEngaged.gd': '366327abca4bbb588fd21260f12b536804b8b885002d68bf53c6451614f4ed86',
    'scripts/system/operations/GetAllPlayersId.gd': 'f572c78c296a5c26223a336efecec86412dfc20b995383508d78afec76d5f44e',
})

# Explicitly read source snapshots, not a filename/prefix classifier.
GETTER_REVIEWS = {
    'GetDataNumber': 'dfd42318747184d33272583c08a115833fdd94f92537d40d1606563f2deb9d89',
    'GetEffectiveLocationBenefit': 'a23fede2356cfe638fb59ea295a034bb26175eb55cdd1a05943e06e01919cf0d',
    'GetLocation': '6ef339a333644fc8057a1d87d9380b92adbd8a5db770f62bb844014a664e49ec',
    'GetPlAttacksOutGame': '3333ed22ed3b3d27bef64e4afef4404008726824a7cd611509cfdd1182c08b2b',
    'GetPlayerBuffs': '65e588a73006c60771d82653a3860681e8eccd50c58a17056c101c75b94121f6',
    'GetPlayerCommandSpell': '09bb54eafbdbaeab63e42c38859403f9ee81f83a19d2865248ea8997a4b78490',
    'GetPlayerDataValue': '72b0060c26ebfa39bd46a0fb1c62c5dc0845274470aff1d361dbbf33ef30676a',
    'GetPlayerDeck': '8506f6ffc1ef0d4d4078a1589c60abdc8d203502b60bc79d699b526588ec6151',
    'GetPlayerDiscard': '4e871443014443fb9c6eb8577ac1d5da1a3cd8c323087011e8137ebce17060a6',
    'GetPlayerHandCards': 'c9816853708e5a3c951974710f3b1fb9d234db351b7a6004d29e60f6cea4d6a1',
    'GetPlayerIdsByDataValue': '790fb42a024e51cb4f853453c42d3dee5e5b7b2026e9a491781ffb35962b270f',
    'GetPlayerLives': 'fcea404c2e975ae81bbb0bc27377cf106b9b8b6d30101f652e821adad229db1c',
    'GetPlayerMaster': '24a5a4ff8172d93304981947d19e20eeeb02e2563058f0deb91f4884f6636253',
    'GetPlayerMasterSkills': '5891b65f1ebd0e2d3fc22eca89b8840980d775f09e985e0bed9c104513d83508',
    'GetPlayerName': 'cc3b5c98db7aed34122adbc6235d20ba0fc394de3bb9cff8749a0e1dd1ff02cd',
    'GetPlayerPlayedCards': '916a486dc8e3db2959e40ae67c12168d2e1346f8ce8d2f3b2c0411cdd3e4fe3c',
    'GetPlayerServant': '9f3ff429b914f08dcf676ef9e8f303155f8a94f08ad568f858a1fa075b8ba182',
    'GetPlayerServantSkills': 'f46f68f6af9d9f23a0603b4af311312f447b91197c956cc811555e068fbdf257',
    'GetPlayersField': '898936867f172cb908e32525063cbadafd52fb63d813548f462f389d9689b46d',
    'GetPlayersInMapArea': '65b45d492f17e836d6267daf281c4616499605217e5cebed8b35a7f63c40739b',
    'GetPlayersInSameArea': '67f40d5a4684069c112919a5467b8b5258b68fa32779c1171b05f214bf5ff45f',
    'GetPlayerTimePoints': '927152881090ebe7a63ca15dae973e1d605082f636248e43f68ffa41d90e8470',
    'GetPlayerTotalPower': '5aa911a2110ae152ab67267141082a736af3596e1163b224edf9fbd6611df92d',
    'GetPlBuffsOutGame': '2d7e19c1953d88de16853ed9344ccc83b80b126c3a173f72a4b906900f4a0bb4',
    'GetPlBuffsSide': '54569b0cc58632f1f72902341573bd8ee51b91d1b2fbf8b878a7f3f68d17c691',
    'GetPlCommandSpellOutGame': '0509701c7719fe2a9b9728e6cb717b9f2355032d4730ce532240f60e5279e9cf',
    'GetPlCommandSpellSide': '2211bf866221e592301650043b329102037d4d55e8143f31908820b747cec7bf',
    'GetPlDeckSide': 'b1b8c171d485418481fb60db316ef7ec6c8ae74b43ca7ec6daf6ee68711ecbcd',
    'GetPlDiscardSide': '1d9e39742ed1bd80686ef11111afce2b28b0f96a8d0366b1931c6162e7d20a6c',
    'GetPlIdUsingEff': '3645c3849657d34fa6cf156c23ea5a33bddf80d604ca2fafde41d72da1179d86',
    'GetPlMasterOutGame': '7b14d541a01aefbcd0308e451a2f1ea5353195de8e5f6022972dfc33bf524cf9',
    'GetPlMasterSide': '139997fcea4c0782f65f7386a2f7d2514511ee68368439cd230660c2f629676d',
    'GetPlOthersOutGame': 'ff3ff4f4aa595359b6d1c1cfe1823a438daba288a391e3cf2d3533690dacc264',
    'GetPlOthersSide': 'f0c211357eb5a9934520d1ea2100575467b0de47b0ab8bcfa910e8bdbfef8f87',
    'GetPlServantOutGame': '3c5dd22e22876fe52060d977743a65838ddd5ee4122a8b1a44e36729962fad7b',
    'GetPlServantSide': '20960e4c496c9054a5ef96ac57dfd8539d2b4d76967c8c3795ca0d38fb83f8d6',
    'GetPlSkillsOutGame': '09aef7752432fb49c95e25de0e9136967f9acd6bfe75f350ca14baedd090c6dc',
    'GetPlSkillsSide': '6561824a15e15822c2782455524e605ade6c75a836a4a9d14f36473d851e4c28',
    'GetRankByDataNumber': 'e0d3716762f3655c1e6b17ef2fe673b3bb5fc8c7a2c59307a55efc8babeccc73',
    'GetSharedAttackAttribute': 'b268639b62ac4cae0611f4f824be10e5eb76f4f133d4e1d5d6d283eac0ada4a4',
}
for name, digest in GETTER_REVIEWS.items():
    HASHES['scripts/system/operations/' + name + '.gd'] = digest

GUARDED_OPERATION_REVIEWS = {
    'AwakenSkill': (10, '9261326ddf94eff56e166d0814c4473b16e5b09d5e4e5903f13971c0032189cb'),
    'CardCountsPower': (16, 'a8feefbb24f59ba556b3b138bc1c572a44f3cea580720e6f4fe4fab8fc82b286'),
    'EditCardPower': (22, '2f70713757123b9c4d0921576e85a967642e21e0defbb2193c4f36932aba5ef6'),
    'ModifyAttackPowerByAttribute': (27, '361d509c00191163ad7970216863fcbb347a75c7b10c889cbdc3e1c7342d46dc'),
    'PlayAttack': (20, '94385a0532baab8222cdd21a22b56c97525b513474667f1f3eb6e40571cb7c04'),
    'ReleaseTrueName': (21, '6ddfe7aa756e0b380e5fef747c687e56701251e40187cbc1c7ccd274593b11b2'),
    'SyncPower': (12, '82b123544a273c264273ba2a6f21bb3749be7e28466a8647c08a5ec3c96d2a99'),
    'ZeroAttributePower': (13, 'd200130c1cb0e2fdff5ed4e39f5c10086c972274c3813ca99ab46d60f8855758'),
    'SetCardConcealed': (26, '24efe7be6575093e2959b4edfdc0c59fcd8df122fa2a7c934bb49a9ede76e95d'),
}
for name, (_, digest) in GUARDED_OPERATION_REVIEWS.items():
    HASHES['scripts/system/operations/' + name + '.gd'] = digest

# B24-followup reviews are declared below after the helper is available.
REVIEWS = {}
def reviewed(path, lines, reason, usage='读取/查询', category='只读', dependencies=()):
    for line in lines:
        REVIEWS[(path, line)] = dict(classification=category, reason=reason,
                                    data_usage=usage, dependencies=list(dependencies))

# B24-followup: 当前源码复核的生产调用；ID 来源均在 reason 中明确记录。
reviewed('scripts/game_scene/battle_board_v2.gd', [3289, 3292, 5021, 5051],
         '3289/3292/5021/5051 使用本地玩家 ID；_ready 312–314 先取 GameData.player_id 并在未开局时调用 GameStart.game_start，GameStart 43 行 reset_game_session(ids) 已为本局 ids 建条目。这里是部署/移动前后读取，不承担召唤建条目。',
         '读取或比较本局已有玩家条目', dependencies=['scripts/main_menu/game_start.gd', 'scripts/system/global/game_data.gd'])

reviewed('scripts/system/global/battle_resolver.gd', [31, 53, 102, 113, 242, 257],
         'ids 在 20–24 行为空时来自 GameDataManager.get_board_player_ids，非空则是调用方提供的参战快照；之后所有调用都遍历同一参战快照。get_board_player_ids 由 active ids 与 player_data_library.keys() 过滤生成，故这里不创建玩家。',
         '读取或修改参战快照中的已有条目', dependencies=['scripts/system/global/game_data_manager.gd', 'scripts/system/global/effect_manager.gd'])
reviewed('scripts/system/global/climax_resolver.gd', [19, 20, 25, 28, 39, 64],
         'active_ids 由 get_active_player_ids 返回，ranked/kept/tied_ids 均由该已有玩家集合派生；39 行还先 has(player_id)，所以高潮排名/淘汰读取已有条目，不是建玩家入口。',
         '读取或修改已有玩家的排名/淘汰状态', dependencies=['scripts/system/global/game_data_manager.gd', 'scripts/system/global/effect_manager.gd'])
reviewed('scripts/system/global/effect_manager.gd', [871, 872, 1068, 1092, 1118, 1235, 1255],
         '871/872 的 a、b 来自 get_player_order_ids（先由 player_data_library.keys 过滤）；1068 遍历 get_all_players_id；1092 有 has 守卫；1118/1235/1255 的 ID 来自已登记效果的 _trigger_player_id，效果登记与玩家条目绑定，均无建玩家职责。',
         '读取已有玩家的顺位、时点或效果归属数据', dependencies=['scripts/system/global/game_data_manager.gd'])
reviewed('scripts/system/global/game_progress.gd', [175, 268, 347, 379, 549, 599],
         '175/268/347/379/549 的 ID 分别来自 active/order 玩家快照；599 接收当前行动者 ID，且调用链由 545–552 的 ordered ids 设置。GameStart 先 reset_game_session，阶段推进不召唤玩家。',
         '读取或修改已有玩家的阶段/回合状态', dependencies=['scripts/system/global/game_data_manager.gd', 'scripts/system/global/effect_manager.gd'])
reviewed('scripts/system/global/master_manager.gd', [7, 16, 43],
         'GameStart 56–89 在 reset_game_session 建好的本局 ids 上逐个调用三个绑定入口；入口只读取 master/牌区并登记克隆效果，不调用 AddPlayer。',
         '读取已有玩家并绑定御主/初始卡牌效果', dependencies=['scripts/main_menu/game_start.gd', 'scripts/system/global/game_data.gd'])
reviewed('scripts/system/global/servant_manager.gd', [6],
         '同由 GameStart 56–89 对 reset_game_session 已建好的每个 id 调用；只读取 servant 并登记效果，不创建玩家。',
         '读取已有玩家并绑定从者效果', dependencies=['scripts/main_menu/game_start.gd', 'scripts/system/global/game_data.gd'])
reviewed('scripts/system/global/time_point_checker.gd', [17, 30, 42, 68, 84, 111, 121, 142],
         '所有循环 ID 来自 EffectManager.get_all_players_id() 或当前行动者；该列表直接来自 player_data_library.keys，且本文件只更新已有条目的时点数组，不含 AddPlayer/初始化分支。',
         '读取或修改已有玩家的时点数组', dependencies=['scripts/system/global/effect_manager.gd', 'scripts/system/global/game_data_manager.gd'])
reviewed('scripts/system/global/victory_resolver.gd', [18, 23, 30, 43],
         'active_ids 由 get_active_player_ids 返回；所有分支都在该已有玩家集合上读取战果或写胜利标记，未出现创建/召唤入口。',
         '读取或修改已有玩家的胜负状态', dependencies=['scripts/system/global/game_data_manager.gd', 'scripts/system/global/effect_manager.gd'])
reviewed('scripts/system/operations/ChangePlOrder.gd', [14, 24, 34],
         'pl_ids 来自 GetAllPlayersId.exec，后者直接返回 GameData.player_data_library.keys；循环只改已有条目的 order，不创建条目。',
         '修改已有玩家的顺位', dependencies=['scripts/system/operations/GetAllPlayersId.gd', 'scripts/system/global/game_data.gd'])
reviewed('scripts/system/operations/HideTrueName.gd', [18],
         '15 行已先 has(id)；18 行只读取已有条目的牌区并执行隐藏，不会触发 get_player_data 的按需建条目。',
         '读取或修改已有玩家的卡牌状态')
reviewed('scripts/system/operations/IsEngaged.gd', [29],
         'other_id 来自 get_board_player_ids；该列表由已有库 keys/active 条目生成，29 行只读取对手条目。',
         '读取版图上已有参战条目', dependencies=['scripts/system/global/game_data_manager.gd'])
reviewed('scripts/system/regular_play.gd', [135, 184, 240, 244],
         '135/184/240 明确先检查 player_data_library.has(id)，244 行在同一提交校验路径取得已有条目；这些调用只做常规出牌合法性读取。',
         '读取已有玩家的出牌状态')

# Existing review table continues to use the helper above.
def reviewed(path, lines, reason, usage='读取/查询', category='只读', dependencies=()):
    for line in lines:
        REVIEWS[(path, line)] = dict(classification=category, reason=reason,
                                    data_usage=usage, dependencies=list(dependencies))

reviewed('scripts/main_menu/game_start.gd', [58],
         'id 来自本次 ids；43 行先 reset_game_session(ids)，GameData 154–157 行逐个建好条目。此处初始化已有条目，不需要隐式创建。',
         '修改已有条目：is_out/order/player_name/角色归属', dependencies=['scripts/system/global/game_data.gd'])
reviewed('tests/net_round_identity_feedback_test.gd', [9],
         '6 行 clear 清空库，8 行 range(3) 产生新 ID，9 行第一次 get 后写 order；夹具明确依赖按需创建。',
         '创建后写入 order', '需创建')
reviewed('scripts/game_scene/battle_board_v2.gd', [554, 2958],
         '同一调用前 has(id) 或 has(_local_player_id) 守卫保证已存在；查询/提示不承担建玩家职责。')

reviewed('scripts/system/global/effect_manager.gd', [598, 2612],
         '显示名称前 has 守卫，不存在时提前返回；只读取 master。')
reviewed('scripts/system/global/effect_manager.gd', [871, 872, 1068],
         'ID 来自 get_all_players_id()，852–853 行明确返回 player_data_library.keys()；排序或时点快照只访问已有条目。')
reviewed('scripts/system/global/effect_manager.gd', [1092],
         '恢复快照循环先 has(id)，不存在则 continue；只操作已有条目。', '修改已有条目的时点数组')
reviewed('scripts/system/global/game_data_manager.gd', [35],
         'ID 来自 get_player_order_ids；EffectManager 852–876 行从字典 keys 过滤/排序，非建玩家入口。',
         dependencies=['scripts/system/global/effect_manager.gd'])
reviewed('scripts/system/global/game_progress.gd', [223],
         '221–222 行 has(player_id) 守卫并在不存在时回退名称；只读 master。')
reviewed('scripts/system/global/climax_resolver.gd', [39],
         '37–38 行 has(player_id) 守卫；淘汰已有玩家，不创建玩家。', '修改已有玩家的淘汰状态')
reviewed('scripts/system/regular_play.gd', [135, 184],
         '调用之前显式 has(id) 守卫；候选/可出牌判定读取已有玩家。')
for name, (line, _) in GUARDED_OPERATION_REVIEWS.items():
    path = 'scripts/system/operations/' + name + '.gd'
    reason = '已阅读完整函数；本调用前 has(id) 守卫，缺失玩家时提前返回；业务只针对已有条目。'
    dependencies = []
    if name in ('EditCardPower', 'SetCardConcealed'):
        reason = ('已阅读完整函数；仅在 CardCountsPower.exec 返回计入威力（或翻面前后结果改变）时获取数据；'
                  'CardCountsPower:14–15 先 has(id)，缺失时返回 false，因此不会为缺失 ID 创建。')
        dependencies = ['scripts/system/operations/CardCountsPower.gd']
    reviewed(path, [line], reason, '读取或修改已有数据/卡牌（非只读业务保证）', dependencies=dependencies)

# These concrete files were read in full, not inferred from names.
for name in GETTER_REVIEWS:
    path = 'scripts/system/operations/' + name + '.gd'
    reason = ('已阅读本文件完整函数：返回已有字段、局部筛选/数值计算或反查既有效果归属；'
              '没有创建玩家职责。ID 是显式参数经 resolve_player_id（-1 回退效果触发者/本地 ID），'
              '或来自既有玩家 keys/active 列表。未守卫调用的缺失 ID 返回策略仍须后续迁移单独设计；'
              '返回的数组/对象可能被下游修改，本分类不声称对象图不可变。')
    # Fixed review snapshot applies only to calls in the exact read file.
    REVIEWS[(path, '*')] = dict(classification='只读', reason=reason,
                                data_usage='读取/返回既有值或其引用（非深层不可变）',
                                dependencies=['scripts/system/global/effect_manager.gd',
                                              'scripts/system/global/game_data_manager.gd'])


# Final line-accurate B24 follow-up reviews after the original table.
reviewed('scripts/game_scene/battle_board_v2.gd', [2957, 3288, 3291, 5020, 5050],
         '当前源码中这些调用使用本地玩家 ID；_ready 先设置 GameData.player_id，并在未开局时调用 GameStart.game_start。GameStart 的 reset_game_session(ids) 在后续读取前为本局 ids 建条目；调用点是 UI 读取/动作前后比较，不是 AddPlayer 召唤入口。',
         '读取或比较本局已有玩家条目', dependencies=['scripts/main_menu/game_start.gd', 'scripts/system/global/game_data.gd'])
# B24 已证实仅 _class_shown/_refresh_ai_play_prompt/_update_ai_play_prompt_geometry
# 三处 get -> find；反向还原后的完整文件 SHA 与旧绑定一致。find 不计入 get 盘点。
# 仅保留旧快照中仍精确对应 get 的 anchor；过期行不平移，未覆盖调用继续无法判定。
reviewed('scripts/game_scene/tactical_board_ui.gd', [2588],
         'UI 的本地/对手 ID 来自 _ready 的 GameData.player_id、顺位节点或 get_board_player_ids()/选中对象；_ready 242–246 确保未开局时先 game_start，GameStart 43 行 reset_game_session(ids) 预建本局条目。调用点均为显示、选择前后比较或已有牌区读取；无 AddPlayer/召唤建条目路径。',
         '读取或比较本局已有玩家条目', dependencies=['scripts/main_menu/game_start.gd', 'scripts/system/global/game_data.gd'])
reviewed('scripts/game_scene/tactical_board_ui.gd', [281, 284, 514, 530, 605, 768, 857, 1454, 2407, 2461, 2590, 2598, 2601, 3645],
         '当前源码中这些调用使用本地玩家或已选目标 ID；_ready 242–246 在未开局时先 game_start，reset_game_session(ids) 预建本局条目。它们用于显示、操作前后比较或选牌面板，不承担召唤建条目。',
         '读取或比较本局已有玩家条目', dependencies=['scripts/main_menu/game_start.gd', 'scripts/system/global/game_data.gd'])
reviewed('scripts/system/global/battle_resolver.gd', [31, 53, 102, 113, 242, 257],
         'ids 在入口中来自 get_board_player_ids 或调用方传入的参战快照；后续调用遍历同一快照。get_board_player_ids 由 active ids 与 player_data_library.keys 过滤生成，战斗结算不调用 AddPlayer。',
         '读取或修改参战快照中的已有条目', dependencies=['scripts/system/global/game_data_manager.gd', 'scripts/system/global/effect_manager.gd'])
reviewed('scripts/system/global/effect_manager.gd', [875, 876, 1072, 1096, 1122, 1239, 1259, 2120],
         '875/876 的 ID 来自 get_player_order_ids；1072 遍历 get_all_players_id；1096 先 has；1122/1239/1259 来自已登记效果的 _trigger_player_id；2120 遍历 close_time_point 已解析出的玩家集合。上述来源均是已有库/效果归属，不是建条目入口。',
         '读取或修改已有玩家的顺位、时点或效果归属数据', dependencies=['scripts/system/global/game_data_manager.gd'])
reviewed('scripts/system/global/game_progress.gd', [256, 335, 367, 537, 587],
         '256/335/367/537/587 的 ID 来自 active/order 玩家快照或当前阶段的 ordered ids；GameStart 先 reset_game_session，回合推进只读取/修改已有条目，不召唤玩家。',
         '读取或修改已有玩家的阶段/回合状态', dependencies=['scripts/system/global/game_data_manager.gd', 'scripts/system/global/effect_manager.gd'])
reviewed('scripts/system/global/master_manager.gd', [7, 16, 43],
         'GameStart 在 reset_game_session 建好的本局 ids 上逐个调用绑定入口；入口只读取 master/牌区并登记克隆效果，不调用 AddPlayer。',
         '读取已有玩家并绑定御主/初始卡牌效果', dependencies=['scripts/main_menu/game_start.gd', 'scripts/system/global/game_data.gd'])
reviewed('scripts/system/global/servant_manager.gd', [6],
         '同由 GameStart 对 reset_game_session 已建好的每个 id 调用；只读取 servant 并登记效果，不创建玩家。',
         '读取已有玩家并绑定从者效果', dependencies=['scripts/main_menu/game_start.gd', 'scripts/system/global/game_data.gd'])
reviewed('scripts/system/global/time_point_checker.gd', [17, 30, 42, 68, 84, 111, 121, 142],
         '所有循环 ID 来自 get_all_players_id 或当前行动者；get_all_players_id 直接返回 player_data_library.keys，本文件只更新已有条目的时点数组。',
         '读取或修改已有玩家的时点数组', dependencies=['scripts/system/global/effect_manager.gd', 'scripts/system/global/game_data_manager.gd'])
reviewed('scripts/system/global/victory_resolver.gd', [18, 23, 30, 43],
         'active_ids 由 get_active_player_ids 返回；各分支在该已有玩家集合上读取战果或写胜利标记，未出现创建/召唤入口。',
         '读取或修改已有玩家的胜负状态', dependencies=['scripts/system/global/game_data_manager.gd', 'scripts/system/global/effect_manager.gd'])
reviewed('scripts/system/operations/ChangePlOrder.gd', [14, 24, 34],
         'pl_ids 来自 GetAllPlayersId.exec，后者直接返回 player_data_library.keys；循环只改已有条目的 order，不创建条目。',
         '修改已有玩家的顺位', dependencies=['scripts/system/operations/GetAllPlayersId.gd', 'scripts/system/global/game_data.gd'])
# Current-source B24 handoff reviews.  Every line below was checked against the
# current file and is bound to the hashes above; no name-only inference is used.
reviewed('scripts/game_scene/battle_board_v2.gd', [5226, 5274, 5405, 5435],
         '本地 ID 在 _ready:348–350 取自 GameData.player_id；未启动时先调用 GameStart.game_start([0..6])，其 43 行 reset_game_session(ids) 在这些 UI 查询/动作前为本局 ids 写入 new_player_data。调用点只读部署/移动前后状态或 AI 已有牌区，不是 AddPlayer/召唤建条目入口。',
         '读取或比较本局已有玩家条目', dependencies=['scripts/main_menu/game_start.gd', 'scripts/system/global/game_data.gd'])
reviewed('scripts/game_scene/tactical_board_ui.gd', [678, 956, 1195, 1364, 4352],
         '678 的 id 来自 get_active_player_ids；956 的 bot_id 来自顺位卡位 meta，而 meta 在 890–897 由已有 ordered_ids 写入；1195 的 id 来自 get_board_player_ids；1364 在 1362–1363 已 has(player_id) 守卫；4352 的 bot_id 来自 4347 的顺位卡位绑定。上述来源是已有玩家集合/已有 UI 绑定，未调用 AddPlayer。',
         '读取已有玩家的榜单、版图、卡位或游戏外牌区数据', dependencies=['scripts/system/global/game_data_manager.gd', 'scripts/system/global/effect_manager.gd'])
reviewed('scripts/system/global/battle_resolver.gd', [31, 53, 102, 113, 242, 257],
         'ids 在 exec:20–23 来自调用方传入的参战快照，或由 get_board_player_ids 从 active ids 与 player_data_library.keys 派生；后续调用只遍历这份参战集合。113/242/257 还处于同一结算链的已有参战者循环；没有创建/召唤路径。',
         '读取或修改已有参战快照中的玩家条目', dependencies=['scripts/system/global/game_data_manager.gd', 'scripts/system/global/effect_manager.gd'])
reviewed('scripts/system/global/climax_resolver.gd', [19, 20, 25, 28],
         'active_ids 在 exec:7 由 get_active_player_ids 返回；ranked、cutoff 和后续 id 都由该已有玩家集合派生。39 行淘汰前还有 has 守卫；排名/淘汰流程没有 AddPlayer。',
         '读取或修改已有玩家的高潮排名/淘汰状态', dependencies=['scripts/system/global/game_data_manager.gd', 'scripts/system/global/effect_manager.gd'])
reviewed('scripts/system/global/effect_manager.gd', [956, 957, 984, 1018, 1155, 1179, 1205, 1322, 1342, 1667, 2208],
         '956–957 的 a/b 来自 get_all_players_id，即 player_data_library.keys；984 的 player_id 被写入效果的 _trigger_player_id 后登记归属；1018 的 id 来自已登记效果；1155/1179/2208 遍历已有玩家 keys 或快照且 1181 有 has 守卫；1205/1322/1342 使用已登记效果的 _trigger_player_id；1667 的 selected_player 是选项目标，进入此函数前由玩家选择候选集产生。均为已有条目/效果绑定读取，不是创建入口。',
         '读取已有玩家的顺位、效果归属、时点快照或选项目标', dependencies=['scripts/system/global/game_data_manager.gd'])
reviewed('scripts/system/global/game_data_manager.gd', [40],
         'get_active_player_ids:39 从 EffectManager.get_player_order_ids 取得顺位集合；该集合由 player_data_library.keys 过滤为独立玩家。40 行只读取该集合中的已有条目。',
         '读取已有顺位集合中的玩家状态', dependencies=['scripts/system/global/effect_manager.gd'])
reviewed('scripts/system/global/game_progress.gd', [179, 260, 339, 371, 567],
         '179 的 id 来自 active_player_ids；260 来自 _resume_round_start 已保存的 active/order 玩家数组；339 来自 get_active_player_ids；371 来自 get_ordered_player_ids；567 的 id 是当前顺位流程已选出的行动者。阶段推进只处理已建立的本局条目，不召唤玩家。',
         '读取或修改已有玩家的牌区/阶段/回合状态', dependencies=['scripts/system/global/game_data_manager.gd', 'scripts/system/global/effect_manager.gd'])
reviewed('scripts/system/global/master_manager.gd', [7, 16, 43],
         'GameStart:56–89 在 reset_game_session(ids) 后逐个传入本局 id；这些函数只从该条目读取 master/牌区并登记克隆效果，不调用 AddPlayer。',
         '读取已有玩家并绑定御主、初始卡牌或令咒效果', dependencies=['scripts/main_menu/game_start.gd', 'scripts/system/global/game_data.gd'])
reviewed('scripts/system/global/servant_manager.gd', [6],
         'GameStart:56–89 在 reset_game_session(ids) 后逐个调用；这里只读取已有条目的 servant 并登记效果，不创建玩家。',
         '读取已有玩家并绑定从者效果', dependencies=['scripts/main_menu/game_start.gd', 'scripts/system/global/game_data.gd'])
reviewed('scripts/system/global/time_point_checker.gd', [17, 30, 42, 68, 84, 111, 121, 142],
         '循环 ID 来自 EffectManager.get_all_players_id() 或当前行动者/已选对手；get_all_players_id 直接返回 player_data_library.keys。该文件只更新已有条目的时点数组，没有 AddPlayer/初始化分支。',
         '读取或修改已有玩家的时点数组', dependencies=['scripts/system/global/effect_manager.gd', 'scripts/system/global/game_data_manager.gd'])
reviewed('scripts/system/global/victory_resolver.gd', [18, 23, 30, 43],
         'active_ids 由 get_active_player_ids 返回，所有分支在该已有玩家集合上读取战果/状态；无创建或召唤路径。',
         '读取或修改已有玩家的胜负状态', dependencies=['scripts/system/global/game_data_manager.gd', 'scripts/system/global/effect_manager.gd'])
reviewed('scripts/system/operations/ChangePlOrder.gd', [14, 24, 34],
         'pl_ids 在 10/32 行由 GetAllPlayersId.exec 返回；该 operation 的实现直接遍历 player_data_library.keys，14/24/34 只调整已有条目的 order。',
         '修改已有玩家的顺位', dependencies=['scripts/system/operations/GetAllPlayersId.gd', 'scripts/system/global/game_data.gd'])
reviewed('scripts/system/operations/HideTrueName.gd', [18],
         '15 行已先以 GameData.player_data_library.has(id) 守卫；18 行才读取该已有条目的牌区并执行隐藏，不承担按需建条目。')
reviewed('scripts/system/operations/IsEngaged.gd', [29],
         'other_id 来自 get_board_player_ids 的已有版图参战集合；29 行只读取对手已有条目，未出现 AddPlayer。',
         '读取版图上已有参战条目', dependencies=['scripts/system/global/game_data_manager.gd'])
reviewed('scripts/system/operations/ModifyAttackPowerByAttribute.gd', [31],
         '仅在 attack 为空的扫描分支读取玩家数据；29–30 行已先 has(id) 并在缺失时 return。修改已有条目的威力不等于创建玩家。')
reviewed('scripts/system/regular_play.gd', [307, 327, 406],
         '307 的 submit_group 先调用 can_submit_group，而 240 行 has(id) 缺失即 return；327 只由已通过 submit_group 的流程恢复；406 的 add 先调用 can_add，而 134 行 has(id) 缺失即 return。三处获取的都是已存在玩家条目。',
         '读取或修改已有玩家的常规出牌状态')


# Explicit fixture reviews: the source statements above were read, not names inferred.
HASHES['tests/ask_player_option_test.gd'] = 'ff5f1e8a2ddca8d5a580385e53e9341d5e2e4deb3ccd018ff92be35b3b41d0db'
reviewed('tests/ask_player_option_test.gd', [27], 'setup:20–23 清库后直接把 new_player_data 写到库[0]；run:57/73 先调用 setup，再由 magic 读取常量 0。', '读取/修改已经显式建立的夹具条目', dependencies=[])
HASHES['tests/battle_score_report_test.gd'] = '9c35031871d8b10c62c5495d3cadc76a3acaf4ddfc25c12d21ca9f13849946eb'
reviewed('tests/battle_score_report_test.gd', [66, 70, 89, 99, 101, 103, 113, 130, 138, 154, 155, 161, 163, 204, 210, 239], '_setup:38–51 为 range(3) 的 0/1/2 直接写库；所有测试入口先 _setup，_use_commands/_battle 读取常量 0/1/2 或 [0,1,2] 快照；不是 getter 建夹具。', '读取/修改已经显式建立的夹具条目', dependencies=[])
HASHES['tests/card_history_test.gd'] = '884cb0fdb7bcde5bcb2c78b7a16dd4720465eca83efc07bf662e82a40e075142'
reviewed('tests/card_history_test.gd', [49, 80, 92, 117, 123, 124, 130, 137, 138, 145], 'setup:13–16 清库后为 range(2) 直接建条目；这些调用所在测试在 45/76/88/113/128/143 先 setup，再读写 0 或 1。', '读取/修改已经显式建立的夹具条目', dependencies=[])
HASHES['tests/card_effect_runtime_test.gd'] = '1e3ada13c88a835d166b0df39296a00450722ebbaf938b0c265b460a9f10edf9'
reviewed('tests/card_effect_runtime_test.gd', [117, 140, 149, 157, 165, 186, 188, 203, 205, 211, 213, 235, 251, 261, 326, 330, 341, 359, 360, 378, 395, 396, 414, 437, 438, 441, 455, 495, 508], 'setup:23–29 清库后为 range(player_count) 写入 new_player_data，缺省 3；直接测试先 setup，_rule_breaker_scene:275/_rin_scene:318/_foreigner_scene:387 也先 setup。所列调用只用已建立的 0/1（setup(1) 的分支只用 0；setup(2) 的分支用 0/1），用于读取/修改夹具已有字段。392 的 owner_id=1+i 范围依赖外部 foreigner_count，未包含于本结论。', '读取/修改已经显式建立的夹具条目', dependencies=[])
HASHES['tests/card_keyword_test.gd'] = 'e77d048e871a5b39b2643921d1c19a67b96d6710f1d1789a9bc6fb2b291a0459'
reviewed('tests/card_keyword_test.gd', [90, 103, 145, 168], 'setup:20–23 清库后 range(3) 直接写库；run:80/95/139/167 先 setup 再访问 0。', '读取/修改已经显式建立的夹具条目', dependencies=[])
HASHES['tests/card_revealed_test.gd'] = '0f4193529305f8fcbd2d3fe8ab4a06e561c7defd0501ab16aaeb8b9658b9d27e'
reviewed('tests/card_revealed_test.gd', [131], 'run:124 先 setup(1)，setup:16–19 建立 0..3；129 行 id 来自 get_active_player_ids 已有集合，131 读取当前时点。', '读取/修改已经显式建立的夹具条目', dependencies=[])
HASHES['tests/climax_elimination_test.gd'] = 'ea6e9f926d784858cd1e3db0339671f97925107b7f26ab7e05d58bbb647b68ba'
reviewed('tests/climax_elimination_test.gd', [59, 61, 62], 'run:56 setup(3)；setup:14–17 为 range(count) 直接写库，随后读取 0 的淘汰/位置状态；淘汰只标记而未删条目。', '读取/修改已经显式建立的夹具条目', dependencies=[])
HASHES['tests/create_card_test.gd'] = 'd3ccea39e528e163571d3cc210e6f00f51de5636c639647827cb57821f36be7c'
reviewed('tests/create_card_test.gd', [52, 58, 65, 92, 98, 102, 114], 'setup:22–25 先清库并写入 new_player_data 到库[0]；run:50/56/62/69/109 先 setup，所列调用均是 0 的牌区/资源断言或已有对象引用。', '读取/修改已经显式建立的夹具条目', dependencies=[])
HASHES['tests/deploy_rules_layer_test.gd'] = '20816ae4d3856d2b6ad8a72c82f88be2a3fae669defafbe33c1fa2e23415933c'
reviewed('tests/deploy_rules_layer_test.gd', [42, 43, 64, 66, 74, 79], 'setup:18–21 清库后 range(4) 直接建立条目；run:31/61 先 setup，后续访问常量 0 检查真实部署或缺失部署的状态，不依赖 getter 创建。', '读取/修改已经显式建立的夹具条目', dependencies=[])
HASHES['tests/prepare_phase_test.gd'] = 'a03e21428a477cfce8a7bec966ed8081840a648145da56cb1fe6f604ddbb4a44'
reviewed('tests/prepare_phase_test.gd', [16, 39], 'run:13–14 清库并为 range(3) 直接写 new_player_data；16/39 随后访问 0/1，属于已有夹具数据。', '读取/修改已经显式建立的夹具条目', dependencies=[])
HASHES['tests/requirement_null_test.gd'] = '82d4c1ce0068368e0e963b44dcec00cc2c1af999d4469eb4c1d7243323c7165c'
reviewed('tests/requirement_null_test.gd', [32, 39], 'run:14–15 已清库并显式写入库[0]=new_player_data；32/39 只比较 0 的既有战果。', '读取/修改已经显式建立的夹具条目', dependencies=[])
HASHES['tests/round47_public_test_observer_test.gd'] = 'c7a0946dc28e84b0f7f1385ba607e3aaa430583638af85b07b3ea17a67010508'
reviewed('tests/round47_public_test_observer_test.gd', [26, 33], 'run:13–14 清库后显式建立库[0]；26/33 读取 0 的资源与回滚结果，不靠 getter 建条目。', '读取/修改已经显式建立的夹具条目', dependencies=[])
HASHES['tests/reported_activation_test.gd'] = 'fef1f7cca3a8f3b165b9e2fbdf1031297b66445e03de46127adf7e76e8fefa02'
reviewed('tests/reported_activation_test.gd', [80], 'test_result_change_detail:79 调用 setup；setup:10–13 清库并为 range(2) 建条目；80 读取已有对手 1。', '读取/修改已经显式建立的夹具条目', dependencies=[])
HASHES['tests/newspecial_spell_materialization_test.gd'] = 'ffc71d800bc60999bc396aee3277d7cfd0b70fe8f3dd7e3da2e07bcf17d6e282'
reviewed('tests/newspecial_spell_materialization_test.gd', [19], 'run:16–18 reset 后 game_start([0,1])，player_id 明确赋为 0；GameStart:43→GameData:154–157 预建这些 ID，然后 19 读取已有条目。', '读取/修改已经显式建立的夹具条目', dependencies=['scripts/main_menu/game_start.gd', 'scripts/system/global/game_data.gd'])
HASHES['tests/find_player_data_purity_test.gd'] = '787ba0041ecb5ca54e49266faf7efb6bba0ea6961fdbc42ee082ddf09ca80fcf'
reviewed('tests/find_player_data_purity_test.gd', [49], '23 行库替换为 {42:known}；44 行恢复同一个 fixture_library；49 行读取 42 验证原字典引用，未创建 42。', '读取/修改已经显式建立的夹具条目', dependencies=[])
HASHES['tests/broadcast_command_dispatch_test.gd'] = '3cffca535e4e872da42247e018a522a79d9ee7d9cab3f772c916575f61dcbb90'
reviewed('tests/broadcast_command_dispatch_test.gd', [45], 'run:26–32 清库后遍历 [0,1]，先直接写入库[seat]；45 读取 0 的既有 power。', '读取/修改已经显式建立的夹具条目', dependencies=[])
HASHES['tests/broadcast_absent_confirmation_test.gd'] = '86c1567b5fb6379ec6f74e7ae8086703bb537802a177d44f6e50e6463d42236a'
reviewed('tests/broadcast_absent_confirmation_test.gd', [40], 'battle:29–38 清库后 range(2) 为 0/1 写入 new_player_data；40 修改已有 0 的 power。', '读取/修改已经显式建立的夹具条目', dependencies=[])
HASHES['tests/broadcast_worker_capability_test.gd'] = '9141b7438482eb5ecb7a4500d55535b8f8151616447fc4b27d8e38d191892ebb'
reviewed('tests/broadcast_worker_capability_test.gd', [43], 'battle:32–41 清库后 range(2) 为 0/1 写入 new_player_data；43 修改已有 0 的 power。', '读取/修改已经显式建立的夹具条目', dependencies=[])
HASHES['tests/broadcast_authority_test.gd'] = '5bd728503d6e63deb3d3365774d4063cabb5ea21d130a9570c3aee5fb7cad7ee'
reviewed('tests/broadcast_authority_test.gd', [31], 'battle:20–29 清库后 range(count) 直接写入库[seat]；run 的 battle 调用传入正玩家数，31 只修改已建立的 0。', '读取/修改已经显式建立的夹具条目', dependencies=[])
reviewed('tests/find_player_data_purity_test.gd', [45], '23 行 fixture_library 初值只有 42；27–40 对缺失 ID 仅使用 find 查询而没有入库；44 行恢复该库，45 首次 get(999)，46–48 明确断言 getter 建条目与默认字段。因此该测试刻意依赖隐式创建。', '测试 legacy getter 的创建契约', category='需创建')
for anchor in [('scripts/system/global/time_point_checker.gd', 111), ('scripts/system/global/game_progress.gd', 179)]:
    REVIEWS.pop(anchor, None)
reviewed('scripts/system/global/effect_manager.gd', [960, 961], 'get_player_order_ids:958 从 get_all_players_id（941–942 返回库 keys）过滤独立玩家；960/961 的 a/b 是该已有 ID 快照的排序参数。', dependencies=['scripts/system/global/game_data.gd'])
reviewed('scripts/system/global/effect_manager.gd', [1159], 'queue_time_point_batch:1158 遍历 get_all_players_id（941–942 返回库 keys）；1159 读取这些已有条目的时点并复制快照。', '读取已有条目并捕获时点快照')
reviewed('scripts/system/global/effect_manager.gd', [1183], '_run_next_queued_time_point:1180 遍历历史 players.keys；1181–1182 当前库 has(id) 缺失则跳过，1183 才获取。该 guard 处理快照中玩家失效的情况，不创建。', '修改经 has 守卫的已有条目时点')


# Final conservative corrections: explicit parameters are not library membership.
for anchor in [('scripts/game_scene/battle_board_v2.gd', 5226),
               ('scripts/game_scene/battle_board_v2.gd', 5274)]:
    REVIEWS.pop(anchor, None)
HASHES['scripts/system/operations/FlipCardFace.gd'] = 'ec683ec5bc7f0018140229290b9bb8811c88c840c8e647f4c325ccd879477a56'
reviewed('scripts/system/operations/FlipCardFace.gd', [85],
         '75 行 id 来自 _player_of(card)，103–106 只遍历 player_data_library.keys 并在 played_cards 含 card 时返回；76 行 CardCountsPower 又检查该已存在条目，84 的 counted 为 true 才执行 85。此处同步已有玩家威力，不创建。',
         '修改已拥有该牌的玩家威力', dependencies=['scripts/system/operations/CardCountsPower.gd'])


def mask_noncode(source):
    """Preserve every offset/newline while blanking comments and string literals."""
    out = list(source)
    i = 0
    while i < len(source):
        if source[i] == '#':
            end = source.find('\n', i)
            end = len(source) if end < 0 else end
        elif source[i] in ('"', "'"):
            quote = source[i]
            marker = quote * 3 if source.startswith(quote * 3, i) else quote
            end = i + len(marker)
            while end < len(source):
                if source[end] == '\\':
                    end += 2
                elif source.startswith(marker, end):
                    end += len(marker)
                    break
                else:
                    end += 1
            end = min(end, len(source))
        else:
            i += 1
            continue
        for j in range(i, end):
            if out[j] not in '\r\n':
                out[j] = ' '
        i = end
    return ''.join(out)


def scan_source(source):
    masked = mask_noncode(source)
    starts = [0] + [m.end() for m in re.finditer('\n', source)]
    lines = source.splitlines()
    functions = list(re.finditer(r'(?m)^[ \t]*(?:static\s+)?func\s+(\w+)\s*\(', masked))
    calls, definitions = [], []
    for match in re.finditer(r'\bget_player_data\s*\(', masked):
        line_index = bisect_right(starts, match.start()) - 1
        prefix = masked[starts[line_index]:match.start()]
        if re.search(r'\bfunc\s*$', prefix):
            definitions.append({'line': line_index + 1, 'source': lines[line_index]})
            continue
        opening = match.end() - 1
        depth, end = 1, opening + 1
        while end < len(masked) and depth:
            depth += (masked[end] == '(') - (masked[end] == ')')
            end += 1
        preceding = [f for f in functions if f.start() <= match.start()]
        owner = preceding[-1] if preceding else None
        context_start = max(0, line_index - 5)
        context_end = min(len(lines), line_index + 6)
        calls.append({
            'line': line_index + 1, 'column': match.start() - starts[line_index] + 1,
            'function': owner.group(1) if owner else '<top-level>',
            'function_line': bisect_right(starts, owner.start()) if owner else None,
            'id_expression': source[opening + 1:end - 1].strip() if not depth else source[opening + 1:].strip(),
            'source': lines[line_index], 'balanced_call': depth == 0,
            'context': [{'line': n + 1, 'source': lines[n]} for n in range(context_start, context_end)],
        })
    return calls, definitions


def review_call(path, call, digest, current_hashes=None):
    site = f"{path}:{call['line']}"
    id_expr = call.get('id_expression', '<无法解析>')
    source_line = call.get('source', '').strip()
    if path.startswith('tests/'):
        unknown_reason = (f'保留 unknown：{site} 使用 id 表达式 `{id_expr}`，调用行是 `{source_line}`；'
                          '当前调用点本身没有同时证明该 ID 已由 reset_game_session/AddPlayer 建立，也没有证明这是首次获取即建条目的夹具。')
        missing = ('需要沿本测试的 setup/fixture 追到该调用前，确认 player_data_library 的清空、'
                   'reset_game_session(ids)、AddPlayer.exec 或首次 get_player_data 的顺序；仅常量 ID/字段写入不能替代该证明。')
    elif path.startswith('reports/'):
        unknown_reason = (f'保留 unknown：{site} 来自 reports 下的历史证据副本，调用行是 `{source_line}`；'
                          '它不是当前运行入口，不能把副本中的上下文当作当前初始化/召唤链。')
        missing = ('需要确认该历史副本是否应从扫描范围排除，或提供其对应当前源码/夹具的初始化、召唤、成员绑定或快照来源；'
                   '在此之前不二分。')
    else:
        unknown_reason = (f'保留 unknown：{site} 使用 id 表达式 `{id_expr}`，调用行是 `{source_line}`；'
                          '当前函数内未闭合证明该 ID 来自已有玩家列表/快照/成员绑定，也未闭合证明它来自初始化/召唤创建流程。')
        missing = ('需要继续追踪该 ID 的全部调用方（含 JSON/动态效果参数）、进入本函数前的 has/列表快照，'
                   '以及对应初始化/召唤/AddPlayer 或成员绑定链；不能因函数名、非负 ID 或写字段强行分类。')
    default = {'classification': '无法判定', 'review_status': '待人工追踪',
               'reason': unknown_reason, 'decision_basis': unknown_reason,
               'missing_information': missing, 'data_usage': '未确认', 'evidence': []}
    review = REVIEWS.get((path, call['line']), REVIEWS.get((path, '*')))
    if review is None:
        return default
    dependencies = [path, 'scripts/system/global/game_data_manager.gd'] + review['dependencies']
    if digest != HASHES.get(path) or (current_hashes is not None and any(
            current_hashes.get(p) != HASHES.get(p) for p in dependencies)):
        return {**default, 'review_status': '证据漂移待复审',
                'reason': f'保留 unknown：{site} 的调用方或证据依赖源码指纹改变；旧人工结论撤销，不自动重新确认。',
                'decision_basis': '源码证据漂移，旧结论撤销。',
                'missing_information': '需要按当前源码重新读取调用点及全部证据依赖并重新绑定 SHA256。'}
    reason = review['reason']
    return {k: v for k, v in review.items() if k != 'dependencies'} | {
        'decision_basis': reason, 'missing_information': '',
        'review_status': '人工源码审阅',
        'evidence': [{'path': p, 'sha256': HASHES[p]} for p in dict.fromkeys(dependencies)]}


def source_trace(source, call):
    """Collect observable bindings, not a dataflow proof or semantic classifier.

    Candidate fixture/caller statements are labelled explicitly: their presence
    does NOT prove dominance, successful initialization, or ID membership.
    """
    lines = source.splitlines()
    start = max(0, (call.get('function_line') or 1) - 1)
    stop = call['line'] - 1
    end = next((i for i in range(stop + 1, len(lines))
                if re.match(r'^(?:static\s+)?func\s+', lines[i])), len(lines))
    symbols = sorted(set(re.findall(r'\b[A-Za-z_]\w*\b', call['id_expression'])))
    bindings = []
    if symbols and start < len(lines):
        signature = lines[start]
        if any(re.search(r'\b' + re.escape(sym) + r'\s*(?::|,|\))', signature) for sym in symbols):
            bindings.append({'line': start + 1, 'source': signature, 'kind': '函数参数（类型不证明存在）'})
    for i in range(start + 1, stop):
        line = lines[i]
        if any(re.search(r'(?:\bvar\s+|\bfor\s+|^\s*)' + re.escape(sym)
                         + r'\b[^=\n]*(?:=|\bin\b)', line) for sym in symbols):
            bindings.append({'line': i + 1, 'source': line, 'kind': '局部赋值/循环来源（需核对分支）'})
    # Field bindings elsewhere in the same file are candidates, not proved links.
    for sym in symbols:
        if sym.startswith('_'):
            for i, line in enumerate(lines):
                if not start <= i < end and re.search(r'\b' + re.escape(sym) + r'\s*=', line):
                    bindings.append({'line': i + 1, 'source': line, 'kind': '同文件字段赋值候选（需核对时序）'})
    lifecycle = []
    markers = re.compile(r'GameStart\.game_start\s*\(|reset_game_session\s*\(|setup_players\s*\(|'
                         r'AddPlayer\.|player_data_library\s*(?:\[.*\]\s*=|=|\.clear\s*\()|'
                         r'(?:load|preload)\([\"\']res://.*\.tscn[\"\']\).*instantiate')
    for i, line in enumerate(lines):
        if markers.search(line) and not line.lstrip().startswith('#'):
            lifecycle.append({'line': i + 1, 'source': line, 'kind': '生命周期/夹具候选（不证明调用先后）'})
    function_name = call['function']
    callers = []
    if function_name != '<top-level>':
        for i, line in enumerate(lines):
            if not re.match(r'^\s*(?:static\s+)?func\s+', line) and re.search(
                    r'\b' + re.escape(function_name) + r'\s*\(', mask_noncode(line)):
                callers.append({'line': i + 1, 'source': line, 'kind': '同文件直接调用方候选（不穷尽动态调用）'})
    return {'id_bindings': bindings, 'lifecycle_candidates': lifecycle,
            'local_caller_candidates': callers,
            'evidence_boundary': '这些是逐条源码观察，不是支配关系证明；未验证外部/继承/动态调用，不据此自动二分。'}


def build_report(root):
    files, excluded, errors = [], [], []
    for directory, dirs, names in os.walk(root, followlinks=False):
        kept = []
        for name in sorted(dirs):
            child = Path(directory) / name
            if name.startswith('.') or child.is_symlink():
                excluded.append(child.relative_to(root).as_posix())
            else:
                kept.append(name)
        dirs[:] = kept
        for name in sorted(names):
            if name.endswith('.gd'):
                files.append(Path(directory) / name)
    current_hashes, texts = {}, {}
    for path in sorted(files):
        relative = path.relative_to(root).as_posix()
        try:
            if path.is_symlink():
                excluded.append(relative)
                continue
            raw = path.read_bytes()
            texts[relative] = raw.decode('utf-8-sig')
            current_hashes[relative] = hashlib.sha256(raw).hexdigest()
        except (OSError, UnicodeError) as exc:
            errors.append({'path': relative, 'error': str(exc)})
    calls, definitions = [], []
    for path, source in texts.items():
        found, defs = scan_source(source)
        for call in found:
            call = {'path': path, 'file_sha256': current_hashes[path], **call}
            call.update(review_call(path, call, current_hashes[path], current_hashes))
            call['source_trace'] = source_trace(source, call)
            if call['classification'] == '无法判定':
                trace = call['source_trace']
                observed = []
                for kind, key in (('ID 绑定', 'id_bindings'), ('夹具/生命周期候选', 'lifecycle_candidates'),
                                  ('同文件调用方候选', 'local_caller_candidates')):
                    entries = trace[key]
                    observed.append(kind + '：' + ('；'.join(
                        f"{path}:{entry['line']} `{entry['source'].strip()}`" for entry in entries)
                        if entries else '当前文件未抽取到（不代表不存在外部/继承/动态来源）'))
                call['decision_basis'] = (f"{call['reason']} 实际观察：" + ' | '.join(observed)
                                          + '；候选语句不证明必经、成功初始化或该 ID 属于建库集合。')
                call['missing_information'] += (f" 必须核对 {path}::{call['function']} 的上述绑定/候选调用分支，"
                                                f"证明 `{call['id_expression']}` 在 {call['line']} 行前属于建库集合，"
                                                '或证明缺失 ID 的创建确为此入口责任；无法证明则继续 unknown。')
                call['evidence'] = [{'path': path, 'sha256': current_hashes[path],
                                     'kind': '当前调用点/来源观察（尚未构成二分类证明）'}]
            call['site_id'] = f"{path}:{call['line']}:{call['column']}"
            calls.append(call)
        definitions.extend({'path': path, **definition} for definition in defs)
    counts = Counter(c['classification'] for c in calls)
    groups = {}
    for group in ('scripts', 'tests', 'other'):
        subset = [c for c in calls if (c['path'].split('/')[0] if c['path'].split('/')[0] in ('scripts', 'tests') else 'other') == group]
        groups[group] = {'total': len(subset), **{label: sum(c['classification'] == label for c in subset) for label in LABELS}}
    issues = [
        '计划 195 不能作为强制调用数：真实函数定义单列，不计调用；额外扫描 tests（含 Git 忽略文件），不计隐藏历史工作树。',
        '只读标签仅表示查找不需创建，不表示后续业务或返回的引用不可变；本工具不生成自动替换补丁。',
        '未守卫查询迁移为 find_player_data 后可能返回空字典；直接下标、BaseNumber 强转及别名写入需逐文件设计缺失策略。',
        '无法判定是真实审阅缺口；未穷尽 JSON 动态规则的初始化/召唤链，不将 resolve_player_id 或非负 ID 当作已存在证明。',
        '仅盘点 GDScript 直接 get_player_data(...) 语法；字符串 call/callv、Callable、动态 JSON 方法引用不在直接调用计数中。',
        '未启动 Godot，未运行游戏专项；本任务仅检验静态工具与报告一致性。',
        '本仓库 .gitignore:55 忽略 /reports/；两份报告已写入磁盘但不会默认出现在 git status；本任务不更改忽略规则或强制暂存。',
    ]
    duplicates = len(calls) != len({c['site_id'] for c in calls})
    unbalanced = [c['site_id'] for c in calls if not c['balanced_call']]
    for path, digest in current_hashes.items():
        if hashlib.sha256((root / path).read_bytes()).hexdigest() != digest:
            errors.append({'path': path, 'error': '扫描期间源码变化，请重新运行'})
    return {'schema_version': 2, 'task': 'B24',
            'script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            'scope': '根目录全部非隐藏、非符号链接目录中的 .gd（包含 Git 忽略/未跟踪文件）；不执行游戏',
            'classification_contract': {'只读': '源码用途不需要创建玩家数据，允许后续修改已有数据；不是深层不可变保证',
                                        '需创建': '源码证明缺失 ID 的初始化/召唤或测试建库依赖创建',
                                        '无法判定': '无足够人工证据，或已有证据源码漂移'},
            'summary': {'scanned_files': len(texts), 'caller_files': len({c['path'] for c in calls}),
                        'total_calls': len(calls), 'definitions_excluded': len(definitions),
                        'classifications': {label: counts[label] for label in LABELS},
                        'unknown_count': counts['无法判定'], 'groups': groups},
            'handoff': {'unknown_is_preserved': counts['无法判定'] > 0,
                        'unknown_rule': '每条 unknown 保留 path/line/context/decision_basis/missing_information；没有静态证据的不二分。'},
            'validation': {'unique_locations': not duplicates, 'unbalanced_calls': unbalanced, 'errors': errors},
            'excluded_directories': sorted(excluded), 'definitions': definitions,
            'issues': issues, 'calls': calls}


def markdown_report(report):
    summary = report['summary']
    lines = ['# B24 玩家数据调用分类', '',
             '> 只读 = 获取时不需要创建条目，不等于后续业务只读；unknown（无法判定）保留，不强行二分。', '',
             f"扫描 {summary['scanned_files']} 个 GDScript，{summary['caller_files']} 个调用方；直接调用 **{summary['total_calls']}** 处，排除定义 {summary['definitions_excluded']} 处。", '',
             f"unknown 逐条交接字段：路径:行、调用点上下文、判定结论、判定依据、缺失信息。当前 unknown **{summary['unknown_count']}** 条。", '',
             f"脚本 SHA256：`{report['script_sha256']}`", '',
             '| 范围 | 调用数 | 只读 | 需创建 | 无法判定 |', '|---|---:|---:|---:|---:|']
    for group, values in summary['groups'].items():
        lines.append('| ' + group + ' | ' + ' | '.join(str(values[k]) for k in ('total', *LABELS)) + ' |')
    lines += ['', '## 方法与证据边界', '', report['scope'], '',
              '词法扫描负责定位；人工证据表负责语义；JSON/Markdown 负责输出。人工结论绑定完整文件 SHA256 和依赖指纹，改变后退回待审。'
              'JSON 的 context 保留原行号源码；evidence 指向审阅文件及指纹，reason/decision_basis 记录判据；文件名只作身份，不作语义规则。', '',
              '判定为只读的依据必须落到已有玩家列表、初始化后成员绑定、顺位/战场快照、效果 trigger 归属或明确 has 守卫；“函数名像 getter”、非负 ID、写字段都不构成依据。',
              '开局证据：GameStart:43 调用 GameData.reset_game_session，GameData:154–157 为每个传入 id 写入 new_player_data；GameStart:58 虽位于初始化流程仍不需要隐式创建。',
              '创建证据：tests/net_round_identity_feedback_test.gd:6 清空库、:8 遍历新 ID、:9 首次获取后写顺位。', '',
              '## 问题与未验收项', '']
    lines += ['- ' + issue for issue in report['issues']]
    lines += ['', '## 静态验证', '', '```json', json.dumps(report['validation'], ensure_ascii=False, indent=2), '```', '',
              '## 逐调用点清单', '', '| 路径:行:列 | 函数 | ID 表达式 | 分类 | 审阅状态 | 调用点上下文 | 判定依据/缺失信息 |', '|---|---|---|---|---|---|---|']
    def escape(text):
        return str(text).replace('|', '\\|').replace('\n', ' ').replace('\r', '')
    for call in report['calls']:
        context = ' ⇢ '.join(f"{item['line']}: {item['source'].strip()}" for item in call['context'])
        basis = call.get('decision_basis', call['reason'])
        missing = call.get('missing_information', '')
        if missing:
            basis += '；缺失：' + missing
        values = [call['site_id'], call['function'], call['id_expression'], call['classification'],
                  call['review_status'], context, basis]
        lines.append('| ' + ' | '.join(escape(v) for v in values) + ' |')
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--check', action='store_true', help='compare saved reports without writing')
    args = parser.parse_args()
    root = args.root.resolve()
    report = build_report(root)
    outputs = {
        root / 'reports/refactoring/player-data-calls.json': json.dumps(report, ensure_ascii=False, indent=2) + '\n',
        root / 'reports/refactoring/player-data-calls.md': markdown_report(report),
    }
    if report['validation']['errors'] or report['validation']['unbalanced_calls'] or not report['validation']['unique_locations']:
        print(json.dumps(report['validation'], ensure_ascii=False))
        return 1
    stale = []
    for path, content in outputs.items():
        if args.check:
            if not path.exists() or path.read_text(encoding='utf-8') != content:
                stale.append(path.relative_to(root).as_posix())
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding='utf-8', newline='\n')
    print(json.dumps({'summary': report['summary'], 'stale_reports': stale}, ensure_ascii=False, indent=2))
    return 1 if stale else 0


if __name__ == '__main__':
    raise SystemExit(main())
