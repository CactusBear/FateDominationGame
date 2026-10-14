# Python真实发射的GDScript诊断读取补充清单

仅四个经调用点人工确认会被write_text/replace真实注入的字面量；词法工具闸门测试和源码迁移旧锚点不算运行时读取；任意动态生成片段仍非穷尽证明

主报告：../gd/report.md。本表与主报告没有文件路径重叠；每条保留Python原始行和发射后的GDScript行。

{
  "verified_templates": [
    {
      "path": "tools/tests/round64_shared_browsing.py",
      "line": 24,
      "template": "BROWSING_SCRIPT",
      "generated_lines": 146
    },
    {
      "path": "tools/tests/round64_shared_browsing.py",
      "line": 74,
      "template": "diagnostic",
      "generated_lines": 1
    },
    {
      "path": "tools/tests/round69_modal_hover.py",
      "line": 28,
      "template": "SPECIAL_VIEWER_SCRIPT",
      "generated_lines": 73
    },
    {
      "path": "tests/round55_gui_first_divergence_runner.py",
      "line": 67,
      "template": "NET_DIAGNOSTIC",
      "generated_lines": 10
    }
  ],
  "state_reads": 18,
  "observation_reads": 15,
  "categories": {
    "需要新增公开能力": 18
  },
  "observation_categories": {
    "需要新增公开能力": 15
  },
  "unresolved": 4,
  "excluded": {
    "纯赋值排除": 1,
    "私有方法调用排除": 5
  },
  "limitations": "仅四个经调用点人工确认会被write_text/replace真实注入的字面量；词法工具闸门测试和源码迁移旧锚点不算运行时读取；任意动态生成片段仍非穷尽证明"
}

## 可立即替换：0处

## 需要新增公开能力：18处

- tools/tests/round64_shared_browsing.py:24 [BROWSING_SCRIPT生成行82]：board._seat_controller → scripts/game_scene/battle_board_v2.gd:144；公开等价：没有确认完全等价入口；对象/容器读取后修改；声明/类型/资源路径
- tools/tests/round64_shared_browsing.py:24 [BROWSING_SCRIPT生成行99]：board._source → scripts/game_scene/battle_board_v2.gd:151；公开等价：没有确认完全等价入口；相关但不等价：refresh_all_ui@608；读取；声明/类型/资源路径
- tools/tests/round64_shared_browsing.py:24 [BROWSING_SCRIPT生成行133]：board._source → scripts/game_scene/battle_board_v2.gd:151；公开等价：没有确认完全等价入口；相关但不等价：refresh_all_ui@608；读取；声明/类型/资源路径
- tools/tests/round64_shared_browsing.py:74 [diagnostic生成行1]：board._fly_layer → scripts/game_scene/battle_board_v2.gd:225；公开等价：没有确认完全等价入口；读取；唯一生产符号（静态归属推断）
- tools/tests/round64_shared_browsing.py:74 [diagnostic生成行1]：board._fly_busy → scripts/game_scene/battle_board_v2.gd:232；公开等价：没有确认完全等价入口；读取；唯一生产符号（静态归属推断）
- tools/tests/round64_shared_browsing.py:74 [diagnostic生成行1]：board._fly_queues → scripts/game_scene/battle_board_v2.gd:231；公开等价：没有确认完全等价入口；读取；唯一生产符号（静态归属推断）
- tools/tests/round69_modal_hover.py:45 [SPECIAL_VIEWER_SCRIPT生成行18]：board._seat_controller → scripts/game_scene/battle_board_v2.gd:144；公开等价：没有确认完全等价入口；对象/容器读取后修改；声明/类型/资源路径
- tools/tests/round69_modal_hover.py:53 [SPECIAL_VIEWER_SCRIPT生成行26]：object._is_awakened → scripts/system/base_skill.gd:14；公开等价：没有确认完全等价入口；相关但不等价：clone_data@4；读取；唯一生产符号（静态归属推断）
- tools/tests/round69_modal_hover.py:56 [SPECIAL_VIEWER_SCRIPT生成行29]：master._other_things → scripts/system/base_master.gd:23；公开等价：没有确认完全等价入口；相关但不等价：clone_data@4；读取；唯一生产符号（静态归属推断）
- tools/tests/round69_modal_hover.py:63 [SPECIAL_VIEWER_SCRIPT生成行36]：board._local_player_id → scripts/game_scene/battle_board_v2.gd:165；公开等价：没有确认完全等价入口；相关但不等价：refresh_all_ui@608；读取；声明/类型/资源路径
- tools/tests/round69_modal_hover.py:71 [SPECIAL_VIEWER_SCRIPT生成行44]：card._card_back_img → scripts/system/base_card.gd:32；公开等价：没有确认完全等价入口；相关但不等价：copy_clone_fields@11；读取；声明/类型/资源路径
- tools/tests/round69_modal_hover.py:71 [SPECIAL_VIEWER_SCRIPT生成行44]：card._card_back_img → scripts/system/base_card.gd:32；公开等价：没有确认完全等价入口；相关但不等价：copy_clone_fields@11；读取；声明/类型/资源路径
- tools/tests/round69_modal_hover.py:73 [SPECIAL_VIEWER_SCRIPT生成行46]：board._source → scripts/game_scene/battle_board_v2.gd:151；公开等价：没有确认完全等价入口；相关但不等价：refresh_all_ui@608；对象/容器读取后修改；声明/类型/资源路径
- tools/tests/round69_modal_hover.py:74 [SPECIAL_VIEWER_SCRIPT生成行47]：board._source → scripts/game_scene/battle_board_v2.gd:151；公开等价：没有确认完全等价入口；相关但不等价：refresh_all_ui@608；读取；声明/类型/资源路径
- tests/round55_gui_first_divergence_runner.py:70 [NET_DIAGNOSTIC生成行4]：guest._seq → scripts/net/session/lobby_session.gd:105；公开等价：没有确认完全等价入口；相关但不等价：request@602; submit_catalog@1188；读取；唯一生产符号（静态归属推断）
- tests/round55_gui_first_divergence_runner.py:70 [NET_DIAGNOSTIC生成行4]：board._battle_command_observer → scripts/game_scene/battle_board_v2.gd:159；公开等价：没有确认完全等价入口；读取；唯一生产符号（静态归属推断）
- tests/round55_gui_first_divergence_runner.py:70 [NET_DIAGNOSTIC生成行4]：board._battle_commands → scripts/game_scene/battle_board_v2.gd:156；公开等价：没有确认完全等价入口；读取；唯一生产符号（静态归属推断）
- tests/round55_gui_first_divergence_runner.py:70 [NET_DIAGNOSTIC生成行4]：board._end_command_attempt → scripts/game_scene/battle_board_v2.gd:163；公开等价：没有确认完全等价入口；读取；唯一生产符号（静态归属推断）
## 应保留许可（不可等价）：0处


## 未消歧候选

- tools/tests/round64_shared_browsing.py:24 [BROWSING_SCRIPT生成行101]：_name；候选生产文件：scripts/net/p2p/p2p_signal_client.gd, scripts/net/session/authority_host_client.gd, scripts/system/base_func.gd, scripts/system/base_object.gd；未消歧，不能确认等价入口
- tools/tests/round69_modal_hover.py:51 [SPECIAL_VIEWER_SCRIPT生成行24]：_name；候选生产文件：scripts/net/p2p/p2p_signal_client.gd, scripts/net/session/authority_host_client.gd, scripts/system/base_func.gd, scripts/system/base_object.gd；未消歧，不能确认等价入口
- tools/tests/round69_modal_hover.py:52 [SPECIAL_VIEWER_SCRIPT生成行25]：_name；候选生产文件：scripts/net/p2p/p2p_signal_client.gd, scripts/net/session/authority_host_client.gd, scripts/system/base_func.gd, scripts/system/base_object.gd；未消歧，不能确认等价入口
- tools/tests/round69_modal_hover.py:57 [SPECIAL_VIEWER_SCRIPT生成行30]：_name；候选生产文件：scripts/net/p2p/p2p_signal_client.gd, scripts/net/session/authority_host_client.gd, scripts/system/base_func.gd, scripts/system/base_object.gd；未消歧，不能确认等价入口
