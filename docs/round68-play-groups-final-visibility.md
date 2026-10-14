# Round68：模态真实关闭、暗置黑槽首证据（最终仍 RED）

## 结果，不以逻辑通过代替视觉通过

- 仅一次夹具版本、一次同冻结最终运行；**没有第二版修补或补跑**。生产 builder / board / mirror / LoadHelper / scene / data / DLL / Godot 均未改。
- “还没轮到你行动”正式 TacticalConfirm 被检测为 blocking；通过现有 `Box/ButtonsRow/BtnCancelAction`（“知道了”）真实 Viewport GUI 点击：`hit=true, downs=1, pressed=1`，随后 `visible=false, blocking_modals=[]`。不 hide、不 emit、不调生产私有 cancel，不改变规则拒绝。
- **局部关闭成功不等于完整目的区闭环成功**：窗口移动到提示按钮时，正式底层 hover 从工房 index0 选择回深山 index1。最终工房 `open=0`、父组未 shown；程序与原生画面均 RED。深山空背景不是“工房四组无遮挡”。本轮按一次约束保留首红，不再试第三版。
- 暗置黑槽首证据已闭合：实际 source `observer=6 / owner_id=0 / own=false / visible=false / concealed=true / back_image=""`，槽 `Img.texture=null / resource_path=""`。深山稳定截图中该槽纯黑；祖先颜色全白、有效 alpha=1、无材质/着色器、无可见槽内 overlay，排除把它解释成祖先染黑或遮罩盖黑。**hidden black 未解决，用户 visual gate FAIL**。
- headless **65/0 exit0**；window **65/2 exit1**；共享浏览 **55/0 exit0**；顶层 runner **exit1**，`logic_passed=false / visual_gate.passed=false / passed=false`。不是 manifest logic PASS 掩盖视觉。

## 修改与耦合边界

只改以下三文件：

1. `tests/battle_play_groups_test.gd`：
   - 原 RegularPlay、残留分区、身份/顺序、暗置非face、四组/十槽、迁区及两区展开逻辑保留；增加 `acknowledge_tactical_alert()`，真实读取提示文本与按钮、观察 pressed、等待不可见。
   - `visible_blocking_modals()`枚举全部正式 ModalLayer 子面板，以及 NetworkChoices 的 Panel/ConnectionWait/Guard、IdentityInheritancePanel、CardBrowser、LogBrowser、EventDiscardMenu 和动态 Window。snapshot `ready` 要求没有这些可见阻挡；不只看叶节点 alpha。不声称这是任意兄弟节点/任意渲染遮挡的完整求解器。
   - `visual_state()`增加完整 modulate/self_modulate、material、shader、use_parent_material 祖先观测。
   - `concealed_evidence()`仅对白名单字段采样 source、实际槽 texture 与 overlay。known-object 对照仅在 `_source_is_local && network_session==null` 下输出到本地 fixture 日志，不写入 source/mirror/命令/网络 payload；绝不从已知对象猜牌类型来补图。
   - `VISUAL_GATE`独立输出 texture RED，不把“不是face”升级为卡背通过；保留原业务 CHECK。
2. `tools/tests/round64_shared_browsing.py`：保留共享浏览生成 GD 原样；记录 scene 的 `VISUAL_GATE`，分别保存 logic_passed 和 visual_gate，任何 hidden black 使顶层失败。原证据归档、日志严格门、Job、SHA读回、清理不放宽。
3. 本报告。

输入辅助与只读观察器只在 fixture，复用正式按钮/GUI分发和正式帧刷新；没有把规则复制到测试，也没有生产例外。唯一新版已实际执行并保留失败，未继续叠加修复。

## 原逻辑覆盖核对

程序比较 Round67 与本轮 stdout 的 CHECK 文案**多重集**：

- headless：原63项全部实际执行，缺失 `{}`；新增2项是模态阻挡检测与真实确认关闭，合计65。
- window：原65中有2项工房头像展开未执行（player0/player3），原因是目的区 settle 先失败，原有 short-circuit 阻止继续交互；新增2项模态检查，实际合计65。不能称原窗口全部逻辑通过；未删代码或改通过门。
- 窗口真实失败项：`destination area contains all four relocated groups`、`workshop all ten cards including six-card group visibly separated after avatar GUI input`。
- 共享浏览55项通过；本地弃牌浏览原有行动阶段横幅仍覆盖中部，不在本轮修复范围；网络弃牌原标题与两牌可见。

## 模态时间链与新增首红

window 原日志：

```text
GUI_CLICK destination-scroll: hover=.../Strip/Seats/SeatScroll hit=true downs=1
TACTICAL_ALERT_BEFORE: description=还没轮到你行动 button_text=知道了 active_strip=0
                     blocking_modals=[.../ModalLayer/TacticalConfirm], ready=false
GUI_CLICK tactical-acknowledge: point=(1084,555.5)
          hover=.../Box/ButtonsRow/BtnCancelAction hit=true downs=1
TACTICAL_ALERT_AFTER: pressed=1 visible=false blocking_modals=[]
VISIBLE_ASSERTRED: active_strip=1, target strip=.../Strips/Strip,
                  open=0, seq=44, parents_shown=false, ready=false, blocking_modals=[]
```

原生 `round68-tactical-before.png`确为工房标题、正式提示及“知道了”；最终 `battle_play_groups_destination.png`已经没有提示，但标题回到深山，出牌区域为空。读源码确认：board `_input` 1971–1972无条件交 `_handle_scroll_hover`；1977仅排除 Pause/debug、1979排除 Board，未排除 TacticalConfirm；真实非零 relative 鼠标移动会按底下 strip rect 调 `_select_scroll`（1988–1991）。这是本次正式输入暴露的导航侧效应，非 hint 未关闭。

**供main后续处理，不在本轮追加试版**：关闭后需通过真实 MouseMotion 把光标移回目的区现有卷轴标题/导航区域（不再次左键点战区），再观察 active_strip=目标、Tween结束、后续source刷新、四父组shown和展开；不能直接 `_select_scroll()`、私有刷新或提高等待秒数。若改生产模态鼠标路由，必须另立授权与回归，不能混进本轮fixture任务。当前新版缺少这一真实导航恢复，因此完整闭环仍未交付。

## 暗置首证据及确定的首因

headless 与 window 的 first-concealed-bind、miyama-final（以及目的区source）一致：

```json
{"source_local":true,"observer":6,"owner_id":0,"own":false,
 "visible":false,"concealed":true,"back_image":"",
 "projected_keys":["id","concealed","visible","back_image"],
 "texture_nonempty":false,"texture_resource_path":""}
```

这里 `texture_nonempty=false`表示实际 `TextureRect.texture == null`，不是资源已加载但 path 未填。

本地fixture已知对象 `_is_concealed=true`，其声明背面为 `res://data/card_backs/attack_card_back.png`；该事实仅用于本地对照，**并不授权公开攻击类型**，不得网络补发、不得渲染器从 `_card_back_img` / BaseAttack / 路径推断类型。真实source只保留上述四个隐藏白名单字段，无name/image/kind。

深山最终 Img：有效 alpha=1、visible_in_tree=true、contained=true、rect约 `(667.75,353,65.23,92.12)`；完整祖先 modulate/self_modulate 均白色且alpha1，所有material_class/shader_path为空，所有采到的槽内辅助控件不可见；不存在可见 ConcealOverlay。工房最终alpha0另有明确原因：它已被hover切回深山而收拢，不能把这个alpha0用作深山黑槽的原因。

实际机制已逐段只读确认：

1. `view_builder.gd` 343–351：`visible = own or (...)`，隐藏敌牌故意令 `back_image=""`，注释明确防止专属卡背泄露从者名/职阶/来源。
2. `battle_board_v2.gd` 5852–5858：Dictionary牌为concealed或不可见时只消费 source `back_image`，不从known-object补图。
3. 同文件 `_bind_card` 937–939 → `_set_img` 902–904：空img明确令texture=null。
4. 实际source为空、texture=null，与该确定分支一致；原生黑槽是模板黑底露出，不是加载了正式卡背又被shader涂黑。

这确认了**本fixture暗置槽**的隐私空背面→空纹理首因；不外推所有卡种/网络观察者均已测过。未修改隐私策略，未修data，black继续FAIL。

## 提交main集中确认：两种明确隐私安全方案（均未执行）

当前 LoadHelper `CARD_BACK_FILES`只有 master/servant/attack/skill/event/situation/climax_situation/command_spell/upgrade_skill 的按类型卡背；实际 `data/card_backs`也只有这些PNG及import，未发现已声明中性通用背面。所谓“通用”是类型内通用，不等于隐藏类型安全，不能直接默认attack。

### A. 权威显式投影同一中性卡背（建议优先讨论）

- 正式内容新增一张不含角色、职阶、来源、牌种暗示的中性背面，并新增一个**公开数据声明**，例如语义名 `hidden_card_back`（字段名是待定设计，非声称现有schema）。对所有不可见隐藏牌使用完全相同的声明资源。
- Builder仍不发专属路径或kind，但 `back_image`明确填该中性背面；board继续消费声明、不推类型。
- 所需确认：中性图案及其资源路径/内容包归属、所有隐藏牌统一适用范围、缺声明时明确拒绝/仍RED的行为、网络内容同步/哈希纳入该资源；明确该资源可公开且不编码隐藏分类。
- 后续验证：不同隐秘类型投影背面相同、敏感字段仍缺失；mirror兼容；本地/网络texture非空且path为同一声明；原生图验收。不是把fixture known对象专属背面发出去。

### B. 保留隐私source空back_image，增加公开中性展示政策

- Builder隐藏字段维持现状；在正式、可同步且可校验的公共展示数据中声明 `hidden_back_policy=neutral_placeholder` 与唯一中性背面资源/中性图案规范（以上命名同为待定设计）。Renderer只在source明确 `concealed=true && visible=false` 且政策已声明时消费该中性展示，不查看本地类型或known对象。
- 所需确认：这是对空back_image的**显式正式展示契约**而非静默fallback；统一所有隐秘分类、政策作用域和内容包版本、缺失政策/资源时RED；若选择程序绘制中性图案，也必须由正式数据声明图案和适用范围，不能仅以黑底占位交付。
- 后续验证同样覆盖网络隐私、缺声明拒绝及原生中性卡背；生产renderer会有一处显式政策消费，耦合和维护成本高于A，但不改变隐藏source背面为空的协议含义。

两方案都需要main集中确认中性背面数据/政策；本轮无权新增。若希望公开牌种并用分类背面，需要额外规则授权，**不属于上述安全默认**。不静默用attack背、专属背、名字/图片路径猜测。

## 原生全图与裁片判读

直接原生加载本次1920×1080 PNG；深山裁片 `[480,320,1630,600]`，最终目的区裁片 `[460,320,1660,640]`，提示裁片 `[740,470,1180,610]`。没有辅助视觉模型、没有重新生成或涂改截图。

|原图|SHA256|原生结论|
|---|---|---|
|battle_play_groups.png|7f636fd436a2d3e3d55d3ca64b31620b5a285c46fac00005e947dffd02651372|四组十槽；六牌清晰5+1，无提示遮挡；暗置一槽纯黑，视觉FAIL|
|round68-tactical-before.png|04fd31f47c9c54ef7cb51a18799c3c1e722b8da103b06a1aeabd00d09f696cdb|工房正式拒绝提示及知道了按钮真实存在|
|battle_play_groups_destination.png|7070930bc49ca8406b38b2df7edbe51b7a35929227ee9e74c596c4af40f9498b|提示已消；错误回到深山，牌区空，目的区视觉FAIL|
|round64-local-shinto.png|3d6db1c108198cb282d7fd71f98ffb0ea0ca34e7e7f2f9b0ff508497ed6cd876|标题与两牌可见，原有行动阶段横幅仍覆盖浏览器中部|
|round64-network-shinto.png|2761cd2b0fd677afc2b76ed1bf2e563b4849f7bf565ec8d4d6c8e2ef608b3917|公共标题与两牌可见|

`round68-first-red.png`也已保存，SHA为 `3730225a878ede518f4159f8d978d053024534ec7c7d62c9d48f5233d45e8217`。不把最终错区空画面或旧Round67工房图拼成此次通过。

## 唯一真实命令、日志、源码和清理

```text
python -B tools/tests/round64_shared_browsing.py --label round68-final-visible --window
# runner exit1；每scene180s，fixed-fps60；未跑全99
```

证据根：`E:/scratch/round64-shared-browsing-round68-final-visible/isolated-4c8f7b4a1b5149ca8db805f39b2e75f3/`

manifest SHA256：`e90eed2cbb15c9690391cb1a519af1eaf6c1dd31ccf091d336326105e98e44ae`。

|阶段|PID|exit|秒|Job active / log handles|
|---|---:|---:|---:|---|
|probe|6340|0|1.485|0 / released|
|import|39880|0|20.426|0 / released|
|headless|32532|0|8.865|0 / released|
|window|39784|1|17.905|0 / released|
|shared55|27436|0|11.915|0 / released|

全部stdout/stderr/归档engine logs：0 SCRIPT ERROR / SHADER ERROR / ERROR / WARNING；窗口业务CHECK失败按原样保留。主/派生真实物理E探针回执在manifest；源码和冻结 drift都 `{}`，当前白名单逐文件复核也 `{}`。产物每个SHA再次读回=true，generated实际不存在，仅保留evidence/frozen-inputs、原始日志、PNG和manifest。没有操作用户PID28100，未commit/push，未改其他已有dirty。

|冻结对象|SHA256|
|---|---|
|battle_play_groups_test.gd|210872e9cf99ce36511bd892ffd1745ff00a8fed8943a06dd3130f3e71e55cd4|
|round64_shared_browsing.py|bab3e35b28504401b802fb3d0b722a1dd02553a0ea423b7b77efeb4005320685|
|battle_board_v2.gd|43b7be1d30dd785dbc3ef5cde0f02bed50e75f939944d0f64e08f1afc2007906|
|view_builder.gd|5d570263ec5c31ccd2f5e08b7116dda951be828607819a59cbdea301022979e9|
|view_mirror.gd|deb091a12f6eb47693934a24653e9b5594e675ee5811aebbcc538bd8bdaeabbf|
|正式signal release DLL|92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd|

## 尚未交付 / 不确定范围

完整工房四组展开无遮挡仍失败（新增导航侧效应）；暗置真实中性卡背仍未定义/未修，视觉门必须FAIL。模态关闭局部已验收，但不称完整业务闭环通过。原生输入使用Viewport.push_input，不是OS硬件输入；多机、LAN恢复、发行、全卡种隐私对照不在本轮。复用教训可由main归入Windows输入技能：真实关闭按钮的MouseMotion也可能触发底层hover导航，关闭后应重新通过真实浏览移动确认目的区，而非只断言弹窗不可见。
