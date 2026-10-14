# Round50：真正终局回大厅 accepted 关联闭包

## 结论与边界

- 正式公开房主自然终局 **board14 GREEN**：真实 ENet host → configure_selection → ready/start → choose_master → begin_match → 显式七席 driver AI fixture 自然终局 → 正式 battle_board_v2 按钮 → 真权威收尾/room 迁移 → 真 accepted → deferred 单次正式大厅移交。此次自然终局为 **281 步**、唯一 game_end；不把历史 282 步写成此次结果。
- 迁移旧专项 **44 checks GREEN**；最终回执专项 **16 checks GREEN**；提取生产函数的 tight 原 RED → minimal GREEN（6 checks）。各套实际退出码与完整日志如下，不用组件夹具冒充真实生产成功。
- 仅修改 `scripts/net/session/lobby_session.gd`、`tests/match_finished_lobby_test.gd`；新增本报告和自有 round50 receipts/tight gd/tscn/runner 共五文件。board/lifecycle/presenter/source/authority/statusinbox/倒计时、场景及引擎均未修改。保留共享工作树既有修改，不提交、不暂存、不擦历史 RED。
- 未开窗口、未操作现有 GUI owner；未声称多机/真人/磁盘故障验收。真实远端 ENet/RSA专项覆盖非房主拒绝回执，真实 accepted 业务成功在本进程房主公开整链验证；没有注入 accepted 来使正式 board 通过。

## 亲读的生产链与最小改动

1. `request()` 先分配实际 seq、登记 `_match_request_results`、执行 registered 回调，再复核 reset 代际；房主同步 `_receive()`，客户端走可靠 ENet。发送 OK 仅是发送结果。新增统一 `MATCH_RECEIPT_REQUEST_KINDS`，三种 kind（match_command/broadcast_confirm_absent/match_finished_lobby）共享登记、sendfail 擦除及 `_reject_request()` 分流。
2. `_accept_match_command_result()` 继续使用原独立 version=1、严格五字段 `{kind,result_version,seq,ok,reason}`；来源仍由 `_receive()` 的真实连接和 sender==1 决定，不信自报 actor。不改请求、快照、结果线协议版本。
3. `_consume_match_result()` 在 signal 前写已消费标记。`_fail()` 的本机已登记请求也进入这个消费门，重复 generic error/rejected 不再二次结算。completed 或 request_rejected 回调同步 close/reconnect 后，复核代际，停止向新代发旧 rejected。
4. `_reject_request()` 给真实请求 connection 发原公共 receipt；远端 legacy error 仍兼容，客户端由已消费 seq 拦重复。`_deliver_match_result()` 的非本机分支保留 `transport.send(connection, receipt)`；`enet_transport.send()` 显式 `TRANSFER_MODE_RELIABLE`、默认 channel0。
5. 成功终局仍完整保留认证映射、连接在线、owner、playing、管理暂停、严格唯一 view_seq:int、请求 seq 去重和 authority 终局资格校验。只有 `finish_match_to_lobby()` 真成功且 `room.return_to_lobby()` 真成功，清真实镜像之后，才 `_deliver_match_result(connection,message.seq,true,"")`。回执可先于跨通道 match_reset/大厅视图到达，消费方仍须 accepted 与 lobby/空 match 同时满足。
6. 在不可逆规则收尾前捕获本请求代际；收尾后、清镜像同步通知后及回执同步通知后复核，close/reconnect 退休请求不得继续结算或发布。正常 match 镜像 reset 不清请求关联，不调用会话代际 reset，因此不会误丢自身 finish 请求。
7. `_prepare_reconnect()`/`close()` 仍先 `_begin_request_reset()`（设置 reset 门、推进代际、同步 invalidated）再清登记；只去掉同一 Session 实例的 `_seq=0`，保留递增分配水位，防旧 receipt 撞中新代同号登记。上限拒绝仍由原 MAX_INT64 检查负责。没有添加 board 兼容私有字段，也没有在报文里自报代际或 auth 身份。

## 旧专项迁移

- 删除 `_network_session_transferred`、`_finish_lobby_request_seq`、`_finish_lobby_unknown` 的全部读写及 teardown 注入。
- 通过生产组合根取得生命周期组件，仅查询其公开 `pending()`、`outcome_unknown()`、`lobby_available()`、`transferred()`；移交等待 deferred SceneTree 帧。
- 成功请求 seq 从真实 `request_completed` 取得；房主/客机正式大厅各自持有原 Session，board exit 不关闭转交会话。
- unknown 覆盖改为真实 ENet 已发送、权威尚未 poll 的请求，再真实 close；只注入组件参数查询，不注入私有关联或结果。无关 rejection 的消费者断言与真实 lifecycle invalidation 分开标明。
- 保留旧专项手工 playing/authority 装配边界，不把它叫完整公开开局；完整公开链只由 board14 证明。

## 原 RED 与真实结果（永久保留）

统一产物根 `E:/HermesScratch/round50-finish-<run>/`。每项均留 `manifest.json`、`dependencies.json`、stdout/stderr 完整日志。tight 另留原样提取生产函数 `tight_session_extracted.gd`。冻结记录包含 5471 个源/资产/cache 文件 SHA256；实际运行 APPDATA/LOCALAPPDATA/TEMP/TMP/TMPDIR 与 user:// 均在独占物理 E 子树，generated 已回收。

|用途|run|实际结果|
|---|---|---|
|干净原版 tight RED|098b795b44f1438db033a2cc15d6243a|exit1；6 checks，4 次业务失败；无 SCRIPT ERROR，无 timeout|
|首次 minimal tight GREEN|5db77f1455ad40c3895795c7b1dd244f|exit0；6 checks，failures=[]；无引擎错误|
|最终 currenthash tight GREEN|08f13fee676f4776867219b178ce2b90|exit0；6 checks，failures=[]；无引擎错误/漂移|
|真正正式 board14 GREEN|b94a632c672740e7b6dd019584a28991|exit0；14 checks，failures=[]；281步、唯一 game_end、真 accepted、单次移交|
|迁移旧专项 GREEN|974be99d29af46d694f14f61af16611c|exit0；44 checks，failures=[]；自然终局272步及真实第二局启动|
|最终 receipt GREEN|84af6cbebba04876a1e47dabcabc6eb7|exit0；16 checks，failures=[]；真 RSA/ENet 非房主回执、sendfail、close/reconnect、旧结果隔离、completed-close 重入|

- tight 是原样生产关联函数 + 明确 fake transport/权威拒绝入口的最小协议单元，不证明权威资格/自然终局。原版 Session hash 为 `89f250bc71372ea70e4a8d011e4334b931f78537aea1165d5f0a0a002d26c005`。
- 原历史正式 board RED 仍保留：`E:/HermesScratch/round47-host-60f238fa12f64106a2832804774f4e46/manifest.json`。未覆盖或修改。
- 初期无效探针也保留：`a5b5753bdf7841d5a4a3c463279dcee9` 是新测试局部类型推断错误/180s自有PID回收；`d14d1f16fce543408e5ea0d67bfd35b2` 虽检出六项关联失败，但带共享 `server_console_channel.gd:377` 作用域 Parse Error，不能算干净 RED；该共享错误后来由其写入者修复，本代理未改。`a1b0f30c732943e283da73f1f20d4f7c` 为提取夹具空格/tab问题；`eaea1c82723745f9a6876219da7c4bec` 为不适用于带 autoload 测试的 --check-only 预检。它们均不算验收通过。
- board/legacy/最终receipt的全部生产依赖（scripts/assets/data/game_data/addons）逐 SHA256 比较一致，当前生产依赖对 board 冻结无漂移。board 执行时仅其它未运行测试 runner/guard test 漂移，已在 manifest 原样记录；不同测试文件变更不被隐瞒，也不把不同全冻结说成相同。
- `git diff --check -- scripts/net/session/lobby_session.gd tests/match_finished_lobby_test.gd` exit0。项目 tests 被现有忽略规则覆盖，新增/修改测试均实际落盘，未改忽略规则。

## 真实命令与 GUI owner 交接

已执行（每个 Godot 子进程180s上限，只回收自有PID，既有15s规则默认未改变）：

```text
python tests/round50_finished_lobby_receipt_runner.py --suite tight
python tests/round50_finished_lobby_receipt_runner.py --suite receipts
python tests/round50_finished_lobby_receipt_runner.py --suite board
python tests/round50_finished_lobby_receipt_runner.py --suite legacy
```

新 runner 故意仅提供 headless 模式，不取得窗口权。唯一 GUI owner 在核对以下生产 hash/依赖后执行既有正式命令：

```text
python tests/round47_host_lifecycle_runner.py --board --window
```

该 runner 创建新独占 E 冻结、去掉 --headless，真实传 `-- window`，用实际鼠标输入点击正式终局按钮，保留终局/大厅截图。owner 必须原生核对截图、非 headless 分支、实际点击与正式大厅替换；此次 headless GREEN 不作为画面验收。

完整 board 依赖索引：`E:/HermesScratch/round50-finish-b94a632c672740e7b6dd019584a28991/dependencies.json`，SHA256 `e2074acabe10745a05451822a6db29cae557f4a349fcec7ada58b8b94a100326`。
最终 currenthash 全索引：`E:/HermesScratch/round50-finish-08f13fee676f4776867219b178ce2b90/dependencies.json`，SHA256 `08eb5a9788eeb464e533ab3e74b23f83d3bba3394fcca12da4c3d6f35eaa7239`。

|关键依赖|最终 SHA256|
|---|---|
|scripts/net/session/lobby_session.gd|11b0f98a6cf68a8b441680ba2d24741be39c9a7c470aa6569e9fbe711a0dbf56|
|scripts/game_scene/battle_board_v2.gd|e72859ee5807c3dbd533507392633dca6234ca19142e669d847b125ee09df709|
|scripts/game_scene/battle_io/battle_host_lifecycle.gd|ac3011654a8ccae7b230d693632fbdab40032c857c2b684a1da4430b5a499605|
|tests/match_finished_lobby_test.gd|d1ff1196d295a4488281ee59f64f11ef2677ed04bdce5c3891c230b2e5db5dac|
|tests/round47_host_lifecycle_board_test.gd|7df8120e89e4f281a32df7eaa5b059d133579b37c794bd9dedc33dd652795369|
|tests/round47_host_lifecycle_runner.py|ec18cdad5d31a5710c80cd31fce28632da219f0c4b62ac4406c9e03a949db193|
|tests/round50_finished_lobby_receipt_test.gd|6f90078be1b9a2fffed6073778f720a8043d8686393f35993e5dbea28628bdfb|
|tests/round50_finished_lobby_tight_test.gd|84229ab6839f88ae0b78fccc2a134efe316f29a2df2b0495981d2253d8357080|
|tests/round50_finished_lobby_receipt_runner.py|3114c4334353f02859ae33bad7cee1dc420dacc31f2d44dd0e92b995b56b5bae|
|Godot 4.7.2 原console二进制（所有运行前/后相同）|c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643|

复用教训已补到默认 profile 的既有 `godot-terminal-lobby-orchestration` skill；未修改其它 profile。
