# 发包就绪度与剩余工作档案（第五轮）

## 当前到底能不能出包、卡在哪
**B31 已完成原配方 7/7 站注册路由与原报告冻结时点的逐站验敏；当前静态可确认七站仍经注册表，800 CHECK/逐站验敏仅对应原报告冻结，本次修订未重跑，不能升级为当前树行为证据，最终仍须停写后同源专项/逐站敏感性复验；旧包 `8f178f6a…` 在收口前冻结，已废止为当前候选、只留历史证据。交接起初为正在重出；写入前新回执已到：`8be554ca…` 新候选四段exit0并完成持久ZIP读回，仍只是build-only/总级PARTIAL；G01/G04、B24、A9/D4、debug 裁定及最终 GUI/活局保存恢复仍未闭合，回归入口另被候选登记门阻断。不得签发行 PASS/ready。**

## 阅读口径与依据
- **已验**＝来源报告实际执行/读回的对应范围；**未验**＝没有合格运行证据（含失败、缺报告、未运行）；**待用户裁定**＝规则/范围/风险授权尚缺。已落盘不等于整项验收闭合。
- 本档案**第五轮**仅更新此文档：读取第四轮档案、Q 第 1–41 条及下列源报告，实跑只读注册表完整性扫描/层门，并核对持久证据文件数量与 B31 目标 SHA；不运行 Godot、行为测试、回归、导出或组包，不修改其它仓库文件、不提交 Git。历史 SHA/运行值仍只对原报告冻结与取证时点有效；本轮静态核验详见 `E:/scratch/dossier-round5/report.md`。
- `T`＝`docs/round74-small-integration-queue.md`；`Q`＝`docs/pending-user-questions.md`；`A`＝`docs/refactoring-open-questions.md`；`R`＝`docs/release-package-readiness.md`；`H`＝`docs/human-test-quickstart.md`。`:L`为对应文件行，数字逐项按同行报告追溯；T随追加漂移，旧行号不沿用。编号、命令/路径中的版本号不是测量值。
- **发行范围与顺序已裁定**：Windows三角色+启动脚本（R:L4）；先必要专项/最低冒烟→真人测试包→用户测试后明确通知才全量（A:L77–81）。Q:L20所写“冻结前全量”不得覆盖此裁定；本档案不再询问已决定的排期/透支/前端政策。
- 第五轮以本档逐项源报告更新当前状态；保留逐批 CHECK/SHA 与第四轮正式链作为**历史证据索引**，未重跑行为或重新认证整树。估时均是源报告规划估算，不是已发生耗时/交期承诺；文档完成、草稿完成、脚本固化不等于风险获批或新包验收。
- 历史相反结论以有证据的后续回执取代：CLI缺启动回执已补、signaling开发工程拒绝是正确负例、旧透支oracle/坏夹具部分已修。不同冻结绿色不能拼成当前整树PASS。

## 当前版本状态快照
**结论按“本批闭合 / 发行或回归阻断 / 待用户裁定”分层，不能相互抵扣。** 下表逐条指向 `docs/pending-user-questions.md`（Q）的第 1–43 条；详细下一步、源报告和估时见后文。Q 原文保留历史，本档不替用户批风险。

| Q 条目定位 | 状态层 | 当前快照 |
|---|---|---|
| `docs/pending-user-questions.md:8`（第1条/Q01） | 待裁定 | 回收站清空授权，用户资产未动。 |
| `docs/pending-user-questions.md:9`（第2条/Q02） | 待裁定 | ComfyUI 保留哪套，未指定不清理。 |
| `docs/pending-user-questions.md:10`（第3条/Q03） | 待裁定 | 旧副本须核无写者再决定清理，不借本轮授权。 |
| `docs/pending-user-questions.md:11`（第4条/Q04） | 待裁定 | scratch/reports 去索引范围并 Q29 |
| `docs/pending-user-questions.md:14`（第5条/Q05） | 阻断/待裁定 | B24 31 项未消解，不能笼统接受33 unknown |
| `docs/pending-user-questions.md:15`（第6条/Q06） | 待裁定 | F16 根因未知，继续分析或仅披露，路线并 Q27。 |
| `docs/pending-user-questions.md:16`（第7条/Q07） | 待裁定 | 身份恢复绿但排他性敏感性证据债未闭，有限人测是否接受须明批。 |
| `docs/pending-user-questions.md:17`（第8条/Q08） | 局部已闭合 | 性能夹具完整预算验敏已闭 |
| `docs/pending-user-questions.md:20`（第9条/Q09） | 待裁定 | B31 7/7 已闭，B02/B08/B28/debug 范围仍保留 |
| `docs/pending-user-questions.md:21`（第10条/Q10） | 阻断/待裁定 | A9 政策已定，实现缺零副作用 forecast 支持域/扩权 |
| `docs/pending-user-questions.md:26`（第11条/Q11） | 未验/阻断 | 新包正式命令链/静态读回已验，最终 GUI/活局保存恢复/跨网多机仍未验 |
| `docs/pending-user-questions.md:27`（第12条/Q12） | 部分已闭合/未验 | 归档类名隔离已有历史证据 |
| `docs/pending-user-questions.md:30`（第13条/Q13） | 阻断/待裁定 | G01/G04 新反例/投入按 Q25/Q26 |
| `docs/pending-user-questions.md:34`（第14条/Q14） | 待裁定 | D4 规则事实撤销/savepoint 未闭，不能借 D1/D5 绿替代。 |
| `docs/pending-user-questions.md:35`（第15条/Q15） | 局部已闭合 | D1 延迟链已有后续绿，旧“待接线”被取代 |
| `docs/pending-user-questions.md:36`（第16条/Q16） | 局部已闭合 | 启动预算夹具已修，不按旧待派单再问 |
| `docs/pending-user-questions.md:22`（第17条/Q17） | 待裁定 | A9 两诊断入口迁到 Move，保留 lower 层对照、不删断言。 |
| `docs/pending-user-questions.md:23`（第18条/Q18） | 待裁定 | RuleAttempt 档位/支持域未批，隔离 forecast 与活体 savepoint 分开验。 |
| `docs/pending-user-questions.md:39`（第19条/Q19） | 待裁定 | backup 排除仍未落盘 |
| `docs/pending-user-questions.md:40`（第20条/Q20） | 待裁定 | client 服务配置裁剪仍未落盘 |
| `docs/pending-user-questions.md:41`（第21条/Q21） | 局部已闭合 | 420→60→420 各62 CHECK、exit0/1/0已闭 |
| `docs/pending-user-questions.md:42`（第22条/Q22） | 待裁定/未验 | OS 与 Viewport 证据分层，额外 OS 覆盖时段并 Q33 |
| `docs/pending-user-questions.md:45`（第23条/Q23） | 局部已闭合 | 旧57处/B31原7只迁2已被收口取代：本批7/7、余52且无意外差集 |
| `docs/pending-user-questions.md:46`（第24条/Q24） | 待裁定 | debug 真进 client/server 且单机 ~ 静态可达 |
| `docs/pending-user-questions.md:49`（第25条/Q25） | 阻断/待裁定 | G01 精确允许/PCK/信令门未补，仍 BLOCK |
| `docs/pending-user-questions.md:50`（第26条/Q26） | 阻断/待裁定 | G04 活局正例及底层证据消费未补 |
| `docs/pending-user-questions.md:51`（第27条/Q27） | 待裁定 | 原构建索符号/原EXE无符号分析/仅披露择路 |
| `docs/pending-user-questions.md:52`（第28条/Q28） | 阻断/待裁定 | B24 31项无无条件放行子集，U033/U043条件豁免仍缺证 |
| `docs/pending-user-questions.md:53`（第29条/Q29） | 待裁定 | 不动/1957生成物去索引/另含tests290，10原生构建物暂缓 |
| `docs/pending-user-questions.md:54`（第30条/Q30） | 待裁定 | debug 推荐运行门禁（v2两处，全宿主四处），尚未实施 |
| `docs/pending-user-questions.md:57`（第31条/Q31） | 阻断/待裁定 | 22套现有测试整项消解0、静态20项未闭 |
| `docs/pending-user-questions.md:58`（第32条/Q32） | 阻断/待裁定 | PLAN blocked_notrun |
| `docs/pending-user-questions.md:59`（第33条/Q33） | 待裁定/未验 | 原两条OS输入独占桌面15–20分钟＋准备45–90分钟；26条UI缺口另按Q43估时/裁定 |
| `docs/pending-user-questions.md:60`（第34条/Q34） | 待裁定 | 三角色排除候选真导出已预演，生产一行未应用 |
| `docs/pending-user-questions.md:63`（第35条/Q35） | 阻断/待裁定 | 合法候选重新登记未做，最新为18契约4漂移而非两处，须按 Q41 审批闭包。 |
| `docs/pending-user-questions.md:64`（第36条/Q36） | 待裁定 | B24 A类7项=43–75h/B类24项=117–203h/C类0项，总178–312h含共用 |
| `docs/pending-user-questions.md:65`（第37条/Q37） | 待裁定 | known-limitations整份结构等值，不能直接增项 |
| `docs/pending-user-questions.md:66`（第38条/Q38） | 历史局部已验 | 旧包439项SHA全过、PID19692/exit0/4.7.2 |
| `docs/pending-user-questions.md:67`（第39条/Q39） | 未验/阻断 | round75三次9红/8红/59绿 |
| `docs/pending-user-questions.md:68`（第40条/Q40） | 待裁定 | 外部告示草稿已就绪但绑旧包 |
| `docs/pending-user-questions.md:69`（第41条/Q41） | 阻断/待裁定 | 18契约4漂移：当前两门与旧ERROR分类两漂移分开 |
| `docs/pending-user-questions.md:70`（第42条/Q42） | 待裁定 | 新包 `8be554ca` 已生成/读回、仍 PARTIAL；发新包/继续只发旧包 `8f178f6a`/等 A9/B24 裁定后再出第三版，尚未选择；旧版不含 B31 收口，文本重绑/送达未完成。 |
| `docs/pending-user-questions.md:71`（第43条/Q43） | 待裁定/未验 | 26 条 UI 缺口真窗口逐项估 90–136 分钟、含校准/收尾 99–146 分钟；独占 2–2.5 小时全验/指定小批 30–45 分钟/暂不验披露，待选择；方案不是运行通过，15–20 分钟仅原两条 OS 输入范围。 |
| `docs/pending-user-questions.md:73`（第44条/Q44） | 本轮新增·未闭/待裁定 | 当前同一字节冻结、两批 N=6：**合格低负载 12 轮：8 绿 / 3 次 `rename_error=1` / 1 次 `READY` 复合门；发布失败率约 25%；全轮 ERROR=0**；SCRIPT ERROR 亦全 0，`READY` 为 worker/成员/身份复合门失败，不计作发布失败。[发布8] 更早的小样本作历史保留、不并入 12 轮：低负载 N=3 三轮 worker 均 READY，首批 2/3 红落在 `files=204,index=204,rename_error=1` 目录发布，1/3 绿；不是该批 worker 启动超时。与历史 204 门仅为同一错误签名但未证实同路径；本机归因未证，不加重试、不放宽期限。 |
| `docs/pending-user-questions.md:75`（第45条/Q45） | 本轮新增·未闭/待裁定 | Q45 登记杀软、搜索索引器与 round75 runner 的外部嫌疑已逐一排除，具体持有者仍未抓；**持有者未观察到（RM 仅覆盖 9/204、长路径未覆盖）⇒ 未观察到≠已排除**。[发布8] 方向改按产品脆弱点讨论。机制已证 ≠ 本机归因已证；处理方案/继续定位/披露待裁定，不构成添加生产重试授权，不解除其它既存阻断、不提升 NOTRUN/UNKNOWN。 |

本轮新增 Q44/Q45 映射；上方第 1–43 条保持原报告时点的登记，发布失败的后续事实与证据边界见下方“本轮新增：Windows 会话目录发布脆弱点”。

**整体验收仍未闭合**：B31 本批闭合不替代 B02/B08、B28、debug、G01/G04、B24 或 A9/D4；性能夹具验敏闭合不替代 LAN 稳定性/F16；旧包启动与文档草稿不授新包/发行许可。所有“待裁定”仍未获本档授权。

## 当前产物（第五轮：旧包归档，新候选重出已到回执）
### 写入前新到：含 B31 收口的新候选（非发行 PASS）
- **已验·新持久 ZIP**：`E:/FateCandidates/human-test-candidate-8be554ca/00fcde316be244728ba0e91c29ee1c73-human-test-candidate.zip`；**933,952,547 B、440成员、CRC OK**；SHA256 `8be554cabc6aebfc6da10961f7f185e490f178961c34424dcccbab78f6261ab3`，侧车一致。本轮只读独立核整体SHA/CRC及439个成员SHA，失败0。源 `E:/scratch/package-reissue-b31/report.md`:L3–10,L294–299；本轮 `E:/scratch/dossier-round5/report.md`。
- **已验·新UUID逐段正式链**：四段exit0，五阶段PASS/独立status=NOTRUN；formal总级仍`PARTIAL_NOT_THREE_ROLE_PASS`。source snapshot/current fingerprint均`0e895a7686b9a08bd7a76c7f48f14757b4fb3329f255ec55a9c8e797d6798a28`、drift空；与旧冻结源唯一差异是B31的`game_progress.gd`从`6b99bfd4…`到`c15ce52f…`。源同报告:L18–39,L72–80,L220–268；本轮仅读包/报告，不重跑Godot，采样同源不保证之后整树仍无漂移。
- **已验·新包证据搬出，未验·自包含/发布许可**：源报告记录674个json/log持久留在新包目录`evidence-receipts/`，原中间根已清理，绝对proof引用未改写，须按`receipt-relocation.json`定位；仍非ZIP自包含。新包未证明双EXE GUI/活局保存恢复/跨网/native推广；**PID19692标题页是旧包证据，不移植给新包**。源同报告:L6–10,L207–218,L284–299；外部告示/随包文本仍须获批并重绑新SHA，生成包不等于批准发给测试者。

### 旧包 `8f178f6a…` 历史证据（下列条目不认证新包）
- **已验·历史持久 ZIP（不再是当前候选）**：`E:/FateCandidates/human-test-candidate-8f178f6a/5b62a3fb3dab4d83910b7f71c26ec1ec-human-test-candidate.zip`；**933,952,299 B、440 成员、CRC OK**；SHA256 `8f178f6a28281610e636c0cb526c2bece5299953744230fcd6357f9265d138dc`。第四轮直接读回 SHA/大小/成员/CRC exit0，证据 `E:/scratch/dossier-round4/current-artifact-readback.json`；源运行报告 `E:/scratch/formal-chain-run/report.md`。B31 后的新包不得沿用此身份或旧绿色。
- **已验·真实四命令链**：按R:L44–76的“第0步build-only + formal all + 候选组包 + 独立读回”，实际exit全0，清理后独立读回亦exit0；`E:/scratch/formal-chain-run/report.md`:L25–84,L453–456及`chain-exit.txt`、`post-cleanup-verify.log`。**这取代本档上一状态“新树正式链尚未跑完/只有旧预演包”；不取代发行门缺口。**
- **已验·包内构建回执**：`build-acceptance.json`为`STATIC_BUILD_ACCEPTED_NOT_RUNTIME_PASS`，7步exit均0、`error_lines`均空；源报告:L86–240；第四轮ZIP内读回见上述JSON。
- **已验·包内formal回执**：`phase-runformal.json`为`classification=PARTIAL_NOT_THREE_ROLE_PASS`、`run_phase=all`；`client-startup/client/server/signaling-ready/signaling-negative`五阶段PASS，独立`status=NOTRUN`（all既定语义，不补造PASS）。startup的10项producer checks全true，含`official_main_load_observed`；source manifest SHA `f03d71f36a058d21f9240b043aaa36cb14d2b70d24116582b626db3398f0d1db`，formal-runtime SHA `595b2ed22e68f35de4e57d656dce2bcc09dd2d8adf8ced7a726c8d7155c78d6b`；源报告:L242–309,L455–456及包内formal/raw proof，第四轮读回JSON。
- **已验·该包取证时同源**：包内`source-diff.json`的snapshot/current fingerprint均`27ed1f67570cde2afd60432287319fc145527e197cf7d8a33dc6303d2343d0d9`；`added=[], removed=[], changed={}`，零漂移（changed实际为空字典，不写成数组）。这是回执采样时的比较，**不是后续B31落地后仍同源的证明**；来源包内source-diff、第四轮读回JSON及源报告:L311–347。
- **未验·验收边界**：包内`known-limitations.json`仍`release_admission=NOT_GRANTED`、`full_suite=NOTRUN`、`gui_two_client=NOTRUN`、`save_restore=UNKNOWN`、`worker_ready=UNKNOWN`、`cross_machine_network=NOTRUN`、`native_promotion=NOT_ATTESTED`；`client_startup=PASS`显式`implies_multiplayer_acceptance=false`。`verified_phases`仅上述五阶段；server是源码RSA fixture+空大厅保存，不是最终双EXE活局保存，源报告:L383–385、第四轮包内读回。
- **已闭合·B31及新包生成/读回；未验·最终交付许可**：旧包已废止为当前候选但原件保留；新包见上方补记，仍未取得G01/G04/B24/A9/D4/debug风险裁定或最终GUI/活局恢复验收。源 `E:/scratch/registry-b31-final-remainder/report.md`:L4–6,L27–30,L297–298；`E:/scratch/package-reissue-b31/report.md`:L3–10。

## 第五轮新增事实与证据边界（九类）
| 类别 | 新事实与不外推的边界 | 源报告路径 / 定位 |
|---|---|---|
| ① B31 与全仓差集 | 仅 `game_progress.gd` 五行补迁，7/7 站经注册表；16 套前/后/恢复各800 CHECK、逐站未知键业务红且无日志对照同红；现余52=3+2+47、无意外差集。**闭合本批，不闭合全仓/发行。** | `E:/scratch/registry-b31-final-remainder/report.md`:L4–6,L121–152,L297–298；`E:/scratch/b31-probes-independent-rerun/report.md`；本轮只读复核 `E:/scratch/dossier-round5/report.md` |
| ② 新候选重出 | B31 在旧 `8f178f6a…` 冻结之后收口；旧包已废止为当前候选、只留历史。**交接时正在重出，写入前已收到新包 `8be554ca…` 完成回执并只读核验**；仍无发行/人测发布批准，不把这一事实升级为最终验收。 | `E:/scratch/formal-chain-run/report.md`；`E:/scratch/registry-b31-final-remainder/report.md`:L27–30；`E:/scratch/formal-chain-rerun/report.md`:L79–84（固化不等于端到端完成）；新到 `E:/scratch/package-reissue-b31/report.md`:L3–10,L207–218,L294–299 |
| ③ 回归前置精确图 | 18项固定契约、4漂移/14相符。match_view预算90→120、view_builder“费用”→“魔力消耗”、load_game可选error_sink均可逆算回登记SHA，有合法变更依据；worker两restore assert实施归属/批准链未知。**当前两门与旧ERROR分类两漂移必须分开**，scheduler/adapter未入指纹名单。 | `E:/scratch/regression-contract-map/report.md`:L5–9,L29–48,L54–90,L146–190；`E:/scratch/regression-preflight-triage/report.md` |
| ④ 玩家数据 B24 工时 | A需新探针7项43–75h；B需契约/实现24项117–203h；C=0。单项160–278h＋共用18–34h＝**178–312h**，U033/U043另6–12h。**计划不是已修复；31项仍未闭，A仅有条件风险候选、非已批准。** | `E:/scratch/b24-workplan/report.md`:L7–22,L116–122,L164–205；`E:/scratch/b24-resolution-suites/report.md`；`E:/scratch/b24-resolution-static/report.md` |
| ⑤ 旧包自洽与包外证明 | 440成员中SHA清单439项全过（清单不自引用）；真实客户端PID19692/exit0/4.7.2、标题页、无SCRIPT ERROR。**只证明旧包本机开箱启动。** raw proof/log是包外绝对引用；280个json/log与`.sha256`侧车已在持久目录，ZIP仍不自包含。 | `E:/scratch/package-selfcheck/report.md`:L11–24,L59–87,L89–135；`E:/scratch/package-doc-consistency/report.md`；持久化交接 Q38（Q:L66）、T“第五轮发现”条；本轮280文件数量读回 `E:/scratch/dossier-round5/report.md` |
| ⑥ JSON不可任意增项 / 外部告示 | `known-limitations.json`全体及manifest对应字段分别与工具重建模板作解析后完整等值比较；重算SHA也不能增项。零工具改动替代＝外部告示草稿 `E:/scratch/human-test-notice/NOTICE-human-test.md`；或获批改quickstart再重组。**草稿绑旧包，第6项B31缺口已过时于新树，需新SHA重绑/逐项复核，未获批/未送达。** | `E:/scratch/known-limitations-tool/report.md`:L5–13,L104–141；`E:/scratch/human-test-notice/report.md`:L5–7,L16–25,L66–73；Q37/Q40 |
| ⑦ 正式链一条命令 | `E:/scratch/formal-chain-rerun/rerun.ps1`固化第0步+三步，含runner/模板核验、进程写者门＋默认900s最近写入门、失败exit1即停/不暖重试、复制持久ZIP后长度/SHA读回。**静态/干跑与失败路径验证不等于本轮新链通过。** | `E:/scratch/formal-chain-rerun/report.md`:L7–14,L58–84；`E:/scratch/formal-chain-rerun/OPERATOR.md`:L9–18,L32–49；写者门负控 `E:/scratch/formal-chain-rerun/execution-report.md`（dry-run拒绝，不是正式重出失败）；T“一条命令”核证条 |
| ⑧ debug仍随包/可达 | client/server包含debug，正式v2单机物理`~`无release门禁可达adapter；网络已有拒绝。推荐v2快捷键＋统一启用接口两处门禁（全宿主四处），**仍待Q30批准、未实施，静态可达不冒充GUI按键实测。** | `E:/scratch/debug-release-options/report.md`:L16–41,L64–110,L148–154；`E:/scratch/package-doc-consistency/report.md`:L161–182 |
| ⑨ 跨套件开局握手不稳定 | round75构造修正后3次为9红/8红/59绿，前两次均未到出牌构造；与性能门“与房主连接中断”同类，共享LAN/worker链、至少两套件有源。**深层同一根因/负载因果未证；F16仍独立未知**。低负载N≥3是假设检验方案，不是已完成证据，也不能预先批准重试/放宽门。 | `E:/scratch/round75-fixture-determinism/report.md`:L5–7,L41–57,L68–77；`E:/scratch/perf-gate-fixture-fix/report.md`；Q39；已到只读归集报告 `E:/scratch/lan-worker-instability/report.md`:L5–11：负载相关/深层同因均未证，低负载 N≥3 实跑仍待授权与安静工况；三绿只能支持低负载可成功，不能证明负载因果 |

### 本轮新增：Windows 会话目录发布脆弱点（Q44/Q45；本项未闭）
本轮仅并入已审增补材料，未运行 Godot、未改生产代码或任何测试/夹具断言。上方第⑨类、Q39 及后文旧动作队列的“低负载 N≥3 待验”保留为此前冻结时点记录；下列是后续实测补记，不撤销旧红或其它既存结论。源草稿：`E:/scratch/publish-fragility-dossier-addendum.md`；问题原文：`docs/pending-user-questions.md:73`（第44条）、`:75`（第45条）。

#### 已证：现象、样本与发布边界
- 联机建房/内容同步专项中，Windows 会话目录发布存在间歇失败样本；表现为 `无法发布完整会话目录`、`CHECK false 正式同步真实完成`。首批 Run1/Run2 均已取得 worker READY；随后在 `original_sync_ready` 阶段记录 `files=204,index=204,phase=write,rename_attempted=true,rename_error=1`，staging 存在、目标不存在；不是 worker 启动超时。[发布1]
- **当前频次口径（同一字节冻结、两批 N=6）**：**合格低负载 12 轮：8 绿 / 3 次 `rename_error=1` / 1 次 `READY` 复合门；发布失败率约 25%；全轮 ERROR=0**；SCRIPT ERROR 亦全 0。`READY` 为 worker/成员/身份复合门失败，不计作发布失败；发布失败率为 3/12，任一红为 4/12（约 33%）。不合格额外尝试 A1 与历史样本不计入这 12 轮。[发布8]
- **更早的小样本，作历史保留（不并入上述 12 轮）**：同一冻结、低负载串行首批 **2/3 红、1/3 绿**。首批全三轮日志 **ERROR/SCRIPT ERROR=0**（报告亦记录 Parse Error=0），不能据此把业务失败写成成功。[发布1]
- **更早的小样本，作历史保留（不并入上述 12 轮）**：另批同一目标夹具 SHA、低负载 N=3：Run1 在更早 READY 预检红，Run2/3 绿，未出现 `ROOM_DATA_ASSEMBLY_REJECT`。发行摘要可写“另批 **0–1/3 红**”，但必须保留口径：**目标发布错误实际 0/3、整套 1/3 更早红**；不是 1/3 发布失败，也不是证实故障消失。扩展到子进程的插桩改变调度，诊断成功或超时不能反推历史原因。[发布2]

#### 机制已证 ≠ 本机归因已证
- **机制已证，限定既有受控 Windows 矩阵**：任何读发布子树子文件的进程，只要在目录发布时仍持有读句柄，就会使目录重命名失败，含 `share=7`。84 格矩阵中，原 Python archive、原引擎 `FileAccess.READ` 和 share=7 活体读子文件均令目录 rename 拒绝；原 Godot 与独立 `MoveFileW` 对应组各 3/3 error 5（ACCESS_DENIED）。share=7 能支持已有文件替换，不足以支持该目录发布。[发布3]
- **未证**：本机具体持有者未抓、历史根因未绑定；没有此次真实失败返回的同线程 Win32 错误与同刻句柄配对。`rename_error=1` 是 Godot 层失败枚举，不能单凭它还原 Win32 原因。[发布2][发布4][发布5] **持有者未观察到（RM 仅覆盖 9/204、长路径未覆盖）⇒ 未观察到≠已排除**；有效 RM 查询均返回空列表，不代表全路径或精确失败瞬时的持有者为空。[发布8]
- 已有只读权威搜索 API 回执表明 `E:/scratch/` 的 `included=false,HRESULT=0x0`，不在搜索索引范围；因此不沿用早期仅凭注册表 SearchRoot 所留下的索引器猜测。本增补不指定任何持有者，也不新增未证原因。[发布6]
- Q45 登记的杀软、Windows 搜索索引器、round75 runner 外部嫌疑已逐一排除；这不等于排除所有瞬时外部读句柄，也不把 Q45 的“更像外部瞬时干扰/时序竞争”推断升级为本机原因已证。方向按“产品脆弱点”讨论，持有者仍未抓。[发布2][发布6] `docs/pending-user-questions.md:75`（第45条）。

#### 与历史 204 发布门的关系
**唯一可用结论：同一错误签名但未证实同路径。** 两类失败均有完整清单写完后的目录发布拒绝形态，并静态汇到同一个 `RoomDataAssembler` rename 语句；但 round75 是客户端网络批准清单/会话缓存的 `RoomDataSync` 链，历史 204 门是本地正式源的 `RoomDataPreparation` 链。调用方、输入来源、时机、路径及冻结/观察条件不可抹平；`files=204` 不证明完整 path/order/hash/size 相同。[发布4]

历史 204 FAIL 未由 round60 fresh 成功解释或根治；其成功调用的 LastError 残值不能解释旧失败。不得将这两类红合并为已确认同源，也不得以成功样本冲销它们。[发布4][发布5]

#### 产品脆弱点（静态已证，不是事件归因裁决）
**产品靠目录重命名发布，无有界重试。** 当前 `room_data_assembler.gd:70–82` 在完整 staging 写完后调用一次 `DirAccess.rename_absolute`；非 OK 即 `_abort` 并返回；`120–126` 打印诊断后 `cancel()`，没有该发布步骤的有界重试。[发布7]

此结构与已证 Windows 读句柄机制共同构成发布边界的脆弱点：子文件在发布瞬间被读取持有时，这个单次 rename 发布步骤不能完成。[发布3][发布7] **这不证明本次间歇红由哪个进程造成，不作“这是产品 bug”或“这是环境噪声”的断言，也不构成添加生产重试的授权。**

#### 对人测包的含义（发行安排，不是试验结论）
按本次交办口径：**需披露，但本项本身不阻塞发人测包**。披露须包含正式同步不完成、有限样本发生情况、机制与归因分离；玩家侧建议为保留首次提示后**重新建房/重试**，不保证成功，不以重试后绿覆盖首次红。

这不是整包放行：不解除 G01/G04 等其他既存阻断、不提升 NOTRUN/UNKNOWN、不认证修复。包外告示仍绑定旧 ZIP SHA256 `8f178f6a28281610e636c0cb526c2bece5299953744230fcd6357f9265d138dc`；**重出包必须重绑实际路径、完整 SHA256 与冻结证据并复审**。本次未证明该项适用于旧包或任何新包，更未证明告示已经送达/签收。当前新候选仍是 `8be554ca…`、总级 PARTIAL；旧包证据不移植新包，Q42 发版选择与其它风险裁定不变。

#### 未闭合边界交接
1. 等待真实失败点绑定同线程 Win32 返回/错误、staging 与 destination 身份、同刻持有者句柄证据；普通活体句柄表不能补猜创建 TID/share mask。[发布2][发布4]
2. 若要升级与历史 204 门的关系，需两类真实失败各自的入口/冻结、完整 manifest 与路径身份、系统错误/句柄配对；当前只保留同一错误签名但未证实同路径。[发布4]
3. 人工重新建房/重试不是已证可靠绕行或根治；无需为本材料追加运行，不改断言、不以插桩扰动所得绿闭合。[发布1][发布2]
4. 发布者另办包冻结重绑、包外同步交付及风险裁定。告示和本增补均不是放行文件；产品处理方案未获授权。

增补来源（本地原件路径与行号）：
- [发布1] `E:/scratch/round75-lowload-n3/retry-report.md:7–11,17–18,27–30,40–43,53–54,68–69`。
- [发布2] `E:/scratch/round75-rename-holder/report.md:7–9,13–21,26–33,52–54`。
- [发布3] `E:/Projects/Godot/FateDominationGame-master/docs/round63-observer-publication-causality.md:6–9,39–53,88`。
- [发布4] `E:/scratch/round75-publish-unification/report.md:5–9,60–73,104,139,169,175–188,192–199,203–205`。
- [发布5] `E:/Projects/Godot/FateDominationGame-master/docs/round60-publication-system-error.md:5,45–54,66,79–86,110–112`。
- [发布6] `E:/scratch/round75-passive-handle-sample/effective-crawl-scope.json:11–21,88–104`。
- [发布7] `E:/Projects/Godot/FateDominationGame-master/scripts/net/content/room_data_assembler.gd:70–82,109–126`（本轮只读来源，未重跑）。
- [发布8] `E:/scratch/round75-passive-handle-sample/report.md:5–7,31–47,85–123,183,187`（本次 12 轮频次与持有者观测的唯一权威来源）。

### 回归门的四漂移分层（不把合法变更写成已放行）
- **当前通门阻断2项**：match_view源语义pin阻断current preflight；view_builder生产pin阻断auto cardback READY。合法变更仍需获批重新登记/完整integration绑定，不能抄当前SHA自批。
- **旧 ERROR 分类资格漂移2项**：load_game与validation worker影响Round42旧精确ERROR分类，**不是另外两项current prepare前置门**。worker的进度发布/error_sink有来源，两条restore assert归属/批准链仍UNRESOLVED；不得只刷新两SHA就续用旧trace豁免。
- **独立指纹缺口**：入口实际import scheduler/parallel adapter，但prepared的3路径/执行归档4路径均未纳入它们；新PLAN也不会自动补此保护，另需维护者批准。
- **未执行的合规路径**：全部候选review（未知assert单列）→审批match语义/cardback当前闭包；full scope另审modal→语义/额外ERROR/源漂移负向→新PLAN读回/validate。零Godot登记/验证人工预算30–60分钟，归属/modal审查另1–3小时，合计1.5–4小时且不保证未明项到点闭合。源：`E:/scratch/regression-contract-map/report.md`:L146–190。
- **范围不能拔高**：全库扫描656场景，现执行器formal103/headless101/program105；附加harness、GUI、loader独立mode/native standalone另计。旧49–58分钟是101-headless历史估计，不是656场景全量或当前通过承诺。源：`E:/scratch/final-regression-plan/report.md`:L17–21,L138–146；`E:/scratch/regression-contract-map/report.md`:L178–190。

## 注册表进度：逐批而非累计绿灯
以下按逐批回执统计；“已落盘”仅认证报告读回时的目标文件，**未独立核验此刻生产文件**。目标路径均相对仓库根；CHECK为各套原始数，斜线不是除法。无另注的正常业务运行exit=0，负向exit与例外见敏感性列及报告；不把导入ERROR吞为正常绿。

| 批次 | 状态 | 目标文件 | 关键CHECK/边界 | 报告前SHA → 后SHA（完整SHA256） | 敏感性结论与证据 |
|---|---|---|---|---|---|
| B01 | 已验·已落盘（专项；非整项发行PASS） | `scripts/system/operations/Deploy.gd` | 22（干净范例）；主表70候选/158次运行，非全PASS | `784f81136612cf437872552070a50556c525cbcd3e0444f20c5965e878dcfdf9` → `bc0ac14d44322e4e30df56615474700f676e0b1ddbbd898d251318c90af568fe` | 已验：路由拒绝使10条业务红；恢复22绿；非空父事务golden未验；`E:/scratch/registry-b01-deploy/report.md` |
| B02 | 待用户裁定·卡A9扩权/写权 | `scripts/system/operations/MoveLocation.gd` | 未验：无本批运行回执 | 未验／无落盘前后SHA回执 | 未验；移动规则未实现，不能拿A9诊断RED当注册表验收；`E:/scratch/registry-routing-plan/report.md` |
| B03 | 已验·已落盘（专项；非整项发行PASS） | `scripts/system/operations/ModifyAttackPowerByAttribute.gd` | 3 / 44 / 45；来源112 | `361d509c00191163ad7970216863fcbb347a75c7b10c889cbdc3e1c7342d46dc` → `3252f0e9320b5b78d9c1169824373c4ea91f8b9f26e95240bdd888734fd8c754` | 已验：输入2条业务红、来源44条红；恢复绿；`E:/scratch/registry-b03-attrpower/report.md` |
| B04 | 已验·已落盘（专项；非整项发行PASS） | `scripts/system/operations/ZeroAttributePower.gd` | 22；补充114/20条事件一致 | `d200130c1cb0e2fdff5ed4e39f5c10086c972274c3813ca99ab46d60f8855758` → `7d2ea7f046fbe5ff2c4c637d0210e300c1735aa7a0660a1985ea3d109db980c6` | 已验：回退使接线红；负增量故障使22条业务红；恢复绿；`E:/scratch/registry-b04-zeroattr/report.md` |
| B05 | 已验·已落盘（专项；非整项发行PASS） | `scripts/system/operations/AwakenSkill.gd` | 44 / 45 | `9261326ddf94eff56e166d0814c4473b16e5b09d5e4e5903f13971c0032189cb` → `bcc9d8048a631be64b7f76418a7a6dd30a2c8498c9202f1db5a2230f074f0684` | 已验：错误键与延后登记均命中目标；恢复绿；`E:/scratch/registry-b05-awaken/report.md` |
| B06 | 已验·已落盘（专项；非整项发行PASS） | `scripts/system/global/master_manager.gd` | 44 / 75；独立探针57 | `3520e6a380d1da087e391fc26c972ed64e1c3bef21d644b7e31d6e187c6bd174` → `c7b5b5c1d8d2ec2bd51433c9dab35a6e945b85a5a22934507c847a296f177015` | 已验：原套件注入仍绿；独立探针错误键8红、归属互换11红（ERROR=0），恢复57绿；`E:/scratch/registry-b06-mastermgr/report.md`；补证 `E:/scratch/registry-b06-probe/report.md`:L39–45 |
| B07 | 已验·已落盘（专项；非整项发行PASS） | `scripts/system/operations/AddEventFromDeck.gd` | 7 / 5 / 15；补充6 | `845e9ad7f18ae25a4601f86ba3fb283453b876fe713f1e1b9832be76c101d3ae` → `87d592024286299de97e813a22f9cad031512618eb0f3ccee652b4bce98c0255` | 已验：两站未知键均使目标业务红；恢复绿；`E:/scratch/registry-b07-addevent/report.md` |
| B08 | 待用户裁定·卡A9扩权/写权 | `scripts/system/operations/Move.gd` | 未验：无本批运行回执 | 未验／无落盘前后SHA回执 | 未验；移动规则未实现，不能拿A9诊断RED当注册表验收；`E:/scratch/registry-routing-plan/report.md` |
| B09 | 已验·已落盘（专项；非整项发行PASS） | `scripts/system/operations/CloseCard.gd` | 14 / 49 / 134；补充11 | `cddc52bda5d103d31043c7a85c1fcb0a85363b1dc47e47a33ad910fe564b0a65` → `9d3f6fdd1f6151e31e3ce4f60c4b5b785bf45856c140ce2075ae3682a5e83931` | 部分已验：回退使静态接线3红；真实拒绝仅ERROR门红，业务仍绿；行为敏感性未闭合；`E:/scratch/registry-b09-closecard/report.md` |
| B10 | 已验·已落盘（专项；非整项发行PASS） | `scripts/system/operations/DiscardPlayedCards.gd` | 134 / 71 / 6；旧residue=0/exit125 | `8d70c76ca53419a35b97000e7f137bf45da192e50298f1ceb13f773fcc35e5b3` → `ba4b15e29555799c041b049eb80fdd25de45c54ca2a659c67fbf4691e6c730ef` | 部分已验：回区/搬运业务红；两翻面站点未验；residue后修106绿未在本批重跑；`E:/scratch/registry-b10-discard/report.md`；后修 `E:/scratch/residue-pile-fix/report.md`（T（历史台账，以同行源报告为准）） |
| B11 | 已验·已落盘（专项；非整项发行PASS） | `scripts/system/operations/ApplyCardKeywords.gd` | 30 / 75 / 9 | `a153e1b48b93f48f7eca974b1f493997857b95cc35f8eb8f942b720023b2f7de` → `038fc545df1d317256f50a0b631216fe9c178fc4f42f74ad89288becf0449fad` | 已验：未知键使5条目标红；恢复绿；`E:/scratch/registry-b11-keywords/report.md` |
| B12 | 已验·已落盘（专项；非整项发行PASS） | `scripts/system/operations/ReleaseTrueName.gd` | 30 / 9 / 75 | `6ddfe7aa756e0b380e5fef747c687e56701251e40187cbc1c7ccd274593b11b2` → `7baf573cd0c6e439983a4a793ed36863ae103b2ffac2cc25ad142cb15780e04e` | 已验：未知键使5条目标红；恢复绿；`E:/scratch/registry-b12/report.md` |
| B13 | 已验·已落盘（专项；非整项发行PASS） | `scripts/system/operations/HideTrueName.gd` | 30 | `98b933393b8ede0c3c1d08d17a3e823c2692cdfe7b682ff1bc2a71fed8d0ccea` → `09e1fe30875bff4e883e863d7615024300c12c894d0406aa369a93b7b45c4d33` | 已验：未知键命中隐藏断言；恢复及额外合流绿；`E:/scratch/registry-b13/report.md` |
| B14 | 已验·已落盘（专项；非整项发行PASS） | `scripts/system/operations/RefillHand.gd` | 14 / 6 / 7 / 6 | `78031a67d0d9f488e33290a1d2107714387a0808389b59712d45e368241ed950` → `1fa4c26b6c955b3b4d7bce30225428aa087ae10c7c2177b4c89143d0837c1cb1` | 已验：洗回/抽牌两站分别业务红；恢复绿；`E:/scratch/registry-b14/report.md` |
| B15 | 已验·已落盘（专项；非整项发行PASS） | `scripts/system/operations/AskPlayerNumber.gd` | 101 / 16 / 115 | `db81fb5c76fa56ff6d9468e2499ef36cf5a6ab0e6c3c082c204430b6a4d1d1b4` → `f9f325490a855c4e4f5255b91d97042b7d154123e931e9982eeba95bddd5728c` | 已验：精确回退命中指定断言；恢复SHA与绿；`E:/scratch/registry-b15/report.md` |
| B16 | 已验·已落盘（专项；非整项发行PASS） | `scripts/system/operations/AskPlayersSecretOption.gd` | 101 / 16 / 115 | `bef437eae7987bb8225ec74c0ade83429867630bd836f8566ced4d75db8adb0a` → `3a6acbb02a3775e9cb8b72f1beb0f615ea97138b6a621a8fb948854d833b92d9` | 已验：未知键使4条目标红；秘密公布/专属根取消未验；`E:/scratch/registry-b16/report.md` |
| B17 | 已验·已落盘（专项；非整项发行PASS） | `scripts/system/buffs/defeat_buff.gd` | 101 / 134 / 44；补充17 | `ed1a3e085210f30f6c899f6e5c1e70d9ebb65fb57a8addf0c1659fa438d26058` → `cb797f3dc0f91d9db6d7cabb1b238726bc2ae5ca58e504054eb3e42dde7254fd` | 已验：两站独立业务红；BUFF选择/根回滚未验；`E:/scratch/registry-b17/report.md` |
| B18 | 已验·已落盘（专项；非整项发行PASS） | `scripts/system/operations/AddAttack.gd` | 30 / 80 / 49 / 26 | `4936f89c6d9dd27f108e4c2b95e5f61c8b64a5e9ff23eb2905cc7074601fee02` → `a0e312bc4d44c0bd834d9560449e016a3d844c337f57e2f3401f3d620ad0304e` | 已验：未知键使新探针9条业务红；恢复26绿；`E:/scratch/registry-b18-implementation/report.md` |
| B19 | 已验·已落盘（专项；非整项发行PASS） | `scripts/system/operations/AddSkill.gd` | 30 / 80 / 49；专项23 | `0ed7aafd4d97d519e188b59c0c24b4ddb090bb0264cf8cf80680e604650c150e` → `a0382e41be5bc47a027c22dd2db2fe96a2ab4c834c4614907f96257fe6fe9243` | 部分已验：回退仅接线断言红；业务等价由23条支撑，不是业务故障检出；`E:/scratch/registry-b19/report.md` |
| B20 | 已验·已落盘（专项；非整项发行PASS） | `scripts/system/operations/PlaySkill.gd` | 30 / 45 / 75 / 12 | `65608c5559ad120a028d0ba252a1dd855fd381150d188cc5c035c039739015c9` → `0db1d9e173fc513b572338c9feff3f1a637386eff37cce7b9724c9ed4439dc50` | 已验：未知键使探针1条业务红；恢复绿；`E:/scratch/registry-b20-implementation/report.md` |
| B21 | 已验·已落盘（专项；非整项发行PASS） | `scripts/system/global/event_resolver.gd` | 八套290：7绿/1既有红；探针11 / 7 | `551774cfd968682d3cb916754153867e43a93d0aacaf098f3af447747ec5215c` → `e2938e9201bfa8deb8cefaf77e5b8f3271c304eafa48a0bc757a2217d04b0ef1` | 已验：翻明目标红；后补放置6红/注销3红且恢复绿；旧三条身份筛选红未闭合；`E:/scratch/registry-b21/report.md`；补证 `E:/scratch/registry-b21-probe/report.md`:L31–40,L139 |
| B22 | 已验·已落盘（专项；非整项发行PASS） | `scripts/system/global/situation_resolver.gd` | 15 / 22 / 180 / 8 / 12 | `752aafc2844781b4403f4f8c99125353e411b4805b1c923e7d136839b230e43d` → `1fedced91270c5fbebe683a1b598f25c97a614cee07385981d47723ede917b5d` | 部分已验：增魔5条业务红；注销/恢复独立敏感性未闭合；`E:/scratch/registry-b22-implementation/report.md` |
| B23 | 已验·已落盘（专项；非整项发行PASS） | `scripts/system/global/battle_resolver.gd` | 234 / 101 / 56 / 180 / 71 / 47 | `6751276a7c00ba0ab9070076e539704d1a28a256b468778582f1d91ecf911e57` → `1a750eb17dc6b4bd3833be9630719d9306324c04516302569c4004acaa323446` | 已验：三站收益断言红；侦察47/10红；恢复/落盘后新副本绿；`E:/scratch/registry-b23-implementation/report.md` |
| B24 | 已验·已落盘（专项；非整项发行PASS） | `scripts/system/global/climax_resolver.gd` | 16 / 101 | `0aab398b99a56f6014203ef99199b802671dbf22aa628e4944ee86718f6b8c37` → `42bfecdd99ded617fe589d17442735bd72a41f67f64d6378dd29519a7757ca46` | 已验：未知键使移出/席位2红；恢复绿；`E:/scratch/registry-b24/report.md` |
| B25 | 已验·已落盘（专项；非整项发行PASS） | `scripts/system/deploy_rules.gd` | 22 / 21 / 8 / 36；观测13 | `e74dccdc4b46d2d77a6ebe34abfc5cc0b837dd97c3f685e99fb2b5931d4bc83d` → `e8f2c3913f9f7a2180481b8e6487ff1789271c9d0f12e6df9117548aaaec2bf5` | 已验：两站独立目标红；恢复绿；`E:/scratch/registry-b25/report.md` |
| B26 | 已验·已落盘（专项；非整项发行PASS） | `scripts/match/match_commands.gd` | 313 / 38 / 43 / 56 / 19 / 11 | `331e8f2839d5c109180f4e9e03aef3693ef0cdb549ceeb5c5d352b835baa30ae` → `0aa7af1b143e732912d007ad8d4a8bb1b891752fce24d19b626d4a0e6e9eff20` | 已验：翻面2红/移动1红/部署2红；恢复11绿；恢复场景ID变化原因未专项验；`E:/scratch/registry-b26-implementation/report.md`；探针 `E:/scratch/registry-b26-probe/report.md`:L57–101 |
| B27 | 已验·已落盘（专项；非整项发行PASS） | `scripts/system/ai/temp/dummy_bot.gd` | 21 / 22；AI观测9 | `94aec64c19a6c7f73e76d63ac1a3a5273279af11e109bb91334967a4600f7e72` → `2b121445f3d3f080384dbec496241c8214a1cc3ca58a546f01344b29caa8d0fd` | 已验：未知键使4条业务红；恢复绿；`E:/scratch/registry-b27/report.md` |
| B28 | 待用户裁定·前端冻结/台账排除（未实施验收） | `scripts/game_scene/tactical_board_ui.gd` | 未验：无实施/运行回执；T（历史台账，以同行源报告为准）称按前端冻结排除 | 未验／无落盘前后SHA回执 | 待范围裁定：A:L85已有前端暂缓；目标两直连仍由B26报告L142–143确认，不能称已迁移；`E:/scratch/registry-routing-plan/report.md`；T（历史台账，以同行源报告为准）、A:L85；`E:/scratch/registry-b26-implementation/report.md`:L142–143 |
| B29 | 已验·已落盘（专项；非整项发行PASS） | `scripts/system/regular_play.gd` | 30 / 75 / 219 / 148 / 115；投影25 | `a1cebe86a5a044b1eb139b3d103578ccd9054905ae282a4f2874f72c49b6b43c` → `a6dfe8715948f3c22e5d213eb0b26432427375fe76ca35c37dc49d98c273a15b` | 已验：两站分别1/2条业务红；恢复绿；非空根交叉golden未验；`E:/scratch/registry-b29-implementation/report.md` |
| B30 | 已验·已落盘（专项；非整项发行PASS） | `scripts/system/operations/PlayAttack.gd` | 30 / 45 / 219 / 148 / 29 | `b2e42b80d1602fa0d52c4c4b59bd00baae3d063870e49880bfe9c95431489444` → `8c9e601fccf9af94adafddaa6506a99a3564ecc2ca5663a476e18c5f8c47370a` | 已验：未知键使5条业务红（含威力）；恢复五套绿；取代此前回滚回执；`E:/scratch/registry-b30-final/report.md` |
| B31 | **已验·本批 7/7 站已闭合**（不等于全仓/发行 PASS） | `scripts/system/global/game_progress.gd` | 历史两站 13 套 605；补齐五站后 16 套改前/改后/恢复后各 800，exit0/ERROR0/Job0；五探针 22/19/21/20/154 | `4afd3ce26a142409c3b77462a85ee5f8d051c0154962022c13c62673add73e15` →（原两站）`6b99bfd4370177eeb5a3ff45e66571d844f10c904a6676aa5b03f89e8978dbb3` →（最终）`c15ce52f98065c4f89d1b30e8fbd1c8949d12e365b6b5a6339066a2f178d025d` | 新补五站逐站未知键使专属业务红、无日志对照同红，恢复绿；原两站证据保留 `E:/scratch/registry-b31-final/report.md`、`registry-b31-refill-probe/report.md`、`registry-b31-probe/report.md`；最新 `E:/scratch/registry-b31-final-remainder/report.md`:L4–6,L121–152,L297–298；独立补证 `E:/scratch/b31-probes-independent-rerun/report.md` |
| B32 | 已验·已落盘（专项；非整项发行PASS） | `scripts/system/global/effect_manager.gd` | 45 / 219 / 115 / 148；D1/D5各24 | `8e8845e12aea1d531cb40d4cd86ab2e4c35ece38c62d318f12b939b3b741f77a` → `a5f3be75ebcece0524dc3344ca29c92daeb5e898ccad6257510137a4b33f1fd8` | 已验：未知键付款金额/来源2红；恢复绿；返回仍被丢弃，D4未验；`E:/scratch/registry-b32-implementation/report.md` |


- **已验·统计边界**：按表有落盘回执的 29 批；B02/B08 待 A9 扩权，B28 遵前端冻结（不是已实现）。B31 历史“只迁两站/余五待迁”已由第五轮终态取代：**原配方 7/7 全部经路由，但 29 批落盘仍不等于原 32 批全验收，更不等于全仓单轨或发行 PASS**；源 `E:/scratch/registry-b31-final-remainder/report.md`:L4–6,L297–298。
- **已验·P00仅接口层**：路由覆盖目标28类，TABLE当时216键/188未覆盖；224 checks、隐私静态审计exit0、层门findings=4/allowlist=4/new=0/stale=0（T（历史台账，以同行源报告为准）；`E:/scratch/registry-p00-router/report.md`）。未验：全G0身份/返回/暂停/根取消矩阵、最终整合与包验收；不能称所有operation已单轨。
- **已验·B31 本批完整收口**：只改 `game_progress.gd` 五个入口表达式，原参数/顺序/返回消费不变；原两站不改。第五轮只读核 SHA 与报告最终值一致；其余批次弱敏感性、暂停/根取消及整合冻结债仍保留，不借 B31 绿灯冲销；源 `E:/scratch/registry-b31-final-remainder/report.md`:L14–30,L121–152。

## 注册表完整性：第五轮全范围对账（保留第四轮历史）
- **已验·第四轮历史扫描**：422 个 `scripts/**/*.gd`、28 配方类、32 批、57 处直连，输出 `E:/scratch/dossier-round4/registry-audit.stdout.txt`，报告 `E:/scratch/dossier-round4/report.md`；独立来源 `E:/scratch/b02-b08-decision-pack/report.md`:L177–181,L210–215。**57 是 B31 收口前值，不再作当前余量。**
- **已验·第五轮分区与零意外差集**：同配方扫描现为 **52 = B02/B08 3 + B28 2 + `scripts/debug/debug_adapters/*` 47**，B31 余量 0，`unexpected_difference=[]`；源 `E:/scratch/registry-b31-final-remainder/report.md`:L297–298 及 `completeness.json`。本轮只读复现 exit0（422 个 gd/28 类/32 批），逐类站点与该分区一致；本轮报告 `E:/scratch/dossier-round5/report.md`。原五站 `:200 RegisterObjectEffects`、`:351 RemoveFromBoard`、`:353 DiscardPlayedCards`、`:356 SyncPower`、`:369 ChangePlOrder` 已迁，原 `:285 RefillHand`、`:367 RestoreLocationBenefits` 保持路由。
- **已验·统计边界**：57不是所有TABLE注册类全仓旁路数；决策包:L162–181指出目标移动文件另有2查询直连，全部TABLE类裸扫172处。查询/新增支付类/调试与既定28动作类不得混算，也不能因此擅扩A7范围。
- **未验·全仓/发行完成**：剩余 52 处全部已归类，**无意外差集不是零旁路/自动豁免**；B02/B08 仍卡 A9，B28 无解除冻结及实施回执，debug 仍随包且单机静态可达。52 仅为指定配方类的扫描口径；完整 TABLE 的历史裸扫 172 不能混算为本轮现值。旧包不含 B31 新五站，新包同冻结回执已另取（`E:/scratch/package-reissue-b31/report.md`），不能冲销其它边界；源 `E:/scratch/registry-b31-final-remainder/report.md`:L297–298、`E:/scratch/debug-release-options/report.md`:L148–154。
- **待用户裁定·B02/B08建议乙路线**：等A9支持域/扩权批准，同一写者把业务与路由一起做；甲只迁原3站会保留先移后付/付款返回丢弃，不修A9。静态候选`git apply --check` exit0仅证明补丁能应用，Godot等价/循环preload/窗口未验；`E:/scratch/b02-b08-decision-pack/report.md`:L5–9,L107,L144–151,L185–206。免费`surveil`的MoveLocation落位语义不得误改。

## 发包真序：第0步 + 三步（取代原“六段表”）
**已验·命令契约**：权威命令块是 `docs/release-package-readiness.md:44–76`；**第0步曾被漏掉**，旧“冻结/导出/启动回执/候选CLI/组包/读回”六段拆分不能当真实CLI顺序。原档配方虽写了build-only，却未把它列作正式链前置；以下就地取代。 R只作命令依据，其旧“隐私仅剩审计未跑”口径已被G01真反例取代，不能用来放行。
**已验·历史快照链**：`E:/scratch/formal-chain-run/report.md`:L25–84 四命令 exit 全 0，保留该时点证据；**写入前新到回执**：B31 后新 UUID `00fcde316be244728ba0e91c29ee1c73` 的四段exit0、持久ZIP/SHA/CRC读回已成立，见 `E:/scratch/package-reissue-b31/report.md`:L18–39,L294–299；这不证明统一PS1本身端到端执行过（新任务按文档逐段执行）。统一入口见“证据链与可复现命令”；build-only 仍不等于正式 `--build` 的 ready-token 准入。

| 真序 | 入口/产物 | 旧包历史已验；仍未验（新包另见当前产物补记） |
|---|---|---|
| 第0步：冻结/冷导入/导出/静态审计 | `round56_three_role_freeze.py --build-only-diagnostic --source E:/Projects/Godot/FateDominationGame-master` → manifest/source-readback | **已验**exit0、7构建步骤全0/无error_lines；旧包当时未含B31余五站；新包重出见当前产物补记，G01独立策略仍未闭；`E:/scratch/formal-chain-run/report.md`:L78–240 |
| 第一步：formal运行回执 | `round56_three_role_freeze.py --run-formal --run-phase all` → formal-runtime | **已验**exit0、五阶段PASS/独立status NOTRUN、classification仍PARTIAL；不是全发行PASS；同报告:L242–293,L455–456 |
| 第二步：候选CLI/组包 | `human_test_candidate.py --output-dir` → 三角色候选ZIP | **已验**exit0、933952299 B/440成员；**未验**最终GUI/活局保存恢复；同报告:L78–84,L349–374 |
| 第三步：独立ZIP读回 | 同一CLI `--verify-zip`（不可与output-dir同传） | **已验**exit0、清理后再exit0；第四轮持久ZIP SHA/CRC亦一致；不是G01批准全集或发行认证；同报告:L453–455及第四轮读回JSON |

**已验·命令形状，收口后新任务已按文档逐段重出；统一PS1本身仍未端到端认证**（本次真实逐字执行在formal-chain-run报告；以下留作新UUID重出清单，按R:L44–76；APPROVED_ROOT不可换成普通`E:/scratch`，见下一节；所有外部路径/版本/runner SHA须在执行现场重核，不能沿用历史哈希）：
```bash
set -euo pipefail
cd 'E:/Projects/Godot/FateDominationGame-master'
APPROVED_ROOT='E:/Caches/Hermes/cache/scratch'
ID=$(python -B -c 'import uuid; print(uuid.uuid4().hex)')
BUILD_ROOT="$APPROVED_ROOT/$ID-build-only-diagnostic"
RUNTIME_ROOT="$APPROVED_ROOT/$ID-formal-runtime"
PACKAGE_ROOT="$APPROVED_ROOT/$ID-human-test-candidate"
GODOT='D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe'
TEMPLATES='C:/Users/Administrator/AppData/Roaming/Godot/export_templates/4.7.2.stable'
SIGNAL_RUNNER='E:/FateCandidates/round53-signaling-runtime-entry-sa1/diagnostic-tools/runner.exe'
# 现场核定SIGNAL_RUNNER_SHA；不得沿用旧报告值。
export PYTHONDONTWRITEBYTECODE=1
export TMPDIR="$APPROVED_ROOT" TEMP="$APPROVED_ROOT" TMP="$APPROVED_ROOT"
# 第0步：只构建非最终候选输入；SOURCE必须是停写获准的仓库根。
python -B tools/release/round56_three_role_freeze.py --build-only-diagnostic --source 'E:/Projects/Godot/FateDominationGame-master' --root "$BUILD_ROOT" --approved-root "$APPROVED_ROOT" --godot "$GODOT" --templates "$TEMPLATES"
# 检查日志/审计/source-readback，再现场取得MANIFEST_SHA；第一步：
python -B tools/release/round56_three_role_freeze.py --run-formal --run-phase all --artifact-manifest "$BUILD_ROOT/manifest.json" --artifact-manifest-sha256 "$MANIFEST_SHA" --root "$RUNTIME_ROOT" --approved-root "$APPROVED_ROOT" --godot "$GODOT" --signal-runner "$SIGNAL_RUNNER" --signal-runner-sha256 "$SIGNAL_RUNNER_SHA"
# 读formal逐阶段判据并现场取得FORMAL_SHA；第二步：
python -B tools/release/human_test_candidate.py --artifact-manifest "$BUILD_ROOT/manifest.json" --artifact-manifest-sha256 "$MANIFEST_SHA" --formal-runtime "$RUNTIME_ROOT/formal-runtime.json" --formal-runtime-sha256 "$FORMAL_SHA" --roles client,server,signaling --output-dir "$PACKAGE_ROOT"
# 第三步：独立读回；另核整体ZIP sidecar SHA。
python -B tools/release/human_test_candidate.py --artifact-manifest "$BUILD_ROOT/manifest.json" --artifact-manifest-sha256 "$MANIFEST_SHA" --formal-runtime "$RUNTIME_ROOT/formal-runtime.json" --formal-runtime-sha256 "$FORMAL_SHA" --roles client,server,signaling --verify-zip "$PACKAGE_ROOT.zip"
```
- **已验·更早预演包不得复用为当前候选**：以下字段属于 `client-startup-receipt` 的 `human-test-candidate-f04c1c458c4b.zip`（ZIP SHA256 `7d292abe3830747f9b20db2812ac6d3fad4d66c75e28eccf4ed1fe98004c8942`），**不是历史包 `8f178f6a…` 的回执字段**：`old_artifact=true`、`eligible_for_current_candidate=false`；`source_pass/release_pass=NOT_GRANTED`、`ready_token=NOT_ISSUED`、`full_suite=NOTRUN`；`E:/scratch/client-startup-receipt/report.md`:L8,L157,L190–212。`8f178f6a…` 不再是最新候选、只留历史的依据另见当前产物及 `E:/scratch/package-reissue-b31/report.md`；不将预演字段移植给它。
- **已验·读回局限**：独立reader的四故障均exit2、恢复0；原CLI不核整体ZIP sidecar SHA，精确集合仅相对上游manifest，不等于G01独立批准全集；`E:/scratch/zip-pack-readback-rehearsal/report.md`:L3–8,L88–99,L314–317。
- **已验·构建坑**：模板隔离首导出exit1→复制匹配模板后0；开发工程直接选signaling应拒绝；round56无单角色/`--freeze-only`/字面`--export`参数；`E:/scratch/export-rehearsal/report.md`:L174–177,L330–337及`E:/scratch/signaling-freeze-blocker/report.md`。旧槽不重跑覆盖。

## 证据链与可复现命令
以下是**获批后的操作入口，不是本轮执行记录**；本轮未跑 Godot/回归/正式链。源报告：`E:/scratch/formal-chain-rerun/report.md`、`E:/scratch/formal-chain-rerun/OPERATOR.md`、`E:/scratch/regression-contract-map/report.md`、`E:/scratch/final-regression-plan/report.md`、`E:/scratch/package-selfcheck/report.md`。

### 正式链：一条命令（第0步+三步）
调用方先准备 UTF-8 `caller-excluded-changes.md`，逐条说明**本包不含哪些改动**；该文件不是本档已创建的产物。先完成所选写者交接、全闭包锁源及授权，不借命令自动批准风险。
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File E:/scratch/formal-chain-rerun/rerun.ps1 -ExcludedChangesFile E:/scratch/formal-chain-rerun/caller-excluded-changes.md
```
- 顺序：build-only diagnostic新manifest → R56 formal all原生产者/消费者 → candidate `--output-dir` → `--verify-zip` → 持久复制后长度/SHA读回；每阶段期望exit0，signaling-negative子进程exit2由契约吸收。
- 每段前查runner SHA、模板、源/输出根与进程写者；默认`WriteWindowSeconds=900`，`FrozenTrees=scripts,assets,data,tools\release`最近写入命中即拒绝。**不是内核锁/全仓写权证明**，未命中也不能免owner释放；不把`-SkipWriteWindowCheck`当默认绕行。
- 新UUID、不复用旧根/manifest/formal；失败exit1即停、不暖重试、保留现场。成功产物目标`E:/FateCandidates/human-test-candidate-<sha8>/human-test-candidate.zip`，读`DELIVERY.md`及该次`execution-report.md`/四步日志，不能只看脚本退出码。
- 静态`PARSE_OK`/历史`DRY_RUN_OK`和写者门故障exit1已有源；现`execution-report.md`记录的是**dry-run刻意指向docs的最近写入负控拒绝**，不是B31后正式链完成/失败证据。主交接“正在重出”已由新任务 `E:/scratch/package-reissue-b31/report.md` 的新UUID逐段回执取代，但该任务不等于本PS1端到端通过。
- 证据路径：`E:/scratch/formal-chain-rerun/report.md`:L58–84、`OPERATOR.md`:L9–18,L32–49,L107–139、`execution-report.md`:L3–14；主代理写者窗口敏感性另见T“一条命令”核证条。

### 回归管线：先候选审批，再新PLAN，再执行
**当前阻断未解除，旧 `E:/scratch/final-regression-plan/PLAN.json` 是 blocked_notrun 草稿，不可直接执行或手改ready。** `nextcandidate`不是命令；先按Q41批准登记/完整闭包，worker未知assert单列review，scheduler/adapter指纹缺口另批处理。以下`NEXT_PLAN`须由执行者设置为approved-root下全新JSON路径，不能沿用旧PLAN/attempt。
```bash
cd 'E:/Projects/Godot/FateDominationGame-master'
: "${NEXT_PLAN:?先设置全新的获准候选PLAN输出路径}"
# 仅在候选登记与批准输入齐全后：生成headless候选，prepare exit0仍不代表ready。
python -B tools/tests/test_round29_integrated_evidence.py --round71 --prepare-candidate "$NEXT_PLAN" --source-root 'E:/Projects/Godot/FateDominationGame-master' --approved-root E:/scratch --headless-only
# 独立读回/round71_validate_prepared(plan)重建验证通过，且用户人测后明确通知全量才执行：
python -B tools/tests/test_round29_integrated_evidence.py --round71 --execute-prepared "$NEXT_PLAN" --approved-root E:/scratch --collect-failures --jobs 2 --cpu-budget 4 --memory-budget-bytes 2147483648 --disk-budget-bytes 8589934592 --cancel-file E:/scratch/cancel.flag
```
- 若选择外部integration approval方案，prepare增`--approved-inputs <获准JSON>`；full scope另审批`modal_regression`完整producer/test/dependency/count闭包并去掉`--headless-only`，重新生成新PLAN，不在上例暗称full已ready。
- 读回精确目标：blockers空、cardback READY、headless的`ready_for_headless=true`；full另要`ready_for_full=true`，两者都不是已跑业务PASS。保留源/目标/executor SHA及原断言/计数下限，做缺标签/断loop/终局false/RESULT不一致/额外ERROR/源漂移负向，不能放宽白名单换绿。
- `cancel.flag`执行前须不存在；jobs2资源预算不意味着LAN在高负载下已稳定。当前101-headless不是全库656场景；GUI/native/harness/loader mode与新增差集单列，执行scope须明批。源码方案与命令出处：`E:/scratch/regression-contract-map/report.md`:L146–190；`E:/scratch/final-regression-plan/report.md`:L7–21,L129–146。

### 层门与注册表完整性（只读可重现，不替代行为）
```bash
python -B tools/check_layer_deps.py --root 'E:/Projects/Godot/FateDominationGame-master' --json
python -B 'C:/Users/Administrator/AppData/Local/hermes/skills/software-development/fate-domination-engine/scripts/registry_completeness_audit.py' 'E:/Projects/Godot/FateDominationGame-master' 'E:/scratch/registry-batch-recipe/report.md'
```
本轮两者实际exit0；层门findings=4/allowlist=4/new=[]/stale=[]，未扩白名单。注册表扫描422 gd/28类/32批、52处，必须再按站点集合核只余B02/B08 3、B28 2、debug 47，不能凭exit0宣称零旁路。源：`E:/scratch/registry-b31-final-remainder/report.md`:L142,L297–298；本轮静态执行见`E:/scratch/dossier-round5/report.md`。

### SHA对账与包外证明留存
统一按**新包现场**绑定 source snapshot/selector闭包→EXE/PCK/native→build manifest→raw startup/logs→formal→candidate manifest→ZIP成员/整体侧车；各层路径/集合/SHA和阶段语义一起读，不以整体SHA替代G01独立批准集合或G04底层证据。
```bash
: "${ZIP:?指定待核的实际候选ZIP路径，不默认沿用旧包}"
# 外置侧车必须在ZIP旁；reader本身不读侧车，所以另核整体SHA。
python -B -c 'from pathlib import Path; import hashlib,sys; p=Path(sys.argv[1]); got=hashlib.file_digest(p.open("rb"),"sha256").hexdigest(); expected=Path(str(p)+".sha256").read_text(encoding="utf-8-sig").split()[0]; print("ZIP_SHA256",got); assert got==expected' "$ZIP"
# 成员SHA + CRC；不能拿正常CRC代替SHA，不能把清单自身漏计当损坏。
python -B -c 'import hashlib,zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); rows=[r.split("  ",1) for r in z.read("SHA256SUMS.txt").decode("utf-8").splitlines() if r]; bad=[n for h,n in rows if hashlib.sha256(z.read(n)).hexdigest()!=h]; print("members",len(z.infolist()),"checked",len(rows),"failed",len(bad)); assert not bad; assert z.testzip() is None' "$ZIP"
```
- 旧包439/0、440成员、PID19692等仅作历史对照，不要求新ZIP字节复刻旧包。完整reader仍须由正式链绑定manifest/formal后执行，以上两行不是它的替身；不据SHA声称真GUI/活局恢复/安全准入通过。源：`E:/scratch/package-selfcheck/report.md`:L11–24,L59–87,L89–135；`E:/scratch/known-limitations-tool/report.md`:L134–142。
- 旧包持久外部证明目录：`E:/FateCandidates/human-test-candidate-8f178f6a/evidence-receipts/`；Q38登记两个证据根280个json/log，另有ZIP旁`.sha256`。本轮只读枚举确为280；**备份不改原formal的绝对引用，未重写为包内/可迁移引用，也不等于已给每个备份重新签全链**。外部告示也不进入JSON模板/ZIP，须获批后随新包SHA重绑。源：`E:/scratch/package-selfcheck/report.md`:L59–87、`E:/scratch/human-test-notice/report.md`:L66–73；持久化交接Q38与本轮`E:/scratch/dossier-round5/report.md`。

## 回执消费链契约（第四轮核证，第五轮保留）
- **已验·反例与格式核证**（`E:/scratch/receipt-consumption-chain/report.md`:L5–15,L17–44）：rehearsal-2 raw启动回执被原消费者拒绝`CLIENT_STARTUP_RECEIPT_SCOPE_MISMATCH`；直接当formal输入拒绝`FORMAL_RECEIPT_EXACT_PHASES_REQUIRED`。它有真实启动事实，却缺schema/层级/绑定，**不是只差路径**；不得手改JSON或搬目录冒充原回执。
- **已验·原链**（同报告:L48–94,L180–225）：R53生产`<root>/client-startup/runtime.json` → R56复核并包装`formal-runtime.json` → candidate消费formal；raw schema为`round53-client-startup-v1`，恰一条run、三份日志，绑定manifest/EXE/PCK/source及前后核验；物理E盘私有子根必须在`E:/Caches/Hermes/cache/scratch`下。formal恰含六阶段key（client-startup/client/server/status/signaling-ready/signaling-negative）；有key不等于全PASS。
- **已验·旧候选及 B31 后新候选的原回执链；未验·最终双EXE GUI/活局保存恢复**：旧链由 R56 调原生产者并包装消费成功（`E:/scratch/formal-chain-run/report.md`）；B31 后新候选已走同一生产/消费契约（`E:/scratch/package-reissue-b31/report.md`:L18–39,L72–80），后续重出仍须走此契约。复用时 receipt 与 receipt-sha256 成对，原 root/logs/users 不得只拷 JSON 冒充；rehearsal-2 仅两角色不合三角色输入（`E:/scratch/receipt-consumption-chain/report.md`:L184–233）。持久备份不改原回执绝对路径/哈希，清理后的新包原引用须按 relocation 映射定位，仍非 ZIP 自包含，也不让旧 artifact 成为 current eligible；headless 启动不覆盖 GUI/联机/保存恢复。

## 未闭合清单：现象、定性、影响、下一责任人
| 项目/现象 | 当前定性与依据行（不是新验收） | 影响面 | 谁做什么 |
|---|---|---|---|
| B02/B08卡A9；满魔力移动仍走旧次序 | **已验·静态，待用户裁定·方案/扩权**：配方3站未迁；纯路由不改变旧先移后付，推荐乙路线，A9政策本身已定；`E:/scratch/b02-b08-decision-pack/report.md`:L5–9,L109–151 | 注册表组织等价不等于规则正确；缺零副作用forecast，支付监听可改变合法性 | 用户定支持域/扩权/诊断入口；同一A9写者获权后接业务及路由，不先迁再冒称A9通过 |
| D4支付拒绝后用量/层数/chosen/规则日志撤销 | **待用户裁定**；无公开规则事实撤销，事务归属token非规则图恢复；受限局部候选涉EffectManager/GameLog/EventJournal/FactDelivery，被动savepoint仍需额外原语；T（历史台账，以同行源报告为准）；`E:/scratch/payment-d4-transaction-feasibility/report.md` | 失败原子性；D1补偿/D5队列绿不覆盖D4 | 用户与A9一次决定统一RuleAttempt范围；主代理独立阶段验证，不能借D1/D5标闭合 |
| F16恢复断线根因未知 | **已验·符号可得性；未验·根因；待用户裁定路线**：本机gateway/worker引擎`4.7.2.stable.official.ed1daf0bf`、SHA `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`；两官方release各34资产均无Windows PDB/map；自编译仅得新EXE符号。`E:/scratch/f16-symbol-feasibility/report.md`:L15–46,L67–71,L127–133 | 不是导出client符号问题；本机官方分发字节未独立核验，旧失败/成功原目录已回收，归档不等于可重放输入 | 推荐原EXE+隔离冻结+既有日志继续最小分析，同时索取原构建留存；用户可选仅记限制，换可符号化新构建须另批；不授恢复PASS |
| 玩家数据审计 B24（非注册表 B24） | **未闭合 31 项，待批准工作包/风险范围**：22 个候选套件整项消解 0；静态 20 项亦未整项闭合，U027/U028 违纯查询、U044 后置门挡不住隐式建库。A=7（43–75h）、B=24（117–203h）、C=0；加共用 18–34h，总 178–312h，U033/U043 另计 6–12h；`E:/scratch/b24-resolution-suites/report.md`、`b24-resolution-static/report.md`、`b24-workplan/report.md`:L7–22,L164–195 | 正式发行须闭合全部 31；仅 A 七项可作为**明确批准且 B 类24项先闭合等条件成立**的人测残留候选，不是自动放行；未证崩溃直接因果 | 用户拍 Q05/Q28/Q31/Q36；工作包未开工、闭合数未增加。不得把 Q36 选项文案误读为“其余 24 项写告示就获批”；JSON 不可任意增项，披露另按 Q37/Q40 |
| G01独立精确允许集合未消费 | **已验·差分反例，未验·补丁/最终包；待用户裁定投入**：合成三角色追加普通`credentials.txt` 3/3 exit0，追加`.log` 3/3 exit2；PCK内`misc/extra.pem`仍exit0；`E:/scratch/g01-allowlist-gap/report.md`:L5–10,L56–68 | 通用全包allow、PCK策略/精确缓存与专用external-native信令消费者均缺口；旧“只是证据弱、包不会更不安全”被取代：补消费者有实质安全提升 | 发行工具唯一写者消费现有批准策略/冻结全集，缺批准fail-closed，不拿待审包全集自批；估10–16h，支持批准external-native合计14–24h（同报告:L121–145），非旧4–8h |
| G04 formal仅未开局大厅保存 | **已验·消费者反例，未验·活局正例/接线；待用户裁定范围**：四种合成缺证server PASS均被validator接受，PASS+exit1负控拒绝；`E:/scratch/g04-activation-gate/report.md`:L13–41 | `saved=false, room_state_saved=true`非活局；仅server PASS字符串不深读底层证据；补门不自动修保存缺陷，现链也未授RELEASE_PASS | 建议正式server+2认证非观战客户端（AI=0）同局、一次真实规则变化、仍playing时saved=true并读日志/同实例关闭；6–12h仅server+源码客户端，总14–28h才含最终双EXE GUI；同报告:L5–7,L98–118 |
| 性能门完整网络验敏已闭，独立断线仍未定根因 | **已验·该夹具门闭合**：完整420→60→420，三轮各62 CHECK，exit0/1/0；续局终局209.742/158.209/161.139s，父/worker ERROR=0、Job0；唯一红为预算终局断言。`E:/scratch/perf-gate-network-injection/report.md`:L5–26,L48–62；取代旧修复报告的完整负向欠账 | 不再把旧60s预算RED列现存门；不是产品性能提升，也不能证明间歇恢复/续局断线已修复；运行期间match_commands/PlayAttack漂移，最新整合未验（报告:L80–112） | 主代理收口预算门，不重复补已完成的网络负向；仅对最终同源必要链复验，并继续单列F16根因未知 |
| `round75` 驱动已修，开局稳定性仍红 | **已验·同序权威预览构造；未验·稳定性/restore**：仅夹具从真实 `preview_group` 推出 `can_submit=true` 组，保留 90s/原断言；三次 **9/红/exit1、8/红/exit1、59/绿/exit0**，前两次均在开局握手且尚未到构造；1ms 唯一目标红，恢复 59 绿。`E:/scratch/round75-fixture-determinism/report.md`:L5–7,L41–77 | 旧“未落盘”已被取代，但不是三次稳定通过；性能门曾同类断连，跨套件共享 LAN/worker 链的现象单列；不据一次绿撤红 | Q39：低负载 N≥3 最小实验/继续调查或披露；负载相关仅假设、深层根因 UNKNOWN，不擅自重试/放宽就绪预算，不与 F16 根因画等号 |
| B26/B31 已到终态，范围仍有保留项 | **已验·B31 本批收口**：B26 六套 313/38/43/56/19/11 历史绿；B31 已从两站升级 7/7、16 套 800、五站逐站业务验敏。`E:/scratch/registry-b26-implementation/report.md`:L88–146、`E:/scratch/registry-b31-final-remainder/report.md`:L4–6,L121–152,L297–298 | 原 B31 五站不再是当前阻断；剩 52 处是 B02/B08、B28 与 debug，不能称全仓完成 | 主代理更新 Q23 的历史状态、不改只增 Q 原文；B02/B08 等 A9，B28 遵前端冻结，debug 等 Q30；新包重新绑定 B31 最终 SHA |
| 已落盘批次仍有弱敏感性/既有红 | **未验·整合债**：B09只有静态接线/ERROR门；B10两翻面站点未独立验；B19仅接线敏感性；B22注销/恢复未独立验；B21旧三条身份筛选红未修。对应进度表报告，尤B09:L111–118、B10:L121、B21:L6–8及探针报告:L139 | 不等于这些批次未写入，但也不能升级“32批逻辑全通过”；暂停/根取消交叉覆盖不足 | 主代理补独立业务探针/分类既有红，再同源小范围整合；不得靠ERROR噪声、扩白名单或删断言转绿 |
| 身份恢复敏感性证据债 | **已验·套件35 CHECK绿；未验·网络排他性敏感性**；三次注入被额外断开/前置失败污染，未落夹具；T（历史台账，以同行源报告为准）；`E:/scratch/resume-fixture-sensitive-20261011/REPORT.md` | 网络身份恢复断言可靠性，不是现存“3红阻断” | 主代理如需补证，执行尚未运行的真实GREEN+同源短场景方案；用户决定有限人测是否接受证据债，不能称已验敏 |
| 窗口输入层级与前端边界 | **已验·有限层**：凛/葛木OS鼠标；美狄亚/美杜莎分帧Viewport；T18核心117/边界132/矩阵161均绿但也是Viewport，OS未验；T（历史台账，以同行源报告为准）；`E:/scratch/battle-end-window-verification/report.md`、`E:/scratch/t18-window-verification/report.md` | 窗口画面/GUI路由不自动证明所有OS输入，更不是最终EXE输入验收 | 主代理独占窗口补最终包最低交互；用户若要求全部OS链，再安排专场；不重复改顺位/玩家名 |
| 悬浮展开四红与D15窗口仍缺证 | **未验·真实窗口**；四红已定性headless鼠标warp未更新生产读取位置，不能证明真实UI回归；T（历史台账，以同行源报告为准）；`E:/scratch/local-spell-hover-red/report.md`。D15静态/旧ENet绿不等当前窗口点击绿（A:L87,L115） | 输入可用性与真实包体验仍需窗口；不把环境限制当功能已通过 | 主代理窗口槽空闲后按报告重跑；未经授权不改前端；顺位折叠/顶栏玩家名/缺省威力/金框差异继续仅登记（A:L104–113） |
| scripts/debug进包且静态可达 | **已验·冻结选集/静态依赖与合成实测，未验·生产GUI修复**：client/server选入20源文件（10gd/10uid）+1场景，真PCK各20脚本remap/gdc成员+1场景remap；signaling冻结不选；正式v2单机物理`~`→启用→session→adapter旁路，网络原有拒绝；`E:/scratch/debug-release-options/report.md`:L16–41及`E:/scratch/package-rehearsal-2/report.md`:L271–292 | A只剔除debug使两角色冻结硬依赖拒绝；C exporter过滤两例export exit0但release宿主load失败/探针exit3；B保资源门禁可行但不是包内零debug/防篡改证明 | **待用户裁定Q30**：推荐v2快捷键+统一启用接口2处`OS.is_debug_build()`，若覆盖旧宿主合计2脚本4处；实施后真release窗口/直调API/正常输入回归；同报告:L64–110,L148–154，尚未实施 |
| backup场景确进PCK | **已验·范围事实；待用户裁定排除**：client/server真PCK含`json_maker/json_maker_backup.tscn`；无正式引用，隔离删除后两角色import/export均0；`E:/scratch/package-scope-suspicious/report.md`:L7–40；Q:L39 | 多带开发/备份载荷，不是已证明泄露凭据或导出失败 | 用户批排除；主代理复用现有EXCLUDED组件机制，最终重导/PCK核无该项，不建新路径表 |
| client多带server.cfg/signaling.json | **已验·范围事实；待用户裁定裁剪**：普通client不读取；对应服务角色需保留；`E:/scratch/package-scope-suspicious/report.md`:L44–85；Q:L40 | 角色最小范围/配置载荷；不是普通客户端运行降级必需 | 用户可与backup一次批准；主代理用既有排除+角色runtime_files保留，再验每角色，不组包后手改 |
| 停写快照老化、归档类名遮蔽 | **未验·最终全闭包许可**；旧436项为260无已知写者/4仍有写者/172未知，runtime仍3开放+33缺证，非当前实时人数；后来P00/T18/RecordLog已有完成回执，不能继续称都在写，也不能据此释放整树；`E:/scratch/writer-stop-convergence/report.md`:L3–20,L332–346；T（历史台账，以同行源报告为准） | 全局类曾指向归档，修复前涉及全局类的历史绿不可沿用；并发漂移使整合证据失效 | 主代理逐owner收stop+精确写权释放，重采全闭包；保留.gdignore隔离/冷缓存指向核验；只补必要专项，不违Q05自动全量 |
| 仓库卫生与scratch/reports跟踪 | **已验·只读清点，待用户裁定执行范围**：跟踪2496文件、索引逻辑60.66MiB；建议第一批1957生成物仅去索引，另10原生构建物有读取依赖暂缓；根tests另跟踪290；`E:/scratch/repo-hygiene-plan/report.md`:L5–8,L64–74,L130–157 | 取代Q04旧2453及旧“需再核2496”口径；去索引不删实物、不释放磁盘、不改Git历史/远端；仅ignore挡不住已跟踪tests | 用户拍Q29（不动/仅1957/另含tests290）；卫生执行者另案复核留存/消费者/漂移后精确去索引，不借第四轮授权改ignore/add/commit |
| 隔离副本空间与清理所有权 | **已验·历史资源中止；未验·当前余量**：性能完整负向被空间门拦；T（历史台账，以同行源报告为准）记后续清理恢复空间，不能拿它当此刻容量；`E:/scratch/perf-gate-fixture-fix/report.md`:L105–116 | 影响并行数/可重跑性，不是测试行为红 | 主代理正式冻结前现场查空间，仅清已结束且归属明确副本，保留最小证据/存档；用户资产/回收站/ComfyUI继续未授权不动 |
| RecordLog已新建但调用点未迁 | **已验·原语/注册，未验·消费者迁移**：14/34 CHECK绿，现有operation内16处、RegularPlay5处、全局编排11处仍未迁；T（历史台账，以同行源报告为准）；`E:/scratch/a7-recordlog/report.md` | A7日志operation化的剩余范围，不是自动导出阻断证明 | 主代理明确本次必需范围；若属于已承诺实现则串行迁移/验敏，不把“已新增原语”写成全部接入 |
| 新候选已重出/读回，最终验收与发版选择仍缺 | **已验·新包8be554ca**：933952547 B/440成员/439项SHA全过/CRC正常，四段exit0、五phase PASS，总级PARTIAL；`E:/scratch/package-reissue-b31/report.md`:L3–10,L294–299及本轮静态读回。**未验**最终双GUI/活局保存恢复/跨机跨网 | 旧8f178f6a只留历史；旧PID19692不能迁给新包；raw proof/log仍在包外，持久备份不让ZIP自包含；G01/G04等仍未闭 | 主代理收发布/风险裁定，外部告示与随包文本重绑新SHA并清过时B31项；Q11/Q37/Q38/Q40的未验边界不变，用户通知后才全量 |
| 回归入口重新登记与执行器指纹缺口 | **阻断/待裁定**：18契约4漂移；当前match/cardback两门与旧ERROR分类两漂移分层，worker两assert归属未闭，scheduler/adapter未入指纹。`E:/scratch/regression-contract-map/report.md`:L5–9,L146–190 | 旧PLAN blocked_notrun；合法差异不等于获批登记，101-headless不等全库656 | Q32/Q35/Q41：获批候选/scope→负向→新PLAN读回/validate；不抄当前SHA自批、不改历史ready/白名单 |
| 补充告示与包证据可迁移性 | **待裁定/未验**：JSON整份结构等值不可增项；外部11项草稿绑旧包，新包原proof路径因清理需relocation映射。`E:/scratch/known-limitations-tool/report.md`:L5–13,L104–141；`E:/scratch/human-test-notice/report.md`:L66–73；`E:/scratch/package-reissue-b31/report.md`:L207–218 | 旧280与新674份包外材料不等于ZIP自包含；告示不是豁免、不代替G01/G04 | Q37/Q40：批准外部附件或quickstart重组，绑定新SHA/复核B31与B24表述、留送达证据；本轮不改告示/指南/JSON |

## 待用户拍板清单（与 Q 的全部第 1–43 条对齐）
本节逐号映射 `docs/pending-user-questions.md` 第 1–43 条；`Q:L` 是此次读取版本的行锚点，条目编号为稳定身份。**已闭合/未验登记不等于全部都要重问**；Q 原文只增不改，本档用新源报告订正历史状态，不把主代理暂按接受/候选方案当用户批准。写入前并发追加的新包回执另作产物补记；本次最小更正补齐 Q42 发版选择与 Q43 真窗口时长/范围映射，不代用户选择。具体源报告见当前快照、第五轮补证及未闭合清单。

| 编号 / Q 原文定位 | 第五轮状态与一句要点（源报告见本档对应节） |
|---|---|
| Q01（Q:L8，第1条） | **待裁定**：回收站清空授权，用户资产未动。 |
| Q02（Q:L9，第2条） | **待裁定**：ComfyUI 保留哪套，未指定不清理。 |
| Q03（Q:L10，第3条） | **待裁定**：旧副本须核无写者再决定清理，不借本轮授权。 |
| Q04（Q:L11，第4条） | **待裁定**：scratch/reports 去索引范围并 Q29；2496 为卫生报告口径，不沿用旧2453。 |
| Q05（Q:L14，第5条） | **阻断/待裁定**：B24 31 项未消解，不能笼统接受33 unknown；并 Q28/Q31/Q36。 |
| Q06（Q:L15，第6条） | **待裁定**：F16 根因未知，继续分析或仅披露，路线并 Q27。 |
| Q07（Q:L16，第7条） | **待裁定**：身份恢复绿但排他性敏感性证据债未闭，有限人测是否接受须明批。 |
| Q08（Q:L17，第8条） | **局部已闭合**：性能夹具完整预算验敏已闭；不证明产品无性能回归，也不修复独立断连。 |
| Q09（Q:L20，第9条） | **待裁定**：B31 7/7 已闭，B02/B08/B28/debug 范围仍保留；不重问既定先人测后通知全量顺序。 |
| Q10（Q:L21，第10条） | **阻断/待裁定**：A9 政策已定，实现缺零副作用 forecast 支持域/扩权；B02/B08 建议乙。 |
| Q11（Q:L26，第11条） | **未验/阻断**：新包正式命令链/静态读回已验，最终 GUI/活局保存恢复/跨网多机仍未验；旧包启动不能追认当前冻结。 |
| Q12（Q:L27，第12条） | **部分已闭合/未验**：归档类名隔离已有历史证据；修复前绿不可追认，最终同冻结仍须重跑。 |
| Q13（Q:L30，第13条） | **阻断/待裁定**：G01/G04 新反例/投入按 Q25/Q26；不是只让证据更弱的无安全影响选项。 |
| Q14（Q:L34，第14条） | **待裁定**：D4 规则事实撤销/savepoint 未闭，不能借 D1/D5 绿替代。 |
| Q15（Q:L35，第15条） | **局部已闭合**：D1 延迟链已有后续绿，旧“待接线”被取代；`E:/scratch/payment-d1-implementation/report.md`。 |
| Q16（Q:L36，第16条） | **局部已闭合**：启动预算夹具已修，不按旧待派单再问；`E:/scratch/server-sim-budget-fixture-fix/report.md`。 |
| Q17（Q:L22，第17条） | **待裁定**：A9 两诊断入口迁到 Move，保留 lower 层对照、不删断言。 |
| Q18（Q:L23，第18条） | **待裁定**：RuleAttempt 档位/支持域未批，隔离 forecast 与活体 savepoint 分开验。 |
| Q19（Q:L39，第19条） | **待裁定**：backup 排除仍未落盘；已预演、推荐排，合并 Q34 裁定。 |
| Q20（Q:L40，第20条） | **待裁定**：client 服务配置裁剪仍未落盘；server/signaling 角色保留已预演，并 Q34。 |
| Q21（Q:L41，第21条） | **局部已闭合**：420→60→420 各62 CHECK、exit0/1/0已闭；旧60s RED不作现存预算欠账，断连另列。 |
| Q22（Q:L42，第22条） | **待裁定/未验**：OS 与 Viewport 证据分层，额外 OS 覆盖时段并 Q33；最终包最低交互仍必需。 |
| Q23（Q:L45，第23条） | **局部已闭合**：旧57处/B31原7只迁2已被收口取代：本批7/7、余52且无意外差集；不等于全仓完成。 |
| Q24（Q:L46，第24条） | **待裁定**：debug 真进 client/server 且单机 ~ 静态可达；处置并 Q30，未做真release按键验收。 |
| Q25（Q:L49，第25条） | **阻断/待裁定**：G01 精确允许/PCK/信令门未补，仍 BLOCK；补门有实质安全提升，风险例外未获准。 |
| Q26（Q:L50，第26条） | **阻断/待裁定**：G04 活局正例及底层证据消费未补；6–12h 与含最终双 EXE GUI 14–28h 不混算。 |
| Q27（Q:L51，第27条） | **待裁定**：原构建索符号/原EXE无符号分析/仅披露择路；新构建符号不能补原EXE。 |
| Q28（Q:L52，第28条） | **阻断/待裁定**：B24 31项无无条件放行子集，U033/U043条件豁免仍缺证；更新工时按 Q36。 |
| Q29（Q:L53，第29条） | **待裁定**：不动/1957生成物去索引/另含tests290，10原生构建物暂缓；不删实物、不提交。 |
| Q30（Q:L54，第30条） | **待裁定**：debug 推荐运行门禁（v2两处，全宿主四处），尚未实施；剔除/export过滤不可单用。 |
| Q31（Q:L57，第31条） | **阻断/待裁定**：22套现有测试整项消解0、静态20项未闭；需新探针或实现工作，分档预算已到 Q36。 |
| Q32（Q:L58，第32条） | **阻断/待裁定**：PLAN blocked_notrun；nextcandidate不是现成命令，精确门图按 Q41，不能只换一个SHA。 |
| Q33（Q:L59，第33条） | **待裁定/未验**：原两条OS输入独占桌面15–20分钟＋准备45–90分钟；26条UI缺口另按Q43估时/裁定；旧副本已失、32脚本漂移，当前四条OS链未验。 |
| Q34（Q:L60，第34条） | **待裁定**：三角色排除候选真导出已预演，生产一行未应用；runtime/GUI/联机仍未验。 |
| Q35（Q:L63，第35条） | **阻断/待裁定**：合法候选重新登记未做，最新为18契约4漂移而非两处，须按 Q41 审批闭包。 |
| Q36（Q:L64，第36条） | **待裁定**：B24 A类7项=43–75h/B类24项=117–203h/C类0项，总178–312h含共用；两豁免另6–12h，未开工/未增闭合数。 |
| Q37（Q:L65，第37条） | **待裁定**：known-limitations整份结构等值，不能直接增项；授权改quickstart重组或包外告示。 |
| Q38（Q:L66，第38条） | **历史局部已验**：旧包439项SHA全过、PID19692/exit0/4.7.2；280 json/log和侧车已持久留存，ZIP仍不自包含。 |
| Q39（Q:L67，第39条） | **未验/阻断**：round75三次9红/8红/59绿；跨套件开局握手不稳，负载相关仅假设，深层同根因未证。 |
| Q40（Q:L68，第40条） | **待裁定**：外部告示草稿已就绪但绑旧包；须获批、重绑新SHA并复核/移除过时B31项，措辞另裁定。 |
| Q41（Q:L69，第41条） | **阻断/待裁定**：18契约4漂移：当前两门与旧ERROR分类两漂移分开；worker两assert归属未闭、scheduler/adapter指纹缺口未补。 |
| Q42（Q:L70，第42条） | **待裁定**：新包 `8be554ca` 已生成/读回但仍 PARTIAL；发新包/继续只发旧包 `8f178f6a`/等 A9/B24 裁定后再出第三版，三选一尚未决定；旧版不含 B31 收口，文本重绑/送达未完成，旧包 GUI 证据不移植新包。`E:/scratch/package-reissue-b31/report.md`:L3–10,L18–39,L294–299；不以新包生成代替发布批准。 |
| Q43（Q:L71，第43条） | **待裁定/未验**：26 条 UI 缺口真窗口逐项估 90–136 分钟，含校准/收尾 99–146 分钟；用户选独占 2–2.5 小时全验/指定小批约 30–45 分钟/暂不验并披露。15–20 分钟仅 Q33 原两条 OS 输入范围；同桌面不能并行操作，未实现项/前置合同仍须先闭合，时长不是到点通过承诺，也不含完整对局时长。`E:/scratch/ui-gap-verification-plan/report.md`:L7–14,L34,L265–271,L288–298；方案不等运行证据。 |
| Q44（Q:L73，第44条；`docs/pending-user-questions.md:73`） | **本轮新增·未闭/待裁定**：当前同一字节冻结、两批 N=6：**合格低负载 12 轮：8 绿 / 3 次 `rename_error=1` / 1 次 `READY` 复合门；发布失败率约 25%；全轮 ERROR=0**；SCRIPT ERROR 亦全 0，`READY` 为 worker/成员/身份复合门失败，不计作发布失败。[发布8] 更早的小样本作历史保留、不并入 12 轮：低负载 N=3 首批三轮 worker 均 READY，2/3 红是 `rename_error=1` 会话目录发布失败、1/3 绿；不是该批启动超时。另批目标发布错误 0/3、整套 1/3 更早 READY 红，不证明消失；与历史 204 门仅同一错误签名但未证实同路径，本机系统错误/持有者绑定未闭。见“本轮新增：Windows 会话目录发布脆弱点”及[发布1][发布2][发布4]；不加重试、不放宽门。 |
| Q45（Q:L75，第45条；`docs/pending-user-questions.md:75`） | **本轮新增·未闭/待裁定**：Q45 登记外部嫌疑已逐一排除、持有者未抓；**持有者未观察到（RM 仅覆盖 9/204、长路径未覆盖）⇒ 未观察到≠已排除**。[发布8] 方向改按“产品脆弱点”讨论；单次目录 rename/无有界重试的静态结构与受控矩阵机制已证，≠ 本机归因已证。按脆弱点处理/继续只定位/先披露待裁定；本项需披露但本身不阻塞人测包，不构成添加生产重试授权，不解除其它既存阻断、不提升 NOTRUN/UNKNOWN，旧告示仍须重绑新包。见增补[发布2][发布3][发布6][发布7]。 |

本轮新增第 44–45 条映射；原第 1–43 条文字、顺序与历史结论未改。Q44/Q45 原文中的同路径/事件解释推断不得越过本档新增节的未证边界；本档不代用户批准处理方案。

## 冻结前必须重采样SHA的文件清单（本节不列哈希）
**未验·最终现场采样**：以下是必须点名的最小再采样/交接集合，不是假装完整最终闭包，也不表示旧UNKNOWN现已释放。必须在写者停止后重新按三角色选择器/descriptor/导入依赖展开完整清单，复制前后核路径集合与SHA；`.uid`/`.import`不能因“生成物”就跳过。仅mtime稳定不是锁源证明。

### 原停写报告白名单：逐路径保留
依据 `E:/scratch/writer-stop-convergence/report.md`:L532–590（原51项）；这些路径后来继续改过的，以新采样为准，不沿用旧SHA。
```text
assets/config/server.cfg
assets/config/signaling.json
assets/scenes/game_scene/battle_board_v2.tscn
assets/scenes/game_scene/tactical_board_ui.tscn
scripts/game_scene/battle_io/battle_host_lifecycle.gd
scripts/game_scene/battle_io/shared_view_sections.gd
scripts/game_scene/tactical_board_ui.gd
scripts/io/native_capability_view.gd
scripts/io/native_method_contract.gd
scripts/io/temporary_cleanup_native_delete.gd
scripts/match/view_builder.gd
scripts/match/view_mirror.gd
scripts/net/authority/match_authority.gd
scripts/net/identity/host_identity_request_codec.gd
scripts/net/identity/player_identity.gd
scripts/net/identity/resume_ack_transaction.gd
scripts/net/server/recovery_save_diagnostic.gd
scripts/net/server/server_admin_request_codec.gd
scripts/net/server/server_bootstrap.gd
scripts/net/server/server_cli.gd
scripts/net/server/server_console_channel.gd
scripts/net/server/server_data_approval.gd
scripts/net/server/server_deployment_validation.gd
scripts/net/server/server_gateway.gd
scripts/net/server/server_room_manager.gd
scripts/net/server/server_room_worker.gd
scripts/net/server/server_shutdown.gd
scripts/net/server/temporary_cleanup_executor.gd
scripts/net/server/temporary_cleanup_ledger.gd
scripts/net/server/temporary_cleanup_proof_collector.gd
scripts/net/session/authority_host_client.gd
scripts/net/session/host_content_inbox.gd
scripts/net/session/host_match_request_inbox.gd
scripts/net/session/host_room_inbox.gd
scripts/net/session/host_room_password_request.gd
scripts/net/session/lobby_session.gd
scripts/net/session/server_data_status_inbox.gd
scripts/net/ui/room_data_panel.gd
scripts/net/validation/room_data_validation_worker.gd
scripts/net/validation/room_validation_task.gd
scripts/system/global/fact_delivery.gd
scripts/system/global/game_log.gd
scripts/system/global/game_progress.gd
scripts/system/global/load_game.gd
scripts/system/global/situation_resolver.gd
scripts/system/global/time_point_checker.gd
scripts/system/operations/EditMagic.gd
scripts/system/operations/PayMagic.gd
scripts/system/operations/PlayAttack.gd
scripts/system/operations/PlaySkill.gd
scripts/system/regular_play.gd
```

### 旧runtime UNKNOWN/开放写权与后续批次补入（与上组去重）
依据停写报告:L20,L332–346,L348–530；注册表各批报告目标路径、A7新增原语及T18后续回执。**未验**：路径写权/当前存在性与最终是否入选须现场核定，不因被列在此处自动放行。
```text
assets/scenes/main_menu/opening_background.tscn
assets/shaders/portal_dolly.gdshader
assets/videos/main_menu/ae_opening_transition_v04.ogv
assets/videos/main_menu/ae_opening_transition_v04.ogv.uid
scripts/game_scene/battle_board_v2.gd
scripts/game_scene/battle_io/battle_host_lifecycle.gd.uid
scripts/game_scene/battle_io/shared_view_sections.gd.uid
scripts/io/native_capability_view.gd.uid
scripts/io/native_method_contract.gd.uid
scripts/io/temporary_cleanup_native_delete.gd.uid
scripts/main_menu/opening_warp.gd
scripts/match/match_commands.gd
scripts/net/identity/client_identity_inbox.gd.uid
scripts/net/identity/host_identity_request_codec.gd.uid
scripts/net/identity/resume_ack_transaction.gd.uid
scripts/net/server/heartbeat_publication_policy.gd.uid
scripts/net/server/recovery_save_diagnostic.gd.uid
scripts/net/server/server_admin_request_codec.gd.uid
scripts/net/server/server_deployment_validation.gd.uid
scripts/net/server/temporary_cleanup_executor.gd.uid
scripts/net/server/temporary_cleanup_ledger.gd.uid
scripts/net/server/temporary_cleanup_policy.gd.uid
scripts/net/server/temporary_cleanup_proof_collector.gd.uid
scripts/net/session/client_match_inbox.gd.uid
scripts/net/session/host_content_inbox.gd.uid
scripts/net/session/host_guard_inbox.gd.uid
scripts/net/session/host_match_request_inbox.gd.uid
scripts/net/session/host_room_inbox.gd.uid
scripts/net/session/host_room_password_request.gd.uid
scripts/net/session/server_data_status_inbox.gd.uid
scripts/net/ui/notification_inbox.gd.uid
scripts/net/ui/v2_view_presenter.gd
scripts/net/validation/room_data_preparation.gd
scripts/net/validation/rule_random_simulation.gd
scripts/system/ai/temp/dummy_bot.gd
scripts/system/buffs/defeat_buff.gd
scripts/system/deploy_rules.gd
scripts/system/global/all_operations.gd
scripts/system/global/battle_resolver.gd
scripts/system/global/climax_resolver.gd
scripts/system/global/effect_manager.gd
scripts/system/global/event_resolver.gd
scripts/system/global/master_manager.gd
scripts/system/operation_router.gd
scripts/system/operation_router.gd.uid
scripts/system/operations/ActivateEffect.gd
scripts/system/operations/AddAttack.gd
scripts/system/operations/AddEventFromDeck.gd
scripts/system/operations/AddSkill.gd
scripts/system/operations/ApplyCardKeywords.gd
scripts/system/operations/AskPlayerNumber.gd
scripts/system/operations/AskPlayersSecretOption.gd
scripts/system/operations/AwakenSkill.gd
scripts/system/operations/CloseCard.gd
scripts/system/operations/Deploy.gd
scripts/system/operations/DiscardPlayedCards.gd
scripts/system/operations/HideTrueName.gd
scripts/system/operations/ModifyAttackPowerByAttribute.gd
scripts/system/operations/Move.gd
scripts/system/operations/MoveLocation.gd
scripts/system/operations/PayMagic.gd.uid
scripts/system/operations/RecordLog.gd
scripts/system/operations/RefillHand.gd
scripts/system/operations/ReleaseTrueName.gd
scripts/system/operations/ZeroAttributePower.gd
```

### 发行工具/配置/声明/说明锁：单列，不冒充runtime停写门
依据 `E:/scratch/packaging-runbook/report.md` C0–C7、`E:/scratch/export-rehearsal/report.md`、`E:/scratch/client-startup-receipt/report.md`及R/H；隐私/模板/配置裁剪若获批准后修改，也必须重采。
```text
project.godot
export_presets.cfg
icon.svg
icon.svg.import
release_contract.json
addons/fate_server_signals/fate_server_signals.gdextension
addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll
addons/webrtc_native/webrtc_native.gdextension
addons/webrtc_native/lib/libwebrtc_native.windows.template_release.x86_64.dll
release/human-test/START-CLIENT.cmd
release/human-test/START-SERVER.cmd
release/human-test/START-SIGNALING.cmd
release/human-test/Launch-HumanTest.ps1
docs/.gdignore
reports/.gdignore
newtests/join_shape_session_wiring_evidence/.gdignore
docs/human-test-quickstart.md
tools/release/freeze_prepare.py
tools/release/round56_three_role_freeze.py
tools/release/release_contract.py
tools/release/signaling_prepare.py
tools/release/package_audit.py
tools/release/role_privacy_audit.py
tools/release/release_privacy_policy.json
tools/release/human_test_candidate.py
tools/diagnostics/round53_exported_runtime.py
tools/tests/round52_current_role_candidates.py
tools/copy_data_after_export.py
tools/check_layer_deps.py
tools/classify_player_data_calls.py
tools/tests/test_round29_integrated_evidence.py
tools/tests/regression_parallel_scheduler.py
tools/tests/regression_parallel_smoke.py
```

### 第四轮改动或关键补证夹具锁：只绑定证据，不复制入发行包
依据T的对应修复/探针条目及注册表表内报告。**未验**：最终专项须绑定这些脚本、实际场景及递归依赖的现场SHA；下列点名脚本不替代完整测试依赖清单，被Git忽略也不能漏采。
```text
newtests/magic_overdraft_declaration_test.gd
newtests/round75_lan_once_test.gd
tests/net_server_gateway_restart_test.gd
tests/server_simulation_default_budget_test.gd
tests/room_data_preparation_consumer_test.gd
tests/net_server_match_test.gd
tests/round36_gateway_fixture.gd
tests/residue_pile_test.gd
newtests/empty_timepoint_dispatch_test.gd
newtests/b06_initial_card_registration_probe.gd
newtests/add_attack_true_name_order_test.gd
newtests/play_skill_keyword_behavior_test.gd
newtests/registry_b21_place_probe.gd
newtests/registry_b21_unregister_probe.gd
newtests/registry_b22_situation_magic_probe.gd
newtests/b23_scout_score_probe.gd
newtests/registry_b26_match_commands_probe.gd
newtests/play_attack_keyword_behavior_test.gd
newtests/round_tail_location_benefit_probe.gd
newtests/round_start_refill_hand_probe.gd
newtests/regular_play_registry_query_test.gd
newtests/b31_round_tail_probe_fixture.gd
newtests/round_tail_discard_played_cards_probe.gd
newtests/round_tail_discard_played_cards_probe.tscn
newtests/round_tail_sync_power_probe.gd
newtests/round_tail_sync_power_probe.tscn
newtests/b31_round_tail_change_order_probe.gd
newtests/b31_round_tail_change_order_probe.tscn
newtests/b31_order_number_observer.gd
newtests/run_b31_change_order_probe.py
tests/match_view_test.gd
```

新增锁项依据 `E:/scratch/registry-b31-final-remainder/report.md`:L107–119、`E:/scratch/registry-b31-changeorder-probe/report.md`、`E:/scratch/regression-contract-map/report.md`:L54–90,L187；回归scheduler/adapter这里只是**要求现场采样**，并未补进执行器指纹名单。相关 `.tscn`/共享夹具/递归依赖与实际选集仍须展开，不把点名表当完整闭包。

### 外部引擎/导出模板/信令runner前置锁（只读核SHA，不修改宿主）
依据 `E:/scratch/packaging-runbook/report.md`:L63–85；同时核隔离APPDATA下对应模板副本与来源一致，不能拿模板原路径存在替代导出进程可见性。
```text
D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe
D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe
C:/Users/Administrator/AppData/Roaming/Godot/export_templates/4.7.2.stable/windows_debug_x86_64.exe
C:/Users/Administrator/AppData/Roaming/Godot/export_templates/4.7.2.stable/windows_debug_x86_64_console.exe
C:/Users/Administrator/AppData/Roaming/Godot/export_templates/4.7.2.stable/windows_release_x86_64.exe
C:/Users/Administrator/AppData/Roaming/Godot/export_templates/4.7.2.stable/windows_release_x86_64_console.exe
E:/FateCandidates/round53-signaling-runtime-entry-sa1/diagnostic-tools/runner.exe
```

## 下一步动作队列（未验工作；谁做、依赖什么）
| 动作/责任人 | 前置依赖 | 完成判据/不能越过的边界 |
|---|---|---|
| 主代理：收集裁定并确认唯一写者 | Q第1–43条逐项状态见快照；重点Q10/Q18/Q25/Q26/Q28/Q30/Q31/Q36/Q37/Q39/Q40/Q41/Q42/Q43；保留前端冻结 | 书面范围/风险例外/精确写权释放；已闭合登记不重问，不把暂按接受/草稿/预演当授权；资产清理及卫生独立另案 |
| 注册表整合者：归档B31终态并锁定新包输入（本批迁移已完成） | `registry-b31-final-remainder/report.md` 7/7、最终SHA、800 CHECK及逐站验敏 | 不再派“余五站待迁”；收新包readback证明包含最终字节；B02/B08/B28/debug仍独立，不冲销其它批次弱敏感性 |
| A9唯一写者：按建议乙联合B02/B08 | 支持域/扩权/诊断入口获批，统一原语接口写者先交接 | 同冻结证明无活体副作用forecast、先付后移、拒绝无代价/残留与注册路由，免费效果移动不变 |
| 发行工具唯一写者：G01/G04 | 用户选范围；批准allow集/信令布局；G04可启动的同冻结包 | 真反例拒绝+真实正例+底层proof消费；G04源码客户端不升级最终GUI；缺批准保持BLOCK |
| 前端唯一写者：debug门禁（若获批） | Q30解除相应行为/文件冻结，独占窗口 | 真release快捷键/API拒绝、debug/editor保留、关闭安全与正常交互回归；资源仍在包须如实标 |
| 语义审计/规则写者：B24分组消解 | Q28风险政策、缺失主体/no-op及同局生命周期契约 | 先共同费用/主体来源，再跨等待/同ID复用；条件豁免绑定最终数据/debug范围，未验不改绿 |
| LAN诊断者：跨套件开局握手最小实验；F16诊断者独立定位 | round75构造已落盘；Q39实验/风险授权，Q27恢复分析择路；原冻结与日志可复放 | 低负载N≥3记录全部样本、负载/断连时点，不绿重试，不预先认负载因果/加宽门；F16同根因未证 |
| 主代理/整合者：重新停写、闭包锁及必要专项 | 所选生产/工具变更已交接，现场空间/全局类缓存核验 | 重采完整源/资源/工具/证据SHA，不用旧停写人数或混冻结绿；性能完整预算验敏不重复补债 |
| 封包/交付负责人：新包证据归档、随包文案重绑（生成/读回已完成） | 新UUID00fcde316be244728ba0e91c29ee1c73、新SHA8be554ca…及四段原回执已到；风险/发布选择仍待批准 | 原8f178f6a保留历史不删除；告示/指南/DELIVERY按获批范围重绑，逐项清过时B31缺口并读回；不把新包生成当G01/G04或有限人测发布批准。统一PS1端到端尚无执行证据 |
| 交付负责人：只交获准的有限真人测试候选 | 当前同源验收及风险清单齐全；用户实际测试 | 不签未取得sourcePASS/releasePASS/ready；用户真人测试后明确通知才全量；恢复/跨网等未验继续列出 |
| 卫生执行者（独立另案） | Q29授权、证据留存/消费者签字、最新索引与SHA清单 | 只去批准索引集合，不删文件、不改ignore、不提交；根tests范围不得从scratch/reports审批推定 |
