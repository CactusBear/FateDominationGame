from pathlib import Path
import shutil

ROOT = Path(r"E:/Projects/Godot/FateDominationGame-master")
NET = ROOT / "scripts" / "net"
MAPPING = {
    "webrtc_link.gd": "transport/webrtc_link.gd",
    "enet_transport.gd": "transport/enet_transport.gd",
    "packet_fragments.gd": "transport/packet_fragments.gd",
    "catalog_message_transfer.gd": "transport/catalog_message_transfer.gd",
    "room_manifest_transfer.gd": "transport/room_manifest_transfer.gd",
    "p2p_invite.gd": "p2p/p2p_invite.gd",
    "p2p_signal_client.gd": "p2p/p2p_signal_client.gd",
    "p2p_signal_server.gd": "p2p/p2p_signal_server.gd",
    "player_identity.gd": "identity/player_identity.gd",
    "player_name_rules.gd": "identity/player_name_rules.gd",
    "player_registry.gd": "identity/player_registry.gd",
    "member_identity_bindings.gd": "identity/member_identity_bindings.gd",
    "room_password.gd": "identity/room_password.gd",
    "identity_inheritance_input.gd": "identity/identity_inheritance_input.gd",
    "identity_inheritance_panel.gd": "identity/identity_inheritance_panel.gd",
    "legacy_identity_migration.gd": "identity/legacy_identity_migration.gd",
    "lobby_session.gd": "session/lobby_session.gd",
    "room_state.gd": "session/room_state.gd",
    "authority_host_client.gd": "session/authority_host_client.gd",
    "match_authority.gd": "authority/match_authority.gd",
    "selection_authority.gd": "authority/selection_authority.gd",
    "blob_receiver.gd": "content/blob_receiver.gd",
    "content_cache.gd": "content/content_cache.gd",
    "data_catalog.gd": "content/data_catalog.gd",
    "room_assets.gd": "content/room_assets.gd",
    "room_data_assembler.gd": "content/room_data_assembler.gd",
    "room_data_plan.gd": "content/room_data_plan.gd",
    "room_data_sync.gd": "content/room_data_sync.gd",
    "room_data_preparation.gd": "validation/room_data_preparation.gd",
    "room_data_validator.gd": "validation/room_data_validator.gd",
    "room_data_validation_worker.gd": "validation/room_data_validation_worker.gd",
    "room_validation_task.gd": "validation/room_validation_task.gd",
    "rule_loop_analysis.gd": "validation/rule_loop_analysis.gd",
    "rule_random_simulation.gd": "validation/rule_random_simulation.gd",
    "server_bootstrap.gd": "server/server_bootstrap.gd",
    "server_cli.gd": "server/server_cli.gd",
    "server_command_line.gd": "server/server_command_line.gd",
    "server_gateway.gd": "server/server_gateway.gd",
    "server_room_manager.gd": "server/server_room_manager.gd",
    "server_room_worker.gd": "server/server_room_worker.gd",
    "server_room_control.gd": "server/server_room_control.gd",
    "server_console.gd": "server/server_console.gd",
    "server_console_channel.gd": "server/server_console_channel.gd",
    "server_shutdown.gd": "server/server_shutdown.gd",
    "server_process_signals.gd": "server/server_process_signals.gd",
    "server_policy_config.gd": "server/server_policy_config.gd",
    "server_data_approval.gd": "server/server_data_approval.gd",
    "recovery_path_safety.gd": "server/recovery_path_safety.gd",
    "lobby_screen.gd": "ui/lobby_screen.gd",
    "room_data_panel.gd": "ui/room_data_panel.gd",
    "network_choice_panel.gd": "ui/network_choice_panel.gd",
    "network_hand_strip.gd": "ui/legacy/network_hand_strip.gd",
    "group_selection.gd": "ui/group_selection.gd",
    "v2_view_presenter.gd": "ui/v2_view_presenter.gd",
}

old_files = sorted(p.name for p in NET.glob("*.gd"))
if set(old_files) != set(MAPPING):
    missing = sorted(set(old_files) - set(MAPPING))
    extra = sorted(set(MAPPING) - set(old_files))
    raise SystemExit(f"mapping mismatch missing={missing} extra={extra}")

# Update active project text references before moving resources.
replacements = {f"res://scripts/net/{old}": f"res://scripts/net/{new}" for old, new in MAPPING.items()}
text_exts = {".gd", ".tscn", ".godot", ".cfg", ".json", ".md", ".py", ".txt"}
updated = []
for path in ROOT.rglob("*"):
    if not path.is_file() or path.suffix.lower() not in text_exts:
        continue
    rel = path.relative_to(ROOT).as_posix()
    if rel.startswith((".git/", ".godot/", "scratch/", "test/")):
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue
    new_text = text
    for old, new in replacements.items():
        new_text = new_text.replace(old, new)
    if new_text != text:
        path.write_text(new_text, encoding="utf-8", newline="")
        updated.append(rel)

moved = []
for old, new in MAPPING.items():
    source = NET / old
    target = NET / new
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(source), str(target))
    moved.append(new)
    uid = source.with_suffix(source.suffix + ".uid")
    if uid.exists():
        shutil.move(str(uid), str(target.with_suffix(target.suffix + ".uid")))

print(f"moved={len(moved)} updated_references={len(updated)}")
print("moved_files:")
for item in moved:
    print(item)
print("updated_files:")
for item in updated:
    print(item)
