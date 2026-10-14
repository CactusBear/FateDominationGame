# Round71 — F09 host match 请求小闭包（已接真实 Session）

## 结果与边界

- 迁出真实 `match_command` 分支的输入形状校验、一次权威提交、发布前结果捕获；新组件 `scripts/net/session/host_match_request_inbox.gd`，真实 caller 已在 `lobby_session.gd:_receive` 接线。不是仅 component-green，也不宣称整个 F09 完成。
- 组件只接收 `kind:String`、`args:Dictionary`、`submit:Callable`、`read_reason:Callable`；无字段、无 Session/Room/全局规则引用、不保存能力、不接 service locator。提交闭包只捕获局部 authority 对象和已认证稳定成员值。
- 单个结果固定为 `{ok, reason, dispatched}`。`dispatched` 表示是否确实调用过唯一 authority.submit，不是新增兼容语义。组件不发布、不发送回执、不做审计、生命周期或授权。
- Session 保留来源/身份/在线/协议/seq 原顺序、管理暂停、掉线门（本人播报确认例外不变）、playing 阶段、失败后实际状态发布、request seq 回执与最终 room 发布。权威层原有座位、视图版本、规则执行和审计原样保留；无新增 kind 或 boolcompat。
- 与本轮初始 Session 原文比较只有两处变动：组件实例声明、`match_command` 内小闭包接线。`func _publish` 开始之后全部文本完全相同，因此保存诊断、恢复事务、生命周期等后半文件没有被本轮改动；身份、transport、room manager、builder/mirror、原回归测试全部只读。

## 契约与选择依据

已完整读取 `_receive`，读取 MatchCommands 全部 API、authority.submit/_submit、dispatcher 全部代码及现有 guard inbox。直接复用 authority.submit；不复制规则、座位判断或扣费逻辑，不新建 operation。

本分支原来在成功和权威拒绝后均 `_publish_match()`，但格式错误不发布。因此结果必须区分“未分派”和“已分派但拒绝”，不能将 execute 与 publish 包进一个能力。错误原因在 submit 后立刻采集，真实发布故意覆盖 authority.error 的用例仍返回原业务拒绝。

`Callable.bind` 追加参数，不能直接给 submit 的第一个成员参数预绑定；caller 使用只捕获局部 authority 和 sender 的请求作用域闭包，组件不保留该 Callable。

程序枚举当前剩余 switch 为 **16 个字面 kind**（本轮仅迁出一个 kind 内的小闭包，分支选择还在 Session）：

`identity_candidates`, `identity_inherit`, `room_password`, `server_data_catalog`, `server_data_prepare`, `server_data_commit`, `server_data_cancel`, `identity_ack`, `preview_group`, `begin_match`, `match_command`, `broadcast_confirm_absent`, `match_finished_lobby`, `join`, `start`, `choose_master`。

剩余职责簇：身份继承/凭据事务、密码保存事务、服务端数据管理授权、预览路由、选人/启动生命周期、播报管理确认、终局返回大厅、join 身份接纳。它们未为凑拆分并入新模块；已迁 room/content/guard inbox 未动。

## 真实 RED → GREEN / 前后对比

证据主目录：

`E:/scratch/round71-host-match-c0863658edc242139cfb1c8cb993d7b9/evidence/`

1. 拆分前真实 ENet host/guest、真实 join 建立 connection→member 映射、真实部署与 Move：37 checks、exit0、stderr 空。
2. 抽取前独占副本将 move 错派成 end_action：37 checks、exit1，命中执行次数/成功回执/真实位置和单次费用断言；无引擎 ERROR。此业务 RED 不写共享源码。
3. 抽取后同输入轨迹一致；最终集成增加组件入口观察（只记录，仍 super.receive）后 48 checks、exit0。
4. 最终 Windows Job 独占副本再次将新组件 move 错派成 end_action：48 checks、exit1、无引擎 ERROR。恢复原字节后重新运行，48 checks、exit0。
5. 11 组前后输入输出/调用轨迹完全相同：accepted、duplicate、bad_seq、bad_shape、bad_params、stale_view、wrong_seat、paused、disconnected、captured_reason、not_playing。`compare.json` 保留完整 before/after，不凭肉眼计数。

真实 accepted：authority.submit 一次、底层 `move` 一次、match 发布一次、成功结果报文一次、消费一次；位置从 area0 到 area1，魔力10→9。duplicate 和坏 seq 不进入组件/authority，不双扣费；paused/掉线/阶段拒绝不进入组件；错 seat 到达唯一权威后拒绝，未执行规则命令。错误形状不调用能力，不发布。

DI 专项另外验证严格 int/String/Dictionary 类型、不新增额外字段限制、缺字段、未知 kind、错误捕获、空错误 fallback、调用次数、输入不变、请求能力不保留及 Session close 后自然释放。

## 最终同一冻结验收

实际可重复命令：

```text
python -B newtests/round71_host_match_runner.py verify
```

所有场景使用原 Godot console EXE、原正式 DLL，`--headless --fixed-fps 60 --path <独占E副本> --scene res://tests/<scene>.tscn`。每项180秒看门狗；最终创建 suspended 进程后加入本轮 Windows Job Object 再 resume，记录 job active=0 与日志句柄释放。未按进程名清理，也未启动28100或 GUI。

| 最终专项 | checks | root PID | exit |
|---|---:|---:|---:|
| round71_host_match_inbox_test | 48 | 28888 | 0 |
| round71_host_match_contract_test | 27 | 13624 | 0 |
| match_command_result_protocol_test（当前原专项） | 39 | 36876 | 0 |
| net_cards_test | 7 | 29736 | 0 |
| net_move_test | 11 | 4224 | 0 |
| net_pending_test | 20 | 23976 | 0 |
| match_command_dispatcher_test | 313 | 18224 | 0 |

**7套、465 checks，均唯一 RESULT、failures=[]、无 SCRIPT ERROR/ERROR、stderr 空。** 控制 RED root PID8260；恢复 GREEN root PID24040。console EXE 的 root PID 与实际引擎子 PID可能不同，Windows Job 覆盖其完整子树，不把 root PID当作 OS.get_process_id 的业务身份。

APPDATA/LOCALAPPDATA/TEMP/TMP/TMPDIR 都显式指向本轮 E scope；场景实测 user 路径为 E:/scratch/.../appdata/FateDomination。另用真实主/子 Godot 探针读回物理路径与文件，main PID7000、worker PID28940；job root21896、exit0、active=0。该探针仅证明环境继承，不代表正式 authority worker/IPC 验收。

最终所有专项的 owned 源哈希一致，并与交付源码相同：

- Session SHA256：`8b02621c55f94746e41780ddd77025e85a7ccb88e4aa0ab2ec5f8c10d1ed88dd`
- 新组件 SHA256：`625476caa400ec04c30b6e99fa82999c4153b6a8bf71c17294ccc57971195fce`
- 原引擎 SHA256：`c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`
- 原 DLL SHA256：`92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd`

最终 fresh freeze 仍与拆分前基线的11组轨迹相等，复核没有拼接不同生产源码版本的专项通过记录。基线原始 Session 与夹具保存在证据中，并核对为初始 freeze SHA256。

## layergate（只读，未新增许可）

实际命令 `python -B tools/check_layer_deps.py --json`。

- 全库初始：exit1，findings44、allowlist46、new=[]、stale2。
- 全库最终：exit1，findings43、allowlist46、new=[]、stale3。
- stale 都来自非本轮拥有的 `tests/net_guard_rollback_test.gd`：`_guard_transactions`、`_paused_runs`、最终又退休 `_guard_continuations`。没有修改该测试、gate 或 allowlist。
- 自有同冻结 before/after 静态结果完全一致、new=[]；该最小冻结未复制历史 scratch，故出现那些许可 stale，不能称为全库 PASS。

这是“没有新增依赖违规或许可”的验证，不是“全库 gate 已绿”。stale 清理由该文件/棘轮 owner 接手。

## 文件与已遇问题

生产修改仅：`scripts/net/session/lobby_session.gd`、新增 `scripts/net/session/host_match_request_inbox.gd`。

自有新增：`tests/round71_host_match_inbox_test.gd/.tscn`、`tests/round71_host_match_inbox_trace.gd`、`tests/round71_host_match_contract_test.gd/.tscn`、`newtests/round71_host_match_runner.py`、本文。

仓库现有 `.gitignore:47` 忽略 `/tests/`，因此新专项文件实存且已运行，但不会自动出现在普通 git status；没有改忽略规则或代为 stage，交接提交时须显式包含这五个自有测试文件。

第一次预检失败不是业务 RED：独占副本漏复制 git/webrtc extension 描述与原 DLL，且夹具在 host() 的 close 重置前注入 traced authority。已准确定位、补齐原依赖、把注入移到 host 后，重建冻结后37 checks通过。初次失败原日志保留在 `E:/scratch/round71-host-match-685283ab152045acbb9840ad8ae30a83/evidence/`；未把解析/加载错误算有效 RED。其余计划内两次错误分派为受控业务 RED，无第三次偶发修复尝试。

未运行 GUI、99套、长恢复场景、导出、多机、正式独立 worker；未验证新组件覆盖未迁职责，未更改或重新验收保存/恢复事务。仅同进程真实 ENet回环、真实规则副作用与明确主动畸形报文覆盖，不冒充完整 LAN/P2P 身份握手。

保留完整原日志、命令/PID/退出码、freeze inventory、源码/原文/差异、hash与路径证明后，仅回收本轮四个独占 scope 的 project/user/path-probe 生成目录，保留 evidence。工作树原有改动未清理、未提交。
