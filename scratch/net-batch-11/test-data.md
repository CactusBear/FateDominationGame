# 测试数据、旧房间和日志污染只读审计

审计时间：2026-10-07 22:45–22:50（本机时间）。未运行 Godot，未清理、迁移或修改测试数据/生产文件；本任务唯一写入为本报告。结论来自现存日志、JSON、目录及源码，不是新的运行验收。

## 结论

- **没有证据表明旧 room/recovery 或旧日志导致最近的 `room worker starts` 失败。** 当前完整对局夹具使用每次独立的 `res://tests/runtime_reports/server_match/<ticks_usec>/workers`，旧 `test/rooms` 和 `test/server_rooms` 均为空；旧信令/房间夹具位于其他独立根。manager 只扫描指定 storage_root 的直接子目录，不全盘扫描 test。
- **两次最近的独立进程探针，工作进程实际到达 READY 后因主管心跳丢失退出。** 根因方向应优先查主管/探针生命周期、autoload 编译错误及心跳刷新，不应先清理卡数据。它们与最新完整对局失败是不同运行，不能混作同一条因果链。
- **日志存在明显的跨运行证据污染风险，但当前生产 ready 判定不读日志。** `test/logs/godot.log` 是共享轮转日志；只扫 `SERVER_ROOM_READY` 会把已退出实例当成功。最新完整对局失败只有通用错误，现存证据不足以定位它在 create_room 的哪一层失败。
- 旧配置确实不符合当前恢复/ready 契约；若显式把它们选为 storage_root，会被拒绝。但没有它们进入最近独立测试根的证据。

## 实际目录和数据检查

测试用户目录：`E:/Projects/Godot/FateDomination/test`。

递归统计（仅该 test 根）：`config.json` 6 个，`recovery.json` 7 个，`ready.json` 7 个，`supervisor.json` 6 个；全部可解析 JSON。7 个 ready 中 5 个是旧网关报告，2 个是旧房间报告，不能全部当作 room ready。

数据根：

| 路径 | 文件数 | 总条目数 | JSON 语法错误 | 扫描到的链接/junction/尾部点空格等异常 |
|---|---:|---:|---:|---:|
| 仓库 `data` | 339 | 420 | 0 | 0 |
| `test/server-dist/windows/data` | 339 | 420 | 0 | 0 |

两根逐文件 SHA-256 对比：路径集合相同，内容不同文件 0。该检查证明现存发行数据与源码数据一致，不证明卡规则语义、Godot 资源装载或 data manifest 验证通过。

近期 `process-owner-room-probe` 两个房间各有 205 个 isolated data 文件、71 个 JSON，JSON 均可解析；recovery.phase 均为 lobby、成员数 0。房间 data 的 64 位目录名不能当作每个文件的摘要（包含组合条目/重写 JSON）；审计中尝试此假设后已弃用，不据此报告数据损坏。未重建 Godot plan/validator，因此不宣称逐文件房间清单校验完成。

`test/game_data` 只有 `stored_jsons.dat`。工作进程明确把 LoadGame.stored_jsons_path 改为 `<room>/stored_jsons.dat`（worker:145–147），不是读取这个共享单机缓存来判 ready。

## 近期失败与探针分账

### 完整对局测试：失败确认，根因未定位

`test/logs/godot.log`（22:43:55 修改）全文 7 行：

```text
CHECK sole server entry starts full match fixture true
SERVER_JOIN_FAILURE 服务端房间操作失败，请联系管理员检查房间状态
CHECK room worker starts false
RESULT checks=2 failures=["room worker starts"]
```

`godot2026-10-07T22.37.52.log` 也记录同样失败。测试源码 `tests/net_server_match_test.gd:6,120–124` 每次生成独立 storage_root；到客户端 view 为空时打印通用 session.error（24–32），该错误本身没有携带 manager.error，不能由它断言数据缺失、旧 ready 或端口冲突。

现存 `tests/runtime_reports/server_match` 只有 6 个旧目录：3777722、4039756、5103116、5170197、5933770、6594767，修改时间为 17:19–18:33；均只有 client-0/client-1/client-cache，无 config.json、ready.json 或 workers。未找到 22:37/22:43 完整对局运行对应的新房间配置。这个负证据倾向于房间配置写入前拒绝或未创建目录，但不足以确定具体分支，且该目录是现存快照，不保证历史从未被其他任务处理。

### 独立进程探针：READY 后主管失联

| 房间 | 实例 | 主管 JSON PID | 时间 |
|---|---|---:|---|
| 6535047b1502f6d6f840e6b8d09a9648 | 9395313f262eff36c6e557d8830d2425 | 8544 | config 22:38:10；engine 最后修改 22:38:22 |
| 03dc65bbfc9d9eb63d77ff67899f088c | 467a1f699455200f21c4171578e9d5f6 | 24008 | config 22:41:03；engine 最后修改 22:41:17 |

各自专属 `engine.<instance>.log` 均只有 5 行，无 SCRIPT ERROR，末两行分别为：

```text
SERVER_ROOM_READY <对应 room id>
SERVER_ROOM_SUPERVISOR_LOST <对应 room id>
```

对应 supervisor.json 都停在 version=1，实例和 PID 与配置/主管记录匹配；现存 ready.json 与 ready.json.tmp 都不存在。日志证明它们曾 ready，不证明当前仍 ready，文件缺失原因也不能只靠目录快照确定。

`godot2026-10-07T22.41.01.log` 与 `godot2026-10-07T22.43.32.log` 各 3197 行，包含 `scratch/process_owner_room_probe.gd` 的 GameData/GameStart 未定义、依赖编译失败和 Nil 调用；尾部 ROOM_STATE 已标 ready=false、error=房间进程已经退出。独立工作进程日志没有相同编译错误，说明不要把主管探针错误误归给房间卡数据。该 scratch 探针源码当前已不存在，无法完整审计其运行模式/心跳轮询调用。未复现、未运行 Godot。

## 旧 room/recovery 的真实影响边界

旧房间配置位于四个 `signal-match-windows-*/rooms/<id>` 根；均没有 authority_host_mode、instance_id，且原始 data_root/directory 含反斜杠。当前 `RecoveryPathSafety.absolute:6` 直接拒绝反斜杠，不会偷偷规范化；manager.discover_rooms:264–269 还要求安全配置、显式权威位置和有效实例。因此管理员若将这些目录指定为恢复存储根，会得到失败关闭而非自动迁移。

旧房间 ready 只有 id/instance/ok/pid/port，没有 room_id、instance_id、authority_host_mode、capabilities，不符合 manager.valid_ready_report:100–106。旧 recovery 缺 member_identities 等绑定字段；必须按当次 required/protected 策略审查，不能一概说所有旧 recovery 都必然拒绝：member_identity_bindings.valid_state 在 required=false、未保护且无身份绑定时仍允许旧无绑定状态，而 required=true 则拒绝。四个旧 config 已先因路径/实例契约被拒绝，无需依赖该后续分支。

`recovery-state-3055265/recovery.json` 是单独恢复夹具，无同级 config，且目录名不是 32 位合法 room id；不能作为完整服务端房间自动注册。

不同根中的重复旧内部端口 52000 不等于当前端口冲突。只有同一指定根中成功登记的房间或真实 socket 占用才会影响；本任务未做 live socket 检查，不能宣称端口可用。

## ready 和日志污染机制核对

- manager.create_room:172–195：随机 room id + instance_id，新建专属目录和 `engine.<instance>.log`；已有同名目录则拒绝，不复用未知旧房间。
- manager.poll:211–235：先验证当前原生拥有进程状态；再读取 exact `<room>/ready.json`，校验 room、PID、端口、实例、authority mode、能力；**不扫描 engine.log 或共享 godot.log 来决定 ready**。
- manager.recover_room:337–345：创建新进程前处理旧 ready，并换新实例日志。这里是代码行为审计，本任务没有调用恢复或删除任何文件。
- worker:133–143：已有 isolated data 只允许经过 manifest validator 验证后复用，不覆盖未知残留。worker:191–202：写 tmp + rename 发布 ready 后才打印 READY。
- worker:211–216：心跳必须匹配 room/PID/instance 并增加版本，超时打印 SUPERVISOR_LOST 退出。现存两个探针证据与该分支吻合。
- 共享 `test/logs/godot.log` 的轮转命名意味着文件名不能当作一个套件身份或一轮会话身份；最近两份大日志还能看到上一轮 ROOM_STATE。需按 suite、room、PID、instance、日志路径和时间区间分账，不能拼接旧成功与新失败。
- 网关 ready/status_file 报告是另一契约，不能传入 valid_ready_report 冒充房间报告。旧网关 status 文件仍可形成外部夹具“仅检查文件存在”的误判风险，本次没有证据表明该风险已触发。

## 交接建议（未实施）

1. 保留全部现场，不以清理 test 修复本次失败。
2. 父代理下一次获准运行时，为完整对局单独指定本轮日志；捕获 manager.error、room binding、主管 version、原生 process state，定位 create_room 是否返回空。
3. 探针与完整对局分开验收：修复探针 autoload/执行模式和持续 gateway.poll 心跳后，再判断 room ready。READY 后 SUPERVISOR_LOST 不能记为数据加载失败。
4. 恢复测试选择明确的新契约存储根；旧 signal-match 数据只读保留，迁移必须管理员显式授权。

生产文件修改：无。测试数据修改/清理：无。新增文件：仅 scratch/net-batch-11/test-data.md。静态范围：manager、worker、load_helper、recovery_path_safety、lobby_session.load_recovery_state、member_identity_bindings、完整对局夹具，以及上述现存文件扫描。未执行：Godot、恢复/房间操作、数据清理、live socket 探针、运行 manifest validator。
