"""Only the 32 transaction-return allowance retirements; no Godot execution."""
import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import unittest
from collections import Counter

TOOL = Path(__file__).resolve().parents[1] / "check_layer_deps.py"
RELATIVE = "scratch/transaction-return-consumers/transaction_return_consumers_test.gd"
# Original exact occurrences, including repeated anchors; never loaded from ALLOWLIST.
RETIRED = (
    ('EffectManager._runtime_guard', 'EffectManager._runtime_guard.paused = false', 64),
    ('EffectManager._runtime_guard', 'EffectManager._runtime_guard.reason = ""', 65),
    ('EffectManager._guard_run', 'EffectManager._guard_run = {}', 66),
    ('EffectManager._guard_transactions', 'EffectManager._guard_transactions.clear()', 67),
    ('EffectManager._transaction_scope', 'EffectManager._transaction_scope = null', 68),
    ('EffectManager._guard_continuations', 'EffectManager._guard_continuations.clear()', 69),
    ('EffectManager._continuation_transactions', 'EffectManager._continuation_transactions.clear()', 70),
    ('EffectManager._batch_transactions', 'EffectManager._batch_transactions.clear()', 71),
    ('EffectManager._active_runs', 'EffectManager._active_runs.clear()', 72),
    ('EffectManager._paused_runs', 'EffectManager._paused_runs.clear()', 73),
    ('EffectManager._pending_choices', 'EffectManager._pending_choices.clear()', 74),
    ('EffectManager._begin_guard_transaction', '_check(not EffectManager._begin_guard_transaction(effect), "start append 失败不得接受根事务")', 93),
    ('EffectManager._transaction_scope', 'EffectManager._transaction_scope = AuditOwner.new(effect)', 100),
    ('EffectManager._inherit_guard_transaction', '_check(not EffectManager._inherit_guard_transaction(BaseEffect.new()), "child append 失败不得接受子事务")', 101),
    ('EffectManager._runtime_guard', 'EffectManager._runtime_guard.paused = true', 107),
    ('EffectManager._drain_guard_continuations', 'EffectManager._drain_guard_continuations()', 109),
    ('EffectManager._guard_continuations', '_check(tail_calls == 0 and EffectManager._guard_continuations.size() == 1, "登记写失败不得执行或丢弃尾部")', 110),
    ('EffectManager._guard_transactions', 'EffectManager._guard_transactions[effect] = owner', 118),
    ('EffectManager._settle_idle_guard_transactions', 'EffectManager._settle_idle_guard_transactions()', 121),
    ('EffectManager._guard_transactions', '_check(EffectManager._guard_transactions.has(effect), "commit 失败必须保留事务")', 123),
    ('EffectManager._guard_transactions', 'EffectManager._guard_transactions[effect] = owner', 130),
    ('EffectManager._release_guard_transactions', 'EffectManager._release_guard_transactions()', 133),
    ('EffectManager._guard_transactions', 'EffectManager._guard_transactions[effect] = owner', 141),
    ('EffectManager._runtime_guard', 'EffectManager._runtime_guard.paused = true', 142),
    ('EffectManager._guard_run', 'EffectManager._guard_run = {"effect":effect}', 143),
    ('EffectManager._guard_run', '_check(EffectManager.runtime_guard_status().paused and not EffectManager._guard_run.is_empty(), "resume 失败必须保留暂停片")', 145),
    ('EffectManager._guard_transactions', 'EffectManager._guard_transactions[effect] = owner', 152),
    ('EffectManager._runtime_guard', 'EffectManager._runtime_guard.paused = true', 153),
    ('EffectManager._guard_run', 'EffectManager._guard_run = {"effect":effect}', 154),
    ('EffectManager._guard_transactions', 'EffectManager._guard_transactions[effect] = owner', 162),
    ('EffectManager._runtime_guard', 'EffectManager._runtime_guard.paused = true', 163),
    ('EffectManager._guard_run', 'EffectManager._guard_run = {"effect":effect}', 164),
)


class TransactionReturnRetirementTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("transaction_retirement_gate", TOOL)
        cls.gate = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = cls.gate
        spec.loader.exec_module(cls.gate)

    def test_each_old_occurrence_is_rejected(self):
        gate = self.gate
        self.assertEqual(len(RETIRED), 32)
        with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR")) as directory:
            root = Path(directory)
            path = root / RELATIVE
            path.parent.mkdir(parents=True)
            for index, (target, code, evidence_line) in enumerate(RETIRED):
                with self.subTest(occurrence=index, target=target, line=evidence_line):
                    path.write_text(code + "\n", encoding="utf-8")
                    findings = gate.scan(root)
                    expected = gate.ExceptionSite("private", RELATIVE, target, code, evidence_line)
                    self.assertEqual([f.key for f in findings], [expected.key])
                    new, stale = gate.evaluate(findings)
                    self.assertEqual(new, findings, "Retired anchor was accepted again")
                    # This isolated fixture has no retained sites. Assert all stale;
                    # do not suppress unrelated drift or fake a passing live baseline.
                    self.assertEqual(stale, list(gate.ALLOWLIST))

    def test_all_32_reintroduced_occurrences_are_rejected(self):
        gate = self.gate
        with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR")) as directory:
            root = Path(directory)
            path = root / RELATIVE
            path.parent.mkdir(parents=True)
            path.write_text("\n".join(code for _, code, _ in RETIRED) + "\n", encoding="utf-8")
            findings = gate.scan(root)
            expected = Counter(gate.ExceptionSite("private", RELATIVE, target, code, line).key
                               for target, code, line in RETIRED)
            self.assertEqual(len(findings), 32)
            self.assertEqual(Counter(f.key for f in findings), expected)
            new, stale = gate.evaluate(findings)
            self.assertEqual(new, findings)
            self.assertEqual(stale, list(gate.ALLOWLIST))


if __name__ == "__main__":
    unittest.main()
