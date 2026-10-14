# Round34：完整房间校验阶段计时

## 结论

**真实单任务通过，exit 0、23 CHECK、failures=[]。主要等待是明确配置的 60 秒模拟，不是文件校验线程或 loop_analysis。**

- 准备开始 → 子进程启动 **16.746s**；启动 → 静态/加载检查点 **6.653s**；准备开始 → 检查点 **23.399s**；最终完成 **83.783s**。
- 正式模拟报告 `budget_seconds=60.0, elapsed_seconds=60.113`，占整个任务约 **71.75%**。实际 59 个案例：58 个终局、1 个 `time_budget`。预算用尽的提示不是文件损坏，也不等于死循环。
- 未改任何生产文件、正式配置、既有测试、worker、validator 或 generic runner。只新增本测试 `.gd/.tscn` 与本报告。

## 短单命令重跑

```bash
python -B E:/scratch/round34-stage-timing-20261010/run.py
```

包装器保留在 E scratch，调用仓库既有 Windows Job/路径安全执行器，每次建立全新 UUID 目录。正式场景命令仍是 `--headless --fixed-fps 60 --path <独占副本> --scene res://tests/validation_stage_timing_test.tscn`。包装器 240s/进程看门狗不是模拟预算；不减少正式任务的 30s 静态时限或 60s 模拟时限。源码若缺少当前 worker 的 `prepare_approved_files` 阶段接口，测试明确失败，不复制旧实现假通过。

公开正式 `assets/config/server.cfg:45-49` 明确开启模拟、预算 60s；读取两项原值，没有读取 identity 文件或秘密。选人模式 `unique_master_class_pool`、两席来自既有 `net_validation_simulation_test.gd:6`；不是猜测真实部署房间人数。未使用该夹具的 40s、3s guard 或固定 seed：正式 `room_options` 原样生成 `guard={enabled:true,steps:0,seconds:60}`，没有 seeds，因此正常跑满时间。静态时限与准备批量分别沿正式 UI 30s 和默认 2 文件/poll。

## 同一真实 worker 的阶段数据

最终 `report.performance` 的原始微秒值已归档；下面换算为秒，**不是独立组件探针相加拼成的任务**。

|阶段|秒|
|---|---:|
|引擎启动 → worker ready（worker 自身时钟）|2.423119|
|初检：20 worker 文件读取/哈希/JSON/引用校验|0.087532|
|第二遍定长读取|0.046724|
|第二遍内存哈希|0.208316|
|安全来源注册（再复读、校验 SHA256）|0.837712|
|第二遍 JSON 解析|0.008437|
|中间 blob cache.store|0.000000|
|loop_analysis|0.016390|
|隔离数据组装|2.558226|
|LoadGame.reload_game（含 JSON 快照读写）|0.369200|
|模拟 await 整段（含初始化/收尾）|60.202158|
|worker ready → 最终报告|64.343036|

真实准备的阶段墙钟：copy **6.295s**、verify **3.567s**、assemble **6.884s**、validate **67.037s**。这些阶段包括调度/观察器等待；`preparation_poll_wall_seconds=9.336` 是同步 poll 累计墙钟，**不是 CPU 时间**。观察器每轮实时等 16ms，避免 fixed-fps headless 无上限空转抢占 worker；不能据此承诺真实窗口同样耗时。

额外同进程组件探针独立列在 `timings.json`：validator 0.089s，复读/注册/解析 0.888s，图分析 0.022s，组装 2.978s，冷快照加载 0.164s，已有快照加载 0.173s。LoadGame.reload_game 不只读取已有快照，仍加载模板并调用 store_jsons；没有“热缓存应跳过全加载”的证据。组件数值不加入上面的真实 worker 时间。

## 文件、字节与重复调用

批准清单 **68 条目、204 文件、95,949,242 bytes、203 个不同 SHA256**；一个内容块在两个路径出现，不能将文件数当独立 blob 数。

|可观测事件|次数|字节|
|---|---:|---:|
|目录递归调用|149|—|
|目录叶子返回事件（含重复访问/导入元数据）|659|187,020,153|
|目录扫描去重文件（含导入元数据）|337|96,083,403|
|catalog + base 实际算法哈希调用|206|96,225,263|
|catalog 主 JSON 文本读取|69 个条目|386,307|
|validator 子类真实文件读取/成功哈希|204|95,949,242|
|准备缓存 store|204|95,949,242|
|准备缓存 fetch|668|282,540,535|
|真实 worker.prepare_approved_files + 组装组件的来源复读/哈希|612|287,847,726|
|上述组件 cache.store|0|0|
|上述组件 fetch（包含在来源复读内）|408|191,898,484|

目录事件由测试 CatalogProbe 的递归虚函数收集，只累加每层直系叶子，避免再累加父级返回数组；字节是文件长度，不是宣称目录枚举读出了所有内容。catalog 哈希调用按**未过滤 command_spells 的原始扫描结果**加 base 统计，因此包含命令牌再次进入基础集合的重复哈希。计数成功路径经真实数据验证。

准备 fetch 精确断言为 `2*204 + 192(entry files) + 68(identity JSON) = 668`：组装 check/write 两遍、逐文件核验、条目身份复读。一次准备并没有重复调用 store 整套；source-root 来源没有注册到此客户端准备 cache，因此该实例 `source_hashes=0` 不表示完全没有 SHA256。

worker 当前使用已核验源而不物化中间 blob。测试直接调用正式 `prepare_approved_files`，再调用正式 assembler，来源注册 204 次 + 两遍组装 fetch 408 次 = **612 次真实安全源复读/哈希**，无 cache.store。另用同一真实 JSON 做 `register + 2*(fetch+store)`，子类观测 **5 次来源读取/哈希、2 store、2 fetch**，读取 27,980 bytes；store 自己对传入字节的 digest 不计入“source_hashes”，不能将它误报为全部哈希次数。

在成功、无重试的冻结 worker 链路中，还存在初检 204 次、显式复读哈希 204 次、组装内存 digest 408 次及目标写回 SHA256 204 次。加来源探针 612 次可推导 **1,632 次内容哈希调用**；这是完整代码链推导，不冒充给真实 child 注入了静态 digest 计数器。Hash/check 的安全复读保持原生产契约，未为性能关闭。

## 精确调用链与是否多次触发

- 本机 UI：`lobby_screen._show_room_data:432-437 → room_data_panel.configure:41-76 → catalog.scan:67`。闲置状态再次打开会再次扫描目录，**configure 不启动 RoomValidationTask**。
- 点击采用：`room_data_panel._apply:144-188 → lobby_session.create_data_preparation:1226-1228 → preparation.start:47 → poll(copy:95-148, verify:156-180, assemble:84-93) → validation.start:92 → RoomValidationTask.start:16-81 → OS.create_process:76 → worker → LoadGame.reload_game → rule_random_simulation.run`。
- 服务端：`server_data_prepare → server_data_approval._prepare:72-106 → preparation.start:99 → approval.poll:109-126 → preparation.poll`；活动请求 `_actor != 0` 拒绝新准备，ready 状态不再 poll。
- `rule_random_simulation.run:41-44,60-83` 是**按真实时间期限循环**，没有 seeds 时不断建立新案例，直到期限或 guard 风险；不是“一局结束即可批准”。已有 fixture 的单 seed 会提早终止，不代表生产 60s 配置。
- 本次实际只启动 **1 个**完整校验 child（PID 38564），没有证据支持生产 UI 自动串联多次完整校验。精确符号 `validation_tasks` 在 scripts/tools 中未找到。
- 既有 `net_validation_task_test.run` 会启动一次不完整数据任务（39）、一次立刻 cancel 的任务（49）、一次完整任务（78）；`net_validation_simulation_test` 继承此 run。把这套测试整段耗时当用户的一次完整校验，会混入另外两次启动与夹具缓存组装。不同套件串行更不能直接推断 UI 多次准备。

## 隔离、证据及漂移

最终证据：`E:/scratch/isolated-f621b530d37b4edeb054baf8a561ca60/manifest.json`

manifest SHA256：`f3fbe37c43d6bc6caa4b4c39a8e85c010e617b4f9ac4d49f400ac09f505edcb6`。

- 只复制源码/批准 data/静态 preload 依赖与单测试：776 文件、100,612,383 bytes；没有全工程、全部 tests、历史 scratch 或菜单视频副本。独占复制真正的非 console Godot 主程序到物理 E，未改 D 原引擎。
- 只在隔离副本禁用开发 VCS 自动启动并将主场景设为本测试；application 的 user 路径和 threading 配置不变。先用无 autoload 最小配置导入真实资源，再以正式 autoload 配置导入和运行；最终两次 import 都 exit 0、没有 SCRIPT ERROR/ERROR。
- 真实主/OS.create_process child 的 user 探针 PID 13380/5616，读回 token/JSON 回执与 child exit 0。路径均为 `E:/scratch/isolated-f621b530d37b4edeb054baf8a561ca60/generated/appdata/FateDomination`。实际测试主 PID 6608 同路；校验 child 38564 的真实报告、engine.log、simulation.json、manifest.json 写入该独占 E 子树并已归档。探针 child 不是校验 child 的 PID，二者未混称。
- Windows Job 核验每组 `active_owned_processes=0`，日志句柄释放。最终生成目录（包括引擎副本、验证目录、模拟归档）已删除且读回不存在；只保留 manifest/日志/配置/计时。未按进程名杀其他 Godot。
- 本次冻结 source before/after 和 frozen before/after **全部漂移为空**；D 引擎不变。报告编写初次额外只读比对为空，随后最终复核发现其他代理继续修改 `battle_board_v2.gd`、worker、validator；记录在 `evidence/post-run-drift.json`。本报告数值只属于已执行冻结，**不声称覆盖这些后续生产改动**，不因此修改旧 manifest。生产原工作树的其他代理改动不属于本测试修改。
- earlier `isolated-89e253...` 使用 worker `d10a2a...`（有中间 cache.store），与最终 `75e3c...`（来源注册路径）是**不同冻结**。前者 79.318s/模拟60.115s，后者83.783s/模拟60.113s；不把它们当独占性能 A/B，也不把另一代理的生产修改归功本测试。
- 探针搭建期间保留了缺依赖/首次资源导入、测试 `Environment` 名字冲突、源路径与批准 canonical 路径误用的 RED 证据。均只修本测试或外部包装器；成功冻结之后未修改测试。

关键源 SHA256：

- worker：`75e3c79f2bf3468d6afdbb723de7979d98e80ba7afe15b5a2dc2513e6c66188c`
- validator：`95f0c09f1eac7ab6540f36841b0b999c3cce88d863486d98f54a6e96b9b9d49f`
- preparation：`540e65ed90bbc4ce245fbf737fd85dcae87beb505139003a5415bd4bdeaf7f21`
- task：`0fad05938a792843dc87253c145dad43759605bd00d993be97449039305aff25`
- 新测试 gd：`ba2049018699690c48b9e9aed42b74422c4c2cb9cb50b68d0bec8c1b84ede97e`

**边界：**本任务没有真人窗口输入、没有未知部署的真实房间席位，也没有全机器独占性能承诺。主线程批次调度与安全路径/缓存复读占剩余等待的大部分；纯文件初检和静态图均不是当前 60 秒级瓶颈。若要减少主要等待，需用户显式变更模拟政策，不能用性能优化偷偷缩短预算。
