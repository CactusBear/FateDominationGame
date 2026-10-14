# Round74 公共战斗结果文字迁移

## 已交付

生产只改 `scripts/game_scene/battle_io/shared_view_sections.gd` 与 `scripts/net/ui/v2_view_presenter.gd`：增加一个 `public_battle_result_lines(summary: Dictionary, players: Array)`，`open_log()` 直接传同次授权 snapshot.battle_result/players。删除 presenter 旧函数，不保留转调兼容层。名字只取投影中的首个匹配 id 的 master.name / player_name，未知玩家为空串，不查询 Session/GameDataManager/规则对象，不改变输入。

board 原本地 `_battle_result_line/lines` **未改**：与网络不等价，不能强并而改变文案。网络播报里原 board 使用路径也未改。本次 scope 没有日志 formatter、播报确认/动画、隐私 builder/mirror/Session 写入。BtnOutOfGame 网络 return 前接线和之前日志改动原样保留；本地浏览器行动横幅欠项未修。

## 固定 golden 正负对照

以下为手写 expected，由迁移前真实 presenter.open_log 和 board 原函数执行确认；GREEN 对照同份 RED 输出，未重新 capture 或更新预期。

|输入|本地原输出|网络原输出＝迁移后|
|---|---|---|
|needs_win=false|【无需】无需战斗，在场者共同获得战果|同左|
|无赢家，highest_power=7.5|【无胜】无人可获胜，战区战果保留|【无胜】无人可获胜，战区战果保留，最高威力 7.5|
|winners=[2,1,2]，12.0|【整数】胜者：御主乙、御主甲、御主乙，最高威力 12|同左，重复/顺序保留|
|12.75|【正小数】胜者：御主甲，最高威力 12|【正小数】胜者：御主甲，最高威力 12.75|
|-2.75|【负小数】胜者：御主甲，最高威力 -2|【负小数】胜者：御主甲，最高威力 -2.75|
|未知 id，缺最高威力|【未知】胜者：，最高威力 0|同左|
|无 master 回退、master.name为空、重复玩家 id 首个匹配|【名字回退】胜者：玩家丙、、御主甲，最高威力 0|同左|
|detail={}|【缺字段】无人可获胜，战区战果保留|【缺字段】无人可获胜，战区战果保留，最高威力 0|

额外覆盖空 summary、空授权 players 仍保留未知胜者空名和0.25、输入不变、本地标题与字典顺序。真实 `open_log()` 的 RichTextLabel 文本/BBCode禁用/窗口visible与迁移前逐字相同；来源读取从每个 winner 重读 session 改为仅一次显式快照读取。

## 实际执行与证据

专项：`newtests/round74_public_battle_text_test.gd` / `.tscn`；runner：`newtests/run_round74_public_battle_text.py`。使用项目原 Godot4.7.2/原DLL，E盘独占冻结及 APPDATA/LOCALAPPDATA/TEMP/TMP/TMPDIR，每阶段180秒watchdog，不编译DLL，不跑full/测速/旧UI专项/GUI。

- RED：`python newtests/run_round74_public_battle_text.py --label red-fixed` → exit1，15 checks，仅3项预期迁移缺失：单快照读取、共享函数缺失、旧presenter函数未退休。原本地/网络golden均通过。
- GREEN最终：`python newtests/run_round74_public_battle_text.py --label green-final --compare E:/scratch/round74-public-battle-text-red-fixed/isolated-6759d6e9d56b4c6c8a85664ea8a3912f/manifest.json` → exit0。
- 真实Godot：`<GREEN根>/generated/Godot.exe --headless --fixed-fps 60 --path <GREEN根>/generated/project --scene res://newtests/round74_public_battle_text_test.tscn` → exit0，RESULT checks=19 failures=[]。
- GREEN根：`E:/scratch/round74-public-battle-text-green-final/isolated-9b9d249cd6a04fb08802724c1cddde79/`，日志 `evidence/round74_public_battle_text_test.stdout.log` 含完整双端golden及真实日志节点输出。
- manifest：`1502842ed50bedf459be98113a7258817f418d9693bb45c6df96bb67eb13bf4b`。
- comparison.matched=true，source_drift={}，freeze_drift={}，ERROR/WARNING门通过；owned generated清理，全部产物读回hash确认。
- 与RED冻结做逐文件diff：board完全无差异；presenter仅caller一行和旧函数删除；SharedViewSections只新增目标函数。`git diff --check`无输出，三个新增test/runner不被ignore。

## SHA256（最终live与GREEN冻结一致）

|文件|SHA256|
|---|---|
|scripts/game_scene/battle_board_v2.gd（本轮未改）|5c7258173a851489504fb30ced994c1e821f062a1c1ca022dbede32a1fc40026|
|scripts/net/ui/v2_view_presenter.gd|daa158678c2d7542c65ba4b4390955193186127986e59203fa05c4b735a6f2ca|
|scripts/game_scene/battle_io/shared_view_sections.gd|da6882e21ad24ecd43bc9d52dd8821dd462e281b6634c2fd425e0526ab0295c8|
|newtests/round74_public_battle_text_test.gd|6bcde574a3a5d12e19426c392b34e20e9576716d50ca3e60ad67627374bbb748|
|newtests/round74_public_battle_text_test.tscn|4a325e1fe465f441df507f9bc37c74fcf94b016fdc23f042d5c1326c5847b13b|
|newtests/run_round74_public_battle_text.py|5c1752ab305dab1fc85323f35b8f294d9f6bbd3356304ff65e935832912c2fc2|

## 失败证据及边界

首次 RED（`...-red/isolated-ac87455eb17240369bae0e036ac39e2b`）CHECK输出用了PASS/FAIL，被既有analyzer判invalid_check；改为true/false后重新运行业务RED，未改golden。首次GREEN（`...-green/isolated-5e0fa7a8daea437abb2d7ea54d189fcf`）真实专项exit0、19项通过、文本匹配，但并行owner修改只读game_progress.gd导致live source_drift门失败，未当成功；再冻结完整专项得到最终无漂移GREEN。

未声称新GUI/ENet/私有worker验收，未触碰用户进程。此任务只证明公共网络文字函数纯输入、真实caller消费与文案等价；本地差异有证据且原样保留。
