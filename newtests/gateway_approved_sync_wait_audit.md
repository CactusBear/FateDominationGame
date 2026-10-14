# gateway restart：approved client files 断言定性

## 结论及边界

**本次委派所指原失败属于 (a) 夹具的总等待前提不成立。** 不是批准文件真正缺失或哈希不一致。只改 `tests/net_server_match_test.gd` 的等待预算；生产代码未改。**不宣称 restart 套件全绿。** 最新无节流样本出现另一首因（第二客户端收到“所选房间已经停止或实例校验失败”），本任务未追查其产品/环境归属。

## 断言原文、位置与判据

修前 `tests/net_server_match_test.gd:81–83`，修后 `:84–86`（restart 通过 recovery_midmatch → recovery → match 继承此 run）：

```gdscript
var accepted: bool = sync.complete and sync.error.is_empty() and agents[index].session.error.is_empty() and agents[index].session.install_room_assets(root)
if not accepted: sync.cancel()
check(accepted, "all approved client files assemble and verify before ready")
```

- 它不是 worker READY 断言，也不只测 assembler：同时要求全部下载/组装完成、同步器及会话无错、逐文件安装成功。
- 输入是两名客户端各自收到的 `session.room_files`（path/hash/size），不是本机随便扫描的所有文件。worker `server_room_worker.gd:155–168` 扫描已授权 server 数据根，选取非 command_spells 条目，加 card_backs、command_spells 及 selection_modes.json 基础文件，经 RoomDataPlan 合并/依赖/路径冲突校验；`:184–219` 缓存、组装和校验。
- `room_data_plan.gd:22–34` 为条目生成 category/provider-hash/key-hash 相对路径并合入基础文件；`lobby_session.gd:1259–1283` 仅发布已登记 blob 的匹配长度清单，并产生新 data_revision。
- 同步器 `room_data_sync.gd:78–86` 等所有文件就绪才组装；assembler `:84–105` 复核长度/哈希、写后再哈希，`:70–81` 只发布完整目录。`room_assets.gd:20–50` 安装时再次逐文件复读校验，全部通过才提交路径表。
- 修后 `net_server_match_test.gd:92–93` 才发 data_ack/ready；生产 `lobby_session.gd:604–607` 显式拒绝未安装资产的当前 revision ACK。因此这里的 ready 指客户端准备，而不是此前已完成的 worker READY。

原失败冻结的批准输入为 **204 文件 / 95,949,242 bytes / 203 唯一 hash**：situations 26、servants 40、masters 46、events 32、attacks 48、card_backs 9、command_spells 2、selection_modes.json 1。worker 数据树另有生成的 tag_list.json，不属于本次同步清单，不能算成 205。

## 首因证据

原始日志：`E:/scratch/e08-e12-budget-rerun-job0-20261011/net_server_gateway_restart_test/evidence/scene.stdout.log:6–12`：worker ready、RSA/native ownership、sync.begin 均 true；原断言 false；紧接 `SYNC_ERROR  session=` 两个错误字段均为空。

原夹具 `net_server_match_test.gd:77–80` 给整个清单固定 45000ms。同步器成功后 complete=true；内部失败会经 `_fail` 设置非空 error；此局部 sync 没有其他取消调用者。结合下面原现场实物，原失败是 **45000ms 截断仍未完成的下载**，尚未进入最终组装/安装。

原现场 client-cache 有 197 个完整 blob，逐个 SHA256=文件名、无坏哈希；还差以下 6 个批准文件：

- selection_modes.json
- card_backs/servant_card_back.png
- card_backs/situation_card_back.png
- card_backs/skill_card_back.png
- card_backs/upgrade_skill_card_back.png
- command_spells/normal_command_spell.json

这 6 个文件在原 worker 固定数据副本中真实存在。该副本的 204 个批准文件与本次诊断运行成功安装的 204 文件，按相对路径/大小/SHA256 **完全一致**。见 `historical-input-evidence-final.json`。未保存原失败活体 offset，所以**无法断言当时具体负载、吞吐下降或最后一块的时序原因**；受控节流只证明预算机制，不能反推历史主机负载。

### 生产显式声明（不是拿 startup_seconds 偷换同步预算）

`room_data_sync.gd:5`：`var timeout_seconds: float = 30.0`。
`:89–95` 观察当前 blob pending offset，offset 变化则刷新 `_last_progress`，仅在 **无进度超过 timeout_seconds** 时失败。正式 `lobby_screen.gd:132–143,149–157` 连续 poll 并以 complete/同 revision/install 成功为准，未声明“整张清单 45 秒必须完成”。本次没有复用启动阶段的 600s 作为内容同步期限。

## 它以前为何不报

- 就本轮“启动预算修复前”的失败：`E:/scratch/isolated-e08-e15-83aeaf0d2b69455d9a7a035f7375b244/evidence/net_server_gateway_restart-attempt1.stdout.log:10,17` 停在 room worker starts=false，代码 `net_server_match_test.gd:48–53` 清理并 return，**根本未到 :83**。
- 两次输入冻结全量比较（排除 .godot）仅不同 `tests/round36_gateway_fixture.gd` 和 `tests/room_data_preparation_consumer_test.gd`，生产及本断言文件未变。见 verification-summary.json。
- 不能泛化成“以前从未过”：同生产冻结、仍用原 45000ms、仅加只读采样的 diagnostic 本次两客户端原断言都 true（204/204）；此前 `E:/scratch/e08-e12-budget-rerun-20261011/net_server_gateway_restart_test/evidence/stdout.log:11,13` 也都 true。它是依赖实际耗时的夹具假红，不是恒定产品缺失。

## 唯一夹具修改

`tests/net_server_match_test.gd:77–80`：用同步器本身的 30s 声明 × 已验证清单文件数计算**有限的测试总等待上界**，保留原 45s 下限；本输入为 6,120,000ms。此乘积是测试的有限保守预算，不声称是生产吞吐 SLA。同步器真实无进度 30s 失败仍生效，原四项 accepted 判据及 ACK/ready 顺序不变，未删断言或改成恒真。

修前 SHA256：`ab91d362dbc7588bc2c8fc5e3df796b02e2d7718bb79bd4b05a2a9a11b854e7d`

修后 SHA256：`a3dedfd5e6d886d1df47fb0478956f132173d58c770b4e480a3bc66959ec020c`

## 故障注入及即时恢复

独立副本保持真实 gateway/worker/下载/哈希/安装，只在客户端0两次 sync.poll 之间让时间经过至少250ms，期间持续 pump 网关及双方，未注入错误文件或跳断言。

- paced-legacy-v2：原45s预算 → 唯一失败即原断言；88/204、running=true、deadline_reached=true、最后进度距今257ms、双方错误为空。
- paced-fixed-v2：只换预算 → 两客户端204/204，原断言均true。稍后 data barrier/worker退出导致套件红，不能冒称整套绿。
- 在上述 **同一个 paced-fixed-v2 项目** 只回退预算重跑：原断言再次为唯一失败，71/204、running=true、deadline_reached=true、最后进度距今254ms、错误为空；exit1、CHECK12。
- finally 立即恢复原字节：回退前/恢复后 SHA 均 `fca632eacb384d98fecc37c192012e6826343a8f9c660829cc4ff55f3b382bd5`；临时回退 SHA `94ee9ef0243785dd0479920525da57c70f6a11ad408092ab4cf0b93d7c0fdf4e`。见 rollback-receipt.json。
- 后续清理阶段再从各自无观测基准恢复所有独立项目中的采样/节流，逐文件比对基准SHA（见 instrumentation-restoration.json）；原仓从未加入这些临时注入。

首次 SceneTreeTimer 节流样本（paced-legacy）没有形成目标期限截断，而在第二客户端收到断线后失败，**不作为回退红证明**。已保留原始失败，改用单调墙钟持续pump节流后得到上述有效对照。

## 实际结果（CHECK 数=实际输出条数，不按标签去重）

| 运行 | CHECK true/false | 原断言 | exit | ERROR | Job ActiveProcesses |
|---|---:|---|---:|---:|---:|
| 原问题历史记录 | 11/1 | false | 1 | 0 | 0 |
| diagnostic 原预算 | 41/5 | true / true | 1 | 0 | 0 |
| paced-legacy-v2 | 11/1 | false | 1 | 0 | 0 |
| paced-fixed-v2 | 12/3 | true / true | 1 | 0 | 0 |
| 同副本预算回退 | 11/1 | false | 1 | 0 | 0 |
| fixed 无节流 | 11/3 | true / false | 1 | 0 | 0 |

全部运行 `--headless --fixed-fps 60`、独占E scratch、TMPDIR/TEMP/TMP/APPDATA/LOCALAPPDATA 在E、外层看门狗1200s、Windows Job Object管理。未对 PID17120/28100执行任何操作。

**最新 fixed 原断言第二次失败的首个已知差异**：client0 complete=true/204并通过；client1只1/204时 session_error=`所选房间已经停止或实例校验失败`、deadline_reached=false。这不是原来“错误为空、45秒截断”的分支。未修该分支，未宣称产品缺陷或环境无责；恢复/续局/终局保存及窗口/多机均未验收。

## 证据、命令及保留范围

最小非凭据证据归档在 `newtests/gateway_approved_sync_wait_evidence/`：每次原始stdout/stderr、receipt、两份输入/汇总证据、rollback receipt、注入恢复hash。活体阶段没有增加文件树归档器；仅所属Job退出后读历史/本次输出。

原始自有运行目录：`E:/scratch/gateway-approved-triage/`。

```text
TMPDIR=E:/scratch TEMP=E:/scratch TMP=E:/scratch python -B E:/scratch/gateway-approved-triage/run_triage.py diagnostic
TMPDIR=E:/scratch TEMP=E:/scratch TMP=E:/scratch python -B E:/scratch/gateway-approved-triage/run_triage.py paced-legacy-v2
TMPDIR=E:/scratch TEMP=E:/scratch TMP=E:/scratch python -B E:/scratch/gateway-approved-triage/run_triage.py paced-fixed-v2
TMPDIR=E:/scratch TEMP=E:/scratch TMP=E:/scratch python -B E:/scratch/gateway-approved-triage/run_rollback.py
TMPDIR=E:/scratch TEMP=E:/scratch TMP=E:/scratch python -B E:/scratch/gateway-approved-triage/run_triage.py fixed
```

runner 拒绝覆盖已有目录；证据冻结的精确生产源码未受本任务修改。最新证据仍是整套 FAIL，不应与目标预算机制证明混为 PASS。
