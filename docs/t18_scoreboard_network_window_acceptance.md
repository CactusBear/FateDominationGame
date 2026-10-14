# T18 战果榜网络窗口输入门验收

## 结论

- **核心窗口输入门通过**：真实 Windows/Vulkan 非 headless 窗口，117/117 CHECK、exit0、SCRIPT ERROR/ERROR0、Job0；正式按钮5次 pressed，GUI down/up各7（另2次禁用按钮点击没有 pressed）。
- **不能把 T18 全链或全部边界记为已验**：同一冻结、同一探针的 `--empty-edge` 为131/132 CHECK、exit1、1次独立 SCRIPT ERROR、Job0。非空快照从2名玩家变成 `players=[]` 被正式 Session 接受后，生产顺位动画空数组越界并卡住 busy。
- 只新增测试/证据文件；生产、FATE布局、原有样板均未修改。用户 PID17120、28100 只做存活读查询，均仍 running；所有自有进程按 OwnedJob 回收，没有按名称杀进程。
- 网络边界：使用真实 LobbySession 的 transport.message_received 声明信号受控投递 bind/view/reset，未改 mirror/source、未伪造身份认证。**不是 ENet、权威 worker、真实联机身份、硬件输入或多机验收**。

## 静态判据与调用链（本次冻结与读回时 live 的六个关键文件 SHA 相同）

| 判据 | 文件:行 |
|---|---|
| ready 选择真正网络 source 与 presenter，同一个 network_session，不走本地规则 UI 入口 | `scripts/game_scene/battle_board_v2.gd:333-344` |
| 网络开关唯一生产 caller：BoardButton.pressed→board._toggle_scoreboard | `scripts/net/ui/v2_view_presenter.gd:57` |
| 初始化按钮禁用；正式 refresh 只用 `view.is_empty()` 控制 BoardButton.disabled，无行动者、房主或阶段限制 | `scripts/net/ui/v2_view_presenter.gd:29-30,163-165,187-202` |
| 开/关只翻转 visible 并重绑 source；不是 MatchCommand，没有 scoreboard 规则命令 | `scripts/game_scene/battle_board_v2.gd:3159-3169` |
| 排行来自同一次 source players，按score降序；姓名、分数、observer样式与高度由相同过滤视图绑定 | `scripts/game_scene/battle_board_v2.gd:3170-3186` |
| NetworkBattleSource.read_view 直接读取绑定 Session.read_match，不读取本机 GameData 补齐 | `scripts/game_scene/battle_io/network_battle_source.gd:48-50` |
| 客户端接收仅接受主机sender1，kind先做字符串门，之后进入正式 match inbox | `scripts/net/session/lobby_session.gd:764-768,789-791,851-852` |
| match_bind 首次绑定观察者；未bind不得接收view；必须state/pending/actions字段与mirror校验通过；match_reset撤销镜像 | `scripts/net/session/client_match_inbox.gd:19-29,38-51` |
| mirror拒绝重复/回退seq、观察者错配和缺失/非有限score | `scripts/match/view_mirror.gd:56-65,95-97` |
| 网络_input先browse，再仅Escape/MouseMotion，不进入本地波浪号调试分支 | `scripts/game_scene/battle_board_v2.gd:1952-1960,1972-1980` |
| 榜显示期间全局地图motion被阻断；关闭后没有禁点延时，首个新motion恢复导航 | `scripts/game_scene/battle_board_v2.gd:2007-2026` |
| Escape不是关榜快捷键：关闭浏览overlay，否则切暂停菜单 | `scripts/game_scene/battle_board_v2.gd:3495-3504` |
| 未终局隐藏返回动作；终局未获房主权限的Session返回大厅禁用；owner/playing/pending/unknown/management_paused再次限制 | `scripts/game_scene/battle_board_v2.gd:503-520` |
| 返回大厅是真实命令 `match_finished_lobby`；提交参数门是playing、owner、game_over、整数seq且未暂停，payload=view_seq | `scripts/game_scene/battle_board_v2.gd:467-469,480-490`；`scripts/game_scene/battle_io/battle_host_lifecycle.gd:60-82` |
| 服务端再次检查暂停、room.owner与playing；再委托权威终局收尾并迁移大厅后交回执 | `scripts/net/session/lobby_session.gd:1082-1119`（本次只静态追链，未动态验证该权威路径） |

## 窗口结果表

| 项 | 结果 | 动态证据 |
|---|---|---|
| 无视图、未绑定、伪来源bind | PASS | disabled真；真实点击只有GUI down/up，没有pressed，不开榜 |
| 正式bind＋主机来源合法view | PASS | Session.read_match＝投递view；board source与presenter持同一个Session；生产使能，不直接改disabled |
| 打开、关闭、重开 | PASS | motion/frame/down/frame/up/frame；真实hovered为正式按钮；每次一次pressed；当前Session字段重绑 |
| 公开榜单文本与更新 | PASS | 初始8/3；合法seq2更新为41/3；姓名同步；同ID行复用而非旧内容缓存 |
| 榜内左键、右键、滚轮、非法波浪号 | PASS | 真实键鼠事件；无本地调试Session，无输入新增规则请求，规则状态与mirror不变 |
| 非主机sender2、缺score、错observer、旧seq | PASS | Session镜像与已打开榜单不被污染 |
| 模态motion与关闭恢复 | PASS | 开榜motion不换区；关榜后首个合法新motion立即换区；没有warp或双路输入 |
| Escape | PASS | 第一次开暂停且保留榜；第二次恢复，正式战果榜按钮仍能关闭 |
| 未获房主权限的终局输入 | PASS（客户端层） | 正式终局view；返回大厅可见但disabled；真实点击pressed0，请求数3→3；没有match_finished_lobby |
| reset | PASS | 等完整绘制帧后镜像为空、按钮disabled、榜关闭；再次点击无pressed |
| observer=-1观战者 | PASS | 正式bind与builder过滤投影；无行动权限仍可只读打开/关闭，无规则副作用 |
| 非空view、players=[]从非空列表更新 | **FAIL（生产边界）** | Session接受seq5，空榜开关本身可用，但顺位动画SCRIPT ERROR并busy未清；不能称整窗口干净通过 |

输入采用真实非headless根 Viewport.push_input 的鼠标运动/按下/抬起与按键按下/释放。没有 pressed.emit、直接调用 toggle、warp_mouse 或修改状态来冒充输入；初始化 GameData 只用于生成合法 builder 投影。未发 OS 硬件输入。

正常投影刷新会通过正式 GroupSelection 发 `preview_group` 查询；这是读取预览而不是战果榜修改规则。初期把所有request总数跨终局比较造成假红，最终逐输入比较前后计数并记录kind；终局按钮 clicked pressed=0、request3→3、state_unchanged=true。不能把正常查询计成非法提交。

## 原生窗口截图（已模型原生加载，非辅助视觉）

核心根目录：
`E:/scratch/t18-scoreboard-hwnd-core-final/isolated-0c73bf2286e04be091b25a02014d7a72/`

- 打开态 OS 截图：`evidence/native-window/t18-network-open.png`
  - SHA256 `097c69733031305cdaf852af0cb92530ba40cd69fb0dfdfc186a43c16dca8d70`
- 输入后态 OS 截图：`evidence/native-window/t18-network-after-input.png`
  - SHA256 `0e43edc6537b05c0a4b9653ad7679376dca93bc344573c2e2a48ca97563e4750`
- 同一PID31584、HWND128456596；原生客户区1920×1080，物理位置(320,150)。使用 `PrintWindow(PW_CLIENTONLY|PW_RENDERFULLCONTENT)`，不切焦点；打开截图当时不是foreground也成功，未截用户其它窗口。
- 亲看两张原生截图：战果榜位于右上、名次/姓名/分数可读；8/3→41/3，无黑屏、裁切或模态遮挡。另存真实渲染PNG于 `evidence/screenshots/`，明确不是OS截图替身。

边界根目录：
`E:/scratch/t18-scoreboard-hwnd-empty-edge-final/isolated-44295cddc0284c9c81c8136abee36a3b/`

- `evidence/screenshots/t18-network-empty-rows.png` 已原生亲看，空榜确实显示；是viewport渲染PNG。视觉显示存在不代表动画与错误门通过。

## 最小因果（未修生产）

这不是命中偏移或无motion：核心hover/pressed/down/up和地图motion都成立。

空投影边界实测：
```
EDGE_CAUSE {"accepted":true,"expected_ids":[],"previous_ids":[0,1],"rival_anim_busy":true,"source_seq":5}
SCRIPT ERROR: Out of bounds get index '0' (on base: 'Array')
  at: _animate_actor_handoff (res://scripts/game_scene/battle_board_v2.gd:1405)
CHECK 零玩家 生产动画完成 false
```

最短生产链：presenter.refresh `:222`→board._bind_rivals `:1166-1171`→`_bind_rival_order`在`:1180`认定order_changed，`:1245-1247`置busy真并传空expected_ids→`_animate_actor_handoff:1405`索引expected_ids[0]越界→未到`:1430-1431`清busy。mirror没有要求players非空，受控view明确被Session接受。未声称真实权威端会生成这份空玩家快照；这里证明的是接收端允许该输入时的消费者故障。

## 新增文件与SHA256

| 路径（仓库相对） | SHA256 |
|---|---|
| `newtests/t18_scoreboard_network_window_test.gd` | `2797f5b192a8c68ca5c70410787c6934e5af48d26dc42b22b40f126ad13a2933` |
| `newtests/t18_scoreboard_network_window_test.tscn` | `b8c8f0c527446c9c858eeded76a8966cd3991cf6023637ec6a6da68c90babc5a` |
| `newtests/run_t18_scoreboard_network_window.py` | `5faca2556e93860a1dcbff6e959dd33ffa4cc1365b3a1df5f0f3f91138588133` |
| `newtests/prepare_t18_prior_freeze.py` | `b19a5b36609907da6c2a7a0de32de8c7617be898ac25e1f436f9e14ddf515af2` |
| `newtests/t18_native_window_capture.py` | `dfe76bbdb219a71a18e7a28b3629d282167072572fb3879d9c3082299f4e74f1` |

还新增本文与 `docs/t18_scoreboard_network_window_receipt.json`。文件位于可入库目录，未提交。

代码分工：GDScript继承round75窗口样板，复用round74 CHECK/renderer断言；WindowLobby仅观察请求kind并照常super.request；runner继承已有E冻结/OwnedJob/import/日志/归档流程；prepare只从已通过复制前后验证的首次冻结恢复生产字节并验SHA后叠加本次测试；native capture只定位marker给出的自有PID，不读身份数据、不碰保护PID，不发输入，借助E文件握手固定捕获阶段。

## 实际命令、日志与冻结边界

```
python -B newtests/prepare_t18_prior_freeze.py --manifest E:/scratch/t18-scoreboard-initial/isolated-a68963b6cf9742ccabe2c14b79188639/manifest.json --output E:/scratch/t18-verified-prior-freeze-v8
python -B newtests/run_t18_scoreboard_network_window.py --label hwnd-core-final --source-root E:/scratch/t18-verified-prior-freeze-v8
python -B newtests/run_t18_scoreboard_network_window.py --label hwnd-empty-edge-final --source-root E:/scratch/t18-verified-prior-freeze-v8 --empty-edge
```

GUI命令为自有E盘Godot.exe `--fixed-fps 60 --path <自有project> --scene res://newtests/t18_scoreboard_network_window_test.tscn -- window`（边界再加empty-edge），没有headless。环境probe/import使用headless，不计窗口输入证明。

每个最终根的 `manifest.json`、`evidence/t18_scoreboard_network_window_test.stdout.log`、`.stderr.log`、`evidence/native-window-captures.json` 与 frozen-inputs 已保留。结构化回执包含命令、PID、退出码、逐日志ERROR/Warning、全部测试SHA、原生截图SHA和关键生产SHA。

| 最终运行 | CHECK | exit | 独立SCRIPT ERROR（stdout/stderr） | Job0 |
|---|---:|---:|---:|---|
| hwnd-core-final | 117/117 | 0 | 0 | true |
| hwnd-empty-edge-final | 131/132 | 1 | 1 | true |

两个运行source_hashes逐项完全相同；source_after_copy_drift/source_drift/freeze_drift都为空，artifact_readback已由runner通过。初始生产冻结重建2112个未改文件全部SHA一致，测试overlay显式单列。并行修改令当前树冻结连续失败，因此没有把不同源码拼成全链绿；最终测试复用首次已验证的生产冻结。读回时board/presenter/lobby_session/client_match_inbox/mirror/正式tscn六个关键文件与live逐一相同，**不代表整个当前工作树或后续并行改动都已复验**。

保留早期日志：initial探针类型推断Parse Error/超时（自有Job0）；typed归档缺文件掩盖首因后修runner只保首异常；typed-safe/window-current/window-current-2因复制阶段外部源码漂移未进窗口；prior-freeze与observed-frame保留假红及分帧/请求种类对照；native-core-final保留拒绝后台桌面裁图的证据，后改用真正的自有HWND PrintWindow，不前台抢焦点。

## 未验部分

- ENet传输、正式身份认证/房间playing完整生命周期、权威worker真正开局与终局、房主合法match_finished_lobby回执和大厅移交。
- OS硬件鼠标/键盘、多机/跨网；没有自动接管用户Godot窗口。
- 每个实际规则阶段的真实权威推进；开关无阶段/行动者权限条件已静态确认，动态覆盖builder初始化投影、终局与观战投影。
- 零玩家投影边界已定位但**未修**；不能把核心117全绿掩盖边界SCRIPT ERROR。
- 全量回归、最终整合源码冻结与导出包；此次不执行、不更新矩阵为全部通过。
