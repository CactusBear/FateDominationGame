# Round74 除外区共享入口交付

## 结果及范围

仅修改 `scripts/game_scene/battle_board_v2.gd` 与 `scripts/net/ui/v2_view_presenter.gd`。正式 BtnOutOfGame 接线移至 `_ready()` 网络提前返回之前；board 共享回调读取当前 `_source.read_view().players` 精确匹配 `_selected_opponent_id`，本地先 invalidate。退休 presenter.open_out_of_game 及绑定/解绑分支；删除确认无 caller 的 `_refresh_drawer_out_of_game`。保留仍用于 zone-hand 排除的 `_out_of_game_cards`。日志 actor、scoreboard 前 owner 改动原样保留；不写 session/gateway/manager/builder/mirror/data。

原 builder 74–80 行明确声明攻击/技能/其他三区、排除令咒，card_view 343–369 行按 own/公开身份/暗置/未觉醒技能过滤。共享 renderer 不补查规则：visible=false 禁止 zoom；本人 concealed=true 只用已声明 back_image，可按已有 zoom_kind 放大自身牌背、无标题/说明。缺声明不猜资源。

## 实际执行

最终命令：`python -B newtests/run_round74_out_of_game.py --label targeted --window`，exit 0。

证据根：`E:/scratch/round74-out-of-game-targeted/isolated-6abdb4949a1344738b8ad5600e69836b/`。

manifest SHA256：`93dfe6474cab919ebe609fad6a689f3720cff5b18c1171896c42723d3d9a8b9e`。

实际 Godot 命令（P=上述根/generated/project，G=上述根/generated/Godot.exe）：
- `G --headless --fixed-fps 60 --path P --scene res://newtests/round74_shared_out_of_game_test.tscn` → exit0，RESULT checks=93 failures=[]。
- `G --fixed-fps 60 --path P --scene res://newtests/round74_shared_out_of_game_test.tscn -- window` → exit0，RESULT checks=78 failures=[]。

probe/import/headless/window 四阶段均 Job active_owned_processes=0、log_handles_released=true，generated 已删除。所有归档日志 ERROR/WARNING 门通过。source_drift={}、freeze_drift={}；交付时重新核对 manifest 全部 source_hashes 与 live，live_drift={}。没有跑原168/221/59或full，没有触碰用户PID28100。

headless：本人/对手过滤、未觉醒、暗置自身背、无背字段、empty/缺牌字段、缺玩家身份/invalidselected、同seq同ID新字段、本地失效缓存、跨source重绑、close source、不创建玩家、无规则命令/actions/pending/preview 查询。SourceSession 是投递逻辑夹具，不冒充网络传输。

窗口：真实本地组合根已有抽屉入口；网络经RSA认证及ENet回环过滤source。各从正式 Rivals 玩家入口真实 mouse 打开抽屉，再点 BtnOutOfGame → Close → BtnOutOfGame重开 → Close；12条 WINDOW_CLICK 全hit=true、down=1/up=1，8条Button均pressed=1。单路 root Viewport.push_input motion/down/up，没有 pressed.emit 代替窗口输入。两端真实右键隐藏卡无正面/说明；浏览前后规则事实与网络request序号不变。

## 原生截图亲验

原件目录：`<证据根>/evidence/screenshots/`：
- `round74-local-opponent-open.png`
- `round74-local-opponent-reopen.png`
- `round74-network-opponent-open.png`
- `round74-network-opponent-reopen.png`

四张均用 load_image_native 原生亲看。本地标题2：公开攻击正面、暗置攻击自身Attack背；网络标题3：公开攻击、Attack背、未觉醒技能自身“升华技”背。关闭按钮和所有牌图清楚可见，没有暗置正面/说明。**本地原有行动横幅仍叠在浏览器中央空白区，不遮卡、标题、关闭按钮；本轮未修改其层级，不宣称横幅遮挡回归已解决。** 网络图无此横幅。

## 冻结sourcehash

|文件|SHA256|
|---|---|
|scripts/game_scene/battle_board_v2.gd|5c7258173a851489504fb30ced994c1e821f062a1c1ca022dbede32a1fc40026|
|scripts/net/ui/v2_view_presenter.gd|609dbae425d4bddff14138af352fb1c196e6afcaf0ef5a5e045c94dfb6d4843e|
|scripts/match/view_builder.gd|9a7ed25688ded565bce41b0a8b7473f8067553b55629fbb7d7ce88a276ec831e|
|scripts/match/view_mirror.gd|8007a3cc6e2e1ed0bb319ba3e1b3bd21fb825e7b9bc24f3f212a724c514eef20|
|newtests/round74_shared_out_of_game_test.gd|b34c955f005e88f3aca52b1b4123b699a680a7f3e8c603af764521aa327d6208|

新增：上述test.gd、同名.tscn、run_round74_out_of_game.py、本handoff。测试继承旧夹具只复用工具方法，override run/run_window，因此不执行旧168/221检查组。

## 首次失败与边界

保留 `E:/scratch/round74-out-of-game-{final,fixed-fixture,retry-freeze}/` 首次失败证据：seed() 名称与GDScript内建冲突引发解析及180秒watchdog；克隆会清除concealed，改为clone后设置；本人暗置可合法放大牌背，修正错误的“一律disabled”夹具预期。均未为通过测试放宽生产隐私。另 post-clone 冻结在启动引擎前失败，finally复制未完成文件遮蔽原异常；runner改为仅归档已冻结文件，下一完整freeze成功。该UUID无Godot.exe/进程/log，确认后仅删除其自有partial generated（1320文件），保留manifest/evidence。

剩余：public_battle_result_lines/open_log 未动；网络身份/连接/guard及其它展示分支保留，不扩五类UI。本轮不导包，交main复核整合。窗口输入为真实Godot GUI路由，不是OS硬件鼠标；网络为同进程RSA/ENet回环，不是多机跨网/worker IPC整链。其它owner后续改变source字节时不得把此freeze的PASS直接升级为新包整链PASS。
