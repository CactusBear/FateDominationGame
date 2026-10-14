# Q01：显式管理员紧急强停

已实现独立可信本机控制台命令，不改游戏内 UI，不改 `lobby_session.gd`，不改正常保存关断、期限或默认自动触发策略。

## 用法与现有惯例

现有 `--server-console <console_dir>` 控制台中输入：

```text
room <id> emergency-stop <pid> <instance_id> --confirm-unsaved-risk '<reason>'
```

PID、实例和原因均由调用方提供。实例从本机当前房间登记/就绪报告读取，不能复用旧实例。控制目录应维持现有可信本机权限；远端管理员经 `execute(..., false)` 也不能调用该命令。未确认风险、原因空白、审计目录未配置、旧绑定或未知原生所有权均拒绝。

定位到的现有原语：
- `server_console_channel.gd` 的 `commands` 白名单与本机 instance+command 文件信封；`server_admin_request_codec.gd` 已支持 `room <id> <action>`，无需新增解析器。
- `server_console.gd` 既有 stdin→本机信封前端；`server_cli.gd` 已 configure 同一 Channel，因此新命令自动进入服务端控制台。
- 正常 close 仍走 `_room_request`、关闭监督、绑定回执及原生 EXITED/release；保存证据仍由 `saved_close_receipt` 的明确布尔字段提供。
- 新 manager 单动作原语只校验当前绑定、复用创建时的原生句柄 terminate 并核对 EXITED；不保存、不 release、不删房间登记。

先将审计 intent 写入并逐字读回，才执行强停；结果另写 `.result.json` 并读回。日志标签为 `SERVER_EMERGENCY_STOP_INTENT/RESULT`。文件位于 `<console_dir>/emergency-stop/<audit_id>.intent.json` 与 `.result.json`，记录确认、原因、来源、完整实例和结果。即使强停成功，`saved=false`、`save_confirmed=false`，提示“紧急强停可能丢失未保存进度；未确认保存成功，不视为已保存”。既有存档、失败回执和登记不删除；句柄后续仍由既有生命周期消费者处理。结果落账失败返回失败并保留已观察到的进程结果及 intent，不伪造保存或回滚。

## 本轮最小改动

生产仅 `scripts/net/server/server_console_channel.gd` 与 `scripts/net/server/server_room_manager.gd`。专项新增 `newtests/net_emergency_stop_test.gd`、同名 `.tscn`、`newtests/run_emergency_stop.py`。

本轮相对接手工作树的完整 minimal diff：`q01-explicit-admin-emergency-stop.diff`，不是相对 HEAD 的其它代理混合 diff。原生产基线 SHA256：
- console：`afbfd5a071a2fcb062555f00fcd9ac08dbe476a04ad3fd6efc2c7142373af3c3`
- manager：`ea4f181aacb86400ec4c46143298cf7edab3ceed952a1ba12ba78ef81f9123e4`

最终代码 SHA256：

| 文件 | SHA256 |
|---|---|
| scripts/net/server/server_console_channel.gd | 18a3926a755a5cdc0e48a32c168bce7b8c03a9b90fbe81fa5946a7412fee4116 |
| scripts/net/server/server_room_manager.gd | 86fd5726bcdca4ecbcf8ac7577fdc90200afa3c30c770c0a37d815cdf52a18fd |
| newtests/net_emergency_stop_test.gd | c6f87e4a8ef7e121a4d81d2945c65d7a100ad84e941bca5855b6c8223911fe05 |
| newtests/net_emergency_stop_test.tscn | 6a71336e379157a18664736a2b6c59ac601e82114c2a5aac862201aba4aaf6d8 |
| newtests/run_emergency_stop.py | 9db79acd2c45979f64d240e93efafa1a4648c018f205e64cacb3eeeab64dc0af |

## 真实执行结果

```text
python newtests/run_emergency_stop.py --godot E:/scratch/adapter-lifecycle-contract-20261010-r2/generated/Godot.exe --root E:/scratch --timeout 600
CHECK=48，全 true
RESULT checks=48 failures=[]
exit=0
ERROR/SCRIPT ERROR/SHADER ERROR=0（包括实际 worker 自己的日志）
Job ActiveProcesses=0（import、路径探针及专项全部观察到 0）
git diff --check=0
```

覆盖：可信本机实际命令文件投递→console.poll→真实自有 worker 强停→原生句柄 EXITED→intent/result 审计读回；未确认/缺原因/空原因/无审计配置/远端/旧 PID/旧实例/伪 token 拒绝；真实 LobbySession 未录制对局正常关闭拒绝且保持存活、无命令的 poll 不自动强停；强停不伪造恢复文件、不改失败保存回执字节；同一 CLI 信封已有回执不重复执行；健康空大厅真实房间状态保存、自然退出及正常 release 仍成功。

最终证据根：`E:/scratch/emergency-stop-b348d0a03a6a46ba838f241dddb3639f`。机器回执 `q01-explicit-admin-emergency-stop.json`，原始专项 stdout `q01-explicit-admin-emergency-stop.stdout.txt`。冻结生产与专项源码 SHA 已逐项核对与当前工作树一致。

所有业务测试与临时产物使用 E 盘；TMPDIR/TEMP/TMP、隔离 APPDATA/LOCALAPPDATA 指 E，Godot headless/fixed-fps 60，600 秒看门狗。未操作 PID 17120/28100。runner 的隔离 project 配置仅去掉主场景、无消费者的 cursor autoload 和编辑器插件自动启动；原工程配置未改。保留隔离快照及失败轮证据，不在活动目录上归档或删除。

## 红测、问题与未验部分

- 干净行为红测（未实现入口）为 24 CHECK、3 个目标失败、exit1、无 engine ERROR、Job0：`E:/scratch/emergency-stop-2d3c80c06eac4e4c9301fc8a1f5b697e`。旧入口未知命令，真实 worker 未退出。
- 首轮直接用源码已有 class cache 时出现 `PayMagic` 未登记；未修其它代理代码，改用独立冷导入快照。冷导入 cursor texture autoload 先于资源导入会报错，协议夹具仅在副本去掉该 UI autoload。
- intent JSON 读回先 parse/stringify 会因 Unix 小数精度发生不等，已改为实际原字节对照；正常关闭夹具曾在 request 删除竞争窗口读回，已沿原夹具等待真实 prepared 屏障，不改生产契约。
- 未运行真实 stdin 交互控制台前端、完整服务端外部监听部署、导出包、Linux、多机或全量回归；已验证的是它实际使用的生产本机信封接收/执行链。
- 健康保存正例为空大厅 `room_state_saved=true`，不宣称完整录制中局/恢复端到端通过。磁盘故障、断电耐久性、审计结果写入失败、进程在 terminate 期间转 UNKNOWN 的故障注入未动态覆盖。
- 接手时上下文提到的 `newtests/run_host_close_save_guard.py` 实际不存在，skill 未提供独立 host-close-save-guard reference；已阅读 authority-worker-lifecycle 并直接核对源码保存契约，本任务不补写那个独立守卫。

未提交或推送。
