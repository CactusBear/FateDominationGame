# 恢复后目录修订号、候选/批准目录与客户端 accepted revision 审计

## 范围与结论

只读审计现有生产代码，未运行 Godot、未修改生产文件。指定四文件已全文读取，并沿 lobby_session、server_data_approval、server_room_worker 的真实读写链检查。这里的“目录”分别指候选条目索引和已批准文件 manifest，不混同磁盘目录。

结论：恢复 JSON 的 revision 本体类型转换正确；但批准状态缺少持久化，恢复重新扫描候选源而不是恢复批准快照，可能拒绝合法的已批准目录或丢失批准状态。另有旧档将 room revision 冒充 data revision、恢复设置不使用已有解码入口等一致性缺口。

## 字段契约

| 字段/对象 | 当前类型与语义 | 恢复行为 |
|---|---|---|
| MatchRoomState.revision | int；成员/准备/设置/阶段变化计数，不是内容版本（room_state.gd:9、69、138-141） | load_recovery_state 校验有限、非负、整数值且不超过 2147483647，再转 int（lobby_session.gd:1290-1292、1329） |
| server_data_approval._catalog_revision | int；候选索引/批准选择展示的进程内版本，从 1 开始；上报索引和成功批准均递增（11、42-46、139-144） | 未持久化，每次新建组件重置到 1 |
| catalogs[member] / server_data.entries | Array；经 MatchDataCatalog.accept 验证的可选元数据，不是已批准内容 | catalogs 未写入 recovery.json；重启成员须重新上报 |
| _approved / server_data.selected | Array[{provider:String,key:String}]；房主已批准引用集合 | 未持久化；configure 仅依据 room_files 非空推断“所有 server 条目已批准”（server_data_approval.gd:26-27） |
| session.room_files | Array[{path,hash,size}]；批准后发布的内容 manifest | recovery.json 不包含此集合；worker 从 config.data_root 新扫描/构建 plan |
| session.data_revision | int；批准 manifest 的内容发布版本。客户端也用同一字段表示最后接受的 manifest revision，并非最后安装成功版本 | recovery.json 有独立字段并校验后转 int（lobby_session.gd:1288-1289、1326、1365）；客户端接收更高版本即更新，并清空 assets（1055-1060） |
| _data_confirmed[member] | 对应 data_revision；安装完成后的 ACK 屏障 | 不持久化；重新 ACK。data_ready 还检查 _rules_revision（1032-1039） |

代码没有名为 accepted_revision 的独立 session 字段；此审计把客户端 data_revision 视为 accepted manifest revision。候选 catalog_revision、房间 revision、内容 data_revision 不可相互替代。网络消息采用 var_to_bytes/bytes_to_var，保留 int；不要因 JSON 会产生 float 就放宽网络 int 契约。

## 发现（静态确认，尚未修复）

### 高：已批准 manifest/来源快照不落盘，恢复用当前候选源替代

证据：lobby_session.gd:1365 的恢复写入保存 data_revision，但不保存 room_files、catalogs、已批准 provider/key/hash 或 approval revision。server_room_worker.gd:71、104-114 从 config.data_root 全量扫描生成 plan；133-143 以该 plan 校验既有 isolated data；不是以最后批准 manifest 校验。

触发：房主成功批准原始 server 全目录的子集或客户端条目；崩溃前 isolated data 与新批准集合一致，config.data_root 仍是原始候选根。重启仍构建原始全量 plan，并用其验证批准目录，可能因缺文件/哈希不同失败关闭。失败关闭保留旧目录是安全行为，但不能视为支持该合法批准状态恢复。即使校验侥幸通过，也没有持久化证据证明新的扫描集合就是上次批准集合。

另外，worker:175-179 在 settings 含 random_sim_enabled 时跳过 set_room_files/install_room_assets；load_recovery_state 只恢复 data_revision，不恢复 room_files。此时可能得到“data_revision > 0 但 room_files 为空”的状态；183 又以空 manifest 配置 approval，使上次批准选择消失。未据此声称恢复一定进入 playing，具体后续恢复屏障需运行验收。

建议：持久化并验证明确的批准 manifest、内容版本与来源引用/哈希；恢复先逐文件核验这份批准快照。候选源扫描只能供下一次选择，不得冒充已批准快照。含预检开关的恢复也应区分“从未批准”和“曾批准且快照有效”，不能仅以开关存在跳过旧批准恢复。

### 中：旧档缺 data_revision 时回退 room.revision，混淆两个版本域

证据：lobby_session.gd:1288，state.get("data_revision", saved.get("revision"))。

room revision 可因准备、成员掉线等增加，与内容发布无关。旧档虽可通过数值校验，仍可能被赋予从未发布过的内容版本。worker 在非预检分支随后 set_room_files 又递增此版本，维持的不是原批准数据序号。

建议：缺独立 data revision 的旧档失败关闭，或通过显式旧档迁移建立已验证 manifest/version；不得用 room revision 隐式填补。

### 中：恢复 settings 未复用 decode_json_settings，整数契约不一致

room_state.gd:143-156 已提供容量/人数等 int/float 整数值校验与归一化；worker:66-70 在配置 JSON 加载时使用它。load_recovery_state:1293-1298 只解码 runtime_guard，1327 原样复制 settings，未调用该入口或 _valid_settings。

因此 JSON 恢复的 capacity/minimum/ai_count/spectator_limit 可仍为 float；room_state._valid_settings:159-167 要求 int。恢复本身可能成功，下一次 set_settings/configure_rules 构造 candidate 后却因未修改的旧浮点字段拒绝；并且恢复入口未验证这些字段的整数性和范围。

建议：恢复读取阶段调用已有 decode_json_settings，并完整验证结构/业务约束，在全部验证通过后提交状态，不增加平行解码实现。

### 中：候选 revision 跨重启重置，客户端只验证正 int，不检查版本域/回退

server_data_approval.gd:11 初值 1；catalogs_changed/commit 才递增。lobby_session._accept_server_catalog:920 验证正 int，946 直接覆盖客户端 catalog_revision，没有进程 epoch 或“不接受较旧版本”的判断。重启后的同一数字不代表重启前同一候选快照。

当前 _prepare 会重新检查引用确实存在且唯一（server_data_approval:78-89），不因此允许任意路径或未登记数据；但同 provider/key 的内容已改变时，旧 UI 引用并未携带旧 hash，revision 重用削弱了“按看过的内容批准”的契约。需验证重连是否必然清空旧 server_data/UI 请求，不能把它直接定性为已复现跨连接攻击。

建议：目录版本绑定实例 epoch，或持久化单调 revision 并在重建候选时推进；客户端明确在新 epoch 清空旧选择/状态、在同 epoch 拒绝回退。

### 低：已批准引用集合的展示来源可能不真实

server_data_approval.configure:26-27 只要 room_files 非空，就将扫描得到的所有 _entries 标成 approved，不按 manifest 对应关系和哈希确认；lobby_session:938-942 对 selected 只验证字段和去重，不保证与可选 entries 匹配。

不过 selected 不能简单要求始终属于当前 online entries：已批准客户端来源掉线后，完整批准副本仍有效，候选 _available 会隐藏其来源（server_data_approval:35-39）。正确修复是给已批准集合独立快照/来源状态，允许“已批准但来源离线”，而非删掉合法批准项。

## 指定组件的边界核对

- data_catalog.gd:11-45 的 accept 只校验索引；47-73 verify_content 才验证缓存字节与 JSON 身份/依赖；名称 accept 不是 approval。scan 返回真实文件 size:int，网络 accept/assembler 检验路径、哈希与大小；此文件不承担恢复 revision。
- catalog_message_transfer.gd:11-53 只负责候选消息基础类型、分片预算、来源/通道隔离；完整消息才走 session 语义校验。它不提升批准权限，也不规范化恢复 JSON revision；不能在分片层塞批准版本逻辑。
- blob_receiver.gd:14-28 的 expect_blob 是本地预先授权的 sender/hash/size，34-59 按连续偏移收块并由 cache.store 验哈希。pending 无 revision，按内容哈希隔离是合理的；完整副本不会因来源离线被撤销。完成接收不意味着批准整个目录，也不意味着客户端已安装/ACK。
- 客户端接受 manifest 后先 data_revision = revision、_assets.clear（lobby_session:1055-1060）。room_files 入口要求 revision > 当前接受值（601），恢复身份仅在相同 revision 且 assets.is_installed 时自动 ACK（560）；已接受但未装完不自动 ACK。这一区分正确，不应把 data_revision 更名为“安装完成 revision”却不新增安装屏障。

## 验证证据与待验收

执行 Python 只读源码断言，6 项均 True，退出码 0：恢复 revision 校验后转 int、旧档 room revision 回退、客户端 strict-new manifest 门槛、approval revision 初始为 1、approved 从全部 entries 推断、session 无 accepted_revision 符号。此结果是锚点核对，不是 GDScript 运行测试，也不是模拟 Godot 结果。

未执行任何 Godot 命令。建议主代理后续串行验收：批准 server 子集后恢复；批准客户端来源后来源离线再恢复；预检开关打开且已批准的大厅恢复；旧档缺 data_revision 拒绝；JSON 人数字段整数浮点合法/小数负数拒绝；客户端已接受但未装完时同版重连继续安装、不错误 ACK；候选 epoch 变化时旧选择/请求不能批准同名不同 hash 内容。

## 文件变更

仅新增本报告 scratch/net-batch-13/catalog-revision.md，生产文件零修改。
