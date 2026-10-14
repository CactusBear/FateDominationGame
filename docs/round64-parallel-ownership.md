# Round64：十路并行写入边界

用户明确要求继续重构并尽可能使用十个子代理。本轮保留两项已开始的根因调查，新增八项独立任务。此表是写入授权与整合顺序，不是通过证据。

## 文件唯一写入者

| 执行者 | 工作 | 写入范围 |
|---|---|---|
| sa-0-7569ad30 | 恢复原生 ENet 断线原因 | round61_restart_agent_runner、restart测试诊断、新round63诊断；生产网络只读 |
| sa-1-6f7f7670 | 观测器与发布锁因果 | 新round63 observer诊断与报告；生产和旧工具只读 |
| sa-0-9f9ea6be | 小范围共享浏览入口、出牌分组视觉 | board、presenter、battle_play_groups测试及独立专项；本轮唯一GUI执行者 |
| sa-1-eb7beeff | 新候选契约与实际计数 | test_round29_integrated_evidence、test_round50_candidate_selection及独立单元 |
| sa-2-34ff7b3c | 正式包运行编排 | round56_three_role_freeze及专属单元；不签token、不导出可变源码 |
| sa-3-3baeb13e | 可选原生清理适配器 | temporary_cleanup_executor、独立清理适配器和专项；不接manager调度 |
| sa-4-6e11aa1f | 原方案逐项对账 | 只写refactoring-delivery-matrix.md |
| sa-5-e3f1a158 | 私有测试消费迁移 | 未被其他任务占用的小范围GD测试；gate只读，主代理退休许可 |
| sa-6-219cac8c | 原生合同单一来源 | native_capability_view、bootstrap/console中仅合同声明和引用、纯合同模块 |
| sa-7-f55e1eb1 | 保存失败诊断边界 | 新单职责纯诊断组件与专项；仅提交Session接线建议 |

## 整合约束

- 每项先读取定义及调用链，中文说明耦合取舍和具体修改，再使用V4A。不得用大范围兼容字段代替迁移。
- 原Godot、正式DLL、默认模拟15秒、线程池20不变。新原生DLL仅用于隔离能力验收。
- Session、gateway、room manager、shutdown、规则本轮无生产写入者。保存诊断与恢复修复须主代理拿到因果后串行接线。
- 每个测试使用自足冻结与真实依赖hash；其他任务修改主工作树不能被隐瞒为无漂移，也不能拿不同冻结结果拼成整体通过。
- E盘物理隔离，自有PID/Job闭环；不得操作用户进程和旧gateway28100。正式存档、身份、未确认保存证据不得清理。
- 自动清理缺完整实例登记或排他证明时保持blocked。可选remove_verified不能变成原四类十三方法启动合同中的新增强制要求。
- 原生合同去重复保持原集合、权限与status字段；不通过自动枚举DLL方法推导授权。
- 新候选执行器只做专项接入与小批验证，本轮不直接重跑全98套。
- UI只迁有界同义入口，不同时重写规则、身份、恢复。窗口和视觉结论必须与实际输入及截图一致。
- 发行编排的未执行阶段明确NOTRUN；最终源码未稳定、各前置未核验前不签发行ready token。

## 父代理验收

读回报告所指原始manifest、日志、source/artifact hash及退出结果；准确区分实现、专项通过、视觉通过和发行通过。只有失去实际调用点的依赖许可才能退休。整体交付继续以恢复、保存可靠性、统一冻结回归和真实三角色EXE验收为门槛。
