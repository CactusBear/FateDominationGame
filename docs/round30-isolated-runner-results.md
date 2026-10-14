# Round 30：独立运行器缺口修复与真实 RED/GREEN

## 结果与范围

- 现有唯一入口 `tools/run_isolated_godot_test.py` 支持 `RESULT refactor_text_golden checks=2 failures=[]`；没有新增重复 runner。
- 最终 **17 tests，OK，exit 0**，包含真实 Godot 冻结/非冻结运行、失败 RESULT、缺依赖，及 Windows Job、预算、保守清理边界。全程 headless，无窗口。
- 修改仅为该 runner、`tools/tests/test_isolated_godot_test.py` 与本报告；`test_round29_integrated_evidence`、生产代码与 project.godot 未修改。未提交、未推送。
- 证据根：`E:/scratch/round30-isolated-125eb638fd3d4ece93c06f72a50de471`。真实引擎 stdout：`Godot Engine v4.7.2.stable.official.ed1daf0bf`。

## 耦合评估与中文代码说明（V4A 修改）

既有解析、物理路径、探针、Job 执行、白名单冻结、清理职责已分开；不引入轮次依赖、不 import 另一个 runner，也不改游戏 operation。新增测试组合现有 `execute` / `delete_owned`，不复制进程管理算法。所有代码修改使用 V4A patch，并在修改前说明职责及安全边界。

1. **RESULT 裸前缀**：在 key=value 分支识别可选 suite 标识，将它作为 `('suite', name)` 加入现有字段对列表，再复用 JSON raw_decode 与 `unique_fields`。因此裸前缀和显式 suite 冲突仍报重复字段；JSON、无前缀 key=value 的原有契约不变。不是按 `refactor_text_golden` 特判，也没有将 PASS/FAIL 文本、整数 failures 或命令结果适配成成功。
2. **严格通过门**：仍要求 stdout 唯一 RESULT、正整数 checks、数组 failures 为空、exit 0；重复 checks、bool/小数、失败/非法 CHECK、数量矛盾、重复 RESULT、引擎 ERROR 都失败。明确测试 `RESULT gateway checks=1 failures=[]` 配合 `ERROR: expected gateway error` 仍拒绝。`RESULT {"ok":true,"command":"status"}` 缺套件 checks/failures 仍拒绝；runner CLI 的 JSON 摘要只用于定位 manifest，绝不当 suite RESULT。
3. **线程配置**：探针项目原先只复制 application；现在同时原样复制 threading 节，未硬编码线程上限。Godot 主/worker 各自回执增加 `worker_pool_max_threads` 实际设置值，保留物理文件读回与摘要检查。冻结仍复制整个 project.godot，复核与源配置一致。测试源配置为 20；主/worker 回执均为 20，目标真实场景另输出 `CHECK thread_config true`。
4. **最小 freeze 缺依赖**：复制后扫描目标 tscn 的直接 `ext_resource path="res://..."`，拒绝越界，缺失路径明确列出并提示显式 `--include`；不自动复制 scripts/tests 整树。其余脚本间接依赖仍由真实 Godot import 校验；import 失败提示两份日志路径与显式 include。直接依赖检查是提前诊断，不是完整 GDScript 依赖分析器。
5. **测试证据收尾**：真实夹具现在先复制 manifest/log 到独占证据根再断言，防止 RED 断言提前失败后 TemporaryDirectory 消费证据。归档不包含 generated；源夹具旧 `test/old.bin` 保持不变。

## RED → GREEN 的实际证据

采用与 `tests/refactor_text_golden_test.gd` 第 34 行相同裸 suite/key=value 语法的最小专项，不冒充整套文本黄金游戏验收。目标脚本真实写读 user://、检查线程设置并退出。

- 初始 `red.log`：冻结与非冻结合法裸 suite 均 runner exit 1，两个断言失败。
- `thread-red.log`：新线程回执断言真实失败；修复 application-only 探针后通过。初次使用字典索引得到 KeyError 后改为 `.get` 重跑，归档保留的是有效 AssertionError RED。
- `dependency-red.log`：故意不 include `small.gd`，旧实现只有 `SafetyError: timeout`，明确诊断断言失败；新实现在真实主/worker 探针完成后直接报缺失 `res://small.gd`，不再进入无脚本场景耗尽预算。
- 为保全完整 RESULT RED 日志，临时撤回同一 runner 裸 suite 解析的四行，重放并归档后恢复；没有生成第二份 runner。`result-red-evidence.log` exit 1、两项有效失败。下面 RED 两次 Godot scene 都 exit 0、两个 CHECK true；唯一失败原因是 `invalid_result: invalid RESULT field`。
- 恢复修复后 `final-green.log`：`Ran 16 tests in 14.450s`，`OK`，exit 0。

目录均为证据根下 `verification-<run_id>`：

| 阶段/输入 | run_id | 实际结果 |
|---|---|---|
| RED 冻结合法裸 suite | `55c1c87e2186496b9030d6a5a7a9dfbe` | scene exit 0；解析拒绝，runner 1 |
| RED 非冻结合法裸 suite | `b88a8282ecbb4110b439c87adc7dc75b` | scene exit 0；解析拒绝，runner 1 |
| GREEN 冻结合合法裸 suite | `d92df30603b7476497acd10bed238618` | probe/import/scene exit 0；runner 0 |
| GREEN 非冻结合法裸 suite | `de8bb8206ff74b87b88d5de73dc88010` | probe/scene exit 0；runner 0 |
| GREEN 冻结 deliberate failures | `afecfe8aacf14fb4aa9a2614c5bef8b7` | scene exit 0；`result_failures`，runner 1 |
| GREEN 冻结缺 small.gd | `e2a53c20ca8a4292ac30a70fbd46e0c3` | probe exit 0；明确依赖诊断，runner 1 |

合法场景真实 stdout：

```text
CHECK actual_write true
CHECK thread_config true
RESULT refactor_text_golden checks=2 failures=[]
```

最终冻结主/worker PID：`34996 / 37852`；非冻结 `27320 / 1240`。各回执的物理 E 路径位于本次 generated/appdata/IsolationFixture 内，token 文件和 JSON 均已读回；归档 manifest 含 probe/receipt SHA-256。真实探针 worker 自然退出码为 0，不是 Python 合成成功回执。

## 生命周期、预算与清理复验

- `test_owned_job_waits_for_natural_descendant_exit`：根 Python 先退出，子进程延迟 0.7 秒后写入 `natural.txt`；execute 返回时标记实际可读、exit 0、budget_failure=None、Job ActiveProcesses=0、日志句柄释放。证明没有因根先退出就关闭 Job 杀掉尚在自然工作中的子进程。
- 原有派生进程 timeout、Job close、byte_budget 负向重新通过；新增 free_space_budget 用真实磁盘总容量以上的下限触发，仅终止自有 Job。
- 合法所有权仅删除 `owner/generated`，兄弟 formal sentinel、manifest、evidence 留存；未退出 owner、缺回执、junction 都拒删，junction sentinel 读回不变。
- 六组重点 RED/GREEN manifest/log 已程序读回，日志摘要全匹配；全部 recorded processes exited=true、active_owned_processes=0、log_handles_released=true，cleanup=generated_removed，generated 不存在。`verified-summary.json` 保存聚合校验结果。

最终可重放命令（引擎副本已消费删除，重跑须重新提供批准物理 E 可执行文件）：

```bash
ISOLATED_TEST_ROOT=E:/scratch/round30-isolated-125eb638fd3d4ece93c06f72a50de471 \
ISOLATED_GODOT=E:/scratch/round30-isolated-125eb638fd3d4ece93c06f72a50de471/Godot.exe \
python -B tools/tests/test_isolated_godot_test.py -v
```

## CHECK 补充整合要求后的最终复验

用户补充指出整合日志的循环 CHECK 文案合法重复；本 runner 不按 label 唯一性拒绝，没有修改只读 `test_round29_integrated_evidence.py`，也不把它的 duplicate_check 结论当 false/ERROR。本任务未自行重跑或宣称验收其 13 场景聚合。

新增回归 `test_repeated_check_labels_are_not_ids`：同文案两次、总 checks=2 正常通过；兼容 `CHECK true label` 和 `CHECK label true`。只有明确数字前缀 `1`、`#1`、`[1]` 被视为 ID，重复编号拒绝；重复 RESULT 继续拒绝；bool-first 的 false 或前后矛盾布尔值都失败。`check-red.log` 是旧解析拒绝合法 bool-first 的有效 RED。修改后再次真实全套执行：`check-final-green.log`，**Ran 17 tests in 14.506s，OK，exit 0**。

最终四组归档及 PID：

| 输入 | run_id | 主/worker PID | 结果 |
|---|---|---|---|
| 冻结合法 | `f53fb7874a434210ae9c0e6a39a20c24` | 37112 / 31820 | runner 0，checks=2 |
| 非冻结合法 | `fc73b71a36f94ad6a21ba2c02ccc3066` | 36824 / 8964 | runner 0，checks=2 |
| deliberate failures | `ac99450edd6e4ed39a7e9155d476095c` | 33832 / 35756 | runner 1，result_failures |
| 缺 small.gd | `c9fcb4fe7da244d5bbbb351609c8c64b` | 2220 / 4076 | runner 1，明确依赖诊断 |

四组全部重新读回日志 SHA-256、进程退出、Job=0、句柄释放及 generated 不存在性。为接收补充要求，重新复制同一已核验引擎到同一独占路径；最终再次精确查询自有进程=0并删除，文件不存在。两次先后消费的引擎副本累计回收 **361717776 bytes**，没有同时保留第二套引擎或另一个 runner。最终证据见 `check-final-verification-cleanup.json`；下面原先单次清理数字保留为第一次收尾记录。

## 引擎副本收尾与边界

本次从 D 盘正式非 console 引擎复制唯一 E 子树 `Godot.exe`，复制前后 SHA-256 相同。验证结束后 Win32_Process 精确 executable path 查询显示自有引擎进程数 0；重验所有归档进程退出、整棵自有证据根无 reparse point、原件及副本摘要一致，删除该副本并读回不存在。实际删除引擎 **180858888 bytes**；原件 SHA-256 未变：`ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`。`cleanup.json` 记录 generated_remaining=[]。只保留最小日志/manifest/摘要；未删除别人的 scratch、生产文件或正式存档，未按进程名清扫。

辅助进程查询第一次尝试 psutil 因当前 Python 未安装而失败，未安装包；改用只读 Win32_Process 精确路径查询完成。此失败不影响 runner 验收。

预算仍是周期监测而非 OS 配额；路径检查/普通删除不声称彻底解决恶意 TOCTOU。线程回执报告配置值，不等于数出 OS 工作线程实际数量。没有执行全量生产黄金/网关验收，也没有因网关预期错误降低通用严格门。
