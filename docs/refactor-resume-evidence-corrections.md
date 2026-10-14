# 重构复验：证据纠正与窗口要求裁定

## 联机截图不属于本轮生成

主代理读回 `E:/scratch/refactor-resume-ui-contract/report.md`，并独立对比两份图像字节与原运行日志。

- `E:/scratch/current-business-live-test/screenshots/net_v2_ui_input_parity.png` 与工程 `tests/runtime_reports/net_v2_ui_input_parity.png` 的 SHA256 均为 `0c05296b7c83998394ac12196f287c4f0a634905588c9c5539c282e11f8297fc`。
- 原日志 `supp-tests-net_v2_ui_input_parity_window_test-window.stdout.log` 显示两次等待后 `view_seq=-1`；最终 `RESULT checks=6`，三条失败，没有截图保存成功记录。
- 专项在手牌前置失败时提前退出，未达到截图保存点。采集器复制了隔离工程中已有的 runtime_reports 图像。
- 撤回“13张全部本轮生成”及该联机图属于本轮战板画面证据的表述。保留原证据、不覆写原日志和历史 JSON；该图标为历史图，不参与本轮验收。其它图像仍须逐项核对实际生成回执，不能以文件存在或摘要相等单独认证运行归属。
- 45次运行、14次严格通过、31次非通过，以及3项窗口专项均失败的日志统计不变。

后续采集仅收本次独占输出目录中、具有实际到达保存点记录的图像；冻结输入不携入旧 runtime_reports 截图。

## 三条旧窗口要求不作为生产修复目标

依据 `docs/user-decisions-2026-10-11.md:75–84`，用户拒绝缺字段表现改造、独立可折叠顺位表、顶栏玩家名修改。

`newtests/round75_order_resources_window_test.gd` 的以下三条历史失败登记为与现行授权冲突：

1. `A 行动顺位表真实展开折叠入口存在`。
2. `A 顺位1显示真实玩家名`。
3. `B 缺字段不显示占位垃圾数值`。

不据此改变生产 UI、不重新要求用户批准已拒绝功能；原失败及原断言暂保留。将来迁移该专项时应显式分离历史需求检查与现行授权验收，不把排除旧要求记作修复通过。

## 候选采纳边界

- native choices 的测试创建来源候选待运行验证；真实支付、取消和目标人数断言保留。
- net parity 候选通过直接填写 authority 私有来源构造前置，只可作为诊断对照，尚不采纳为正式业务验收。正式验收应迁移到现有可信选人/开局入口，不能以 started=true 加私有赋值替代真实启动。
- 提示队列末条未出现根因仍未定；先排除上游失败污染，保留原期限和断言，不能直接加等待时间刷绿。

本文件是主代理的证据纠正和范围裁定，不代表新增 Godot 通过记录或生产修复完成。
