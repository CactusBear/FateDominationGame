# Round64：共享事件弃牌浏览入口（有界两次 probe）

## 交付结论

- 生产最小闭包完成：三分类事件弃牌菜单由 board 共享接线与展示，消费 source 已有 `event_discard_by_source`；presenter 两个重复浏览函数和接线删除。presenter 691→679行，board 6631→6638行。本轮不统一日志、局势或个人弃牌，不引入 Bus。
- 同最终冻结真实检查：分组 headless **56/0 exit0**；分组非 headless **58/0 exit0**；新本地/已认证真实 ENet 事件浏览点击专项 **55/0 exit0**。
- **视觉没有全部完成**：原生查看最终四张 PNG。深山町四组均有可见牌，但六牌仍为默认折叠堆，未证明六张完整展开；工房截图仍没有显示四组。叶节点落位检查是假绿风险，不能当新区可见验收。两次 probe 已用完，不继续试版或补截图。
- 最终所有 stdout/stderr 与归档 Godot logger 无 SCRIPT ERROR/SHADER ERROR/ERROR/WARNING。最终 source_drift={}、freeze_drift={}；五个阶段均 Job ActiveProcesses=0、log_handles_released=true；证据SHA读回=true；自有 generated 树已删除。

## 修改前逐函数中文说明与耦合边界

1. board `_ready()`：本地/网络 source 初始化后分别调用同一 `_bind_event_discard_controls`。组合根显式注入原有标题格式及按钮开合语义，不让共享浏览器猜模式。
2. 新 `_bind_event_discard_controls(title_format, toggle)`：把三个既有按钮按 shinto/miyama/other 投影键绑定到同一回调。标题仍为本地“新都 · 事件弃牌”、网络“公共事件弃牌 · 新都”（其它两分类同理）。
3. 新 `_open_event_discard_menu(toggle)`：本地保留切换，网络保留只打开；沿用 `_raise_modal`，不发命令。
4. board `_open_event_discard(category,title)`：退休 MapData 过滤、BaseMapArea 对象依赖和类型判断；每次打开读取 source 当前周期投影，缺字段为空，不排序、不去重、不查本机网络规则，继续调用原 `_show_card_browser`。
5. presenter `_init()`：只删除上述四按钮接线。`open_event_discard`、`_open_event_category` 删除；个人弃牌、局势、日志、抽屉浏览均原样保留。
6. `battle_play_groups_test.run()`：一次夹具生命周期修正。取消 `set_process(false)`；用已有 SeatController.REMOTE 隔离自动推进；在任何布局等待前用公开 `GameProgress.reset_progress()` 终止旧会话代际，再初始化真实规则运行时/action状态。保留公开 RegularPlay.add 两张普通牌及原56逻辑检查。
7. 新 `settle_presentation()`：仅观察正常帧循环、真实槽位/Who显现及飞行层清空，不写透明度、不调用飞牌/恢复私有方法。用于六牌加入后及目的区截图前。**已知不足**：未覆盖父组 shown/有效透明度及卷轴展开后的正式刷新时机，目的区1帧返回仍不可作为视觉完成。
8. 自有 runner：白名单冻结生产依赖、两个已有身份/端口夹具；只在独占副本生成新窗口专项。窗口事件经 viewport 的真实 GUI 分发，不 emit pressed、不直接调用浏览回调。对三分类逐一核验菜单、标题、完整数量、source ID顺序、贴图、关闭及规则状态不变。

分类应属于权威 builder，展示属于 board；source 已具备过滤合同，故无需修改数据/规则/命令适配。`view_builder.event_discard_by_source()`保持 MapData 原顺序；正式 `EventResolver.clear_all()`先 set_concealed(false) 再入弃牌，因此正式公共弃牌的明置合同不变。网络浏览只消费会话投影，没有客户端回查规则。浏览专项收到的网络业务消息为 `NETWORK_RECEIVED []`。

## 生命周期首证据与未证实因果

首次只读探针在冻结测试中插入被动日志，不改透明度或动画：

```text
headless RESULT checks=56 failures=[]
LIFECYCLE processing=false fly_count=1 queues=[6]
slot_alpha=[[1,1],[1],[0],[0,0,0,0,0,0]]
Tween elapsed仍增长
```

这推翻“set_process(false)必然冻结Tween”的初始假设。真实结构是：串行飞牌每张0.42秒、间隔0.08秒，旧夹具仅等待0.4秒就截图；同时关闭board处理使头像/飞牌跟随更新停用。第一次窗口在 first_evidence 遇到 location=null、只运行5检查失败；日志原件保留。`end_round()`等待协程不属于board帧循环，源码显示它可在唤醒后移除位置；**尚未证明它就是该次空位置的唯一原因**。

单一生命周期修正后的实际日志：

```text
headless LIFECYCLE settled=true frames=240 processing=true cards=[2,1,1,6]
headless LIFECYCLE settled=true frames=1 processing=true cards=[2,1,1,6]
window   LIFECYCLE settled=true frames=240 processing=true cards=[2,1,1,6]
window   LIFECYCLE settled=true frames=1 processing=true cards=[2,1,1,6]
```

第一阶段等待真实串行队列完成，原生图也出现四组牌；第二阶段1帧返回只证明叶节点，不能覆盖父组首次显示。源码 `_bind_player_row()`由当前卷轴完成展开后才置shown，父组无shown时alpha=0；`_select_scroll()`卷轴过渡0.48秒，夹具搬区后原等待仍0.4秒。该时序与图相符，但未加第三次探针证明其唯一因果。后续应只读覆盖父组/祖先有效透明度并经过正式刷新；全牌需真实头像点击展开，不应手工写动画字段。

## 执行命令、退出码与冻结证据

从仓库根执行；两版全部每scene180秒、fixed-fps60，原引擎和正式DLL不替换。

```text
python -B tools/tests/round64_shared_browsing.py --label lifecycle-baseline --baseline --window   # exit1
python -B tools/tests/round64_shared_browsing.py --label final --window                         # exit0
```

基线目录：`E:/scratch/round64-shared-browsing-lifecycle-baseline/isolated-14144232ee434f6398e41d4d778863db/`

- manifest SHA256 `8ad545b5a767e1fddfca8515deefe3875b133eeee17aeb3ef4dc98ab2eec0895`。
- headless56绿；window5检查、1失败、exit1、location空的SCRIPT ERROR。不得用最终绿冲销。
- 基线运行期间其它写入者修改了 `scripts/net/server/temporary_cleanup_executor.gd`，故source_drift非空；未改动或回滚此文件。冻结本身无漂移。
- probe/import/headless/window四阶段均Job0，日志句柄释放，证据读回通过，自有生成树删除。

最终目录：`E:/scratch/round64-shared-browsing-final/isolated-58688c401c0940018a6071e682873263/`

- manifest SHA256 `fe705928f71ad4b37c8d0e854f831a3e5b104ecfa72e10b6030d04bbe7d04442`。
- probe PID39364、派生worker33388：user://实测并读回位于本目录generated/appdata/FateDomination，物理E，worker_pool20。
- import PID34760 exit0；headless PID31088 12.341秒 exit0；window PID5064 13.169秒 exit0；browsing-window PID6140 14.045秒 exit0。
- 新窗口专项要求非headless且`-- window`。同一生产board先本地三分类点击，再正式session+回环ENet+既有内存RSA挑战认证、权威match_bind/过滤快照、网络三分类点击；真实空Other列表也检查。
- 全部五阶段Job0/log handles released；source/freeze drift空；artifact_readback=true；generated_removed。
- 未跑98；freezehost/countdown/restore命令与生产推进完全未改，无需扩大到这些独立专项。本次不代表完整LAN、多机、恢复actor或发行验收。未操作PID28100或用户进程。

## 最终源hash（SHA256）

|文件|hash|
|---|---|
|scripts/game_scene/battle_board_v2.gd|43b7be1d30dd785dbc3ef5cde0f02bed50e75f939944d0f64e08f1afc2007906|
|scripts/net/ui/v2_view_presenter.gd|dff5b30f48655ad8637218d082717df0da6a543cad37fd643fe35f2d8b259a6e|
|tests/battle_play_groups_test.gd|7d45aef748fc024fbfc11f12d09ce7202b0550fd518d72bf13a34dfdb84f30c6|
|tools/tests/round64_shared_browsing.py|5303d6eb2f7fbbdc0a6138d600b48ea12967d8cbdbb80cd74d30db672f45d147|
|冻结生成的tests/round64_shared_browsing_test.gd|3349f07e75e2782352f9521c87496c5f430bdccbf1c06bd03901f8a67d5e1f45|
|原Godot|ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424|
|正式signal release DLL|92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd|

与本轮基线字节对照：生产board仅_ready和事件菜单闭包改变；presenter仅删除上述接线及两函数。scene字节hash相同。git diff --check exit0；check-ignore exit1无匹配（测试/runner未被忽略）。大量既有dirty保留，不commit。

## 原生图（均在最终目录evidence/）

|文件|SHA256|原生判读|
|---|---|---|
|battle_play_groups.png|01af950e45a875a7c2e17cd8ec124a6a46c2e84a67460eb41fb371e4a00246b2|深山町四头像、四组均有可见牌；六牌折叠，未全牌展开验收|
|battle_play_groups_destination.png|6f6d878aa058402c81d2bd2954e3f5ca4dfadb4f6e2b4ca87617878340623a53|工房背景和席位可见，四组牌未显，视觉失败保留|
|round64-local-shinto.png|4eafa8a2339e7635b17688da4a4ae3a610d25283a85ec174fd080beaeb17b9b9|原本地标题与两张公开牌可见；阶段横幅正在过场，覆盖浏览器中部，未改此独立层级行为|
|round64-network-shinto.png|1b3bacb50d140b52457d4170394fa522605dfa5da7db265a507c51058c827d52|原网络标题与两张公开牌可见，无异常色块|

## 文件与缺口

本轮修改且实际运行：board、presenter、battle_play_groups_test。新增：自有runner、本文；专项GD/scene只在独占冻结生成并归档，未写正式scene。当前profile的group-preview skill补记Tween反证、父组假绿和实际展开验收。

仍保留：新区父组显现视觉未通过；六张全牌未真实点击展开；基线空位置唯一因果未证实；首探针外部source drift；历史Round58随机输入缺证。不得将最终manifest逻辑passed=true改称全部用户验收完成。
