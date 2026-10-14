# Round42 原生 modal / zoom 生命周期

## 结论

- **最终 `final4/` 同一冻结真实窗口 GREEN：新增生命周期专项134项、令咒原专项42项、local_restore原专项25项，共201项；三套自然退出0、failures=[]、无 SCRIPT/SHADER/engine ERROR。**
- 原生查看本轮 PNG 与 PrintWindow 客户区 BMP：单机/认证ENet pending 的选项与放弃按钮不再被令咒浮图遮住；关闭后合法 hover 恢复。
- **地图不修**：关闭选择的同一按下/抬起没有地图 GUI 命中；地图提示发生于随后新输入。未加固定延时、全局禁地图或吞下一次点击。
- 补获并修复本地真实暗置卡 zoom 仍取正面的隐私问题；网络字典分支原本取卡背。正式右键翻暗及翻回、旧 hover 回调、翻面 tween 自然结束均实窗通过。
- OS客户端区已捕获并原生检查；DPI近捕获元数据已记录。**同帧桌面裁片/DPI三方比较、local_restore展开瞬间OS客户区仍未验**，见末节，不冒称全视觉通过。

## 所有权与改动

生产仅修改 `scripts/game_scene/battle_board_v2.gd`。`scripts/net/ui/network_choice_panel.gd`、renderer、场景、其他生产、旧GUI tests均只读，本轮前后hash相同。
新增 `tests/choice_modal_zoom_lifecycle_test.gd/.tscn`；继承只读 round41 窗口夹具的正式开局、RSA认证和实际 GUI 输入，不复制 UI、规则或命令实现。
新增证据运行器/验证器于 `reports/refactoring/round42-modal-zoom/`，本报告于 `docs/round42-modal-zoom.md`。

仓库本来存在大量未提交改动；`git diff` 相对HEAD不是本轮差量。`owned-board-delta.patch` 与 `scope-verification.json` 精确绑定本轮前后；逆向去掉本轮补丁后hash严格还原round41原始board，没有覆盖其他代理工作。

### 根因与复用

1. `_hover_zoom_source`、`_zoom_hover_candidate_id`、`_zoom_hover_elapsed`、`_zoom_hide_remaining` 是唯一查看owner与悬浮/保活状态；zoom本身没有延时Callable或Tween。`_show_zoom_for`、`_show_desc_for`、每帧 `_update_hover_zoom_keepalive` 原来没有modal屏障。
2. 复用已有 `_modal_blockers`，在 `_bind_card_view_controls` 中绑定正式控件 `visibility_changed`；任何 `show/hide/visible` 都同步调用已有 `_hide_event_zoom()`，清owner、候选、成熟计时与说明。打开和关闭均失效；多个modal重叠时仍按全部当前可见状态判屏障。
3. 四个共享入口检查 `_native_modal_visible()`：显示浮图、显示说明、hover候选、每帧keepalive。modal期间旧Callable调用也不能复活；最后modal关闭后从当前真实命中按既有hover门槛重启，不加新延时/第二外壳。
4. `bind_zoom_for_card` 的本地BaseCard分支原先只取 `_card_img`，虽隐藏说明仍泄露正面浮图。现在暗置取对象声明 `_card_back_img`，与网络字典口径一致；复用 `_bind_zoom_data` 的换图失效和 `_can_show_card_desc`，不改规则。

### 原生入口审计

|原生控件|打开入口|关闭/重绘入口|共同生命周期|
|---|---|---|---|
|EffectChoice|local `_show_effect_modal` / network `_render` → shared renderer.active → `_open_confirmation_panel`|local pending刷新/取消/提交；network `_hide_native`、`_completed`、请求失效/换声明|visibility_changed|
|CardSelect|shared `_show_card_select_panel`（local/network都用）|local `_close_card_select_panel`/确认取消/调试丢弃；network隐藏与回执|visibility_changed|
|PlayerSelect|shared renderer.players（local/network都用）|local pending清理/取消/换声明；network隐藏/回执/失效|visibility_changed|
|EffectResult|`_show_effect_result`|`_on_effect_result_closed`、批通知清理|visibility_changed|
|TacticalConfirm|`_show_tactical_confirm` → `_open_confirmation_panel`|execute/cancel/局面变化/调试丢弃|visibility_changed|
|PauseMenu|`_toggle_pause_menu` → `_open_confirmation_panel`|`_close_pause_menu`/返回菜单|visibility_changed|

六个控件逐一实窗验证打开立即回收、旧回调无效、隐藏后真实hover恢复，另验两个modal叠加后部分关闭不解锁。
location_choice 是地图选点提示+LocationCancel，不是阻止地图交互的模态选择窗；不把它作为全局modal。CardBrowser允许浏览卡图，不加入禁止查看列表；日志/抽屉保持原输入契约。
共享renderer只生产显示声明，网络panel继续只承担命令/回执适配；无需修改network_choice_panel，也没有增加新壳。

### Tween与代际

zoom没有自己的Tween，不能凭名称编造zoom tween generation。确认面板的deferred fit只改位置，不显示浮图。真实牌面 `_play_card_flip` 已按frame持有 `card_flip_tween`，开始新翻面先kill旧Tween、节点回调按instance_id取；zoom绑定在刷新时即更新，不等待翻面中点。真实翻暗专项立即核对zoom已取卡背，再等既有 `card_flipping=false` 自然结束核对卡位纹理；没有强行清busy、固定延时或新造异步状态机。

## RED / GREEN实证

- `red/`：生产修改前非headless exit1、109 checks。明确失败为本地旧zoom owner未关闭、modal期间旧hover/说明复活、持续hover遮挡取消GUI，以及六个modal的共享生命周期；原生 `round42-local-pending.png` 直接看到浮图遮住弹窗。无脚本解析/engine错误。
- `red-dark/`：夹具只查卡中心，手牌中心越过viewport，没找到候选；这是夹具失败，不计业务RED。改为真实可见交集点，未移动生产布局。
- `red-dark2/`：130 checks，仅本地“真实翻暗后旧hover回调只能放大卡背无说明”失败；网络相同真实输入通过。确认BaseCard取正面的根因后才修绑定。
- `final3/`：新增卡位纹理断言在单机仅按下/抬起两帧后即采样，Tween尚未结束而红；网络pump实际等待50帧。仅修自有夹具按 `card_flipping` 等自然结束，不修改生产Tween。
- **最终只计 `final4/`**，134+42+25。`green1/`、`final/`、`final2/` 是中间冻结，不累加、不拼接为最终通过。

新增134项覆盖正式local/认证ENet activate→取消→重开→真实选项、资源不预扣/只付一次、旧hover/说明Callable、modal期间持续悬浮、六个native控件开关、重叠modal、字典暗置重绑、真实持有攻击牌右键明暗置/翻回、既有Tween自然结束、事件穿透审计。
前哨与部署继续经共同adapter，不直接操作效果exec；输入为 `Viewport.push_input` 移动/按下/抬起，GUI hit日志核对正式控件，不emit pressed。不是OS硬件鼠标输入。

## 地图事件审计：不修

`final4/evidence/choice_modal_zoom_lifecycle_test.stdout.log` 的 `INPUT_AUDIT`、`MAP_GUI_EVENT`、`NEW_CLICK_AUDIT` 登记每次分发serial、原event instance_id、handled与tactical状态。Godot GUI转换可复制event，不能用对象ID差异代替事件身份；用同一同步分发serial关联。

- local选择按钮serial7/8：handled=true、tactical=false、map_events=[]。随后等权威/截图仍无地图回调。
- local新点击serial9/10：地图只在serial9命中，随后tactical=true；对应原生图 `round42-local-selected-no-map.png` 没有地图提示，`round42-local-new-map-click.png` 出现“移动只能沿单方向前进”。
- ENet选择serial19/20没有地图回调；新的serial21命中地图。当前部署区不在权威move目标声明中，因此不弹tactical，断言按真实候选而不是强求与local文案一样。

round41原脚本的关闭后重复输入本来就是新事件，并非同事件穿透。没有漏accept证据，不增accept补丁、不禁地图、不吞用户下一次合法操作。

## 最终执行、冻结、清理

实际命令：`python -B reports/refactoring/round42-modal-zoom/run_gui.py final4`（wrapper退出0）；`python -B reports/refactoring/round42-modal-zoom/verify_scope.py`退出0；`git diff --check -- scripts/game_scene/battle_board_v2.gd scripts/net/ui/network_choice_panel.gd`退出0。
三个实际窗口命令均为：

```text
E:/scratch/isolated-698ebbad59294fd3adf0a376c8e0af22/generated/Godot.exe --fixed-fps 60 --path E:/scratch/isolated-698ebbad59294fd3adf0a376c8e0af22/generated/project --scene res://tests/<suite>.tscn -- window
```

|suite|PID|RESULT|耗时|退出|
|---|---|---|---|---|
|choice_modal_zoom_lifecycle_test|25860|134 failures=[]|49.496s|0|
|round41_command_spell_window_test|37440|42 failures=[]|19.941s|0|
|local_spell_restore_test|23052|25 failures=[]|12.441s|0|

三套无headless，Vulkan1.4.351 / Forward Mobile / RTX5070Ti。每套预算180s，Windows Job只管理自身PID树；无超时kill，ActiveProcesses=0、日志句柄释放。probe/import也exit0。
实际主探针PID7552/真实子进程17916均物理 `E:/scratch/isolated-698ebbad59294fd3adf0a376c8e0af22/generated/appdata/FateDomination`，线程池20。probe子进程不等于独立房间worker业务。
冻结2075文件；`source_before == source_after_copy == source_after_execution == source_final`，source_drift=[]、frozen_drift=[]；最终验证当前源仍等于执行hash、全部图片/日志hash重新读回一致。所有尝试的自有generated均回收，最终generated_exists=false；未删生产或用户数据。
隔离副本仅保留既有受审查editor VCS两字段变换（不启动GitPlugin）；生产project.godot未改，不冒称未变换发行EXE验收。

最终manifest：`reports/refactoring/round42-modal-zoom/final4/manifest.json`，SHA256 `fb68f7e707d9836aab815a4aad6a66761deaa6bcb189757a89be21d79dfda478`。

|执行文件|SHA256|
|---|---|
|battle_board_v2.gd|93bbe403d3aee4bd59349d55d9dad7416a24ff6b444af390e2fbb606df16e888|
|network_choice_panel.gd（未改）|a48412ca6c0738bbf4bf4222a42dfaa3e557137124cca3d1d020a77720c0aa2a|
|choice_modal_zoom_lifecycle_test.gd|bf3a580c0300111289d63c44931cb4f96c6adb1cd8b6ca48d5747693b94fd9ae|
|choice_modal_zoom_lifecycle_test.tscn|dde7e8f71644f5acbe5b8afe105bd93d17828a279de31a6107b61dc7b3b4dcba|
|round41_command_spell_window_test.gd（未改）|29a640bc47e413456d6f6f62374e2442f222e9ebbd3c800b0d55d4c545c24667|
|local_spell_restore_test.gd（未改）|dbbf0be8c648980eec2bb5c900b7acc1f179ac8ec5efeb4d37051395e0c398a8|

## 原生画面与blocked项

使用 `load_image_native` 直接读本轮最终图片，未用vision_analyze或辅助模型。

- 最终local/ENet pending PNG与对应PrintWindow BMP：背景/卡图/法阵可见、正式选项及放弃完整，无令咒zoom遮挡。原42项两张pending亦重新原生查看，结论一致。
- 关闭恢复图显示令咒浮图正常重新出现；真实暗置两张图只显示攻击卡背，无私有说明。local截图在翻面自然结束后采集，卡位也是卡背。
- `local_spell_restored_open.png`：普通令咒完整、暗色角标、展开特殊卡与无可见滚动条；原25项覆盖尺寸/滚轮/真实特殊卡点击/取消/关闭。没有冒称旧专项历史hash可追溯，使用本轮重跑hash。
- 实际本轮HWND：新专项1312376、42项23202918、local25项23268454。PrintWindow客户区1920×1080，近捕获GetDpiForWindow=96、DPI awareness=1(system-aware)、ClientToScreen=[320,156]；未改变系统缩放。

**单列未验/blocked（不计PASS）：**
1. 同帧桌面客户区裁片、PrintWindow与viewport/DPI三方一致性未执行；只有同HWND近捕获元数据和原生客户区内容检查，不能推断其他缩放/跨显示器行为。
2. local25展开瞬间OS客户区没有stage同步，仅viewport展开图与早期window-start BMP；不把后者当展开OS验收。
3. OS硬件输入、多机、跨网、独立authority worker令咒业务及AI推进未覆盖；ENet为同进程权威与客机的真实回环RSA认证，业务transport-poll与原专项一致。
4. 手牌扇形底部越界仍是既有布局表现，本轮只使用可见交集真实输入，不宣称全界面零裁切或修改其布局。背景连续运动/亮度性能未验。
