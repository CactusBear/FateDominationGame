from pathlib import Path
import difflib, hashlib, json
root = Path('E:/Projects/Godot/FateDominationGame-master')
out = root / 'scratch/net-batch-24/restore-seat-ui'
changes = {}
def replace(text, old, new):
    assert text.count(old) == 1, old
    return text.replace(old, new)
p = 'scripts/net/ui/lobby_screen.gd'
old = (root / p).read_text(encoding='utf-8')
text = replace(old, '$ArchiveConfirm.confirmed.connect(_restore_archive)', '$ArchiveConfirm.confirmed.connect(_prepare_archive_restore)\n\t$RestoreSeatPanel.restore_selected.connect(_restore_archive)')
text = replace(text, '\t$IdentityInheritancePanel.refresh_context()\n\t$Margin/Content/Actions/InheritIdentity.disabled', '\t$IdentityInheritancePanel.refresh_context()\n\t$RestoreSeatPanel.refresh_context()\n\t$Margin/Content/Actions/InheritIdentity.disabled')
a = text.index('func _restore_archive() -> void:')
b = text.index('\nfunc _join()', a)
text = text[:a] + '''func _prepare_archive_restore() -> void:
	if _selected_archive.is_empty(): return
	var source:String = _selected_archive
	_selected_archive = ""
	var reason:String = $RestoreSeatPanel.open_archive(session, source)
	if not reason.is_empty(): status.text = reason

func _restore_archive(source:String, selected:Dictionary, metadata_source:String) -> void:
	if $RoomDataPanel._preparing or $RoomDataPanel._validation.running or _data_sync.running:
		status.text = "请先完成或取消当前数据准备"
		$RestoreSeatPanel.restore_finished()
		return
	if not $RestoreSeatPanel.can_restore(session) or selected.is_empty():
		status.text = "恢复权限或座位映射已失效，请重新选择存档"
		$RestoreSeatPanel.restore_finished()
		return
	status.text = "正在校验存档并等待权威恢复回执"
	var restored:bool = await session.authority_host.restore_local_match(source, selected, metadata_source)
	status.text = "存档已恢复并另存，等待客机完成数据同步" if restored else session.error
	$RestoreSeatPanel.restore_finished()
''' + text[b:]
text = replace(text, '\t$IdentityInheritancePanel.close_panel()\n\t$RoomDataPanel.reset_selection()', '\t$IdentityInheritancePanel.close_panel()\n\t$RestoreSeatPanel.close_panel()\n\t$RoomDataPanel.reset_selection()')
changes[p] = (old, text)
p = 'assets/scenes/main_menu/multiplayer_lobby.tscn'
old = (root/p).read_text(encoding='utf-8')
text = replace(old, '[gd_scene load_steps=4 format=3]', '[gd_scene load_steps=5 format=3]')
text = replace(text, '[node name="MultiplayerLobby" type="Control"]', '[ext_resource type="PackedScene" path="res://assets/scenes/main_menu/restore_seat_panel.tscn" id="4"]\n\n[node name="MultiplayerLobby" type="Control"]')
text = replace(text, '[node name="ArchivePicker" type="FileDialog" parent="."]', '[node name="RestoreSeatPanel" parent="." instance=ExtResource("4")]\n\n[node name="ArchivePicker" type="FileDialog" parent="."]')
text = replace(text, 'ok_button_text = "恢复并另存续写"', 'ok_button_text = "下一步：指定座位"')
text = replace(text, '请先让原来的真人加入，真人与 AI 座位类型必须一致。', '下一步逐座手选在线玩家；必须具有选中档本机认证座位元数据。')
changes[p] = (old, text)
p = 'scripts/net/session/authority_host_client.gd'
old = (root/p).read_text(encoding='utf-8')
text = replace(old, 'func diagnostics() -> Dictionary:', '''## 仅本机UI公开候选投影；不选择恢复座位，不返回身份键或恢复凭据。
func restore_member_candidates() -> Array:
	var session = _session.get_ref() if _session != null else null
	if session == null or not session.identity_authenticated or not _identity_bridge.confirmed: return []
	var target:Dictionary = gateway.manager.instance_binding(room_id)
	var snapshot:Dictionary = _identity_bridge.snapshot_for(gateway, target, session)
	if snapshot.is_empty(): return []
	var members:Dictionary = {}
	for member in session.view.get("members", []):
		if member.get("connected") == true and member.get("spectator") == false:
			members[int(member.id)] = {"name":member.name}
	var identities:Dictionary = {}
	for connection in snapshot.connections.values():
		if members.has(connection.member): identities[str(connection.member)] = connection.key
	return preload("res://scripts/net/identity/player_registry.gd").public_member_labels(members, identities, snapshot.profiles)

func diagnostics() -> Dictionary:''')
changes[p] = (old, text)
for p, (old, text) in list(changes.items()):
    dest = out/'candidate'/(p+'.txt')
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(text, encoding='utf-8')
for p in ['scripts/net/identity/restore_seat_panel.gd', 'assets/scenes/main_menu/restore_seat_panel.tscn']:
    changes[p] = (None, (out/'candidate'/(p+'.txt')).read_text(encoding='utf-8'))
patch = ['*** Begin Patch']
manifest = {}
for p, (old, text) in changes.items():
    if old is None:
        patch.append('*** Add File: '+p)
        patch.extend('+'+line for line in text.splitlines())
    else:
        patch.append('*** Update File: '+p)
        diff = list(difflib.unified_diff(old.splitlines(), text.splitlines(), n=3, lineterm=''))
        patch.extend('@@' if line.startswith('@@') else line for line in diff[2:])
        manifest[p] = hashlib.sha256((root/p).read_bytes()).hexdigest()
patch.append('*** End Patch')
(out/'restore-seat-ui.v4a').write_text('\n'.join(patch)+'\n', encoding='utf-8')
(out/'baseline.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
print(json.dumps({'targets':list(changes), 'production_writes':0, 'v4a':str(out/'restore-seat-ui.v4a')},ensure_ascii=False))
