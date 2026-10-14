# Round60：六套旧生命周期夹具迁移

**actual=6 / unique=6 / PASS=6 / RED=0；六套自然 exit0，308 个实际 CHECK 与唯一 RESULT 的 checks 逐套精确一致，零 SCRIPT ERROR / ERROR / timeout。仅专项通过，不提升完整 sourcePASS / releasePASS。**

## 原件、新证据与冻结

- 原 RED 不覆盖：`E:/scratch/isolated-1105873e41cd4f6a94a999e65ac6af50/manifest.json` 及 `evidence/complete-<suite>.stdout.log/.stderr.log`。
- 新独占证据根：`E:/scratch/round60-fixture-f8a66eb3fde84cabb78eae5ee64eb735/`。
- 新 `manifest.json` SHA256：`5e156b65d75419aa423fba7b2d9159a001b9ebd55e52eff15f1b417e86a582c2`。
- `execution-readback.json`：当前逐文件 hash、日志 hash、原断言保留、actual/unique/checks、Job0、清理及只读门结果的程序读回。
- `evidence/<suite>.stdout.log/.stderr.log`：本次六场景原始日志；`evidence/worker/` 保留 Godot logger 原件。`evidence/inputs/` 保留本次 GDScript/场景/工程/扩展声明字节；`evidence/six-fixtures.patch` 是 round58 原始字节与本次六文件的实际补丁。
- 原 source 指纹：`1b2e5277f8769e1c65ed42695bb8b796580b9003288443ff85ba1508784dd0c4`。
- 本次六场景共同当前 source 指纹：`f18f5f8a9304aeb8547ace912d0e32ea03af9d5f95c3b270b8d5b29be58928ff`。1802 份显式依赖，生产复用原获准清单并补当前 scripts 新增文件；测试只取六入口和真实继承/preload 闭包15文件，不复制整个 tests。
- source/frozen/finalize drift 均 `[]`，终末当前1802份重新 hash 与场景冻结一致。原六测试改前字节 hash 与 round58 归档相等。两个指纹依赖集不同，不能把指纹差异仅解释成六文件改动。
- 引擎采用既有 E 盘 `round51-engine/Godot_v4.7.2-stable_win64.exe` 的同字节自有副本，SHA256 `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`，与 round58 相等。未替换引擎或正式 DLL。工程副本仅沿用授权 editor/VCS 转换，原 application/threading 保留。

## 根因与解耦

旧 `_network_session_transferred = true` 的作用是让测试临时 board 退出后不关闭仍由夹具持有、后面还要发真实请求的 Session；不是业务成功或规则状态。当前生产 `BattleHostLifecycle` 只有真实移交后 `transferred()` 才为真，`close()` 在未移交时关闭 Session。因此不能机械删字段后让普通 owning board 提前 free，也不能设新的私有 `_transferred`、兼容旧字段或伪造 accepted。

六文件分两种实际初始化：

1. end / round28 / activation 共用 `board_for()`，正常执行正式 board `_ready()`。共享夹具加入单职责 `BorrowedSessionBoard`，只覆盖 `_bind_host_lifecycle()` 构造钩子：该命令夹具借用 Session，不取得其所有权；其余正式 ready、source、presenter、命令处理、退出释放均保留。由测试最终显式 close Session。round28、activation 通过继承复用，不复制第二套工具，不设私有替代字段。
2. active / player 的 ProbeBoard 及 location 继承的 ProbeBoard 本就跳过 `_ready()`，根本没有构造 lifecycle。移除无效赋值，保留 panel/source 释放及夹具显式 Session.close。

原在途释放、旧代际/回执、防重复扣费、拒绝保 pending、重连与真实 ENet 权威请求等原断言逐条保留：与 round58 归档的 `check(...)` 行作带多重计数比较，六文件 missing 均 `[]`。没有改断言谓词或业务请求来制造通过。

原断言文案中的“退出移交”按用户要求原样保留；在命令借用夹具内它验证 adapter 释放且外部 Session 保留，**不能独自证明正式大厅生命周期移交**。为避免失去 ownership 覆盖，共享 end 添加8条正式 owner 断言，采用未覆盖的正式场景：

- 当前 lifecycle 存在且初始未移交。
- 公开 `request_lobby()` 真正进入 `LobbySession.request("match_finished_lobby", ...)`，观测真实 `request_completed` 的正 sequence、ok=true；没有手动 emit 回执。
- 真实权威状态成为 lobby 且 match mirror 清空。
- 公开 `transferred()` 为真、旧 owner 真正释放、新正式 lobby 持有同一个 Session。
- 已移交 `close()` 不关闭新 owner 会话。
- 未移交正式 owner 的真实 exit_tree release 恰一次使 Session 生命周期失效，重复公开 close 幂等。

这8条在 end 与继承调用 `super.run()` 的 round28 中都真正执行。所有权专项显式设置终局夹具，**不是自然终局或全GUI验收**；场景命令业务原断言和真实 ENet 链没有被替代。两次执行同一父断言不计为额外套件。

## 最小旧错误 RED 与实际六专项

最小 RED 使用已有真实原日志，不重新等待180秒制造同样错误。原件每套最早错误均是给 Control 写不存在的 `_network_session_transferred`。

|真实场景|旧父exit / firsterror位置|新exit|新实际CHECK=RESULT checks|新firsterror|
|---|---|---:|---:|---|
|battle_board_end_command_test|125；run:170|0|46|无|
|round28-command-migration_test|125；verify_enet_held:173；随后继承end run:170|0|74|无|
|battle_board_activation_command_test|125；run:150|0|21|无|
|active_choice_source_command_test|0；network_cases:330；虽旧RESULT65/failed0仍SCRIPT ERROR|0|65|无|
|location_choice_source_command_test|0；network_cases:178；虽旧RESULT37/failed0仍SCRIPT ERROR|0|37|无|
|player_choice_source_command_test|0；network_cases:281；虽旧RESULT65/failed0仍SCRIPT ERROR|0|65|无|

每场景仅运行一次；全部 `--headless --fixed-fps 60`，每进程180秒。所有新 stdout/stderr 与 worker logger 无错误，failures为空/failed0；没有失败重试、没有超时放宽。308是实际断言事件数，不是308个去重业务案例。

真实命令（仓库根）：

```text
python -B tools/tests/test_round60_fixture_lifecycle.py
python -B tools/tests/test_round60_fixture_lifecycle.py --finalize-owned E:/scratch/round60-fixture-f8a66eb3fde84cabb78eae5ee64eb735/manifest.json
python -B -m unittest tools.tests.test_isolated_godot_test.ResultTests tools.tests.test_round50_candidate_selection -v
python -B tools/check_layer_deps.py --json
```

## 独立 runner 收尾问题及解决

第一条 runner 命令 **exit1**：六专项已自然exit0且真实日志全部生成，随后旧执行器 `delete_owned` 因本次 `round60-fixture-<UUID>` 不满足它的 `isolated-<UUID>` 身份格式而拒绝删除，报 `SafetyError: invalid ownership identity`。这是新 runner 接入旧清理器的错误，不是游戏失败；旧清理器安全拒绝正确，未修改旧执行器。

只修新 owned runner 的单职责清理：核对精确UUID命名、`owner.json` 与 manifest 的目录身份、全部自有进程退出/Job0/日志句柄释放，读回每份归档日志 hash，严格拒绝所有祖先/内部 reparse point，然后只删除本次 generated。

第二条命令 **exit0**，仅完成原回执收尾，不再次 import/运行任何场景；`pre-cleanup-manifest.json` 保留原未完成收尾回执，最终 manifest 标记 `initial_runner_issue` 与 `finalization_only_no_scene_rerun=true`。最终 `cleanup=generated_removed`、generated 实际不存在、原六 RED 日志 hash 不变。所有9条执行记录（probe/import/parser/六场景）均 exit0、exited=true、active_owned_processes=0、log_handles_released=true。不是声称全机器没有用户进程，也未按名字清理进程。

## parser / gate 只读结果与边界

- 真实冷导入 exit0，errors=[]。
- 独占副本逐个 `load()` 六个 GDScript 并要求 `can_instantiate()`：exit0、`PARSER_LOADER actual6=true`、errors=[]；并非只凭 import exit0。
- 现有 parser/candidate 单元16项：exit0、OK；负向中的 deliberately blocked / harness drift 输出属于单元验证预期，不是六专项失败。
- 只读 layer gate：exit0 / PASS，findings=50、allowlist=50、new=[]、stale=[]。未修改 gate 或 allowlist。
- 六文件退休精确赋值9处：end原170/242/269；round28原173；activation原98/150；active原330；location原178；player原281。其他旧私有测试消费本轮只读，不新增许可。
- 本轮未发现需要越权修复的 production 回退；不声称其余 round58 RED 已解决。未重跑完整98套、未进行窗口/真人/跨机/导出验收。

## 当前 old/new SHA256

|tests文件|round58旧SHA256|本次当前SHA256|
|---|---|---|
|battle_board_end_command_test.gd|`6ee7dc2c00a795ba8d64c9629900c9f54a09bcd3297e157350d6ebf848830d15`|`fa55b327c11b61731fe0e30a459331214967163e11512168ec3a14484c387485`|
|round28-command-migration_test.gd|`a764f947efbc97fbbabd945e41bc02c3e16087713fe0b9ef369cf0c470227319`|`58e9030b028016946a707c54a8acdac0ab9f793298155e5081ca39da8f131827`|
|battle_board_activation_command_test.gd|`f7f921291325a0b93dd4d91f9391643225c7eee9b8d8611ef8b0bc5ab1df70fe`|`4a152a1672c550839359617d2dd410e446a3f7e1cb1eefceeb76a90a4568f605`|
|active_choice_source_command_test.gd|`f52260f3edfc26ee8fba8c56928f21d364b8563c75493ce7ba6183d6d41d9890`|`b6cec1512bcb8f694752b7617d63cb7db7558450f5b54ba36ec49fe6f3423e6e`|
|location_choice_source_command_test.gd|`9bc6fe25acdf4236ac1c812c9bebfd4c30b691a1b30ea21b663ec7a61639dcee`|`6e2a7d7add541036a293e79a244796ed2e548e7508289a835301eeda64f357eb`|
|player_choice_source_command_test.gd|`e927a72b9136b0a0c1507265cc1104761e62e8965f743946cd9c4522bdf0df6d`|`104a9945fb0e6841cca3dfc56ac30c58b418e316df897daf13a0670baac46b38`|

唯一仓库写入：上述六GD、`tools/tests/test_round60_fixture_lifecycle.py`、本文。生产/其他测试/gate/旧执行器只读；没有 stage/commit。六GD处于仓库忽略的 tests 路径，不能仅凭 git diff 列表判断未修改；实际补丁与 hash 见新归档。
