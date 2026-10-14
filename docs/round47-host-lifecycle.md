# Round47 宿主生命周期闭包

## 主代理接线前置（不能宣称整链已绿）

`LobbySession.request()` 目前只把 `match_command` / `broadcast_confirm_absent` 登记到 `_match_request_results`；`match_finished_lobby` 成功分支仅清镜像、发 `match_reset`、发布大厅，没有 `_deliver_match_result()`。因此当前生产房主请求会保持 pending，不能以新大厅视图伪造 accepted。Session 唯一写入者须把终局请求加入既有回执登记、发送失败清理、拒绝分流与成功发布；成功仅在真实规则收尾/room 迁移完成后回执。本代理未修改 Session。

## 真实 trace

- 大厅 `lobby_screen.gd: _enter_match`（当前实际入树代码）注入 `board.network_session`，board `_ready` 建立 source/presenter 和宿主。
- 原 `_bind_board_return_controls` 绑定终局按钮；`_request_finished_lobby` 读取 playing、owner、game_over、int seq，request 的 registered 回调先关联 seq；原 rejected / invalidated 解除或未知。
- Session `request` 在 registered 后复核 `_request_generation`，`_begin_request_reset` 在登记清除/seq 复用之前同步发失效；`close` 清登记与镜像。
- 原 `_process` 直接 session.poll，再凭 lobby+空 match deferred `_return_to_network_lobby`；该函数实例化大厅并注入 session，标 transferred 后移除 board；`_exit_tree` 及主菜单退出直接 close。
- 原实现业务 RED：自身请求失效后，凭大厅视图仍能转交，未要求 accepted。
- 本次只迁这个闭包，不改 presenter、source、Session、权威规则、场景、手牌、modal zoom 或暗牌保护。

## 新组件契约

`battle_host_lifecycle.gd` 构造参数：`(host:Node, session, lobby_scene:PackedScene, request_kind:String, read_request:Callable, read_lobby:Callable)`。

- board 组合根注入正式大厅 PackedScene、`match_finished_lobby`、明确请求参数查询和真实 lobby/空 match 查询；组件没有硬编码 scene path/协议名，没有旧 UI 或规则依赖。
- `request_lobby()`：先立单请求门、registered 关联 seq，消费 request_completed / 兼容 request_rejected；发送 OK 不表示成功。自身请求必须真实 accepted + 完成态同时成立，结果与视图可任意先后到达。
- `pending()` / `outcome_unknown()` / `lobby_available()` 为只读展示状态；changed / notice 由 board 原按钮/提示接收。
- `poll(delta) -> bool`：统一 poll；false 只表示旧宿主本帧不刷新，不是业务成功。大厅先于回执到达或 Session 永久失效时保留终局展示，不调用 presenter 用空视图清页。
- `transferring` 只供命令消费者停止旧在途；组件先标移交并断三个 Session 信号，再挂正式大厅，旧 board exit close 不关闭转交会话。
- close 永久幂等、先断信号/清 attempt 再实际 session.close；失效不重放，不自动保存。

## presenter 串行接口声明（未修改 presenter）

presenter 只保留 `refresh()` / `release()` 的投影职责；没有 session 转交/close 权。board `_process` 仅在 lifecycle.poll 为 true 时刷新 presenter；传交开始只 stop commands。主代理不得再让 presenter 同时 poll 或按空视图推断 finish 请求成功。若需要 presenter 生命周期通知，应由主代理显式接线，不把候选接口当已存在。

## 当前证据

- 干净业务 RED：`E:/HermesScratch/round47-host-296cbbf4def949d5a0bed0e49c7bf30c/manifest.json`，Godot 4.7.2，exit1，1项断言失败，errors=[]；原 board 函数原样提取，仅替换目标 PackedScene 为隔离 lobby fixture。
- 第二 RED：`E:/HermesScratch/round47-host-44031e8c8cac4ba0861f7102cad9cd86/manifest.json`，拒绝后大厅不能冒充 accepted，exit1，errors=[]。
- 第三 RED：`E:/HermesScratch/round47-host-361059903107404186dd52f0bd196752/manifest.json`，大厅先于回执时不能刷新空镜像清终局，exit1，errors=[]。
- 当前组件 GREEN：`E:/HermesScratch/round47-host-cdf8f1ff362947f0befa326cb9c9576f/manifest.json`，exit0，33 checks，failures=[]，errors=[]。这是可控 Session 合同，不是 RSA/ENet 终局协议或画面验收。
- 命令：`python tests/round47_host_lifecycle_runner.py`。每进程180秒，只回收自有PID；APPDATA/LOCALAPPDATA/TEMP/TMP/TMPDIR 全部自有 E 目录，generated 已删除，完整日志/hash/manifest 留存。
- 没有操纵窗口，没有改引擎，没有提交。

## 旧专项迁移缺口

共享 `tests/match_finished_lobby_test.gd` 直接读写已移除 `_network_session_transferred` / `_finish_lobby_request_seq` / `_finish_lobby_unknown`，以及假设同步 transfer；不在本代理写权。本轮保留其源码不改，主代理须迁到宿主只读公开状态、真实 request 夹具与 deferred SceneTree 帧等待，不再注入私有序号。

## 最终冻结交付

### 组件及检测能力

- 最终组件合同 GREEN：`E:/HermesScratch/round47-host-c1b7b1c41d794713abed69163aea36be/manifest.json`，exit0，33 checks，failures=[]，errors=[]。
- 隔离负向检出（不是修改生产，也不是把 mutation 当旧版本基线）：`--fault old-result` run `ae630ac140584227b73f8070938c9526`；`--fault close-reentry` run `25875e7dce784fc4b49bcc434c584673`；`--fault poll` run `075acd1cd84040e08b91454f8ca26bdc`。三者均正常业务 exit1、对应断言 RED、errors=[]，随后同生产 hash 再跑 GREEN。均在 `E:/HermesScratch/round47-host-<run>/manifest.json`，记录 production/injected 两套 hash。

### 真实生产组合根 RED（必须交 Session 唯一写入者）

命令 `python tests/round47_host_lifecycle_runner.py --board`；最终记录：

`E:/HermesScratch/round47-host-60f238fa12f64106a2832804774f4e46/manifest.json`

- 实际 Godot exit1；14 checks，2业务失败，errors=[]，无 timeout、解析错误、退出资源残留。
- 真 ENet host，公开 configure_selection→ready→start→choose_master→begin_match，七席实际启动；显式 driver 席位 AI fixture 自然终局282步、唯一 game_end，真实终局镜像发布；不使用私有 room.phase/authority.started 装配，不伪造 result signal。
- 正式 `battle_board_v2.tscn` 成功解析/入树，宿主组件与终局按钮实际接线；权威真实收尾、发布 lobby/清 match 均通过。
- 当前失败只有 `real_correlated_finish_accepted_receipt` 与 `formal_board_transfers_exactly_once_after_real_receipt`：确切 kind 未提供 accepted 回执，因此安全保留 pending 与终局页面。页面保留断言通过；这不是迁移整链 PASS。
- 正式 fixture 不是多机/RSA客机或真人规则测试；这里只验证本机房主的公开生产链。
- 全依赖 hash 保存 `dependencies.json`。执行期间漂移仅两个未运行的其它代理测试（`tests/round47_presenter_power_test.gd`、`tests/server_data_status_inbox_contract_test.gd`）；本轮 board/component/正式测试与 Session 生产依赖未漂移。不用此冻结证明其它代理当前工作树。
- 实际 user 路径分别已打印/校验到自有 E APPDATA。运行器所有 APPDATA/LOCALAPPDATA/TEMP/TMP/TMPDIR 都显式注入 E；全部自有 generated 已回收，最终 remaining=0。引擎二进制完全未改。

### 串行 GUI 验收 command（本代理未执行）

仅由主代理/唯一窗口执行者在补齐 Session 回执后执行：

```text
python tests/round47_host_lifecycle_runner.py --board --window
```

该命令创建新独占 E 冻结，去掉 `--headless`，实际传 `-- window`，执行 `Input.parse_input_event` 鼠标移动/按下/松开正式终局按钮；窗口分支另断言非headless、按钮树内可见、正式大厅替换旧宿主。运行器保留 `round47-terminal-before.png` / `round47-lobby-after.png` 后回收工程/user数据。主代理还须原生查看截图/窗口，不得把 headless 检查称为画面通过。当前未补回执时，此 command 应业务 RED，不可注入 fake accepted 求绿。

### 最终 SHA256

|文件|SHA256|
|---|---|
|scripts/game_scene/battle_board_v2.gd|`b9cc2f627a9bcf4f74c66d173166572152c001d7816dc37f57a71fb6c94e205a`|
|scripts/game_scene/battle_io/battle_host_lifecycle.gd|`ac3011654a8ccae7b230d693632fbdab40032c857c2b684a1da4430b5a499605`|
|tests/round47_host_lifecycle_test.gd|`b8c3dcbde884473a54c53e6457f5515ae4ae75c6cd60d48924e988fef3e8d292`|
|tests/round47_host_lifecycle_board_test.gd|`7df8120e89e4f281a32df7eaa5b059d133579b37c794bd9dedc33dd652795369`|
|tests/round47_host_lifecycle_runner.py|`ec18cdad5d31a5710c80cd31fce28632da219f0c4b62ac4406c9e03a949db193`|
|Godot 4.7.2 console原二进制|`c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`|

新增自有 tests 共8文件（baseline GDScript；组件 gd/tscn；fixture lobby gd/tscn；正式 board gd/tscn；runner.py），均被仓库 tests 忽略规则覆盖；已实际落盘，未擅自改忽略规则或暂存。新组件与本报告未被忽略。board 的既有未提交修改原样保留，`git diff --check -- scripts/game_scene/battle_board_v2.gd` exit0。

复用流程教训已补到默认 profile 的 `godot-terminal-lobby-orchestration` skill；项目外无其它配置更改。