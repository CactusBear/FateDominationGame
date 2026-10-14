# Round54：原发行服务端真实认证、房间关闭与 stop 接缝

## 结论

**BLOCKED_GATEWAY_STOP_AFTER_SAVED_LOBBY_NATIVE_RELEASE，不是 SERVER_PROTOCOL_GREEN。**

同一原 `FateServer.exe`/PCK 已实际通过 RSA 客户端认证、真实新房 READY、继承 settings15、正式 console 保存空大厅关闭、worker exit0 和原 Process 句柄释放。但随后正式 console `stop` 返回保存确认失败，日志明确 `SERVER_STOP_FAILED`；网关 PID **28100** 仍存活，未强杀、未重试 stop、未删除存储。必须由主代理消费这一红项和保留 PID，不能只汇总前半条成功。

## 原件、独占路径与真实入口

- parent：`E:/FateCandidates/round52-current-roles-20261010-sa1/manifest.json`，SHA256 `5a6f9013bbb09a29798a12b999ca1428222f0e3c061f1caf7fd005c0b72230f0`。
- 首次有效 worker 证据：`E:/Caches/Hermes/cache/scratch/round54-packaged-protocol-first-worker-sa3/actualruntime.json`。
- 编排前、每个子进程前后及最终完整核对：client **209** 文件、server **210** 文件，集合与 SHA 全部精确匹配 parent；未重导出、替换 DLL/PCK 或写入包目录。
- 公共归档：上述根 `public-evidence.zip`，SHA256 `e5283d60a86c9137bb6b4ffdbc72986649426ca5b4db828101e6dd084dc1a6a9`；CRC 与逐文件 SHA 读回通过。包含公共回执、运行参数/日志、worker engine log、源码哈希及当前诊断源码，不包含身份密钥、registry、recovery stores；没有删除这些目录。
- 只客户端使用原官方 editor `D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe`，SHA `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`，`--path` 指向 source、`--scene res://tools/diagnostics/round54_authenticated_client.tscn`。这是 **source-editor 场景客户端夹具，不是正式 release client GUI**。
- 服务端始终原包主入口 `-- --server-gateway --config <独占deployment.json>`；真实 worker 同样是包内 `FateServer.exe` 原职责。没有 Python server/响应替身、release `--script` 或引擎改动。

## 首次有效 worker 的整条实际结果

|环节|实际证据|
|---|---|
|gateway READY|PID28100，UDP60232，本机显式批准原包 data_root|
|RSA 客户端|PID35300，authenticated=true，exit0，pool20；真实 user root 在独占 E users/client-own/appdata/FateDomination|
|创建请求|capacity7/minimum1/ai_count0/正式 default_mode unique_master_class_pool/spectator_limit7；人数容量调用正式 rules.capacity 原语；请求 **不含 random_sim 字段**|
|worker READY|PID25640，UDP60233，room `2c9ddf5fa6f97659185b336d7441dbfa`，instance `2cd94756465e85782cc110fc6cd0938b`，authority_host_mode=dedicated|
|配置传递及客户端读回|worker config.settings 与客户端 settings 均 random_sim_enabled=true/random_sim_budget_sec=15.0；继承明确来自本次 deployment.data15，不扩大为包内 cfg runtime getter证明|
|空大厅|客户端正常 Session.close 后，正式 console `list` 读回 []；`rooms` 读回对应原 PID ready=true/error空|
|正式 console close|request `9d9c584f9be8e6b862cafd156ba39f3b`；最终响应的 room/pid/instance/authority_host_mode/request_id 全部精确对应 READY|
|最终保存语义|ok=true，closing=true，**saved=false，room_state_saved=true**；只证明大厅恢复状态保存，绝不当作对局 save|
|worker退出|独立 Win32 GetExitCodeProcess 保留观察句柄读回 **exit0**|
|原网关句柄释放|仍存活 PID28100 的真实 Process handle table：指向 PID25640 的句柄1324，关闭前1个、关闭后0个，Process类型复制失败0；同时正式 rooms 变 ready=false/pid=-1|
|正式 stop|仅一次；即时 ok=true 但 stopped=false/pending_rooms=[]/failures非空；原日志 SERVER_STOP_FAILED，网关未exit0|

最终 stop 唯一房间失败原文：`原生进程句柄不可用，无法确认本次保存`。

独占 console：`E:/Caches/Hermes/cache/scratch/round54-packaged-protocol-first-worker-sa3/deployments/protocol/console`。storage：同级 `rooms`。主代理处理前须读取 actualruntime 和原日志，确认精确 PID/绑定；不要按进程名清理。

## stop 接缝的只读定位

亲读 parent 冻结 `project-server/scripts/net/server/server_shutdown.gd`：start() 的31行只接受 shutdown 自己 `_closed` 中已有条目；79–81行只在 shutdown 自己请求的关闭链填充 `_closed`。本次先走独立 console close，manager 已保存 closed binding 且 release，shutdown `_closed` 仍为空，随后32–36行用当前撤销后的 binding 查询原生句柄，得到不可确认状态并拒绝。因此前置保存和 release 成功不能拼接成 stop exit0。

这是原包可复现接缝证据，未修改生产 shutdown/manager。新 status actor 或未来修复必须经新 pack 后另行补验；当前旧包不能捏造 ClassDB 注册/方法表、manager cfg getter、closed-binding新 status 字段。

## 前置拒绝与编排器事故保留

1. 最初旧 Round53 夹具式空 settings={} 请求先实际完成 RSA，但在创建前拒绝：`SERVER_ROOM_CREATE_FAILED {"error":"人数配置必须显式提供整数"}`。**没有 worker/config/READY/staging**，不是 worker 启动或 settings15 失败。证据根 `round54-packaged-protocol-sa3` 保留，正式 rooms=[] 后正常 stop，原网关 PID23184 独立 exit0。原执行器已返回，不能追认其旧 Job active0。随后按正式 UI 的合法人数/选人声明修正夹具，只启动一次有效 worker。
2. 有效 worker 的 settings15 首次成功后，诊断器误把101个非 Process 句柄不可复制当成失败，尽管已找到原 worker Process handle；修正为从自己打开的真实进程句柄动态确认 object type，仅观察 Process 类型。另一编排器命令误用 `clients`，原包实际返回“未知命令”；读源码白名单后改为正式 `list`。两次只继续同一网关/同一 worker 的观察，没有重建房、worker/client重试或调整配置。
3. 一次观察恢复给现存 gateway/worker 赋予真实私有测试 Job；这不是新 C++ Job 能力或发行包完整树准入。由于 stop 明确失败，原执行器仍等待到既有180秒看门狗才返回，这是不必要的等待，证据不抹除。已将诊断器改成收到 stop failures 即停止，未上调 startup30/shutdown30/180预算。最终网关被保守保留，不能声称 Job active0。

## 真实 native/module 可观测边界

原 gateway 和原 worker 均实际加载包内 `libfate_server_signals.windows.template_release.x86_64.dll`，SHA `92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd`，路径、PID和模块 SHA 均记录。结合真实启动、Process handle 和精确绑定管理响应，提供独立 native binding/modulepresence 证据；**不是全部四类 ClassDB 注册及方法读回**。runtime manager cfg15 getter 未验，明确部署默认→配置传递→客户端15有效值这一层实际通过。

对外/内部 UDP 都来自真实 bind0，释放到正式 bind 是 **非原子交接**，保留竞态风险；没有监听失败换端口。未读取用户身份库或打印生成密钥/指纹/挑战值；仅自身独占 E user root 使用生产 RSA 身份原语。

## 文件和剩余项

本 owner 仅新增 `tools/diagnostics/round54_packaged_server_protocol.py`、`round54_authenticated_client.gd/.tscn` 与本报告。源树生产文件未由本 owner 写入；最终哈希发现并发其他 owner 改动 `addons/fate_server_signals/src/process_owner_core.cpp`，因此不宣称全源树被冻结，client相关 GD/data与本次包未变。本次新增场景实际解析运行并 exit0；Python语法检查通过。

开放：**gateway 正常 stop exit0**、正式 release client GUI、多机/跨网、对局save/恢复、完整 native注册/manager getter、新status actor发行、新C++Job及cleanup能力。默认trace另一 owner 的报告必须由主代理亲自验证，本报告不代其验收；不与 GUI owner 重叠开窗，也未修改生产代码。
