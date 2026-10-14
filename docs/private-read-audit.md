# 私有读取审计：仓库内迁移与可复现边界

## 结论

- 两个扫描器已迁入 `tools/audit/private_reads/`，只用 Python 标准库与仓库现有 gate 的词法器；不启动 Godot。仓库根默认从脚本位置推导，CLI 输入/输出均可按仓库相对路径指定。
- 扫描范围、排除规则、归属分析与分类代码均未改变；15 个分析辅助函数及主分析段 AST 对比一致。只改 CLI/路径入口、输出位置保护、报告链接与 root 元数据。
- 历史 inventory 与证据按字节保存于 `baseline/`，不回写原数据。历史文档/回执里的旧绝对路径只作溯源，不是运行依赖。
- 第一次仓库内重跑，两条命令均 exit 0；与原报告计数**不一致**。第二次从仓库外工作目录、省略 `--root` 重跑，两条也均 exit 0，但树内新增文件导致 GD 计数再次改变。不是冻结全树的同输入重放；不得宣称两次 GD 结果相同。

## 主口径：观察读取

排除纯赋值、私有方法调用、读改写、取容器/对象后修改。每个词法出现独立计数；状态读取扩展口径另外统计，不能混用。

|快照/范围|可立即替换|需要新增公开能力|应保留许可（不可等价）|合计|
|---|---:|---:|---:|---:|
|原报告：现行测试/诊断 + scratch + 已核验 Python 发射片段|11|3306|155|3472|
|原报告：上述 + 树内历史诊断证据|11|3833|204|4048|
|第一次重跑：现行 + scratch + Python|2|3369|157|3528|
|第一次重跑：含历史|2|3896|206|4104|
|第二次重跑：现行 + scratch + Python|2|3373|157|3532|
|第二次重跑：含历史|2|3900|206|4108|

这些是扫描器原始分类，不包含替换回执对两处独立 oracle 的人工纠正：扫描器仍把 `tests/authority_revision_query_test.gd:18,40` 标为“可立即替换”，但实际不能同强度替换，应视为“需要新增公开能力”。两处保留且不改 inventory，详见 [替换结论](private-read-replacement.md)。

### 包含容器修改/复合赋值的扩展状态口径

|快照|可立即替换|需要新增公开能力|应保留许可（不可等价）|合计|
|---|---:|---:|---:|---:|
|原报告|11|4294|228|4533|
|第一次重跑|2|4360|230|4592|
|第二次重跑|2|4366|230|4598|

## 真实命令、退出码与重跑方式

在仓库根目录执行（Git Bash；Python 3，标准库）：

```bash
PYTHONDONTWRITEBYTECODE=1 python tools/audit/private_reads/scan_private_reads.py --root . --output tools/audit/private_reads/runs/migration-20261011/gd
PYTHONDONTWRITEBYTECODE=1 python tools/audit/private_reads/scan_embedded_reads.py --root . --core tools/audit/private_reads/runs/migration-20261011/gd/inventory.json --output tools/audit/private_reads/runs/migration-20261011/embedded
```

两条 exit 都是 **0**。完整 stdout/stderr 与生成的 `gd/`、`embedded/` 报告和 inventory 位于 `tools/audit/private_reads/runs/migration-20261011/`。
报告文件使用 exclusive 创建；已有输出不覆盖。再次执行时把两条命令里的 `migration-20261011` 一起换成一个全新的 run-id；`--core` 必须指向同一轮 GD inventory。输出仅允许在 `tools/audit/private_reads/runs/` 下；两个越界输出负向检查都按预期 exit 1，未创建目标。

第二轮验证省略 `--root`，从仓库外 E 盘临时工作目录调用同一迁入脚本，参数仍为仓库相对路径；临时工作目录已移除。可从仓库根复现同样的参数语义：

```bash
PYTHONDONTWRITEBYTECODE=1 python tools/audit/private_reads/scan_private_reads.py --output tools/audit/private_reads/runs/repro-20261011/gd
PYTHONDONTWRITEBYTECODE=1 python tools/audit/private_reads/scan_embedded_reads.py --core tools/audit/private_reads/runs/repro-20261011/gd/inventory.json --output tools/audit/private_reads/runs/repro-20261011/embedded
```

实际第二轮两条均 exit **0**；原始输出保存在 `runs/repro-20261011/`。上面已存在的 run-id 也需改成新名字才能再执行。仓库外实际调用仅将脚本 argv 改为该仓库脚本的绝对位置，未指定固定仓库盘符作为扫描根。

## 原报告与第一次重跑：逐项计数对比

以下逐项覆盖两份原 inventory summary 的所有数字计数字段，分类缺失项按 0 比较；Python 模板位置/行数与源 SHA256 全部一致。机器可读记录（也含第二轮对比）见 `tools/audit/private_reads/runs/migration-20261011/comparison.json`。

|来源|字段|原报告|第一次重跑|差值|一致性|
|---|---|---:|---:|---:|---|
|GD|`active_categories.可立即替换`|11|2|-9|不一致|
|GD|`active_categories.应保留许可（不可等价）`|179|181|+2|不一致|
|GD|`active_categories.需要新增公开能力`|3684|3750|+66|不一致|
|GD|`active_observation_categories.可立即替换`|11|2|-9|不一致|
|GD|`active_observation_categories.应保留许可（不可等价）`|155|157|+2|不一致|
|GD|`active_observation_categories.需要新增公开能力`|3291|3354|+63|不一致|
|GD|`active_observation_read_total`|3457|3513|+56|不一致|
|GD|`active_state_read_total`|3874|3933|+59|不一致|
|GD|`by_scope.scratch诊断`|27|26|-1|不一致|
|GD|`by_scope.历史证据副本`|641|641|+0|一致|
|GD|`by_scope.现行测试诊断`|3847|3907|+60|不一致|
|GD|`categories.可立即替换`|11|2|-9|不一致|
|GD|`categories.应保留许可（不可等价）`|228|230|+2|不一致|
|GD|`categories.需要新增公开能力`|4276|4342|+66|不一致|
|GD|`diagnostic_files`|801|811|+10|不一致|
|GD|`excluded.owner自己访问`|2|2|+0|一致|
|GD|`excluded.私有方法调用排除`|2478|2526|+48|不一致|
|GD|`excluded.纯赋值排除`|1285|1297|+12|不一致|
|GD|`gate_owner_reads`|3|3|+0|一致|
|GD|`gd_files`|1797|1808|+11|不一致|
|GD|`historical_state_read_total`|641|641|+0|一致|
|GD|`lexical_candidates`|8791|8920|+129|不一致|
|GD|`mode_counts.反射读取`|39|39|+0|一致|
|GD|`mode_counts.容器下标读取`|247|253|+6|不一致|
|GD|`mode_counts.对象/容器读取后修改`|472|474|+2|不一致|
|GD|`mode_counts.读取`|3747|3797|+50|不一致|
|GD|`mode_counts.读改写`|10|11|+1|不一致|
|GD|`observation_categories.可立即替换`|11|2|-9|不一致|
|GD|`observation_categories.应保留许可（不可等价）`|204|206|+2|不一致|
|GD|`observation_categories.需要新增公开能力`|3818|3881|+63|不一致|
|GD|`observation_read_total`|4033|4089|+56|不一致|
|GD|`outside_gate_owner_reads`|4512|4571|+59|不一致|
|GD|`private_callable_references_separate`|74|83|+9|不一致|
|GD|`production_files`|423|423|+0|一致|
|GD|`resolution_counts.唯一生产符号（静态归属推断）`|122|123|+1|不一致|
|GD|`resolution_counts.声明/类型/资源路径`|3791|3829|+38|不一致|
|GD|`resolution_counts.成员组合静态推断`|602|622|+20|不一致|
|GD|`state_read_total`|4515|4574|+59|不一致|
|GD|`unresolved_by_scope.scratch诊断`|8|8|+0|一致|
|GD|`unresolved_by_scope.历史证据副本`|58|58|+0|一致|
|GD|`unresolved_by_scope.旧工作树`|14|14|+0|一致|
|GD|`unresolved_by_scope.现行测试诊断`|329|330|+1|不一致|
|GD|`unresolved_by_scope.第三方插件`|28|28|+0|一致|
|GD|`unresolved_candidates`|437|438|+1|不一致|
|GD|`unresolved_with_production_declarations`|385|386|+1|不一致|
|Python embedded|`categories.需要新增公开能力`|18|18|+0|一致|
|Python embedded|`excluded.私有方法调用排除`|5|5|+0|一致|
|Python embedded|`excluded.纯赋值排除`|1|1|+0|一致|
|Python embedded|`observation_categories.需要新增公开能力`|15|15|+0|一致|
|Python embedded|`observation_reads`|15|15|+0|一致|
|Python embedded|`state_reads`|18|18|+0|一致|
|Python embedded|`unresolved`|4|4|+0|一致|
|Combined|`active_observation_categories.可立即替换`|11|2|-9|不一致|
|Combined|`active_observation_categories.应保留许可（不可等价）`|155|157|+2|不一致|
|Combined|`active_observation_categories.需要新增公开能力`|3306|3369|+63|不一致|
|Combined|`active_observation_total`|3472|3528|+56|不一致|
|Combined|`active_state_categories.可立即替换`|11|2|-9|不一致|
|Combined|`active_state_categories.应保留许可（不可等价）`|179|181|+2|不一致|
|Combined|`active_state_categories.需要新增公开能力`|3702|3768|+66|不一致|
|Combined|`active_state_total`|3892|3951|+59|不一致|
|Combined|`observation_categories.可立即替换`|11|2|-9|不一致|
|Combined|`observation_categories.应保留许可（不可等价）`|204|206|+2|不一致|
|Combined|`observation_categories.需要新增公开能力`|3833|3896|+63|不一致|
|Combined|`observation_total`|4048|4104|+56|不一致|
|Combined|`state_categories.可立即替换`|11|2|-9|不一致|
|Combined|`state_categories.应保留许可（不可等价）`|228|230|+2|不一致|
|Combined|`state_categories.需要新增公开能力`|4294|4360|+66|不一致|
|Combined|`state_total`|4533|4592|+59|不一致|
|Combined|`unresolved_total`|441|442|+1|不一致|
|Combined|`unresolved_with_production`|389|390|+1|不一致|

### 最小可证差异原因

- 原始与第一次 GD 清单的观察读取签名（路径/接收者/成员/owner/模式等，不计 ordinal 与行号）增加 65 处、减少 9 处，净增 56；减少的九处精确落在替换回执的六个文件。新增八个消费者路径详见 comparison.json；扩展状态口径增加 68、减少 9，净增 59。
- 第一次 GD 枚举 1808 个文件，原报告 1797；生产索引仍为 423。索引中的十个新增路径、十三个已变更路径及 SHA256 逐项保存在 comparison.json；这些不是本次迁移写入的生产/测试文件。迁入内容没有新增 `.gd` 文件，未用修改排除规则压平差异。
- 第二次比第一次新增 `tests/magic_payment_contract_test.gd`：四处观察读取、两处容器读取后修改；观察合并总数因此再增加 4（4104 → 4108），状态总数增加 6（4592 → 4598）。其余共同索引文件 SHA256 未变；Python 两次 inventory 字节一致。
- 两轮各自 `changed_during_scan=[]`；这个字段只重验已登记输入，不能检测扫描之后/枚举期间新出现的文件，所以不是全树冻结证明。
- 历史审计 gate SHA256 是 `a8271e946890cbc1a58dcdf54b75ecc8078542be55c838df33d093f284d2be05`；原替换回执、迁移起始/两轮重跑/最终读回都是 `5dabf762ded90d5e0a6151ba1a50468c14f9029c3f2478ef996c9f6fb6bcf0be`。两历史资产原本已有差异；本次没有写 gate 或允许清单，不把历史差异归因于迁移。

## Gate owner 与允许清单

`tools/check_layer_deps.py:25–29` 的 owner 仅 EffectManager、GameProgress、DummyBot。原 11 条可替换读取的 owner 只有 BaseCard 与 NetworkMatchAuthority，**0/11 属于 gate owner；九处替换不能减少 gate 允许清单**。
“全部观察读取中 gate owner 为 3”与“这 11 条中为 0”是不同分母。历史观察读取 4048 中 owner 范围外为 4045；第一次重跑 4104 中为 4101，第二次 4108 中为 4105。“应保留许可”是逐锚点白盒建议，不表示已有 gate 许可。

## 当前是不是全树穷尽？不是

- 主扫描遍历实际 `.gd`，不遵循 git ignore，只排除 `.git/.godot`，拒绝源文件越根链接；生产声明索引仅 `scripts/**`、`json_maker/**` 的顶层 `_` 状态，消费者按原诊断规则识别。历史生产源码副本不当诊断重复计数。
- 字面量 `get/get_indexed` 与生产继承读取纳入；注释/普通字符串不当访问；私有方法调用排除，私有方法引用单列。声明/类型/资源、成员组合、唯一符号静态推断不是运行时类型证明。
- Python 补充只覆盖三个已人工核验的 runner 中四个真实发射字面量；不是遍历全部 Python 动态生成代码。动态反射、拼接、任意跨函数/模块返回类型不保证穷尽。
- 原报告有 389 个带生产声明的未消歧候选，另有 52 个无生产声明候选；两次重跑均为 390 + 52。它们未完成确认归属/三分类，不能宣称全树精确总数或私有读取清零。
- 当前树存在其他写者。仓库路径可复现与当前树稳定是两件事；本交付提供脚本、历史快照、两轮真实输出、源摘要及差异，不提供旧源码全树快照，不能承诺在持续变化的工作树重现旧数字。未运行 Godot/窗口/全量行为验收。

## 仓库内证据与 SHA256

- `tools/audit/private_reads/baseline/audit/`：原 SUMMARY、两份原逐条报告与 inventory（按字节保留）。
- `tools/audit/private_reads/baseline/replacement/`：原 REPORT、receipt、before.json、changes.json、migration.patch 与最小历史执行 manifest/log。不迁入 `.gd` before 副本或旧 E 盘专用 Godot 执行器。
- `tools/audit/private_reads/.gitignore`：仅放行本目录历史执行/重跑 `.log`，使证据随仓库保存；不改根 `.gitignore`，也不改变扫描规则（扫描器不遵循 Git ignore）。
- `tools/audit/private_reads/SHA256SUMS.txt`：本次全部新增文件（文档、脚本、历史证据、两轮输出、对比）的完整 SHA256；清单不自包含。
- 未改生产源码、前端、gate、允许清单或测试断言，也未触碰指定受保护 PID。
