# Round75 行动横幅/卡浏览器层级专项

## 已修改并验证

生产唯一修改 `scripts/game_scene/battle_board_v2.gd` 104–106行：`ROUND_LIFTED_Z 100→80`、`BANNER_Z 120→85`，以及对应层级注释。自本轮开始前源码复原hash为 `5c7258173a851489504fb30ced994c1e821f062a1c1ca022dbede32a1fc40026`。局部生产diff：`newtests/round75_banner_browser_layer.production.diff`。没有覆盖writer的其它改动，没有写presenter/正式场景。

实际因果：Banner和CardBrowser在同一主画布，运行时 `z_as_relative=true`、`top_level=false`、无CanvasLayer祖先；本地ready将Banner设置120、move到最后，CardBrowser100；raise_modal只move_child，无法越过高z。现共享 `_native_modal_visible` 的选择/暂停悬浮guard刻意不含只读浏览器，本轮保持名单和生命周期原样。现在顺位抬升80 < 行动/阶段提示85 < 浏览器100 < 日志110 < 播报120。网络ready提前返回，Banner维持原场景z0；网络阶段提示也使用85，没有增加show/hide逻辑。

不增加状态、不隐藏通知、不修改规则/冻结、不改播报确认；drawer/buttons/卡背guard/hover保持原样。浏览器关闭仅揭示其下的现有有效提示，过期不复活，不需要actor/phase恢复分支或强refresh。

## 冻结真实执行

命令：`python -B newtests/run_round75_banner_layer.py --label green --window`，exit0。

证据根：`E:/scratch/round75-banner-layer-green/isolated-3c728ddd530e4aed907f0e63e3d56515/`。

实际引擎命令（G=证据根/generated/Godot.exe，P=证据根/generated/project）：
- `G --headless --fixed-fps 60 --path P --scene res://newtests/round75_banner_browser_layer_test.tscn`：exit0，RESULT checks=7 failures=[]。
- `G --fixed-fps 60 --path P --scene res://newtests/round75_banner_browser_layer_test.tscn -- window`：exit0，RESULT checks=95 failures=[]。

只跑新的层级专项，继承旧夹具仅复用创建、认证、GUI输入、清理方法，覆盖run及gui_removed，不执行原93/78、168/221/59；无全量、无测速。看门狗沿用180s，不把其当性能验收门槛。

本地单个真实窗口用公开 `GameProgress.can_end_current_player_action/end_current_player_action`产生当前横幅及浏览期间actor/phase更新；生产process一直运行，不直接写actor/phase、不直接show banner、不暂停Tween、不强refresh。正式玩家入口→抽屉BtnOutOfGame→Close；稳定打开/关闭、浏览期间actor变化、phase变化、提示自然过期都通过。actor从间桐慎二变间桐樱；阶段变前哨后当前actor为远坂凛。关闭不回到旧文案。

网络：旧夹具内存RSA认证+独占UDP ENet回环，正式source/原抽屉入口，单次打开→卡背真实右键→关闭；序号和规则事实未变。没有冒充独立worker、多机/跨网验收。

日志 `evidence/round75_banner_browser_layer_test-window.stdout.log` 有12条 WINDOW_CLICK，程序聚合全部hit=true、down=1/up=1；2个玩家入口、10个按钮均对应真实GUI路由，按钮pressed=1。输入为单路root Viewport.push_input motion/down/up，无pressed.emit、无warp双路，不是OS硬件鼠标。

probe/import/headless/window四阶段exit0、active_owned_processes=0、log_handles_released=true；generated_removed。source_drift={}，freeze_drift={}，clean_error_warning_gate=true，artifact_readback=true。没有触碰用户PID28100。

manifest SHA256：`ea3355e38488bb88d8c0a2cc43ef8b5283da306b6cf7b5bc91044c7b30fc40a7`。

## 原生截图亲验

以下9张均已用load_image_native原生亲看（未使用vision_analyze），目录为证据根/evidence/screenshots：
- round75-local-before.png：间桐慎二行动横幅清楚可见。
- round75-local-stable-open.png：浏览面板完整压住横幅，标题/牌/关闭按钮无覆盖。
- round75-local-stable-close.png：关闭后同一有效横幅正常揭示。
- round75-local-actor-change-open.png / round75-local-actor-change-close.png：浏览时仍不覆盖，关闭显示新actor间桐樱。
- round75-local-phase-change-open.png / round75-local-phase-change-close.png：阶段提示也不压浏览器；关闭已处前哨阶段，提示当前远坂凛。
- round75-local-expired-close.png：自然过期后关闭无横幅复活。
- round75-network-opponent-open.png：3张声明牌，公开攻击、Attack背、升华技背；无横幅覆盖/私牌正面/说明泄露。

## 交付SHA256与范围

|文件|SHA256|
|---|---|
|scripts/game_scene/battle_board_v2.gd|c8633ad506338f33139618e402cdb03bbe1305853bef7e94b2785d3a8e439298|
|assets/scenes/game_scene/battle_board_v2.tscn（未写）|39a681e1f00578e2a2d7278b241262a72a78afe99937d99553c6ebf615c0fb6d|
|scripts/net/ui/v2_view_presenter.gd（未写）|daa158678c2d7542c65ba4b4390955193186127986e59203fa05c4b735a6f2ca|

以上live字节与本次manifest freeze一致；正式tscn `#`注释行计数0。`git diff --check -- scripts/game_scene/battle_board_v2.gd assets/scenes/game_scene/battle_board_v2.tscn` exit0。其它已有工作树diff不属于本轮。

新增：round75_banner_browser_layer_test.gd/.tscn、run_round75_banner_layer.py、局部production.diff、本handoff。无首次失败；未执行runner可选red路径（原观察和层级因果已有证据）。本轮不导包，交主代理接入后续真人包；本证据不得替代改字节后新包整链验收。
