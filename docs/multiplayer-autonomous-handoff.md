# 联机自主实施交接

## 当前用户授权

继续 P1，且随后自主完成整个联机方案。过程中需要用户决策时写入 `docs/multiplayer-open-questions.md`，跳过相关部分，继续不受影响的内容；用户回来时集中询问，不反复等待确认。

## 现有成果与范围

- `docs/multiplayer-plan.md` 是方案，以后续用户明确口径和 `multiplayer-open-questions.md` 的“已确定”段为准。
- P0 已完成：`scripts/match/{seat_controller,match_driver,match_commands}.gd`，v2 已接入。检查报告 `docs/multiplayer-p0-verification.md`，结果 `docs/multiplayer-p0-results.json`。
- 急行内部标识 `surveil`，不是侦察。两个曾失败的真实窗口测试已查明只漏了第一次点击展开牌堆，修正测试后各三轮全绿，无正式 UI/规则改动。
- 用户手动删除了旧开场视频，git 中 D 状态属于用户，不得恢复。

## P1 正在实现

新增文件：
- `scripts/match/match_journal.gd`：基础 Variant 帧、64 位整数无损、序号、哈希链、尾部截断恢复、续写。
- `scripts/match/net_ids.gd`：弱引用会话 ID、参数编码/解码、规则对象图快照；脚本字段名缓存避免每步重复反射；同名对象不合并；本局数据路径标准化。
- `scripts/match/match_replay.gd`：显式 begin/perform/pulse/restore/resume_recording/release，调用既有 GameStart / MatchCommands / MatchDriver；本局 data 备份，版本校验；每动作保存独立随机入口；比较操作前后对象图状态；未知写入拒绝续录。
- `LoadHelper.session_data_dir`：非空时读取本局 data，空值保持原有路径。
- `tests/match_journal_test`、`net_ids_test`、`match_replay_test`、`match_replay_pending_test`。

已运行证据：
- 日志测试从文件缺失报红到 9 checks 全绿；ID 测试从缺失报红到 5 checks 全绿。
- 初版真实全 AI 对局 146 次操作到终局，连续恢复两次，10 checks 全绿。
- 等待输入保存、恢复后继续追加、再恢复、篡改检查点定位第 1 条拒绝：10 checks 全绿。
- 随后新增了注册表、静态规则池和广播等待的校验、输入形状校验、跨进程窗口恢复测试，最终回归正在跑，不能沿用旧结果声称最终版通过。

## 当前测试锁

`python C:/Users/Administrator/AppData/Local/hermes/cache/scratch/p1-verification.py` 正在同仓库串行执行。
后台 session `proc_1614eb71aff3`，PID 23532。
结果：`C:/Users/Administrator/AppData/Local/hermes/cache/scratch/p1-verification/summary.json`。
顺序：P1 完整记录+两次重放 → 新进程非 headless 恢复并截图 → 其余全部 `tests/*_test.tscn`。
测试运行时源文件冻结，不能并发启动 Godot，也不能改代码制造同批测试版本混杂。先等该进程结束，再核对汇总、检查日志、修问题。
窗口恢复截图：`tests/runtime_reports/p1_restored.png`，必须用 load_image_native 原生看图，不能只信保存成功。

## 当前 P1 尚未宣称完成

- 普通选人/v2/调试控制台没有默认自动录制，必须显式通过 MatchReplay API 执行；后续接入不可默默漏掉调试、播报或异步续行。
- `restore` 是破坏当前运行局的操作，只恢复本机存档；尚不是远端不可信存档导入协议。
- 需继续检查恢复后可正常操控的中局画面、帧间回合末待答、同名克隆、数据变更拒绝、完整参数边界、截断存档另存续写。
- `NetIds.snapshot` 是本轮新增的规则状态检查点，不是任意对象图反序列化器，也不能用于声称任意死循环完全无误判。
- `GameData.player_id` 旧回退、AI 使用对象实例号作内部尝试缓存等需随着服务端接入审计，不能直接声称已经无本地玩家依赖。

## 工具与验收

Godot console：`D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`。
标准参数 `--headless --fixed-fps 60 --path <仓库> --scene res://tests/xxx_test.tscn`。
窗口模式去掉 headless，加 `--resolution 1920x1080 -- window`，但恢复专项用 `-- restore_only user://...`。
Python 为 `python`，不是 python3；工具 terminal 是 Git Bash，原生程序用 C:/ 路径。
所有新增源码用 write_file，已有源码用 patch 的 V4A 格式；不要用 Python 直接改源码。
不提交、不推送、不重置工作区、不读取凭证、不杀用户自己的 Godot。
当前 tests 目录整体被 gitignore 忽略，测试文件会存在且能跑，但 status 不显示，不据此认为测试没写。
全量基线本来有旧失败：用 p0 汇总对账；窗口专用测试 headless 失败需窗口复跑，不得掩盖。
完整报告保存在 docs，scratch 只有短期保留。

## 后续阶段顺序

完成 P1 并记录真实验收 → P2 按玩家视角数据、网络 ID 与 UI 只读镜像 → P3 requires/条目挑选/冲突/下载缓存 → P4 局域网自选端口、大厅、联机选人、管理、观战、断线等待与房主恢复 → P5 多房间 Windows/Linux 命令行服务端 → P6 P2P、可选服务端信令/辅助打洞。
阶段有外部环境阻塞时写明未实现/未验收部分，先做其他不依赖部分，不编造跨网或 Linux 验收。禁止服务端替 P2P 转发对局流量。身份与管理员权限不能仅凭客户端自报 UUID 信任。
