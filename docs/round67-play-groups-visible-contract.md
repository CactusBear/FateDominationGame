# Round67：出牌组可见合同（一次夹具修正、一次同冻结验收）

## 结论：逻辑 PASS，完整视觉验收 ASSERTRED

- 生产 board、presenter、scene、规则、原 Godot 和正式 DLL **均未修改**。
- 同一冻结只跑一次：headless **63/0 exit0**；window **65/0 exit0**；共享浏览必要回归 **55/0 exit0**。程序逐项比较 Round64 headless CHECK 多重集，原 **56** 项没有遗漏；新增7项，两张窗口截图额外2项。
- 新区父组生命周期已实际证实：过渡结束后正式刷新，四组 `shown=true`、父组及牌面有效 alpha=1、真实viewport/裁切包含，不再是叶节点1帧假绿。
- 两区的两牌组和六牌组都由真实 GUI 头像点击展开；六牌原生全屏和裁片可见 **5+1** 分行、六张独立分离，无互相遮挡。
- **工房全四组全牌无遮挡未通过**：真实战区点击触发“还没轮到你行动”提示，遮住第三组头像/卡。新增几何条件只检查御主、席位及Hint，漏了 TacticalConfirm；所以程序65绿仍是这部分合同的假绿。原图保存为本次首个原生视觉 RED，不改 fixture、不补跑、不补图。
- 深山町四组十槽分离可见，但其中暗置槽是纯黑，而不是原卡背图案。原“不是face图片”的检查过弱，未证明真实卡背纹理。因此不宣称完整暗置卡视觉合同通过。
- 全部stdout/stderr/归档logger **0 SCRIPT ERROR / SHADER ERROR / ERROR / WARNING**；五阶段Job ActiveProcesses=0、日志句柄释放；source/freeze drift={}，产物SHA读回=true，自有generated已删除。没有操作用户PID28100，没有跑全99。

## RED前证据与观测对象

完整读取 `docs/round64-shared-browsing.md`、原fixture和四张最终PNG；不是依赖旧总结推断结果：

- 旧深山町图：四组可见，六牌折叠堆，未全牌验收。
- 旧工房图：背景和席位可见，四组牌不显。
- 旧本地弃牌图：原标题和两张牌可见，行动阶段横幅覆盖浏览器中部。
- 旧网络弃牌图：原网络标题、两牌可见。

旧 `settle_presentation()` 只观察 Who、slot 本身透明度，忽略父group和Main/Strip祖先，目的区1帧返回不能证明屏幕可见。结构合同必须观察 **父+祖先**，不是叶槽位自己的alpha。

## 定义与全部相关入口追踪（只读）

`battle_board_v2.gd`：

1. `_select_scroll()`（2007）：更新当前区，真实0.48秒Tween改变卷轴尺寸与Main透明度。它不调用 `_bind_player_row()`，也不把shown塞给组。
2. 所有选区调用：`_ready`本地/网络338、404；`_update_default_area`606、608；真实移动 `_handle_scroll_hover`1991；区域数量变化2126。`_handle_scroll_hover`要求非零relative的MouseMotion，正式浏览选区是鼠标移动，不是发出移动规则请求。
3. `_process()` 563–566按已有REFRESH_INTERVAL调用公开 `refresh_all_ui()`；`_bind_strips`→`_bind_main`1779→`_bind_groups`5736→唯一 `_bind_player_row`调用5765。
4. `_bind_player_row()`（5801–5808）在卷轴Tween不运行且 `_strip_open()`真实尺寸稳定后首次设置shown；父group没有shown时modulate.a=0。`_strip_open`5967的帧缓存会写入生产观察缓存，因此测试不调用它，仅读Tween/open、source.seq和实际节点几何。
5. `_bind_groups`5760–5764给Who和CollapseHint连上 `_on_play_group_toggle`；其唯一展开调用1904→`_set_group_spread`1889→现有 `_layout_play_groups`6463。其它 `_set_group_spread`调用：残留牌堆5664、折叠牌点击5924；本测试没有调用这些私有方法。
6. `_layout_play_groups`按模板声明 `expanded_columns=5 / expanded_visible_rows=2`布置六牌成5+1，复用真实尺寸/位置Tween；测试不自造布局规则。
7. 战区左键链：`_on_strip_gui_input`1822→`_on_battlefield_clicked`5356→`AreaActionRules.block_reason`35；current_player不是local_player时67–68返回“还没轮到你行动”，5372通过 `_show_tactical_confirm`3549打开正式提示。

## 唯一夹具版的函数说明、解耦边界

仅改 `tests/battle_play_groups_test.gd`：

- `run()`：保留正常board process、SeatController.REMOTE及reset_progress代际隔离；原56逻辑、公开RegularPlay.add两次、残留分区、身份、顺序、暗置、尺寸、迁区均保留。窗口要求显式 `-- window`。两区截图前都经真实头像GUI展开。
- `settle_presentation()`：被动等待卷轴Tween结束，记录当时source.seq，再要求后续真实正式刷新seq更大；父组shown与祖先alpha/visible完整；真实飞行层/队列/busy清空；节点携带的布局Tween停止，连续跨帧几何稳定。上限沿用600帧，不增加固定秒数等待，不强refresh、不写透明度、不私有invalidate。
- `visual_state()`：计算node.self_modulate × 自身及祖先modulate；祖先self_modulate不影响子节点。卡/组global rect须被viewport与所有clip_contents祖先交集包含；仅给0.5px浮点/像素边缘容差。输出完整祖先路径、visible、alpha、rect、clip作为首状态。
- `presentation_state()`：只读数据与节点，检查四组、十卡、六牌组、展开状态、牌图有效可见、Tween与几何；展开后检查十卡两两不相交及御主/席位/Hint遮挡。**明确缺口：没有枚举ModalLayer/TacticalConfirm，texture != null也未加进此条件，所以它不能独立证实全部视觉。**
- `gui_click()`：Viewport.push_input独立派发移动帧，再核对实际hover为目标/后代；随后左键按下/抬起，订阅真实gui_input计数downs=1，不emit signal。目的区实际hover是SeatScroll，鼠标移动已触发选区，左键随后冒泡至strip。
- `expand_and_verify()`：对>1卡组实际点击Who头像中心，检查真实expanded变化，再等真实刷新与布局；六牌不能按默认折叠堆验收。鼠标最后移到卷轴标题内避免tooltip遮牌。
- `failure_shot()`：父组未shown或等待条件失败时保留首次完整viewport图，不覆盖既有RED。此次这些程序条件均绿，所以没有生成 `round67-first-red.png`；本次原生视觉RED原件就是 `battle_play_groups_destination.png`，不能声称自动ASSERTRED已覆盖提示遮挡。

复用正式GUI入口和正式帧刷新，规则不复制进测试；观察器与输入辅助只在fixture内。唯一runner修改 `tools/tests/round64_shared_browsing.py`：所有子进程TEMP/TMP/TMPDIR补到独占E目录；窗口显式传window；记录runner依赖SHA；最终严格检查全部日志0error/0warning；manifest明确logic PASS不自动认证视觉。共享浏览GD内容SHA与Round64完全相同。

## 真实时间链、输入回执

同一window stdout：

```text
VISIBLE_MODE display=Windows args=[window]
深山初次十牌：SCROLL_COMPLETE seq13；VISIBLE_COMPLETE frames240 seq21
深山两牌头像：downs1 hittrue expandedtrue；frames27 seq22
深山六牌头像：downs1 hittrue expandedtrue；frames27 seq23
深山全牌稳定：frames28 seq24
目的卷轴：GUI_CLICK hover=.../Strip/Seats/SeatScroll downs1 hittrue
目的过渡结束：frame28 seq26
目的首次正式显现：frame60 seq27，四父组showntrue/alpha1
工房两牌头像：downs1 hittrue expandedtrue；frames29 seq28
工房六牌头像：downs1 hittrue expandedtrue；frames29 seq29
工房全牌稳定：frames28 seq30
```

两个最终全牌状态十个Img均contained=true、有效alpha=1；父组可见不再取叶节点作为代理。这些仍不能排除其它兄弟/高层控件遮挡，后者由原生图发现。

## 原生全屏与裁片结果

在同一evidence目录加载四张完整1920×1080图；另加载深山 `[480,320,1630,600]`、工房 `[460,320,1660,640]`原尺寸裁片。没有让另一个视觉模型判图，没有新生成补图。

|图|SHA256|原生判读|
|---|---|---|
|battle_play_groups.png|ac89ae27226dac37af25b37a19af1dca8baac85af4e8887c3ee03a9dc9373d39|四组十槽分离；六牌5+1清晰；暗置槽纯黑，卡背纹理合同未证实|
|battle_play_groups_destination.png|251acbad18f368ee5cdc3b14c803fd7de727cbe1942530007576dc45dce1cdbe|四父组正式显现；六牌5+1可见；第三组被“还没轮到你行动”框遮住，**全四组无遮挡ASSERTRED**|
|round64-local-shinto.png|4da09543dde9306ce9f50d2e121221adb8b98d704fa3811a1c1f27c7bd2dc643|原本地标题及两牌；原有阶段横幅覆盖中部，未改这个独立层级行为|
|round64-network-shinto.png|60b5489f28bfb5d1596cd774144f63e69d954301ae7a0d81f06cc97368423717|原网络标题及两牌，未见异常色块|

另原生查看正式 `data/card_backs/attack_card_back.png`：是蓝底Attack图案，不是纯黑。不能把黑槽“不是face”解释为卡背已正确显示。

## 交主代理的最小建议（未执行，不增加一次试版）

1. **遮挡首因**：真实浏览移动选区之后，测试仍左键点战区；该点击经正式冒泡进入部署/移动拒绝提示。这里没有证据要求修改生产规则或自动隐藏提示。下一次获得新预算时，优先让fixture把 `ModalLayer/TacticalConfirm/Box`加入观察遮挡集合，并通过正式 `Box/ButtonsRow/BtnCancelAction`（“知道了”）GUI关闭后再等visible=false；不能调用cancel函数、hide()或改透明度。纯浏览与规则点击应明确区分。本轮按一次约束没有做这个修正。
2. **暗置黑槽**：`MatchViewBuilder.card_view`343–351为不可见敌方暗置卡有意不发送专属back_image；`_bind_played_cards_row`5855–5858直接加载该空back_image。源码能解释黑槽机制，但本轮未采实际texture/path，因此还不能认定生产唯一首因。最小生产候选是由权威投影显式提供隐私安全的通用卡背（复用已有LoadHelper.resolve_card_back，不泄露专属来源）；renderer只消费声明，不从本地规则对象猜类型。需主代理先证实安全类别合同，再动生产。原暗置测试应要求非空真实back texture及预期路径，而不是仅!=face。
3. **禁止伪交付**：manifest.passed仍保留原始逻辑值true，且visual_acceptance字段明确不能认证视觉。本文把用户完整验收判为ASSERTRED；不得替换原日志、涂图或拼接另一版通过记录。

## 唯一命令、冻结与安全账

仓库根：

```text
python -B tools/tests/round64_shared_browsing.py --label round67-visible --window
# runner exit0；3专项exit0；整体用户视觉合同未通过
```

每scene180秒、fixed-fps60；原引擎只复制到E独占generated运行，生产DLL不替换。产物目录：

`E:/scratch/round64-shared-browsing-round67-visible/isolated-77aec0843e4b4172ab874ed5a17c6246/`

- manifest SHA256：`57118e78183b38fd7df7c1f3e2fba66bf720fbcf31529148e8f7980683193dd4`。
- 主探针PID30952/子26988，真实user://及receipt读回物理E；worker_pool20。probe1.575秒、import20.131秒、headless6.896秒、window12.704秒、browsing11.083秒，各自Job0/句柄释放/exit0。
- 当前source全白名单逐文件SHA与manifest再次比较，`CURRENT_DRIFT={}`。三个专项使用同一冻结/同一生产依赖。原56 CHECK多重集缺失 `{}`，没有削弱原业务。
- generated_removed，只保留evidence/frozen-inputs、原PNG、原stdout/stderr/engine-logs及manifest。未commit、未push、未改其他dirty。

|冻结对象|SHA256|
|---|---|
|battle_board_v2.gd|43b7be1d30dd785dbc3ef5cde0f02bed50e75f939944d0f64e08f1afc2007906|
|v2_view_presenter.gd|dff5b30f48655ad8637218d082717df0da6a543cad37fd643fe35f2d8b259a6e|
|battle_board_v2.tscn|39a681e1f00578e2a2d7278b241262a72a78afe99937d99553c6ebf615c0fb6d|
|battle_play_groups_test.gd|845ed2539e79a0511f7411ac904bd183b31e9ca84fe21d5e8092055d7fd66560|
|round64_shared_browsing.py|a0e49e96baf57a39207ccc3720f4ab97aba579653a8a885804813ff93385fe65|
|共享浏览生成GD（与Round64相同）|3349f07e75e2782352f9521c87496c5f430bdccbf1c06bd03901f8a67d5e1f45|
|原Godot|ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424|
|正式signal release DLL|92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd|

## 尚未验收

工房四组全牌无遮挡、暗置牌真实卡背；自动观察器的任意模态/兄弟遮挡与texture存在合同。历史空位置唯一原因、Round58随机输入缺证、多机/LAN/恢复/发行不是本轮覆盖范围。此次输入为正式Viewport GUI派发，不宣称OS硬件或真人多机输入。
