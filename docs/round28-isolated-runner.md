# Round 28：单场景物理 E 盘隔离测试运行器

## 交付与职责边界

新增：

- `tools/run_isolated_godot_test.py`：只负责一个显式指定场景的隔离执行、证据判定和本次生成副本回收。
- `tools/tests/test_isolated_godot_test.py`：Python 安全边界负向与真实 Godot 小场景集成测试。
- 本报告。既有 runner、游戏规则、生产网络源码均未修改；未提交或推送。

耦合审查：旧 baseline runner 的固定盘符、套件集合、报告目录和轮次名称不适合作为通用依赖。新 runner 不 import 旧 runner，也不含 round/A02 等名称。路径检查、RESULT 解析、进程所有权、复制白名单、探针核验、清理分别封装，唯一组合职责是“执行一个场景并交付可信结果”。

## 接口与执行顺序（中文代码说明）

所有关键参数均必填，无隐式路径或预算：

```text
python -B tools/run_isolated_godot_test.py \
  --project E:/approved/source-project \
  --scene res://tests/target_test.tscn \
  --root E:/approved/isolated-runs \
  --godot E:/approved/Godot.exe \
  --timeout 180 --max-bytes 536870912 --min-free-bytes 1073741824 \
  --freeze --include scripts --include data --include tests/target_test.gd
```

这是接口示例，实际路径及依赖须由调用方明确指定；不可把示例占位目录当成本机现存目录。

1. `no_links/physical_e/contained` 检查路径自身及全部现存祖先的 symlink/reparse point，要求 project/root/executable 的实际路径在 E，scene 必须为项目内 `res://*.tscn`，拒绝 `..` 越界。拒绝预算零值/负值、非有限 timeout；分配前检查剩余空间。
2. 每次在批准根下排他创建随机 UUID 子树，分成 `generated` 与 `evidence`。只给本次进程环境设置独占 APPDATA/LOCALAPPDATA；不修改系统配置，不设置 TEMP/TMP/TMPDIR，也不创建 C 盘 junction。
3. 前置探针使用源项目相同 `[application]` 配置的最小 Godot 项目，不启动生产 autoload。存在 `override.cfg` 或 project settings override 声明时在分配前拒绝；冻结 import 与场景启动前还复核项目配置未变，避免探针配置与实际配置不一致。真实 Godot 主进程打印 `OS.get_user_data_dir()` 并写随机 token 文件与 JSON 回执，然后真实 `OS.create_process` 启动 worker。worker 独立执行相同探针；父进程核对真实子 PID、等待退出，并读取 `OS.get_process_exit_code()`，必须为 0。
4. Windows worker stdout 不保证继承 Python 的日志管道，所以父进程从 worker 自己写入的 `user://` JSON 回执汇总，不伪造 worker 路径。Python 再核验两个不同 PID、token、物理 E 路径、独占生成树边界、文本文件和 JSON 内容，并记录 SHA-256。仅声明 APPDATA、仅 exit 0、只有主进程探针，均不足以放行。
5. Windows `OwnedJob` 创建内核 Job Object，设置 `KILL_ON_JOB_CLOSE`。根进程挂起启动，先绑定 Job 再恢复，消除先派生后登记的窗口。等待条件同时覆盖根进程和整个 Job 的活动进程数；超时/超字节/剩余空间不足仅终止该自有 Job。活动数为零后，还对自有日志执行有界 DELETE-access 打开检查（不删除），处理 Windows 继承 I/O 句柄延迟释放。
6. `--freeze` 可选。开启时只复制 project.godot、目标 scene 与显式 `--include` 依赖；拒绝整棵 tests 目录，跳过旧 test、reports、runtime_reports、scratch、window、发行目录、`.git/.godot/__pycache__` 和日志/临时文件。复制前估算字节，复制后记录长度与 SHA-256；新冻结必须通过真实 Godot import，缺依赖报错，不从旧缓存补造成功。
7. 使用真实 `--headless --fixed-fps 60 --path ... --scene ...` 执行目标。通过必须同时具备 exit 0、stdout 唯一合法 RESULT、显式正整数 checks、空 failures、无引擎错误及无失败 CHECK。支持 JSON 和 JSON 值 key=value；重复字段、布尔/小数计数、缺 RESULT、多 RESULT、坏 CHECK、CHECK 数量矛盾均失败。
8. 先归档完整本次 stdout/stderr、摘要和 manifest。失败额外保留探针源码、目标 scene、直接 Script 依赖与配置；每文件最多 64 KiB、目标源码合计最多 1 MiB，超限记录缺口而不是留整棵冻结。
9. 清理只接受本次 UUID 对应 `generated` 和已落账的所有权 manifest。重验目标、全部链接边界、各进程 `exited` 与 Job 活动数为零后才删除。未知所有权、junction、未证明退出或清理异常均保留并返回失败。正式项目、正式存档和其它代理 scratch 从不进入删除目标。

## 真实验证结果

最后一次执行命令（完整命令及退出码亦见归档 `python-tests.json`）：

```bash
ISOLATED_TEST_ROOT=E:/scratch/isolated-runner-validation-b714f603625f4070b2fc05a8ab1d5d33 \
ISOLATED_GODOT=E:/scratch/isolated-runner-validation-b714f603625f4070b2fc05a8ab1d5d33/Godot.exe \
python -B tools/tests/test_isolated_godot_test.py
```

结果：**13 tests，OK，Python exit 0**。真实引擎为 Godot `4.7.2.stable.official.ed1daf0bf`。验证可执行文件是在本任务独占 E 子树中由现有 D 盘正式引擎制作的临时副本；验证结束已校验原件摘要并删除副本，以上历史命令不再假称可立即重放。重跑需显式提供批准物理 E 的现存完整 Godot 可执行文件。

归档根：`E:/scratch/isolated-runner-validation-b714f603625f4070b2fc05a8ab1d5d33/`。

| 验证 | manifest 子目录 | 结果 |
|---|---|---|
| 冻结、小 Godot 真实写入/读回 user:// | `verification-0387675d980e47c5842a9bc3c263a0c9` | probe/import/scene exit 0；checks=1、failures=[]；PASS |
| 非冻结、同一真实小场景 | `verification-ba0d4182c4f845198a29a7ea0aaf4e78` | probe/scene exit 0；checks=1、failures=[]；PASS |
| 冻结、故意失败 RESULT | `verification-495c7c6eab3349d6aaaa8f6cb25355e6` | scene 仍 exit 0，但 failures=["deliberate"]；runner exit 1 |

冻结成功探针的真实主/worker PID 为 `29960/22396`，非冻结为 `8652/38904`，故意失败为 `35540/8008`。三次均核验物理 E 的独占 user:// 文件与回执；归档日志逐项读回 SHA-256 一致，所有 Job 活动数为 0，三个 `generated` 均已确认不存在。

Python 负向覆盖：C 盘 project root/executable、路径越界、非法 scene、非法预算、未探测的配置 override、缺 worker、声明路径但无物理读回、重复/非法/失败 RESULT、exit 非零、引擎错误、CHECK 矛盾、历史产物排除、无所有权拒删、真实 Windows junction 拒删、派生子进程存活超过根进程、Job 关闭终止自有进程、监控字节超预算。

junction 夹具的目标是自建 `formal-save`，拒绝清理后 sentinel 内容仍为 `do not delete`；仅移除自建链接本身。真实场景失败证据保留了 scene、直接脚本和配置；源项目旧 test 产物未被复制或删除。

## 本次磁盘收尾

只清理本任务独占子树内已消费、已证明停用的产物。保留最终三组日志/manifest、Python 执行日志、边界故障最小摘要和 `validation-cleanup.json`。

- 累计实际删除 32 个明确记录的文件/目录项，实际回收 **362888471 bytes**；包含两次验证消费的 E 盘临时引擎副本、旧验证副本和已消费预算填充数据。该数字是累计删除字节，不是盘符可用空间净变化。
- 删除后逐项读回不存在性；最终保留 **39408 bytes** 证据。
- D 盘原始引擎未修改，未删除其它代理 scratch，未扫描或清除正式存档。

## 已知边界，不扩大通过声明

- 字节/空间预算为周期监测，不是 OS 配额；快速写入可能瞬时越过阈值，不能宣称硬上限或对任意恶意脚本提供文件系统沙箱。
- 路径复验及普通文件删除仍不是抗恶意并发替换的句柄级事务；遇到链接失败关闭，但不宣称解决全部 TOCTOU。
- 前置探针验证相同 application 配置和正常继承环境的 Godot spawn；额外 project settings override 已失败关闭，不提供未经探测的兼容捷径。生产 worker 若主动重写环境或动态改写用户目录，需要自己的等价实际探针；本报告不将最小夹具冒充整个生产网络进程链的验收。
- 不冻结时，Godot 可能在原项目产生引擎缓存；只保证本次隔离 user:// 生成树的生命周期，不宣称源项目只读快照。
- 本次只验证 headless，不涉及窗口交互，也未运行全量项目规则套件。

另记录通用技能 `godot-isolated-test-runner`，用于后续复用这些物理探针、Job 所有权和证据后清理规则。
