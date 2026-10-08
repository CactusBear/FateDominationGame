# net-batch-40 定向验收缺口

## 结论与边界

- 只对照 `docs/package-real-test-checklist.md`（下称 PK）与 `docs/real-world-multiplayer-test-plan.md`（下称 RW），定位相关生产入口与现存套件；未做泛审计，未审计已取消的 host-reregister。
- 本轮不启动 Godot/发行程序，不发送真实信号，不读取凭据，不改生产或测试源文件。只运行静态/mock 自测并写本目录。
- LAN 70/0、P2P 82/0、自动信令 383/0 是委派上下文已确认成果，本轮不重复背书，也不外推到真人、正式包、Linux 信号或公网。
- 剩余重点：**日志共享脱敏闸尚无专项闭环；公共视图代码已有收紧但专项/真人证据不足；Linux 完整中局信号矩阵仍待真实包执行，且静态夹具目前有两处测试失配。**
- 两份 v5 文档中的“所有 NOT_RUN/未导出”是其历史编写状态，不应据此否定后续已过专项。反过来，后续专项通过也不能自动把 RW01–24 改为 PASS。

## A. 日志脱敏闸：现在可定位，运行验收须另行授权

对应 PK 82、126、145–149；RW 45–48、RW03/05/12/18/19/24。

### 当前精确事实

1. `scripts/net/server/server_console.gd:47–53`：本机命令响应文件被完整打印为 `CONSOLE_RESULT`，不是字段白名单摘要。
2. `scripts/net/server/server_console_channel.gd:90–102`：`players` 复制每条注册记录并附 `record.identity=id`；`whitelist list` 复用该结果。可信本机私有管理响应可含身份标识，但将其 stdout 当普通日志分享会越过 PK149 的公开边界。这里是**共享/输出闸缺口，不宣称已经发生公共网络泄露**；本轮未读取任何注册记录。
3. 同文件 87 行只打印命令名和 ok，与完整响应打印不是同一安全等级；网关 `server_gateway.gd:178` 打印 manager.error，420 行打印诊断。需要实际失败载荷及错误字段白名单证据，不能只扫关键词认定安全。
4. `tests/identity_inheritance_test.gd:53,77–79,93–96` 覆盖继承审计无新密钥、候选标签白名单及隐藏字段拒绝；`tests/audit_commit_test.gd` 覆盖 append/flush 故障、保存/恢复/关闭成功闸。**审计提交闸不等于日志脱敏闸**，不沿用旧 batch-32 报告把这两项混为“均未实现”。

### 精确套件与缺口

| 现存套件（tests/<名>_test.tscn） | 能补的证据 | 不能替代的证据 |
|---|---|---|
| identity_inheritance | 候选公开标签与授权审计字段限制、错误密钥先拒绝 | CLI stdout、其他错误路径、截图共享脱敏 |
| net_server_console_channel | 真实控制通道、实例绑定、命令状态 | 没有覆盖 players/whitelist 的最终打印脱敏 |
| net_identity_admin_window | 实际管理员 UI 回执入口 | 必须另核 UI 标签和截图是否含身份标识 |
| audit_commit | 审计 append/flush 失败阻止权威/管理成功；需 `-- <隔离绝对输出目录>` | 不证明密码/票据/SDP/ICE 无输出 |

**缺专用日志红/绿套件**：在隔离、合成非真实秘密的测试环境分别向 players/whitelist、创建失败、管理 save/close、恢复拒绝、继承、信令错误注入可识别标记；同时捕获 stdout/stderr/engine/管理 UI 文案，断言密码、私钥、token、fingerprint、公钥、SDP/ICE、隐藏牌标记和完整身份记录不进入公开材料；合法 room/instance/request/状态码仍可追踪。修复前红、修复后绿，不能只检查一个 `_players()` 返回对象。

**共享放行前仍缺**：日志白名单文件索引、原件本机受限存储声明、脱敏副本哈希、逐字段脱敏记录与人工签名；截图/录屏同样检查。不提供“打包整个 user 目录”的收集捷径。

## B. 公共视图隐私：已有约束，不能用手牌过滤代表全链路

对应 PK136、149；RW08、11、12，以及 RW03/18 的身份标签。

### 已核代码（静态，不是运行通过）

- `scripts/match/view_builder.gd:109–135`：公共日志事件白名单；跳过 secret_choice；重建有限事实字段并去掉原 object，play 不带牌对象。
- 同文件 153–178：隐藏牌不带专属卡背路径；公开卡不带自身私有效果 ID；165 行非 own 走 public_description。
- 同文件 186–204：按来源链判定未解放从者，移到出牌/弃牌区不因此公开；未知从者来源失败关闭。
- 同文件 206–234：公共说明读声明文案，不回退内部效果诊断名。

### 精确最小回归组

| 套件 | 当前断言覆盖 | 残余证据 |
|---|---|---|
| match_view | 所有 observer、隐藏手牌/未解放从者、隐藏 name/image、非法镜像字段拒绝 | 未显式断言专属 back_image、公共 description/log 标记及跨牌区来源链 |
| net_selection | 公共选人无 servant/class，观战仅完成提示 | RW08 随机模式真人 H/G/S 同刻公开与私有画面 |
| net_lobby | ENet 过滤、进行中观战无手牌/私有待答 | RW12 头像/悬浮说明/日志/抽屉/缓存全链路 |
| net_cards + net_pending | 选择候选仅给所属玩家、待答授权 | RW11 目标玩家亲自点两分支并证明仅续行一次 |
| net_formal_entry_window | 正式 v2 观战公共视图、禁止规则输入、真实 Escape/Resume | 其夹具直接初始化规则/playing，不是默认主菜单真人建房全过程 |
| net_process_full_game | 独立客机未运行规则，全局手牌过滤，正式 v2 多帧渲染 | 需按外部 host/join 配对启动；单独无参数会 checks=0；不覆盖所有隐藏字段 |

补专项必须包含：隐藏专属卡背/目录名、未解放从者技能与其 BUFF 跨到出牌/弃牌区、公共说明内部效果名、secret_choice/play/异常日志、从公开回到隐藏、公开后的正常更新；对 G/S/X 的完整网络包和实际 UI 文案递归检查合成标记。私有 own 视图应保留合法内容作为正例。

真人剩余执行：RW08 随机选人 → RW11 双答复分支 → RW12 观战逐入口/中途加入/公开更新。保留同刻 H/G/S 画面、公开包/日志、动作前后顺位资源归属；隐藏私有画面仅受限本机保存。缺这些不得填真人 PASS。

## C. Linux 完整信号：矩阵、启动前置与真实缺口

对应 PK57–61、70、133、140、150；RW23–24。

### 现存正式夹具

`tests/run_server_signal_acceptance.py` 驱动 `tests/net_server_signal_window_test.tscn`，Linux 仅接受 `--release` 与 `--signal int|term`。窗口段由驱动附 `-- window`；GDScript 46–55 行明确要求双客户端至少到第2回合、正式 v2 真窗口，前置失败不发送信号。

四个分支须独立 run_id：

| Linux 信号 | 分支 | 必需证据 |
|---|---|---|
| SIGINT | 录制成功 | request→信号 consumed→保存 complete；实际 engine exit=0、所有绑定 worker 已退出；日志完整可恢复且 state_hash 等于末条 after |
| SIGTERM | 录制成功 | 同上，不能拿 SIGINT 或 Windows CtrlBreak 替代 |
| SIGINT | `--reject` 未录制 | 明确 SERVER_STOP_FAILED/未启用录制，无 COMPLETE；engine/worker 均仍存活，ready 保留，原局后续 seq 真推进 |
| SIGTERM | `--reject` 未录制 | 同上，独立原局继续操作证据 |

后续获授权可使用（示例，占位必须替换为冻结包/隔离路径，**本轮未执行**）：

```bash
PYTHONDONTWRITEBYTECODE=1 python tests/run_server_signal_acceptance.py --platform linux --release --distro FateLinux --signal int --project <隔离源码项目> --godot <实际Windows控制台引擎> --linux-exe <冻结Linux发行exe的Linux路径> --output-root <新的Windows可见隔离run根>
# 另起运行分别改 --signal term；两种信号再各另起一次并加 --reject。
```

每分支收集 `summary.json`、`signal-request.json`、`signal-result.json`、`process-evidence.json`、`finally-process.json`、engine.log/server-stdout.log/client.log，以及各 worker 实例日志、ready/config 的脱敏绑定字段、存档哈希与末态恢复对照。launcher 返回值不能代替 pidfd/实际 engine 状态。

### 已证实夹具/适用边界

- 本轮真实执行 `tests/server_signal_fixture_static_test.py`：**10项，8通过、1失败、1错误，退出码1**。证据为本目录 `signal-static-test.log` / `signal-static-result.json`，仅静态/mock，无真实 Godot/信号。
- 失败：静态测试100行还要求旧字符串 `verify_linux_target(args, pid`；现驱动已改用 `LinuxOwner`/pidfd，需更新断言为实际 ownership 契约，不应退回裸 PID。
- 错误：mock `Exited`（111–114行）缺 `returncode`，驱动 finally 288行读取它，遮住原启动失败异常；需补完整 Popen mock 再验证失败产物。不能把这两个自测问题认定 Linux 生产信号实现坏了。
- 驱动119行显式 `identity_registry=""`：这是不认证信号夹具，不覆盖 PK81“默认保持认证开启”、RW认证恢复/继承分支。不能以信号通过宣布发布安全配置已验收。
- 驱动114–116行将 Linux storage_root 重设为 output-root 的 WSL 转换路径；`--linux-storage-base` 实际被覆盖，`--linux-output-base` 当前无消费者。把输出根放 E: 会形成 /mnt/e 热点，不满足 PK70 原生文件系统推荐；必须先明确本机 Linux 存储与 Windows证据可见映射，不能只加参数就声称换成原生目录。
- batch-38 `linux-worker/findings.md` 只证明曾到缓存写入、41块已发布而未见 ready；首要前置是现冻结包 worker 能从 spawn 到 ready、候选数据 prepare→ready→commit→applied、窗口达到中局。该历史快照不是本轮 Linux 信号通过，不能凭 banner 判死锁，也不能统一加大 timeout。
- 最小启动诊断套件：`net_server_linux_create_test.tscn`、`net_server_linux_preflight_test.tscn`（后者开启1秒随机模拟，与信号夹具关闭模拟不同）。先读继承基类的外部服务启动契约再执行，不孤立起客户端场景冒充 Linux 包运行。
- 两个 `--reject` 只覆盖未录制拒绝；PK140/RW24 还需真实隔离存储写失败及关闭超时分支。相关现存 `net_server_shutdown_failure_test.tscn` 要显式设置 `HERMES_SHUTDOWN_TEST_ROOT`，但 Windows/其他平台专项结果不能外推 Linux系统信号故障路径。

## D. 其他剩余可执行验收（不扩审计）

| 剩余项/文档映射 | 精确套件或入口 | 尚缺结果/放行前置 |
|---|---|---|
| 冻结、实际交包 PK7–11/84–96 | `scratch/package-preflight-v5/preflight.py`；`net_server_export_test`、`net_server_export_create_test`、`net_server_export_identity_test`、`net_server_export_reload_test` | 主代理冻结后预检、导出授权、当前 release_id 三类正式包、PCK实际内容/库/外置数据逐文件哈希、真实模板/引擎/ldd、清单与 SHA256SUMS；本轮不运行预检以免覆盖别人的产物 |
| 配置/不同cwd/console PK71–82/130–133 | `net_server_cfg_test`、`net_server_roles_test`、`net_server_console_channel_test`；正式包首次启动与 stdin 真人步骤 | 首次只生成退出无监听、已有配置不覆盖、坏配置失败；Windows wrapper stdin 等待仍响应、输入端退出网关存活；Linux console独立PID；认证默认配置不能由 identity_registry空夹具替代 |
| 数据批准/同步 RW06–07/PK135 | `net_server_data_approval_test`、`net_server_data_approval_window_test`、`net_data_barrier_window_test`、`net_data_selection_window_test` | 真人明确选择冲突来源、逐字节哈希/批准修订、缓存命中及清理、未批准不能开始；同名牌图来自房间数据 |
| 真人基础 RW01–10 | `tests/real_world_acceptance_v5/prepare.ps1` → 输出 launch.ps1 → 默认H菜单入口 | 四独立身份/用户目录、真实鼠标键盘/同期录屏、每用例每分支签名；prepare不启动引擎且不等于真人通过 |
| 掉线/崩溃/恢复 RW13–19 | `net_resume_identity_test`、`net_p2p_resume_identity_test`、`net_server_recovery_midmatch_test`、`net_server_resume_identity_test`、`identity_inheritance_test`；既有LAN/P2P核心成果不重复跑 | 正式包真人区分同进程重连/重启/权威崩溃/原局恢复，全部原认证真人过屏障才playing；受控负测夹具无凭据读取；无条件者 BLOCKED |
| 预算/回退 RW20–22 | `net_runtime_guard_test`、`net_runtime_guard_window_test`、`acceptance_root_transaction_test` | 安全异常夹具、真窗口响应、完整发动前/部分执行/回退后三态、重开/大厅分支与保留预算；没有完整检查点不能伪称跳过 |
| 保存正常/失败 RW23–24 | `net_server_console_save_test`、`net_server_console_close_test`、`audit_commit_test`、`net_server_shutdown_failure_test` | 实际包保存成功再关闭、原档哈希/恢复继续操作、隔离ACL失败且还原，失败保留现场 |
| 跨公网 PK134/150（RW本身只回环） | `tests/validate_p2p_public_evidence.py <现场report.json>` | 两异地网络+独立信令机、实际 authority PID在房主、selected candidate非relay、无TURN/客机无规则、信令关闭后双向业务继续、relay_game_bytes=0及四角色日志/流量取证；验证器只验完整性/哈希，不能认证现场事实 |

**已纠正文档过时阻断**：当前 `export_presets.cfg:132,153` 两服务端预设均包含 `scratch/*`，且根 `scratch/.gdignore` 存在。PK40 的旧“未排除 scratch”不能继续当当前源码阻断；仍需实际PCK核验，不能据此宣称正式包已交付。

## E. 执行次序与验收记账

1. 本轮可执行且已执行：只读入口核对、静态/mock 自测、保存证据；自测红项保持可见。
2. 需生产/测试修改授权：统一日志公开投影与专项红/绿、补公共视图标记覆盖、修正信号静态夹具及路径适用问题；不由本只读子代理实施。
3. 需引擎/发行程序授权：冻结包 worker ready与Linux预检 → 四信号分支 → 失败/超时路径 → 正式包配置/控制台/数据/恢复专项。
4. 需真人/多机：RW真实窗口逐项签名、Linux完整信号/包交付、跨公网。已过核心局部不应反复扩种子代替这些缺口。
5. 每套记录实际 command、cwd、源码/包/库/数据哈希、平台、配置脱敏摘要、独立run_id、RESULT/checks、进程退出码、SCRIPT ERROR/原生错误、截图人工复核。0 checks 或无窗口段不能 PASS；所有未执行为 NOT_RUN，前置确实缺失为 BLOCKED，不把文档步骤当实测证据。

文件：仅本目录报告与2份静态自测证据；生产/测试源文件未改。静态/mock自测临时目录在 Hermes TMPDIR内，由夹具自动清理。
