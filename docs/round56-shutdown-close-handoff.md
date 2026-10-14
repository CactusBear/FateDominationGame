# Round56：console 保存关闭 → shutdown stop 接缝

## 结论与边界

**SOURCE_CLOSE_STOP_HANDOFF_GREEN；旧发行包仍是 BLOCKED_GATEWAY_STOP_AFTER_SAVED_LOBBY_NATIVE_RELEASE。**

有效 RED 后最小修复生产 shutdown 与 manager 的只读历史查询。正式 manager 创建生产独立 worker，空大厅经公开 console `room <id> close` 保存、真实 EXITED/release，然后同一 shutdown 一次 stop 完成。另验重复 stop、新 recover 实例、自发 close、真实保存失败、UNKNOWN、磁盘回执类型/绑定/缺失/摘要变化和读回竞态、pending 原请求与 retired 未确认历史。

本轮不改旧 PCK，不新增 native Job/cleanup/实例登记能力，不改 console、codec、policy、native、ledger、CLI。成功是 source-editor 专项的真实生产 worker/消费者链，不是新发行服务端 EXE 正常退出验收，也不是完整派生进程树释放能力。

## 根因与唯一生产变更

亲读 `docs/round54-packaged-server-protocol.md`、原 actualruntime（1,570,590 bytes，按字段精确提取非秘密证据）和原 gateway stdout。旧 shutdown SHA `620b9c7ff62f02cbb25a45f18a6db626f23d720ea987baf277e9a78018efaa76` 与本轮 RED 源码相同。旧 `start()` 只查自身 `_closed`，console 已独立 release 后，该表为空；查询撤销的 token 得 UNKNOWN，报“原生进程句柄不可用，无法确认本次保存”。这不是保存失败，也不能用前半链成功擦掉原 stop 失败。

- `server_room_manager.gd`：仅新增 `current_closed_binding(id)`。只从当前 closed 身份提取合法 request_id，再复用 `closed_binding_for_request`，返回独立副本；不读取 retired 档案、不读取保存状态、不提供保存结论。
- `server_shutdown.gd`：`_inherit_closed_receipt()` 捕获当前 instance/mode，从公开 `console.execute("room … result …")` 获取同一请求完整绑定回执及 `consumption_sha256`；复用 codec 五元绑定和严格 bool `saved_close_receipt`；对已登记房间目录下的精确 response 路径作安全检查和当前 SHA 核对，再公开重读、复验磁盘 SHA/当前实例/closed 身份。只有全部匹配才继承 `_closed` 并跳过旧 worker。
- `_closed_receipt_hashes` 锁定**本 shutdown 首次继承时**的摘要，重复 stop 时改字节即拒绝；不是 manager release 当时的持久摘要，也不是跨进程防篡改能力。第一次继承前的任意合法重写不能凭不存在的原始摘要检测，本轮不扩展 manager/ledger 保存契约。
- 重复 start 仍保持原 `pending` 协调合同；完成信号同一关闭代际只发一次，新实际 close 请求开始新代际。
- 原 `_requests`/poll 保存→退出→release 主链保留。pending 超时不是撤销；不向在途单房 close 重发请求覆盖晚回执。retired 历史仍只供原消费者读取迟到回执，不能被当前关闭身份查询升级为成功。

路径根使用 manager 已登记的房间目录，不新增“目录必须在 storage_root 下”的假设。原持句柄回归夹具合法登记在独占目录但保留默认 storage_root；首版误加该假设导致真实回归 RED，现已修正，不修改旧回归、不放宽链接或摘要闸。

## 真实命令、结果和证据

统一执行器：`E:/Caches/Hermes/cache/scratch/round56-shutdown-handoff-owner/run.py`。官方引擎原件 `D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe`。命令核心：

```
<Godot> --headless --audio-driver Dummy --fixed-fps 60 --path E:/Projects/Godot/FateDominationGame-master --scene res://tests/<suite>.tscn --log-file <E独占日志>
python E:/Caches/Hermes/cache/scratch/round56-shutdown-handoff-owner/run.py red
python E:/Caches/Hermes/cache/scratch/round56-shutdown-handoff-owner/run.py final-main
python E:/Caches/Hermes/cache/scratch/round56-shutdown-handoff-owner/run.py final-pending-verified server_shutdown_close_handoff_pending_test
python E:/Caches/Hermes/cache/scratch/round56-shutdown-handoff-owner/run.py final-regression net_server_shutdown_failure_test
```

每个 Godot 单套上限180秒，顺序执行；TMPDIR/TEMP/TMP/APPDATA/LOCALAPPDATA、日志、配置、恢复存储均为物理 E 独占路径。仅把本次 suspended-root 接入私有诊断 Job，不触碰旧 PID28100；所有执行结束均读取 Job active count。该外层 Job 是测试观察/回收边界，不能冒充生产 C++ Job 能力。

|记录|真实结果|本次 active_owned_processes|
|---|---|---|
|`red/result.json`|14 checks，唯一失败“console close 后仅一次 stop 正常完整完成”，exit1；原错误精确复现|0|
|`green-minimal/result.json`|相同未改14项夹具 GREEN，exit0|0|
|`final-main/result.json`|86 checks，failures=[]，exit0，约19.64秒|0|
|`final-pending-verified/result.json`|36 checks，failures=[]，exit0，约10.78秒|0|
|`final-regression/result.json`|原未改 `net_server_shutdown_failure_test` 161 checks，failures=[]，exit0，约29.37秒|0|

最终三套总计 **283 checks**，严格解析 RESULT、CHECK 数量及 stderr，引擎错误为0；相关源码 before/after SHA 完全一致，三套两个生产文件 SHA 相同。旧回归文件 SHA `dcae086ea696d5193dd9e183a06ce5c4df9cd03c4d84356b1ded0ed8a52ae932`，未修改。

新增测试分别覆盖：

- 生产真实 worker：单房 close 后 release 的 UNKNOWN；保存只为 `room_state_saved=true/saved=false`，不是对局 save；一次 stop、不新增控制请求、恢复字节保留；重复完成信号不重发；query 副本不影响 manager。
- 在真实 response 文件上逐项破坏 room/pid/instance/mode/request、ok/closing/room_state_saved 的字符串/整数、saved 整数、缺保存字段、result 数组；移走完整 response、修改仍含合法保存布尔的真实字节/摘要；旧 instance/mode；每项必须失败且不能建立 `_closed`/新请求。
- 竞态夹具只在真实公开 result 返回后改变同一文件字节或当前 instance；返回内容来自原 console，不伪造成功 response。摘要不一致和重新读回不匹配均失败。
- 正式 recover 创建新 instance/READY，旧保存回执不可借；真实 invalid token → native UNKNOWN；真实 recovery 目标目录冲突产生 worker 最终保存拒绝，worker 保持 running、无 closed proof；撤销自有故障并恢复原 recovery 后 shutdown 自发 close 完成新代际。
- 原受控持句柄 fixture（真实 native spawn、RoomControl/LobbySession，但无完整网络/规则模拟）：真实已保存 response 暂存，worker 自然退出→retired 未确认；无回执和迟到回执均不能继承当前 proof。共享原 pending close、超时保留 running、重试请求编号/文件集合不变、迟到真实回执仍等 EXITED/release。

保留所有中间红项。新 pending 夹具最初仅等 response 存在，原始 `pending-observe` 采样显示 request 文件移除竞态使公开读回“房间管理请求无效”、state=1/verified=true/confirmed=false。修正**新增测试**为原10秒短屏障内继续泵送直到消费者 confirmed；允许超时仍 failed，未改生产预算/消费者，也不把存在性当保存成功。

## 交 main 发行 owner：冻结源码 hash 与新 pack 复验合同

机器可读交接：`E:/Caches/Hermes/cache/scratch/round56-shutdown-handoff-owner/source-handoff-hashes.json`。

|文件|SHA256|
|---|---|
|`scripts/net/server/server_shutdown.gd`|`7526d0b8fd7d427a04a67085f462425f845e883a3210ee8017a0a30963b60227`|
|`scripts/net/server/server_room_manager.gd`|`fadbeb892cfce741d62b95ff1c452d86b883d9a39c811851318d4a97f3799d53`|
|`tests/server_shutdown_close_handoff_test.gd`|`4c64445d1ea86ef5206cafa5fc8c475b66144706d73acdc89cdc2c1719ca06e7`|
|对应 `.tscn`|`8c84d61b261b16bab56d782209bb7aea9b07061c497bf1d47b85fec3d46f57fd`|
|`tests/server_shutdown_close_handoff_pending_test.gd`|`346c320b4e6be2f6d39c6f620de1f4aba79686071e4b91f29c1cff1b4b7f18a0`|
|对应 `.tscn`|`6987ab9046b93ef77353bd879e1e2d1457efdd29414e5e25755ffa864f841a41`|

console/codec/CLI 在 RED 和最终三套 before/after 都未变：console `9eea95ad15fc0f4e04c3d9edfe0071a523e1f44a23558b324ceab818de16da02`，codec `970c86654563b2d3a9b87ded76229bbd6d1466ba3a5ada05a8f5e3d647b91a89`，CLI `8ecc943bd496ef2c85e16e66c3495a6b37b63818d56e94e2e398c0a94ddfaf6a`。不声称其他并发 owner 的整个源树冻结。

新包验收必须：

1. main 冻结以上源码及完整发行依赖，生成新 EXE/PCK/资源 manifest 和逐文件 SHA；不得将旧包验证记录当新包记录。
2. 原包主入口真实 gateway、RSA client、生产 worker；无身份秘密入 argv/报告。正式人数、default selection_mode 和部署 settings15 合同保持。
3. 同一 gateway/room/instance/request：空大厅公开 console close 最终完整回执及当前 SHA，严格 `saved=false/room_state_saved=true`；真实 worker EXITED/exit code 与原 Process handle release 1→0。
4. 已 release 后在**同一 gateway**执行一次正式 stop，消费完整 stop-status/失败明细；必须 `SERVER_STOP_COMPLETE`、gateway 独立 GetExitCodeProcess=0，并记录本次自有进程 active0，不能以 `ok=true/stopped=false` 冒充完成。
5. 新包单独补拒绝回执/UNKNOWN、pending 晚回执不覆盖、新 recover instance 不借旧 proof。源码专项不代替正式包该链。
6. 没有完整 production Job 方法合同时只报告单进程 handle 释放和本次诊断 Job；不报告所有派生进程清理或完整 registry/file-exclusive proof。

## 旧网关 PID28100：精确只读证据与独立管理员处理缺口

收尾精确只读记录 `E:/Caches/Hermes/cache/scratch/round56-shutdown-handoff-owner/legacy-gateway-readonly.json`：

- PID **28100** 仍活，ParentPID36196，EXE `E:/FateCandidates/round52-current-roles-20261010-sa1/artifacts/server/FateServer.exe`。
- Win32 CreationDate 精确 `/Date(1791600644040)/`，CommandLine 与原件 deployment/engine-log 路径对应。没有按名字认领/杀进程。
- 旧 worker PID25640、instance `2cd94756465e85782cc110fc6cd0938b`、room `2c9ddf5fa6f97659185b336d7441dbfa`、request `9d9c584f9be8e6b862cafd156ba39f3b`；原 actualruntime exit0 和 handle1324 前1后0已亲读。
- 同 req 当前磁盘完整保存 response SHA `8077859a265d12310d29d58c8de78aca2364bcf05d07d8caccdb034a0a266ca4`，仍 `ok=true/closing=true/saved=false/room_state_saved=true`。
- recovery 仍存在，SHA `70241146e8589795d5f5d84eebb9e9da264a7ff4e715c12212d11e2898f12964`。原 stdout SHA `c8e11d9e00363d2a132b6104dc036d06448b33497ee4f5b5f88161d7194b9b24` 未变，原唯一 stop 失败保留。

**没有执行第二次 stop、forcekill、删除回执/存档/目录或撤销旧登记。旧 gateway 为 notowned cleanup scope，仍交 main 保留。**

独立管理员的非破坏性方案必须与修复验收分开：先获当前管理员显式授权，读取上述保存回执/摘要、closed 身份、worker EXITED/release、当前 instance 未变；仅撤销旧房间**内存活动登记**，再执行一次管理员正常 shutdown、观察 gateway exit0。旧 manager 原件793–807行的 `stop_room(id,-1,instance)` 有此纯登记分支，PID=-1 时不 terminate、不删目录。但是：

- **旧包没有暴露这个可信管理员操作入口，故当前不能给出可执行的独立正常关服命令。** 单独启动新 manager 或改磁盘目录不会撤销旧进程内存登记；不得伪造可用方案。
- 亲读旧 console 原件404–412行：`room <id> forget <request>` 删除 response 和 retired 记录，不是忘记房间登记，不能用它解决旧 stop，反而会删保存证明。本轮明确不执行。
- main 若持有受支持的可信进程内管理通道，须先确认上述条件和授权，再精确调用纯登记分支；否则保持旧 PID，单列“旧包缺管理员 unregister-saved 入口”阻塞项。新包修复不回写旧运行实例，也不以旧网关最终管理员处置掩盖原失败。

## 文件、清理与未验项

唯一生产写入：`scripts/net/server/server_shutdown.gd`、`scripts/net/server/server_room_manager.gd`；新增上述两套 `.gd/.tscn` 和本文。scratch 保留诊断执行器、原始日志、结果、真实自有恢复原件和 hash 交接，不进包。tests 被现有 gitignore 忽略，已按字节 SHA 核对；未强制 add、提交或推送。

`git diff --check` 对两生产文件通过。manager 原有其他 owner 修改并未归本轮所有，本轮仅加8行公开 query。本次执行器各次 Job active0；这与仍活的旧 gateway28100 明确分开。

未验/待 main：新 pack 发行链、正式 release client GUI、多机/跨网、中局对局保存恢复、完整 native Job/cleanup 能力；旧网关受支持的独立管理员正常 shutdown 入口仍缺。
