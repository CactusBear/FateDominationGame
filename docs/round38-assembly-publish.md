# Round38：会话目录发布失败的句柄生命周期诊断

**结论：已精确复现受控占锁导致的“204 文件写完、目标不存在、短根 rename FAILED=1”，但 round34 原现场的占锁者及 Win32 错误仍未证明。没有生产修复、发布回退、重试、权限提升或超时调整；不能称历史失败已根治。**

## 交付与边界

- 新增 `tests/assembly_publish_lifecycle_test.gd/.tscn`。实际调用正式 catalog、plan、磁盘 cache、assembler 和 RoomDataPreparation；发布前只由测试暂停观测，不向生产组件注入诊断钩子。
- `scripts/net/content/room_data_assembler.gd`、`tests/net_validation_simulation_test.gd` 本轮未改。assembler 的既有工作树改动来自此前轮次，未回滚。
- worker、validator、cache、准备器及其他代理拥有的反馈专项均只读。未改项目配置、路径安全门、规则或线程池。
- 独占执行器及原生诊断探针位于 `E:/scratch/round38-assembly-owner/verify.py`、`native_probe.py`，归档内留有副本。诊断只复制自身进程的文件类句柄、读取路径/目录身份及检查共享访问；不启用 SeDebugPrivilege，不检查外部进程文件路径或猜测安全软件。
- 新测试被现有 `.gitignore` 的 `/tests/` 忽略；文件实际存在并已冻结运行、归档，未擅自 force-add、提交或修改忽略规则。

## 原证据与同输入核对

已重读 `docs/round34-validation-pipeline-performance.md` 和原 `delivery-simulation.stdout.log/.stderr.log`、进程回执。原进程 PID=22844、exit=1、9.522s，唯一失败为 `explicit chosen data assembles under approved scratch root`，不是解析错误。原失败字段：

```json
{"phase":"write","index":204,"files":204,"destination_directory_exists":false,"destination_file_exists":false,"staging_exists":true,"destination_length":138,"staging_length":155,"rename_attempted":true,"rename_error":1}
```

原失败前未留该任务 manifest，但同轮 `delivery-pipeline-child-2/manifest.json` 留有正式选择的 204 文件清单。此次通过原 catalog→plan 调用重建，与这份归档清单的 **全部字段和顺序完全相等**；总声明字节 **95,949,242**。不把它说成原失败进程自身落盘的 manifest，也不混用 205 文件整目录集合。

与 round34 最终候选 `frozen_hashes` 比较：assembler、cache、catalog、plan、RecoveryPathSafety、准备器、validator、worker、task 基类及 simulation 脚本均相等。比较证据在 `evidence/historical-comparison.json`，原日志及正式清单副本在 `evidence/historical-input/`。当前新观察仍不能重建已经消失的原现场句柄和 OS 错误。

## 真实机制观测

原生探针先用已打开的普通目录取得实际 File 对象类型索引，再仅复制目标 Godot PID 的同类句柄；管道等非磁盘对象不当作数据文件。复制失败或磁盘路径查询失败单独记录并使测试失败，不能把不可检查误判为无句柄。首次诊断版曾将其他内核对象的 DuplicateHandle error=50 也列入日志，随后收紧到实际文件类；正式最终证据全部 `duplicate_failures=[]`。

|现场|相关自有文件/枚举句柄|staging DELETE 访问|文件共享检查|实际 Godot 发布|
|---|---|---|---|---|
|小清单无锁|0|0|没有拒绝|成功且读回摘要相等|
|自有 FileAccess.READ 保持打开|1，具体 staging 文件|0|同文件 read=0、write=0、DELETE=32|拒绝，FAILED=1，目标不存在|
|自有 DirAccess.list_dir_begin 未结束|1，staging 目录|0|无文件拒绝|**成功**；枚举句柄活着不等于禁止重命名|
|独立自有子进程读文件，share=READ\|WRITE=3|Godot 相关自有句柄0|0|同文件 read=0、write=0、DELETE=32|拒绝，FAILED=1，目标不存在|
|204 文件正常发布边界|0|0|全部文件/子目录 DELETE 访问成功|成功，204 个文件全部 SHA256 读回相等|
|204 文件最后一份 selection_modes.json 保持自有读句柄|1|0|该文件 DELETE=32|index=files=204，FAILED=1，目标不存在|
|真实 RoomDataPreparation 的204发布边界|0|0|全部文件/子目录 DELETE 访问成功|发布及真实隔离规则加载校验成功|

外部占锁子进程的 ready 回执 PID 与 OS.create_process 返回值一致，明确 share_flags=3；释放后实际退出码为0。不是仅凭“自身没有句柄”就推断外部来源。

204 受控失败回执路径长度为 destination=146、staging=164，目标文件/目录都不存在，staging 存在；保持原摘要/写入流程且没有原失败重试。这复现了原症状的一种因果机制，**不证明原失败也由该句柄或外部瞬时锁造成**。

精确 Win32 对照来自同一独占夹具中的一次性 sibling 目录：持有子文件 GENERIC_READ、FILE_SHARE_READ\|FILE_SHARE_WRITE=3，`MoveFileW` 实际返回 false、`GetLastError=5 (ERROR_ACCESS_DENIED)`。同一文件的非破坏性 DELETE-access open 返回32 (ERROR_SHARING_VIOLATION)。**5 是这个原生控制探针的错误，不是从原 Godot 失败回溯取得的错误，也不是实际批准 staging 的发布回退。**

已取得运行引擎提交 `ed1daf0bf` 的官方 Windows 后端源码并归档：DirAccess rename 对该分支使用 MoveFileW，将失败折叠为 Godot FAILED；FileAccess 使用 `_wfsopen`，close 调用 fclose 并清空指针；枚举用 FindClose 结束。没有用不同 API 替代产品发布。

## 生命周期与失败关闭

源码检查并结合真实边界观测：assembler 写句柄在摘要读回前显式 close；cache 的 fetch/verified-source 读句柄在返回前 close；路径检查的 DirAccess 和 catalog 枚举均为局部生命周期。真实 RoomDataPreparation 的 source 输入句柄也在 cache.store/publish 前 close。两种正式204发布边界未观测到 source/cache/staging 的自有存活文件或枚举句柄，测试还检查了可检查性，而非仅相信局部变量作用域。

小清单和正式204正常发布前后，父目录身份以完整字符串记录并相等，避免 JSON float 损失 inode/volume 精度。另将**仅自身父目录真实移走**：staging 在原路径消失，Godot 发布 FAILED=1 并拒绝。这与原日志 staging_exists=true 不同，不能把该负向案例当作原失败解释。

专项还实际覆盖：
- 写完但未发布时目标不存在；所有已发布字节读回批准摘要。
- 发布前取消：不发布半成品，也不继续旧 generation。
- 初检后真实 cache 字节变化：write 阶段拒绝，目标不存在。
- 发布前出现目标文件或目录：rename_attempted=false，保留原文件字节/原目录。
- 自有及外部文件占锁：拒绝、不设置 complete、不发布目标；只释放/终止自己创建的 PID。
- 完整准备相关的源变更、路径/摘要/大小门及正式采用链，继续由未改的 pipeline/dependencies/environment 专项真实执行。

以上保持既有可信目录/串行写入契约，不宣称能防同权限恶意进程在预检与 OS 调用之间置换路径。未加入失败后换目录、删除目标、shell move 或未验证目录发布。

## 最终冻结复验

最终新测试版本后，重新 import 并顺序执行下列六套；每进程真实看门狗 **180s**，引擎为独占物理 E 副本，命令形态：

```text
python -B E:/scratch/round38-assembly-owner/verify.py final-import
python -B E:/scratch/round38-assembly-owner/verify.py scene final-lifecycle assembly_publish_lifecycle_test
python -B E:/scratch/round38-assembly-owner/verify.py scene final-simulation net_validation_simulation_test
python -B E:/scratch/round38-assembly-owner/verify.py scene final-hard-timeout net_validation_hard_timeout_test
python -B E:/scratch/round38-assembly-owner/verify.py scene final-complete-preparation validation_pipeline_performance_test
python -B E:/scratch/round38-assembly-owner/verify.py scene final-dependencies room_data_preparation_dependencies_test
python -B E:/scratch/round38-assembly-owner/verify.py scene final-environment lobby_content_environment_restore_test
```

实际 Godot argv 保存在 manifest.processes：`--headless --fixed-fps 60 --path <冻结工程> --scene res://tests/<suite>.tscn`。准备依赖专项另显式传入批准 E 根。

|最终套件|exit|实际CHECK=RESULT checks|判定|
|---|---:|---:|---|
|assembly_publish_lifecycle_test|0|66|PASS：包括受控真实发布失败与准备边界观测|
|net_validation_simulation_test|0|35|PASS：真实随机预检/隔离加载/采用|
|net_validation_hard_timeout_test|0|37|PASS：真实暂停自有子进程并由硬截止终止|
|validation_pipeline_performance_test|0|260|PASS：完整静态/模拟及正式准备/采用|
|room_data_preparation_dependencies_test|0|34|PASS|
|lobby_content_environment_restore_test|0|1544|PASS|

合计 **1976 checks，6/6**。每套唯一合法 RESULT、无失败 CHECK、无 SCRIPT ERROR/ERROR，最终 import exit0、errors=[]，冻结工程无漂移。早期诊断/扩展测试日志单独保留，不加到最终总数。原 simulation 这次成功只说明当前样本通过，不冲抵 round34 RED；没有修复型 RED→GREEN，因为根因未明确、生产代码未改。

最终 environment 执行期间其他代理修改 `scripts/system/global/master_manager.gd`；冻结未漂移，自有交付文件均与冻结相等。故这是明确冻结副本六套 PASS，不是当前整个工作树或整仓全量通过，也没有窗口/多机/跨网验收。

## 归档与收尾

归档：`reports/refactoring/round38-assembly-publish-aebee0ca538841bab8ffef4f3b528e10/`。

留有 manifest、完整 stdout/stderr、正式 child 报告/manifest/配置/engine.log、主/child user 路径回执、历史输入、原生快照、最终源码、执行脚本和官方后端参考。`evidence/final-verdict.json` 给出程序化最终计数与观测摘要。

主/真实派生探针均写入并读回物理 E user 回执；正式 worker 也保留真实 user 回执，池20保持。Job Object 仅约束本轮挂起创建后立即纳入的 PID 树，所有已记录进程 `exited=true`、`active_owned_processes=0`、日志句柄释放；额外精确自有可执行路径查询为空，不按进程名称清扫。

先复制项目归档并逐文件校验 SHA256，再回收唯一 `E:/v38/isolated-aebee0ca538841bab8ffef4f3b528e10/generated`。回执 `archive_verified_before_cleanup=true`、`cleanup=generated_removed`、`generated_exists_after_cleanup=false`；D 盘源引擎摘要未变。未回收其他代理或正式数据目录。

## 未解决项与政策

1. 历史失败缺发布时的自身/外部锁现场与 Win32 精确错误，现有样本未再出现非受控失败。不能据一次重跑成功宣布修复，也不能从 FAILED=1 或 Win32 5 单独判定杀毒、权限或锁。
2. **不加入重试。** 仅若未来现场证明是外部瞬时占锁，才提交有界尝试次数/总时间、取消与 generation 检查、每次路径/目标冲突/内容仍有效的复验、耗尽失败关闭的政策；这些参数目前未确认，不擅自赋值。
3. 后续若需精确识别新的非受控 MoveFileW 返回值，应在同一自有运行进程的真实失败调用点观测，不能拿此次 sibling 控制探针的5或后续成功替代缺失证据。当前没有可以据此实施的最小生产修复。

最终自有文件摘要：
- assembler（未改）：`f39d01f8b8a48a3298c461a69fdcee986e68559066b29e69957e0899f76d282e`
- simulation（未改）：`310ff0a7c36baa041cd8737e612e2da2947bc7cbbba5d40dd0eec237394f0560`
- 新测试 gd：`df499eff188d781c57b90a5ded679b9c0cc732f7ace9d8ca87e0cb607c14792b`
- 新测试 tscn：`087ed73bbfee68515fb45a3c37bdc229868b5a857760df78be01f964da7f6470`
