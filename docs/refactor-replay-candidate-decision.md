# 回放恢复候选采纳裁定

## 当前决定：不安装测试绕行候选

已读 `E:/scratch/refactor-refill-replay/report/report.md` 及其 `candidate/newtests/replay_batch_origin_fixture.gd`。

候选在每个原 AI tick 前增加 `replay.perform("deploy_to_area", [area, player_id])`，由测试挑选可用战区。该操作使用真实公开接口并记录journal，但替换了原AI负责部署的路径，不是单纯传递现有创建来源。

生产DummyBot/MatchDriver来源缺口已有专属候选和真实局部红绿证据（`E:/scratch/refactor-resume-deploy/`），无需让回放测试代做部署。正收益部署还受EM/EditMagic等待动作来源缺口阻断。

- 此份回放候选保留作诊断，不合入主源，不算回放修复，不声称恢复成功。
- 下一次回放验收优先保留原 `tests/replay_restore_batch_test.gd` 字节，安装经过核验的生产来源修复及后续正收益修复后执行。
- 若原测试仍有独立合法来源缺口，再按首个真实失败迁移；不能将额外部署调用当生产修复的替代。
- 原恢复、广播批次、指纹断言及原失败日志保留。当前动态状态仍未通过。
