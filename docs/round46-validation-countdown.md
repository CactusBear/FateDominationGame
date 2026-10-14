# MCP项目扫描与服务器校验倒计时

## 已实施

- `reports/.gdignore`隔离测试证据归档，保留原始日志、脚本、BMP，不再把归档作为正式资源/全局类来源。不是删除证据，也不把它当作原生崩溃修复。
- `rule_random_simulation.gd`只读progress信号在实际模拟开始后报告真实预算与剩余时间，不修改run参数、deadline、规则推进或报告批准。
- `room_data_validation_worker.gd`每显示秒原子写本次目录progress.json；与静态检查点report.json分离，进度写失败不赋予批准能力。
- `room_validation_task.gd`从当前任务独占目录读取进度，检查phase、预算匹配、有限数、单调sequence与剩余时间不倒涨；读取句柄在解析前关闭。按本地单调时钟消减，不比较不同进程的ticks。没有真实模拟进度时维持原静态校验文案。
- `room_data_preparation.gd`复用task.status_text；ServerDataApproval既有text差异发布、服务端状态消息、RoomDataPanel及后台提示沿同一条链显示，不加第二套UI或改变线协议。
- 剩余时间向上取整；归零仅提示“随机模拟预算已用尽，正在收尾”，不宣称校验成功。取消、进程结束清除当前进度，重启任务不能沿用旧sample。禁用/零预算不展示倒计时。

## 主代理真实验证

- `validation_countdown_contract_test`业务RED：exit1，2项准确缺API断言；不是脚本解析错误。GREEN：exit0，21 checks/failures=[]/无引擎错误。覆盖预算匹配、坏类型、负数、无穷数、重复/非整数sequence、归零不得批准、取消/重启失效。
- 日志`reports/refactoring/main-review/countdown-contract-red.log`、`countdown-contract-green.log`。
- `python tools/check_layer_deps.py`：PASS findings=80 allowlist=80 new=0 stale=0。
- `git diff --check -- scripts/net/validation reports/.gdignore`：exit0。

## MCP观察和实际修复边界

- 精确session `fatedominationgame-master@ecc0ba7efcb336f7`，原编辑器PID17120，4.7.2-stable，ready/stopped；未关闭用户编辑器、未修改主场景或引擎。
- logs_read source=editor详细读取358条：归档BMP无法导入、归档脚本全局类重复；另有旧测试依赖和override签名的解析错误。
- 通过filesystem_manage.scan + 对8个真实生产脚本的update_file刷新，编辑器global_script_class_cache恢复生产res://scripts来源；此前RoomValidationTask缓存曾指向reports里的frozen-source，实际headless出现class hides global class。
- 修后MCP filesystem_manage.search path reports/refactoring返回total_count=0；logs_read since_cursor358 returned_count=0；直接Godot专项不再有归档导致的Class hides错误。旧历史日志原样保留，不能据无新增日志称所有旧测试或导出已通过。
- 原MCP日志在Hermes本轮spillover `call_f21f38751efe.txt`及`call_81fd1612131a4f2699062f49333ca7bd.txt`。原生冷导入崩溃仍交独占诊断者从项目启动/ABI/初始化因果对照追踪。

## 未验项

用户随后将默认预算改为15秒。Round48完成冻结内72项真实GUI及13项默认配置契约、CLI内部24项、204文件23项准备专项；主代理已核验GUI原manifest SHA及面板/approval当前源码hash。但GUI执行冻结未覆盖并行更新后的Session/statusinbox，正在Round49串行复验，仍不称最终统一候选通过。详见docs/round48-countdown-completion.md。生产变更后Round43历史70套不覆盖当前新功能版本。
