# Round73：共享个人/局势弃牌真实窗口验收

## 结论与能力边界

- 当前源码同一新冻结：原 Round71 headless **168/0**完整保留；独立 discard window **221/0**；原 Round69 modal window **59/0**。另原 card_browser 4/0、drawer_dismiss 1/0、privacy 137/0，均 exit0；总590只是不同层检查之和，不是590次GUI点击。
- 正式网络两端（host observer=1，guest observer=0）从 `Ops/Discard` / `Piles/SituationPile` 实际单路根 Viewport motion/down/up 命中；24次打开/关闭都有真实 gui_input down/up，Close另观测真实 pressed。窗口分支不调用打开callback、不emit gui_input/pressed、不warp系统光标。headless原信号分支仍明确只算逻辑。
- **正式本地组合根没有这两个浏览入口**，这是Round71明确保留的原能力差异。窗口真实motion/down/up确认它们不打开浏览器、连接为空；本地当前source/刷新/顺序/empty继续由原168覆盖。不能声称“本地两入口GUI打开已通过”，也没有为验收给生产新增接线。
- 只修改 `newtests/round71_shared_discard_browsing_test.gd`、`newtests/run_round71_shared_discard.py`，新增本文；原 `.tscn`未变。board/presenter/builder/mirror、原tests、battle_play_groups、modal、规则与生产均只读。没有新游戏种子规则、没有提交。

## 测试代码职责与耦合

已有正式scene/source/renderer/session/RSA fixture/端口fixture足够；测试组合它们，不新增生产适配层或推断卡背政策。

- `_ready`：仅显式 `-- window`分派新window分支，其它参数继续原run。
- `_process/window_wait/window_settle`：持续正式session poll；窗口120秒墙钟看门狗、单项10秒；等待生产 `_is_progress_blocked` 与真实 `_scroll_tween`完成，再正式refresh和布局帧。没有固定sleep代替动画完成，也不关闭生产board帧循环。
- `window_motion/window_button/window_click`：唯一Viewport输入通路；motion帧后验证真实hover命中，派发down/up，记录serial/handled/active和临时只读信号观察者。不靠pressed观察者触发产品行为。
- `window_cards/window_browse/expect/textures_match`：从各端当前正式source按observer取本人或公共数组，与真实槽metadata完整顺序、实际Img纹理、标题数量、empty逐项对照。牌槽不排序、不去重；实际ENet单容器使用独立对象ID，同ID重复消费能力仍由原headless覆盖。
- `window_close`：浏览中跨卷轴motion保持目标；关闭按钮motion/down/up期间和关闭后帧仍保持目标；关闭后的firstnewmotion立即切换。没有测试回选原目标掩盖输入问题。
- `window_publish`：修改测试牌区后调用现有正式权威发布，等待guest经ENet收到递增source；两端重新点击验证个人22→3→0、公共3→2→0的刷新。没有直接注入客户端视图。
- `state(generic_cards=false)`：原168默认路径仍使用原攻击牌字段；window显式选择通用牌观察，仅对实际声明 `_is_closed` 的类型读它，其它记not-declared。仍比较回合、当前行动者、阶段、终局、日志、待答、牌区、资源、顺位、弃牌正反面声明；host/guest请求序号前后不变，证明本次浏览没有提交规则命令。不是全部规则内部状态的全量证明。
- `window_shot/window_finish`：真实post_draw保存1920×1080全图及1200×580浏览panel裁片；所有board销毁后关闭两会话/RSA/端口，清空引用再原finish。
- runner `--window`：同一逐字freeze先完整四headless，成功后顺序运行新discard window和原59 window；不扩到50或其它旧窗口套件。继续既有独占Job/E环境/probe/import/hash/archive/readback/cleanup，归档PNG后才清理自有generated。

## 真实网络与交互结果

使用现有 `net_window_identity_fixture.gd`，两端内存生成真实RSA并走正式挑战/签名/成员绑定，OS分配独占127.0.0.1 UDP端口、正式LobbySession/ENet、正式MatchAuthority过滤快照与NetworkBattleSource。**同进程回环，不是worker主管/IPC/LAN多机或跨网验收，也不是OS硬件鼠标输入。**

两端原始source个人22牌及当前本人投影通过；source每次发布、关闭再点击正确替换个人/公共列表，缺牌时标题0和“这里还没有卡”一致。真实滚轮使横向scroll增加；Close清理browser/zoom/desc；每次完整浏览前后事实快照及两会话request序号不变。原59同时验证本地真实拒绝和网络真实部署确认期间native modal guard、关闭后firstnewmotion和既有Browser所有权；六模态政策未改。

隐藏牌原样保留source已声明背面：个人未觉醒技能为专属“升华技”背面；host公共局势包含暗置终极局势背面。真实槽无zoom_img/zoom_desc，真实右键没有正面放大或说明；可见攻击、普通技能、令咒、事件、普通/终极局势继续使用source正面。这里覆盖这些真实样本，不宣称所有卡牌资产穷举。

## 原生视觉检查

证据目录：

`E:/scratch/round71-shared-discard-round73-final/isolated-cc4be315cb8b48d0bbaff7b600a2f77b/evidence/screenshots/`

本轮保存24张discard PNG（12组full/browser）及原59的4张PNG。通过原生图片加载实际查看两端初始个人/公共的full和browser；重开时host crop与guest full；empty时两端个人/公共的full/crop组合；另看59本地/网络before图。不以保存成功代替视觉结论。

亲看结果：个人标题22与混合类别可读，攻击/普通技能/令咒/事件正面、未觉醒技能专属升华技背面明确区分；host公共第一张显示蓝色局势背面，后两张保持声明的局势正面；guest公共恢复后的三个正面符合它当时source。重开个人3、公共2排列符合source；空列表标题0且中心empty文字，无残留槽。浏览器在最上层、正常背景遮暗，但没有行动/阶段过场盖住卡牌或关闭按钮。没有使用旧Round72图片冒充本轮视觉。

## 执行、冻结和清理

真实命令：

```bash
python -B newtests/run_round71_shared_discard.py --label round73-final --window
```

manifest：`E:/scratch/round71-shared-discard-round73-final/isolated-cc4be315cb8b48d0bbaff7b600a2f77b/manifest.json`

manifest SHA256：`1842ad65c07875783bb8d05e0287fb176188ce5362cbed53a2a302cf70729605`

|阶段|PID|秒|检查/失败|退出|
|---|---:|---:|---:|---:|
|原168 headless|38048|7.168|168/0|0|
|card_browser headless|21428|7.024|4/0|0|
|drawer_dismiss headless|37756|7.088|1/0|0|
|privacy headless|31468|4.569|137/0|0|
|discard window|1412|17.055|221/0|0|
|原59 window|34344|13.913|59/0|0|

主probe PID37600、真实worker5620均读回物理E `generated/appdata/FateDomination`、worker_pool20；probe/import/六专项八个Job阶段均exit0、ActiveProcesses=0、log_handles_released=true。全部stdout/stderr和归档engine日志 **0 SCRIPT ERROR/ERROR/WARNING**。`artifact_readback=true`（交付前再次逐artifact SHA读回）、`source_drift={}`、`freeze_drift={}`、`cleanup=generated_removed`，当前source再次逐hash对freeze仍无漂移。

|文件|最终SHA256|
|---|---|
|board|6a6cecf4f5eb4672f5af77f4d9ac28d62543a0260e3d786f0bcd7781db52bc5d|
|presenter|dd409f9d35d6be0078fc83c6198dd1c1deed9c7f35e4a98be34812e39bf464b6|
|builder|9a7ed25688ded565bce41b0a8b7473f8067553b55629fbb7d7ce88a276ec831e|
|mirror|8007a3cc6e2e1ed0bb319ba3e1b3bd21fb825e7b9bc24f3f212a724c514eef20|
|newtest gd|6977fa0789866083340511000f3a175bbe69c0888f54c3300a06e5ca6245154f|
|newtest tscn|361ab12e01562ef0ab9f977f886cc88422f5a44c4a7eb50afa2fa1e41b990cf4|
|runner|94e22e1cba519c1ee1f4ff6ff2ef4f76bf76b016ad38896e9a15b446ed3e6028|
|原Godot|ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424|
|原正式release DLL|92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd|

没有替换引擎/DLL，没有操作用户PID28100。此为新增测试的独立epoch，不计入别的owner先前完整headless依赖闭包，不把旧freeze回归与本次拼接。

## 保留首次失败与两次针对修复

1. window1 manifest：`E:/scratch/round71-shared-discard-round73-window1/isolated-722804bb36a743aea681386a3cbaaf20/manifest.json`。原168/0；窗口13检查、首次发布超时及120秒看门狗，另freed board错误。第一因果是夹具同牌区重复对象ID被正式mirror拒绝，且没有发布playing房间修订。修复独立克隆ID与正式room revision/_publish，保留原mirror，发布失败立即停止；不是生产入口bug。
2. window2 manifest：`E:/scratch/round71-shared-discard-round73-window2/isolated-514db5aafa104071ab8b110b798891d6/manifest.json`。窗口exit0、219/0但有SCRIPT ERROR，runner正确判FAIL、不执行后续59。第一因果是原攻击牌state夹具直接读 `_is_closed`，新通用卡/局势类型没有该声明。第二次修复仅window选择声明感知观察，原168默认逻辑保留；同时加入真实暗置公共局势样本。

随后完整FINAL一次绿通过，未散跑40分钟，无生产patch或测试绕过。

## 未覆盖/不得扩大结论

- 本地没有个人/局势点击入口，不能提供不存在能力的打开GUI证据；若main要添加该能力，需独立生产决定和新冻结，不在本轮补。
- 未做OS硬件输入、多进程两窗口、多机/跨网、所有隐藏卡种穷举；轮询两真实session由同一GUI执行者顺序验两端board。
- 不扩跑其它50suite/battle_play_groups/全量headless；与Round72分组视觉证据及其它owner完整headless结果保持不同epoch。
