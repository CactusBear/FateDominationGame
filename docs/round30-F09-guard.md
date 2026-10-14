# Round 30 — F09 主机 guard 管理消息闭包

## 交付与边界

实际迁出 `guard_continue / guard_skip / guard_restart / guard_lobby` 四种已有 kind；不新建 pause/resume/skip/retry 协议。`management_paused` 是原 Session 管理状态，不是新增请求。guard 暂停续行与正常 `match_finished_lobby` 仍为两个入口。

本轮生产代码只修改 `scripts/net/session/lobby_session.gd`，新增无状态 `scripts/net/session/host_guard_inbox.gd`；新增 `tests/host_guard_inbox_contract_test.gd/.tscn` 和本报告。authority/gateway/manager/UI/Room/EffectManager/房间及内容 inbox 均只读，未提交 Git。先读取 hermesWarning、技能、Round29 内容交付报告及当前源码，沿真实入口确认内容闭包已经接线。按父代理唯一文件拥有者约定工作，没有另启共享文件写入者；最终本轮四份文件与真实测试冻结字节一致。

程序化扫描当前 `_receive` switch：原剩20 kind，本轮迁4，现在剩16；库存不是历史方案推算。累计已迁出房间4、客户端内容3、guard4。F09 整项仍未完成。

| 剩余簇 | 实际 kind |
|---|---|
| 服务端内容管理4 | server_data_catalog, server_data_prepare, server_data_commit, server_data_cancel |
| 选人/对局7 | start, choose_master, begin_match, preview_group, match_command, broadcast_confirm_absent, match_finished_lobby |
| 身份/凭据5 | join, identity_candidates, identity_inherit, identity_ack, room_password |

## 修改前耦合审查与中文 V4A 详释

旧 Session 同时处理传输认证/长期状态与规则管理命令适配。更合适的边界是：只抽同步、无长期状态的 guard 请求适配，不把完整回滚、权限或大厅生命周期再造一份。未新增 operation；四种请求复用唯一 `MatchAuthority.continue_runtime_guard`，它继续调用原 EffectManager 续行、完整 skip、重开和结束会话原语。

1. `HostGuardInbox.handles` 是原四种 kind 的显式白名单；其他管理、播报、内容、身份 kind 不进入该职责。
2. `receive` 显式输入当前 phase、已认证稳定 actor、kind、args、原权威执行 Callable、原错误读取 Callable；输出 `{ok,reason}` 或 `{ok,lobby}`。模块无字段、不存 Session/authority/Callable、不 await，无反向 Session 强引用、总线或服务定位器。
3. Session 的生命周期门先于任何请求；LAN/RSA 来源 gate 后映射 connection→稳定 member；来源连接权限、协议类型、旧 seq、在线检查之后才消费 seq。以上顺序不变。
4. guard 接线保持管理暂停先拒绝、当前稳定 owner 再拒绝；模块只检查原 playing、args恰好1项、view_seq严格int条件，然后调用原权威原语。没有第二 owner/席位/认证规则，错误仍带原请求 seq。
5. 原 authority 继续唯一判断 issued view/revision、是否真实暂停及审计是否可用；skip 仍要求完整检查点、随机恢复和事务归属校验，预算失败不能降级为部分回滚；本轮没有修改这些规则。
6. 成功 guard_lobby 后，Session 仍负责原 Room 返回大厅、重建 selection/模板、清战局视图、向原成员发送 match_reset、最后发布房间。其他成功 guard 仍只发布实际对局；失败不伪发管理成功。
7. E07 本人播报确认/代断线整批授权代码和顺序、F08 身份、既有房间/内容抽取均未修改。项目 `threading/worker_pool/max_threads=20` 原值保留，未改生产 project.godot 或验证器配置。
8. 用中文说明后执行 V4A 锚定增删，未覆盖 Session 全篇或其他代理文件。

## 真实 RED/GREEN 与同冻结回归

真实 Godot v4.7.2；独占 E 根 `E:/Fate-F09-guard-r30-agent/`。复制真实主可执行文件到 E engine 并校验 SHA256（不是单独复制 console wrapper）。使用既有隔离运行器的 Windows Job Object，仅管理自有主/派生 PID，每进程180秒、无窗口。先以同 application 配置运行真实主/worker user 路径探针，读取 token 回执；新测试另断言真实 `user://` 解析到 E。

最终六套使用**完全相同的冻结文件 SHA256 映射**；Python 比较全部 source_files 清单相等。生产工程字节未因测试变异修改。冻结只复制显式 scripts/assets/data/addons 及追踪到的具体测试依赖，不复制历史整个 tests、旧 test、reports、scratch 或源 .godot。

实际命令形式（每次完整命令、PID、exit和日志已归档）：

```
E:/Fate-F09-guard-r30-agent/engine/Godot_v4.7.2-stable_win64.exe --headless --fixed-fps 60 --path E:/Fate-F09-guard-r30-agent/isolated-<uuid>/generated/project --scene res://tests/<name>.tscn
```

| 执行 | 实际结果 | 引擎 exit / 验收 |
|---|---|---|
| red-ready，迁移前 | 8 checks；独立模块不存在；父夹具阶段保护随之停止 | 1 / RED |
| mutant-dispatch，仅独占副本 | 把真实 kind 强换为 guard_continue；47 checks，6项失败，包括预算闭锁、资源/随机恢复及成功审计 | 1 / RED |
| 恢复副本 green-restored | 70 checks，空失败 | 0 / GREEN |
| 最终 host_guard_inbox_contract | **72 checks，空失败** | 0 / PASS |
| net_runtime_guard | 34 checks，空失败 | 0 / PASS |
| broadcast_absent_confirmation（E07） | 56 checks，空失败 | 0 / PASS |
| client_identity_inbox_contract（F08） | 58 checks，空失败 | 0 / PASS |
| host_room_inbox_contract | 34 checks，空失败 | 0 / PASS |
| host_content_inbox_contract | 55 checks，空失败 | 0 / PASS |

最终成功六套共 **309 checks**；均无 SCRIPT ERROR/ERROR/失败CHECK，主/worker/import/scene自有进程正常退出，Job ActiveProcesses=0、日志句柄释放、无预算超限。`git diff --check -- scripts/net/session/lobby_session.gd scripts/net/session/host_guard_inbox.gd` exit=0。

新专项继承真实 net_guard_rollback 规则夹具，观察 Node 不进入完整规则对象图，覆盖：合法 RSA/ENet绑定；真实错误 RSA 签名不能绑定稳定成员，其 guard 请求来源门拒绝且不消费seq；非owner；真实ENet旧seq优先拒绝；管理暂停不能退出；畸形参数及所有生命周期门；完整 ready checkpoint 随机恢复校验失败仍保留暂停和已变资源、不写成功审计；真实采集预算失败导致skip闭锁；正常skip恢复资源/随机及父子双方事务、清旧待答；批准阵容缺失重开失败保留原局，恢复模板后重开；旧视图及正常对局不能冒用guard_lobby；暂停后返回大厅保留成员/批准数据/连接并清旧对局；重新准备、选人和正式开局；协程返回后deferred WeakRef确认无Session环。net_runtime_guard另真实覆盖新owner续行、旧视图拒绝、没有完整检查点拒绝skip、时间预算暂停、移除成员拒绝、客机退出保留主机暂停、主机退出清续行引用。

## 问题与未伪报的边界

- 首次冻结 import 因项目启用但缺失 GitPlugin 扩展报错。只在独占测试 staging 的 project.godot 将**编辑器** `version_control/autoload_on_startup` 改false；application/thread20/生产project完全不改。保留首次失败日志。
- 运行器初次不接受具名旧RESULT，虽真实67 checks全绿，验收仍false；本轮新测试改为单条结构化JSON RESULT，未改共享运行器。
- 额外最终跑 F06 client_match_inbox_contract：引擎exit=0，原34/最终45两条RESULT均failures=0、无错误，但违反隔离运行器“唯一RESULT、failures数组”契约，运行器exit=1、`expected_one_stdout_result`；**不计入成功六套**。该测试非本轮拥有，未篡改输出或共享测试，保留交接。
- 本轮是同进程真实RSA/ENet、无窗口验收；不是主管/worker IPC、跨网、GUI、崩溃恢复或发行包整链，不以静态保留或旧报告冒充本轮重跑。

## 归档、回收及摘要

完整命令/主派生PID/退出码/探针真实user路径/日志/冻结manifest：`E:/Fate-F09-guard-r30-agent/isolated-*/`；聚合 `reports/summary.json`、`reports/freeze-sha256.json`、四份源码副本 `reports/sources/`；执行/聚合/回收脚本同根保留。

隔离运行器逐次回收自有generated树；最终扫描自有staging/engine及祖先/内部无reparse/link后回收二者，读回确认不存在、所有generated不存在、证据保留。未终止其他PID、未修改全局TEMP、未触碰正式用户存档，不向用户询问回收。

最终本轮文件SHA256（程序化读回及与冻结比对）：

- lobby_session.gd：`b1cb85fd7bbb1fb0f89f30388756e4e5deebdac735478f34cfcba2111231c76f`
- host_guard_inbox.gd：`e2042626210bd12dbedd63ddf6369216a741791696a68465d89b7391ae480832`
- host_guard_inbox_contract_test.gd：`84957adbe05b3be9206ca81747678252b6e98e9069ced00063604210e38f2b05`
- host_guard_inbox_contract_test.tscn：`8f1fabaeb0ad9b7123329a803a32602f9bd970e511c15ec2cec7f891a2e837bc`

`tests/` 被项目gitignore忽略，两个新测试已落盘且真实运行，未擅自git add；主代理纳入交付时需显式处理。请求收件闭包技能追加guard单权限边界、完整失败保留及结构化RESULT教训。
