"""Source assertions only: never executes Godot or models network success."""
from pathlib import Path
import argparse
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
SOURCES = {
    key: ROOT / 'scripts/net/p2p' / name
    for key, name in [('client', 'p2p_signal_client.gd'), ('server', 'p2p_signal_server.gd'), ('invite', 'p2p_invite.gd')]
}
TEXT = {key: path.read_text(encoding='utf-8') for key, path in SOURCES.items()}

def function(key, name):
    match = re.search(r'^func ' + re.escape(name) + r'\([^\n]*\n(.*?)(?=^func |\Z)', TEXT[key], re.M | re.S)
    return match.group(1) if match else ''

class StaticBoundaries(unittest.TestCase):
    def test_closed_signal_uses_terminal_cleanup(self):
        poll = function('client', 'poll')
        branch = poll.split('if _socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:')[1].split('if _deadline')[0]
        self.assertIn('_fail_signaling(', branch)

    def test_terminal_cleanup_preserves_established_link(self):
        body = function('client', '_fail_signaling')
        self.assertIn('invite.cancel_offer(', body)
        self.assertIn('_pending.clear()', body)
        self.assertIn('not session.transport.is_connected_to_host()', body)
        self.assertIn('session.transport.close()', body)
        self.assertIn('_socket = null', body)

    def test_host_keeps_answered_peer_until_ice_connected(self):
        receive = function('client', '_receive')
        answer = receive.split('\n\t\t"answer":')[1].split('\n\t\t"error"')[0]
        self.assertNotIn('_pending.erase(', answer)
        self.assertIn('.answered = true', answer)
        self.assertIn('invite.is_connected(pending.peer_id)', function('client', 'poll'))

    def test_cancel_offer_guards_connection_not_answer_consumption(self):
        body = function('invite', 'cancel_offer')
        self.assertNotIn('_pending[id].consumed', body)
        self.assertIn('is_connected(id)', body)

    def test_create_ack_precedes_registration(self):
        body = function('server', '_handle').split('\n\t\t"create":')[1].split('\n\t\t"join":')[0]
        self.assertIn('if _send(', body)
        self.assertLess(body.index('if _send('), body.index('_rooms[code] ='))
        self.assertIn('_remove(id)', body)

    def test_join_notification_precedes_registration(self):
        body = function('server', '_handle').split('\n\t\t"join":')[1].split('\n\t\t"offer":')[0]
        self.assertIn('if _send(', body)
        self.assertLess(body.index('if _send('), body.index('client.room ='))
        self.assertIn('_remove(id)', body)

    def test_sliding_window_replaces_fixed_second_bucket(self):
        body = function('server', '_allow_message')
        self.assertIn('now - 1000', body)
        self.assertIn('<= cutoff', body)
        self.assertIn('timestamps.size() >= max_messages_per_second', body)
        self.assertNotIn('client.second', TEXT['server'])
        self.assertIn('not _allow_message(client, Time.get_ticks_msec())', function('server', 'poll'))

    def test_sdp_candidates_reject_whitespace_relay_bypass(self):
        body = function('invite', '_direct_description')
        self.assertIn('replace(String.chr(9), " ")', body)
        self.assertIn('link._direct_candidate(', body)
        self.assertIn('not _direct_description(data.sdp)', function('invite', '_read'))

    def test_partial_answer_failure_destroys_peer(self):
        body = function('invite', 'accept_answer')
        self.assertIn('link.remove_peer(int(data.from))', body)
        self.assertIn('_pending.erase(int(data.from))', body)
        self.assertIn('item.consumed', body)

    def test_completed_join_request_cannot_allocate_second_peer(self):
        self.assertIn('_joined_clients.has(int(message.client))', function('client', '_receive'))
        self.assertIn('_joined_clients[client] = pending.peer_id', function('client', 'poll'))
        self.assertIn('_joined_clients.clear()', function('client', 'close'))

    def test_duplicate_and_authority_boundaries(self):
        self.assertIn('_pending.has(int(message.client))', function('client', '_receive'))
        self.assertIn('client.answered', function('server', '_handle'))
        self.assertIn('"game_forwarding": false', TEXT['client'])
        self.assertIn('"game_forwarding": false', TEXT['server'])
        link = (ROOT / 'scripts/net/transport/webrtc_link.gd').read_text(encoding='utf-8')
        self.assertIn('not url.begins_with("stun:")', link)
        self.assertIn('server.keys() != ["urls"]', link)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--record', default='static-results.json')
    parser.add_argument('--snapshot', action='store_true')
    args = parser.parse_args()
    if args.snapshot:
        for key, path in SOURCES.items():
            target = HERE / 'before' / (path.name + '.txt')
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(path.read_bytes())
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(StaticBoundaries))
    (HERE / args.record).write_text(json.dumps({'scope': 'source assertions only; no Godot/network execution', 'tests': result.testsRun, 'failures': len(result.failures), 'errors': len(result.errors), 'successful': result.wasSuccessful()}, ensure_ascii=False, indent=2), encoding='utf-8')
    raise SystemExit(0 if result.wasSuccessful() else 1)
