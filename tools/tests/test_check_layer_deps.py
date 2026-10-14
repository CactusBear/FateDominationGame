"""Layer gate fixtures: no production GDScript is changed."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from collections import Counter

TOOL = Path(__file__).resolve().parents[1] / "check_layer_deps.py"


class LayerGateTests(unittest.TestCase):
    def load_gate(self):
        spec = importlib.util.spec_from_file_location("layer_gate_under_test", TOOL)
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
        return module

    def scan_fixture(self, files):
        gate = self.load_gate()
        with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR")) as directory:
            root = Path(directory)
            for relative, text in files.items():
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8")
            return gate, gate.scan(root)

    def test_private_access_in_any_file(self):
        gate, findings = self.scan_fixture({
            "tests/probe.gd": 'EffectManager . _new_member()\nGameProgress._state = true\nDummyBot._memo.clear()\n',
            "reports/frozen/scripts/probe.gd": 'EffectManager._copied_member()\n',
        })
        self.assertEqual([f.rule for f in findings], ["private"] * 4)
        self.assertEqual(len(gate.evaluate(findings, ())[0]), 4)

    def test_e14_expired_route_allowance_is_retired(self):
        gate = self.load_gate()
        self.assertFalse(any(site.path == "scripts/system/global/load_game.gd"
            and site.target == "res://assets/scenes/main_menu/server_bootstrap.tscn"
            for site in gate.ALLOWLIST))

    def test_retired_checkpoint_consumer_allowances_are_absent(self):
        gate = self.load_gate()
        self.assertFalse(any(site.path == "scripts/match/effect_checkpoint.gd"
            and site.target == "GameProgress._battle_broadcast_consumer"
            for site in gate.ALLOWLIST))

    def test_retired_outpost_access_reintroduced_is_rejected(self):
        gate = self.load_gate()
        relative = "tests/outpost_identity_test.gd"
        retired = (
            ("GameProgress._phase_end_pending", "GameProgress._phase_end_pending=false"),
            ("GameProgress._phase_end_running", "GameProgress._phase_end_running=false"),
        )
        for target, code in retired:
            with self.subTest(target=target):
                self.assertFalse(any(site.path == relative and site.target == target
                    for site in gate.ALLOWLIST), "Retired access still has an allowance")
                # Exercise the real CLI with current permitted sources; never
                # inject into the live repository or change its assertions.
                with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR")) as directory:
                    root = Path(directory)
                    for source in {site.path for site in gate.ALLOWLIST}:
                        path = root / source
                        path.parent.mkdir(parents=True, exist_ok=True)
                        path.write_bytes((TOOL.parents[1] / source).read_bytes())

                    def run():
                        return subprocess.run([sys.executable, str(TOOL), "--root", str(root)],
                            capture_output=True, text=True, encoding="utf-8")

                    baseline = run()
                    self.assertEqual(baseline.returncode, 0, baseline.stdout + baseline.stderr)
                    injected = root / relative
                    injected.parent.mkdir(parents=True, exist_ok=True)
                    injected.write_text(code + "\n", encoding="utf-8")
                    rejection = run()
                    self.assertEqual(rejection.returncode, 1, rejection.stdout + rejection.stderr)
                    self.assertEqual([line for line in rejection.stdout.splitlines()
                        if line.startswith("NEW ")], [f"NEW private {relative}:1 -> {target}"])
                    self.assertNotIn("STALE ", rejection.stdout)
                    injected.unlink()
                    restored = run()
                    self.assertEqual(restored.returncode, 0, restored.stdout + restored.stderr)

    def test_newtests_private_coverage_keeps_existing_layer_boundary(self):
        gate, findings = self.scan_fixture({"newtests/probe.gd":
            'EffectManager._new()\nGameProgress._new()\nDummyBot._new()\n'
            'GameLog._not_a_scanned_owner()\n'
            'load("res://scripts/game_scene/ui.gd")\n'})
        self.assertEqual([finding.target for finding in findings],
            ["EffectManager._new", "GameProgress._new", "DummyBot._new"])
        self.assertEqual(gate.evaluate(findings, ()), (findings, []))

    def test_public_watermark_does_not_waive_private_allocator_access(self):
        gate, findings = self.scan_fixture({"scripts/net/authority/match_authority.gd":
            'var cutoff = EffectManager.latest_allocated_message_serial()\n'
            'var next_serial = EffectManager._message_serial._next_serial\n'})
        self.assertEqual([f.target for f in findings], ["EffectManager._message_serial"])
        new, stale = gate.evaluate(findings, ())
        self.assertEqual(new, findings)
        self.assertEqual(stale, [])
        self.assertFalse(any(site.target == "EffectManager._message_serial"
            for site in gate.ALLOWLIST))

    def test_comments_and_non_reference_strings_are_ignored(self):
        gate, findings = self.scan_fixture({"scripts/system/probe.gd": '''
# EffectManager._hidden preload("res://scripts/game_scene/ui.gd")
var s = "EffectManager._hidden # not a comment"
var doc = """DummyBot._memo
GameProgress._state"""
EffectManager.public_method() # DummyBot._memo
''', "scripts/game_scene/ui.gd": 'class_name UiBoard\nextends Control\n',
            "scripts/match/probe.gd": 'var label = "UiBoard"\n'})
        self.assertEqual(findings, [])

    def test_class_names_and_loads_and_route_literals(self):
        _, findings = self.scan_fixture({
            "scripts/game_scene/ui.gd": 'class_name UiBoard\nextends Control\n',
            "scripts/net/ui/panel.gd": 'class_name NetPanel\nextends Control\n',
            "scripts/system/probe.gd": '''var board: UiBoard
var panel = NetPanel.new()
var scene = load('res://assets/scenes/game_scene/board.tscn')
const ROUTE = "res://assets/scenes/main_menu/menu.tscn"
var ui = preload(
  "res://scripts/game_scene/ui.gd"
)
''',
        })
        self.assertEqual(len(findings), 5)
        self.assertEqual({f.rule for f in findings}, {"layer"})

    def test_all_plan_directories_and_only_those(self):
        gate = self.load_gate()
        files = {prefix + "probe.gd": 'UiBoard.new()\n' for prefix in gate.LAYER_ROOTS}
        files["scripts/game_scene/ui.gd"] = 'class_name UiBoard\nextends Control\n'
        files["scripts/net/p2p/probe.gd"] = 'UiBoard.new()\n'
        files["tests/probe.gd"] = 'UiBoard.new()\n'
        _, findings = self.scan_fixture(files)
        self.assertEqual(len(findings), len(gate.LAYER_ROOTS))

    def test_owners_exempt_only_their_own_members(self):
        gate = self.load_gate()
        files = {path: f'{owner}._self()\n' for owner, path in gate.OWNERS.items()}
        files[gate.OWNERS["EffectManager"]] += 'GameProgress._external()\n'
        _, findings = self.scan_fixture(files)
        self.assertEqual([f.target for f in findings], ["GameProgress._external"])

    def test_text_modules_reject_ui_and_node_inheritance(self):
        _, findings = self.scan_fixture({
            "scripts/game_scene/ui.gd": 'class_name UiBoard\nextends Control\n',
            "scripts/ui/base.gd": 'class_name TextBase\nextends Node\n',
            "scripts/ui/text/direct.gd": 'extends Node\n',
            "scripts/ui/text/uncommon.gd": 'extends SpringBoneCollisionCapsule3D\n',
            "scripts/ui/text/custom.gd": 'extends TextBase\n',
            "scripts/ui/text/resource.gd": 'extends "res://scripts/ui/base.gd"\n',
            "scripts/ui/text/pure.gd": 'extends RefCounted\nEffectManager.public_method()\n',
            "scripts/ui/text/bad.gd": 'extends RefCounted\nUiBoard.new()\n',
        })
        self.assertEqual([f.rule for f in findings].count("text-node"), 4)
        self.assertEqual([f.rule for f in findings].count("text-ui"), 1)

    def test_path_dot_segments_do_not_bypass_gate(self):
        _, findings = self.scan_fixture({"scripts/system/probe.gd":
            'load("res://scripts/system/../game_scene/ui.gd")\n'})
        self.assertEqual(findings[0].target, "res://scripts/game_scene/ui.gd")

    def test_precise_allowance_does_not_allow_duplicates_or_other_files(self):
        code = 'EffectManager._old()'
        gate, findings = self.scan_fixture({
            "scripts/match/probe.gd": code + '\n' + code + '\n',
            "tests/other.gd": code + '\n',
        })
        site = gate.ExceptionSite("private", "scripts/match/probe.gd", "EffectManager._old", code, 1)
        new, stale = gate.evaluate(findings, (site,))
        self.assertEqual(len(new), 2)
        self.assertEqual(stale, [])

    def test_same_line_duplicate_load_is_counted(self):
        code = 'var x = preload("res://scripts/game_scene/ui.gd")'
        gate, findings = self.scan_fixture({"scripts/match/probe.gd": code + '\n'})
        site = gate.ExceptionSite("layer", findings[0].path, findings[0].target, code, 1)
        duplicate_code = code + ' + preload("res://scripts/game_scene/ui.gd")'
        _, duplicate = self.scan_fixture({"scripts/match/probe.gd": duplicate_code + '\n'})
        self.assertEqual(len(duplicate), 2)
        new, stale = gate.evaluate(duplicate, (site,))
        self.assertEqual(len(new), 2)  # changed complete code anchor is not allowed
        self.assertEqual(len(stale), 1)

    def test_stale_allowlist_detected_and_removal_restores_pass(self):
        gate = self.load_gate()
        site = gate.ExceptionSite("private", "scripts/match/probe.gd", "EffectManager._old", 'EffectManager._old()', 1)
        self.assertEqual(gate.evaluate([], (site,)), ([], [site]))
        self.assertEqual(gate.evaluate([], ()), ([], []))

    def test_line_shift_whitespace_and_inline_comment_keep_anchor(self):
        code = 'EffectManager._old()'
        gate, findings = self.scan_fixture({"scripts/match/probe.gd":
            '\n# leading\n  EffectManager . _old ( ) # trailing\n'})
        site = gate.ExceptionSite("private", findings[0].path, findings[0].target, code, 1)
        self.assertEqual(gate.evaluate(findings, (site,)), ([], []))

    def test_real_baseline_copy_cli_pass_new_and_stale(self):
        gate = self.load_gate()
        repository = TOOL.parents[1]
        with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR")) as directory:
            root = Path(directory)
            for relative in {site.path for site in gate.ALLOWLIST}:
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes((repository / relative).read_bytes())

            def run():
                return subprocess.run([sys.executable, str(TOOL), "--root", str(root)],
                    capture_output=True, text=True, encoding="utf-8")

            baseline = run()
            self.assertEqual(baseline.returncode, 0, baseline.stdout + baseline.stderr)
            injected = root / "tests/new_violation.gd"
            injected.parent.mkdir(parents=True, exist_ok=True)
            injected.write_text('EffectManager._new()\n', encoding="utf-8")
            violation = run()
            self.assertEqual(violation.returncode, 1)
            self.assertIn("NEW private tests/new_violation.gd:1", violation.stdout)
            injected.unlink()
            findings = gate.scan(root)
            for rule in ("layer", "private"):
                with self.subTest(rule=rule):
                    if not [site for site in gate.ALLOWLIST if site.rule == rule]:
                        # 该规则已全部退休（当前 private 即如此，最后一处公开等价能力接线后许可被删）：
                        # 正确报告是"无该规则 findings、无该规则 stale"，而不是要求仍存在一条锚点可供注入。
                        new, stale = gate.evaluate(findings, tuple(gate.ALLOWLIST))
                        self.assertEqual([f for f in new if f.rule == rule], [])
                        self.assertEqual([s for s in stale if s.rule == rule], [])
                        continue
                    # Select a current real anchor with exactly one finding on
                    # its line; retired production call sites are not fixtures.
                    candidates = [finding for finding in findings
                        if finding.rule == rule and sum(
                            other.path == finding.path and other.line == finding.line
                            for other in findings) == 1]
                    self.assertTrue(candidates, f"No single-occurrence {rule} anchor")
                    finding = candidates[0]
                    sites = [site for site in gate.ALLOWLIST if site.key == finding.key]
                    self.assertEqual(len(sites), 1)
                    site = sites[0]
                    path = root / finding.path
                    original = path.read_bytes()
                    lines = original.decode("utf-8-sig").splitlines(keepends=True)
                    self.assertEqual(gate.signature(gate.lex(lines[finding.line - 1])), finding.anchor)
                    del lines[finding.line - 1]
                    try:
                        path.write_text("".join(lines), encoding="utf-8")
                        stale = run()
                        self.assertEqual(stale.returncode, 1, stale.stdout + stale.stderr)
                        expected = f"STALE {rule} {site.path}:{site.evidence_line} -> {site.target} 请删除白名单项"
                        self.assertEqual([line for line in stale.stdout.splitlines()
                            if line.startswith("STALE ")], [expected])
                        self.assertIn("请删除白名单项", stale.stdout)
                        self.assertNotIn("NEW ", stale.stdout)
                        self.assertEqual(gate.evaluate(gate.scan(root)), ([], [site]))
                    finally:
                        path.write_bytes(original)
                    restored = run()
                    self.assertEqual(restored.returncode, 0, restored.stdout + restored.stderr)

    def test_each_real_allowlist_occurrence_is_individually_retirable(self):
        gate = self.load_gate()
        findings = gate.scan(TOOL.parents[1])
        self.assertEqual(gate.evaluate(findings), ([], []))
        # Check current real lexical anchors including repeated occurrences.
        self.assertEqual(Counter(finding.key for finding in findings),
            Counter(site.key for site in gate.ALLOWLIST))
        for index, finding in enumerate(findings):
            with self.subTest(path=finding.path, line=finding.line, target=finding.target):
                remaining = findings[:index] + findings[index + 1:]
                new, stale = gate.evaluate(remaining)
                self.assertEqual(new, [])
                self.assertEqual(len(stale), 1)
                self.assertEqual(stale[0].key, finding.key)
                reduced = list(gate.ALLOWLIST)
                reduced.remove(stale[0])
                self.assertEqual(gate.evaluate(remaining, reduced), ([], []))

    def test_missing_root_is_error_not_success(self):
        with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR")) as directory:
            result = subprocess.run([sys.executable, str(TOOL), "--root", directory],
                capture_output=True, text=True, encoding="utf-8")
            self.assertEqual(result.returncode, 2)
            self.assertIn("ERROR", result.stderr)

    def test_new_ui_dependency_exits_one(self):
        self.assertTrue(TOOL.is_file(), "A04 layer gate has not been implemented")
        with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR")) as directory:
            root = Path(directory)
            path = root / "scripts/system/new_rule.gd"
            path.parent.mkdir(parents=True)
            path.write_text('extends RefCounted\nconst UI = preload("res://scripts/game_scene/new_ui.gd")\n', encoding="utf-8")
            result = subprocess.run([sys.executable, str(TOOL), "--root", str(root)], capture_output=True, text=True, encoding="utf-8")
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("NEW layer", result.stdout)
            self.assertIn("scripts/system/new_rule.gd:2", result.stdout)


if __name__ == "__main__":
    unittest.main()
