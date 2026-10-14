# Round75：单次 LAN 生产入口取证——启动前置失败，后续未知

## 结论

本次没有完成双客户端端到端。首个分歧位于 `original_host_join`：真实 manager 已创建独立 worker，worker 最后记录 `SERVER_ROOM_STARTUP stage=blob_publication result=1`，没有对应 `result=0`，随后 manager 原 30 秒启动期限到期、READY 文件仍缺失。首错后没有重试，没有进入客机加入、内容批准、选人、对局、保存或恢复。

最后成功的 worker 阶段是 `selection_configuration result=0`；最后成功的夹具检查是生产 `host_client.start()` 返回 `OK=0`。这些不等于房间 READY 或双客户端连接通过。

**收尾仍有保留进程**：本次 Job 从 2 降至 1，worker 已离开 Job，但客户端夹具主进程 PID **21940** 仍运行；runner PID **18520** 仍观测。观测到 674.203 秒时仍是 `root_exit=null, ActiveProcesses=1`。没有伪造退出码，没有清理运行目录，没有人工强杀。后台会话 `proc_f5824b007def` 交给父代理保留观察。

## 交付与冻结

- 续用并修改：`newtests/round75_lan_once_test.gd`。
- 场景未改：`res://newtests/round75_lan_once_test.tscn`。
- 新 runner：`newtests/round75_lan_once_runner.py`。
- 独占证据根（下称 `$O`）：`E:/scratch/round75-lan-once-52a9757186764a3b95da6a5b01e457d8`。
- 实际工程：`$O/generated/project`；实际 EXE：`$O/generated/Godot.exe`。
- 原始证据/清单：`$O/manifest.json`、`$O/evidence/`；冻结副本和全部运行材料保留。
- 两客户端设计为一个 parent engine 内的两个生产 `LobbySession` 和独立 ENet 连接，权威为真实独立 worker。不是两个独立客户端 OS 进程，也没有 GUI/发行 EXE 窗口验收。本次在 client 连接前失败，不能声称真实双 ENet 客户端链已通过。

生产 manager/gateway/Session/worker/DLL 均未修改。冻结使用当前工作树，不是旧 PCK。只在副本关闭 editor VCS 自动启动；业务运行不使用 editor 场景。主命令均带 `--headless --fixed-fps 60`。独立 worker 的参数由原生产 manager 生成，未为了夹具插入 flags 或改生产期限。

APPDATA/LOCALAPPDATA/TEMP/TMP/TMPDIR 均显式位于 `$O/generated/env-<phase>/` 下。运行日志实际 `OS.get_user_data_dir()` 为 `$O/generated/env-record/appdata/FateDomination`。本次 UDP 探测结果外部端口 54000、manager 内部候选 54001/54002。没有操作 PID17120/28100，没有全量或测速。

夹具修正：用生产 `player_identity.open()` 创建/重用私有身份，而非上一夹具 4096 位 RSA（生产协议 `KEY_BITS=2048`，4096 位签名不匹配其固定验签长度）；将录制与恢复拆为两个显式进程阶段，公开对账材料用 `store_var/get_var` 保留整数类型；正常关闭只等待原 process_frame 泵送，不另行双重调用 `_drain_close`。密钥只由生产身份代码内部使用，工具未读取/打印密钥或恢复票据。

## 真实命令与退出

工作目录均为 `E:/Projects/Godot/FateDominationGame-master`。

```text
python newtests/round75_lan_once_runner.py prepare
python newtests/round75_lan_once_runner.py import E:/scratch/round75-lan-once-52a9757186764a3b95da6a5b01e457d8
python newtests/round75_lan_once_runner.py record E:/scratch/round75-lan-once-52a9757186764a3b95da6a5b01e457d8
```

prepare exit0。import runner exit0，真实 engine PID37868 exit0，Job ActiveProcesses=0，130.789 秒；日志无 ERROR/SCRIPT ERROR。导入是必要资源准备，不算一次业务阶段重试。

实际 import engine 命令：

```text
E:/scratch/round75-lan-once-52a9757186764a3b95da6a5b01e457d8/generated/Godot.exe --headless --fixed-fps 60 --path E:/scratch/round75-lan-once-52a9757186764a3b95da6a5b01e457d8/generated/project --editor --import
```

实际 record engine 命令：

```text
E:/scratch/round75-lan-once-52a9757186764a3b95da6a5b01e457d8/generated/Godot.exe --headless --fixed-fps 60 --path E:/scratch/round75-lan-once-52a9757186764a3b95da6a5b01e457d8/generated/project --scene res://newtests/round75_lan_once_test.tscn
```

业务入口实调：`authority_host_client.start(session0, "R75-ONCE-LAN-original", settings, "lan", 54000, "127.0.0.1", null, <runtime>/original/workers)`，返回0；原 `server_room_manager` 的原生 owner.spawn 创建 PID21600，实例 `c3b8bc909c30f2c5097c39b6e3dc0a6e`，room `cc00403a33c0c2a156cb5a42f823d530`。没有持有 worker 的独立 runner 句柄，**worker原始退出码未知**；不能将 Job 活动数降低当 exit0/正常关闭。worker完整 argv 没有 OS 取证，参数生成代码位于冻结 manager.gd:495，不把源码重建命令冒充实际采样。

| 阶段 | 实际命令/回执 | exit / RESULT | Job 与结论 |
|---|---|---|---|
| 准备 | runner prepare | exit0；无 RESULT | 未运行业务 |
| 导入 | 上述 import engine | exit0；无 RESULT；无脚本错误 | Active=0，已完成 |
| 建房及房主接入 | host.start返回0；等待原 worker READY/成员/身份 IPC | parent exit未知；该检查失败 | Active 1→2→1；未 READY |
| 客机加入 | `sessions[1].join` 未调用 | 未尝试 | 首错截断 |
| 内容同步/批准 | catalog/prepare/commit/data_ack/ready 未发送 | 未尝试 | 首错截断 |
| 选人/进入对局 | start/choose_master/begin_match 未发送 | 未尝试 | 首错截断 |
| 超过第1回合 | match_command 未发送 | 未尝试 | seq/actor/round 均null |
| 保存/正常关闭 | save 未调用；cleanup host.close 调用一次，未取得 request_id | 正常关闭未证实 | Active=1，未 strong kill |
| 重启/存档恢复 | restore 进程未启动、restore_local_match 未调用 | 未尝试 | 首错截断 |
| 状态对比 | 未产生保存或 comparison.json | 未尝试 | 序号/行动者/玩家/卡区等价均未知 |

record parent stdout 真正打印：

```text
RESULT checks=8 failures=["房主 worker READY、真实成员及身份 IPC","首错后仅正常关闭，不强杀"]
```

这不是 exit1 或进程退出证据。夹具 `finish(false)` 保留主进程，`final.json.exit_proven=false`，runner 尚未完成，manifest 的 record 结果尚无最终条目。report 不把缺失最终条目当通过。生产 `request_completed` 收据0条，业务 `requests` 0条。

## 首分歧与证据行

`$O/evidence/record.stdout.log`：

- L15：实际 engine/project/user 路径、随机预检声明 true/15秒、外部端口54000（尚未运行预检）。
- L16–18：host.start返回0 / CHECK true生产 manager启动。
- L19–48：两端 connected=false，seq/actor/round=null，pending/actions为空；这只是未接入，不是恢复停滞。
- L49–50：首个 CHECK false；夹具同进程 ticks=49033。host.start返回 ticks=18901，到首错 **30132毫秒**，此差仅属 parent 时钟，不是 blob_publication 耗时。
- L52–55：cleanup host.close 请求号为空、response=null、confirmed=false。
- L56–57：上述 RESULT / exit_proven=false。

`$O/evidence/first-failure.json` 原 manager_error：

```text
房间启动超时；stage=startup_deadline role=--server-room-worker room=cc00403a33c0c2a156cb5a42f823d530 pid=21600 instance=c3b8bc909c30f2c5097c39b6e3dc0a6e mode=lan native_state=RUNNING ready_report=missing report_path=E:/scratch/round75-lan-once-52a9757186764a3b95da6a5b01e457d8/generated/runtime/original/workers/cc00403a33c0c2a156cb5a42f823d530/ready.json
```

worker 原件：`$O/generated/runtime/original/workers/cc00403a33c0c2a156cb5a42f823d530/engine.c3b8bc909c30f2c5097c39b6e3dc0a6e.log`；归档：`$O/evidence/record-worker-engine.log`，共42行：

- L20–27：cache_population/data_assembly/data_validation/fixed_source_registration 均记录调用完成。
- L28–37：process_content/content_environment/rules_reload/roster/host 均完成。
- L38–41：recovery_binding、selection_configuration 完成。
- L42：`SERVER_ROOM_STARTUP stage=blob_publication result=1`，整份原件到此，没有 blob result0、room_asset_installation、ready_publication 或 SERVER_ROOM_READY。
- 无 SCRIPT ERROR、Parse Error 或 ERROR 行。标记本身不包含时间或逐文件完成数，不能推算停在哪个文件，更不能证明死锁。

Job 原件 `$O/evidence/record.job.jsonl`：root21940；首次 Active=2 为 runner单调19.603秒；49.639秒时从2降1；49.819秒读到首错与cleanup/finished事件；674.203秒仍Active=1/root_exit=null。时间来自 runner，不能与 worker未记录的 ticks 做跨进程减法。

stderr `$O/evidence/record.stderr.log` L1：`WARNING: 权威关闭句柄不可用；保留子进程与目录，不伪报已关闭`，栈为生产 Host.close:268 → fixture.normal_close:278。没有把警告省略后声称成功正常关闭。

## 最小因果与仍未知

**已证实的最近因果**：默认启动期限先于 READY，manager 报 startup_deadline；冻结 manager.poll:564–570 随即走原 `_terminate_process(room)`。Job 活动数随后减少，说明 worker 已离开本次 Job。**本次 worker 非通过正常保存关闭退出**；runner/夹具未人工 kill，但产品原启动失败分支确实包含原生 terminate，不能把这点隐藏成“全程自然退出”。

**最小候选**：worker 未完成的范围缩小到 blob_publication 循环（冻结 worker.gd:263–267：cache.fetch + session.publish_blob）。循环工作在30秒门槛内未完成、底层IO阻塞或其他原因均有可能；未记录每次调用及其耗时，故更深根因 **unknown**。不猜 timeout，不扩大 startup_seconds，不改生产。

已排除/未支持：不是 spawn能力缺失、路径入口拒绝、配置读失败或脚本解析错误；worker 已实际执行至上述阶段。最后标记排除了“从未进入_ready/只banner”的历史假设。本轮没有RSA拒绝、内部route已attach、ACK、真实pending、播报或对局命令证据，这些不能用于解释首因。recovery_save_diagnostic 未触发，因为尚未进入保存；未知不能写成native_commit失败。

cleanup CHECK 不是第二个业务根因：Host.close需生产 manager.hold_process_supervision 对 RUNNING实例返回true；此时 Job已有worker消失，请求号仍空。夹具保守 `finish(false)` 不退出，形成当前保留主进程。没有正常保存证据，不能以进程不存在/新目录存在替代。

后续夹具边界也未运行验收：初始化房间显式 random_sim_enabled 时生产 worker 不在批准前发布 room_files，当前 guest等待条件却包含非空room_files；未来如获授权重跑，应先静态修正该未触达前置条件。此次没有为它追加一轮或修改冻结。恢复等价比较的合法ID映射、资产哈希、序号差异门同样未证实。

## 指纹与保留

已工具对账：下列实际冻结 SHA 与当前仓库对应文件一致；`git diff --check -- <两测试文件>` exit0。其余工作树已有修改未动。

| 文件 | SHA-256 |
|---|---|
| 实际 fixture .gd | 7bec4cf2b0b9092fb16a401a7661ca28cbd58a60ccaf7dc9587548cb93f45276 |
| runner .py | ecf997c2c1aa04a10bc03f9d65b70543f2c4e7dc32b2f75e4160b322a6eeb84f |
| worker.gd | a1d935675ce6d6a3f804ac9000104b15d95c2c279c8cf13c459acdd3920107eb |
| manager.gd | ea4f181aacb86400ec4c46143298cf7edab3ceed952a1ba12ba78ef81f9123e4 |
| 正式 Windows DLL | 92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd |
| first-failure.json | 151affb9df564b3ce60b30ce7e29a38ead804c1e645a9240153a933af11c3cf0 |
| final.json | 3e80488bfe827c237fa0d23bb05d0bbac89f86c8cd7c592ac5b89a95491d6bd0 |
| record-worker-engine.log | 40321770a86531ecbaaa3462be6794a45c6007a85f0f9f0ba9483fd105564e16 |

runner 每阶段先建 exclusive attempt.lock 再 spawn，拒绝覆盖原证据。Job取消 KILL_ON_JOB_CLOSE；从未调用 job.stop/proc.kill/TerminateJobObject。1200秒仅是外层观察上限触发一次stop-normal.request，不改任何产品期限；finish(false)后的主进程不会消费该文件，故不把它作为已完成关停。当前无安全root退出入口证据，保留而非强杀；不要删除 `$O`，不要新启动restore或自动重跑。
