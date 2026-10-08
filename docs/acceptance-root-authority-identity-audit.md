# 完整根事务、权威机器、身份继承与审计专项验收

## 交付状态与限制

本轮只新增 `tests/acceptance_*` 六个夹具文件与本报告。未修改生产文件、未运行 Godot、未操作真实凭据、未 commit。现有工作树有其他代理写入，以下源码结论是读取时快照，不是最终冻结版本结论。

已执行：`uv tool run --from gdtoolkit gdparse tests/acceptance_root_transaction_test.gd tests/acceptance_audit_chain_test.gd tests/acceptance_identity_state_test.gd`，退出码 0，无输出。这里只证明 GDScript 语法解析，不证明 Godot 类型检查、自动加载、测试行为或窗口接线通过。运行结论全部保留待验，不虚构红/绿 RESULT。

`tests/` 为忽略目录中的交付，必须按真实路径转交，不能仅依赖 `git diff`。测试引用已存在 API；缺乏安全入口的验收只描述 seam，不调用想象出的接口。

## 红反例 → 绿预期与源码

| 领域 | 红反例（错误实现应被抓到） | 绿预期 | 证据/缺口 |
|---|---|---|---|
| 完整根事务 | 父效果已扣资源/移牌/耗随机，另一个玩家答复引发子效果暂停；仅撤销子效果、清剩余函数 | 父子同属根事务，资源、牌区身份/牌序、随机、规则事实、待答与暂停队列回到根发动前；外部尾部恰好一次 | 新 `acceptance_root_transaction_test`，复用 `rule_guard_chain_rollback_test` 的真实 `activation_pool/run_pipeline/submit_active_choice` |
| 日志序号 | 重写第二帧序号并重新计算合法 SHA | 具体索引处拒绝，不把哈希正确当作序号正确 | 新 `acceptance_audit_chain_test` |
| 日志链 | 每帧各自哈希正确，但第二帧没有承接前链 | `error_index=1` 校验失败 | 同上 |
| 日志恢复 | 尾帧少一字节后直接续写 | 完整前缀可读，`truncated=true`，原件不可续写；正常续写沿用原序号与链头 | 同上 |
| 写盘失败 | 句柄已关闭还报告 append/flush 成功 | 返回失败、序号链头不推进、磁盘字节不变 | 同上；**不是磁盘满/flush 失败注入** |
| 身份旧档 | 无绑定旧档在认证模式下，首个持票者认领 | 失败关闭、禁止自动推断/补映射 | 新 `acceptance_identity_state_test` 结构反例；真实加载入口由已有 `net_member_identity_binding_test` 覆盖 |
| 密钥不匹配 | B 已获准且持 A 有效票据，自报 A 网关身份 | 网关覆盖自报值，房间再次验证认证 B 与原 A 绑定；拒绝不改修订与票据 | 已有 `net_member_identity_binding_test` 105–119、135–165；本轮未运行也未生成密钥 |
| 指定继承标签 | 自报标签、同昵称或已获准账号直接继承原玩家/房主 | 由当前房主显式指定受让已认证身份和可继承标签，权威再验证；管理权转让不转移计算位置 | 当前未查到继承标签 API，详见 seam，不宣称完成 |
| 权威机器 | dedicated 房主客机点击批准导致本机 spawn；relay 跑规则 | LAN/P2P 房主本机 spawn；dedicated 工作服务端本机 spawn；客机只发意图；relay 不读规则/不 spawn | 静态调用链已定位，缺真实 spawn 位置证据 |

根事务新套件主动检查副作用确实发生，再允许跳过；不能因未进入待答/未触发暂停而出现空验收假绿。它与既有根事务套件互补，不涵盖所有规则池、所有静态字段或所有对象释放场景。随机比较点放在父效果发动前，特意排除“恢复到答复前”的部分回滚假绿。

## 当前源码核对

### 1. 子进程在哪里运行

- `room_data_panel.gd` `_apply()` 138–148：独立服务端选择时发送 `server_data_prepare` 并返回；149–151：非权威只共享目录并返回；165–169：本地房主调用准备器。
- `server_data_approval.gd` 持有同一 `room_data_preparation.gd`，96 行调用 `start()`；应在工作服务端执行，不因管理房主在客机而迁移。
- `room_data_preparation.gd` 95–98：组装完成后调用 `RoomValidationTask.start()`；`room_validation_task.gd` 50–76：真实 `OS.create_process(OS.get_executable_path(), ...)`。这是调用进程所在机器 spawn，不是向客机远程执行。
- `server_cli.gd` 90、118、121：game 与 relay 分开启动；显式纯 relay 不走游戏监听。已有 `net_server_roles_test` 真启动纯 relay 并验证 UDP 可绑定、WebSocket 建房，但本轮禁止运行。
- 准备器 `start()` 本身只检查 session 非空和预算，未单独验证计算主机角色；现行 UI 调用点设闸不等于整个服务 API 已具备该不变量。建议在共享边界再显式拒绝非权威调用，保留 dedicated 服务端角色语义，不能以 `room.owner==peer_id()` 判断实际计算权。

### 2. 回滚状态与执行范围

`effect_checkpoint.gd` 13–26 明确保存随机、GameLog journal/trace/上下文、限制、属性、静态卡池和 AI 尝试状态，并捕获 GameData/GameProgress/MapData/TimePointChecker/GameStart/EffectManager 根对象；事务/预算运行元数据有显式排除。`rule_checkpoint.gd` 保留集合引用及对象字段、恢复信号连接；PackedArray 明确拒绝而非伪造完整检查点。

已有 `rule_guard_rollback_test` 覆盖直接效果的新状态/牌区引用与随机；`rule_guard_chain_rollback_test` 覆盖跨玩家、内部延迟子效果和外部尾部。本次补齐“父动作真正耗随机/移动牌后，子答复异常回到最早前态”的组合，并对全量规则事实而非只 `type=effect` 比较。

严格全量事实比较若被正常管线外层事实扰动，必须先查证该事实是否属于事务外部安全尾部、记录其合法顺序，再拆成事务内等价与事务外恰好一次；不能直接放宽/删去日志断言求绿。当前夹具仍保留严格比较，运行后才能知道差异。

### 3. 审计不等于普通规则日志

`match_journal.gd` 使用 MAGIC、帧长、序号、前链 SHA、基础 Variant，append flush 后检查 `FileAccess.get_error()` 才推进内存序号与链头。新夹具验证格式与失败拒绝；其中 root_begin/root_rollback 是**测试写入内容**，不是生产入口已经生成这两类审计事件的证据。

`effect_checkpoint.gd` 回滚的是内存 GameLog；它不提供回卷已追加磁盘 MatchJournal 的 API。根事务审计需与规则事实分开：失败规则事实应撤销，管理“回滚成功/失败、执行身份、前后状态指纹、根 ID”审计应保留且不可随回滚删除。没有找到专用持久审计写入接线，不可用通用日志格式能力声称已实现事务审计。

### 4. 认证恢复与旧档

`member_identity_bindings.gd.valid_state(state, required)` 要求受保护房间全部成员有合法公开指纹，resume_hashes/previous 的成员归属存在；不接受 `02`、小数等成员键。本次新增结构反例不涉及私钥。

已有真实入口测试明确区分：专用房间恢复需已认证密钥；LAN/P2P 不能相信客机自报 gateway_identity；认证模式旧档失败保留原字节；未认证旧 JSON 有兼容路径。**旧档绝不自动认领**应指原身份绑定不得被首个持票者建立，不能把未认证模式兼容读取自动称为违规；若要全面废止未认证旧档，需要主代理将模式适用范围显式写入策略。

## 尚需主代理增加的安全 seam（本轮不改生产代码）

1. **spawn 观察/注入 seam**：集中真实 spawn 入口，允许测试记录调用方 OS PID、机器标识、会话计算角色、worker PID 与参数，再调用原 OS API。不可仅返回假 PID 宣称进程已运行。LAN/P2P/dedicated/relay 各走正式入口；dedicated 外部协调器记录网关、工作进程、房主客机，断言只服务端记录规则 spawn。机器标识仅用于位置证据，不作为用户身份或认证材料。两台机器与本机多进程分别报告。
2. **磁盘失败 seam**：给日志 writer 提供可注入的存储接口（保持生产 FileAccess 默认），在 store/flush/rename 各点返回错误；测试真实序号链头、错误锁定、saved=false、暂停仍在、后续操作不得继续成功。注入只证明失败语义；另在独立受限测试卷做真实 I/O 错误。不要填满用户盘、修改系统权限或杀生产进程。部分帧已经写出时，原件要明确标坏/只读，不在旧文件偷偷续写。
3. **房主继承标签入口**：复用权威成员/认证绑定与现有房主管理入口，定义标签的数据来源及允许集合、源成员、受让认证身份、权限/修订校验。当前无可安全引用 API。测试矩阵：非房主指定拒绝；客户端自报标签拒绝；同昵称异密钥拒绝；封禁受让人拒绝；过期修订拒绝；仅允许标签继承；未指定标签不继承；重复提交幂等；明确转让后原票据/旧密钥不能继续控制；写盘失败原绑定与标签全保留。继承授权不绕过恢复票据与密钥校验，不能把公开标签当恢复凭据。
4. **审计接线与成功边界**：先定义审计内容、失败关闭策略和与 MatchJournal/管理回执的提交顺序。若用户要求回滚必须有持久审计，审计写盘失败不能同时返回“回滚成功并继续”；内存已回滚但审计失败应保持暂停并报出混合状态，不把已经发生的恢复反向伪装成未发生。测试拒绝不写成功事实，成功只有一次且可读回；审计不记录 token、私钥、隐藏牌/执行参数。
5. **全状态见证**：新套件只覆盖已可安全创建和引用的状态。补真实次数/变量、共享/循环集合、时点队列、限制与静态数据池、AI 缓存、失效对象及未知 RNG 的具体变异，禁止仅比较局部哈希证明完整根事务。进程崩溃不能使用同进程对象图恢复，应独立重放/保存协议验收。

## 可执行命令（交给主代理，写入者全部退出后串行执行）

Git Bash，仓库根目录执行，显式设置隔离 scratch；不要边运行边改源码。

```bash
export TMPDIR='C:/Users/Administrator/AppData/Local/hermes/cache/scratch'
GODOT='D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
# 主代理先检查上述文件确实存在；路径来自项目技能，未在本轮启动。
for t in acceptance_root_transaction acceptance_audit_chain acceptance_identity_state; do
  "$GODOT" --headless --fixed-fps 60 --path 'E:/Projects/Godot/FateDominationGame-master' --scene "res://tests/${t}_test.tscn"
  code=$?
  printf '%s exit=%s\n' "$t" "$code"
  if [ "$code" -ne 0 ]; then break; fi
done
```

依赖组合回归：`rule_guard_rollback_test`、`rule_guard_chain_rollback_test`、`net_member_identity_binding_test`、`net_server_roles_test`，参数同上。后两者含真实认证/子进程，由主代理按授权范围执行，本子代理未执行。每套需同时核对退出码、RESULT failures 和 SCRIPT ERROR，任何一项错误都不算绿。

红验证只在主代理批准的独立工作副本暂时撤掉对应修复，不修改当前共享生产工作树：根事务改成只清队列应被资源/牌区/RNG/日志断言抓住；移除日志序号校验应被重算 SHA 的错序抓住；移除前链应被断链抓住；移除 required 绑定门槛应被旧档抓住。已有身份套件 `-- red` 可在独立基线副本运行以验证 B 持 A 票据反例；当前修复版本 red 模式仍拒绝时不能称已重现原缺陷。

## 未决边界

- 继承标签语义、授权撤销和持久化边界尚无实现 API，需主代理完成规格与接线。
- 格式日志已具备检查能力不等于业务审计已经接线；磁盘满/flush/rename 失败仍待真实故障或 seam。
- 权威 spawn 位置仅静态确认；没有启动进程、两机、P2P/NAT、公网或 Linux 证据。
- gdparse 通过不代表运行绿，主代理必须冻结源码后执行；tests 被忽略需显式交接/按项目决定是否强制纳入版本控制，本轮不 commit。
