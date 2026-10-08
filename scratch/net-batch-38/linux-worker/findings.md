# Linux release worker 只读定位

## 结论
不是 bootstrap 未路由、PCK 缺 worker，亦不能由 banner-only 推断 native 初始化死锁。现有落盘证据证明 worker 已进入 server_room_worker._ready() 的内容缓存逐文件写入循环（143–154 行）。观察到 41 个已发布 SHA256 内容块，合计 20,367,991 字节，全部匹配该导出旁 data 的真实文件；尚无 data、data.building-* 或 ready.json，因此失败快照的最窄范围是首次组装目录创建之前：worker 缓存写入循环，或 assemble() 的前置清单/缓存校验。无法从历史快照指定某个 syscall。

## 已核验
- 冻结项目：E:/Projects/Godot/FateDomination/test/export-current-38/project。
- bootstrap、worker、manager、content_cache 四文件与当前生产字节一致。
- project.godot: run/main_scene.fate_server 指向 server_bootstrap.tscn；run/flush_stdout_on_print.fate_server=true。
- manager 257–261 行生成 --headless --audio-driver Dummy --path ... --log-file ... --scene ... -- --server-room-worker CONFIG APPROVED_DATA_ROOT STORAGE_ROOT。bootstrap.process_arguments() 在 fate_server 下只删 --path/--scene，保留 -- 及 worker 用户参数；bootstrap 72–93 行显式路由 worker。
- 只读解析 PCK v4：1325 条目；server_bootstrap/server_room_worker 场景 remap 与二进制 scn、bootstrap/worker/manager/content_cache 的 remap 与 gdc、project.binary 均在包内。PCK 文件 302,605,764 字节。
- 非凭据配置：authority_host_mode=dedicated；port=48000；supervisor_timeout_seconds=5；record_matches=true；transaction_log=true；recovery_key_mismatch=reject；recovery_inheritance=host_select；data_root 为 Linux 导出同目录 data；directory 为本次 room。网关 startup_seconds=30、shutdown_seconds=30。未输出或读取身份/票据字段值。
- 外置 data 共 205 文件、95,950,610 字节（此计数不是 room plan.files 数，不能互换）。
- cache 首块本机文件时间 2026-10-08T08:11:55.753420，末块 08:11:58.991621；41 块在 3.238201 秒内持续发布。首块相对 gateway ready.json mtime 滞后 22.503201 秒；这两个文件时间只证明墙钟间隔，不等于 worker scan 精确耗时或 spawn 时刻。最后匹配 masters/00007_kuzuki_souichirou/00007_kuzuki_souichirou.json。
- 20 秒客户端入房预算先于网关 30 秒启动预算；不能把客户端失败等同 worker 死锁。manager 316–319 行在自身 deadline 到期设置启动超时并终止自己拥有的 worker；此分支是否真实执行，没有独立回执，不能断言。
- 正确 WSL 发行版 FateLinux；只读 /proc 查询时已无 --server-room-worker 进程，也无 FateServer/历史 pid411。未发送信号、未附加调试器、未操作进程。默认发行版 docker-desktop 无 python3，首次探针失败后显式指定 FateLinux 成功。

## 精确分阶段埋点（交主代理实施，不扩大 timeout）
使用统一 WORKER_STARTUP_STAGE JSON 单行，字段仅 room_id、instance_id、pid、stage、event(begin/end)、elapsed_msec、file_index、file_count、processed_bytes、error_code；不记录 config 全文、成员、认证字段或票据。bootstrap 日志在已确认 stdout flush 的路径输出；worker 仍由原 ready.json 契约判定 ready，不以进度冒充 ready。

1. bootstrap._ready()：route selected，以及 deferred change_scene 的实际返回码。当前 fire-and-forget 调用无法标出资源加载失败；加包装回调只记录结果并保留失败关闭。
2. worker._ready() 开头：entry；protect_worker() 前后 signal_guard；配置读取及 RecoveryPaths.checked/tree 前后 paths_verified。既然此次已到 cache，这些不是首要嫌疑，但可准确区分下次冷启动。
3. 129–140：catalog.scan(root) 前后 catalog_scan（entries 数、files 总数）；base 构建前后 base_manifest；plan.build 前后 plan。catalog.scan 内对每个 category begin/end，必要时每个 JSON 条目计数，不输出 JSON 内容。
4. 143–154：cache_seed begin/end；每个条目测量 source_path_check、source_read、cache.store。content_cache._store_locked 内分开 path_validate、temp_write_flush、readback_digest、publish_rename。每若干文件输出进度并保证最后一个文件输出。不能把安全路径检查删掉或缓存为永久已批准。
5. assemble 166：assembly begin/end；RoomDataAssembler 19–22 的全缓存前置校验单独 precheck；27–47 写入循环 assembly_copy；48 rename 为 assembly_publish。尚无 staging 的事实只能定位在此之前，不能指认 rename。
6. 169–181：isolated_tree_validation、validator.validate、LoadGame.reload_game、get_masters/get_servants、mode capacity 分开。
7. 183、201–215、225、233–244：session_host、selection_configure、publish_blobs、install_assets、approval_configure、ready_publish 分开记录。
8. manager 261 spawn 成功处记录 room_id/instance_id/pid；316 deadline 处记录当前阶段及本实例最后进展，不扫完整日志阻塞主循环。可用独立原子 startup-progress.json 绑定 room_id/instance_id/pid，读回验证身份；阶段进度不能延期硬截止或替代 ready。

## 后续修复方向（须靠埋点确认）
若路径检查/catalog/缓存 IO 被证实占据启动预算：将同步启动拆为现有 SceneTree 主线程下的分帧状态机/每文件协作步骤，阶段之间让主管心跳与取消检查运行；不要将共享 autoload reload 或会话 host 盲移工作线程。复用 RecoveryPaths.tree 的 maintenance Callable 做安全维护检查，但不递归调用 session.poll。一次枚举生成清单、减少同文件重复读/哈希仅能在保持逐文件校验与变更失败关闭契约后实施。当前 RecoveryPaths.checked 会逐层打开到 / 的所有祖先，cache.store 每文件多次检查，/mnt/e 上是明确可测热点，不是已证明根因。

验收：同一冻结导出与本次参数，收集从 spawn 到 ready 的阶段耗时、文件进度、最后阶段；若再次超时，保留精确 stage 和进度。运行授权仅在主代理；本审计未运行 Godot、发行程序、生产写、凭据读取或进程操作。

## 文件变更
仅此 scratch 报告。生产和冻结项目未修改。无运行验收、无已验证修复。
