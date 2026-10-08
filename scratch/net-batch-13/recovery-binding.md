# 恢复实例与网关绑定审计

## 范围与证据等级

- 只读审计 `server_room_manager.poll/recover_room`、`server_room_worker` 启动/自动恢复，以及 `server_gateway` pending/route、`lobby_session.load_recovery_state/restore_local_match` 实际调用链。
- 未运行 Godot，未修改生产代码；以下是源码静态确认，不是多进程、故障注入或对局恢复运行验收。
- 仓库：`E:/Projects/Godot/FateDominationGame-master`；HEAD `8b46af0`。被审计主要生产脚本当前是未跟踪文件，结论依据工作树而非 HEAD。
- 拓扑：dedicated 的公网连接经网关到服务端本机回环 worker，worker 执行规则；LAN/P2P worker 应位于房主机器，信令节点不负责规则。当前 worker 对带 recovery.json 的 LAN/P2P 启动明确失败关闭。

## 状态转换表

| 阶段 | 主管实例/PID/token/ready | worker room/phase | 网关 |
|---|---|---|---|
| discover_rooms | 读 config 中原 instance_id、mode；PID=-1，无 process_token；ready=false | 临时 session 仅验证 recovery 文件，不启动规则 | 尚无绑定 |
| 运行 worker 退出 | poll 先 ready=false；原生 state=0 且 release 成功后 PID=-1、token=""，保留 instance_id/mode/目录 | 原进程已退出 | 旧 pending 的 PID 失配；旧 route 因 require_ready 失效，撤销 link，不删除登记 |
| recover_room 准备 | 验证旧 PID/instance、已退出、config 同登记且 mode 相同；生成新 instance 写 config；删旧 ready | 尚未加载 | 旧绑定不能迁移到新实例 |
| recover_room 提交 | spawn 返回新 PID/token；释放旧 owner 后写新 PID/token/instance；ready=false、error=""、新 deadline；mode 不改 | 新 worker 开始启动 | 发起恢复的连接登记恢复后的 binding；其他原成员可等待同一个新实例 |
| worker load_recovery_state | ready 尚未发出 | host 创建新 room 对象；校验恢复文件后原地填充该对象；真人均 disconnected、ready=false；playing→restoring，其他 phase 原样保留 | pending 不依赖 phase，等待 ready/OS 所有权 |
| worker ready | ready 报告同 room/PID/instance_id/instance/mode；主管确认报告及原生 state | 恢复文件加载、数据安装成功，但对局可能仍 restoring | pending 四元组+原生 verify 通过才 attach；不要求恢复对局完成 |
| 自动 restore | 不换实例 | 等 `_recovery_bindings` 中真人 connected；复制日志到实例私有目录；await restore_local_match；成功后数据屏障仍保持 restoring | 只转发当前实例 link 的回应 |
| 回到 playing | 同实例 | candidate.started 且 data_ready 时 poll 改 playing、修订号+1、绑定并发布 | route 身份持续校验；不自动换 worker |

`room.instance` 的命名需区分：主管房间记录实际字段是 `instance_id`；ready 报告及控制协议另有 `instance` 别名，不是 MatchRoomState 的字段。`restore_local_match` 中 `original_room = room` / `room != original_room` 检查的是 RefCounted 对象身份，不是进程随机实例。MatchRoomState 本身没有 PID、token、mode、instance 字段。

## 已有正确边界（静态确认）

1. 原生 owner 的 process_token 只在主管内存；磁盘 PID 不被认领。binding 对外仅传 room/PID/instance_id/mode，require_ready 还要 owner.verify(token, PID)。见 manager:53–98、204–247、295。
2. recover_room 用旧 expected PID/instance 防过期管理请求；配置同时约束 room/port/instance/mode，不从恢复配置提升 mode；新 ready 必须在 spawn 前清除，日志按新实例分离。见 manager:304–379。
3. ready 报告同时校验 instance 与 instance_id 且值等于登记；旧 worker 退出只删除自己 PID/instance 对应 ready。见 manager:100–106、worker:191–200、350–355。
4. gateway pending 保存快照四元组，恢复后重新取 binding，不沿用旧 PID；attach 前/连接后重验，route 回调还核对 link 对象，旧回调不能关新 link；崩溃只撤 route，不 stop_room。见 gateway:61–98、181–200、280–346。
5. 恢复请求启动 worker 前，网关核对票据哈希和已认证密钥；worker join 再核对密钥后核对票据，随后 reconnect 稳定 member_id。见 gateway:263–278、session:254–285。
6. worker 初次 host 发布时 recovery_state_path 尚为空，新进程不会立即覆盖旧 recovery.json；load 的主体校验在 room 修改前完成。LAN/P2P 安全阻断位于 host/load 前，自动恢复另有第二道阻断。见 worker:84–90、155–164、225–235，session:1281–1317。

## 缺陷与风险（按优先级）

### R1 高：dedicated 自动存档恢复不是失败原子事务，会把 restoring 写成 lobby

- 路径：worker:260 → session:1374–1425。
- `restore_local_match` 在验证/replay 成功前就修改 room.phase/revision 并 `_publish()`（1382–1384）；`_publish` 无条件调用持久化且忽略返回（879–899）。失败时两处改 `room.phase="lobby"` 并再次发布（1390–1396、1405–1414）。
- 效果：旧 playing 恢复进入 restoring 后，只要日志/绑定/replay/素材发布失败，recovery.json 可被覆盖成 lobby；再次重启不再自动尝试恢复。恢复副本保护了原 match.log，但没有保护恢复阶段事实。写盘失败也不阻止内存状态或成功返回，不能声称失败原状态不变。
- worker 的 `_recovery_attempted=true` 对错误不回退（225–261），只有缺席真人才重置 false，失败后同实例没有自动重试。
- 建议：提交前维持原 room/phase/revision/rules root/恢复文件，候选恢复+数据安装+持久化统一提交；失败仍 restoring，记录可重试错误，不降级 lobby；提交失败不得返回成功。

### R2 高：恢复 lobby/selecting 没有重新建立选人配置/状态

- worker:167–170 只在 `not recovered_state` 时 configure_selection；session.host 的 close 清空 `_selection_config` 并创建空 selection（423–433）。load 只恢复 settings/members/phase 等，并不恢复 selection（1281–1353）。
- lobby 恢复后 `_selection_config` 为空，进入选人的 `_begin_selection` 会因无注册规则拒绝（session:1258–1261）；selecting 恢复则直接保留 phase，却没有阵容/顺位/规则对象，不能正常继续；自动日志恢复只处理 restoring。
- 建议：恢复大厅也重建批准的 selection 配置；selecting 要明确保存并验证原选人状态，或通过明确政策回退大厅并重置，不保留一个空的 selecting 壳。不要把 worker ready 当大厅/选人恢复验收。

### R3 高：playing/restoring 的绑定允许空或不完整，缺席等待可被绕过

- load 仅校验 bindings 元素的数值/成员存在，没有验证 playing/restoring 必须有完整 player_id 映射、键范围/规范形式或真人映射唯一性（session:1305–1313、1346–1351）。`bindings={}` 合法。
- worker 等待真人只遍历已声明 bindings（231–235）；空绑定直接越过等待。共享 restore 在空绑定时退回 `_room_seats()`（session:1385），按当前成员遍历顺序重造 player→member，违背“最近有效稳定绑定”。
- match_authority 的 header 校验会拒绝座位数量/类型不一致（475–481），因此不能说所有空绑定都能恢复；但若 fallback 的数量/类型吻合，则未验证真人原身份或在线，错误映射仍可被接受。即使被拒绝，也会触发 R1 写 lobby。
- 建议：playing/restoring 必须声明完整绑定，与日志 header 双向校验；禁止 fallback；每一原真人的稳定 member、密钥和票据均需可验证；重复成员/负 player key/别名键碰撞失败关闭。

### R4 中：磁盘新 instance 先于内存登记发布，回滚错误未检查

- manager:341–379 先写新 config，随后删 ready/spawn/释放旧 token，最后才更新 room.instance_id/PID/token。三条回滚写配置均忽略返回（352–354、361–364、368–371）。
- 若发布后、登记前主管崩溃，磁盘新实例可能已运行但新 owner token 尚未进入 room，重启 discover 只登记 PID=-1；不会错误认领 PID，这是安全边界，但需靠 worker supervisor 超时退出再恢复。
- 若 spawn/release 失败且回滚写失败，磁盘 config.instance_id 与内存旧登记失配，之后 recover_room:332–334 永久拒绝，直至显式再发现/管理修复。新 spawn 的 terminate/release 返回也未核对（366–367），失败关闭没有完整清理确认。
- 建议：显式记录准备/提交代际，所有补偿返回都报告并保留可对账状态；原生能力不能从“调用了 terminate/release”推导已清理。另需故障注入验证主管崩溃窗口。

### R5 中：恢复中再次掉线仍可切 playing；数据屏障不检查全部原真人在线

- worker 开始恢复前检查 connected，但 await 期间 `_maintain_restore_transport()` 持续 poll（session:1427–1430），真人可再次掉线。
- session:380 只要求 match_authority.started 与 data_ready；data_ready:1037–1039 只检查 connected 成员的 ACK，忽略离线成员。故恢复完成后可能在原真人缺席时仍将 phase 改 playing。
- playing 的 step/命令另有 `_disconnected_players` 暂停门槛（378、790–792），所以这不是已证明的缺席继续运算/AI 接管漏洞；是 phase 宣告早于恢复成员屏障的状态语义问题。
- 建议：提交到 playing 时重验完整 controllers 的真人连接及密钥/当前数据 ACK；掉线仍保持 restoring，恢复提交成功与可运行状态分开表达。

### R6 中：实例网关专项测试引用已删除的验证注入接口

- `tests/gateway_instance_binding_test.gd:24,27` 赋值 `manager.process_identity_verifier`；当前 manager 没有该字段且已改为原生 `_process_owner`（manager:53–98）。测试断言“可信提供者消费者接线”不再与生产契约匹配。
- 未运行该测试，不能宣称具体 Godot 错误输出；静态已确认它不能作为现行 OS owner/恢复 pending 接线的可靠验证证据。
- 建议：替换成现行原生 owner 契约或明确消费者夹具；新增旧 pending→新 instance 拒绝、新 PID 同号/不同 mode 拒绝、恢复等待中权限撤销、旧 link 排队关闭不影响新 link 等用例。

## 次要观察

- manager.poll:220–224 release 后 continue，当帧 PID=-1/token="" 却可能 error 仍为空；下一 poll 才标进程退出。网关本帧仍因 PID 失配拒 pending/route，不会误 attach，但房间列表可短暂 ready=false/failed=false。
- pending 没有独立截止时间；常规启动依靠 room.deadline/error 清理，连接时再有 route.deadline。若正 PID 的原生 state 不确定而 error 为空，会依赖主管后续 poll 给错误，不应将其当恢复完成。
- recovery.json 不携带 room ID、authority_host_mode 或 instance 代际；跨层关联依赖目录+config，恢复内容本身没有绑定检查。原始状态应允许跨合法 worker 实例续用，但仍宜绑定稳定 room/mode，并清晰区分“保存时实例”与“当前执行实例”；不能要求旧状态实例等于新实例而阻断合法恢复。
- session.close 未清 recovery_state_path/_recovery_bindings（404–474）；当前 worker 新进程路径不复用旧 session，所以首次 host 无覆盖风险，但复用同一 LobbySession 再 host 的路径应补生命周期审计。

## 交接验收清单（本次未执行）

1. Godot 专项：现行原生所有权、gateway pending/route、net_recovery_state、恢复大厅/选人、对局存档恢复；先修正失配夹具。
2. 故障注入：ready 后立即退出、释放旧 token 失败、新 config 发布后 crash、回滚配置写失败、replay/素材/恢复文件提交失败，逐项核对目录与配置/phase 原状态保留。
3. 多真人恢复：持票错密钥拒绝、不同成员并发等待同新实例、恢复 await 中掉线、全部真人认证+数据 ACK 前保持 restoring；旧实例消息/断线回调不得改变新绑定。
4. 明确区分：worker 就绪、房间大厅恢复、崩溃前对局恢复三套结果。当前 ready 不包含 phase 或 restore 成功状态，不可代用。

## 文件与命令边界

- 新建仅本文件 `scratch/net-batch-13/recovery-binding.md`；未创建补丁、未改生产或测试源。
- 执行范围：读取源码/技能参考、搜索调用点、git status/rev-parse。禁止运行 Godot已遵守。
