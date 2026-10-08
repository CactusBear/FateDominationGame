# 数据路径与缓存安全审计（只读）

范围：数据根切换、路径穿越/边界、Windows/Linux 便携路径、缓存清理、已采用数据、提供者掉线、对局固定副本、恢复目录。未运行 Godot，未改生产文件。

## 明确问题

### P1：恢复发现未校验 `data_root`，可把房间数据根切到房间目录之外
- 证据：`scripts/net/server_room_manager.gd:145-151` 的 `discover_rooms()` 只校验 `id/name/port/directory`，没有校验 `config.data_root` 是否为服务端批准的数据根、是否规范化且位于允许根内。
- 证据：`scripts/net/server_room_worker.gd:29-50` 直接接受配置中的 `data_root`；`79-87` 用它扫描 `selection_modes.json` 与基础文件；`94-114` 将其内容写入房间缓存/固定 `data` 副本并切换 `LoadHelper.session_data_dir`。
- 真实反例：在 `user://server_rooms/<合法房间>/config.json` 保留合法 `id/directory/port/instance_id`，仅把 `data_root` 改成 `C:/Users/Administrator/Documents/other-data`（或 `../../outside` 的规范绝对结果），重启发现仍登记房间；worker 会读取该目录并把其 JSON/图片纳入房间副本。结果是恢复目录边界失效，且可能加载服务端不批准的数据。
- 最小修复：启动/发现共同调用单一 `validate_data_root(candidate, approved_root)`；规范化、拒绝链接/junction，要求 `candidate == approved_root` 或严格位于批准根内；恢复配置中保存并校验 `data_root` 的指纹/相对 ID，而不是接受可编辑绝对路径。非法时保留原目录和恢复文件，不启动 worker。

### P1：本地恢复入口未限制存档源必须位于 `archive_root`
- 证据：`scripts/net/lobby_session.gd:1326-1339` 的 `restore_local_match(source)` 只做角色/房主/阶段检查，然后把用户给出的 `source` 传给 `match_authority.restore_archive()`。
- 证据：`scripts/net/match_authority.gd:426-430` 直接执行 `source.path_join("match.log")`，没有检查 source 的规范绝对路径、是否为 `archive_root` 下的既有目录、是否为链接目录。
- 真实反例：本机文件选择器选择 `C:/temp/foreign-match`（含攻击者准备的合法日志/数据）；该目录不在 `user://match_saves`，但会被读取、恢复并复制到新归档/房间数据流程。最小复现只需 `source = ProjectSettings.globalize_path("C:/temp/foreign-match")` 调用入口。
- 最小修复：在 `restore_local_match` 和 `restore_archive` 两层都做 canonical boundary check；拒绝 source 自身/任一父目录是 link/junction；只接受 `archive_root` 的直接子目录，并要求目录名/`match.log` 清单符合格式。第二层校验防止未来新增调用方绕过 UI。

### P1：组装/校验阶段未 pin 缓存，清理可删除仍在使用的固定副本输入
- 证据：`scripts/net/room_data_preparation.gd:45-85` 多次 `cache.fetch()`，`93-98` 随后组装；`scripts/net/room_data_assembler.gd:18-46` 在预检与逐文件写入间重复读取缓存，但没有 `pin()`。
- 证据：`scripts/net/lobby_screen.gd:605-606` 可直接执行 `cache.clear_unused()`；`content_cache.gd:145-153` 只按共享 pin 判断。
- 真实反例：数据准备/预检尚未完成时点击“清理缓存”：某哈希已完整下载且未被 `BlobReceiver` 在途 pin，清理删除它；下一次 `fetch()` 返回空，组装失败。更坏的是在首次检查后删除，造成 TOCTOU，固定副本无法稳定完成。
- 最小修复：`RoomDataPreparation.start()`/`Assembler.assemble()` 在整个会话期间对 plan 全部 hash 建立 owner-scoped pins，完成/取消/失败 finally 全部释放；清理入口只删除无任何生命周期引用的 blob。将下载完成后的引用交接给 preparation，再释放 receiver pin。

### P2：缓存清理漏删损坏哈希文件和 `.part` 残留，长期可被磁盘耗尽
- 证据：`content_cache.gd:145-153` 只删除 `valid_key(key)` 的完整文件；损坏的 64 hex 文件被保留，随机临时文件 `<hash>.<nonce>.part` 也永远不匹配 `valid_key`。`store()` 失败路径虽删自己的临时文件，但进程崩溃/强杀会留下残留。
- 真实反例：写入 `.part` 后进程退出，或写一个内容错误但文件名仍为 64 位 hex；之后反复点击清理，`removed` 不增加，`usage()` 也不统计这些文件，磁盘增长不可见。
- 最小修复：清理只扫描 cache 根的普通文件，按受控临时文件命名和 mtime/会话锁清理过期 `.part`；对非法/损坏 blob 在无 pin 时移入隔离删除队列并计入 usage/错误；不递归、不跟随链接。

## 已确认为安全/未发现漏洞的边界
- `room_data_assembler.gd:53-91` 已拒绝 `..`、绝对路径、反斜杠、冒号、控制字符、Windows 保留名、尾点/尾空格、扩展名外文件，并以 `to_lower()` 拒绝大小写冲突；文件/目录前缀冲突也有检查。建议把同一校验复用到恢复源与 data_root，而不是另写一套。
- `server_data_approval.gd:42-44,183-187` 已把目录刷新与已建立请求分开；`room_data_preparation.gd:106-113` 不因提供者掉线而使已收齐校验副本失效。当前已采用数据的撤回边界静态上正确，但仍依赖上面的缓存 pin 修复保证副本能完成组装。
- `server_room_worker.gd:101-111` 对已有 `data` 目录逐文件校验后复用，拒绝覆盖不完整/未知残留；这不是对 `data_root` 越界的替代校验。

## 建议验收命令（不运行 Godot）
```bash
# 静态证据
python - <<'PY'
from pathlib import Path
p=Path('scripts/net/server_room_manager.gd').read_text()
assert 'config.get("data_root")' not in p[p.index('func discover_rooms'):p.index('func is_ready')]
print('当前基线应失败：discover_rooms 未校验 data_root')
PY

# 修复后应加入的黑盒夹具（由主代理在 Godot/专项测试环境执行）
# 1) 合法 config + data_root=房间外目录 -> discover/recover 拒绝且原 recovery/config 字节不变
# 2) restore_local_match(archive_root 外目录) -> false，原目录未读/未写
# 3) preparation 运行中 clear cache -> 固定副本仍完成，且全部 pins 在 finally 释放
# 4) 崩溃留下 .part/损坏 blob -> clear_unused 后不再占用/计数
# 5) CON.json、a\b.json、a/../b.json、foo:bar.json、Foo.json+foo.json -> 一律拒绝
```
