# Round47并行写入边界与Round48优先反馈

## 用户最新指令

继续重构，尽可能10子代理。默认模拟预算由30秒改为15秒；保持原引擎不变，使用Godot MCP追项目/扩展根因。用户新反馈倒计时结束似乎不能宣布校验成功，优先定位完成链；不以归零直接批准，不跳风险确认。

## 唯一写入者

|执行者|允许修改|禁止共享写入/接线方式|
|---|---|---|
|sa-0-2a9d86fa|倒计时完成链：validation task/worker/preparation/simulation、server_data_approval、room_data_panel及自有默认/窗口测试|升级为反馈bug唯一生产写者、唯一窗口执行者；Session接口由另一owner交主串行整合|
|sa-2-f622eb57|独立原生构建契约报告及只读审计工具|现DLL/source/SConstruct只读、不启动原生/窗口|
|sa-0-1571e42f|battle_board_v2、new battle_host_lifecycle及自有测试|presenter/Session/source只读，生命周期闭包后交窗口owner|
|sa-1-d33056ae|v2_view_presenter、new shared_view_sections及自有测试|board只读，缺入口由主在board owner交付后串行接线|
|sa-2-6258fea6|lobby_session、new server_data_status_inbox及自有测试|approval/panel/validation只读，保持ready风险确认→commit合法，终态不复活|
|sa-3-95de2eaf|server_bootstrap、server_room_manager及自有测试|validation_task/native/cleanup只读，新route接口主后接，许可主退休|
|sa-4-36569fe4|new temporary_cleanup_core .hpp/.cpp及独立native probe测试|现native/DLL/SConstruct、executor/ledger只读，原子能力先验、不得假定完整实例登记或启用自动删档|
|sa-5-78e2536e|command_spell、ask_player_option、requirement_null、session_restart、debug_console_pause测试|生产/闸门只读，保留原覆盖，退休锚点交主|
|sa-6-58925251|assembly_publish_failure_capture及自有定点测试|原生产/引擎只读，最多两次有效定点观察，不把对照成功消除业务红|
|sa-7-5e73f137|acceptance_root_transaction、linux_paused_recovery、ui_refresh_cost_board测试|生产/其父测试/闸门只读，修实际MCP发现的过期契约，不造空方法|

主代理独占assets/config/server.cfg、统一待决/执行记录、tools/check_layer_deps.py的许可退休。当前已经修改默认15秒，最新验证结果须绑定当前配置，不用历史30秒日志充抵。

## 验收边界

- 独立物理E冻结，不在并发可变源树上导入或测试；一文件一owner，不操作用户原编辑器关闭、不按进程名终止用户Godot。
- short套件≤180秒，原自然终局正确性与性能门单列；本批不反复70大回归，所有接口完成后最终新冻结统一运行。
- 模块创建不等于消费者接线，不以归档.gdignore/globalclass修复冒称原生冷导入已修。
- 闸门基线80/80 new=0 stale=0，7项layer为启动路由、73项private来自遗留测试/诊断夹具；不能笼统称都是生产内核私有依赖。许可只能按确实消失锚点退休，不能扩大或遮蔽扫描范围。
- 合法RESULT、真实退出、无SCRIPT/engine错误、前后hash、必要GUI原生截图及进程/生成树回收是交付条件；代理报告由主读回复核，不拼多个版本称整体完成。
