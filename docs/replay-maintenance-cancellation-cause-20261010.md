# 「维护回调取消了存档操作」窄因果定位

## 结论

- 两路 `match_replay_test` 的六条失败由**测试夹具自行到期取消恢复**造成，不是资源回收器把在飞存档误判为孤儿。该路径传入的维护回调是 `tests/match_replay_diagnostic_fixture.gd::maintain`，唯一返回条件为 `Time.get_ticks_msec() < deadline`。
- 截止时间在测试 `_ready` 时设为当前 ticks + 170000；录制整局、第一次恢复、第二次恢复共用它。录制不传回调，恢复才传，所以耗时录制仍成功，恢复碰到余额耗尽即红；第二次恢复复用已过期 deadline，必然立即红。
- **归类仅限本报告的 match_replay 六条 CHECK：夹具正确性验收预算/契约问题；生产取消分支符合设计。** 未把 F01–F09 其他 RED、房间此前退出、管理 save/close 回执缺陷归为同因。原先 170 秒性能门本轮依然未通过，不得靠改预算宣称性能改善。
- 失败发生在 `restore`，不是 `save_restored_as` 或文件保存提交；文案泛称“存档操作”容易误导。原测试没有调用另存或管理保存。

## 直接源码证据与调用链

仓库相对路径，以下行号已由 read_file 实读：

| 文件:行 | 直接事实 |
|---|---|
| `tests/match_replay_test.gd:13–15` | `_ready` 唯一设置 `Diagnostic.deadline = Time.get_ticks_msec() + 170000`。不是绝对 ticks=170000，启动时间也要计入。 |
| `tests/match_replay_test.gd:55,61–76` | `begin(folder,[0,1,2],8181)` 不传 maintenance；录制循环只调用 perform/pulse，没有诊断截止判定。 |
| `tests/match_replay_test.gd:81,84–90` | 正常关闭录制、读记录，循环两次 `await replay.restore(folder, diagnostic.maintain)`，无 deadline 重置。 |
| `tests/match_replay_diagnostic_fixture.gd:14–18` | maintain 仅在 index 变化时 trace，随后 `return Time.get_ticks_msec() < deadline`；不检查房间、所有权、代际、孤儿资源。 |
| `scripts/match/match_replay.gd:237–243,71–72` | 公共 restore 将回调绑定为 `_checkpoint.bind(maintenance)` 后传给 `_restore`。 |
| `scripts/match/match_replay.gd:299–334` | 每条记录执行、比较 after hash、检查已有 error 后调用 `_tick(maintenance)`；因此首红并非已出现 hash 校验错误后被覆盖。 |
| `scripts/match/match_replay.gd:632–638` | `_tick` 先拒绝审计/既有 error，然后调用维护；返回 false 则中止。若 wrapper 已设置 error，不覆盖它。 |
| `scripts/match/match_replay.gd:40–68` | `_checkpoint` 快照随机与审计，再 `accepted = maintenance.call()`；审计变化优先报「维护回调修改了事务审计，拒绝继续恢复」，否则 **accepted 是 bool 且 false** 才报本次文案。 |
| `scripts/match/match_replay.gd:251–259,676–678` | 第二次恢复清旧 error 后最先 `_file_hash(match.log, maintenance)`，其第一句先 `_tick`，到期可在读文件之前失败。 |
| `scripts/match/match_replay.gd:499–517` | 测试显式 close 正常结束 journal/audit 所有者并递增 recording_serial；restore 自身也调用 `_close_unchecked`。维护回调根本不读取该 serial，不以释放 writer 判取消。 |
| `tests/match_replay_profile_fixture.gd:12–22` | ProfiledReplay 只包装 state_hash/_execute 计时，不替换 restore、maintenance 或规则。 |

首轮失败的静态可达调用栈：

```text
tests/match_replay_test.gd:87 run
 -> MatchReplay.restore:243
 -> MatchReplay._restore:334（逐记录尾部）
 -> MatchReplay._tick:635
 -> MatchReplay._checkpoint:55（71–72 绑定）
 -> Diagnostic.maintain:18
 -> now >= deadline => false
 <- _checkpoint:67–68 设置精确文案
 <- _tick:635–637 false
 <- _restore false -> test:88–90 三条失败
```

第二轮：`run:87 -> restore:243 -> _restore:257 -> _file_hash:677 -> _tick -> _checkpoint -> maintain`，复用同一过期 deadline，setup/index=-1 即取消。

## 原始运行证据（本轮读取，不重跑完整对局）

### A：F01–F09

根：`E:/scratch/f01-f09-headless-reverify-20261010-b72e6c/isolated-012eafed6e8f4a18b3f1e075bd079511/`

- `manifest.json:9–25`：真实 Godot argv、exit=1、duration_seconds=176.692、budget_failure=null；`:42–45` 外部 watchdog=600；`:60–62` exit=1、Job0=true、generated_removed。
- `evidence/match_replay_test.stdout.log:11–15`：录制无错误、自然终局成功、142 条记录；录制 state_hash 累计 140.945189 秒（284 次，日志给 usec，本轮 Python 换算）。这不是本轮测速，亦不能单凭该统计归因具体性能回退。
- 同日志 `:16`：首次恢复 setup 时 ms=153754，保留录制终局 round=11/game_over=true。
- `:17–37`：真实恢复持续推进到 index=21/ai_turn；末条 ms=175925、round=2、player=1、game_over=false、error=""、running=false、waiting=false、tree_paused=false、broadcast=false、consumer=false。
- `:38–40`：第一次恢复三条失败；`:41` 第二次 index=-1、ms=175935，同一 replay 实例；`:42–44` 立即同文案三条失败；`:47` RESULT checks=10、六条 failures。

### B：独立 E05–E07d retry

根：`E:/scratch/broadcast-headless-5bc5e8ea2bbf47108d5a6ebae227403f/isolated-90288b7dd03a4785aa54679de91dccbf/`

- manifest 的 match_replay-1 真实进程 exit=1、duration_seconds=176.103、budget_failure=null；suite status=FAIL；Job0=true；source_drift=[]、frozen_drift=[]。
- `evidence/match_replay-1.stdout.log:11–15`：同样录制自然终局成功、142 记录；录制 state_hash 累计151.835606秒（284次）。
- `:16` setup ms=165379；`:17–25` 正常恢复推进 index=1 到9，末条 ms=174948、round=1、player=0、game_over=false、error=""、running=false、waiting=false、tree_paused=false、broadcast=false、consumer=false。
- `:26–28` 首轮三条失败；`:29` 第二轮 index=-1、ms=174956；`:30–32` 第二轮立即三条失败；`:35` 同样 RESULT checks=10、六 failures。
- `run_replay_retry.py:36,118` 明确外部600秒、内部170秒未改；`:93–103` 非 timeout 的失败不再循环重试。

两路在失败前都仍逐条推进；首轮恢复位置不同但都在测试启动后约170秒耗尽，第二轮都立即失败，与共享绝对 deadline 的预测一致。

### 同一源码绑定

本轮 Python 真实计算并逐一对照 A `source-before.json.files`、B `manifest.source_hashes`，四个相关文件 current/A/B 的 SHA256 全等：

```text
scripts/match/match_replay.gd            851f77f939974d3f51eea51b70feda9c2593c0ee700e265bb4e090b78419d175
tests/match_replay_test.gd              c65919215e6ab6cba7d65b0689c59a776278949e6056eab4ffc800a8c9615253
tests/match_replay_diagnostic_fixture.gd 4a3002be03822511ae9ab63a8435e1b3e8abca344ed59c80a3ec9dd4ee49c569
tests/match_replay_profile_fixture.gd    fe9eebeb5ba2f2c76b5899f0cb2136d98502a58b4e0a3faa5698df4dbc0a78e3
```

## 真实小探针：机制与栈，不冒充完整恢复验收

命令（cwd=仓库）：

```text
python -B newtests/run_replay_maintenance_cause_probe.py
```

最终 exit=0。manifest：`E:/scratch/isolated-ca13e1c56e50451ea7f528a106a5ed96/manifest.json`。

runner 从原文件提取未修改函数正文 `_confirm_audit/_checkpoint/_maintenance_callback/_tick/_file_hash` 与 `Diagnostic.maintain`，记录源码 hash、切片行号与 hash。Journal/RuleRandom 原文件整份复制；EffectManager 只留不应触发的审计失败标记替身；只替换诊断 trace 为安全 deadline/调用栈输出，不加载对局/房间/规则图。

实际业务命令（manifest:162–170）：

```text
E:/scratch/isolated-ca13e1c56e50451ea7f528a106a5ed96/generated/Godot.exe --headless --fixed-fps 60 --path E:/scratch/isolated-ca13e1c56e50451ea7f528a106a5ed96/generated/project --script res://newtests/replay_maintenance_cause_probe.gd
```

- 用户目录主/子进程预检 exit=0；最小导入 exit=0；cause exit=0；外部watchdog=600；Job0=true；source_unchanged=true；generated_removed。PID17120/28100未操作。运行材料全部物理E盘；只读取D盘引擎源并复制到E执行。
- `evidence/cause.stdout.log:7`：真实 get_stack 为 `_initialize -> _file_hash -> _tick -> _checkpoint -> maintain -> trace`，ms=246、deadline=245、expired=true。
- `:8–10`：到期中止、精确文案、审计revision/identity未变化均为 true。
- `:11–14`：复用过期deadline立即取消；去掉回调则相同文件可哈希；更新deadline后相同真实seam可成功，均为 true。
- `:15–16`：注入审计代际变化时拒绝，但文案为另一条「修改了事务审计」，排除将两条错误混为一谈。
- `:17`：`RESULT checks=10 failures=[]`；stderr 空。

早期自有runner错误亦保留：
1. `isolated-a031f54aee3f49e8aaab9a3f1215dea4/manifest.json`：exit1，启动Godot前误将只读D盘源要求为E；已修为复制到E后检查/执行。该次无进程启动，generated保守保留。
2. `isolated-3965b3451a014546972ac93436fc3682/manifest.json`：exit1，最小diagnostic代码空格/tab混合导致preload解析失败；仅修自有runner字符串缩进。Job0=true、generated_removed，错误日志原样保留；此轮不是产品复现证据。

其他实读命令：`git status --short`、`git diff --numstat -- scripts/match/match_replay.gd tests/match_replay_test.gd tests/match_replay_diagnostic_fixture.gd tests/match_replay_profile_fixture.gd`、`git log -3 --oneline -- scripts/match/match_replay.gd tests/match_replay_test.gd tests/match_replay_diagnostic_fixture.gd`、`git diff -- scripts/match/match_replay.gd`，全部exit0。已有生产diff只改公开接口、播报政策/成功后换batch，不改本次取消条件；不能据此证明其他依赖没性能变化。

## 房间退出、代际、所有权：已证实与未观测必须分开

- 该测试没有建立 LobbySession、room manager、authority host 或 worker；diagnostic维护回调中没有任何资源回收代码。因此不能从同批其他套件的「房间此前退出」推成本测试首因。
- 正常 `replay.close()`/restore入口会释放journal/audit句柄并递增recording_serial，这是已证实的设计行为，不是回收误判；maintenance不检查它。原始日志没有逐个serial/所有权运行时字段，本报告不伪称捕获其数值。
- `_start` 会 `GameStart.end_session()` 并重建规则 driver（match_replay:150–157），这是恢复规则起点的设计，不是维护回调检查“会话退出”。日志录制driver与恢复driver不同、同一恢复中driver稳定，与该设计一致。
- 原始失败日志没有 deadline 数字、accepted值或当次get_stack；精确截止值与首拒绝栈由相同源码和唯一返回条件推导，并由小探针真实验证机制，**不是原始生产运行的动态栈**。trace在return前执行，毫秒边界内可能略有差值，不能把trace.ms冒充精确return ticks。

## 非 replay 路径为什么未受影响；产品回调的另一路

1. 本测试录制begin没传maintenance，perform/pulse也不走diagnostic.maintain，所以170秒余额耗尽不会由该回调取消录制。同步AI/哈希段无process_frame时，Node `_process` watchdog也无机会抢占。原始日志没有“complete replay exceeded 170-second test deadline” CHECK；这不是外部600秒超时。
2. 恢复路径每条记录都主动 `_tick`，纯同步也会查deadline，所以可以在整个 run 返回帧之前被取消；下一轮继续同一过期值立即取消。
3. 不宜泛化为“所有非replay都安全”：生产 `MatchAuthority.start` 录制分支同样把maintenance传入 `candidate.begin`（`scripts/net/authority/match_authority.gd:98–104`）；调用者可按自己的条件正常取消。
4. 生产恢复另一条链为 `LobbySession:1897,1902 -> MatchAuthority.restore_archive:552,556,560 -> MatchReplay.restore/save_restored_as/resume_recording`。这里实际回调是 `_restore_checkpoint.bind(original_room,original_snapshot)`，不是诊断deadline。
5. `scripts/net/session/lobby_session.gd:1995–2008` 要求维护前后相同room对象、host及房间snapshot；`1978–1993` 要求host、restore_in_progress、非failed_closed、非cancelled、底层连接仍在。真实close/断连/房间变更会按设计取消；本报告**没有运行或证明该生产路径历史RED是否误判**，也未检查孤儿回收策略是否有独立缺陷。

## 交 main 的最小修法候选（本轮不修改生产/原测试）

**优先：只修正确性夹具的看门狗合同，保持产品取消保护不动。**

- 将 `tests/match_replay_test.gd:14` 的170000改为显式runner传入、经整数验证且>=600000的正确性预算，并同步`:20`超时断言文案；外部runner预算需覆盖该内预算及启动/归档开销。禁止悄悄延长产品规则预算。这里“>=600000”是本任务明确的看门狗要求，不是新增产品业务期限。
- 可选按阶段重新分配显式预算，但必须同时覆盖Node `_process` watchdog与Diagnostic.maintain；只重置某一处或只提高外部600秒无效。仅在每次restore前再给170秒也可能仍不足，不能作为已验证修复。
- 保留种子8181、完整自然终局录制、两次恢复、原状态hash与终局全部10条断言；一次完整正确性验证后才能宣称该专项PASS。原170秒门另列未通过；不要通过取消callback、吞false、修改生产取消判据或降低恢复次数“转绿”。
- 可增加安全的首次拒绝诊断（now/deadline/index/phase；不序列化存档或身份），先保留本报告精确过期反例，确保恢复生命周期的合法取消仍拒绝。
- 如果另有性能修复授权，再单独定位RuleState.capture/net_ids/对象图成本；当前日志只证明state_hash累计占时，不足以判定是哪次产品重构导致。此次不测速、不提未经证实的性能补丁。

## 未证实/验收边界

- 未在修改夹具预算后跑完整141动作/两次恢复，不能宣称完整正确性或产品性能已通过；原始六RED保持原状。
- 未证明同批其余6个RED套件的因果；尤其「房间此前退出」与所有权释放断言、F12 `_drain_close` 缺保存成功判据应独立处理。
- 未动态捕获原始首拒绝的deadline数值、完整栈、房间/recording_serial/所有权字段；路径判定已由相同源码唯一predicate和隔离机制实跑支持，但不把未记录字段写成实测。
- 小探针是源正文seam机制验收，非完整MatchReplay场景、LAN、管理保存、发行包或窗口验收。

## 本次写入范围

仅新增：
- `newtests/replay_maintenance_cause_probe.gd`
- `newtests/run_replay_maintenance_cause_probe.py`
- 本报告。

未修改生产GD、原tests、配置或其他代理文件。复用既有Job隔离执行器；证据仅写本次独占E:/scratch/isolated-*。