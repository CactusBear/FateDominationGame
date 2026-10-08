"""Source-contract tests only; not a substitute for GDScript execution."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
CONSOLE = (ROOT / 'scripts/net/server_console_channel.gd').read_text(encoding='utf-8')
GATEWAY = (ROOT / 'scripts/net/server_gateway.gd').read_text(encoding='utf-8')
MIGRATION = (ROOT / 'scripts/net/legacy_identity_migration.gd').read_text(encoding='utf-8')
BLOCK = GATEWAY.split('func console_legacy_migration(', 1)[1].split('\nfunc ', 1)[0]

class Contracts(unittest.TestCase):
    def test_local_only(self):
        self.assertIn('admin_console.execute(message.args.command,false)', GATEWAY)
        self.assertIn('and not trusted_local:', CONSOLE)
        self.assertLess(CONSOLE.index('and not trusted_local:'), CONSOLE.index('commands[command].handler.call(arguments)'))
    def test_command_arity(self):
        self.assertIn('"room legacy-approve":{"arguments":5', CONSOLE)
        self.assertIn('"room legacy-reject":{"arguments":3', CONSOLE)
        self.assertIn('marker != "legacy_approved"', MIGRATION)
    def test_authenticated_mapping(self):
        self.assertIn('authenticated_identities.get(connection,"")', BLOCK)
        self.assertIn('identity_registry.can_access(key)', BLOCK)
        self.assertIn('selected.size() != members.size()', BLOCK)
        self.assertIn('used_keys.has(key)', BLOCK)
    def test_instance_scope(self):
        self.assertIn('manager.matches_instance(room,pid,instance_id)', BLOCK)
        self.assertIn('OS.is_process_running(pid)', BLOCK)
        self.assertIn('parser.data.get("id") != room_id', BLOCK)
        self.assertIn('parser.data.get("authority_host_mode")', BLOCK)
    def test_persist_before_private_send(self):
        self.assertLess(BLOCK.index('migration.commit('), BLOCK.index('_send_client(connection,prepared.private_tickets[member]'))
        self.assertIn('if not committed.ok: return committed', BLOCK)
        reply = BLOCK.split('return {"ok":failed == 0', 1)[1]
        for forbidden in ('token', 'private_tickets', 'approved', 'profiles', 'key'):
            self.assertNotIn(forbidden, reply)
    def test_safe_atomic_replace(self):
        self.assertIn('[System.IO.File]::Replace', MIGRATION)
        self.assertIn('FileAccess.get_file_as_bytes(path) != original', MIGRATION)
        self.assertIn('FileAccess.get_file_as_bytes(path) != encoded', MIGRATION)
        windows = MIGRATION.split('if OS.get_name() == "Windows":', 1)[1].split('\n\telse:', 1)[0]
        self.assertNotIn('rename_absolute', windows)
        self.assertNotIn('migrate_legacy_file', BLOCK)
    def test_no_auto_claim_or_sensitive_audit(self):
        for line in BLOCK.splitlines():
            if 'print(' in line:
                self.assertNotIn('key', line)
                self.assertNotIn('token', line)
                self.assertNotIn('selected', line)
        self.assertNotIn('recover_room(', BLOCK)
        self.assertIn('if not legacy_approved:', BLOCK)
    def test_parser_guards(self):
        for guard in ('not member is String', 'str(member.to_int()) != member', 'connections.has(int(connection))', 'not Bindings.valid_counter(connection)'):
            self.assertIn(guard, MIGRATION)

if __name__ == '__main__':
    unittest.main(verbosity=2)
