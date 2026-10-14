# Round27 — 真实活局恢复投影与独立 worker 播报

## 结论

- **恢复投影已定位并修复比较契约，不是通知 epoch/batch 引发原失败，也未发现规则投影或本人身份改变。** 当前树原始重跑 `before-restore` exit 1 / 147.25 秒 / 58 checks；48 个差异全部是 `players/*/zone_hand_entries/*/card` 下的 card/effect NetIds 和 image/back_image 路径。正式 ViewBuilder 对这个入口调用同一 `card_view`，旧 helper 的显式路径表没有它。其余逐字段比较已通过。
- 在拥有的 LAN 测试内扩展原比较器路径，不修改共享 helper。最终实际原局/恢复局共用 60 项 ID 双射、53 项资产路径内容映射，errors=[]；observer 0→0、1→1。新增 rule/observer/privacy/asset/reference/barrier 六类真实镜像变异全部被拒绝。未删除原规则、hash、席位、隐私、ACK 屏障或终局断言。
- **true 第二批失败已真实复现并定位到测试错误分类。** 最初生产树 true 53 checks / exit 0；重复 `final-true` 41 checks / exit 1 / 66.41 秒：客机 `error=视图已过期`，`drive_until` 通过 `has_error` 将可重试业务版本拒绝误判为链路故障。Session 的正式 match_command 路径拒绝后仍发布实际状态，不必修改生产错误提示契约或放宽 authority 版本校验。
- 最终 `verified-stale-true` **56 checks / exit 0 / 78.75 秒**。真实 RSA/ENet/独立 worker 两批均通过；第二批还故意发送过期 view_seq，收到真实拒绝且没有确认本人/解除屏障，随后合法离线代确认与房主本人确认成功。实际记录一条过期拒绝。旧 true 实例正常保存关闭、release、新 manager 恢复成另一 worker，并验证当前默认 false 不继承旧 true 权限。
- **完整恢复终局验收仍红：180 秒外部硬上限，没有放宽。** `retry-fixed-restore` 投影/六反例/两席身份/管理员暂停不继承均通过；随后 round2/action 的 seq 41/42 与 decisions 5/8 持续不变，完整续行至终局没有完成。尚未取得足以修生产根因的证据，不能把它称为仅性能问题或完整恢复通过。

## 耦合与修改边界

1. `LiveEquivalent` 仅覆写原 helper 的明确引用/资产分类：zone card/id→card，zone card/effects/*→effect，zone card/image/back_image→实际资产哈希；数组顺序、重复引用、双向映射、类型及其余字段全部交给原递归比较。
2. 原 position 的所有字段保留，并新增播报规则资格 pending/confirmers/confirmed 严格比较；batch_id 单独存输送证据，不把整个播报对象删除。原失败投影根本未包含 notifications 或 batch_id，因此不能将 48 项差异归给它们。最终通知载荷/ID 确有生命周期变化，完整保存在 comparison.json 的 transport_before/after，不能据此推导规则变化。
3. 只处理正请求序号且原因**完全等于**“视图已过期”的真实 request_rejected，留存请求/观察席/视图序号证据，清掉已处理的提示；不安装镜像、不伪造动作结果、不修改 authority/组选择。其他错误仍失败。回调绑定 WeakRef，避免 Session 自引用环。
4. 同一次测试内每个客户端分别保留自己的正式内容寻址缓存；恢复仍调用 fetch、assemble、install 和 revision ACK，首次 ENet 下载保留。没有缓存 RuleState/snapshot，没有减少规则检查。
5. 修改仅 `tests/lan_restore_live_test.gd`、`tests/broadcast_spawn_capability_test.gd`。Session/authority 前后 SHA-256 一致；manager/hostclient/CLI/UI/引擎及共享 helper 均未改。本报告新增，无提交。

## 执行与证据

物理独占根：`E:/Caches/Hermes/cache/scratch/round27-restore-broadcast/`。
运行器 `run.py` 每次用新目录，拒绝覆盖；独占 APPDATA/FATE_TEST_SCRATCH_ROOT，场景新 live 根，真实 RSA/ENet、原生 worker 所有权，全程无窗口。

```text
python E:/Caches/Hermes/cache/scratch/round27-restore-broadcast/run.py <独占标签> <测试名>
D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe
  --headless --fixed-fps 60 --path E:/Projects/Godot/FateDominationGame-master
  --scene res://tests/<测试名>.tscn
```

每次 `stdout.log`、`result.json`、`source-hashes.json` 均独立保留。旧 round25 日志没有写入/覆盖。

| 标签 | 真实结果 |
|---|---|
| before-restore | exit 1，147.25s；原投影 RED，58 checks |
| before-true | exit 0，85.10s；生产树 true 两批及默认恢复通过，53 checks |
| after-restore | TIMEOUT180；投影与六反例已绿，终局未到 |
| after-true | exit 0，108.37s；加入 batch 换代断言后54 checks |
| cached-restore | exit 1，52.78s；真实资产组装写入校验失败；当时 E 盘只剩26,558,464字节 |
| cached-restore-2 | TIMEOUT180；投影绿，续行推进到round4；完整终局未到 |
| final-true | exit 1，66.41s；复现第二批前客机“视图已过期”被当致命错误 |
| retry-fixed-true | exit 0，84.79s；54 checks，窄化业务拒绝处理后通过 |
| retry-fixed-restore | TIMEOUT180；投影绿，续行round2/action停滞；终局未验收 |
| verified-stale-true | exit 0，78.75s；56 checks；故意过期请求反例与两批确认实际通过 |

Godot 原 Journal 读取器另行审计真实落盘文件，未用 Python 替代规则或 journal 行为：

```text
Godot --headless --path <项目> --script <独占根>/audit_journals.gd -- <某次>/live
```

- cached-restore-2：原档21条、新恢复续写档74条，二者 ok=true / truncated=false；新档确实新增规则日志，不以 decisions 尝试计数代替。
- retry-fixed-restore：原档19条、新档33条，同样完整且未截断。各自完整 SHA-256/尾规则hash位于 `live/journal-audit.json`。
- 这些只能证明恢复后真实续写，**不能替代终局管理 save 回执及其尾hash对照**；原终局断言仍在且尚未执行完成。
- 超时均只 kill 本次父 PID；随后按本次 ready.json PID 精确 CIM 查询，31052、38184、31680 均 verified-absent，未按进程名批杀。证据分别在对应 `owned-cleanup.json`。
- E盘写入失败后仅释放本代理已结束运行的 cache/client 目录，逐文件大小和 SHA-256 保存在 `released-owned-artifacts.json`；日志、comparison、worker原档/新档和 hash 证据保留，未删除他人数据。后续可用空间恢复，不能将那次 I/O 红当规则错误。
- 最终 true 无 SCRIPT ERROR/ERROR/泄漏报告。`git diff --check -- tests/lan_restore_live_test.gd tests/broadcast_spawn_capability_test.gd` exit 0。

## 未完成项

恢复整套必须继续定位 round2/action 的驱动停滞，并在同一180秒上限内完成终局、最终正式 save 回执及续写尾hash对照；本轮没有擅改不拥有的 Agent/group/engine，也不以减少回合、取消隐私检查或跳过终局伪过。没有窗口、真人、多机或跨网验收。
