# A7 第①步：RegularPlay 接已有 operation

**状态：九处规则写入已逐处验证；注册表唯一映射迁移仍待其写入者，当前显式 preload 是临时修法。最新工作树四个依赖已漂移，未声明最新整树通过。**

## 范围与 SHA256

只修改 `scripts/system/regular_play.gd`，新增自己的 newtests/newtools 和此证据目录。不写注册表、lobby_session 或前端；未操作 PID 17120/28100。

- 改前：`40ad584c500f5a327b248b528175b33ffe9574b9b3998ed36aec700b09eec064`
- 当前：`1f7ffbabf1c9556bca4d33622a8a45d5b1bd00b15079cd042c55870dfd94394e`
- 原始 compare（25 案例、字节完全一致）：`bbbac51f0858a17d9e4690ff8ce3b249193b5289899334f435ac3a04cf40388b`

`minimal.diff` 只相对本轮开始的实际工作树，不含更早支付重构或 git HEAD 的其它修改。每一步另有独立 diff、SHA 和真实进程日志。

## 逐条处置

表中 RegularPlay 行号固定为本轮改前源码；操作注册表为本轮实际读取。类实现均在 `scripts/system/operations/<类名>.gd`，exec 精确入口：RemoveFromArray:5、AddToArray:5、SetProperty:6、EditNumAndReturn:4、PayMagic:17。

|审计项|动作|当前改前位置|现有 operation / 注册表行|处置|理由与等价边界|
|---|---|---|---|---|---|
|R01|开始事实|regular_play.gd:342|无 RecordLog 注册项|不动|下一环才新增 RecordLog；原去重条件与 magic 参数保留。|
|R02|真名预结算|regular_play.gd:350|ApplyCardKeywords / scripts/system/global/all_operations.gd:256|已使用、不动|apply 单词条和预结算位置不变。|
|R03|费用时点|regular_play.gd:375|EmitTimePoint / scripts/system/global/all_operations.gd:245|不可替换、不动|候选缺 card source，保留先推进 enter 游标和真实派发。|
|R04|扣魔力|regular_play.gd:380|PayMagic / scripts/system/global/all_operations.gd:178|已使用、不动|旧审计纯减法已被支付任务替换；当时余额复核、免疫、透支声明原样保留。|
|R05|支付事实|PayMagic.gd:26|PayMagic / scripts/system/global/all_operations.gd:178|已使用、不动|支付 operation 已承载标准事实；不拆出重复支付/资源时点。|
|R06|明暗置赋值|regular_play.gd:383|SetProperty / scripts/system/global/all_operations.gd:194|安全替换|对象属性存在；原位置写 hidden，不同步威力、不派亮出。|
|R07|激活赋值|regular_play.gd:384|SetProperty / scripts/system/global/all_operations.gd:194|安全替换|object.set 走原 setter，值仍为 not hidden；不绕过 source_deactivated。|
|R08|声明来源数组移除|regular_play.gd:62|RemoveFromArray / scripts/system/global/all_operations.gd:165|安全替换|原 play_zone_arrays 遍历及每区单匹配删除；不追加牌区事件。|
|R09|手牌移除|regular_play.gd:63|RemoveFromArray / scripts/system/global/all_operations.gd:165|安全替换|保留声明区删除后再次删手牌；不去重数组引用。|
|R10|从者技能区移除|regular_play.gd:63|RemoveFromArray / scripts/system/global/all_operations.gd:165|安全替换|四个固定来源中的第二个，调用次数/位置不变。|
|R11|御主技能区移除|regular_play.gd:63|RemoveFromArray / scripts/system/global/all_operations.gd:165|安全替换|四个固定来源中的第三个，调用次数/位置不变。|
|R12|side.skills 移除|regular_play.gd:63|RemoveFromArray / scripts/system/global/all_operations.gd:165|安全替换|四个固定来源中的第四个；重复元素/别名实测等价。|
|R13|追加 played_cards|regular_play.gd:386|AddToArray / scripts/system/global/all_operations.gd:164|安全替换|显式 index=-1；保留数组身份、不去重、不登记效果，先移除后追加。|
|R14|入场后威力累加|regular_play.gd:387|CardCountsPower / scripts/system/global/all_operations.gd:102；SetProperty / scripts/system/global/all_operations.gd:194；候选 EditNumAndReturn / scripts/system/global/all_operations.gd:276|安全替换完整组合|不能直接用 EditNumAndReturn（跳过 float 零）。保留入场后查询，捕获同一 power/increment 引用，can_change 时写 number + increment.number，不改 is_float、不记 power_source。|
|R15|单牌 play 事实|regular_play.gd:388|无 RecordLog 注册项|不动|原对象、tags、中文/名称、extra、concealed 与时序完全保留；下一环处理。|
|R16|逐张明置词条|regular_play.gd:396|ApplyCardKeywords / scripts/system/global/all_operations.gd:256|已使用、不动|暗置仍跳过，原 exec 保留。|
|R17|亮出批次|regular_play.gd:401|EmitTimePoint / scripts/system/global/all_operations.gd:245|不可替换、不动|全局三种亮出时点的同批次及真实 source 不能拆开。|
|R18|整批后 PLAYED_CARD|regular_play.gd:411|PlayedCards / scripts/system/global/all_operations.gd:231；EmitTimePoint / scripts/system/global/all_operations.gd:245|不可替换、不动|候选缺真实 source；必须所有牌先入场/记日志，再逐张打出派发。|
|R19|整组完成事实|regular_play.gd:416|无 RecordLog 注册项|不动|count/forced=false/finish/事实提交顺序保留。|
|R20|增量开始事实|regular_play.gd:448|无 RecordLog 注册项|不动|独立去重与原 magic 参数保留。|
|R21|finalize 完成事实|regular_play.gd:431|无 RecordLog 注册项|不动|原 forced 参数、can_finalize/has_legal_add 门禁保留。|

### 不动的续行/事务编排

K01–K19 全部不动：K03–K13/K15 机械字典写虽有 `SetDictionaryValue`（scripts/system/global/all_operations.gd:166），但本任务是规则效果替换，不把游标写变成长串效果描述；其余是 frame/defer/finish/finalize 的生命周期边界。新增支付任务的 `_begin_group`（检查点、随机/事实事务）、`_reject_group`（abort/整组 restore/终态）、done/commit 全部按字节保持。

不采用 EditMagic（夹取/魔力时点）、EditPower（power_source）、SetCardConcealed（威力差分/亮出）、DrawCardByCard（取消/牌区事件）、PlayAttack/AddAttack/PlaySkill/AddSkill（整链和次序不同）、SyncPower（覆盖非牌增量）。

## 最小运行验证

同一独立 E 盘依赖冻结，依次只改一处：R08→R09→R10→R11→R12→R13→R06→R07→R14。每步保存实际源码；比较上一版及原基线，25 案例的规则对象/集合身份、全部事实对象/参数、资源值及 int/float 类型完全相同；没有删除字段或事后规范化差异。

覆盖明/暗混组、声明 deck 来源、四个固定来源、数组别名/重复元素、零/float零/负数/小数威力、不可变 BaseNumber、免疫、逐张增量、第二张涨价整组回滚、激活转暗置 setter、done 迟到续行。预算续行和余额复核由原受影响套件再次执行。

|逐处阶段|compare 案例|CHECK（compare/regular/payment/group guard/add guard）|exit|ERROR|Job0|
|---|---:|---|---|---|---|
|baseline|25|75/54/219/9/18|0,0,0,0,0|0|True|
|R08|25|75/54/219/9/18|0,0,0,0,0|0|True|
|R09|25|75/54/219/9/18|0,0,0,0,0|0|True|
|R10|25|75/54/219/9/18|0,0,0,0,0|0|True|
|R11|25|75/54/219/9/18|0,0,0,0,0|0|True|
|R12|25|75/54/219/9/18|0,0,0,0,0|0|True|
|R13|25|75/54/219/9/18|0,0,0,0,0|0|True|
|R06|25|75/54/219/9/18|0,0,0,0,0|0|True|
|R07|25|75/54/219/9/18|0,0,0,0,0|0|True|
|R14|25|75/54/219/9/18|0,0,0,0,0,0,0,0|0|True|
|explicit-preload|25|75/54/219/9/18|0,0,0,0,0,0,0,0|0|True|

R14 与显式 preload 两版另跑 battlefield_conceal / extra_play_limit / mana_spend：CHECK 25/22/45，全部 exit 0、ERROR 0、Job0。固定 `--headless --fixed-fps 60`，每进程看门狗 600 秒，APPDATA/LOCALAPPDATA/TMPDIR/TEMP/TMP 全在本次 E 盘独占 generated 根，主/派生 user:// 实测回执在 manifest。

真实命令模板（每步原始 Godot argv 在 manifest）：

```bash
TMPDIR=E:/scratch/regular-play-existing-ops TEMP=E:/scratch/regular-play-existing-ops TMP=E:/scratch/regular-play-existing-ops python newtools/run_regular_play_existing_ops_compare.py stage --base E:/scratch/regular-play-existing-ops --owner E:/scratch/regular-play-existing-ops/isolated-bcb811c286fd49cea4c820fdd0aa0a7b --label <R编号>
```

## 组包 BLOCK 与修法边界

最初 helper 按注册表类名拼 `%s.gd` 路径，引入 freeze scanner BLOCK。已经替换为三个具体 preload，行为/compare/套件再验相同。真实命令 `python -B tools/release/role_privacy_audit.py` exit 0，stdout：

```json
{"status": "PRIVACY_PACKAGE_CONSUMER_WIRED_AUDIT_NOTRUN", "fixture_case_count": 17, "evidence": "tools\\release\\evidence\\role-privacy", "godot_invoked": false, "checks_removed": []}
```

此输出明确 NOTRUN，不据此宣称隐私运行验收。用户指定最终映射应进入 AllOperations 唯一注册表；由于本代理写权禁止修改该文件，已在 `E:/scratch/regular-play-existing-ops/registry-writer-handoff.md` 提交三项 preload + `create_instance_of` 接口片段，等待注册表写入者迁移后再接消费者。

## 尚未证实 / 阻断

- 注册表唯一映射尚未落地（当前映射在 RegularPlay 临时修法中）。
- 冻结外依赖漂移：`scripts/net/server/server_console_channel.gd`, `scripts/net/server/server_room_manager.gd`, `scripts/system/global/game_progress.gd`, `scripts/system/global/time_point_checker.gd`。这些文件未被本代理修改；现有绿灯仅对固定依赖，不认证当前热工作树。
- 未新增 RecordLog、未补时点、未做窗口/前端或全量回归。
- 规则投影覆盖显式声明根，不声称全引擎任意活动栈；guard 套件补充真实暂停/续行断言。
