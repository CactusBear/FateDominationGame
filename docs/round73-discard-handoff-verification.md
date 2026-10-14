# Round73 弃牌 GUI 独立复核 handoff（不重复运行）

## 决策与范围

按用户“前 owner 同当前生产 hash PASS 则只核验图片/输入 receipt 并 handoff”执行。已有 `docs/round73-discard-window.md` 与真实 FINAL 原件齐全，本轮 **未启动 Godot、未重跑窗口/headless、未测速、未出包、未操作用户 PID28100**。未修改生产、原267通过测试、新tests或runner；本轮仅新增本文。

原 FINAL 命令：`python -B newtests/run_round71_shared_discard.py --label round73-final --window`。

## 同版本与完整性

原件根目录：
`E:/scratch/round71-shared-discard-round73-final/isolated-cc4be315cb8b48d0bbaff7b600a2f77b/`

- `manifest.json` 实际 SHA256：`1842ad65c07875783bb8d05e0287fb176188ce5362cbed53a2a302cf70729605`，与前 owner 文档相符。
- 本轮 Python 对 manifest 的全部 **2116** 个 `source_hashes` 文件读取当前仓库字节重新 SHA256：**drift={}**，不是只比较 board/presenter。runner 未包含于该映射，已另读当前字节核对下表。
- source 映射指纹：`sha256(json.dumps(source_hashes, sort_keys=True, separators=(',', ':')).encode())` = `0860e005fcf1d7902c0673c0a4da6fb31602e00447df18f794c37ae511b75ac3`。这是映射指纹，不是 Git commit。
- 全部 **799** 个 manifest artifact 从 `evidence/<path>` 重新读取、比较 bytes/SHA256：**bad=[]**；其中PNG共28张（24张discard、4张既有modal）。

|源码|SHA256|
|---|---|
|`scripts/game_scene/battle_board_v2.gd`|`6a6cecf4f5eb4672f5af77f4d9ac28d62543a0260e3d786f0bcd7781db52bc5d`|
|`scripts/net/ui/v2_view_presenter.gd`|`dd409f9d35d6be0078fc83c6198dd1c1deed9c7f35e4a98be34812e39bf464b6`|
|`scripts/match/view_builder.gd`|`9a7ed25688ded565bce41b0a8b7473f8067553b55629fbb7d7ce88a276ec831e`|
|`scripts/match/view_mirror.gd`|`8007a3cc6e2e1ed0bb319ba3e1b3bd21fb825e7b9bc24f3f212a724c514eef20`|
|`assets/scenes/game_scene/battle_board_v2.tscn`|`39a681e1f00578e2a2d7278b241262a72a78afe99937d99553c6ebf615c0fb6d`|
|`newtests/round71_shared_discard_browsing_test.gd`|`6977fa0789866083340511000f3a175bbe69c0888f54c3300a06e5ca6245154f`|
|`newtests/run_round71_shared_discard.py`|`94e22e1cba519c1ee1f4ff6ff2ef4f76bf76b016ad38896e9a15b446ed3e6028`|

原引擎 `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`；原release DLL `92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd`（DLL归档source映射已核对；本轮不启动/替换引擎）。

## 实际输入与检查

完整读取 `evidence/round71_shared_discard_browsing_test-window.stdout.log` 和当前对应GDScript原件；再程序解析结果：221条CHECK全true，24条WINDOW_CLICK全hit=true且down=1/up=1，12次Close pressed=1。入口为真实正式 `Ops/Discard`、`Piles/SituationPile`，单路根Viewport push_input motion/down/up；窗口分支没有warp或pressed.emit打开/关闭旁路。原168的headless信号分支仍保留并明确不冒充GUI。

两端host observer=1 / guest observer=0各执行个人与公共局势：初始22/3 → 权威发布后重新打开3/2 → empty 0/0；顺序、source贴图、标题、empty一致。个人真实滚轮有效，个人隐藏升华技及host暗置局势真实右键无正面/说明泄露。每次关闭清理browser/zoom/desc，模态motion及关闭同步/下一帧保持当前战区，关闭后的firstnewmotion立即恢复导航。每轮浏览前后牌区/阶段/资源/日志等事实与host/guest请求序号相等，无规则命令副作用。

等待读真实 `_is_progress_blocked` 与 `_scroll_tween` 完成后正式refresh和布局帧；截图走frame_post_draw。没有固定sleep、取消banner或调整层级来取得截图。

原结果读回：原168 headless **168/0**；discard GUI **221/0**；既有modal GUI **59/0**；另既有card_browser 4/0、drawer_dismiss 1/0、privacy 137/0，全部exit0。本轮只读这些原结果，未新跑或拼接其它epoch。

## 本轮原生看图（不只count）

目录 `evidence/screenshots/`，实际调用原生图片加载查看以下12张：

- `round73-{host,guest}-{personal,situation}-full.png`（4张）
- `round73-host-{personal,situation}-reopen-browser.png`（2张）
- `round73-guest-{personal,situation}-reopen-full.png`（2张）
- `round73-{host,guest}-{personal,situation}-empty-full.png`（4张）

亲看：个人22标题、攻击/技能/令咒/事件卡面与两张“升华技”专属背面可辨；host公共第一张为蓝色局势背面，后两张正面；guest公共在正式恢复后为三个正面，符合该时source。重开个人3张（两张攻击与一张局势）、公共2张排列正确；两端empty均标题0、中心“这里还没有卡”、无残留牌槽。所看full图浏览器、卡牌、关闭按钮清楚，无阶段横幅覆盖；背景正常遮暗。裁片用于核验具体卡面，不取代full遮挡检查。

## Job0 与清理回执

本轮重新读manifest八个真实阶段（probe/import/四headless/两window）：均exit_code=0、active_owned_processes=0、log_handles_released=true。discard窗口原PID1412，原168 PID38048。所有归档`.log`重新扫描 SCRIPT ERROR / 行首ERROR / 行首WARNING：无命中。manifest的source_drift/freeze_drift均空，artifact_readback=true，cleanup=generated_removed；实际generated目录不存在。Job0是原次执行的归档回执，不声称本轮新建Job。

## 交付边界

- **正式本地组合根没有个人/局势这两个浏览点击入口**；原真实点击验证“不打开”通过。不可宣称本地打开GUI通过，不为验收新增生产能力。
- 输入为Viewport实际GUI路由，不是OS硬件鼠标；网络为真实RSA/ENet同进程回环，不是多机/跨网或IPC worker业务整链。
- 本轮没有需要修复的首cause；不消耗额外定位迭代。保留前owner两次fixture失败和FINAL证据，不动原分组/modal/cardback测试。
- 可交实现完成后测试包整合者复用此明确hash证据；若后续owner改变生产字节，必须标明不同freeze，不能把本次GUI PASS自动升级为新版本整链PASS。
