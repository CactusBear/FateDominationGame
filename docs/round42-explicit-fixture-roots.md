# Round42：两套夹具显式输出根

## 结论

- 已移除两套拥有脚本中的 `E:/Projects/Godot/FateDomination/test` 输出硬编码。lobby 的继承入口也不再重新选择旧 `restore-atomicity` 根。
- 同一冻结副本真实 Godot 4.7.2：lobby **1544 checks / failures=[] / exit 0**；blob concurrent **20 checks / failures=[] / exit 0**。两套均另有重复 GREEN，业务断言未减。
- 新契约场景：有效业务 RED（缺消费入口，2 checks、2 failures、exit 1，无 SCRIPT ERROR），接线后 GREEN（6 checks、failures=[]、exit 0）。没有为了制造 RED 启动会真实写未授权旧根的旧业务入口。
- 11 类非法输入 × 两套 = **22 次**真实 Godot 拒绝；每次唯一合法 `RESULT checks=1 failures=[...]`、exit 1、无 SCRIPT ERROR；拒绝前后外部夹具目录/文件元数据快照完全一致。
- 源和冻结副本的 `data/**` **339 个文件 SHA-256 全部不变**。旧 E 输出根、默认 C 用户数据根无新增文件。
- 本任务 generated 已回收，实际 **4,405,590,793 bytes**，读回不存在；持久证据、原/新源码、差异和摘要保留。

## 给聚合器的参数契约（聚合器未修改）

```text
FATE_TEST_SCRATCH_ROOT=<本轮当前 UUID manifest 批准的、已存在物理 E 根>
godot --headless --fixed-fps 60 --path <冻结工程> \
  --scene res://tests/lobby_content_environment_restore_test.tscn \
  -- <该批准根内已存在的专属输出目录>
godot --headless --fixed-fps 60 --path <冻结工程> \
  --scene res://tests/net_blob_concurrent_test.tscn \
  -- <该批准根内另一个已存在的专属输出目录>
```

- 两套只使用 `OS.get_cmdline_user_args()[0]`；环境变量不能替代首参数，首参数也不能替代环境授权。
- 聚合器必须显式提供当前 UUID 的可信批准根及预创建输出目录；夹具不猜 UUID、不按名称推导路径、不读取 round41 历史根、不采用默认 user/TMPDIR 根。
- 批准根和首参数必须以规范 `E:/` 开头。其余规范性、逐层祖先链接拒绝、包含关系、已存在目录检查，全由既有 `RecoveryPathSafety` / `net_server_match_test.fixture_directory()` 实施；不修复反斜杠、点段或越界输入。
- UUID/当前执行者身份属于外部 manifest 授权，不新增“目录名长得像 UUID 就自动批准”的规则。路径字符串存在并不自行产生授权。
- 仅在上述检查通过后，既有 primitive 创建 `<输出目录>/<label>-<pid>-<ticks>` 独占子目录。lobby 的内容缓存、候选数据、恢复原子性阶段全部在该子目录内；其他既有 `user://` 行为依赖执行器显式 E 盘环境。
- 缺参、缺环境、C 盘、缺根、链接或越界均立即 `check(false)` + `finish()`；不会继续业务阶段。正向前置不额外计 check，保留聚合器已知 1544 / 20 总数。
- `tests/isolated_fixture_root_contract_test.tscn` 正向同样接受首参数。其第二参数 `reject` 仅用于该契约场景声明负向预期，不是业务夹具参数。

## V4A 修改说明与解耦审查

拥有文件以 V4A 局部补丁修改，可复用补丁保存在证据 `fixture-roots.v4a.patch`；普通差异见 `fixture-roots.diff`，完整原始/最终源码亦已归档。

1. **`isolated_fixture_root_contract_test.gd/.tscn`（新增）**：测试层薄适配入口 `directory(label)` 只声明本轮物理 E 盘前置，然后复用已有恢复校验夹具 primitive。场景在真实 Godot 中实例化两套未挂树消费方，检查入口存在、按声明拒绝/接受及真实目录安全性。未创建新生产安全规则。
2. **`lobby_content_environment_restore_test.gd`**：新增 `_explicit_fixture_directory()`；`run()` 最先处理合法回执/失败关闭，打印实际 PID、工作根和 user 根；`_content_environment_paths(work)` 改为接受明确工作根。原 `super.run()` 会在父类重写 `fixture_root` 到旧绝对位置，因此在拥有的子类仅重组原父类的七个阶段：active/shared/preflight、persist/replay/receipt、success。所有真实恢复方法和断言仍继承父类，没有复制规则或改父类。恢复根明确设为当前工作根下的 `restore-atomicity`。
3. **`net_blob_concurrent_test.gd`**：同一薄适配入口在监听和缓存写入之前执行，合法时只设置 receiver 缓存根；两来源真实 ENet 分块、来源绑定、预算释放、断线独立性、完整落盘、收尾全部不变。
4. 两个原 `.tscn` 不需要变更，已保留。`production/**`、父夹具、聚合器均未由本任务修改。

共享安全策略来自既有原语，不在两套业务夹具复制路径判断。因只拥有子夹具，父类阶段组合仍需手动保持同步；这是明确保留的维护边界，不冒充完成父类重构。

## 真实执行与证据

持久目录：

```text
E:/scratch/isolated-0ef08a979bfe4c95b9a33a4f42448437/evidence
E:/scratch/isolated-0ef08a979bfe4c95b9a33a4f42448437/manifest.json
```

真实命令入口（已执行，不是建议命令）：

```text
python .../evidence/run_fixture_roots.py setup
python .../evidence/run_fixture_roots.py red
python .../evidence/run_fixture_roots.py green
python .../evidence/run_fixture_roots.py negative
python .../evidence/run_fixture_roots.py repeat
python .../evidence/run_fixture_roots.py verify
python .../evidence/archive_cleanup.py
```

每个完整原生 Godot 命令、launcher PID、退出码、用时、关闭状态均在 `manifest.json/processes`；业务 engine PID 和实际输出/user 根在 `EXPLICIT_FIXTURE_ROOT` 日志。Windows console launcher 与 engine PID 不一定相同，执行器用自有 Job Object 追踪整棵树，而非按名称结束其他 Godot。

| 证据 | 结果 |
|---|---|
| `red-contract.stdout.log` | 缺两套显式入口，合法失败 RESULT，exit 1 |
| `green-contract.stdout.log` | 6 checks，exit 0 |
| `green-lobby_content_environment_restore_test.stdout.log` | 1544 checks，exit 0 |
| `green-net_blob_concurrent_test.stdout.log` | 20 checks，exit 0 |
| `repeat-*.stdout.log` | 最后一次重复 GREEN，1544 / 20，exit 0 |
| `reject-*.stdout.log`、manifest `rejection_external_checks` | 22 次合法失败；外部文件/目录元数据无变化 |
| `external-verification.stdout.log`、manifest `data_before/data_after` | 源数据摘要、外部新增扫描原始证据 |
| `original-sources/`、`final-sources/`、`fixture-roots.diff` | 原源码摘要与首次冻结匹配，最终四个拥有文件摘要稳定 |

负向矩阵：缺首参数、缺环境、C 输出、C 批准根、越界、输出根不存在、批准根不存在、真实 junction、已有子目录的链接祖先、点段、反斜杠。

主/真实子进程探针实际 user 根均为：

```text
E:/scratch/isolated-0ef08a979bfe4c95b9a33a4f42448437/generated/appdata/FateDomination
```

探针 engine PID：main **32060**、child **37264**；子进程 exit 0，原生父等待退出；两份物理文件和回执由外部读回、核对摘要。业务两套也打印同一 E user 根。APPDATA、LOCALAPPDATA、TEMP、TMP、TMPDIR 只对本任务子进程显式重定向 E 独占目录，未修改系统环境。

每次 180 秒看门狗，仅处理自有 Job/PID 树；已归档的 33 个执行记录全部 `exited=true / active_owned_processes=0`，最长 54.651 秒。故意 junction 已先移除并确认不存在，再用既有保守回收 primitive 安全遍历/删除自有 generated；未询问用户、未按进程名清理。保留的 repeat 日志为最后一次同名执行；初始 GREEN 日志独立保留。

## 外部验证范围和遇到的问题

- 新旧数据 SHA 使用 Python 外部计算，不用 Godot 自报代替。22 次拒绝同时读回已有 fixtures/unapproved 整树目录、文件类型/大小/mtime，确认未新增或修改业务产物。
- 源工程、旧 `E:/Projects/Godot/FateDomination/test`、`C:/Users/Administrator/AppData/Roaming/FateDomination`、`C:/Users/Administrator/AppData/Local/Godot` 做外部新增文件扫描。旧输出根和两处 C 根始终为空新增。
- 并发其他代理向源工程 `reports/refactoring` 等位置写报告，故全仓库“完全没有新文件”的严格断言真实失败，已保留原始新增清单。不能把这些并发报告当本夹具越界写，也不能声称全机零写入；所测旧输出根/C 默认根无泄漏、339 个源数据文件不变已成立。
- 首次冻结 import 因仅复制所需插件却保留 GitPlugin 编辑器自动启动而报错；只在冻结副本关闭 VCS 自动启动后重新 import 干净通过。这不是业务 RED，原项目配置未改。
- 外部执行器最初整树预算扫描会提前拒绝自建 junction；该次在自有 Job 关闭协议内终止，链接移除。后改用同一 E 树内无链接监控 cwd，让真实 Godot 原语执行链接拒绝；180 秒/自有进程约束保留。此反例阶段不宣称整树字节预算获得持续保证；全部实际 generated 在交付前已回收。
- tests 被 `.gitignore:47 /tests/` 忽略，`git diff` 空不代表未修改；未 force-add、未提交。磁盘源码及摘要是本次交付依据。
- 无窗口验收、无真实独立 authority worker 生命周期验收；主/子探针只证明本任务启动环境继承与 E 盘实际路径，不扩大成 worker 产品验收。

## 最终四文件摘要

```text
57bee431227486ac2f60fc44c41bc3aeb28da6d24d56473ba233fdb58130ba3f  tests/lobby_content_environment_restore_test.gd
5b4cc1b2740239b158e8dc0a087c17d0e1fa668d906f31c4d2103243d31d0b1d  tests/net_blob_concurrent_test.gd
5415dd3fbc1aaa94a6a1624b0c935eb70a0e3f8d3201c282dde78cb585a18c82  tests/isolated_fixture_root_contract_test.gd
b0f802bc0ad27020ee1db9af71e8fd5c008b89548159a94355e04b5eb32bda4c  tests/isolated_fixture_root_contract_test.tscn
```
