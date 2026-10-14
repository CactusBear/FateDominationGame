# Round41 令咒真实窗口验收

## 结论与边界

- **业务 GREEN：最终冻结下新窗口专项 42 项、local_spell_restore 25 项，共 67 项；两套非 headless，均自然退出 0、failures=[]、无 SCRIPT/SHADER/engine ERROR。**
- **视觉不是全绿**：原生画面确认单机令咒悬浮放大图覆盖 pending 弹窗左下部分；关闭弹窗后在原选项坐标重复点击会触发地图移动提示。令咒未重复支付，但不能据此宣称重复点击没有其他 UI 响应。只报告，不改生产。
- 本轮认证 ENet 是**同进程房主权威 + 客机 session 的真实回环 ENet + 正式 RSA challenge/proof**。认证后业务阶段仅轮询真实 transport，与现有令咒专项一致，未覆盖权威自动 step/AI。
- **独立 worker** 是另外一个 OS 进程，经主管和私有 IPC 管理，不等于上述同进程权威。本轮实际启动了 main/child 路径探针，证明子进程物理 E 盘 user:// 与 exit0；**未执行独立房间 worker 的令咒业务、多机、跨网或 OS 硬件鼠标验收**。

## 新增范围与正式调用链

仅新增 `tests/round41_command_spell_window_test.gd/.tscn` 与本 GUI 报告/证据运行器。production、原窗口 tests、generic runner 均只读。

复用 `battle_board_v2.tscn`、既有 local/network battle source 和 command adapters、`net_window_identity_fixture.gd`。准备 → 前哨 → 正式部署 → 本人行动均经共同命令入口，不创建替代 UI，不 emit pressed，不直接调用效果 exec 发动。

鼠标移动/左键按下抬起通过 `Viewport.push_input` GUI 分发；日志记录 `gui_get_hovered_control` 与真实 EffectButton、真实选项 Button 路径一致。这是实际窗口 GUI 命中，不是 OS 硬件输入。

最终日志直接核对引擎 `EffectManager.get_pending_active_effect()`、权威 `match_authority.pending_for(guest.peer_id())` 与窗口 pending 一致，并读取实际权威规则资源与窗口资源一致。

|场景|选择|魔力前→后|令咒前→后|重复输入|
|---|---|---|---|---|
|单机|行动阶段：获得4魔力|4→8|3→2|发动/选择/关闭后原位置点击不重付|
|认证ENet|同一正式选项|5→9|3→2|poll前重复GUI发动只发1条activate；整链只有activate、option两条命令，关闭后不重发不重付|

最终原始日志：`reports/refactoring/round41-spell-window/final/evidence/round41_command_spell_window_test.stdout.log`；实际 `RESULT {"checks":42,"failures":[]}`。local 专项日志在同目录，实际 `RESULT checks=25 failures=[]`。

## 执行命令、版本与退出

入口：`python -B reports/refactoring/round41-spell-window/run_gui.py`。

最终两条真实窗口命令（不是计划命令）：

```text
E:/scratch/isolated-ed43869947ff477995a0ddb90ed55cc5/generated/Godot.exe --fixed-fps 60 --path E:/scratch/isolated-ed43869947ff477995a0ddb90ed55cc5/generated/project --scene res://tests/round41_command_spell_window_test.tscn -- window
E:/scratch/isolated-ed43869947ff477995a0ddb90ed55cc5/generated/Godot.exe --fixed-fps 60 --path E:/scratch/isolated-ed43869947ff477995a0ddb90ed55cc5/generated/project --scene res://tests/local_spell_restore_test.tscn -- window
```

渲染器：Vulkan 1.4.351 / Forward Mobile / NVIDIA GeForce RTX 5070 Ti。两套 PID 23836 / 32956，耗时 20.523s / 13.283s；预算每进程 180s。两套自然 `get_tree().quit(0)`，Windows Job 最终 ActiveProcesses=0、日志句柄释放、无超时/回收终止；没有 taskkill。

物理 E 盘探针 main PID14872、真实 child PID37656，实际路径均为 `E:/scratch/isolated-ed43869947ff477995a0ddb90ed55cc5/generated/appdata/FateDomination`；真实池20，child exit0。业务窗口也输出该真实 user:// 根；local_restore 没有自己的路径打印，继承同一隔离环境/项目配置。

冻结 2073 个依赖文件。`source_before == source_after_copy == source_after_execution == source_final`；source_drift=[]、frozen_drift=[]。本轮所有尝试的 shared UI/scripts/assets hash 一致；最终两套共享同一个物理项目冻结，而不是拼接过去日志。

隔离副本仅复用已验证的 `[editor]` VCS 两字段变换（关闭开发 GitPlugin autoload）；生产 project.godot 不动，规则/UI/数据源均逐文件原始 hash 保留；原配置与执行配置 hash 分列在 manifest。不是未变换的发行 EXE 验收。

最终 manifest：`reports/refactoring/round41-spell-window/final/manifest.json`；SHA256 `a13d5e3a8a8045f273676ea1ca2779180debb768865685b434f92329593d4500`。

### 当前执行源码 SHA256（前后相同）

|文件|SHA256|
|---|---|
|assets/scenes/game_scene/battle_board_v2.tscn|39a681e1f00578e2a2d7278b241262a72a78afe99937d99553c6ebf615c0fb6d|
|scripts/game_scene/battle_board_v2.gd|50171086aee3d1a85c2659f4410b2ab96efca6bc958a1fe59f2147b1780d74e3|
|scripts/game_scene/tactical_board_ui.gd|9c9d61642bf619c4012fced2b0244eebe89cf642be700f4418be82a0e4522ed9|
|scripts/system/global/effect_manager.gd|56eff4380b1a63a35dc802a913565159a2c295c4dfae17b931b0c93ad70fecd8|
|tests/local_spell_restore_test.gd|dbbf0be8c648980eec2bb5c900b7acc1f179ac8ec5efeb4d37051395e0c398a8|
|tests/local_spell_restore_test.tscn|853190ec5fe0504bbae61e3973109e4c2428ea3394a8250e368d4dfe087a654a|
|tests/round41_command_spell_window_test.gd|29a640bc47e413456d6f6f62374e2442f222e9ebbd3c800b0d55d4c545c24667|
|tests/round41_command_spell_window_test.tscn|238bc381f5968947b824abcd2a6f9c8bfed1086187f67b1c9d1fee708cb439dd|

全部 source/adapters/数据/图片 hash 及前后记录见 manifest；截图/日志 evidence_hashes 全部重新读回一致。

## 原生图像检查

最终 `final/evidence/` 保留未经修改的 viewport PNG 与 PrintWindow 客户区 BMP；使用 `load_image_native` 直接读图，未用 vision_analyze 或辅助视觉模型。

- **背景/资源**：最终单机/ENet button、pending、paid 画面中教堂背景与正式卡图、资源魔法阵可见，无黑屏、资源缺失占位。魔力4→8、5→9与令咒角标3→2在画面中可见，和权威日志一致。没有连续背景运动或亮度指标验收，不能称已证背景静止。
- **隐私**：未见身份密钥、指纹、票据等文案。local_restore 同轮25项确认观察者不收到对手私有持有令咒，画面只展示自身展开卡条与对手概览；新令咒执行局是单规则席位，不冒称覆盖多人敌方私密卡点击/放大。
- **卡条/裁切**：`local_spell_restored_open.png` 原生检查普通完整卡、暗色角标、展开的一张特殊卡及无可见滚动条；25项覆盖90×126、层级、动画中间宽度、展开186、实际滚轮、真实特殊卡点击、取消不扣费及关闭。正常令咒卡、角标、EffectButton 与正式选项位于 viewport 内。手牌扇形有底部越出窗口表现；未把它当成本轮“全界面零裁切”通过。
- **OS 客户区**：本轮实际按业务 PID 查到 HWND 并取得1920×1080客户区 BMP；原生查看最终 ENet pending 客户区，与相应 viewport 内容一致、非黑屏。故令咒弹窗客户区不是未验。没有同帧桌面客户区裁片/DPI三方比较，也没有捕获 local_restore 展开瞬间的 OS 客户区（仅有其早期 window-start BMP）；这些项明确未验。
- **视觉待修**：最终 `round41-local-pending.png` 显示原悬浮放大图仍处于弹窗前方，遮住左下部分；`round41-local-paid.png` 显示关闭后的原选项坐标点到地图并出现移动提示。业务费用断言通过不消除这些可见问题。生产只读，未修。

## 历史 GUI 缺执行 hash 与首红

Round40 引用的 round37 历史 GUI 日志没有执行时源码绑定，不能反向补造历史 hash。该历史记录仍不计本次 PASS。本轮用当前 local_restore 原脚本在同一最终冻结实际重新执行25项、exit0、无 engine errors，保存新的执行 hash 与新的展开图片，补的是**当前版本证据缺口**而非伪造 round40 历史执行版本。

首次尝试证据在 `reports/refactoring/round41-spell-window/manifest.json` / `evidence/`：新专项23项、exit1，认证完成后前哨等待失败；local_restore25项exit0。首次新夹具使用完整 session.poll，引入权威自动step，与既有专项 transport-poll 前置不同。仅改自有新夹具：认证使用session.poll、业务使用transport.poll，补阶段状态日志；随后42项直接权威断言最终通过。首红不计PASS，也未指控生产。

`attempt2/` 的38项记录和25项仍保留，但最终结论只使用 `final/` 的42+25，不累加重复运行。

## 清理与剩余

三次尝试生成的 E 盘引擎、项目/素材数据副本、用户数据与缓存均按自有 receipt/Job 退出证明及时删除，generated_removed；最终及attempt2根回查 generated_exists=false。没有下载网络素材、没有删除生产数据或用户原数据。原始图片、日志和hash留在报告证据目录。

业务 GREEN 不代表全视觉GREEN、独立worker业务GREEN或最终发行GREEN。剩余是上述可见 UI 问题、未验DPI/展开OS画面、多机跨网与独立worker令咒链；本代理不修改生产。
