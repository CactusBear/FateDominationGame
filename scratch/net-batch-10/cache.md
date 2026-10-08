# 缓存与恢复路径安全审计

## 范围与证据等级
- 仓库：`E:/Projects/Godot/FateDominationGame-master`。
- 只读检查 `scripts/net/content`、相关同步/预检调用方、`server/recovery_path_safety.gd` 与恢复落盘/复制入口，以及已有测试源码。
- 仅创建本报告；未修改生产文件，未运行 Godot、网络测试或文件系统攻击夹具。
- 以下均为**静态确认的控制流/防护缺口**，不是运行复现。P1 表示会阻断常见恢复/同步或损害恢复可靠性；P2 表示生命周期、残留或需要本地文件系统条件的风险。

## 结论
当前 pin 与缓存清理的进程内互斥基础可靠，但有一条实际同步路径先 pin 后发现损坏缓存，使 Windows 重下载无法落盘。缓存/组装/素材安装未复用恢复路径的祖先链接检查；恢复 JSON 与配置写入没有落实缓存自身已声明的 Windows 原子替换边界。组装 staging 与恢复副本失败/崩溃后的残留缺乏完整清理策略。

## 发现

### C1 — P1：已 pin 的损坏 blob 在 Windows 同步链上无法修复
- 证据：`content/room_data_sync.gd:35-38,60-71` 在第一次 fetch 前 pin 全部清单；`content/content_cache.gd:94-126` 校验失败返回 miss，但 shared pin 阻止删除损坏文件；`:43-48` 遇到任何已有且内容不匹配的目标，在 Windows 直接失败；`content/blob_receiver.gd:50-54` 随即结束接收并释放；sync `:75-78` 将请求消失判为失败。
- 静态触发序列：已缓存 hash=H 的内容被损坏 → sync.begin pin(H) → fetch(H) 得到 miss 但坏目标仍在 → 正确字节完成下载 → store(H) 因 Windows 已有目标拒绝 → 本次同步失败。
- `server/server_room_worker.gd:118-129` 同样先 pin 后 store；损坏的持久缓存还会阻断房间启动，而不是重新读取批准源修复。
- 普通“未 pin 的 fetch 删除坏文件后下载”可成功，因此现有 `tests/net_cache_test.gd:23-26` 只测损坏不可读取，不能覆盖这个交叉场景。
- 建议：将 pin 的删除保护和经 hash 校验的修复提交语义分开设计；不要用先删旧目标再 rename 冒充原子修复。需要真正的 Windows 安全替换或独立的新代文件/引用切换。补真实 sync 与 worker 的“已 pin 损坏缓存”用例。

### C2 — P2：缓存、组装与素材安装只做词法/末端防护，未拒绝祖先链接
- 证据：cache `:39-42,97-102,124-126,174-184,199-203` 对 root 直接创建/打开，只检查 blob 文件名是否链接；`_identity :128-130` 是 globalize+simplify+小写，不是物理路径身份。
- `room_data_assembler.gd:14-36` 对 destination/staging/子目录不检查任何祖先链接；`room_assets.gd:20-28,44-45` 验证相对清单后直接打开本机目录下文件，既不 checked 目录也不 checked 单文件。
- 影响：预置的 cache 根/父目录链接可把读、写、清理导向别处；相同物理缓存通过不同链接别名访问时 shared pin 也可能被另一实例绕过。staging 的中间目录链接可能导致组装写入/失败清理越过本机目标。素材安装验证 hash 防止接受不同字节，但不能证明安装路径位于批准的物理目录内。
- 边界：这不是网络清单直接携带绝对路径的漏洞。destination 有明确本机分配约定；利用需要本机预置链接、配置或同权限修改。Windows junction/其他 reparse point 是否被 Godot `is_link` 完整识别，尚未运行验证。
- 对比：`RecoveryPathSafety.checked :69-85` 确实逐级检查至文件系统根，`tree :87-105` 包括隐藏项、链接、深度与数量预算；server worker 已有恢复根/树检查，但不能代替内容组件自身的通用约束或消除 TOCTOU。
- 建议：本机批准根+目标所有祖先的 fail-closed 检查复用恢复组件；若威胁模型包含同权限竞态，需要原生无跟随/句柄相对操作，不能声称逐层检查已做到竞态安全。

### C3 — P2：RoomDataSync 丢弃 pin token，缓存根/实例变化会解除错误生命周期引用
- 证据：sync `:37-38` 仅保存 hash，`:93-97` 通过当时的 `_session.blobs.cache` 调用 unpin；cache `:142-149` 无 token 时用当前 root 推导身份。
- 影响：同步期间 root 变化时，旧路径 pin 不能被释放；若新路径也由该实例持有相同 key，可能错误减少新路径引用。cache 对象被替换时亦不能释放原对象引用。sync 无 root/cache 快照，也无 PREDELETE 自动 cancel，丢弃仍运行的 sync 可能把 pin 留在长寿命 session cache 上。
- 对比：blob receiver `:25-26,40-42,78-86` 保存原 cache/root/token，拒绝 root 改变并在所有释放出口使用原 token，且 PREDELETE 释放；此实现可复用。
- 建议：sync 保存 `{cache,root,key,pinned_path}`，poll 拒绝 root/cache 漂移；cancel/失败/析构均按原 token 释放。补根变化、替换 cache、丢弃运行中 sync 用例。

### C4 — P1：恢复状态/配置的 rename 发布未贯彻 Windows 旧目标保留语义
- 证据：cache `:45-48` 明确声明 Windows 原生 rename 可能先删除已有目标，并对此失败关闭；`session/lobby_session.gd:1351-1367` 却对既有 `recovery.json` 直接 rename 固定 PID 临时文件；`server/server_room_manager.gd:108-118` 同样替换既有配置。
- 影响：代码没有证明 replace 失败时旧恢复文件仍存在，也没有读回 JSON/字节校验；若原生行为符合 cache 中所声明的边界，旧目标可能先丢失，返回 false 或回滚内存无法恢复磁盘旧档。临时文件名只有 PID，不是一次写入独占身份；lobby 写入链还没有 RecoveryPaths 前后复查。
- 证据边界：本审计未调用引擎验证 Windows rename 实现、未模拟电源故障，因此不宣称已复现旧文件丢失。`flush()` 也不能据此称为文件/父目录掉电持久化保证。
- 建议：统一安全发布能力与平台边界，固定临时名换为独占临时对象，写入/flush/读回校验后安全提交；必须补“目标已存在+替换失败保留旧 JSON”的 Windows 夹具，恢复/配置两入口都覆盖。

### C5 — P2：staging 非独占，正常失败清理也有确定的空目录遗漏
- 证据：assembler `:23-25` 使用 ticks_usec 名字并 make_dir_recursive，无随机独占分配/已存在 staging 拒绝；`:28-40` 先创建子目录并第二次 fetch/open，只有文件已打开才 created.append；`:93-106` 仅从已登记文件推导要删的目录。
- 静态触发序列：清单包含 `new/sub/card.json` → 预取成功 → 创建 staging/new/sub → 第二次 fetch miss 或 FileAccess.open 失败 → created 尚未记录此路径 → cleanup 无法删除 new/sub，最终 staging 删除失败；所有 remove 返回值又被忽略。
- 崩溃/强杀不会进入 cleanup；仓库 scripts 搜索 `.building-` 仅见该生成点，未见 startup 收集器。旧目录通常不会阻断新 tick 名重试，但持续占用磁盘。复用碰撞/预置 staging 还可能写入原有目录内容，和“只删除本次建立目录”的注释不符。
- 建议：使用随机、独占且拒绝已有的 staging，登记成功创建的目录而非从成功打开的文件倒推，传播清理失败；崩溃残留清理按受信根、组件专属命名与存活实例检查进行，禁止泛删陌生目录。

### C6 — P2：恢复副本失败保留半成品，没有生命周期回收
- 证据：worker `:253-259` 写到 `restore-<instance_id>`；`_copy_recovery_tree :263-306` 先创建目录，后续预算/读取/写入/hash/路径检查失败均直接返回，未撤销已建文件；`:264` 目标存在则拒绝。
- 影响：原档保留是正确的，但失败副本残留；同 instance 同路径重试会因已有目录拒绝，换 instance 又留下新一代目录。测试 `recovery_path_safety_test.gd:58-60` 仅断言预算失败和原档不变，不断言半成品清理。
- 建议：复制到组件独占 staging，完成树/hash检查后发布；失败记录并仅清理本次创建项。后续启动区分活跃恢复副本、已采用副本、未完成残留，不能自动删除原崩溃档。

## 已有有效防护与 part 清理边界
- key 严格小写 SHA-256；store 校验正长度、上限、digest，fetch 校验实际长度/读错误/hash，损坏字节不返回（cache `:19-25,33-38,94-118`）。
- cache 所有 store/fetch/pin/unpin/clear/usage 共用静态 Mutex；跨实例但同规范词法路径的 pin 计数有效，本实例不能解除别实例 pin，析构释放自己的引用（`:7-10,132-165`）。这些是**进程内**约束，不协调多个 Godot 进程。
- receiver 预算覆盖完整预计大小，拒绝未授权来源/错误偏移/超块；取消、坏块、store失败、析构释放 pin；completed 回调执行时仍持有引用，并防止同 ID 回调重建请求被误释放（`:14-59,62-86`）。
- cache part 使用 16 字节随机 nonce，写/flush错误与读回 hash 失败均尝试删除，rename失败也删除本次 part（`:49-73`）；清理只认 `<64hex>.<32hex>.part`，不泛删陌生 `.part`，跳过显式链接，沿 blob key 尊重 shared pin（`:178-194`）。
- 限制：这些 remove 失败未反馈；进程崩溃 part 需显式 clear 才回收，未见自动启动回收。跨进程 static lock/pin 不共享，另一个进程调用 clear 可以删除当前进程仍在写的合法 part；需明确不共享 cache root 的部署约束或引入跨进程协调。Windows 目标存在的拒绝分支仍受 C1 影响。
- RoomAssets 路径表只有全部 size/hash成功后才一次赋值，失败不污染原表（`:25-45`）；这是内存映射提交，不是文件系统快照，install 后文件仍可变化。
- 恢复路径词法防护包括点段、重复分隔、ADS、保留设备名、尾点/空格、Windows绝对盘符；containment 用路径段边界，不是裸前缀。现有祖先链接测试需要系统权限，会明确 skip；未执行，不能称链接运行验收通过。

## 下一轮最小验收矩阵（本轮均未运行）
1. Windows：sync/worker 已 pin 损坏 blob，下载/读取批准源后可修复且旧有效文件从不先删。
2. 多 cache 实例同路径 pin+clear；receiver 取消/完成回调重入；sync root/cache变化与析构释放。
3. cache 根链接、根之上祖先链接、staging 中间链接、RoomAssets 文件链接；Windows junction 单独核验；不修改外部哨兵。
4. 原目标存在时注入 write/flush/readback/rename失败；缓存、配置、recovery JSON均断言旧目标完整。
5. 合法 part/unowned part/link/pinned part，跨进程共享根的清理竞争；清理返回失败需可观察。
6. 创建嵌套目录后注入第二次 fetch/open失败，断言无 staging 残留；中途退出后受控重启回收。
7. 恢复复制预算失败/中途写失败/崩溃，原档保留、半成品可处理、同实例重试不被残留永久卡住。

## 交付
- 创建：`scratch/net-batch-10/cache.md`。
- 修改生产/测试/技能文件：无。
- 执行验证：源文件逐行读取、调用点与测试静态检索；没有运行 Godot，也没有假称运行通过。
