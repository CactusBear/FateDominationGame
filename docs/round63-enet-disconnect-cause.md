# Round63：ENet 原生断线来源——明确工具阻断，不冒称 cause

## 结论

**实际原生断线类别仍 unknown。** 本轮完成同引擎身份/官方源码/API与符号可用性核查、原件完整脚本栈复读，结果为 `TOOLBLOCK_MISSING_NATIVE_FIELD_AND_VERIFIED_ENET_ADDRESS_MAP`，真实执行 exit2。没有取得断线来源的同线程 native stack、断线前 ENetPeer 实际字段或协议事件类型，因此不报 timeout 根因、不建议改超时，也不宣称 sourcePASS。

新增运行恢复次数 **0**；没有续440、改target/seed/原15/pool20/600预算，没有冷import、GUI、attach、全机抓包、重编译或引擎/DLL/SDK/production/transportprobe写入。没有调用任何统计/timeout setter。只启动原宿主 `--version`（exit0），不执行可变主工程。

## 可复核产物与运行

```text
python -B tools/diagnostics/round63_enet_disconnect_cause.py --root E:/scratch/round63-enet-cause-final --archive E:/scratch/isolated-7ee7ee28648c4e36a3b71869a8234316 --engine D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe
```

- 报告：`E:/scratch/round63-enet-cause-final/report.json`，SHA256 `af4fdd29ecbefc92be8f9ac42b2fcccac58fbbbf312e8f56a1fc8feaf1de24be`。
- 实际执行器原件：同根 `executor.py`，SHA256 `e7f5609c9d4ca77c0217095351b2a85ec3f072f725ae13c50299ad00d3d495fb`。
- 官方原源码9份与发行asset页1份均真实下载成功，URL/字节数/逐SHA256保存于report；原件位于同根 `source/`、`official-release-assets.html`。未拿近似版本或Android符号代替Windows符号。
- 原始宿主版本stdout/stderr、官方tag查询stdout/stderr均保存。API最初遇真实403 rate-limit，改raw源码/官方asset页/git tag路径后成功；没有捏造API返回。
- `actual-evidence-tests.log`：真实PE/实际源码、现有根拒绝、越界拒绝、旧Job0/原件保持、完整cleanup栈、无payload投影及无假native trace共8项检查，exit0。这只是分析器检查，不是产品REDGREEN。
- 初步preflight原件 `E:/scratch/round63-enet-cause-readonly/` 仍保留；最终报告使用完整官方commit，未合并为两次产品成功。

## 宿主与符号边界

实际宿主版本 `4.7.2.stable.official.ed1daf0bf`；EXE SHA256 `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`，与round62原manifest相同。

`git ls-remote https://github.com/godotengine/godot.git refs/tags/4.7.2-stable` 实际返回 `ed1daf0bf001b61586d9930840f2f1394092c079`，与宿主版本提交前缀吻合。官方源码按此完整commit取得；**这是源码版本绑定，不是native地址映射，更不证明动态走过对应分支。**

真实PE检查：AMD64、COFF symbol_count=0、debug directory RVA/size=0、无CodeView记录，无DWARF/debuglink section；3个export中无ENet函数。同引擎目录没有 `.pdb/.debug/.sym/.map`。文件内偶然出现 `RSDS` 字面量不是有效调试目录记录，不能据它下载“匹配PDB”。官方4.7.2 asset页只提供Android原生symbol zip，没有Windows原生symbol/PDB资产。

已有 `native_cold_import_debug.py` 亲读确认可自有 `DEBUG_ONLY_THIS_PROCESS` 启动及StackWalk64，但其断点需要已核实RVA、只观测主进程、不自动覆盖worker子进程。既有editor teardown RVA与ENet无关；本轮没有安装任何猜测断点或盲attach用户editor。无可靠ENet入口映射时再跑一次长恢复仍只能得到相同脚本信号，故停在工具门槛，而非以重复seed消耗代替证据。

## SDK/API真实可观测范围

以下引用均为同根 `source/` 内完整官方commit文件。

- `modules/enet/enet_packet_peer.cpp:133–164,208–251`：`get_statistic`真实只暴露packetLoss/variance/epoch、roundTripTime/variance/last与throttle系列14统计；另有remote address/port、state/channels/is_active。**无timeout三字段、lastReceiveTime/lastSendTime、earliestTimeout/nextTimeout、可靠未ACK队列、disconnect origin getter。** 未调用getter或setter来替代missingnativefield。
- `modules/enet/enet_connection.cpp:226–246`：`pop_statistic`取计数后执行 `*ptr=0`，不是只读；禁止作为本轮host计数采样。
- `thirdparty/enet/protocol.c:80–89,137–157`：DISCONNECT交付前 `enet_peer_reset` 已发生；`peer.c:382–435` 清lastSend/lastReceive/next/earliestTimeout、计数、队列并重新赋timeout默认值。不能在callback后把reset值冒称断线前actualfields。
- `enet_connection.cpp:133–141`先 `pp->_on_disconnect()`，`enet_packet_peer.cpp:185–193`清底层peer指针，然后才交付Godot事件；`enet_multiplayer_peer.cpp:216–223`才emit服务器的peer_disconnected。故单在脚本callback加getter已太晚，需在原生reset之前捕获。

## 四类来源的源码分型，不冒充真实trace

|候选|同提交源码关键入口|还缺什么|本次判定|
|---|---|---|---|
|远端显式DISCONNECT|`protocol.c:822–847` handle_disconnect；可能先进入ACKNOWLEDGING_DISCONNECT/ZOMBIE，再dispatch|该handler实际命中、同threadstack、host/remote绑定、仅协议command类型/时间|unknown|
|本地请求close/disconnect/reset|`enet_multiplayer_peer.cpp:271–306`、`enet_packet_peer.cpp:35–71`；`peer.c` disconnect函数；`protocol.c:929–934`处理本地DISCONNECT可靠ACK|双方route对应native调用断点覆盖与caller完整栈；无命中负证据必须有覆盖窗口|仅否定现有fixture晚cleanup为首触发；不能全局否定explicit close|
|可靠重传timeout|`protocol.c:1351–1405` check_timeouts → notify_disconnect|同thread实际timeout分支、host serviceTime、peer实际timeout三字段/earliest/next/lastReceive、outgoing sentTime/RTO/sendAttempts及可靠ACK状态|unknown；gap不是证明|
|异常hostfatal|`enet_connection.cpp:179–182` service<0 → EVENT_ERROR；`enet_multiplayer_peer.cpp:227–229`服务器error分支直接close|真实host service负返回/错误来源栈、双方route关联|源码上“纯本地server service<0”不是直接emit该peer_disconnected的分支；未捕获native栈，不能据此排除远端fatal导致的后续关闭或其他复合路径|

另有 `enet_multiplayer_peer.cpp:148–171` inactive-peer sweep也可emit同一个信号；单个signal无法区分它与EVENT_DISCONNECT。该分支进一步说明必须取得原生stack，不能补一个伪造来源字段。

timeout源码实际条件：先有 `sentReliableCommands` 中命令达到其 `roundTripTimeout`，设置/比较 `earliestTimeout`，随后 `serviceTime-earliestTimeout >= timeoutMaximum`，或重传倍数达到 `timeoutLimit` 且时间达到 `timeoutMinimum` 才notify_disconnect。ACK handler `protocol.c:913–918`会更新lastReceiveTime、清earliestTimeout并移除sent reliable命令。这里仅抄源码谓词；**没有现场数字，不拿源码默认宏、RTT78或约4.95秒pollgap冒充actualtimeout。**

## 原件栈与routeclose证据的准确边界

原worker日志亲读48物理行，仍严格是：34行 peer988510555先native-disconnected，35行transaction1/member2111426756/cancelled=false，36行才cancel/revision16；39行才worker close_requested。4–5行是listen初始化时native_instance=0的close，不是已连接route恢复期close。

原客户端JSONL中**22条有关身份/完整脚本栈**已白名单投影到report；业务 `message_received` 行在JSON decode前跳过，无新读取/输出payload、keys或tickets。

- event100/102完整栈：lambda:restart78 → `_begin_request_reset`:lobby627 → `_prepare_reconnect`:277 → `reconnect`:300 → `_recover_match`:restart339。对应generation2重连，不是新route取消。
- event116完整栈：lambda:restart44 → `_on_disconnected`:enet85 → `keep_alive`:94 → `poll`:106 → `ServerGateway.poll`:102 → `_recover_match`:restart377。**这是另一内部route1077362028的下游断开，不是首worker peer988510555的native栈。**
- event120/121完整栈相同：lambda:restart78 → `_begin_request_reset`:lobby627 → `close`:637 → `cleanup`:matchtest230 → `run`:106 → `_after_baseline`:restart141 → `_continue_restored_match`:150 → `_recover_match`:414。均为diagnostic_cleanup/generation3，比客户端故障观察晚。

旧trace没有双方所有native close/disconnect调用断点，不具备完整“无显式close”负向证明；也没有首worker回调原生同线程stack。worker.close_requested字段本身不含调用栈，不能拿源码调用关系伪装当时动态栈。

## 冻结、漂移、退出与保留

原manifest SHA256 `645697d418d79b1ea18d1310d14eb9558d221490c1312968adda28cb26e79fb9`；全部762 artifact在分析前后逐SHA256读回一致，原manifest亦未改。原3 Job仍 exited=true/active_owned_processes=0/log_handles_released=true，退出码0/0/1；原generated已removed。不把历史Job0写成新恢复成功。本轮无新game/worker Job，无需进程清退，不触碰用户28100。

实际因果输入是原 `evidence/frozen-inputs/` 和原日志，加完整官方commit源码；可变主repo仅作漂移读取、不运行。原manifest列出的2094路径在preflight前后皆逐哈希观察，本次窗口 `outside_readonly_original_drift=[]`、`source_tree_drift_during_observation=[]`；这是本次采样事实，不担保并行写者随后不改，也不覆盖原manifest之外新增文件。完整before/after及原hash保存于report。

最新版两loader亲读并与原round62冻结相同：validationworker `a3d94c8af2723022d62420ed5cf81486711425c72c7a90232e246f2ce05d793a`、load_game `2a78f90ac18bd76ea2ea3181349d069874bda5df3ce8280134e17f9ef17c92e5`。无拿旧round61 loader合并成功。

本代理仅新增仓库 `tools/diagnostics/round63_enet_disconnect_cause.py`、本报告；不改runner/restart测试诊断或任何production。原资料/日志/rawfrozen/失败与初步preflight均保留。没有产品修复、fixture REDGREEN或sourcePASS；完整恢复/ACK/终局/save仍未验。

## 主接缺口

需要当前EXE匹配的可验证ENet地址/类型映射（官方Windowssymbols或独立审核后的准确反汇编映射），并能自有监督同时覆盖gateway与恢复worker，捕获reset前现场。最小白名单是同threadstack、host/route/remote identity、protocol类型与时间、实际timeout/lastreceive、可靠未ACK命令的类型/时间/重传计数，禁止数据payload/keys/tickets。

当前缺上述映射与nativefield，停止重复长case。gateway泵送停顿仍仅候选：没有“确切阻塞函数/时段 + 同route实际native timeout分支”双证据，不给keep_alive生产patch或加timeout建议。
