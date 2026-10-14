"""Targeted B24 source-binding tests; no repository-wide scan or report writes."""
import hashlib
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    'classify_player_data_calls', ROOT / 'tools/classify_player_data_calls.py')
b24 = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(b24)
TACTICAL = 'scripts/game_scene/tactical_board_ui.gd'
OLD_SHA = '9c9d61642bf619c4012fced2b0244eebe89cf642be700f4418be82a0e4522ed9'
NEW_SHA = '3063aca824df5c4561cf08588c4e77d14588a3777e48397d33823e5b6a15acda'
MIGRATIONS = {
    3476: '_class_shown',
    4149: '_refresh_ai_play_prompt',
    4292: '_update_ai_play_prompt_geometry',
}
SURVIVING = {281, 284, 514, 530, 605, 768, 857, 1454, 2407, 2461,
             2588, 2590, 2598, 2601, 3645}
FOLLOWUP = {678, 956, 1195, 1364, 4352}
UNKNOWN = set()


class TacticalSourceBindingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.raw = (ROOT / TACTICAL).read_bytes()
        cls.digest = hashlib.sha256(cls.raw).hexdigest()
        cls.source = cls.raw.decode('utf-8-sig')
        cls.calls, _ = b24.scan_source(cls.source)
        cls.hashes = {TACTICAL: cls.digest}
        for path in ('scripts/system/global/game_data_manager.gd',
                     'scripts/main_menu/game_start.gd',
                     'scripts/system/global/game_data.gd',
                     'scripts/system/global/effect_manager.gd'):
            cls.hashes[path] = hashlib.sha256((ROOT / path).read_bytes()).hexdigest()

    def test_binding_preserves_only_unchanged_review_anchors(self):
        # Exact old-file identity proves that no other source was re-signed.
        old_raw = self.raw.replace(b'find_player_data', b'get_player_data')
        self.assertEqual(hashlib.sha256(old_raw).hexdigest(), OLD_SHA)
        self.assertEqual(self.digest, NEW_SHA)
        self.assertEqual(b24.HASHES[TACTICAL], self.digest)
        old_calls, _ = b24.scan_source(old_raw.decode('utf-8-sig'))
        old_by_line = {call['line']: call for call in old_calls}
        by_line = {call['line']: call for call in self.calls}
        self.assertEqual(set(old_by_line) - set(by_line), set(MIGRATIONS))
        anchors = {line for path, line in b24.REVIEWS if path == TACTICAL}
        self.assertEqual(anchors, SURVIVING | FOLLOWUP)
        for line in anchors:
            with self.subTest(line=line):
                self.assertEqual(old_by_line[line], by_line[line])
                result = b24.review_call(TACTICAL, by_line[line], self.digest, self.hashes)
                self.assertEqual(result['classification'], '只读')
                self.assertEqual(result['review_status'], '人工源码审阅')

    def test_three_migrated_find_calls_are_excluded_not_moved(self):
        old_calls, _ = b24.scan_source(
            self.raw.replace(b'find_player_data', b'get_player_data').decode('utf-8-sig'))
        old_by_line = {call['line']: call for call in old_calls}
        lines = self.source.splitlines()
        for line, function in MIGRATIONS.items():
            with self.subTest(function=function):
                self.assertEqual(old_by_line[line]['function'], function)
                self.assertIn('GameDataManager.find_player_data(', lines[line - 1])
                self.assertFalse(any(call['function'] == function for call in self.calls))
        self.assertEqual(self.raw.count(b'find_player_data'), len(MIGRATIONS))
        self.assertEqual(self.calls, [call for call in old_calls
                                     if call['line'] not in MIGRATIONS])

    def test_followup_reviews_cover_the_five_actual_call_sites(self):
        self.assertEqual({call['line'] for call in self.calls}, SURVIVING | FOLLOWUP)
        for call in self.calls:
            if call['line'] in FOLLOWUP:
                with self.subTest(line=call['line']):
                    result = b24.review_call(TACTICAL, call, self.digest, self.hashes)
                    self.assertEqual(result['classification'], '只读')
                    self.assertEqual(result['review_status'], '人工源码审阅')
                    self.assertTrue(result['decision_basis'])
                    self.assertEqual(result['missing_information'], '')

    def test_existing_creation_call_keeps_creation_classification(self):
        path = 'tests/net_round_identity_feedback_test.gd'
        raw = (ROOT / path).read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        calls, _ = b24.scan_source(raw.decode('utf-8-sig'))
        call = next(call for call in calls if call['line'] == 9)
        result = b24.review_call(path, call, digest, {**self.hashes, path: digest})
        self.assertEqual(result['classification'], '需创建')
        self.assertEqual(result['review_status'], '人工源码审阅')

    def test_source_redrift_revokes_every_surviving_review(self):
        # Even an unrelated appended comment revokes the whole-file evidence.
        digest = hashlib.sha256(self.raw + b'\n# later drift\n').hexdigest()
        hashes = {**self.hashes, TACTICAL: digest}
        for call in self.calls:
            if call['line'] in SURVIVING:
                with self.subTest(line=call['line']):
                    result = b24.review_call(TACTICAL, call, digest, hashes)
                    self.assertEqual(result['classification'], '无法判定')
                    self.assertEqual(result['review_status'], '证据漂移待复审')
                    self.assertEqual(result['evidence'], [])

    def test_dependency_redrift_still_revokes_reviews(self):
        call = next(call for call in self.calls if call['line'] == 281)
        for path in ('scripts/system/global/game_data_manager.gd',
                     'scripts/main_menu/game_start.gd', 'scripts/system/global/game_data.gd'):
            with self.subTest(dependency=path):
                hashes = {**self.hashes, path: hashlib.sha256(b'changed').hexdigest()}
                result = b24.review_call(TACTICAL, call, self.digest, hashes)
                self.assertEqual(result['classification'], '无法判定')
                self.assertEqual(result['review_status'], '证据漂移待复审')

    def test_new_call_on_former_anchor_cannot_inherit_review(self):
        lines = self.source.splitlines(keepends=True)
        lines[279 - 1] = '\t\tGameDataManager.get_player_data(999)\n'
        source = ''.join(lines)
        digest = hashlib.sha256(source.encode('utf-8')).hexdigest()
        calls, _ = b24.scan_source(source)
        call = next(call for call in calls if call['line'] == 279)
        result = b24.review_call(TACTICAL, call, digest, {**self.hashes, TACTICAL: digest})
        self.assertEqual(result['classification'], '无法判定')
        self.assertEqual(result['review_status'], '待人工追踪')
        self.assertEqual(result['evidence'], [])


class StaticHandoffTests(unittest.TestCase):
    def test_lexical_scan_excludes_strings_comments_and_definitions(self):
        source = ('func get_player_data(id):\n\treturn {}\n'
                  '# get_player_data(1)\nvar text = "get_player_data(2)"\n'
                  'func actual():\n\tGameDataManager.get_player_data(\n\t\tint(3))\n'
                  '\tGameDataManager.get_player_data(4); GameDataManager.get_player_data(5)\n')
        calls, definitions = b24.scan_source(source)
        self.assertEqual(len(definitions), 1)
        self.assertEqual([c['id_expression'] for c in calls], ['int(3)', '4', '5'])
        self.assertEqual(len({(c['line'], c['column']) for c in calls}), 3)
        self.assertTrue(all(c['balanced_call'] for c in calls))

    def test_unreviewed_names_and_field_writes_never_force_a_binary_label(self):
        for function in ('initialize_player', 'summon_member', 'get_existing_player'):
            source = f'func {function}(id):\n\tGameDataManager.get_player_data(id).order = 1\n'
            call = b24.scan_source(source)[0][0]
            result = b24.review_call('scripts/unreviewed.gd', call, hashlib.sha256(source.encode()).hexdigest())
            self.assertEqual(result['classification'], '无法判定')
            self.assertIn('scripts/unreviewed.gd:2', result['reason'])
            self.assertTrue(result['missing_information'])

    def test_source_trace_preserves_parameter_and_actual_fixture_candidates(self):
        source = ('func initialize(ids):\n\tGameData.reset_game_session(ids)\n'
                  'func inspect(player_id):\n\tvar id = player_id\n'
                  '\tGameDataManager.get_player_data(id)\n')
        call = b24.scan_source(source)[0][0]
        trace = b24.source_trace(source, call)
        self.assertTrue(any(item['line'] == 4 for item in trace['id_bindings']))
        self.assertTrue(any(item['line'] == 2 for item in trace['lifecycle_candidates']))
        self.assertIn('不据此自动二分', trace['evidence_boundary'])
        result = b24.review_call('scripts/unreviewed.gd', call, 'unreviewed')
        self.assertEqual(result['classification'], '无法判定')

    def test_mixed_parameter_paths_remain_unknown(self):
        for path, line in (('scripts/system/global/time_point_checker.gd', 111),
                           ('scripts/system/global/game_progress.gd', 179),
                           ('scripts/system/global/effect_manager.gd', 2212)):
            raw = (ROOT / path).read_bytes()
            calls = b24.scan_source(raw.decode('utf-8-sig'))[0]
            call = next(c for c in calls if c['line'] == line)
            result = b24.review_call(path, call, hashlib.sha256(raw).hexdigest())
            self.assertEqual(result['classification'], '无法判定')
            self.assertTrue(result['missing_information'])

    def test_purity_fixture_distinguishes_first_missing_from_known_reference(self):
        path = 'tests/find_player_data_purity_test.gd'
        raw = (ROOT / path).read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        results = {c['line']: b24.review_call(path, c, digest)
                   for c in b24.scan_source(raw.decode('utf-8-sig'))[0]}
        self.assertEqual(results[45]['classification'], '需创建')
        self.assertEqual(results[49]['classification'], '只读')
        self.assertTrue(results[45]['evidence'])


if __name__ == '__main__':
    unittest.main()
