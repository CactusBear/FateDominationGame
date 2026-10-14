# 已归档回归成本（停止扩展）

按最新指令停止新增测速、基准、调度仿真和泛分析；未启动 Godot/full/续跑，生产及所有 runner 未修改。

已收集数据：`E:/scratch/regression-cost-preserved-20261010-1935/`
- `rows.json`：195条去重执行记录，保留真实 PID、command、label、duration、scene、退出/安全中止及原 manifest 索引。
- `sourcehash.json`：8份原 manifest 的绝对路径与 SHA256。
- `profile.json`：历史成本合计4367.601秒；这是跨轮已启动进程投入，不是当前全量通过或提速数字。round73只记录已启动部分。

最小保存工具：`tools/diagnostics/regression_cost_profile.py`，没有 benchmark/simulation 执行入口。
执行：`python -B tools/diagnostics/regression_cost_profile.py --output E:/scratch/<新的独占目录>`。
离线断言已通过：重复累计 manifest 不双计；非法/缺失 duration 处理；分项合计；195 rows/8 sources 精确JSON读回。未新增持续单测文件。

计时覆盖启动至 Job 排空，不是场景纯耗时；Job tail、复制/hash/归档、开发编辑时间无独立原始计时，保留 unknown，不用总 wall 相减伪分段。静态并行分类/进一步优化建议按最新指令取消，没有宣布任何 suite 已可并行。
