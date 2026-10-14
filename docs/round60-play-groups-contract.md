# Round60：出牌组快照合同与夹具分区

## 结论与不可放行项

- 同冻结完整专项：headless **56/0、exit0**，真实非 headless **58/0、exit0**；stdout/stderr 及归档 Godot logger 无 SCRIPT/SHADER/ERROR。
- 已证明：当前公开刷新正常更新 source；显式普通牌经真实公开 `RegularPlay.add` 第一张及补齐第二张成功进入分组。没有发现需要生产 patch 的快照缓存或 group projection bug。
- 已证明旧夹具的输入前提不完整：`hand_cards.pop_back()` 的任意牌不一定属于当前出牌组；显式残留牌在 source 的 played/residue 两区都有合法 ID，但分组消费者按 residue ID 排除它。
- **未证明 Round58 历史红的唯一首因**：旧原件没有记录当时随机卡 ID、效果或残留字段。受控 residue RED 不能冒充历史相同输入。
- **完整可见布局未验收**：原生看过 E 上两张窗口 PNG；深山町图显示四个组头像但只显出部分牌，工房图没有完整显示四组牌。未见异常色块，不能据此宣称尺寸/遮挡全部视觉通过。测试开头 `board.set_process(false)`，生产飞牌、头像等逐帧更新在 `_process` 中；是否它与入场时间共同造成该画面，尚未运行验证。达到三版有效尝试上限，不继续改夹具/补跑，不调私有动画或透明度伪造截图。

## 首层只读证据

读取当前与 Round58 冻结 `battle_board_v2.gd:612-638`：`refresh_all_ui()` 在本地分支首先 `_source.invalidate()`，再绑定整屏。不是测试缺失公开刷新。

`local_battle_source.gd:20-39`：read_view 在无效周期才 build，返回副本；invalidate 不发 changed，refresh 才开启通知周期。board 使用公开刷新自主 invalidate 是原生产合同。本轮测试没有直接 source.invalidate/refresh 强刷，也没有 private fake view/direct `_bind_groups`。

`view_builder.gd:82-95,105-116`：played_cards 投影全部已出牌；residue_cards 仅取 BaseHandCard、未关闭、未暗置、存在显式 `_is_residue` 的牌；area.locations.players 来自真实 location._players。

`battle_board_v2.gd:2059-2114,5729-5763`：全部卷轴按 source areas 绑定；每区 occupants 来自 location.players；从 source players.played_cards 排除同 player.residue_cards ID 后建组，不按名称、大小或图片猜残留。

生产请求刷新：本地 driver.state_changed 接 refresh_all_ui（board:339）；命令结算 `_settle_end_command` 在 :5563-5564 调 refresh_all_ui。公开 `RegularPlay.add/submit_group` 的规则入场本身不是 UI 刷新器；布局专项明确调用原公开 board.refresh_all_ui，不伪造事件。

### 实际观测表

|版本|输入/合法 ID|effects.residue|真实/源占位|source played/residue|组数|结果|
|---|---|---|---|---|---:|---|
|首次保留随机夹具|83|effects=[]|均为 0..6|played 含83、residue空|1|43/0 exit0，未复现旧红|
|受控 RED|85|显式true|均为 0..6|两区均含85|0|2 checks、1 failure、exit1；无脚本错/timeout|
|最终普通牌公开规则链|稳定正 ID，详见 FIRST_EVIDENCE|effects=[]|两层一致|played 含该ID、residue空|1→3→4|56/0 headless，58/0 window|

受控 RED 只替换第一张输入并保留旧“单牌必有组”的断言，真实证明分歧在**规则分区→消费者过滤**，不是 direct mutation→缓存漏刷。最终 fixture 独立断言残留分区正常，而非删除残留 coverage。

## 测试修改与解耦

修改前中文说明；全部代码编辑经 V4A patch。唯一游戏测试写入 `tests/battle_play_groups_test.gd`：

- 复用现有规则专项使用的 `BaseAttack.new` 原语，显式无效果、0费、1威力，并声明卡面、卡背与 zoom_kind。名称只用于诊断，不挑卡、不决定合法性。
- 两张普通牌经公开 `RegularPlay.add`，断言真实 accepted 与 completed；不改费用、最低/最高牌数或场面禁令。
- 其它玩家与六牌组明确是任意布局状态夹具，直接布置 played_cards，不声称六牌是普通出牌合法组；统一走原公开 board 刷新。
- 保留全部分组、头像、装饰条、暗置卡背、唯一槽位、尺寸、统一宽度、组间不交叠、边界覆盖。两张真实出牌确保原 engine-order 断言实际执行，不再单牌跳过。
- 补 source seq 新周期、同 ID group/slot 节点复用。零组、错误行数、暗置组/槽缺失立即 finish fail，避免旧 get_child/nil 级联。
- 旧 `scroll` 指向原区域，其清空检查符合“搬走后旧区清空”合同；保留该检查，并补目标真实卷轴四组到达。
- 截图在四组状态及目标区各保存一次；保存成功只作文件断言，视觉不自动放行。

没有修改 board/presenter/source/operations 或其它 actor 的测试；没有替换原引擎和正式 DLL。

## 真实执行与原件

从仓库根执行，所有 scene 原 180 秒，fixed-fps=60，main/worker 的 user:// 物理 E 探针通过，只处置自己 Job/PID：

```text
python -B tools/tests/round60_play_groups_contract.py --label red-first
python -B tools/tests/round60_play_groups_contract.py --label red-residue-control
python -B tools/tests/round60_play_groups_contract.py --label final --window
python -B tools/tests/round60_play_groups_contract.py --recover-first
```

三版，不再运行第四版。每版的 frozen-inputs 保存实际测试与生产 GDScript/scene 字节，不覆盖旧 RED。

- 首次：`E:/scratch/round60-play-groups-red-first-dd2832071f644e348e30532a16138752/`。场景43绿，执行器归档后因旧清理器要求 isolated-token namespace/manifest receipt 而 exit1。没有据此重跑业务；仅 finalize 一次。`recovery.json` 记录当前 own executable 活动为空、SHA读回=true、generated_removed。历史逐 Job accounting 未在异常前序列化，明确保持缺口，不补造记录。
- 受控 RED：`E:/scratch/round60-play-groups-red-residue-control/isolated-ec574506b25b41aba6c5a79905280dcf/manifest.json`，SHA `badcfd331839ddf02345ca71e22dccbf7db054f91c0f7506a45e36381513c4d4`。scene exit1，唯一原业务失败；各阶段 active_owned_processes=0/log_handles_released=true；source/freeze drift空；artifact_readback=true；generated_removed。
- 最终：`E:/scratch/round60-play-groups-final/isolated-712950fb4ee8428f99c67381c531b90c/manifest.json`，SHA `74f08007985f83c6ee0673bfd0294453c071259fd1ca2cf8faad3ba9181f2d01`。headless PID29956、window PID36200，分别7.312/10.333秒；同冻结56/58全绿。四条 probe/import/headless/window 记录均 Job0、log handles released；source_drift={}、freeze_drift={}、artifact_readback=true、generated_removed。

最终 engine SHA `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`；正式 signal release DLL仍 `92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd`；最终 test SHA `5ba88f8f4b24186149300e5c8d38102cd28c3d16bf689640d48943c61e718a03`。

截图在最终根 `evidence/`：

- `battle_play_groups.png`，SHA `56c4cc5418b934a3218d74380ceb99aa3ccb656cd565796c21c3b35be63ae89a`。
- `battle_play_groups_destination.png`，SHA `350987f5b5955d7f1f08dd8c6a9ff3055df6b7505c5c1482b4dfcc7c1819e2dd`。

Round58 旧原件仍在 `E:/scratch/isolated-1105873e41cd4f6a94a999e65ac6af50/evidence/complete-battle_play_groups_test.stdout.log/.stderr.log`：stdout SHA `6dee1fdaf8cacef417d782105d37d99954a379af9cd0c4332d343c5431b2c6c0`，stderr SHA `d9cfc827ab09314d07ead87f507b223ff3eb5ef173bb2d719006bac06804346b`。旧 first false/get_child越界/nil、exit125 均不被新绿冲销。没有触碰旧 PID28100、用户进程、原正式存档或旧红目录。

## 交付

- 修改：`tests/battle_play_groups_test.gd`。
- 新建：`tools/tests/round60_play_groups_contract.py`、本文。
- 本机当前 profile 的 `godot-group-preview-projection` skill 增补 snapshot/residue 首证据、夹具身份保护和截图不自动验收教训。
- `git diff --check -- tests/battle_play_groups_test.gd` exit0。
- main 无生产 patch 建议：合法普通牌投影链真实通过，当前没有生产 bug 证据。仍需处理视觉夹具 process/入场生命周期验证，并保留历史随机输入缺证这一不可结案项。
