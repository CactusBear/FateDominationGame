"""Regression evidence for the headless log gate; saved logs stay read-only."""
import importlib.util
import contextlib
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('baseline_gate', ROOT / 'tools/run_refactor_headless_baseline.py')
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


class ResultGateTests(unittest.TestCase):
    def test_saved_false_green_has_explicit_contradictions(self):
        path = ROOT / 'reports/refactoring/round9-continuation-logs/rule_guard_rollback_test.log'
        # The historical process really exited zero; RESULT omitted rolled-back failures.
        text = path.read_bytes().decode('utf-8')
        analyze = getattr(gate, 'analyze_logs', lambda *args, **kwargs: {})
        result = analyze(text, '', exit_code=0, timed_out=False)
        self.assertEqual(result.get('status'), 'RED')
        self.assertEqual(result.get('checks'), [10])
        self.assertEqual(result.get('observed_check_count'), 12)
        self.assertIn('check_count_mismatch', result.get('failure_reasons', []))
        self.assertIn('check_result_contradiction', result.get('failure_reasons', []))
        self.assertIn('真实循环', result['assertion_failures'][0])

    def test_saved_json_success(self):
        text = (ROOT / 'reports/refactoring/round10-D17-refactor_group_projection-final.log').read_bytes().decode('utf-8')
        result = gate.analyze_logs(text, '', exit_code=0, timed_out=False)
        self.assertEqual(result['status'], 'PASS')
        self.assertEqual(result['checks'], [48])

    def test_saved_script_errors_and_missing_result_stay_red(self):
        for relative, reason in [
            ('round10-D17-battle_board_v2-green.log', 'engine_error'),
            ('round10-D17-refactor_held_actions-green.log', 'missing_result'),
        ]:
            with self.subTest(log=relative):
                text = (ROOT / 'reports/refactoring' / relative).read_bytes().decode('utf-8')
                # Even a hypothetical exit zero must not hide this real log evidence.
                result = gate.analyze_logs(text, '', exit_code=0, timed_out=False)
                self.assertEqual(result['status'], 'RED')
                self.assertIn(reason, result['failure_reasons'])

    def test_exit_zero_requires_valid_result_and_no_errors(self):
        cases = [
            ('Godot banner\r\n', '', 0, False, 'missing_result'),
            ('RESULT checks=3 failures=[]', '', 0, True, 'timeout'),
            ('RESULT checks=3 failures=[]', '', 2, False, 'nonzero_exit'),
            ('RESULT checks=3 failures=[]', 'SCRIPT ERROR: 中文错误\r\n', 0, False, 'engine_error'),
            ('RESULT checks=3 failures=[]', 'ERROR: failed\r\n', 0, False, 'engine_error'),
            ('RESULT checks=3 failures=[]', 'SHADER ERROR: bad\r\n', 0, False, 'engine_error'),
            ('RESULT checks=3 failures=["坏断言"]', '', 0, False, 'result_failures'),
            ('RESULT {"checks":3,"failures":["坏断言"]}', '', 0, False, 'result_failures'),
            ('RESULT failures=[]', '', 0, False, 'invalid_result'),
            ('RESULT {"checks":true,"failures":[]}', '', 0, False, 'invalid_result'),
            ('RESULT {"checks":1.5,"failures":[]}', '', 0, False, 'invalid_result'),
            ('RESULT checks=-1 failures=[]', '', 0, False, 'invalid_result'),
            ('RESULT checks=1.5 failures=[]', '', 0, False, 'invalid_result'),
            ('RESULT checks=3 failures=[]\r\nRESULT checks=3 failures=[]', '', 0, False, 'multiple_results'),
            ('RESULT checks=3 failures=[]\r\n CHECK 中文 false \r\n', '', 0, False, 'check_result_contradiction'),
            ('CHECK 中文 true\r\nRESULT checks=2 failures=[]', '', 0, False, 'check_count_mismatch'),
            ('RESULT checks=1 failures=[] checks=2', '', 0, False, 'invalid_result'),
            ('RESULT {"checks":1,"checks":2,"failures":[]}', '', 0, False, 'invalid_result'),
        ]
        for stdout, stderr, code, timeout, reason in cases:
            with self.subTest(reason=reason, stdout=stdout):
                result = gate.analyze_logs(stdout, stderr, exit_code=code, timed_out=timeout)
                self.assertEqual(result['status'], 'RED')
                self.assertIn(reason, result['failure_reasons'])

    def test_no_inferred_counts_and_unicode_crlf(self):
        for text, count in [('RESULT checks=7 failures=[] window_only=false\r\n', 7),
                            ('CHECK 中文😀 true\r\nRESULT failures=[] checks=1\r\n', 1)]:
            result = gate.analyze_logs(text, '', exit_code=0, timed_out=False)
            self.assertEqual(result['status'], 'PASS')
            self.assertEqual(result['checks'], [count])
        result = gate.analyze_logs('CHECK 中文 true\r\nRESULT failures=[]', '', exit_code=0, timed_out=False)
        self.assertEqual(result['checks'], [])

    def test_saved_before_false_green(self):
        text = (ROOT / 'reports/refactoring/round9-continuation-logs/before/rule_guard_chain_rollback_test.log').read_bytes().decode('utf-8')
        result = gate.analyze_logs(text, '', exit_code=0, timed_out=False)
        self.assertEqual(result['status'], 'RED')
        self.assertEqual(result['checks'], [9])
        self.assertEqual(result['observed_check_count'], 16)
        self.assertEqual(len(result['assertion_failures']), 2)

    def test_report_preserves_raw_crlf_and_rejects_invalid_unicode(self):
        with tempfile.TemporaryDirectory(dir=os.environ['TMPDIR']) as tmp:
            root = Path(tmp)
            text = 'CHECK 中文😀 true\r\nRESULT checks=1 failures=[]\n'
            (root / 'out.log').write_bytes(text.encode('utf-8'))
            (root / 'err.log').write_bytes(b'')
            item = dict(gate.analyze_logs(text, '', exit_code=0, timed_out=False),
                        suite='sample', exit_code=0, timed_out=False,
                        stdout_log='out.log', stderr_log='err.log')
            with patch.object(gate, 'ROOT', root), patch.object(gate, 'REPORT', root / 'report'):
                gate.save({'head': 'evidence-only', 'expected_count': 1, 'suites': [item]})
                report = json.loads((root / 'report/baseline-headless.json').read_bytes())
                self.assertEqual(report['suites'][0]['checks'], [1])
                self.assertIn(text.encode('utf-8'), (root / 'report/baseline-headless.txt').read_bytes())
                self.assertEqual(gate.read_log(root / 'out.log'), text)
                (root / 'invalid.log').write_bytes(b'\xff')
                with self.assertRaises(UnicodeDecodeError):
                    gate.read_log(root / 'invalid.log')

    def test_main_uses_real_log_gate_and_returns_red_exit(self):
        raw = (ROOT / 'reports/refactoring/round9-continuation-logs/rule_guard_rollback_test.log').read_bytes()
        with tempfile.TemporaryDirectory(dir=os.environ['TMPDIR']) as tmp:
            root = Path(tmp)
            (root / 'docs').mkdir()
            (root / 'tests').mkdir()
            names = ['suite_%d' % i for i in range(24)]
            (root / 'docs/refactoring-plan.md').write_text('**A02** for s in ' + ' '.join(names) + '; do', encoding='utf-8')
            for name in names:
                (root / ('tests/' + name + '.tscn')).touch()
            binary = root / 'fake-godot.exe'
            binary.touch()
            class RecordedProcess:
                def __init__(self, command, **kwargs):
                    kwargs['stdout'].write(raw)
                def wait(self, **kwargs):
                    return 0
            with patch.object(gate, 'ROOT', root), patch.object(gate, 'GODOT', binary), \
                 patch.object(gate, 'REPORT', root / 'report'), patch.object(gate, 'LOGS', root / 'logs'), \
                 patch.object(gate.subprocess, 'Popen', RecordedProcess), \
                 patch.object(gate.subprocess, 'check_output', return_value='recorded\n'), \
                 contextlib.redirect_stdout(io.StringIO()):
                code = gate.main()
            report = json.loads((root / 'report/baseline-headless.json').read_bytes())
            self.assertEqual(code, 1)
            self.assertEqual(report['red_count'], 24)
            self.assertEqual(report['suites'][0].get('observed_check_count'), 12)
            self.assertEqual((root / 'logs/suite_0.stdout.log').read_bytes(), raw)


if __name__ == '__main__':
    unittest.main()
