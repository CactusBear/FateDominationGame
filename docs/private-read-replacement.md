# 私有读取替换结论（历史回执迁入）

## 已确认结论

- 原审计的 11 处候选中，**九处已等价替换，涉及六个消费者文件；两处保留**。本次只迁移证据，没有再次改源码或重跑 Godot。
- 原 `receipt.json` 的六个已改消费者与一个未改消费者的当前 SHA256 均与 `after_sha256` 一致；原九处读签名在本次主扫描中已消失。
- `tests/authority_revision_query_test.gd:18,40` 是公开查询自身准确性及查询不改内部水位的独立 oracle。改为被测 `current_revision()` 会降低断言强度，因此不替换、不删断言，人工结论为“需要新增公开能力”。
- 两个扫描器沿用原分类代码，仍把这两处标为“可立即替换”；该工具局限与人工纠正独立记录，**没有修改原或新 inventory 数据**。

## 完整 11 条处置

|消费者:行|owner|处理|
|---|---|---|
|`newtests/play_affordance_rule_audit_test.gd:75`|`scripts/system/base_card.gd`|已等价替换（历史任务）|
|`scratch/transaction-return-consumers/transaction_return_consumers_test.gd:280`|`scripts/net/authority/match_authority.gd`|已等价替换（历史任务）|
|`tests/authority_revision_query_test.gd:18`|`scripts/net/authority/match_authority.gd`|保留；需要新增公开能力（独立 oracle）|
|`tests/authority_revision_query_test.gd:40`|`scripts/net/authority/match_authority.gd`|保留；需要新增公开能力（独立 oracle）|
|`tests/climax_gated_ability_test.gd:62`|`scripts/system/base_card.gd`|已等价替换（历史任务）|
|`tests/match_finished_authority_test.gd:59`|`scripts/net/authority/match_authority.gd`|已等价替换（历史任务）|
|`tests/match_finished_authority_test.gd:63`|`scripts/net/authority/match_authority.gd`|已等价替换（历史任务）|
|`tests/match_finished_authority_test.gd:83`|`scripts/net/authority/match_authority.gd`|已等价替换（历史任务）|
|`tests/match_finished_authority_test.gd:86`|`scripts/net/authority/match_authority.gd`|已等价替换（历史任务）|
|`tests/refactor_net_area_diagnostic.gd:180`|`scripts/net/authority/match_authority.gd`|已等价替换（历史任务）|
|`tests/servant_skill_eight_magic_test.gd:85`|`scripts/system/base_card.gd`|已等价替换（历史任务）|

原等价入口：`BaseCard.has_attribute(原参数)` 原样执行 `_attributes.has`；`NetworkMatchAuthority.current_revision()` 原样返回 `_revision`。原替换回执包含原位差异及改前/改后 SHA256，见下方仓库内证据。

## 为什么不能减允许清单

`tools/check_layer_deps.py:25–29` 的 OWNERS 只有：

- EffectManager → `scripts/system/global/effect_manager.gd`
- GameProgress → `scripts/system/global/game_progress.gd`
- DummyBot → `scripts/system/ai/temp/dummy_bot.gd`

11 条的 owner 均不在这三个路径内，receipt 与原 inventory 的 `gate_owner` 全部 false：**0/11，因此本次九处替换不能减少允许清单**。迁移期间 gate 摘要保持不变；不运行/更新 gate、不修改允许项。

## 历史运行验收的限定

原回执记录同一冻结版本的六个逻辑套件通过、CHECK 合计 617；一个区域诊断在 headless 下返回 `checks=0 window_only=true`，不计通过。原总执行器 exit 1/manifest.passed=false，还记录了外部源漂移。这不是当前树或发行全绿，也不是窗口验收。
这些结果是迁入的历史记录，不是本次执行。本次只跑 Python 静态扫描器：第一次合并观察读取 4104，第二次 4108；原报告 4048。逐项对比和不穷尽/非冻结边界见 [审计文档](private-read-audit.md)。

## 固定证据位置

- `tools/audit/private_reads/baseline/replacement/REPORT.md`：原替换说明，字节不变。
- `tools/audit/private_reads/baseline/replacement/receipt.json`：原处置、改前后摘要、人工纠正及验收边界，字节不变。
- 同目录 `before.json`、`changes.json`、`migration.patch`：完整 11 条与精确九处差异；不再次应用 patch。
- 同目录 `execution/manifest.json`、`execution/evidence/*.log`：原实际日志与结果。保留原 manifest 绝对路径字段，仅供历史溯源，不依赖其旧生成目录。
- `tools/audit/private_reads/baseline/audit/gd/inventory.json`：原审计明细及公开方法索引，未做分类纠正回写。
- `tools/audit/private_reads/runs/migration-20261011/comparison.json`：本次计数、签名差异、SHA256 和验证回执。
- `tools/audit/private_reads/SHA256SUMS.txt`：本次全部文件 SHA256（不含清单自身）。

“保持可复现”仅指仓库内扫描入口、所需历史数据和真实输出可直接重跑/核对；没有承诺重造历史 Godot 冻结环境，没有把缺失的旧全树源码/引擎伪装成可重放包。
