# 当前源码：卡面声明 → UI 说明/卡背复跑

## 结论

本次重新从当前工作树复制依赖、冷导入并执行 Godot，**没有沿用旧冻结回执，也没有 capture/改写 golden**。最终同一新冻结 3 套 **6676 CHECK / exit 0 / ERROR=[] / Job0**；全量、测速和窗口均未运行，PID 17120/28100 未触碰。源复制/执行期间 source_drift={}、freeze_drift={}；交付前关键源码摘要再次核对仍相同。

交付末次1885项全依赖复核时，其他并行写入者在本次运行完成后修改了 `scripts/net/session/lobby_session.gd`；关键builder/mirror/CardDescText/battle_board_v2仍无漂移。**本回执绑定本次新冻结，不将运行后更新的Session字节冒充已验证。** 最终证据摘要再次读回仍完全一致。

| 套件路径 | 实际 CHECK | exit | false / failures | ERROR / WARNING | 自有 Job active |
|---|---:|---:|---|---|---:|
| `newtests/current_card_info_ui_contract_test.tscn` | 6269 | 0 | 0 / [] | 0 / 0 | 0 |
| `tests/round70_declared_card_backs_test.tscn` | 320 | 0 | 0 / [] | 0 / 0 | 0 |
| `tests/shared_spell_view_contract_test.tscn` | 87 | 0 | 0 / [] | 0 / 0 | 0 |

Probe PID 32272、import PID 34416、三套 PID 25756/14112/32352 均 exited=true、exit_code=0、active_owned_processes=0。日志和证据摘要读回成功，独占 generated 已按所有权回执清理；原始证据保留。

## 历史套件定位与恢复说明

仓库文件搜索包括 Git 忽略的 tests，进一步查阅历史记录，定位到 B08 的逐对象新旧说明对照探针：原文件 `C:/Users/Administrator/AppData/Local/hermes/cache/scratch/b08_card_desc_probe.gd/.tscn`。文件如今不存在，原始源码来自历史 session `20261009_123027_322f30` 的消息 **165515**，相关报告 `reports/refactoring/B08.md`。

完整保留其全部断言：新模块实际编译、RefCounted/非Node、两常量等价、null 输入、固定种子七座开局、每对象名称、每牌说明、每 BUFF 说明、非空覆盖、单/多组选项、空选项、关联去重、层数0/1/2、名称回退。当前日志逐条统计为原 **911 CHECK**，另增 **5358 CHECK**，合计6269。只改变逐条输出、持有枚举快照以避免新克隆登记扩张循环、正常清理；没有删除旧断言或降低判据。

**精确边界：这是找到的历史“逐对象说明等价”探针，而非一份独立卡图印字人工真值表。没有找到名称就直接叫“卡面信息↔UI描述”的另一套独立原文件，不能声称已确认那套另有编号的历史套件就是 B08。** 因而保留历史来源与当前新增覆盖的区分，不拿相近套件冒充用户可能指的其他原套件。

## 当前覆盖与缺口清单

- 固定种子20261009、七座真实 GameStart，枚举当前登记对象573、卡311、BUFF9；与旧911检查完全对账。
- 对311个卡对象逐项验证 own 卡面/名称、builder→正式formatter等价、当前模型声明的数值、提示、打出条件、效果或选项文案在说明中，正式 v2 `bind_zoom_for_card` 的 title/description/image 与声明完全一致。
- 所有311牌的 `_card_back_img` 非空、资源存在、真实加载返回非null，own及隐藏公共投影严格保留自己声明。隐藏正面八字段逐项禁止，未觉醒技能正面与说明仍禁止，未声明zoom不猜。
- 原 round70 覆盖八类模型的自身牌背、跨类型声明、缺声明无回退、未解放/未觉醒、跨容器同ID，以及真实 ENet 序列化接收后 mirror 接受/坏字段与坏类型拒绝、拒绝后镜像不变。
- 原 shared_spell 87项验证实际持有来源、稳定ID、私有/公开边界、重复/冲突ID、可选zoom以及真实ENet。
- **本次上述已覆盖的模型声明项未发现数据/生产缺口：`card_info_gaps.json`=[]，311牌缺背面数0。** 这是模型声明→说明/绑定的契约结果，不证明JSON未声明的文案与卡图印字天然完整。未做卡图OCR/人工印字比对、窗口纹理视觉/鼠标命中验收，也未复跑三回合 text golden。
- 只从真实模型读背面，未按牌种或图片路径补图；未修改任何生产GD/正式数据。

## 真实命令

仓库根目录执行：

```bash
python newtests/run_current_card_info_ui_contract.py --label current-source-fixture-corrected-retry
```

runner 每进程看门狗600s、独占E环境和Windows Job Object。最终实际三条 Godot argv 的共同前缀：

```text
E:/scratch/current-card-info-current-source-fixture-corrected-retry/isolated-a81458c43f9643e5969ad8462e3400ea/generated/Godot.exe --headless --fixed-fps 60 --path E:/scratch/current-card-info-current-source-fixture-corrected-retry/isolated-a81458c43f9643e5969ad8462e3400ea/generated/project --scene
```

逐套末参依次：

```text
res://newtests/current_card_info_ui_contract_test.tscn
res://tests/round70_declared_card_backs_test.tscn
res://tests/shared_spell_view_contract_test.tscn
```

精确 argv、source_hashes1885项、物理E主/worker探针、自有进程回执和全部日志摘要均在 manifest。隔离副本仅关闭编辑器VCS自动启用并移除未包含main_scene声明，转换单独登记，原 project.godot不改。

## 失败历史：原记录保留

1. 首跑 `--label current-source-first`：新增探针 exit0、5411 CHECK、failures=[]，但 **71 SCRIPT ERROR**，整体 runner exit1。测试错误地假设所有BaseCard都有 `_shown_notes`，实际 BaseEvent/BaseSituation/BaseCard 没该字段；提前中断带来71 CanvasItem RID与142实例泄漏警告。原B08911断言没有删，原卡背320/共享牌面87已经绿；绝不把首跑算绿。
2. 读取真实BaseEvent/BaseCard后，只将新增测试的直接属性访问改成 `card.get("_shown_notes")` 且仅在真实Array声明存在时核对全部note，事件后续卡背/效果等断言仍执行，CHECK增加至6269。此问题属于新增测试错误假设，不是生产缺字段。
3. 修夹具首个冻结尝试因并行源码写入 `scripts/net/ui/v2_view_presenter.gd` 触发 **freeze copy drift**，没有启动业务场景，exit1；仅做一次新的当前源复制重试，最终成功。未覆盖/忽略漂移门。

原RED：`E:/scratch/current-card-info-current-source-first/isolated-d613d837126741beaacfe1d1bcee5c26/manifest.json`

冻结漂移：`E:/scratch/current-card-info-current-source-fixture-corrected/isolated-aed91fa9d0194fbe824a1dfdc1aa7f48/manifest.json`

最终GREEN：`E:/scratch/current-card-info-current-source-fixture-corrected-retry/isolated-a81458c43f9643e5969ad8462e3400ea/manifest.json`

最终明细：同根 `evidence/card_info_inventory.json`、`evidence/card_info_gaps.json`，以及三套 `.stdout.log/.stderr.log`。

## 源码摘要与本次文件

最终关键SHA256：

- builder `9a7ed25688ded565bce41b0a8b7473f8067553b55629fbb7d7ce88a276ec831e`
- mirror `8007a3cc6e2e1ed0bb319ba3e1b3bd21fb825e7b9bc24f3f212a724c514eef20`
- CardDescText `80c62325ac4287c57fee1b8bdb32043a1cffdfb490971076ac9f23217e5431ba`
- battle_board_v2 `9f1cece2079691fae275fa7c588ef542142c06e85276e50739a9ec9f36ed0d2f`
- 新GD `0b8d43edb0c748f89c45721d3000732627829f0628145e815484c50b357f6497`

新增：`newtests/current_card_info_ui_contract_test.gd/.tscn`、`newtests/run_current_card_info_ui_contract.py`、本报告。没有修改旧tests、生产、正式数据或其他写入者文件，没有提交。
