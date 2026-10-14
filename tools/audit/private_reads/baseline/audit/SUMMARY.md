# 当前树测试/诊断读取生产私有成员：交付摘要

这是实际执行的静态清单，不是全树运行时类型证明，更不是“已清零”。没有修改仓库文件、gate或技能；没有启动Godot，没有操作PID 17120/28100。只在本E盘目录新建分析脚本和报告。

## 主口径：观察读取

排除纯赋值、私有方法调用、读改写、取容器/对象后修改。每个词法出现独立计数；含字面量反射、生产继承脚本中的未限定读取。

|范围|可立即替换|需要新增公开能力|应保留许可（不可等价）|合计|
|---|---:|---:|---:|---:|
|现行测试/诊断 + scratch + 已核验Python发射片段|11|3306|155|3472|
|上述 + 树内历史诊断证据副本|11|3833|204|4048|

4048处中4045处的所属生产文件不在gate的3个owner范围内。

如果同时统计取私有容器后修改/复合赋值这些真实成员读取依赖，则共4533处：可立即替换11、需要新增公开能力4294、应保留许可228。这包括主GD清单4515处和Python发射片段18处；不要把这一口径与纯观察4048处混用。

## 文件与逐条清单

- `scan_private_reads.py`：全树GD词法、类型/资源/继承/成员组合归属分析脚本。
- `latest/report.md`：GD读取逐条三分类表，逐条包含文件:行、被读成员、生产文件:声明行、公开等价入口、范围、访问种类、归属依据。4515行已程序核对。
- `latest/inventory.json`：完整结构化清单、公有方法证据索引、源文件SHA256、计数和未消歧附录。
- `scan_embedded_reads.py`：Python真实注入的4个经调用点核验的GDScript字面量补充脚本。
- `embedded-latest/report.md` / `inventory.json`：每条同时列Python源行和生成GDScript行。

### 11处可立即替换（完整）

|文件:行|私有成员|生产文件|完全等价入口|
|---|---|---|---|
|newtests/play_affordance_rule_audit_test.gd:75|_attributes.has(...)|scripts/system/base_card.gd:88|has_attribute(原参数)|
|tests/climax_gated_ability_test.gd:62|_attributes.has(...)|scripts/system/base_card.gd:88|has_attribute(原参数)|
|tests/servant_skill_eight_magic_test.gd:85|_attributes.has(...)|scripts/system/base_card.gd:88|has_attribute(原参数)|
|scratch/transaction-return-consumers/transaction_return_consumers_test.gd:280|_revision|scripts/net/authority/match_authority.gd:33|current_revision()|
|tests/authority_revision_query_test.gd:18|_revision|scripts/net/authority/match_authority.gd:33|current_revision()|
|tests/authority_revision_query_test.gd:40|_revision|scripts/net/authority/match_authority.gd:33|current_revision()|
|tests/match_finished_authority_test.gd:59|_revision|scripts/net/authority/match_authority.gd:33|current_revision()|
|tests/match_finished_authority_test.gd:63|_revision|scripts/net/authority/match_authority.gd:33|current_revision()|
|tests/match_finished_authority_test.gd:83|_revision|scripts/net/authority/match_authority.gd:33|current_revision()|
|tests/match_finished_authority_test.gd:86|_revision|scripts/net/authority/match_authority.gd:33|current_revision()|
|tests/refactor_net_area_diagnostic.gd:180|_revision|scripts/net/authority/match_authority.gd:33|current_revision()|

其他两类完整逐条清单在上述report.md，不能用此摘要替代逐条表。

## 扫描规则与真实缺口

1. 扫描真实*.gd，不遵循git ignore；排除.git/.godot；拒绝越根链接。最终实际枚举1797个GD文件，其中801个诊断候选文件；生产声明索引范围scripts/**和json_maker/**。
2. `_`前缀按项目gate口径纳入，包含纯数据模型；这不是GDScript语言级访问限制。历史生产源码副本不作为诊断代码重复计入；历史测试/探针副本明确单列scope。
3. 注释和普通字符串不作为直接访问；Object.get/get_indexed字面量私有键另纳入。私有方法调用不算状态读取；74处私有方法引用单列，不混入状态总数。
4. 归属证据分开标注：声明/类型/资源路径、成员组合静态推断、唯一生产符号推断。后两者不能冒称运行时类型证明。
5. 公有等价只接受完全保持原值/断言语义的入口。has_name包含别名、get_shown_name有回退、setter、泛用反射和消费队列不等于原始只读事实。凭据/哈希仅列字段名，从未打印值。
6. 保留许可是逐锚点白盒建议，不表示gate已许可。原容器身份隔离、认证回滚精确不变性不能用值投影伪装等价。
7. **还有389处带生产声明的未消歧候选**：GD385、Python4，另有52处无项目生产声明的候选（含第三方/测试自有成员）。它们在附录逐条列明位置、成员、可能生产文件；其公有等价尚未确认。因此这里不能给出完全精确全树总数，也不能宣称全部候选已经完成三分类。
8. Python补充仅统计4个人工追到真实write_text/replace注入点的模板；动态拼接、通用反射、任意跨函数/跨模块返回类型不保证穷尽。
9. 当前树有其他代理并发写入：最新一次扫描内changed_during_scan=[]；后续复核发现scripts/net/ui/v2_view_presenter.gd继续变化。数字是带SHA256的扫描快照，不可冒称持续不变的冻结树。前次快照还观察到lobby_session及新的投影测试变化；主要读取计数重跑后相同，但不构成全部语义不变证明。

## 实际命令与核验

```text
PYTHONDONTWRITEBYTECODE=1 python E:/hermes-scratch/private-read-audit-20261010/scan_private_reads.py --root E:/Projects/Godot/FateDominationGame-master --output E:/hermes-scratch/private-read-audit-20261010/latest
PYTHONDONTWRITEBYTECODE=1 python E:/hermes-scratch/private-read-audit-20261010/scan_embedded_reads.py E:/hermes-scratch/private-read-audit-20261010/latest/inventory.json E:/hermes-scratch/private-read-audit-20261010/embedded-latest
```

两条真实命令退出0；输出目录采用exclusive创建文件，重跑请指定新的E盘输出目录。词法访问分类8个真实自测PASS；清单行数、三分类和、范围分项和均程序核对PASS。未运行Godot行为验收。

曾只读运行gate，返回exit1，仅有已退休_pending_announcements许可STALE；没有NEW。这不代表观察读取清零。供gate唯一写入者参考的精确旧anchor：

```python
ExceptionSite("private", 'tests/pending_board_power_test.gd', 'EffectManager._pending_announcements', '"announcements":freeze(EffectManager._pending_announcements),', 99),
```

该记录只是当次真实输出；本任务没有修改或退休许可，后续gate当前状态需主代理读回确认。

## 遇到的问题

一次分析脚本自身patch工具超时，但实际写入已落盘；通过定向读取及后续真实执行核验，不影响仓库。最主要未完成验收是389处未消歧生产候选与动态生成边界；不得把本轮扫描包装为全树完全精确穷尽。
