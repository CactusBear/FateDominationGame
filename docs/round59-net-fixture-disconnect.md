# Round59：net 首次合法不可用与“连接中断”首因追踪

## 结论

本轮没有证据证明真实 ENet/权威断线是首因。旧 `round57` final 的 net 首分歧发生在**首个主动按钮尚未形成可用 UI 入口**，之后的“与房主连接中断”以及 22 项失败没有真实 request/authority/ENet 首因证据，不能倒推为网络根因。

在同一当前冻结、仅 GUI scope 的新 trace 中：认证、ENet、房间 revision、match adapter、actions/effect identity、真实 GUI pressed、authority input、accepted receipt、pending 和高 revision playing 全部连续通过；场景内没有 `transport_disconnected`、packet rejection、ENet error 或 authority rejection。旧红仍保留为历史红证据，未用新绿覆盖其事实。

## 先读的旧证据与缺口

旧 final：`E:/HermesScratch/round57-host-button-first-event/final-b93f0a1f33414f6780c3edb846e5e944/`。

旧 net stdout 的首 checkpoint 顺序：

- `room_revision=4`、`phase=playing`、`view_seq=2`、`registered_seq=5`；
- `candidate_ids=[22,19]`、`command_available=true`、`adapter_present=true`、`pending={}`；
- hovered 是 `HandCard`，但没有记录 `EffectButton.visible`、`EffectButton.disabled`、manual effect 数量或 `_held_input_available()`；
- 紧接 `native card exposes authority-approved activation button=false`，没有 `ROUND55_REAL_PRESSED`、authority match input 或 request receipt；
- 后续截图的“连接中断”没有对应 transport peer lifecycle、ENet error、认证失效或断线时点。

因此旧证据只能定为：**UI 首分歧在权威请求之前；断线因果缺少数据**。不能分类为 UI input race、authority deadline、fixture poll 漏掉、teardown 或真实 disconnection 中的任何一个。

## 新 trace 设计

仅修改 `tests/net_v2_ui_input_parity_window_test.gd`：

- 每帧只取小型只读状态；每个字段只输出首次变化，避免巨量 IO；
- 记录 request seq、actions 摘要、权威/客户端 pending 摘要、card/action effect identity、adapter 生命周期、当前 room revision/phase/view seq、认证和 transport 状态；
- transport connected/disconnected、packet rejection、authority match input、request completed/rejected 作为事件输出；
- 保留真实 `ROUND55_RECEIPT` 和真实 accepted wait；accepted 通过 `before_seq` 后最小真实 receipt 关联，不把后续 preview seq 当成原请求；
- 不生成 candidate、pending 或 pressed，不调用 `pressed.emit()`，不修改生产 selector/authority seq，不增加 UI 锁或 sleep。

## 两个小 probe

### Probe 1

路径：`E:/HermesScratch/round57-host-button-first-event/trace-probe-1/`

- net GUI 单 scene、单冻结；exit 1，66 checks，10 项为诊断器自身错误的 accepted wait；
- 原始 trace 同时显示真实 authority `activate seq=6`、authority pending `effect=19/kind=active_choice`、`ROUND55_RECEIPT seq=6 ok=true`；
- 首版观察器把后续自动注册的 seq7 当成 seq6 的 receipt，造成假红；未据此修改产品。

### Probe 2

路径：`E:/HermesScratch/round57-host-button-first-event/trace-probe-2/`

- exit 0，`RESULT checks=66 failures=[]`，无 SCRIPT/Parse/ERROR；
- 首合法状态：认证完成，`room_revision=4`、`phase=playing`、`view_seq=2`、`guest seq=5`、actions effect ids `[19,22]`、card effect ids `[19,22]`、adapter `epoch=1/observer=0/present=true`、双方 transport connected；
- 首按钮真实可用并产生 `ROUND55_REAL_PRESSED effect`；
- `activate seq=6` 进入 authority，pending 为 `active_choice/effect=19`，随后 `receipt seq=6 ok=true`；
- 翻面、选牌、play group、战场主动、令咒和 end action 的真实 authority input 与 accepted receipt 均存在；room revision 保持 4，match view seq 从 2 推进到 26；
- trace 中没有 `transport_disconnected`、`packet_rejected`、ENet error、认证失效或 authority reject。

Probe1/2 是同一当前源码范围下的诊断探针，不拼接不同冻结的产品结果。

## 最终一次同冻结 GUI 链

路径：`E:/HermesScratch/round59-net-fixture-disconnect/final-7d97662935a9470bbad3169cc1b37227/`。

| suite | scope | exit | RESULT | SCRIPT/ERROR |
|---|---|---:|---|---|
| host_gui19 | GUI | 0 | 19/0 | [] |
| net_gui_trace | GUI，含原有 net 检查及 accepted trace | 0 | 66/0 | [] |
| countdown72 | GUI，原有 risk/zero/cancel 分支 | 0 | 72/0 | [] |

冻结/漂移门：

- `source_scope=14` 个实际测试依赖；不是 14 套执行；
- `source_freeze_mismatch={}`；
- `source_drift={}`；
- `freeze_drift={}`；
- `gui_only=true`，headless scope 明确排除，由另一 freeze owner 负责；
- 每场景沿用 180 秒、E 独占 Job 及自身 PID 回收约束。

与旧 round57 final freeze hash 的可见差异只有三项：`addons/fate_server_signals/src/process_owner_core.cpp`、`project.godot`、本测试文件；本轮 GUI final 内 source/freeze 均无漂移。不能把这三项差异自动解释成旧红根因，尤其本轮没有 production network error。

## 根因判定边界

已被本轮 trace 反驳的候选：

- 不是当前运行中的认证失败：guest authenticated 后稳定；
- 不是当前运行中的 room revision/lobby 投影缺失：client 与 host 都是 revision 4/playing；
- 不是 authority deadline 或 rejected request：真实输入均收到 accepted receipt；
- 不是 fixture 忘记 poll：每次 accepted wait 都由真实 host/guest poll 驱动，并读回权威 pending/状态；
- 不是 fixture end-session teardown 导致场景中断：断线事件未在操作链出现；
- 不是本轮观察到的 ENet disconnection：没有 disconnection/error 事件；
- 没有观察到自动 tick 使首个合法 selector 在点击前过期；actions/effect identity 在首 checkpoint 与后续链均有合法投影。

未能从旧红中证明的部分：旧首 checkpoint 没有 button visible/disabled、manual effect selector 结果和同帧 transport lifecycle，所以**旧红的具体 UI 不可用分支仍缺一条可复现的 first cause**。新 trace 在当前冻结通过，说明旧“连接中断”不能继续作为 main production root cue；若要再次定位旧红，必须保留旧冻结并在首 checkpoint 同时记录上述缺失字段，不能用重跑绿抹红。

因此本轮没有 main production fix diff，也没有 compat fallback、UI 硬锁、延时 sleep 或取消权威序列。生产 board/lifecycle/presenter/session/transport/authority/规则均未修改。

## 原生画面与 DPI 边界

已原生查看最终 host 终局/大厅、net 战板、countdown zero-budget/cancelled/risk-confirmation 图：布局和控件层级正常，没有异常色块或断线遮罩。checkpoint 只实际记录 viewport/window `1920×1080`；没有 DPI 实值，未作 DPI 或系统缩放归因。

## 文件改动

- 修改：`tests/net_v2_ui_input_parity_window_test.gd`。
- 新建：本报告。
- 未修改：production GD、scene、native engine/addon、host/countdown tests、runner。
