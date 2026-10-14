"""Python-only human-test handoff gates; fixtures are not runtime evidence."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

REPO = Path(__file__).resolve().parents[2]
MODULE = REPO / "tools/release/human_test_candidate.py"
FREEZE = REPO / "tools/release/round56_three_role_freeze.py"


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class HumanTestCandidateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Resolve junctions before the physical-E gate; never use C:/Temp.
        cls.scratch = Path(os.environ.get("HUMAN_TEST_SCRATCH", "E:/Caches/Hermes/cache/scratch")).resolve()
        cls.scratch.mkdir(parents=True, exist_ok=True)
        if cls.scratch.drive.upper() != "E:":
            raise RuntimeError("TEST_PHYSICAL_E_SCRATCH_REQUIRED")
        os.environ["TMPDIR"] = str(cls.scratch)
        os.environ["TEMP"] = str(cls.scratch)
        os.environ["TMP"] = str(cls.scratch)
        cls.subject = load(MODULE, "human_test_candidate_unit")
        cls.freeze = load(FREEZE, "round56_freeze_unit")

    def base_manifest(self, root):
        artifact = root / "artifact.json"
        roles = {
            role: {"source_fingerprint": "a" * 64, "package_files": {},
                   "declaration": {"role": role, "platform": "windows", "executable": role + ".exe"},
                   "package": str(root / role), "static_audit": "ok", "static_exit_code": 0}
            for role in self.subject.ALL_ROLES
        }
        document = {
            "status": "BUILD_ONLY_DIAGNOSTIC_THREE_ARTIFACTS_RUNTIME_NOTRUN",
            "artifact_identity_sha256": self.freeze.fingerprint({role: {} for role in self.subject.ALL_ROLES}),
            "roles": roles,
            "snapshot_acquisition": {"inventory": {"source_fingerprint": "a" * 64},
                                     "attempts": [{"status": "EXACT_COPY_VERIFIED"}]},
        }
        artifact.write_text(json.dumps(document), encoding="utf-8")
        return artifact, document

    def test_structured_limitations_preserve_unknowns(self):
        formal = {"stages": {name: {"status": "NOTRUN"} for name in self.subject.FORMAL_PHASES},
                  "run_phase": "client-startup", "classification": "INCOMPLETE_NOTRUN"}
        result = self.subject.known_limitations(formal)
        self.assertIsInstance(result, dict)
        for key in ("full_suite", "gui_two_client", "save_restore", "worker_ready", "client_startup", "branch_vs_package"):
            self.assertTrue({"id", "status", "scope", "evidence"}.issubset(result[key]))
            self.assertEqual(result[key]["id"], key)
        self.assertEqual(result["full_suite"]["status"], "NOTRUN")
        self.assertEqual(result["gui_two_client"]["status"], "NOTRUN")
        self.assertEqual(result["save_restore"]["status"], "UNKNOWN")
        self.assertEqual(result["worker_ready"]["status"], "UNKNOWN")
        self.assertFalse(result["client_startup"]["implies_multiplayer_acceptance"])
        self.assertEqual(set(result["formal_phases"]), set(self.subject.FORMAL_PHASES))

    def test_missing_formal_receipt_is_rejected(self):
        with tempfile.TemporaryDirectory(dir=self.scratch) as temp:
            root = Path(temp)
            with self.assertRaisesRegex(self.subject.CandidateError, "FORMAL_RECEIPT_REQUIRED"):
                self.subject.load_formal(root / "absent.json", "a" * 64, root / "artifact.json", "b" * 64)

    def test_missing_new_phase_is_not_backfilled(self):
        with tempfile.TemporaryDirectory(dir=self.scratch) as temp:
            root = Path(temp)
            artifact = root / "manifest.json"
            artifact.write_text("{}", encoding="utf-8")
            receipt = {"stages": {name: {"status": "NOTRUN"} for name in self.subject.FORMAL_PHASES if name != "client-startup"}}
            formal = root / "formal.json"
            formal.write_text(json.dumps(receipt), encoding="utf-8")
            with self.assertRaisesRegex(self.subject.CandidateError, "FORMAL_RECEIPT_EXACT_PHASES_REQUIRED.*client-startup"):
                self.subject.load_formal(formal, self.subject.sha(formal), artifact, self.subject.sha(artifact))

    def test_full_suite_has_no_supported_pass_receipt(self):
        for value in ("PASS", "FAIL", {"status": "PASS"}):
            with self.subTest(value=value), self.assertRaisesRegex(self.subject.CandidateError, "FULL_SUITE_RECEIPT_UNSUPPORTED"):
                self.subject.reject_final_claims({"full_suite": value}, "INPUT")
        self.subject.reject_final_claims({"full_suite": "NOTRUN"}, "INPUT")

    def test_old_package_cannot_claim_latest(self):
        for claim in ({"is_latest": True}, {"declared_latest": True},
                      {"artifact_currency": "LATEST"}, {"source_comparison": {"is_latest": True}}):
            with self.subTest(claim=claim), self.assertRaisesRegex(self.subject.CandidateError, "LATEST_CLAIM_NOT_SUPPORTED"):
                self.subject.reject_final_claims(claim, "OLD_ARTIFACT")

    def test_sneaky_lowercase_final_pass_is_rejected(self):
        for key, value in (("source_pass", "PASS"), ("release_pass", "PASS"), ("ready_token", "READY")):
            with self.subTest(key=key), self.assertRaisesRegex(self.subject.CandidateError, "FALSE_FINAL_CLAIM"):
                self.subject.reject_final_claims({key: value}, "INPUT")

    def test_handoff_rejects_missing_or_forged_structured_boundary(self):
        formal = {"stages": {name: {"status": "NOTRUN"} for name in self.subject.FORMAL_PHASES},
                  "run_phase": "client-startup", "classification": "INCOMPLETE_NOTRUN"}
        manifest = {"schema": self.subject.SCHEMA, "source_pass": "NOT_GRANTED", "release_pass": "NOT_GRANTED",
                    "ready_token": "NOT_ISSUED", "full_suite": "NOTRUN", "unrun_full": True,
                    "known_limitations": self.subject.known_limitations(formal),
                    "minimum_smoke": self.subject.minimum_smoke(formal)}
        self.assertTrue(hasattr(self.subject, "validate_handoff_claims"), "missing structured ZIP readback gate")
        self.subject.validate_handoff_claims(manifest, formal)
        import copy
        for mutate in (lambda value: value["known_limitations"].pop("worker_ready"),
                       lambda value: value["known_limitations"]["save_restore"].update(status="PASS"),
                       lambda value: value["minimum_smoke"].update(full_suite="PASS"),
                       lambda value: value.pop("full_suite")):
            forged = copy.deepcopy(manifest)
            mutate(forged)
            with self.assertRaisesRegex(self.subject.CandidateError, "ZIP_.*MISMATCH"):
                self.subject.validate_handoff_claims(forged, formal)

    def test_zip_gate_rejects_rehashed_false_claims_and_extra_files(self):
        # Mock only upstream artifact/protocol discovery, never ZIP gate behavior.
        from types import SimpleNamespace
        import copy
        with tempfile.TemporaryDirectory(dir=self.scratch) as temp:
            root = Path(temp)
            artifact, document = self.base_manifest(root)
            document['steps'] = [{'name': 'fixture', 'exit_code': 0, 'exited': True}]
            formal = {'stages': {name: {'status': 'NOTRUN'} for name in self.subject.FORMAL_PHASES},
                      'run_phase': 'client-startup', 'classification': 'INCOMPLETE_NOTRUN'}
            manifest = {'schema': self.subject.SCHEMA, 'status': self.subject.STATUS,
                        'package_kind': self.subject.PACKAGE_KIND, 'release_status': 'NOT_RELEASED',
                        'published': False, 'source_pass': 'NOT_GRANTED', 'release_pass': 'NOT_GRANTED',
                        'ready_token': 'NOT_ISSUED', 'full_suite': 'NOTRUN', 'unrun_full': True,
                        'source_fingerprint': 'a' * 64, 'source_fingerprint_latest': 'b' * 64,
                        'source_comparison': {'snapshot': 'a' * 64, 'latest': 'b' * 64,
                                              'drift': {'added': [], 'removed': [], 'changed': {}},
                                              'source_readback_sha256': 'c' * 64},
                        'included_roles': ['client'],
                        'roles': {'client': {'files': {}, 'executable': 'client.exe',
                                             'launcher': 'client/START-CLIENT.cmd'}},
                        'minimum_smoke': self.subject.minimum_smoke(formal),
                        'known_limitations': self.subject.known_limitations(formal),
                        'build_acceptance': self.subject.build_acceptance(document)}
            readback = {'snapshot_fingerprint': 'a' * 64, 'current_fingerprint': 'b' * 64,
                        'drift': {'added': [], 'removed': [], 'changed': {}}}
            formal_bytes = json.dumps(formal).encode()
            launcher_members = {
                name: (REPO / 'release/human-test' / name).read_bytes()
                for name in ('START-CLIENT.cmd', 'Launch-HumanTest.ps1')
            }
            launcher_hashes = {name: hashlib.sha256(raw).hexdigest() for name, raw in launcher_members.items()}
            document['roles']['client']['package_files'] = launcher_hashes
            document['roles']['client']['declaration']['runtime_files'] = [
                {'source': 'release/human-test/' + name, 'target': name}
                for name in launcher_members
            ]
            manifest['roles']['client']['files'] = launcher_hashes
            quickstart = b'client/START-CLIENT.cmd'
            manifest['handoff_documents'] = {'quickstart': 'docs/human-test-quickstart.md',
                                             'quickstart_sha256': hashlib.sha256(quickstart).hexdigest()}
            manifest['phase_runformal'] = {'receipt': 'phase-runformal.json',
                                          'receipt_sha256': hashlib.sha256(formal_bytes).hexdigest(),
                                          'artifact_manifest_sha256': 'd' * 64,
                                          'classification': 'INCOMPLETE_NOTRUN'}
            members = {'README-human-test.md': b'fixture only',
                       'docs/human-test-quickstart.md': quickstart,
                       'source-diff.json': json.dumps(readback).encode(),
                       'build-acceptance.json': json.dumps(manifest['build_acceptance']).encode(),
                       'phase-runformal.json': formal_bytes,
                       'known-limitations.json': json.dumps({'status': 'NOTRUN_OR_PARTIAL',
                                                             'items': manifest['known_limitations']}).encode()}
            members.update({'client/' + name: raw for name, raw in launcher_members.items()})

            def write_zip(value, files):
                files = dict(files)
                files['human-test-candidate-manifest.json'] = json.dumps(value).encode()
                files['SHA256SUMS.txt'] = ''.join(
                    f'{hashlib.sha256(raw).hexdigest()}  {name}\n'
                    for name, raw in sorted(files.items())).encode()
                target = root / 'fixture.zip'
                with zipfile.ZipFile(target, 'w') as archive:
                    for name, raw in files.items():
                        archive.writestr(name, raw)
                return target

            args = SimpleNamespace(artifact_manifest=artifact, artifact_manifest_sha256='d' * 64,
                                   formal_runtime=root / 'formal.json', formal_runtime_sha256='e' * 64,
                                   roles='client', verify_zip=None)
            with patch.object(self.subject, 'load_artifact', return_value=(document, 'a' * 64)), \
                 patch.object(self.subject, 'load_source_readback', return_value=(readback, 'c' * 64)), \
                 patch.object(self.subject, 'load_formal', return_value=(formal, formal)):
                args.verify_zip = write_zip(manifest, members)
                self.assertEqual(self.subject.verify_zip(args)['status'], 'ZIP_READBACK_VERIFIED_NOT_PUBLISHED')
                for mutate in (lambda v: v['known_limitations'].pop('save_restore'),
                               lambda v: v['known_limitations']['worker_ready'].update(status='PASS'),
                               lambda v: v['minimum_smoke'].update(full_suite='PASS'),
                               lambda v: v.update(declared_latest=True),
                               lambda v: v.update(source_pass='PASS')):
                    forged = copy.deepcopy(manifest)
                    mutate(forged)
                    args.verify_zip = write_zip(forged, members)
                    with self.assertRaises(self.subject.CandidateError):
                        self.subject.verify_zip(args)
                extra = dict(members, **{'unlisted.txt': b'not allowed'})
                args.verify_zip = write_zip(manifest, extra)
                with self.assertRaisesRegex(self.subject.CandidateError, 'ZIP_MEMBER_SET_MISMATCH'):
                    self.subject.verify_zip(args)
                tampered = dict(members, **{'known-limitations.json': b'{}'})
                args.verify_zip = write_zip(manifest, tampered)
                with self.assertRaisesRegex(self.subject.CandidateError, 'ZIP_LIMITATIONS_MISMATCH'):
                    self.subject.verify_zip(args)
                missing = dict(members)
                missing.pop('phase-runformal.json')
                args.verify_zip = write_zip(manifest, missing)
                with self.assertRaisesRegex(self.subject.CandidateError, 'ZIP_HANDOFF_FILES_MISSING'):
                    self.subject.verify_zip(args)

    def test_missing_role_is_rejected(self):
        with tempfile.TemporaryDirectory(dir=Path(os.environ["TMPDIR"]).resolve()) as temp:
            artifact, document = self.base_manifest(Path(temp))
            document["roles"].pop("server")
            artifact.write_text(json.dumps(document), encoding="utf-8")
            with self.assertRaisesRegex(self.subject.CandidateError, "BUILD_MANIFEST_EXACT_THREE_ROLES_REQUIRED"):
                self.subject.load_artifact(artifact, self.subject.sha(artifact), list(self.subject.ALL_ROLES))

    def test_wrong_manifest_hash_is_rejected(self):
        with tempfile.TemporaryDirectory(dir=Path(os.environ["TMPDIR"]).resolve()) as temp:
            artifact, _ = self.base_manifest(Path(temp))
            with self.assertRaisesRegex(self.subject.CandidateError, "ARTIFACT_MANIFEST_HASH_MISMATCH"):
                self.subject.load_artifact(artifact, "0" * 64, list(self.subject.ALL_ROLES))

    def test_wrong_role_package_hash_is_rejected_by_round56_gate(self):
        with tempfile.TemporaryDirectory(dir=Path(os.environ["TMPDIR"]).resolve()) as temp:
            artifact, _ = self.base_manifest(Path(temp))
            with patch.object(self.subject.freeze, "validate_roles", side_effect=ValueError("PACKAGE_HASH_DRIFT: client")):
                with self.assertRaisesRegex(self.subject.CandidateError, "PACKAGE_HASH_DRIFT: client"):
                    self.subject.load_artifact(artifact, self.subject.sha(artifact), list(self.subject.ALL_ROLES))

    def test_secret_final_pass_is_rejected(self):
        with self.assertRaisesRegex(self.subject.CandidateError, "FALSE_FINAL_STATUS"):
            self.subject.reject_final_claims({"status": "RELEASE_PASS"}, "ARTIFACT")
        with self.assertRaisesRegex(self.subject.CandidateError, "FALSE_FINAL_CLAIM"):
            self.subject.reject_final_claims({"status": "BUILD_ONLY", "source_PASS": "PASS"}, "ARTIFACT")

    def test_formal_receipt_preserves_partial_not_pass(self):
        with tempfile.TemporaryDirectory(dir=Path(os.environ["TMPDIR"]).resolve()) as temp:
            root = Path(temp)
            artifact = root / "manifest.json"
            artifact.write_text("artifact", encoding="utf-8")
            manifest_sha = self.subject.sha(artifact)
            stages = {name: {"status": "NOTRUN"} for name in self.freeze.RUN_PHASES}
            stages["signaling-ready"] = {"status": "PASS", "exit_code": 0}
            receipt = {"schema": 1, "artifact_manifest": str(artifact),
                       "artifact_manifest_sha256": manifest_sha,
                       "classification": "PARTIAL_NOT_THREE_ROLE_PASS", "run_phase": "signaling-ready",
                       "stages": stages, "exit_code": 0, "formal_exported_client_RSA": "NOTRUN"}
            result = self.freeze.validate_formal_receipt(receipt, artifact, manifest_sha)
            self.assertEqual(result["classification"], "PARTIAL_NOT_THREE_ROLE_PASS")
            self.assertEqual(result["stages"]["client"]["status"], "NOTRUN")
            receipt["classification"] = "RELEASE_PASS"
            with self.assertRaisesRegex(ValueError, "FORMAL_RECEIPT_CLASSIFICATION_MISMATCH"):
                self.freeze.validate_formal_receipt(receipt, artifact, manifest_sha)

    def test_zip_readback_and_whitelist(self):
        with tempfile.TemporaryDirectory(dir=Path(os.environ["TMPDIR"]).resolve()) as temp:
            root = Path(temp) / "human-test-candidate-fixture"
            root.mkdir()
            (root / "README-human-test.md").write_text("candidate", encoding="utf-8")
            (root / "human-test-candidate-manifest.json").write_text(
                json.dumps({"status": "HUMAN_TEST_CANDIDATE", "source_fingerprint": "a" * 64}), encoding="utf-8")
            expected = self.subject.readback_manifest(root)
            zip_path = root.with_suffix(".zip")
            self.subject.zip_and_verify(root, zip_path, expected)
            with zipfile.ZipFile(zip_path) as archive:
                self.assertEqual(sorted(archive.namelist()), sorted(expected))
            with self.assertRaisesRegex(self.subject.CandidateError, "PACKAGE_WHITELIST_FORBIDDEN_PATH"):
                self.subject.safe_rel("reports/bad.json")

    def test_quickstart_is_copied_with_script_isolation_instructions(self):
        with tempfile.TemporaryDirectory(dir=Path(os.environ["TMPDIR"]).resolve()) as temp:
            root = Path(temp) / "candidate"
            root.mkdir()
            row = self.subject.copy_quickstart(root)
            self.assertEqual(row["path"], "docs/human-test-quickstart.md")
            self.assertIn("client/START-CLIENT.cmd", (root / row["path"]).read_text(encoding="utf-8"))
            text = (root / row['path']).read_text(encoding='utf-8')
            for term in ('APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMPDIR', 'host', 'guest'):
                self.assertIn(term, text)
            self.assertNotIn('可直接双击', text)


if __name__ == "__main__":
    unittest.main()
