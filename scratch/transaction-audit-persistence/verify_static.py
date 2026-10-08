"""静态契约负对照；不运行 Godot，也不模拟 GDScript 业务行为。"""
from pathlib import Path
import json
from gdtoolkit.parser import parser

ROOT = Path(__file__).resolve().parents[2]
FILES = ["scripts/match/match_journal.gd", "scripts/match/match_replay.gd", "scripts/net/match_authority.gd", "scratch/transaction-audit-persistence/audit_persistence_test.gd"]
sources = {name: (ROOT / name).read_text(encoding="utf-8") for name in FILES}
for name, source in sources.items():
    parser.parse(source)
    print("PARSE_OK", name)
journal = sources[FILES[0]]
replay = sources[FILES[1]]
authority = sources[FILES[2]]
checks = {
    "namespace": lambda j, r, a: 'generate_random_bytes(32)' in j and '"transaction_id":transaction_id' in j,
    "capacity": lambda j, r, a: '_file.get_length() + 36 + body.size() > max_total_bytes' in j,
    "reason": lambda j, r, a: 'safe.reason not in AUDIT_REASONS' in j and 'safe.reason = "redacted"' in j and '"random_digest"' not in j,
    "lease": lambda j, r, a: 'DirAccess.make_dir_absolute(lease)' in j and '_audit_mutex.lock()' in j,
    "idempotency": lambda j, r, a: '_append_receipts.has(receipt_key)' in j and '_audit_receipts.has(key)' in j,
    "full_audit_copy": lambda j, r, a: 'verified.records != parsed.records.slice' not in r and 'for index in range(1, parsed.records.size()):' in r,
    "rollback_gate": lambda j, r, a: 'if not audit.flush_audit()' in a and '事务审计写入失败，回滚未确认' in a,
}
assert all(fn(journal, replay, authority) for fn in checks.values())
mutations = {
    "namespace": (journal.replace('generate_random_bytes(32)', 'generate_random_bytes(8)'), replay, authority),
    "capacity": (journal.replace('_file.get_length() + 36 + body.size() > max_total_bytes', 'false'), replay, authority),
    "reason": (journal.replace('safe.reason = "redacted"', 'safe.reason = metadata.reason'), replay, authority),
    "lease": (journal.replace('DirAccess.make_dir_absolute(lease)', 'OK'), replay, authority),
    "idempotency": (journal.replace('_append_receipts.has(receipt_key)', 'false'), replay, authority),
    "full_audit_copy": (journal, replay.replace('verified.records != parsed.records', 'verified.records != parsed.records.slice(0, _restored_audit_revision + 1)'), authority),
    "rollback_gate": (journal, replay, authority.replace('if not audit.flush_audit()', 'if false')),
}
for name, candidate in mutations.items():
    assert not checks[name](*candidate), f"负对照未检测: {name}"
    print("STATIC_NEGATIVE_DETECTED", name)
result = {"parsed_files": FILES, "static_contracts": list(checks), "negative_controls_detected": list(mutations), "godot_executed": False, "behavioral_red_green_verified": False}
(ROOT / "scratch/transaction-audit-persistence/static_verification.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
print("STATIC_CONTRACTS_OK; NOT_GODOT_RUNTIME")
