# 权威工作进程交接

## 已落盘生产文件
- scripts/net/server_room_manager.gd：本机 OS.create_process 的 lan/p2p/dedicated 明确模式；每次启动随机 instance_id；ready 与 PID/实例/部署模式核对；恢复/停止提供预期 PID+实例比较；每实例日志；异常退出保留 rooms 登记与目录；恢复前删除旧 ready；去除网关 poll 中完整引擎日志扫描。
- scripts/net/server_room_worker.gd：保留 protect_worker、disable、身份 required 接线和既有恢复等待；ready 增加 room_id、instance_id、authority_host_mode 和能力字段；主管心跳绑定 PID+实例；退出仅清理自身报告；正确校验 int/float 整数端口。复用事务代理新 MatchJournal.audit_event/begin_audit/end_audit：未启用对局录制时使用房间目录 transactions.<instance_id>.log；启用录制时让既有 MatchReplay 管理 transactions.log，不冲突占用写入器。能力区分接口、当下可回滚、审计持久化策略，不把重启/杀进程称回滚。
- scripts/net/server_bootstrap.gd：新增 --server-signaling --config 的纯信令职责入口，roles 必须仅 relay；仅动态装载 p2p_signal_server 和原生信号适配器，无 gateway/session/规则 authority 实例。
- tests/authority_worker_lifecycle_contract_test.gd/.tscn：就绪字段、三种部署模式、PID 复用/旧实例、损坏端口、过期恢复/停止的真实 GDScript 专项。尚未运行 Godot。
- server_process_signals.gd 未修改。

## 交付补丁
- production.patch：以上 owned 生产文件及专项的**累计 HEAD diff**，含接手时已存在的身份/原生信号改动（保留，不应当再覆盖）。已执行 git apply --reverse --check，能与当前落盘内容对账。
- gateway-required.patch：尚未写生产网关；为 pending、route、创建者生命周期分别记录 PID+instance_id；恢复/停止显式传旧实例；保留 pending 的原字符串类型兼容控制台读方；实际身份认证接线不变。已执行 git apply --check，可应用于生成时当前网关。server_gateway.merge_candidate.gd 是静态解析通过的合并参考，主代理应合并 patch 而非整文件覆盖其他代理后续工作。

## 真正无规则的独立信令项目
游戏原 project.godot 有 EffectManager 等 autoload，单加命令行 flag 并不能声称“不加载规则”。已在 signaling-project/ 暂存独立无 autoload 项目（仅 9 项脚本/场景/信号扩展文件及 relay.json）；stage_signaling_project.py 可重新生成，并检查显式 load/preload 依赖闭包不含规则文件。该快照未启动，主项目配置未改。只有使用这个独立项目/对应导出才能满足“不加载规则”，不要拿原游戏项目的 --server-signaling 当此项已验收。此精简职责入口不提供原控制台/状态文件管理功能。

## 验证（未启动 Godot）
- python scratch/authority-worker-v2/static_contract_check.py：12 个静态接线检查全部通过。
- gdtoolkit parser：manager、worker、bootstrap、signals、GDScript 专项、scratch 网关候选共 6 文件解析通过。
- git diff --check（manager/worker）通过。
- 静态 ready 实例绑定断言做内存变异，确实 EXPECTED_RED；无落盘临时破坏。
- stage_signaling_project.py：SIGNALING_PROJECT_STAGED files=9 gameplay_autoload=0 rules_authority_scripts=0；没有进程启动/凭证/commit。

## 主代理必须继续接入/验收的边界
1. LAN/P2P 的 UI/传输 host 入口不归本代理：必须在**房主本机**创建 manager，设置 authority_host_mode=lan/p2p，并通过本机回环路由访问 worker；现有直接 session.host/host_peer 调用不会因本批 manager 字段而自动变为子进程。不要把该接线称本批已完成。
2. 合并 gateway-required.patch 后再验证原成员重连和崩溃路由保留；子进程恢复后仍由既有 lobby_session/worker 的 restoring 流程恢复对局。
3. 本批复用的 MatchJournal 审计 API 来自事务代理同期改动；必须与该代理文件一起交付，并检查多局/恢复下审计写入器生命周期。
4. 同期 server_policy_config 的 transaction_log 声明尚非 worker 配置开关：本批始终保存事务审计，不允许把策略字段写入当执行链已接线；若主代理需实现禁用策略，应与事务核心约定审计写入器接口后统一处理。
5. recover_room/stop_room 的可选参数保留本机旧调用兼容；所有跨权限边界调用必须显式带 PID+实例（网关补丁已给出）。不要向客户端暴露不带实例的旧入口。
6. 旧 config 缺少 authority_host_mode/instance_id 时 discover_rooms 失败关闭且保留目录，需要管理员迁移，不会自动猜测旧实例。运行时测试与独立信令导出验收交主代理串行执行。
