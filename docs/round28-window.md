# Round28 窗口专项验收

## 结论与边界

- **真实独立生产 worker 大厅链通过**：非 headless，真实大厅部署 → 内容准备/批准 → 真人选人 → 正式 v2 → 规则播报等待本人 → 正式继续按钮 → 权威成功回执 → 屏障放行。最终 `RESULT checks=17 failures=[]`，退出码 0，104.784 秒。
- **共同本地 source/command 原生关键动作通过**：active/card/location 真实规则成功，保留父夹具 player、输入、隐私、通知全部断言。`RESULT native_choices_window checks=69 failed=0`，退出码 0，13.837 秒。
- 两者不能等同于全仓 GREEN：生产没有整体冻结，期间其他测试发生修改；本地 active/card/location 并不证明远端 worker 的这三类效果成功。原父夹具网络路径仍是请求捕获，报告不升级其含义。
- 未修改任何生产脚本/场景。没有使用 vision_analyze，没有全仓副本、认证绕过或伪造成功回执。每个进程看门狗为 180 秒。

## 实际运行命令

启动器：`python E:/Caches/Hermes/cache/scratch/round28-window-run.py <suite>`。

两套实际窗口命令均为：

```text
D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --verbose --fixed-fps 60 --path E:/Caches/Hermes/cache/scratch/round28-window-live/overlay --scene res://tests/<suite>_test.tscn -- window
```

`<suite>` 分别为 `net_lobby_transition`、`round28_command_window`。临时项目仅挂接正式资源并复制必要缓存、独立 project.godot；正式 data 独立复制，不使用链接作为批准数据根。隔离配置仅修改用户目录名，最终大厅再附加只读路径日志 autoload。

## 真实主/worker/验证 child 的物理 E 证据

最终大厅本轮 PID：主窗口 **18556**、生产权威 worker **21896**、真实内容验证 child **13932**。逐个进程自身执行 `OS.get_user_data_dir()`，全部输出：

`E:/Caches/Hermes/cache/scratch/round28-window-live/appdata/HermesRound28WindowLive`

不是额外主进程 probe 推断继承。worker 的 ready PID 与大厅管理记录一致且不同于主 PID。

worker 房间：`authority_rooms/ebc9b0f1305d9893fc589bf76ff438c4`；顶层 `broadcast_confirmation_capable=true`。真实 config/ready 文件、批准数据根、安装数据根均通过 Python Path.resolve 验为物理 E。

worker 自身日志观察到实际内容根依次为房间 `data`、`preflight/room_validation/21896-13486052/validation-data`、`matches/2026-10-09T22-35-16_0823a9df21a4bc3571311bc3/data`，均在该 E 房间下。验证 child 自身也报告 E validation-data 根。保存 205 个已安装数据文件 SHA-256；未导出身份、密钥或配置秘密。

路径探针必须调用 `LoadHelper.get_data_dir()` 才反映会话安装根；`resolve_path(DATA_DIR_NAME)` 只显示默认根，不能作为 worker 实际加载证据。

## 权威业务结果

大厅播报等待：`batch_id=1, pending=true, confirmers=[0], confirmed=[]`。正式按钮经过 Viewport 鼠标移动、左键按下/抬起命中；回执 `ok=true`；随后 `batch_id=0, pending=false`。属于实际 GUI 命中输入，不是 OS 硬件真人输入；零 AI 单真人阵容，不覆盖多真人确认/AI/跨网。

新增动作窗同一正式 `battle_board_v2.tscn`，复用正式本地 source/command adapter：

- active：实际待答声明 → 原生选项按钮 → `[1,true,""]`，魔力 10→7，真实待答清除。
- card：实际本人手牌 → 原生选择/确认按钮 → `[2,true,""]`，选中真实 card 对象，待答清除，魔力 10→7。
- location：真实部署后生成候选 → Viewport 地图输入回调 → `[3,true,""]`，真实 selected_location 非空，待答清除，魔力 10→7。
- 本地夹具跳过启动/自动推进，只接入正式控件处理函数；地点使用测试命中区域，不是完整本地战局地图布局验收。
- `native_choices_window_test.gd` 未修改；新测试继承它执行其全部原 player 单/多选、精确费用、隐藏牌/私有消息、键盘数值、多分支、防重复等断言。

## 每个窗口的精确版本

完整逐文件 SHA-256：证据目录 `<suite>-source-before.json`、`<suite>-source-after.json`。最终两次关键生产文件哈希一致：

| 文件 | SHA-256 |
|---|---|
| scripts/game_scene/battle_board_v2.gd | 97b5a7bc232999a8f4ce611c6ebf0f2dd020f4a071ddf2f72809d868f45c8655 |
| assets/scenes/game_scene/battle_board_v2.tscn | 39a681e1f00578e2a2d7278b241262a72a78afe99937d99553c6ebf615c0fb6d |
| scripts/net/session/lobby_session.gd | 0cb12ae8eabc0922dd9d244b22012ad235e87bf1040a4197115c1ebb21b69135 |
| scripts/net/server/server_room_worker.gd | 2c93c8ef26e48a32e37d098beb43590114fd1c8494ab785c8ccc08741bc85a4a |

最终动作窗运行前后无源码变化；最终大厅仅 `tests/round28-command-migration_test.gd` 在运行期间变化，关键生产哈希没有变化。较早尝试曾捕获 board/gateway 和其他测试变化并及时提示。共享资源不是冻结副本，前后相同不能排除短暂改回；不得称全仓冻结绿色。最终收尾时以上关键源码哈希仍匹配。

## 原生画面

原生读取已保存 PNG：正式选人完成大厅、正式 v2 开局、真实播报等待、active/card/player 关键动作。检查的正式 1920×1080 Viewport 画面没有见到异常彩色色块或叠层失控；大厅控件在完整 Viewport 内，v2 地图/手牌/资源与播报覆盖层可辨。

早期 PrintWindow 客户区捕获为 1536×864，曾显示右侧裁切；完整 Viewport 截图显示右侧控件齐全，因此不把该捕获直接定性为生产布局缺陷。未做同帧桌面客户区对比，**真实桌面客户区缩放/裁切仍不完全验收**。局部夹具有空玩家名/未初始化地图及测试命中块，不冒充完整生产战局画面。

## 遇到的问题与夹具处理

- 第一轮 E 路径防线拒绝：启动器传入 alias 不等于 Godot 实际目录。改为直接传实际 E APPDATA/自定义目录，不启动不合规 worker。
- 隔离缓存遗漏 extension_list，正式进程所有权扩展不可用；补复制原 extension_list 后恢复，未绕过校验。
- 链接 data 被正式安全校验拒绝；改成仅正式数据物理副本。
- 随机端口落入 Windows UDP 排除区间；改由启动器实际 bind 探测空闲端口，显式回环地址。
- 本地夹具遗漏 `_ready()` 选牌按钮接线、地图 area_idx；仅补正式 handler 接线。部署会改变魔力，费用初值在部署后显式设为 10。
- 最终主与 worker/验证 child 日志没有 SCRIPT ERROR、Parse Error 或 ERROR；未遇到需要修改生产的脚本错误。

## 修改与交接

- 修改 `tests/net_lobby_transition_test.gd`：实际端口、回环绑定、真实 worker 就绪/配置/数据证据。
- 新增 `tests/round28_command_window_test.gd/.tscn`：共同本地权威原生关键动作及继承原断言。
- 新增本报告 `docs/round28-window.md`。注意 `.gitignore:47:/tests/` 忽略上述测试，git diff 空不能证明未改；测试交接以逐文件哈希及 V4A 补丁为准。
- V4A：证据目录 `round28-window.v4a.patch`；对旧大厅夹具只替换测试端口与追加只读证据，新测试独立添加，不改规则或生产耦合结构。

## 证据与回收

证据目录：`E:/Caches/Hermes/cache/scratch/round28-window-live/`。

主要文件：两套 `.log`、`*-result.json`、`*-source-before/after.json`、截图目录、`final-verification.json`、`preserved-child-logs/21896/engine.log`、`preserved-child-logs/13932/engine.log`、`cleanup.json`。

本轮及较早尝试所有已记录自有 PID 均核验不再存活；没有按进程名全局清理。已回收临时 overlay 挂接与物理数据/用户目录/缓存副本，仅保留日志、截图、指纹证据与启动器。配置转换 SHA-256 为 `69ad986f9d53a3562b24d49099445912a4a86d69c5625b54f71aa9c39507da90`，只读路径探针 SHA-256 为 `b0a8ea4e7d276281e1206080b595dac7b6b0905229d309f44283e6bcadafff25`。
