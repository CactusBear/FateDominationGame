# close/save 后续失败根因与级联审计

## 结论与证据等级

本轮仅只读审计生产/测试源码及既有 batch-11 交接，禁止且未运行 Godot；Python 静态断言实际执行通过。仓库检索未找到本轮 close/save 的原始失败日志，不能把下述候选时序问题宣称为已复现生产回归。

- **静态确认的测试根因**：`net_room_control_instance_test` 仍发三字段请求，而生产要求五字段；`net_server_shutdown_failure_test` 房间登记缺 `instance_id/authority_host_mode`。它们导致的拒绝、缺回执、后续属性访问错误不能算独立生产故障。
- **close 失败后的级联**：拿到失败/空回执后仍检查 PID 退出和最终 saved；安全实现本来就拒绝在未保存时退出，因此至少“子进程未退出”不是第二个独立根因。
- **真实 save/close 时序候选**：两套件停止继续 `agent.act()` 后提交管理命令，但仍推进真实 SceneTree；客户端中局快照不是权威录制安全边界的证明。不过生产已在归档 pulse/恢复期间推迟消费，并在保存时检查状态哈希；不能看到失败就直接归为“测试太快”，需看实际 error。
- **正常回执生产顺序静态正确**：先保存、原子写 response 成功、删 request、最后发退出信号；消费者在 request 已删除后仍读 response；关服只有 closing 回执和 PID 消失同时成立才完成。
- **独立生产风险**：已有 response 分支未校验归属就删除 request；提交端读取 ready 未将 instance/mode 与 manager 登记严格交叉绑定；这些是静态缺口，不是现有 close/save 失败的已确认原因。

## 一、先划清实际执行链

`net_server_match_test.gd:23-32` 建房/首次入房失败打印 `SERVER_JOIN_FAILURE`，随后 cleanup/finish/return。此时 `:65` 的 `_after_baseline()` 未进入。该失败应记为共享建房/ready/attach 前置失败，save/close **未执行**，不是保存条件或回执失败。batch-11/save-test.md 只有该层面的旧证据，不能用它解释尚无日志的后续红。

继承关系：close → save → midmatch → recovery-match → archive-match → match。

- save 重写 `_after_baseline()`，完成自身 save/seed 检查后 `super._after_baseline()`（save:27）才开始父类崩溃恢复和继续至终局。
- close 重写 `_after_baseline()`，**不调用 super**，不会先运行 save 专项断言，也不会自动执行父类恢复步骤；它只复用保存测试的等待 helper 和继承的录制开关/中局目标。
- 因此 close 最终回执失败不是“save 套件先失败后传下来”；应在 close 自己的提交、消费、保存和退出链找最早事件。

## 二、已确认的旧夹具契约问题

### 1. room control 实例专项

`server_room_control.gd:35` 只接受五字段：`room/pid/instance/authority_host_mode/action`，且须匹配当前实例。

`net_room_control_instance_test.gd:18,28,39` 所有请求只写 `pid/instance/action`。即便所谓新实例 seed、未录制 close 或 pulse 等待请求，都会走通用无效请求 response，而不会执行目标动作。

因果链：

1. 三字段夹具 → 通用失败 response（根因）。
2. 新实例 seed 成功断言失败；若求值到 `valid.result.seed`，还可能触发缺键脚本错误（级联）。
3. 未录制 close 的 error 不包含“未启用录制”（级联，尚未进入 save）。
4. pulse 正在运行仍返回失败并删 request，因为 pulse 延迟检查在五字段验证**内部**；“应保持待处理”断言失败（级联）。

旧实例拒绝断言可能碰巧绿，但拒绝原因并未真正证明 PID 相同/instance 不同隔离。最小夹具修正是显式设置 control.room_id/mode，并给每条请求补对应五字段，其他测试口径不放宽。

### 2. shutdown 失败专项

`net_server_shutdown_failure_test.gd:16` 登记不含 `instance_id/authority_host_mode`，`:22` ready 也只有 id/pid/instance。

初次 ready=false 拒绝仍可能按预期绿；第二次 ready=true 成功提交后，`server_shutdown.gd:32` 无条件读取 `room.instance_id` 和 `room.authority_host_mode`。缺键可使 start 中断，根本没完成新的 request/deadline/stage 更新；随后“无回执超时”断言就是级联，不能证明生产 timeout 错误。应先补完整 manager room binding 与 ready 契约再验超时，不改生产为容忍缺字段。

## 三、保存条件与时序分账

`server_room_worker.gd:218-221` 每帧先 session.poll，再 control.poll。
`server_room_control.gd:36`：restoring 或 `_archive_pulse_running` 时 request 留盘，不产生回执。
`match_authority.gd:450-458`：pulse_running 包围 `await recorder.pulse()`；`match_replay.gd:133-149` 两个真实帧续行后追加 frames 记录并更新 `_last_hash`。

`save()` 的拒绝分支（control:80-88）必须分别归类：

| 首个可观测结果 | 根因归类 | 后续预期 |
|---|---|---|
| 提交 `ok=false`，未就绪/ready 不可读/实例不匹配 | 前置 ready/实例或夹具问题 | 无 room request，不能等保存 |
| request 留盘，无 response，phase=restoring 或 pulse_running | 暂时不在可消费边界；10 秒测试预算可能不足 | 不是已确认保存失败，不得强杀 |
| 未启用录制 | recorder 缺失/对局未 started | close 拒绝退出是正确行为 |
| recorder.error 非空 | 前置录制已经失败 | save 和 close 都是后果，应追首条 recorder 错误 |
| “存在尚未记入存档的状态，未保存” | 权威当前哈希不等于最后可信日志 | 保护有效；需查未录制修改或边界遗漏，不能仅延长等待掩盖 |
| 日志 flush / recovery 写入失败 | 真实存储失败 | close 不退出；已有目录存在不等于本次保存成功 |
| response 无效/进程实例不匹配 | 回执或实例绑定问题 | 区分有效保存响应被消费者拒绝与 worker 本身拒绝 |
| response 已确认 closing 但 PID 超预算仍活着 | 退出路径独立问题 | 才应调查 shutdown 信号/进程退出，而非存档 |

save helper（save:29-35）只 pump，不继续 agent.act；不会靠 helper 不断产生新玩家动作。但进入 `_after_baseline` 前仍可能有已送出的网络请求、引擎异步续行。close 在提交前还等第二房间最多 30 秒（close:9-15），原房间仍被 pump；这会改变权威状态，不会主动重新提交玩家动作。两者都没有捕获 worker 当时 pulse/error/hash，因此“停止客户端 act = 可保存”只是未证明假设。

**建议最小可证伪验收**：同一 room/PID/instance 下记录 request/action、consume 时 phase/pulse、recorder.error/current hash/last hash、flush/recovery 结果、response 落盘结果及退出时间；只改一个边界条件比较。如果加等待后仍 hash mismatch，就是记录覆盖问题而非单纯测试速度。暂停并不自动补记已有脏状态，不应作为绕过保存保护的修复。

## 四、close/save 后续断言哪些是级联

### close

close:20 保存/closing 检查失败后没有 return。

- `:23` PID 未退出：若前一步是保存拒绝或无回执，就是安全设计的后果，不另报生产退出 bug。
- `:24` recovery/matches 存在：只能证明旧产物保留，不能反证本次已保存。
- `:30` saved 回执读取失败：若读取的是同一失败 response，属于重复症状；若已经有合法成功回执而之后读取失败，才是独立回执保留/绑定缺陷。
- `:25-28` 网关/另一房间在线检查与目标保存是否成功并非同一个因果条件；它们若红应保留独立诊断，不能全数归为级联。

### save

save:14 回执失败，:15 直接打印 `ROOM_SAVE_ERROR` 并 return；不会执行日志哈希、seed 或父类恢复断言，因此正常失败 response 不会在这一方法内产生一串存档/恢复红。

若 helper 超时返回 `{}`，同样 return，但目前没有打印 request 是否仍存、room phase、PID、worker error；这只是测试预算耗尽，不能说生产回执已丢。

成功 response 之后，save:19 不先确认 directories 非空就用 directories[0]。目录缺失会成为脚本异常而不是精确断言；archive 父类早先检查过 size==1，但 check 不会阻断继续执行（match:107 后仍继续）。若最早“达到中局目标”或“独立存档目录”已红，应把后续目录索引/哈希失败标为前置失败的级联。成功 response + 本应存在的日志确实缺失则是保存承诺/目录选择的独立问题。

save:27 父类恢复阶段失败不必然由 save 导致：先用保存时可信日志与崩溃前期望位置证明链条，再分恢复身份、数据屏障和重放错误，不能只按测试名称算保存故障。

## 五、生产回执路径及独立缺口

1. control:48-52 的顺序正确：response 原子写成功才删 request 并 emit shutdown；写失败保留 request、不会 close。write_json（channel:131-140）经 tmp 写入/flush/check/rename。
2. channel:275-289 先读取 response，request 不存在仍可返回；所以“删除 request 导致无法读 close 最终回执”不符合当前正常实现。
3. shutdown:45-53 验证最终 response，closing 后仍等 PID 消失；失败 response 进入 failures，不强杀；pending 超时也保留进程（:54-60）。
4. control:24-26 遇到已有 response 未验 request_id/room/pid/instance/mode 就删 request，是可独立注入验证的生产风险；正常随机 ID 碰撞不是已有证据。
5. channel:253-255 ready 校验 id/pid/instance 格式，但未在提交时比较 ready.instance 与 room.instance_id，也未比较 ready 的 mode。若 ready 与 manager 不一致，会提交后被 worker/结果读取拒绝；应给出同一轮字段证据再归因。batch-11 close 报告中“提交端校验完整 instance/mode 绑定”的表述比当前源码更强，不能照搬。
6. control:49 忽略 remove 返回值；response 成功但 request 删除失败后仍可退出，result 可读但 forget（channel:294）拒绝清理。属于回执清理独立风险，不会解释 saved=false。

## 交付与边界

- 创建文件：`scratch/net-batch-12/control-cascade.md`；未修改生产代码或测试。
- 实际执行：Python 对继承 super 缺失、五字段门槛/三字段旧夹具、helper 无 act、close 失败不短路、response-before-shutdown、shutdown 夹具缺字段等静态事实断言，全部通过。
- 未执行：Godot、动态 close/save/recovery/stop 专项，任何 Godot 解析或多进程复现。
- 未拿到本轮 close/save 原始日志，最终动态根因仍需主代理按上述第一失败事件和同实例证据对账；本报告明确区分已静态确认、生产风险与待复现候选，不宣称运行验收通过。
