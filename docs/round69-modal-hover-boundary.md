# Round69：父模态悬停差分通过，原四组关闭后目的区仍 RED

## 实测结论（不得合并或放宽门）

- **modalregression PASS**：同一生产冻结的正式 local + 既有 RSA 认证回环 ENet network 板，旧 guard 移除版 **59/2、exit1**，恢复原字节版 **59/0、exit0**。旧版仅 local/network 的“模态 motion 跨其它 strip 保持原目标”两项失败；当前模态中的原目标保持、真实 pressed 关闭、关闭后第一个新 motion 同步切换、CardBrowser/Drawer 原输入行为均通过。
- **geometry FAIL，而不是期望的 PASS**：原局部 headless **65/0、exit0**；原四组 window **67/3、exit1**。本轮没有在关闭后重新选区，完整工房四组十槽闭环仍未完成。
- **fullvisual FAIL（旧 producer 冻结）**：暗置实际 texture=null 的旧证据保留，不能把未加载纹理称作完整视觉通过。
- 唯一 current 最终批次 **246 CHECK / 3 failures**（65 + 67 + 59 + 55），另列旧 guard RED **59 CHECK / 2 failures**。共享 browsing **55/0、exit0**。这是给 main 汇总的局部增量，未写 fulltool/全候选总数。
- 顶层 runner **exit1 / passed=false / logic_passed=false**；freeze_drift={}、owned_source_drift={}，最终全部 stdout/stderr/引擎日志 **0 SCRIPT ERROR / SHADER ERROR / ERROR / WARNING**。

## 最新用户决策及生产所有权

用户已经确认“牌种是可以泄露的，技能牌和攻击牌就用自己的牌背即可”，随后 main 又通知卡背 owner 已获全牌背许可。**Q04 不再是待用户决定**。本报告黑槽只属于改动前已冻结的 builder/mirror，不评价并行卡背 writer 的新实现；后续新版 producer 与新浏览汇合后，由 main 另立同版本窗口验收，不能与本轮旧冻结拼接通过。

本轮只写：

1. `tests/round69_modal_hover_test.gd/.tscn`：正式输入专项。
2. `tests/battle_play_groups_test.gd`：仅增加正式“知道了”按钮 GUI motion 当下 index 和真实关闭后 index 的只读断言/日志。
3. `tools/tests/round69_modal_hover.py`：独占 E 隔离 runner。
4. 本报告。

新增 `.gd/.tscn` 实际存在且与最终运行 hash 一致；仓库 `.gitignore:47 /tests/` 会隐藏这两个新文件的 git status，未擅自改 ignore 或 stage。

生产 board / presenter / scene / builder / mirror / session / data / DLL **未由本代理修改**。guard 保持 main 已写的唯一修复；六个 `_modal_blockers` 原样复用。没有新增锁、延时吞输入、规则政策、卡背 fallback 或选择 pending 注入。

## 模态真实输入及独占 RED

- local：正式 map GUI 输入走真实规则拒绝，生产文本“还没轮到你行动”，生产“知道了”按钮可见。
- network：复用 `net_window_identity_fixture.gd` / `network_test_port_fixture.gd`，OS 分配 UDP、真实 ENet 连接和 RSA 挑战；权威发布真实 outpost 部署候选，正式 map GUI 打开现有 TacticalConfirm，点击生产“取消”。取消后权威玩家 location 仍为 null，没有部署。不是多机/LAN 主管拓扑验收。
- 根 Viewport.push_input 分帧 motion 与 down/up，逐事件 serial、同步 immediate index、GUI hovered、gui_input down/up、真实 Button.pressed 都落原日志；没有 pressed.emit / hide / 私有 cancel 冒充关闭。
- 模态内跨其它三个 strip：旧版 immediate index 实际 0→1→2→3，当前保持 0；关闭后首个新 motion 实际立即切至下一 strip。local/network 都覆盖正式 `_input` 分支。
- 旧版连续跨 strip 后，“取消/知道了”的 motion 在该布局中自然又把 index 选回 0，所以本次旧版关闭后 index 断言为 true；不把这种往返当成“模态期间保持”。有效 RED 强制两个跨 strip invariant 失败，禁止任何无关漏点/脚本错误进入有效 RED；当前 GREEN 仍必须全部 CHECK 通过。
- CardBrowser 没有被加入 native blockers，沿原输入所有权阻止 motion 导航；基线取浏览器正式打开后，不把打开前菜单 motion 的原导航归给 Browser。Drawer 保持非模态导航、原头像点击开关。

## 原四组首个未闭合边界

原窗口的实测链：

```text
GUI_CLICK destination-scroll: hit=true downs=1
CHECK destination scroll selected by real GUI motion and click true
TACTICAL_ALERT_BEFORE: target=工房 index0
GUI_CLICK tactical-acknowledge: hit=true downs=1 pressed=1
CHECK modal acknowledge GUI motion keeps original destination area true
CHECK modal pressed close keeps original destination without reselection false
TACTICAL_ALERT_AFTER: motion_index=0 target_index=0 active_strip=1 visible=false
VISIBLE_ASSERTRED: active_strip=1 open=0 parents_shown=false ready=false
```

原窗口三项失败：

1. `modal pressed close keeps original destination without reselection`
2. `destination area contains all four relocated groups`
3. `workshop all ten cards including six-card group visibly separated after avatar GUI input`

**first divergence 不再是模态可见时那一个正式 GUI motion**（新增观察已证明它保持0），而是按钮 pressed 关闭后、随后帧读到1。未强制重新选区，未补 source 私有刷新，未把后两项改为通过。工房的两个 avatar 展开 CHECK 因原 settle 短路未执行，所以窗口实际67项而非完整69项；headless65保留。

只读冻结源码：`_on_tactical_confirm_cancel()`本身不选择卷轴；`_update_default_area()`独立读取 `get_global_mouse_position()`；原 `gui_click()`仍同时 warp OS 光标与 push_input。新增模态专项仅用根 Viewport 输入，避免制造第二路 OS motion。**现有原四组日志未逐 serial 记录关闭后那一段额外输入，因此不能证明是迟到的 OS motion、默认区计时或其它机制；不把嫌疑写成已证因果，也不为此追加生产修复。** main 后续可在同旧冻结、原夹具中对该帧增加纯观察，或在新汇合窗口中明确分离 OS warp 与单路 Viewport 输入；不能重选目的区掩盖失败。

## 原生截图判读

直接原生加载本轮 PNG（未用辅助视觉模型），并原生看深山十槽裁片 `[540,320,1640,580]`：

|最终同冻结图|SHA256|原生结论|
|---|---|---|
|groups-window/battle_play_groups.png|f34f8bd94063d0ce76171a6bc6304dd0c6a14404fb33dddb9880033aa353b56d|深山四组十槽，六张明确5+1；一槽纯黑，旧纹理门FAIL|
|groups-window/round68-tactical-before.png|9e8eaf482fe82a160155ef9212b9a9f545d874cbeb651926b480d33126a5ac8c|正式工房标题、“还没轮到你行动”及“知道了”按钮|
|groups-window/battle_play_groups_destination.png|f51443a0db3df29d281a913193f092b81dd926403b186b08076ded5c07bd1a1f|提示已消，但标题回深山、牌区空；不是工房四组十槽通过|
|modal-current-window/round69-local-before.png|d84c1cd59d5552f500aaff698fd564ba8b2bd683707a40fdc948131ab7e31e18|工房正式拒绝提示及“知道了”|
|modal-current-window/round69-local-after.png|87087204354ab1f818801eaaeed834fd2d9b4249329a2dd695d4c08151017a4a|原工房标题保持、提示消失；此专项没有构造十槽，不能代替四组验收|
|modal-current-window/round69-network-before.png|703072dd5619bfae2b830eba354a44444ba06e1d3628f92c7fb5f763b1253c5f|工房正式部署确认与“取消”|
|modal-current-window/round69-network-after.png|1736017b8e013788fb7912268cdf6c9d0831d8d50981764eedaff6f5492b6111|原工房保持、正式确认已消失|

**未取得工房四组十槽通过截图**；不拿 headless 或旧轮工房图替代本轮真实失败画面。

## 唯一 current 命令、冻结与进程

```text
python -B tools/tests/round69_modal_hover.py --source E:/scratch/round69-source-e568d936e3b94b7c93ce863896aef388 --label current-final-v3
# 每suite独占Windows Job；180s / fixed-fps60；只有本代理运行GUI
```

证据根：`E:/scratch/round69-modal-hover-current-final-v3/isolated-ee3a34edc1d34e319c030805271080d0/`

最终 manifest SHA256：`c13638e36e4e7e126939b809054fd7402599ca19a2d48f08ee59b723eae016ef`。

|对象|SHA256|
|---|---|
|当前 board|74cf1aa4529a0fa15cda37a2db2c2121422c0fa0cab9b7f62991b433621f1380|
|仅移除共享 hover guard 的 board|43b7be1d30dd785dbc3ef5cde0f02bed50e75f939944d0f64e08f1afc2007906|
|battle_play_groups_test.gd|9cc85ea7cd3154d4441eee9eb4503eaf86acdfe1de1699812d7f16918c83bd8c|
|round69_modal_hover_test.gd|b7a96bd366368caa06e505624f08953da41ce364b36a9e2224f7e8f590f8973c|
|round69_modal_hover.py|e37e146391d7e46e7f5404e966ab8ff3adacd71cca77dcd0808629aa67fc7e72|
|旧冻结 builder|5d570263ec5c31ccd2f5e08b7116dda951be828607819a59cbdea301022979e9|
|旧冻结 mirror|deb091a12f6eb47693934a24653e9b5594e675ee5811aebbcc538bd8bdaeabbf|
|正式 signal template_release DLL|92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd|

移除版 board 与 Round68 原冻结 SHA **完全一致**，不是另改生产来造RED。两版逐字节档案在 `evidence/board-versions/`；所有最终产物 hash 真实读回=true。

|阶段|PID|exit|秒|Job active / log handles|
|---|---:|---:|---:|---|
|physical E主/派生probe|39028|0|1.900|0 / released|
|import|4644|0|24.501|0 / released|
|fixture scene preflight（预期拒绝headless）|5576|1|3.150|0 / released|
|有效旧 guard RED|26088|1|13.841|0 / released|
|groups headless|25076|0|14.881|0 / released|
|groups window|14732|1|26.654|0 / released|
|modal current window|14524|0|21.143|0 / released|
|shared browsing window|9828|0|22.369|0 / released|

最终 generated 实际不存在；仅保留证据及独立生产输入快照供 main 追踪。未操作用户 PID28100、未 commit/push、未改其它已有 dirty。所有Godot主/派生进程 user/临时目录均通过真实物理E探针；没有运行全99或发行/多机验收。

## 外部并行 drift 只作观测，不解释本冻结结果

当前批次始终从已建立的2106文件生产快照读取，只在拥有测试上作明确 overlay。结束时仅对主仓生产作 hash 观测，差异完整保存在 `manifest.outside_drift_observation`：board、builder、mirror、temporary_cleanup_ledger、lobby_session、presenter。**这些新字节未进入本轮 Godot**，不猜它们是本轮失败原因，不声称已验收其新增浏览或卡背。

## 预备诊断保留（不是有效 RED 或额外 current）

本轮有多次夹具预备诊断，全部原始记录保留，不包装成“首版全绿”：

- `fixture-red`：夹具 `kept` 类型推断解析错误；外层终端180s提前中断，原scene PID/Job0没有记录，不能伪称完整退出证据。随后只对该自建 generated 的精确 ExecutablePath 前缀查询，实测无进程；归档原输入/日志后回收该自建目录，事实在 `interrupted-record.json`。
- `fixture-red-v2`：`--script --check-only`未建立项目 autoload，GameData 编译失败；改为正式场景headless分支的预期拒绝式预检。不是生产错误。
- `fixture-red-v3/v4`：早期地图命中 receiver/进度动画/容器布局未正确等待，存在非目标漏点；不算有效RED。后续只调整夹具，真实等待生产动画和容器帧布局，不清busy、不改规则。
- `fixture-red-v5`：首次有效旧版59/2；随后 `current-final`、`current-final-v2` 两批都在旧RED前置因额外浏览命中/菜单基线错误停下，**均未执行任何 current suite**。
- `current-final-v3`：最终修正为单路Viewport输入、Browser正式打开后基线，同一批有效RED59/2，再执行一次且仅一次全部current矩阵；其原四组67/3失败照实保留，未再次补跑current。

尚未闭合：原四组关闭后的额外切图具体事件因果、工房完整geometry、确认后的新版卡背与新增浏览汇合窗口。本轮已独立闭合的是共享 native hover guard 正负差分，不是全部可见闭环。
