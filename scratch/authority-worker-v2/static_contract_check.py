"""Static wiring assertions only; does not emulate Godot or rule execution."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]

class AuthorityWorkerStaticContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manager = (ROOT / 'scripts/net/server_room_manager.gd').read_text(encoding='utf-8')
        cls.worker = (ROOT / 'scripts/net/server_room_worker.gd').read_text(encoding='utf-8')
        cls.bootstrap = (ROOT / 'scripts/net/server_bootstrap.gd').read_text(encoding='utf-8')
        cls.control = (ROOT / 'scripts/net/server_room_control.gd').read_text(encoding='utf-8')

    def test_local_machine_spawn_and_modes(self):
        self.assertIn('AUTHORITY_HOST_MODES = ["lan", "p2p", "dedicated"]', self.manager)
        self.assertEqual(self.manager.count('OS.create_process(OS.get_executable_path()'), 2)
        self.assertIn('"authority_host_mode":authority_host_mode', self.manager)
        self.assertIn('"127.0.0.1"', self.worker)

    def test_identity_and_signals_preserved(self):
        for value in ['_system_signals.protect_worker()', '_gateway_identity_required', 'session._identity_binding_required = identity_required', '_system_signals.disable()']:
            self.assertIn(value, self.worker)

    def test_ready_bound_generation_and_capabilities(self):
        for value in ['"room_id":config.id', '"instance_id":_control.instance_id', '"authority_host_mode":_authority_host_mode', '"capabilities":_capabilities()']:
            self.assertIn(value, self.worker)
        self.assertIn('report.get("pid") == room.pid', self.manager)
        self.assertIn('report.get("instance_id") == room.instance_id', self.manager)
        self.assertIn('report.get("authority_host_mode") == room.authority_host_mode', self.manager)
        self.assertIn('"process_restart_is_rollback":false', self.worker)
        self.assertIn('EffectManager.can_rollback_runtime_guard()', self.worker)

    def test_control_reuses_bound_instance(self):
        self.assertIn('_control.instance_id = config.instance_id', self.worker)
        self.assertIn('request.get("pid") == OS.get_process_id()', self.control)
        self.assertIn('request.get("instance") == instance_id', self.control)
        self.assertIn('matches_instance(room, expected_pid, expected_instance_id)', self.manager)
        self.assertIn('matches_instance(rooms[id], expected_pid, expected_instance_id)', self.manager)

    def test_heartbeat_binds_both(self):
        self.assertIn('"pid":room.pid, "instance_id":room.instance_id', self.manager)
        self.assertIn('pulse.get("pid") == OS.get_process_id()', self.worker)
        self.assertIn('pulse.get("instance_id") == _control.instance_id', self.worker)

    def test_ready_removed_before_recovery_spawn(self):
        recovery = self.manager.split('func recover_room(', 1)[1].split('func _write_supervisor', 1)[0]
        self.assertLess(recovery.index('DirAccess.remove_absolute(ready_path)'), recovery.index('OS.create_process('))
        self.assertIn('engine.%s.log', recovery)
        self.assertNotIn('recovery.json', recovery)
        self.assertNotIn('remove_dir', recovery)
        cleanup = self.worker.split('func _exit_tree()', 1)[1]
        self.assertLess(cleanup.index('report.get("instance_id") == _control.instance_id'), cleanup.index('DirAccess.remove_absolute(path)'))

    def test_logs_do_not_gate_transport(self):
        poll = self.manager.split('func poll()', 1)[1].split('func discover_rooms()', 1)[0]
        self.assertNotIn('"ERROR:" in', poll)
        self.assertNotIn('"SCRIPT ERROR" in', poll)
        self.assertNotIn('log_file', poll)

    def test_signaling_only_no_authority_construction(self):
        signaling = self.bootstrap.split('func _start_signaling(', 1)[1]
        self.assertIn('configuration.get("roles") != ["relay"]', signaling)
        self.assertIn('"rules_authority_started":false', signaling)
        for value in ['server_gateway.gd', 'server_room_manager.gd', 'lobby_session.gd', 'match_authority.gd', 'LoadGame']:
            self.assertNotIn(value, signaling)
        self.assertIn('p2p_signal_server.gd', signaling)

    def test_audit_independent_of_match_recording(self):
        self.assertIn('if not session.record_matches:', self.worker)
        self.assertIn('begin_audit(_directory.path_join("transactions.%s.log"', self.worker)
        self.assertIn('end_audit(_audit_journal)', self.worker)
        self.assertIn('"transaction_audit_persistence_enabled":session.record_matches or _audit_journal != null', self.worker)

    def test_signaling_snapshot_has_no_rule_autoload(self):
        stage = ROOT / 'scratch/authority-worker-v2/signaling-project'
        self.assertNotIn('\n[autoload]\n', (stage / 'project.godot').read_text(encoding='utf-8'))
        self.assertFalse((stage / 'scripts/system').exists())
        self.assertFalse((stage / 'scripts/net/server_gateway.gd').exists())
        self.assertFalse((stage / 'scripts/net/server_room_worker.gd').exists())

    def test_gateway_merge_candidate_generation_binding(self):
        gateway = (ROOT / 'scratch/authority-worker-v2/server_gateway.merge_candidate.gd').read_text(encoding='utf-8')
        self.assertIn('var _pending_instances:Dictionary', gateway)
        self.assertIn('var _creator_instances:Dictionary', gateway)
        self.assertIn('route.pid, route.instance_id', gateway)
        self.assertIn('manager.recover_room(args.room, int(manager.rooms[args.room].pid), str(manager.rooms[args.room].instance_id))', gateway)
        self.assertIn('manager.stop_room(id,int(expected.get("pid",-2)),str(expected.get("instance_id","")))', gateway)

    def test_no_single_float_or_truncation_validation(self):
        self.assertIn('_valid_integer(config.get("port"), 1, 65535)', self.worker)
        self.assertIn('floor(float(value)) == value', self.worker)
        self.assertNotIn('config.get("port") is float', self.worker)

if __name__ == '__main__':
    unittest.main(verbosity=2)
