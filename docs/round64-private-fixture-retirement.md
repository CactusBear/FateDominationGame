# Round64 私有测试消费者退休

## 编辑前唯一所有权登记

本分支唯一可写现有 GD：
- `tests/audit_commit_test.gd`
- `tests/deferred_transaction_facts_test.gd`

新独占 runner：`tools/tests/test_round64_private_fixture_retirement.py`；报告：本文。生产、gate/allowlist、完整执行器、其他测试只读。两份文件四处调用，不为数量迁移整套 board 或引入兼容字段。

## 原语义与替换边界（编辑前）

1. audit 原108 `_begin_guard_transaction(root)`：建立真实根 start 并留住未 settled 的原检查点，让后续真实磁盘 commit 失败验证事务仍持有。现公开 `pay_effect_cost(root)` 先执行同一根建立，root 无 cost，因此不扣资源或派发时点；额外 flush 在健康写入器上须成功。不通过公开管线提前 commit。
2. audit 原112 `_release_guard_transactions()`：空闲根 commit 写失败不 settled、不丢归属。公开 `run_pipeline(true)` 在无选择、无执行池、无排队/尾票的同一停点最后执行原 release；必须对照无额外规则改变。
3. deferred 原59 `_queue_time_point_batch(effect, 0)`：真实跨玩家待答期间登记后续时点，事实不可越 commit 边界。公开 `run_time_point(effect, 0)` 在 is_running=false / is_waiting_for_choice=true 的停点进入同一 queue 分支；额外 transient consume 必须在本夹具空瞬时时点下无改变。
4. deferred 原94 `_release_guard_transactions()`：完成后重复 release / resume 不重复投递四条事实。公开 `run_pipeline(true)` 在真实已清空的管线执行 release，保留原一次性投递断言，并核对无额外资源/随机/事实变化。

解耦审查：复用已有生产公开入口及 snapshot/query；不加 prod wrapper、反射或模拟成功响应。根 v2 Mutation 的私有入队发生在 is_running=true，公开 run_time_point 会 collect 而非 queue，不能等价替换，保留。net_guard_rollback/outpost/net_v2/pending_board 含 GUI/board，因此不碰；腐蚀的 round-end 私有标志未发现已有等价公开投影，保留。

## 初始只读门

`python -B tools/check_layer_deps.py --json`：exit0，PASS，findings=50 / allowlist=50；layer=4 / private=46；new=[] / stale=[]。后续 gate 若 stale 仅交精确锚点 main 统一退休。

## 已完成结果

四处私有调用已迁移，两份唯一测试文件；**GREEN actual=2 / unique=2 / 实际 CHECK=293 / 零 ERROR**。不是三至五份测试，未为数量动不相关或缺等价入口的文件。原件本来通过，因此使用原件/迁移件的真实等价 observer 对照，不伪称修复原业务 FAIL。

## 程序计数与 main 退休交接

|扫描口径|before|after|
|---|---:|---:|
|全树 findings|50|46|
|private findings|46|42|
|layer findings|4|4|
|两份自有文件 private findings|4|0|
|allowlist|50|50|
|NEW|0|0|
|STALE|0|4|

初始门 exit0；迁移后真实 CLI exit1，**只因以下四项 STALE**，不是 gate 绿。gate/allowlist 本分支未写，SHA256 前后同为 `627a526d28f41f2ff224c0de7356ffa169cb491b1e86d2a52ffb76f1df09a1d0`。main 仅按以下精确词法锚点各删一个 occurrence：

|path|target|gate evidence_line|本轮原源码行→当前行|精确旧 code|count|
|---|---|---:|---|---|---:|
|`tests/audit_commit_test.gd`|`EffectManager._begin_guard_transaction`|106|108→109|`check(EffectManager._begin_guard_transaction(root), "真实根事务 start")`|1|
|`tests/audit_commit_test.gd`|`EffectManager._release_guard_transactions`|109|112→113|`EffectManager._release_guard_transactions()`|1|
|`tests/deferred_transaction_facts_test.gd`|`EffectManager._queue_time_point_batch`|59|59→60|`EffectManager._queue_time_point_batch(effect, 0)`|1|
|`tests/deferred_transaction_facts_test.gd`|`EffectManager._release_guard_transactions`|94|94→95|`EffectManager._release_guard_transactions()`|1|

当前新调用依次为 `pay_effect_cost(root)`、`run_pipeline(true)`、`run_time_point(effect, 0)`、`run_pipeline(true)`。evidence_line 只是 gate 冻结证据，不以当前行号伪造词法许可身份。

## 真实原件/迁移对照与负向

所有游戏场景使用同一隔离生产冻结、原 E 引擎及旧 DLL；测试仅两入口与真实继承/preload 闭包。observer 函数仅注入独占冻结副本，不落到正式 GD，取已有公开 transaction snapshot、paused-runs snapshot、规则事实 query、随机 snapshot、公开资源/时点窗口与 guard 状态。

|完整场景|原件 observer exit / CHECK|公开 observer exit / CHECK|负向 exit / CHECK|最终无 observer 字节 GREEN exit / CHECK|
|---|---|---|---|---|
|audit_commit_test|0 / 243|0 / 243|1 / 244|0 / 243|
|deferred_transaction_facts_test|0 / 50|0 / 50|1 / 51|0 / 50|

每份原件和迁移件两处 observer 的 JSON 逐值一致，四个停点均匹配；不是仅比最终 RESULT。包括根/子绑定名称及 settled、审计事件顺序、当前/动态时点数组、资源与牌区大小、随机 seed/state、事实类型顺序、time_point_id、选择/执行池、暂停父记录、事务批次和尾票投影。audit 根前态健康 flush 没有扣资源或提交；真实 commit 写失败仍保留原 checkpoint，公开根及当前效果身份、拒绝续行/skip 的原断言全部保留。deferred 正常续行四条事实、同帧/跨帧撤销与重复投递拒绝的原断言保留。

**可观察边界**：deferred 的待答后续队列发生在非回调作用域，`batch_transactions` 投影为零只表示没有该批次的事务归属，不等于内部实际未入队。等价性依据真实待答停点、公开 `run_time_point` 实际 queue 分支、两名玩家 current/dynamic 数组均为空（额外 transient consume 无改变）、以及保留的真实 rollback/事实投递断言。未新增私有队列观察或声称公开 snapshot 覆盖其内部长度。

两份负向只在独占副本多插一条 `check(false, ...)`：audit 在 failed commit 前；deferred 在真实 child budget pause 后、skip rollback 前。两套均自然 exit1，唯一 RESULT 保留失败，各自实际 CHECK 与 RESULT checks 等于244/51，没有 SCRIPT ERROR/ERROR/timeout；deferred 真实回滚没有吞掉失败宿主。随后恢复归档迁移字节并核对 hash，最终两套原字节自然 exit0。负向只验证 observer 敏感性，不宣称生产突变覆盖。

程序按多重集合比较原 `check(...)` 行（仅标准化已批准 API 替换），两份 `missing_assertions=[] / added_assertions=[]`。未删断言或业务步骤。

## 证据、哈希与真实命令

独占证据：`E:/scratch/round64-private-0cc0373552844229839f2e60abe0bb98/`。

- `manifest.json` SHA256：`c4dd4aad1b98d9617e27a71953c7823937da275f35817c7d193183005c675ac2`。
- `evidence/readback.json`：程序生成的 before/after、四个 STALE 完整 code/count、逐场景 actual/declared CHECK、原件/当前 hash、完整 observer 对照、Job0/命令/PID/exit 和日志回读。
- `evidence/original/*.gd`、`evidence/migrated/*.gd`：原件与实际验证字节；当前与最终 GREEN hash 相同，原件 hash 与冻结清单相同。
- `evidence/migration.patch` SHA256：`1e6146de974c99dd9e7272c9562d6d8cb2153491942173a2b5b2150af2cdf06a`。
- `evidence/{original-,public-observer-,negative-,green-}<suite>.stdout.log/.stderr.log`：真实全量输出；只读 hash 回查 `log_drift=[]`。
- 引擎 SHA256：`ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`，采用既有 `E:/scratch/round51-engine/Godot_v4.7.2-stable_win64.exe` 的自有副本。全部 DLL 对照 round58 原批准冻结 hash，无替换或新构建；各 DLL 明细在 readback。
- 生产/非自有依赖当前 vs 冻结 `unowned_source_drift=[]`。副本仅复用已有获准 editor/VCS 转换，未修改仓库 project.godot。

|唯一 GD|before SHA256|after SHA256|精确当前位置|
|---|---|---|---|
|`tests/audit_commit_test.gd`|`e0c428e778e73ba76f47edc7800d74c49fc145d4e2dfef4afd8a61c43f99c251`|`8314b5f395fc10754aef482f174a5256aec31cbf6ec0454be0f909a333af8fa7`|109、113|
|`tests/deferred_transaction_facts_test.gd`|`81e7ce581c630efc61b121ad775070cbfe896384a0bd6c1248ccb78115f5f8d1`|`a162839e178649913bd8eb898e5fdcd2df5f907a04a30a6d09862680b60ca7dc`|60、95|

真实命令（仓库根）：

```text
python -B tools/tests/test_round64_private_fixture_retirement.py
python -B tools/tests/test_round64_private_fixture_retirement.py --verify E:/scratch/round64-private-0cc0373552844229839f2e60abe0bb98/manifest.json
python -B tools/tests/test_round64_private_fixture_retirement.py --readback E:/scratch/round64-private-0cc0373552844229839f2e60abe0bb98/manifest.json
python -B tools/check_layer_deps.py --json
git diff --check -- tools/tests/test_round64_private_fixture_retirement.py docs/round64-private-fixture-retirement.md tests/audit_commit_test.gd tests/deferred_transaction_facts_test.gd
```

前三条 exit0，diff-check exit0；gate 初始exit0/后续exit1仅四个预期STALE。冷导入 exit0、零错误；真实完整场景加载并运行，不只凭 import 判 parse 成功。

## 自有资源与范围

每进程180秒，场景固定60fps/headless，环境 APPDATA/LOCALAPPDATA/TEMP/TMP/TMPDIR 全写独占 E 路径；真实 main/child user 探针通过。10条自有 root 执行记录（probe、import、8次场景）均 `exited=true / active_owned_processes=0 / log_handles_released=true / budget_failure=null`；不是声称全机器没有用户进程。未读取或终止用户 PID、未用28100或任何游戏网络端口。`generated_removed`，程序实查生成工程及 user 数据不存在，保留 manifest/日志/字节归档。

仓库唯一写入为上述两 GD、新独占 runner、本文；没有修改生产、旧执行器、gate、并行名单及 GUI/shutdown/round60 六测试。未 stage/commit。两 GD 可能在忽略的 tests 路径，交付以实际字节及 patch/hash 为准，不只看 git diff。程序经验追加到 default profile 的 `godot-public-test-consumer-migration` skill，不涉及其他 profile。

尚未验收：main 删除四许可后 gate 转绿；其余私有消费者；全98套、GUI/真人/跨机/导出。没有生产阻断或本轮专项失败；scope 只覆盖当前两测试四调用。
