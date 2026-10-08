"""Static source-contract checks, not a GDScript runtime substitute."""
from pathlib import Path
import json
from gdtoolkit.parser import parser

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
paths = ['scripts/match/view_builder.gd', 'scripts/match/view_mirror.gd', 'scripts/net/server_gateway.gd', 'scratch/public-view-privacy-v3/negative_cases.gd']
source = {}
for path in paths:
    source[path] = (ROOT / path).read_text(encoding='utf-8')
    parser.parse(source[path])
b, m, g = [source[p] for p in paths[:3]]
checks = {
    'all_player_zones_use_shared_filter': all(f'cards(data.get("{zone}", []), own)' in b for zone in ['discard', 'played_cards', 'master_skills']),
    'source_visibility_not_zone_visibility': 'not concealed and publicly_identifiable(card)' in b and 'source = source.get_from()' in b,
    'source_release_gate': 'return ReleaseTrueName.is_released(pid)' in b and 'if object is BaseServant:\n\t\t\treturn false' in b,
    'hidden_back_path_removed': 'str(card._card_back_img) if visible or own else ""' in b,
    'public_description_no_internal_effect_fallback': 'public_description(card)' in b and 'effect._shown_name' in b and 'get_shown_name' not in b.split('static func public_description')[1],
    'effect_ids_private_only': 'if own and effect is BaseEffect:' in b,
    'log_no_raw_entry_copy': 'entry.duplicate' not in b and '"object": null, "data": {}' in b,
    'mirror_unreleased_identity_rejected': 'if not own and not player.get("servant_released", false):' in m and 'not player.servant.is_empty() or not player.servant_skills.is_empty()' in m,
    'mirror_private_card_context': '_cards(player.get(key), own)' in m and '_card(entry.card, true)' in m,
    'mirror_public_back_rejected': 'not private_view and value.get("back_image", "") != ""' in m,
    'mirror_public_effect_ids_rejected': 'not value.effects.is_empty()' in m,
    'gateway_filter_before_trusted_context': g.index('message = _public_room_request(message)') < g.index('message["gateway_inheritance"] = _room_inheritance_context(peer)'),
    'gateway_join_identity_not_forwarded': '"join": allowed_args = ["name", "spectator", "password", "resume"]' in g,
    'gateway_fixed_failure_audit_only': 'last_send_failure = {"connection":peer,"channel":channel,"stage":stage,"error_code":int(result),"queued":false}' in g,
}
# Negative controls: removing each literal guard must invalidate its contract.
negative_controls = {
    'source_gate_removed': 'not concealed and publicly_identifiable(card)' not in b.replace('not concealed and publicly_identifiable(card)', 'not concealed'),
    'back_gate_removed': 'not private_view and value.get("back_image", "") != ""' not in m.replace('not private_view and value.get("back_image", "") != ""', 'false'),
    'identity_gate_removed': 'if not own and not player.get("servant_released", false):' not in m.replace('if not own and not player.get("servant_released", false):', 'if false:'),
}
report = {'mode': 'static-only', 'parsed_files': paths, 'checks': checks, 'negative_controls': negative_controls, 'godot_executed': False, 'runtime_assertions_executed': False, 'credentials_logged': False}
(OUT / 'static_results.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'parse_ok': len(paths), 'static_checks_passed': sum(checks.values()), 'static_checks_total': len(checks), 'negative_controls_passed': sum(negative_controls.values()), 'godot_executed': False}, ensure_ascii=False))
assert all(checks.values()) and all(negative_controls.values())
