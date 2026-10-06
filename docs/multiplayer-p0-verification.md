# 联机 P0 实施与验收

## 范围

本轮仅做 P0 单机解耦，网络、大厅、数据合并、存档和死循环检测尚未实现。

- `scripts/match/seat_controller.gd`：按玩家 ID 记录 local / ai / remote / vacant，单机未登记座位默认 AI。未登记默认 AI 仅用于保持既有单机行为；网络会话必须改为显式登记。
- `scripts/match/match_driver.gd`：无界面 AI 推进、四类待答处理、DummyBot 宿主契约。通过信号通知 UI 刷新、AI 行动开始及出牌。
- `scripts/match/match_commands.gd`：本地写入口门面；复用引擎判定。部署只组合部署与席位收益，结束行动仍独立。选项数量与选项一起提交。
- `scripts/game_scene/battle_board_v2.gd`：接入上述实例；保留旧测试及调试控制台调用的入口。本地玩家 setter 同步座位表；远程玩家不代答、不自动确认播报。
- `_seats` 原本是 UI 节点变量，所以座位表使用 `_seat_controller`，不覆盖旧变量。
- 没有修改 DummyBot、规则原语、卡牌 JSON、场景布局或用户删除的视频。

## 验证证据

日志根目录：`C:/Users/Administrator/AppData/Local/hermes/cache/scratch/`。
四份回归结果已汇总到 `docs/multiplayer-p0-results.json` 持久保存；包含原始 RESULT、退出码、错误与隔离窗口对照，不依赖 scratch 的保留期限。

- `p0-baseline/summary.json`：改动前 128 套全量基线。14 套存在失败、超时或运行错误；不是全绿基线。
- 新增驱动器测试先验证文件缺失时 RESULT 失败，再实现。
- `p0-driver-green.log`：20 checks，全 AI 无界面对局到第 11 回合结束，没有实例化游戏 UI；部署、战斗、终局日志存在。
- `p0-first/summary.json`：第一轮专项 6 套，255 checks 全绿、无运行错误。后续数量参数改动需由最终回归覆盖。
- `p0-mutation.log`：临时把 AI 判据退化成“不是本地”，v2 专项报 10 项失败；已恢复正式判据。
- `match_commands_test`：17 checks，覆盖合法/非法出牌、重复提交、不重复扣费、朝向修改、无效选择、部署收益不重复和部署不自动结束行动。
- `match_driver_v2_test`：20 checks，覆盖 local/remote/vacant 不代答、远程播报不自动确认、本地 ID setter、UI 选项数量与部署提交链。
- `p0-window-full.log`：非 headless 真实 v2 场景 + 新驱动器运行到第 11 回合终局，277 steps，7 checks 全绿，无运行错误。没有借旧控制器推进。
- 已原生查看 `tests/runtime_reports/p0_v2_action.png` 与 `p0_v2_end.png`：行动提示与终局排行榜可见，未见异常色块或新增布局错位。
- `p0-after/summary.json`：最终 headless 全量 132 套，包括新增 4 套。13 套存在失败、超时或运行错误，均与基线逐项相同；无新增失败。基线中的 battle_scroll 输出目录错误在后测未出现。窗口专用新增套件在 headless 下明确跳过，不计作窗口通过。
- `p0-window-suites/summary.json`：16 套非 headless 串行复跑，14 套通过且没有运行错误，包括 selection_mode 的 223 项菜单→选人→对局窗口链检查。
- 仍失败的 bellerophon_window 和 surveil_window 已在隔离的改动前项目中用同样窗口参数重跑，并在当前代码再跑一次；两边失败清单完全相同。证据：`p0-window-baseline-comparison.json`。隔离目录为 scratch 下 `p0-baseline-project`，未抽走用户工作区改动。
- 独立只读复核未发现有代码证据支持的新增回归；该结果不代替上述实际运行证据。
- `git diff --check` 通过；v2 中已无原先的直接规则提交调用和 DummyBot 调度调用，19 处提交统一通过 `_commands`。

## 后续阶段审计事项

1. `MatchDriver` 目前加载旧界面脚本，只调用 `_first_effect_location_target` 静态查询，不实例化旧界面。P1/P4 抽取查询前须核对所有消费方，避免出现两套落点规则。
2. 单机 `GameData.player_id` 回退尚未改：EffectManager 的默认触发者/费用归属、DefeatBuff 默认参数、AskPlayersSecretOption 无来源回退。服务端接入前必须审计，不能无主体时落到真实玩家头上。
3. GameStart 默认阵容与 selection_screen 的单机 AI 选人判据保持原样；联机选人阶段再接入显式座位归属。
4. DummyBot 仍直接调用规则层，P0 只迁移宿主与调度。存档不能只记一次 ai_step 就假定能确定性重放，须记录/恢复随机状态、AI 尝试集合及所有暂停续行状态。
5. 调试控制台仍走原有独立写入口；联机前必须加主机权限和日志，不允许客机直接修改权威状态。
6. `capture_rule_state()` 不是完整可序列化执行状态；不得直接拿它的相等判定证明死循环或存档完整性。P1/LoopGuard 必须覆盖执行栈、局部变量、队列、次数、随机状态，并用实测证明恢复。

## 结论与已知未修

P0 已实现并完成本轮验收，未引入可观察的新回归。不宣称仓库全量全绿。

- P0 验收时骑英之缰绳、急行的真实鼠标点击专项在基线和当时代码都失败。急行的内部标识是 `surveil`，不是侦察，中文名称以 JSON 的 `shown_attack_name` 为准。随后专项排查确认：旧测试只点了一次收拢的出牌堆，第一次点击实际仅展开，不会发动效果。已补齐“真实点击展开→等待布局→再次点击发动”，保留所有原有规则断言，并新增展开不发动的断言；没有修改游戏规则或正式 UI。两套在真实窗口下各连续复跑三次，急行每次 10 checks、骑英之缰绳每次 13 checks 全绿，无运行错误。已原生核对效果完成截图。原 P0 汇总保留历史结果，不改写旧证据；本次结果见 `docs/card-click-test-fix-results.json`。
- json_maker_ui 的存盘失败，以及 mana_spend、masters_audit_fix、private_knowledge_corrosion 的退出资源错误，均已在改动前基线出现，本轮未扩展修改范围。
- 其他 headless 的窗口依赖失败或超时已通过非 headless 复跑核实，完整结果在上述两个 summary 文件中。
- 新增测试源码位于 `tests/match_*_test.gd/.tscn`。仓库既有 `.gitignore` 忽略整个 tests 目录，因此它们存在且已运行，但默认 git status 不显示；没有修改忽略规则或替用户暂存文件。
- 已清理本轮测试追加到 `debug_console_probe.txt` 的内容，保留用户原文件；未恢复或更改用户主动删除的视频。
