# RegularPlay 三项原语映射迁入 AllOperations

**结果：迁移完成；原八套专项改前/改后均通过，新增注册表查询单测通过；完整 25 案例 compare 原始字节完全一致；发布审计真实 exit 0。测试认证范围为上轮固定依赖，不是最新热工作树。**

## 修改范围和核实位置

改前临时 preload 位于 `scripts/system/regular_play.gd:59–64`：

- 第 61 行：`RemoveFromArray.gd`
- 第 62 行：`AddToArray.gd`
- 第 63 行：`SetProperty.gd`
- 第 68 行：按 `AllOperations.get_class_name_of(func_name)` 查调用方临时字典并 `.new()`。

现已移至 `scripts/system/global/all_operations.gd:285–290`，只登记这三项具体 `preload("res://scripts/system/operations/<具体类>.gd")` 字面量；第 294–295 行新增 `create_instance_of(func_name:String) -> RefCounted`，仍经原 TABLE 查询类名，每次创建新实例。`regular_play.gd:60–61` 的 `_operation` 只调用此注册表入口。

没有添加其它 operation、路径格式串、缓存、效果执行器、预算、日志或事务；原 TABLE 与全部已有查询入口内容不变。源码精确变换核验确认 RegularPlay 除移除字典与替换 helper 的返回表达式外完全不变，因而 exec 参数、时序、日志、返回值、PayMagic 扣款当时余额复核、检查点与整组回滚代码均保持原样。保留的 `rule_random` / `effect_checkpoint` / `rule_checkpoint` preload 是原有事务依赖，不是本轮临时原语映射。

生产修改仅两个授权文件；未写 `effect_manager.gd`、`PlaySkill.gd`、`Move*.gd` 或前端，未操作 PID 17120 / 28100。

## 改前后 SHA256

| 文件 | 改前 | 改后 |
|---|---|---|
| `scripts/system/regular_play.gd` | `1f7ffbabf1c9556bca4d33622a8a45d5b1bd00b15079cd042c55870dfd94394e` | `a1cebe86a5a044b1eb139b3d103578ccd9054905ae282a4f2874f72c49b6b43c` |
| `scripts/system/global/all_operations.gd` | `8f39c2dfa98a2989a79040fba436d69bc93c8e6c93a86e7f3664e0f44fbd775a` | `223fd3176d57d556cab3fe876580046772dda74fa625cb60a1e3dddddcb2b47b` |

最小改动见 [`minimal.diff`](minimal.diff)，基于本任务改前实际字节，不以包含其它写入者修改的 git HEAD 为基线。两个文件改前/改后原字节快照与 manifest 已归档。最终生产文件 SHA 与测试变体 SHA 一致；`git diff --check -- scripts/system/regular_play.gd scripts/system/global/all_operations.gd` exit 0。

## 同冻结逐套结果

从上轮 `isolated-bcb811c286fd49cea4c820fdd0aa0a7b` 的明确输入白名单独立复制 2127 项冻结输入；先校验现有两文件改前 SHA 等于上轮最终变体，再仅声明这两个文件为可变体文件，其余依赖保持原摘要并核验无漂移。未读取热文件更新其冻结内容，未放宽冻结门。

最终运行 owner：`E:/scratch/regular-play-registry/isolated-d7fe32e4320d40f5a567045a3198ab19`。

| 套件 | 改前 CHECK | 改后 CHECK | 改前/改后 exit | 改前/改后 ERROR | 改前/改后 Job0 |
|---|---:|---:|---|---|---|
| regular_play_existing_ops_compare | 75 | 75 | 0 / 0 | 0 / 0 | true / true |
| regular_play | 54 | 54 | 0 / 0 | 0 / 0 | true / true |
| magic_payment_contract | 219 | 219 | 0 / 0 | 0 / 0 | true / true |
| rule_guard_regular_group | 9 | 9 | 0 / 0 | 0 / 0 | true / true |
| rule_guard_regular_add | 18 | 18 | 0 / 0 | 0 / 0 | true / true |
| battlefield_conceal | 25 | 25 | 0 / 0 | 0 / 0 | true / true |
| extra_play_limit | 22 | 22 | 0 / 0 | 0 / 0 | true / true |
| mana_spend | 45 | 45 | 0 / 0 | 0 / 0 | true / true |
| **新增 regular_play_registry_query** | 不适用 | **29** | 不适用 / **0** | 不适用 / **0** | 不适用 / **true** |

每套 stdout 唯一合法 RESULT、计数相符、failures=[]，不含 SCRIPT ERROR / ERROR；所有断言和门均保留。新单测核对入口、三类具体资源路径与脚本身份、每次新实例、只映射三项、支付元数据、原语返回值、数组重复元素/别名/插入位置及属性 setter/float/无效属性行为。

完整 compare 25 案例（原专项覆盖对象/数组身份、事实、资源数值与类型，含第二张涨价后整组回滚等）改前后原字节完全一致，未删除字段或规范化输出。两份 JSON SHA 均为：

`bbbac51f0858a17d9e4690ff8ce3b249193b5289899334f435ac3a04cf40388b`

主进程/派生进程 user:// 回执实际读回路径位于本次独占 E 盘 generated/appdata/FateDomination；探针、两次导入与全部专项共 20 个 owned Job 执行记录均退出且 ActiveProcesses=0。所有 Godot argv 使用 `--headless --fixed-fps 60`；每进程看门狗 600 秒，TMPDIR/TEMP/TMP 与 APPDATA/LOCALAPPDATA 都明确指向 E 盘独占生成树。

真实最终命令（runner exit 0；原始输出在 final-run.stdout.txt / final-run.stderr.txt；全部 Godot argv 在 manifest）：

```bash
TMPDIR=E:/scratch/regular-play-registry TEMP=E:/scratch/regular-play-registry TMP=E:/scratch/regular-play-registry python -B newtools/run_regular_play_registry_compare.py --base E:/scratch/regular-play-registry --seed-owner E:/scratch/regular-play-existing-ops/isolated-bcb811c286fd49cea4c820fdd0aa0a7b --before E:/scratch/regular-play-registry
```

## 发布审计：真实 exit 原文

实际执行命令：`python -B tools/release/role_privacy_audit.py`，环境 TMPDIR/TEMP/TMP 指向 `E:/scratch/regular-play-registry`。

stdout 原文（对应 audit.stdout.txt）：

```json
{"status": "PRIVACY_PACKAGE_CONSUMER_WIRED_AUDIT_NOTRUN", "fixture_case_count": 17, "evidence": "tools\\release\\evidence\\role-privacy", "godot_invoked": false, "checks_removed": []}
```

真实退出回执：

```text
AUDIT_EXIT 0
```

stderr 为空；`audit.exit.txt` 保存实际 subprocess 返回码 `0`。该审计包含三角色 freeze dry-run 自检，说明此次静态依赖可冻结；输出明确 NOTRUN / godot_invoked=false，不代表隐私运行验收或真人包通过。

## 初次工具问题与处理

首次新增查询测试实际 CHECK 29 全 true、exit 0、ERROR 0、Job0，但两条标签以裸 `true` / `false` 收尾，被既有解析器误认成第二个布尔结果，导致 runner exit 1。只将标签改为 `true value` / `false value`，未改断言、计数、解析器或任何门。原失败日志及仅标签修正的重试记录保留于 `prior-attempt/`。随后对最终代码进行新的完整干净执行，以上表格均来自同一个最终 owner，不拼接不同执行的通过记录。

## 新增文件 / 证据

- `newtests/regular_play_registry_query_test.gd`、`.tscn`：注册表查询单测。
- `newtools/run_regular_play_registry_compare.py`：复用既有 owned-Job runner 的双文件变体验证，支持保留原证据的受限标签重试。
- 本 `docs/audit/regular-play-registry-migration/`：报告、minimal diff、manifest、改前后源码、所有原始进程日志、compare JSON、审计原始回执及初次失败历史。

这些目录未被 gitignore 忽略；未提交。已将固定依赖双文件迁移验证方法补入 `godot-operation-static-freeze-dispatch` 技能。

## 未验部分 / 认证边界

相对上轮冻结的最新工作树漂移仍为以下五个文件（本任务未修改）：

- `scripts/net/server/server_console_channel.gd`
- `scripts/net/server/server_room_manager.gd`
- `scripts/system/global/game_progress.gd`
- `scripts/system/global/situation_resolver.gd`
- `scripts/system/global/time_point_checker.gd`

八套规则等价只认证原固定依赖 + 本轮两文件变体，不认证这些漂移后的最新整树。最新工作树仅发布静态审计已实跑通过。没有运行最新整树专项、全量回归、非 headless/前端/真人多机、正式三角色组包或隐私运行验收；没有扩展 EffectManager 及其它消费者到此三项新入口。
