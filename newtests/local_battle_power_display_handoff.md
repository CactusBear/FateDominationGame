# 本地最高威力显示专项

## 最小生产修改

只改 `scripts/game_scene/battle_board_v2.gd:4184`：

```diff
-return "【%s】胜者：%s，最高威力 %d" % [area_name, "、".join(names), int(detail.get("highest_power", 0))]
+return "【%s】胜者：%s，最高威力 %s" % [area_name, "、".join(names), BaseNumber.display_text(detail.get("highest_power", 0))]
```

复用网络 `SharedViewSections.public_battle_result_lines` 已有形式，只替展示入口，无数值赋值/类型转换。直接 callers 已查：`_battle_result_lines`（其生产 caller `_open_game_log`）及 `_show_battle_broadcast` 的网络摘要 Label。后者自动消费同一格式修正，但动画/确认/规则未修改。名字仍走原 `_player_name`，顺序、重复、缺名及首匹配不变；无赢家仍不带最高威力，`needs_win=false` 原文不变。无需增加组件或合并本地/网络其他语义。

## 固定 golden 与真实 Godot

新建独立 `newtests/local_battle_power_display_test.gd/.tscn`，手写固定 expected；旧 round74 expected 未改。**12.75→12.75（原12）、-2.75→-2.75（原-2）是批准的两处显示修正。** 同时覆盖 12.0→12、0/0.0→0、负整数、合法负数文本、名字顺序与重复/回退/未知、无赢家与无需战斗、标题与区域顺序、空摘要、输入值与类型不变。

实际调用原 board formatter、原网络 formatter；正式 BoardScene 实例仅以继承 probe 停用 `_ready` 启动和 `_exit_tree` 清理，不覆写 formatter/日志入口。调用真实 `_open_game_log()`，逐字核对正式 `LogBrowser/Panel/Entries` RichTextLabel 文本和弹窗状态。headless 节点文本证明，不声称窗口或像素验收。

- RED：`python newtests/run_local_battle_power_display.py --label red-fixed`，runner/Godot exit1，45 checks，13 个失败均由小数/负数文本截断及其日志、网络数字对照造成；无解析错误。
- GREEN：`python newtests/run_local_battle_power_display.py --label green`，runner/Godot exit0，45 checks、failures=[]。
- 实际 Godot 命令：`<根>/generated/Godot.exe --headless --fixed-fps 60 --path <根>/generated/project --scene res://newtests/local_battle_power_display_test.tscn`。
- RED根：`E:/scratch/local-battle-power-display-red-fixed/isolated-f85f999028ef46738b5ed01dee270a18/`。
- GREEN根：`E:/scratch/local-battle-power-display-green/isolated-e99ec50251254d4cbbadf00ef6819751/`。
- 每根 `manifest.json` 与 `evidence/local_battle_power_display_test.stdout.log` 保存真实命令、exit、checks、双端文本和实际日志文本；`evidence/frozen-owned` 保存冻结的目标源码。
- 原 Godot4.7.2/原DLL，E盘独占运行环境/子进程探针、180秒看门狗；无用户28100进程操作，无编译DLL、全量、旧套件、GUI或测速。
- source_drift={}、freeze_drift={}，ERROR/WARNING=0，artifact_readback=true；RED→GREEN冻结差异仅目标board一行，其他生产文件/新golden字节不变；`git diff --check` exit0。

## SHA256

|文件|SHA256|
|---|---|
|board修改前（与委托基线一致）|c8633ad506338f33139618e402cdb03bbe1305853bef7e94b2785d3a8e439298|
|board修改后（live=GREEN冻结）|9f1cece2079691fae275fa7c588ef542142c06e85276e50739a9ec9f36ed0d2f|
|local_battle_power_display_test.gd|879cbe7ec67dfa2432c37352b9ccb7294bae57593ecc6380a12ba3c47155000d|
|local_battle_power_display_test.tscn|dba5b1a7f43d9f8361a4ea20a302843065a457c5d4a861bfb1f4c4981eec3790|
|run_local_battle_power_display.py|d0d83401eea32c95cededc909108ad6c8bfec5a83b411c45b1228cfe2d8a0dc8|
|旧round74_public_battle_text_test.gd（未改）|6bcde574a3a5d12e19426c392b34e20e9576716d50ca3e60ad67627374bbb748|

## 收尾问题

第一次RED业务已按预期失败，但新runner漏写清理所有权manifest，导致收尾报 missing ownership receipt；已补齐run_id/generated及删除前落盘，重新取得上述完整RED→GREEN。该首轮自有generated也在精确进程/链接检查及证据归档后回收，三轮均保留日志而无生成副本遗留。辅助清理探测先遇当前Python无psutil及PowerShell编码问题，改用真实Win32_Process UTF-8查询；未终止任何外部进程。

旧 round74 历史测试刻意保留旧本地小数预期，本次不跑、不修改它；它不应再作为修正后本地显示契约。新专项明确记录批准差异。
