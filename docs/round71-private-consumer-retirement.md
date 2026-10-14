# Round71 F05：三处私有测试观测退休交接

## 结果与唯一范围

实际迁移 **1 份测试、3 个词法 occurrence**，没有凑成 2–4 份文件。本轮仓库唯一写入：

- `tests/net_guard_rollback_test.gd`：33、245、280 行三处读取。
- `tools/tests/test_round71_private_consumer_retirement.py`：独占冻结/原件对照/负向/回读工具，复用已有 OwnedJob 与严格 RESULT 分析器；未改旧 runner。
- 本报告。

production、gate/allowlist、其他测试只读；没有 test-only API、`get("_private")`、字符串反射或新接口包装。测试文件虽有可选 `-- window` 分支，本轮只改其原有公共流程中的三处引擎观测，不改任何 GUI 分支，且只执行 headless，不声称窗口验收。禁止名单中的 battle_play_groups、窗口专项、round60 六命令测试、shutdown 三套、audit_commit/deferred_transaction 均未写。

## 原语义及等价边界

1. 原事务字典 `.get(effect)` 用于诊断真实暂停检查点；`capture_transaction_state().transaction_bindings` 按生产实现复制外层字典，保留同一个 effect/checkpoint 引用，因此原 `ready/error/root/random.known` 诊断原样保留。
2. 原 `_paused_runs.is_empty()` 检查网络链回滚撤销父续行；`paused_runs_snapshot()` 枚举同一字典键，外层/记录复制不改变 empty 判据。原临时效果注销、双方魔力恢复、客机旧待答撤销、旧答复拒绝断言全部保留。
3. 原 `_guard_continuations.is_empty()` 检查真实重开丢弃旧尾部；公开事务令牌的 `continuation_queue` 复制同一票据队列。原种子不变、`not old_tail`、从批准模板重建阵容及新局视图递增断言全部保留。

解耦审查：只消费已有生产快照，不改变交易建立/结算，不替换业务执行入口。公开 `runtime_guard_effect/status/root_effect`、`can_rollback_runtime_guard`、待答 API 与上述 snapshot 的真实实现均已读取。其余剩余入口不强迁：运行中 `run_time_point` collect 与私有 queue 不是同一行为；phase/round-end 私有完成标志、待广播公告完整容器、scratch 人工故障状态写入均尚未证明有等价公开契约，保留为未来生产 API 责任，不开放任意私有 setter。

## 当前同一冻结的真实证据

最终根：`E:/scratch/round71-private-c96fd8c837974aa88410a2df10b49a46/`。

|阶段|exit|实际 CHECK / RESULT checks|failures / SCRIPT ERROR|
|---|---:|---:|---|
|原件 observer|0|39 / 39|空 / 无|
|迁移件 observer|0|39 / 39|空 / 无|
|真实 host rollback 前故意失败|1|40 / 40|仅 `round71 negative before actual host rollback` / 无|
|最终正式迁移原字节，无 observer、无固定播种|0|39 / 39|空 / 无|

**GREEN actual=1 / unique=1 / 39 checks**；不把原件、observer 与历史绿拼成多套覆盖。

原件和候选四个停点 `initial_mutation_pause / chain_answer_pause / chain_rollback / restart_complete` JSON 逐值完全相等，四方面均取真实 Godot 状态：

- 资源：每名玩家魔力、战果、牌堆/手牌/弃牌/技能区计数。
- 随机：完整公开 seed/state/known 与检查点随机快照。
- 事实：真实 GameLog 的 type/actor 顺序，审计 event 顺序；不宣称比较未纳入的全部事实 payload。
- 事务：effect/root 名、ready/settled/error、暂停 choice 身份名称、批次/尾票/尾票归属数量、guard 全状态；并比较时点窗口与 time_point_id、待答/执行池。

跨进程对象 ID 不作为比较键；正式 API 仍保留对象身份，未用名称代替正式 lookup。observer 仅注入独占副本。两 observer 副本在选人抽样/初始顺位产生前通过现有公开 RuleRandom 统一播种；最终正式字节场景不播种、不带 observer。

负向仅在隔离测试副本多插一条 `check(false, ...)`，并关闭测试宿主按 failures 提前停止的逻辑，以执行全部原 39 条业务检查。实际房主 skip、双方恢复、链 rollback、restart、return-lobby、再次选人/开局都继续执行；生产参数、检查点、断言条件未削弱。最终自然 exit1，唯一失败仍保留。然后恢复正式迁移字节/hash，完整 GREEN；不需要给宿主添加 static 状态或生产接口。

按仅标准化三项已批准替换后的 check 行多重集合比较：`missing_assertions=[] / added_assertions=[]`。原断言未删除，GUI 业务段原样保留但未运行。

## 精确 gate 交接（main 才可退休许可）

初始真实 CLI：exit0，46 findings / 46 allowlist = 4 layer + 42 private，NEW=[]、STALE=[]。
当前真实 CLI：exit1，43 findings / 46 allowlist = 4 layer + 39 private，NEW=[]，**仅以下三条 STALE**。本轮未写许可表。

|path|target|精确旧 code|count|
|---|---|---|---:|
|`tests/net_guard_rollback_test.gd`|`EffectManager._guard_transactions`|`var checkpoint = EffectManager._guard_transactions.get(effect)`|1|
|`tests/net_guard_rollback_test.gd`|`EffectManager._paused_runs`|`check(not EffectManager.effect_pool.has(chain_effect) and EffectManager._paused_runs.is_empty(), "网络连锁回滚撤销临时效果注册与父子续行")`|1|
|`tests/net_guard_rollback_test.gd`|`EffectManager._guard_continuations`|`check(host.match_authority._restart_seed == seed_before and not old_tail and EffectManager._guard_continuations.is_empty(), "重开保留种子并丢弃旧执行片尾部")`|1|

evidence_line 分别 33、245、280，不把行号当许可身份。gate SHA256 前后保持 `a228663dfe54d5800de99e6589ad997661aeabeccd3bb51cf374698f367c981b`。

## firstroot 与保留的真实失败

本轮第一次物理分配：`E:/scratch/round71-private-ca3cb31c0f7a458e85874bc18f8e6d27/`，冻结期间另一写入者更新 temporary_cleanup_ledger，copy hash 拒绝，未运行 Godot。

随后 `...31e3796ac03e46fc95c47634710d415d/` 原/候选均39 checks，但第一次比较显示选人顺位已在播种之前产生，事实/窗口不同。保留历史 logs/equivalence，提前到真实选人前播种，四停点相等之后才写三处正式 GD。第一次 verify 又因 runner 候选写成 CRLF、正式源码为 LF 的字节不一致拒绝；没有放宽 hash，改为候选保留 LF 后重建。该失败及旧候选原字节保留。

`...d9965ebab4fa479d96d26b38f0941457/` 在并行 battle_board 更新期间冻结拒绝，未运行 Godot。

`...30140414b3bf44b49ae86069e22eff4e/` **原件自身首红**：11 checks，`initial_mutation_pause`；资源/可回滚检查点成立，但 host/guest actions/view 均为空。公开独立 MatchViewMirror 实测 `accept=false / error=地图视图无效`，host 错误 `权威待答视图无效，未发布`。原件、诊断、最终正式迁移字节均自然 exit1，无 SCRIPT ERROR；未修生产或放宽镜像验证。旧根 readback 标记 BLOCKED，保留失败。随后检测到其他写入者更新 view_mirror 等源码，重新冻结到最终 c96 根，才得到上述原件/迁移/negative/final-GREEN 完整同冻结结果；不以旧绿掩盖旧首红，也不把同时发生的源码变化写成单一因果定论。

## 哈希、资源与命令

- 最终 manifest SHA256：`b88abbe55818b99b43fbf1152653dd49d8ac9b83630f0c6e356997d27821c7cb`。
- 最终生产/依赖冻结 fingerprint：`3a95ff7590c9ded195b3103e902037c168c00b7fae2a5945d59cc3dea6707b46`，1802 个明确依赖文件，tests 仅7项继承/preload闭包，不复制整 tests。
- 原 GD SHA256：`ec700142265395c3314687f129de1bf85673fae7bfa956de264d2253d2f7d84f`。
- 正式迁移 GD SHA256：`4e555be7db7e5ce889bfa4015f82e2685f2b88e5b7bce24003253b15c338f141`。
- `evidence/migration.patch` SHA256：`48796a1c1eb6e0b4aff79f24d65e756ada9309058f23f1514d96878af5e1cf47`；`original.gd/candidate.gd` 保存原/迁移源码。
- `evidence/readback.json` 保存三文件最终 scope SHA256、精确 STALE code/count、四停点等价、实际/声明 checks、命令/PID/exit、原件/当前/最终 GREEN 一致性、log/source drift=[]。
- 原 E 引擎 hash 与既有获准基线一致；9 个正式 DLL hash 均与原批准 freeze 一致，未构建/替换 native。
- 每进程180秒、自有 Windows Job、fixed-fps60/headless；真实 main/worker user 路径探针通过。最终6条 root 记录均 Job0；含历史共18条自有 root 记录全部 exited、ActiveProcesses=0、日志句柄释放、无预算失败。未终止其他 PID、未跑99/allGUI。
- 五个自有根的 generated 工程/引擎/user 数据均删除，只保留 manifest、patch、源码归档和日志。失败生成树亦按 owner 回执与 Job0 清理。

真实命令（仓库根，日志中的 Godot argv 为实际执行路径）：

```text
python -B tools/tests/test_round71_private_consumer_retirement.py --restart E:/scratch/round71-private-31e3796ac03e46fc95c47634710d415d/manifest.json
python -B tools/tests/test_round71_private_consumer_retirement.py --verify E:/scratch/round71-private-c96fd8c837974aa88410a2df10b49a46/manifest.json
python -B tools/tests/test_round71_private_consumer_retirement.py --readback E:/scratch/round71-private-c96fd8c837974aa88410a2df10b49a46/manifest.json
python -B tools/check_layer_deps.py --json
```

前三条最终 exit0；gate exit1仅三条预期STALE。首次 prepare/reprove/byte-mismatch、地图首红及清理命令日志/回执保持独立。未 stage/commit；测试可能被 Git ignore，交付以实际字节和 patch/hash 为准。default profile 的迁移技能仅补充换行、选人播种与并行首红经验。

剩余：main 精确删除三许可后重跑 gate；其余39 private 不在本轮覆盖；GUI/真人/跨机/导出/99套未验收。
