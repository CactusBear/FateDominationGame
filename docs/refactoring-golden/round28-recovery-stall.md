# Round28 — 恢复续行停滞观测（未完成终局验收）

## 结论

- **未定位 round27 的 seq41/42、decisions5/8 持续不变根因，不能宣称修复或完整恢复通过。** round27 报告已读，但其声明的 `E:/Caches/Hermes/cache/scratch/round27-restore-broadcast/run.py` 及该运行目录当前不存在，无法重放那次原局；本轮均为实际新录制的独立 worker 对局。
- 三次进入恢复续行的实际运行均持续推进：observable-red-2 与 short-stall-red-2 到 round5；最终 stage-observable 到 round7/action、seq320/321、decisions49/57。连续12秒无镜像/决策/组预览/pending变化的诊断未触发。不能将瞬时 `sent_seq == seq` 当作永久 Agent 锁。
- 最终运行的所有进度样本 `stale_receipts=0`、`battle_broadcast.pending=false`；真实 active_choice 曾出现并随后推进。**这批运行没有支持“stale拒绝被锁死”或“播报屏障卡住”的实证，但也没有排除 round27 原失败中的这些原因。** 没有猜测性修改 Agent、authority 或引擎。
- 最终运行外部 TIMEOUT180，未取得终局、最终管理save回执、终局尾hash对照；原三项断言全部保留，仍然红。仅证明真实恢复续写：Godot Journal 原读取器审计原档19条、新档126条，ok=true、truncated=false，完整sha256/尾hash在 `journal-audit.log`。

## 修改及耦合审查（仅本代理拥有文件）

仅修改 `tests/lan_restore_live_test.gd`，未修改另外三个拥有文件；Session、引擎、manager均只读。

1. 续行进度记录明确拆开 seq/sent_seq/decisions、observer/current_player、真实pending、broadcast、actions和group。既有stale精确理由消费仍保留；不将业务拒绝一律忽略。
2. 新增12秒连续**无任何观测变化**的短失败诊断，写出 `stall.json` 后走原cleanup；没有延长180秒外部上限，没有改变规则、回合、对局胜负或正式版本校验。此门是测试诊断，不是产品性能结论；这批实际续行从未触发它。
3. `installed_materials` 仅保存同客户端、同一次测试已经正式安装的目录及完整清单，不保存规则状态或镜像。当前清单完全相同才复用；不同清单仍走原Sync下载/组装。
4. 复用仍调用正式Assembler.validate，逐文件cache.fetch及内容digest、磁盘文件长度和sha256验证，然后正式install_room_assets；当前修订ACK由原门控制。复用恢复revision2时依然扣住客机ACK，全部ACK后才发布playing；没有复写整份材料，也没有直接伪造sync.complete。
5. 六类负向投影 rule/observer/privacy/asset/reference/barrier 在最终实际原局/恢复局均通过；本人观察席、暂停不继承、私有手牌持续检查及客户端不运行规则断言均保留。

补丁语义（V4A）：在变量区添加材料索引；在install_data入口添加“相同清单→正式校验→实际cache/disk验证→正式安装→按需ACK”分支，并仅在原安装成功后登记索引；在continue_to_end添加观测签名、失败证据和更完整进度字段。没有替换原终局/save/hash条件。

## 实际执行

独占物理根：`E:/Caches/Hermes/cache/scratch/round28-recovery-stall/`；每次目录新建拒绝覆盖。

```text
python E:/Caches/Hermes/cache/scratch/round28-recovery-stall/run.py <标签>
D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe
 --headless --fixed-fps 60 --path E:/Projects/Godot/FateDominationGame-master
 --scene res://tests/lan_restore_live_test.tscn
```

APPDATA、FATE_TEST_SCRATCH_ROOT、HERMES_LAN_RESTORE_LIVE_ROOT全部设为该次E盘根。真实 `appdata/FateDomination/logs/godot.log` 已生成，证明Godot的user数据落在E盘；没有窗口或用户交互。每次保留stdout/result/source-hashes/owned-ready。

| 标签 | 实際结果 |
|---|---|
| observable-red | exit1，72.66s；恢复新worker房主身份就绪失败 |
| observable-red-2 | TIMEOUT180，180.02s；恢复续行到round5 |
| short-stall-red | exit1，18.77s；原worker房主身份就绪失败 |
| short-stall-red-2 | TIMEOUT180，180.01s；恢复续行到round5，短停滞门未触发 |
| material-reuse-stall | exit1，16.31s；原worker身份就绪失败 |
| material-reuse-stall-2 | exit1，98.96s；复用revision1成功，恢复IPC回执未完成，close回执也失败 |
| material-reuse-stall-3 | exit1，76.37s；恢复客机已authenticated/connected，但房主报连接中断 |
| stage-observable | TIMEOUT180，180.02s；65项CHECK为true；两客户端revision1/2均复用204文件，六反例及ACK门通过，续行round7 |

最终真实worker段计时：replay_begin17721763→replay_end28556755微秒；save_restored_begin28556967→30680791；resume_recording_begin30680963→31179352。仅定位开销，不把性能段当停滞根因。

**版本注意**：本轮source-hashes显示authority/game_progress/Agent各只有一个hash，但Session出现两个hash（本代理未写）。因此早晚运行不能拼成同一冻结版本完整验收；最终stage-observable以自己的source-hashes为准。

## 归档及交接

- `journal-audit.log`：真实Godot读取13份match.log，exit0，全部ok=true且未截断；原档、新档和恢复冻结日志保留。
- `owned-cleanup.json`：本代理已知父进程/ready绑定PID共11项均精确查回verified-absent；未按进程名批杀，没有触碰其他进程。
- `released-owned-artifacts.json`：先保存逐文件大小/sha256，再删除本轮自己的cache/client、worker运行data/cache、恢复冻结副本data；释放13048文件/6133656272字节，目录删除读回通过。正式原档及续写档data、日志、回执、comparison保留；没有创建仓库冻结副本。
- `git diff --check -- tests/lan_restore_live_test.gd` exit0；未提交。
- **精确剩余交接**：必须找回round27失败原档/真实日志或新的12秒stall.json；收到失败时先看当前行动者sent_seq、确切拒绝收据、pending归属与broadcast确认资格，再对照最后真实journal动作。当前没有足以判定引擎缺陷的证据。身份就绪/IPC恢复回执间歇失败属于不同前置故障，不应冒充round2停滞修复。
- 必须继续在同一180秒上限内完整终局、最终管理save回执及尾hash对照；本轮没有达标，没有减少规则、跳终局或以新增日志伪过。
