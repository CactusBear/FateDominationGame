# batch24 手选恢复座位 UI（只读交接）

## 交付与边界
- `restore-seat-ui.v4a`：最小候选 V4A，改 3 个既有文件、新增 2 个文件；未应用生产。
- `candidate/**.txt`：与 V4A 完全一致的候选，避免项目内 scratch 被 Godot 扫描出脚本类。
- `baseline.json`：3 个既有目标的 SHA-256 基线；合并前检查。生成器读工作树，不是旧 Git HEAD。
- `interaction.test.mjs` / `red.log`：真实大厅原入口缺少显式映射的 RED；原断言修复后通过。
- `interaction-source.test.mjs` / `green.log` / `results.json`：Node 有限语法转译候选的真实选择、刷新、完整性与提交方法；节点、既有 InputModel、认证候选桥为夹具。18 项通过。元数据与场景接线用源码断言覆盖，不声称已经真实文件/原生窗口交互验收。
- `verify_patch.py` / `patch-check.json`：V4A 在内存按唯一上下文应用，与全部候选逐行相等；生产基线未改。
- gdtoolkit：3 个候选 GDScript 解析通过；不等于 Godot 引擎 API、场景继承或窗口运行通过。

## 代码解释与真实入口
1. 大厅沿原 `ArchivePicker → ArchiveConfirm` 入口，确认后不直接恢复，改为 `RestoreSeatPanel.open_archive`。窗口提交的三个参数完整传给 batch23 `authority_host.restore_local_match(source, selected, metadata_source)`；移除 source-only 的共享恢复后门。数据准备冲突、管理权丢失及空映射拒绝并关闭窗口。每帧刷新上下文，重置/离房关闭。
2. 新场景继承现有 `identity_inheritance_panel.tscn`，保留 Window/VBox/ItemList/反馈/刷新/确认/关闭样式，只增加座位 OptionButton，覆盖说明与按钮文案；新脚本继承现有控制器，复用 `_ready` 输入接线、`_clear_candidates` 和 InputModel.accept/select_member，不修改原继承流程。
3. 座位按选中档的规范 player_id 提供，真人初始均未指定，AI 仅按已验证原档显式绑定 0。逐座选择后下拉项显示“座位 → 当前候选标签”；禁止一人多座，完整覆盖座位全集才开放确认。换映射可刷新重选，不按公钥、昵称或成员号相等自动认领。
4. 原大厅 `member.name` 不能保证昵称重名消歧，因此给 authority_host_client 加一个本机公开候选投影函数，复用已有 `_identity_bridge.snapshot_for` 和 `PlayerRegistry.public_member_labels`，只返回已认证、在线、非观战成员的 `{member_id,label}`。只有重名才附用户名，UI 不接收 key/fingerprint/ticket。这个函数不提交或自动选择座位，私有认证快照不离开 authority_host_client。
5. 本机选中档的唯一元数据路径是 `source/restore-identity.json`，不搜当前 worker recovery.json，不跨档拼接、不提供另选元数据入口、不写原档。先做现有无链接路径检查，再复用 bounded read_metadata、valid_state(required=true)、RecoverySeatJSON.decode；缺文件、日志、认证座位元数据或空/无效座位均中文明确拒绝。
6. 房间修订或成员/连接/权限变化后清空全部真人映射；迟到点击/确认丢弃，避免新列表索引被当成旧选择。提交锁住重复请求并复制完整字典，权威回执返回前不显示已恢复。恢复成功仍沿 batch23 数据 ACK 屏障；拒绝与失败不降级为 source-only 恢复。
7. UI 仅是显式意图入口，不取代 worker 的存档房主密钥、目标密钥、当前认证、房间 revision、请求序号及原子恢复验证。元数据/成员在提交后变化仍由 worker 拒绝，不伪造取消或成功。

## 候选目标
- `scripts/net/ui/lobby_screen.gd`
- `assets/scenes/main_menu/multiplayer_lobby.tscn`
- `scripts/net/session/authority_host_client.gd`（仅新增公开候选投影，不改 batch23 restore API）
- 新增 `scripts/net/identity/restore_seat_panel.gd`
- 新增 `assets/scenes/main_menu/restore_seat_panel.tscn`

## 复验（仓库根执行；不运行 Godot）
```bash
python scratch/net-batch-24/restore-seat-ui/verify_patch.py
node scratch/net-batch-24/restore-seat-ui/interaction.test.mjs
node scratch/net-batch-24/restore-seat-ui/interaction-source.test.mjs
uv run --with gdtoolkit python -c "from pathlib import Path; from gdtoolkit.parser import parser; p=Path('scratch/net-batch-24/restore-seat-ui/candidate'); files=list(p.rglob('*.gd.txt')); [parser.parse(f.read_text(encoding='utf-8')) for f in files]; print('parse PASS',len(files))"
```
不要合并后直接运行 build_patch.py：它以只读当前生产基线生成交接，新入口已存在时会拒绝唯一锚点。生产文件若变化须先重基线审阅，再生成补丁。

## 未执行/剩余验收
遵守禁止项：未运行 Godot，未写生产、未读取凭据文件、未真实提交恢复 IPC。场景继承加载、原生鼠标交互、认证桥时序和多机恢复回执由主代理获准后串行验证；本交付仅给可合并候选与 Node/静态证据。
