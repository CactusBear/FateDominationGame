"""Package a real build-only artifact as a separately named human-test candidate.

This tool never exports, runs Godot, creates credentials, or grants release admission.
It consumes the immutable round56 artifact manifest and a round56 phase-runformal receipt.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import sys
import zipfile

sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import round56_three_role_freeze as freeze

SCHEMA = 3
PACKAGE_KIND = "human-test-candidate"
STATUS = "HUMAN_TEST_CANDIDATE"
ALL_ROLES = ("client", "server", "signaling")
# Keep the consumer aligned with the actual producer, not a copied stage list.
FORMAL_PHASES = tuple(freeze.RUN_PHASES)
FORBIDDEN_PARTS = {"tests", "reports", "devmcp", "source", "savedkeys"}
DEFAULTS = {
    "random_sim_budget_sec": 15.0,
    "worker_pool_max_threads": 20,
    "automatic_cleanup": False,
}
QUICKSTART = REPO / "docs/human-test-quickstart.md"


class CandidateError(ValueError):
    pass


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def json_read(path: Path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise CandidateError(f"JSON_UNREADABLE: {path}") from exc


def json_write(path: Path, value) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def safe_rel(value: str) -> str:
    if not isinstance(value, str) or not value or "\\" in value:
        raise CandidateError("PACKAGE_PATH_INVALID")
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or any(part.lower() in FORBIDDEN_PARTS for part in path.parts):
        raise CandidateError("PACKAGE_WHITELIST_FORBIDDEN_PATH: " + str(value))
    return path.as_posix()


def parse_roles(value: str) -> list[str]:
    roles = [item.strip().lower() for item in value.split(",") if item.strip()]
    if not roles or any(role not in ALL_ROLES for role in roles) or len(set(roles)) != len(roles):
        raise CandidateError("EXPLICIT_INCLUDED_ROLES_REQUIRED")
    return roles


def reject_final_claims(document, label: str) -> None:
    if not isinstance(document, dict):
        raise CandidateError(f"{label}_OBJECT_REQUIRED")
    # No full-suite receipt is accepted by this packaging-only consumer.
    if "full_suite" in document:
        full = document["full_suite"]
        if (full.get("status") if isinstance(full, dict) else full) != "NOTRUN":
            raise CandidateError(f"{label}_FULL_SUITE_RECEIPT_UNSUPPORTED")
    comparison = document.get("source_comparison", {})
    for claims in (document, comparison if isinstance(comparison, dict) else {}):
        if (claims.get("is_latest") not in (None, False)
                or claims.get("declared_latest") not in (None, False)
                or str(claims.get("artifact_currency", "")).upper() == "LATEST"):
            raise CandidateError(f"{label}_LATEST_CLAIM_NOT_SUPPORTED")
    values = {
        "status": document.get("status"),
        "classification": document.get("classification"),
        "source_PASS": document.get("source_PASS"),
        "release_PASS": document.get("release_PASS"),
        "source_pass": document.get("source_pass"),
        "release_pass": document.get("release_pass"),
        "ready_token": document.get("ready_token"),
        "ready": document.get("ready"),
    }
    forbidden = {"SOURCE_PASS", "RELEASE_PASS", "READY", "PASS"}
    for key, value in values.items():
        if key in {"source_PASS", "release_PASS", "source_pass", "release_pass", "ready_token", "ready"} and value not in (None, False, "NOT_GRANTED", "NOT_ISSUED", "NOTRUN"):
            raise CandidateError(f"{label}_FALSE_FINAL_CLAIM: {key}")
        if key in {"status", "classification"} and any(token in str(value).upper() for token in forbidden):
            # Only exact nonfinal labels containing PASS are exceptions. A
            # substring exemption would accept BUILD_ONLY_RELEASE_PASS.
            allowed = {"PARTIAL_NOT_THREE_ROLE_PASS", "STATIC_BUILD_ACCEPTED_NOT_RUNTIME_PASS"}
            if value not in allowed:
                raise CandidateError(f"{label}_FALSE_FINAL_STATUS: {key}")


def load_artifact(manifest_path: Path, manifest_sha256: str, included_roles: list[str]):
    if not isinstance(manifest_sha256, str) or sha(manifest_path) != manifest_sha256:
        raise CandidateError("ARTIFACT_MANIFEST_HASH_MISMATCH")
    document = json_read(manifest_path)
    reject_final_claims(document, "ARTIFACT")
    roles = document.get("roles")
    if not isinstance(roles, dict) or set(roles) != set(ALL_ROLES):
        raise CandidateError("BUILD_MANIFEST_EXACT_THREE_ROLES_REQUIRED")
    fingerprints = {roles[role].get("source_fingerprint") for role in ALL_ROLES}
    if len(fingerprints) != 1 or not next(iter(fingerprints), ""):
        raise CandidateError("BUILD_MANIFEST_THREE_ROLE_HASH_MISMATCH")
    source_fingerprint = next(iter(fingerprints))
    if document.get("artifact_identity_sha256"):
        identity = freeze.fingerprint({role: roles[role].get("package_files") for role in ALL_ROLES})
        if identity != document["artifact_identity_sha256"]:
            raise CandidateError("BUILD_MANIFEST_ARTIFACT_IDENTITY_MISMATCH")
    try:
        freeze.validate_roles(document, ALL_ROLES)
    except (OSError, ValueError, KeyError, TypeError, IndexError) as exc:
        raise CandidateError(f"BUILD_MANIFEST_PACKAGE_HASH_OR_ROLE_INVALID: {exc}") from exc
    acquisition = document.get("snapshot_acquisition", {})
    inventory = acquisition.get("inventory", {})
    if inventory.get("source_fingerprint") != source_fingerprint:
        raise CandidateError("BUILD_ONLY_SNAPSHOT_FINGERPRINT_MISMATCH")
    if not any(row.get("status") == "EXACT_COPY_VERIFIED" for row in acquisition.get("attempts", [])):
        raise CandidateError("BUILD_ONLY_EXACT_SNAPSHOT_REQUIRED")
    if any(roles[role].get("source_fingerprint") != source_fingerprint for role in included_roles):
        raise CandidateError("INCLUDED_ROLE_SOURCE_FINGERPRINT_MISMATCH")
    return document, source_fingerprint


def load_source_readback(build_root: Path, source_fingerprint: str):
    path = build_root / "source-readback.json"
    if not path.is_file():
        raise CandidateError("SOURCE_READBACK_REQUIRED")
    value = json_read(path)
    if value.get("snapshot_fingerprint") != source_fingerprint:
        raise CandidateError("SOURCE_READBACK_SNAPSHOT_MISMATCH")
    if not isinstance(value.get("current_fingerprint"), str) or len(value["current_fingerprint"]) != 64:
        raise CandidateError("SOURCE_READBACK_LATEST_FINGERPRINT_REQUIRED")
    drift = value.get("drift")
    if not isinstance(drift, dict) or set(drift) != {"added", "removed", "changed"}:
        raise CandidateError("SOURCE_READBACK_EXACT_DRIFT_REQUIRED")
    for key in ("added", "removed"):
        if not isinstance(drift[key], list):
            raise CandidateError("SOURCE_READBACK_DRIFT_LIST_REQUIRED")
    if not isinstance(drift["changed"], dict):
        raise CandidateError("SOURCE_READBACK_DRIFT_CHANGED_REQUIRED")
    return value, sha(path)


def load_formal(formal_path: Path, formal_sha256: str, artifact_path: Path, artifact_sha256: str):
    if not formal_path.is_file():
        raise CandidateError("FORMAL_RECEIPT_REQUIRED")
    if not isinstance(formal_sha256, str) or sha(formal_path) != formal_sha256:
        raise CandidateError("FORMAL_RECEIPT_HASH_MISMATCH")
    receipt = json_read(formal_path)
    if not isinstance(receipt, dict) or not isinstance(receipt.get("stages"), dict) or set(receipt["stages"]) != set(FORMAL_PHASES):
        # The release producer may read historical receipts; a new handoff must not
        # silently synthesize a phase omitted by its actual input receipt.
        actual_phases = set(receipt.get("stages", {})) if isinstance(receipt, dict) and isinstance(receipt.get("stages"), dict) else set()
        raise CandidateError("FORMAL_RECEIPT_EXACT_PHASES_REQUIRED: " + json.dumps({
            "missing": sorted(set(FORMAL_PHASES) - actual_phases),
            "unexpected": sorted(actual_phases - set(FORMAL_PHASES)),
        }))
    reject_final_claims(receipt, "FORMAL")
    try:
        validated = freeze.validate_formal_receipt(receipt, artifact_path, artifact_sha256)
    except (OSError, ValueError, KeyError, TypeError, IndexError) as exc:
        raise CandidateError(str(exc)) from exc
    return receipt, validated


def build_acceptance(document):
    steps = document.get("steps")
    if not isinstance(steps, list) or not steps:
        raise CandidateError("BUILD_STEPS_REQUIRED")
    step_rows = []
    for row in steps:
        if not isinstance(row, dict) or row.get("exit_code") != 0 or row.get("exited") is not True:
            raise CandidateError("BUILD_STEP_NOT_EXIT0")
        step_rows.append({
            "name": row.get("name"),
            "exit_code": row.get("exit_code"),
            "exit_hex": row.get("exit_hex"),
            "error_lines": row.get("error_lines", []),
            "log_sha256": row.get("log_sha256"),
        })
    static = {}
    for role, row in document["roles"].items():
        if role in ("client", "server") and row.get("static_exit_code") != 0:
            raise CandidateError("STATIC_BUILD_AUDIT_NOT_EXIT0: " + role)
        if not row.get("static_audit"):
            raise CandidateError("STATIC_BUILD_AUDIT_MISSING: " + role)
        static[role] = {"exit_code": row.get("static_exit_code", 0), "audit": row["static_audit"]}
    return {"status": "STATIC_BUILD_ACCEPTED_NOT_RUNTIME_PASS", "steps": step_rows, "roles": static}


def minimum_smoke(formal_validated):
    stages = formal_validated["stages"]
    return {
        "status": formal_validated["classification"],
        "run_phase": formal_validated["run_phase"],
        "stage_status": {name: stages[name]["status"] for name in FORMAL_PHASES},
        "full_suite": "NOTRUN",
        "unrun_full": True,
        "runtime_pass_claim": "NOT_GRANTED",
    }


def known_limitations(formal_validated):
    stages = formal_validated["stages"]

    def item(identifier, status, scope, evidence):
        return {"id": identifier, "status": status, "scope": scope, "evidence": evidence}

    no_receipt = {"receipt": None, "reason": "本候选未提供此验收层的同冻结回执；不由专项绿推断"}
    phase_evidence = lambda name: {"receipt": "phase-runformal.json", "pointer": "/stages/" + name,
                                   "status": stages[name]["status"]}
    limitations = {
        "release_admission": item("release_admission", "NOT_GRANTED", "真人测试候选，不是正式发行；source/release PASS 与 ready token 均未授予", no_receipt),
        "full_suite": item("full_suite", "NOTRUN", "全量回归；没有 full 回执，不回退、不伪造", no_receipt),
        "gui_two_client": item("gui_two_client", "NOTRUN", "最终包双客户端 GUI 认证、创建/加入、合法操作及完整对局", no_receipt),
        "save_restore": item("save_restore", "UNKNOWN", "历史保存恢复整链 unknown 保留；须同冻结正式 EXE 保存、退出、原身份恢复并续写", no_receipt),
        "worker_ready": item("worker_ready", "UNKNOWN", "历史独立 authority worker 就绪 unknown 保留；静态 build 或信令 READY 不证明游戏 worker 就绪", no_receipt),
        "client_startup": item("client_startup", stages["client-startup"]["status"], "正式客户端启动冒烟；不是 GUI、联机或恢复验收", phase_evidence("client-startup")),
        "branch_vs_package": item("branch_vs_package", "PACKAGE_NOT_VERIFIED", "专项绿只可标『本分支已验、整包待验』，且本分支已验须有对应专项证据；不得升级为整包验收", {
            "receipt": "phase-runformal.json", "verified_phases": [name for name in FORMAL_PHASES if stages[name]["status"] == "PASS"],
            "package_acceptance": "NOT_GRANTED"}),
        "cross_machine_network": item("cross_machine_network", "NOTRUN", "多机、跨网、NAT 与真实部署环境", no_receipt),
        "native_promotion": item("native_promotion", "NOT_ATTESTED", "本工具仅核对 manifest 已绑定的 DLL，不据包名推断新 native DLL 已推广", {
            "receipt": "human-test-candidate-manifest.json", "pointer": "/roles"}),
        "deployment_credentials": item("deployment_credentials", "NOT_PROVISIONED", "不猜部署地址、不打开公网端口、不携带凭据；身份由正常 UI 生成", {"policy": "launcher-pass-through-only"}),
        "automatic_cleanup": item("automatic_cleanup", "DISABLED", "自动清理默认关闭；未知保存证据不得自动删除", {"policy": "defaults.automatic_cleanup", "value": DEFAULTS["automatic_cleanup"]}),
    }
    limitations["client_startup"]["implies_multiplayer_acceptance"] = False
    limitations["formal_phases"] = {
        name: item(name, stages[name]["status"], "仅此正式阶段，不代表 full 或整包验收", phase_evidence(name))
        for name in FORMAL_PHASES
    }
    return limitations


def validate_handoff_claims(manifest, formal_validated):
    """Require explicit nonfinal states and evidence-derived boundary rows."""
    expected = {
        "schema": SCHEMA,
        "source_pass": "NOT_GRANTED",
        "release_pass": "NOT_GRANTED",
        "ready_token": "NOT_ISSUED",
        "full_suite": "NOTRUN",
        "unrun_full": True,
        "known_limitations": known_limitations(formal_validated),
        "minimum_smoke": minimum_smoke(formal_validated),
    }
    for key, value in expected.items():
        if key not in manifest or manifest[key] != value:
            raise CandidateError("ZIP_HANDOFF_CLAIMS_MISMATCH: " + key)
    reject_final_claims(manifest, "ZIP_MANIFEST")


def launcher_files(declaration, role):
    """Require declared package entries; never generate or discover launchers."""
    name = {"client": "START-CLIENT.cmd", "server": "START-SERVER.cmd",
            "signaling": "START-SIGNALING.cmd"}[role]
    required = (name, "Launch-HumanTest.ps1")
    runtime = declaration.get("runtime_files", [])
    for destination in required:
        matches = [item for item in runtime if item.get("target") == destination]
        if len(matches) != 1:
            raise CandidateError("DECLARED_LAUNCHER_REQUIRED: " + role + ":" + destination)
        safe_rel(matches[0]["source"])
    return required


def readback_manifest(root: Path):
    result = {}
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        rel = safe_rel(path.relative_to(root).as_posix())
        result[rel] = sha(path)
    return result


def write_readme(root: Path, document, source_fingerprint: str, source_readback, formal_validated, included_roles, zip_name: str):
    stage_lines = "\n".join(f"- `{name}`: **{formal_validated['stages'][name]['status']}**" for name in FORMAL_PHASES)
    role_lines = "\n".join(f"- `{role}`: `{document['roles'][role]['declaration']['executable']}` → `{role}/`" for role in included_roles)
    text = f"""# human-test-candidate（真人测试包）

> 状态：`{STATUS}`。这不是正式发行包。

## 先看这里

- 只需要客户端：运行 `client/START-CLIENT.cmd`；若交付物只含 client，则不要寻找 server/signaling 目录。
- 三个启动脚本不接受命令行参数；client 通过 FD_CLIENT_PROFILE 或提示选择 host/guest。server/signaling 固定读取同目录 server.cfg/signaling.json，并以 --headless 和对应业务角色参数启动。脚本不猜部署地址/端口、不生成凭据；服务按已审核配置监听。
- server/signaling 仅在部署者给出目标配置后启动；凭据只能通过产品正常 UI 生成。
- 包内没有 `tests/`、`reports/`、`devmcp/`、`source/` 或 `savedkeys/`。

## 启动入口

{role_lines}

- `client/START-CLIENT.cmd`：真人客户端入口，不接受命令行参数，不向 EXE 追加产品参数；按提示选 host/guest，或用 FD_CLIENT_PROFILE 指定。
- `server/START-SERVER.cmd`：服务端入口（如包含），不内置地址/公网端口。
- `signaling/START-SIGNALING.cmd`：信令入口（如包含），不内置地址/公网端口。

## 冻结与验收身份

- build-only snapshot source fingerprint：`{source_fingerprint}`
- 最新只读 source fingerprint：`{source_readback['current_fingerprint']}`
- old → latest 精确差异：见 `source-diff.json`（added/removed/changed 原样保留）。
- 构建验收：见 `build-acceptance.json`；仅表示真实 build/static audit，不是 runtime PASS。
- 最小 smoke：`{formal_validated['run_phase']}`，见 `phase-runformal.json`；各阶段原样记录 PASS/NOTRUN/FAIL。

### phase-runformal 阶段

{stage_lines}

## 明确未完成

- `full_suite`: **NOTRUN**；不得把本包称 sourcePASS、releasePASS 或 ready。
- 已知限制完整清单见 `known-limitations.json`。
- 这份包与正式包使用不同目录/命名：`{PACKAGE_KIND}`。

## 校验

- `human-test-candidate-manifest.json` 是包清单，`SHA256SUMS.txt` 是包内文件 SHA-256。
- ZIP 位于包目录旁：`{zip_name}`；旁边的 `.sha256` 文件提供 ZIP SHA-256。
"""
    (root / "README-human-test.md").write_text(text, encoding="utf-8", newline="\n")


def copy_roles(root: Path, document, included_roles):
    copied = {}
    for role in included_roles:
        row = document["roles"][role]
        package = Path(row["package"]).resolve()
        expected = row["package_files"]
        launcher_name, helper_name = launcher_files(row["declaration"], role)
        for rel in (launcher_name, helper_name):
            if rel not in expected:
                raise CandidateError("PACKAGE_DECLARED_LAUNCHER_MISSING: " + role + ":" + rel)
        actual = freeze.package_audit.manifest(package) if hasattr(freeze, "package_audit") else None
        # round56.validate_roles already checked the exact package; repeat the source readback here.
        if actual is None:
            import package_audit
            actual = package_audit.manifest(package)
        if actual != expected:
            raise CandidateError("SOURCE_PACKAGE_CHANGED_BEFORE_COPY: " + role)
        target = root / role
        target.mkdir(parents=True, exist_ok=False)
        for rel, digest in sorted(expected.items()):
            rel = safe_rel(rel)
            src = package / Path(rel)
            if not src.is_file() or sha(src) != digest:
                raise CandidateError("SOURCE_PACKAGE_HASH_MISMATCH: " + role + ":" + rel)
            dst = target / Path(rel)
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, dst)
            if sha(dst) != digest:
                raise CandidateError("COPIED_PACKAGE_HASH_MISMATCH: " + role + ":" + rel)
        exe = row["declaration"]["executable"]
        # Launchers/helper are already hash-verified package files. Do not rewrite them.
        copied[role] = {"files": expected, "executable": exe, "launcher": f"{role}/{launcher_name}"}
    return copied


def copy_quickstart(root: Path):
    if not QUICKSTART.is_file():
        raise CandidateError("HUMAN_TEST_QUICKSTART_REQUIRED")
    target = root / "docs" / QUICKSTART.name
    target.parent.mkdir(parents=True, exist_ok=True)
    source_digest = sha(QUICKSTART)
    shutil.copyfile(QUICKSTART, target)
    if sha(target) != source_digest:
        raise CandidateError("HUMAN_TEST_QUICKSTART_HASH_MISMATCH")
    text = target.read_text(encoding="utf-8")
    if "client/START-CLIENT.cmd" not in text:
        raise CandidateError("HUMAN_TEST_QUICKSTART_CLIENT_LAUNCHER_REFERENCE_REQUIRED")
    return {"path": "docs/" + QUICKSTART.name, "sha256": source_digest}


def zip_and_verify(root: Path, zip_path: Path, expected_files: dict[str, str]):
    if zip_path.exists():
        raise CandidateError("FRESH_ZIP_REQUIRED")
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for rel in sorted(expected_files):
            archive.write(root / Path(rel), rel)
    with zipfile.ZipFile(zip_path, "r") as archive:
        names = sorted(archive.namelist())
        if names != sorted(expected_files):
            raise CandidateError("ZIP_MEMBER_SET_MISMATCH")
        for rel, digest in expected_files.items():
            if hashlib.sha256(archive.read(rel)).hexdigest() != digest:
                raise CandidateError("ZIP_MEMBER_HASH_MISMATCH: " + rel)
    return sha(zip_path)


def package(args):
    artifact_path = Path(args.artifact_manifest).resolve()
    formal_path = Path(args.formal_runtime).resolve()
    output = Path(args.output_dir).resolve()
    if "human-test-candidate" not in output.name.lower() or "release" in output.name.lower():
        raise CandidateError("HUMAN_TEST_DIRECTORY_NAME_REQUIRED")
    if output.exists():
        raise CandidateError("FRESH_OUTPUT_REQUIRED")
    included_roles = parse_roles(args.roles)
    document, source_fingerprint = load_artifact(artifact_path, args.artifact_manifest_sha256, included_roles)
    source_readback, source_readback_sha256 = load_source_readback(artifact_path.parent, source_fingerprint)
    formal_receipt, formal_validated = load_formal(formal_path, args.formal_runtime_sha256, artifact_path, args.artifact_manifest_sha256)
    if formal_validated["run_phase"] not in FORMAL_PHASES and formal_validated["run_phase"] != "all":
        raise CandidateError("FORMAL_PHASE_INVALID")
    build = build_acceptance(document)
    output.mkdir(parents=True)
    try:
        role_files = copy_roles(output, document, included_roles)
        quickstart = copy_quickstart(output)
        json_write(output / "build-acceptance.json", build)
        json_write(output / "source-diff.json", source_readback)
        json_write(output / "phase-runformal.json", formal_receipt)
        json_write(output / "known-limitations.json", {"status": "NOTRUN_OR_PARTIAL", "items": known_limitations(formal_validated)})
        manifest = {
            "schema": SCHEMA,
            "package_kind": PACKAGE_KIND,
            "status": STATUS,
            "release_status": "NOT_RELEASED",
            "published": False,
            "source_pass": "NOT_GRANTED",
            "release_pass": "NOT_GRANTED",
            "ready_token": "NOT_ISSUED",
            "full_suite": "NOTRUN",
            "unrun_full": True,
            "source_fingerprint": source_fingerprint,
            "source_fingerprint_latest": source_readback["current_fingerprint"],
            "source_comparison": {
                "snapshot": source_fingerprint,
                "latest": source_readback["current_fingerprint"],
                "drift": source_readback["drift"],
                "source_readback_sha256": source_readback_sha256,
            },
            "build_only": {
                "artifact_manifest": str(artifact_path),
                "artifact_manifest_sha256": args.artifact_manifest_sha256,
                "original_status": document.get("status"),
                "artifact_identity_sha256": document.get("artifact_identity_sha256"),
                "role_source_fingerprints": {role: document["roles"][role]["source_fingerprint"] for role in ALL_ROLES},
                "snapshot_acquisition": document["snapshot_acquisition"],
            },
            "build_acceptance": build,
            "minimum_smoke": minimum_smoke(formal_validated),
            "phase_runformal": {
                "receipt": "phase-runformal.json",
                "receipt_sha256": None,
                "artifact_manifest_sha256": args.artifact_manifest_sha256,
                "classification": formal_validated["classification"],
            },
            "defaults": DEFAULTS,
            "handoff_documents": {"quickstart": quickstart["path"], "quickstart_sha256": quickstart["sha256"]},
            "included_roles": included_roles,
            "roles": role_files,
            "known_limitations": known_limitations(formal_validated),
            "forbidden_zip_paths": sorted(FORBIDDEN_PARTS),
        }
        write_readme(output, document, source_fingerprint, source_readback, formal_validated, included_roles, output.with_suffix(".zip").name)
        # Receipt/hash fields are filled only after their bytes are final.
        manifest["phase_runformal"]["receipt_sha256"] = sha(output / "phase-runformal.json")
        json_write(output / "human-test-candidate-manifest.json", manifest)
        expected = readback_manifest(output)
        sums = "".join(f"{digest}  {rel}\n" for rel, digest in sorted(expected.items()))
        (output / "SHA256SUMS.txt").write_text(sums, encoding="ascii", newline="\n")
        expected = readback_manifest(output)
        if expected.get("SHA256SUMS.txt") != sha(output / "SHA256SUMS.txt"):
            raise CandidateError("PACKAGE_READBACK_SHA_MISMATCH")
        # The sums file intentionally excludes itself; the final readback is the authoritative full set.
        expected = readback_manifest(output)
        zip_path = output.with_suffix(".zip")
        zip_sha256 = zip_and_verify(output, zip_path, expected)
        (Path(str(zip_path) + ".sha256")).write_text(f"{zip_sha256}  {zip_path.name}\n", encoding="ascii", newline="\n")
        return {
            "status": STATUS,
            "package_dir": str(output),
            "zip": str(zip_path),
            "zip_sha256": zip_sha256,
            "manifest": str(output / "human-test-candidate-manifest.json"),
            "manifest_sha256": sha(output / "human-test-candidate-manifest.json"),
            "included_roles": included_roles,
            "source_fingerprint": source_fingerprint,
            "full_suite": "NOTRUN",
            "published": False,
        }
    except BaseException:
        shutil.rmtree(output, ignore_errors=True)
        raise


def verify_zip(args):
    artifact_path = Path(args.artifact_manifest).resolve()
    included_roles = parse_roles(args.roles)
    document, source_fingerprint = load_artifact(artifact_path, args.artifact_manifest_sha256, included_roles)
    source_readback, source_readback_sha256 = load_source_readback(artifact_path.parent, source_fingerprint)
    formal_path = Path(args.formal_runtime).resolve()
    formal_receipt, formal_validated = load_formal(formal_path, args.formal_runtime_sha256, artifact_path, args.artifact_manifest_sha256)
    zip_path = Path(args.verify_zip).resolve()
    if not zip_path.is_file():
        raise CandidateError("ZIP_REQUIRED")
    with zipfile.ZipFile(zip_path, "r") as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise CandidateError("ZIP_DUPLICATE_MEMBER")
        for name in names:
            safe_rel(name)
            if name.lower().startswith(tuple(part + "/" for part in FORBIDDEN_PARTS)):
                raise CandidateError("ZIP_FORBIDDEN_MEMBER: " + name)
        required = {"human-test-candidate-manifest.json", "README-human-test.md", "docs/human-test-quickstart.md", "source-diff.json", "build-acceptance.json", "phase-runformal.json", "known-limitations.json", "SHA256SUMS.txt"}
        if not required.issubset(names):
            raise CandidateError("ZIP_HANDOFF_FILES_MISSING")
        manifest = json.loads(archive.read("human-test-candidate-manifest.json"))
        validate_handoff_claims(manifest, formal_validated)
        if (manifest.get("status") != STATUS or manifest.get("published") is not False
                or manifest.get("source_fingerprint") != source_fingerprint
                or manifest.get("package_kind") != PACKAGE_KIND
                or manifest.get("release_status") != "NOT_RELEASED"):
            raise CandidateError("ZIP_MANIFEST_IDENTITY_MISMATCH")
        comparison = {"snapshot": source_fingerprint, "latest": source_readback["current_fingerprint"],
                      "drift": source_readback["drift"], "source_readback_sha256": source_readback_sha256}
        if (manifest.get("source_fingerprint_latest") != source_readback["current_fingerprint"]
                or manifest.get("source_comparison") != comparison
                or json.loads(archive.read("source-diff.json")) != source_readback):
            raise CandidateError("ZIP_SOURCE_COMPARISON_MISMATCH")
        if manifest.get("included_roles") != included_roles:
            raise CandidateError("ZIP_INCLUDED_ROLES_MISMATCH")
        expected_roles = {}
        expected_names = set(required)
        for role in included_roles:
            row = document["roles"][role]
            executable = row["declaration"]["executable"]
            launcher_name, helper_name = launcher_files(row["declaration"], role)
            launcher_rel = f"{role}/{launcher_name}"
            expected_roles[role] = {"files": row["package_files"], "executable": executable, "launcher": launcher_rel}
            for rel in (launcher_name, helper_name):
                if rel not in row["package_files"]:
                    raise CandidateError("PACKAGE_DECLARED_LAUNCHER_MISSING: " + role + ":" + rel)
            for rel, digest in row["package_files"].items():
                name = role + "/" + safe_rel(rel)
                expected_names.add(name)
                if hashlib.sha256(archive.read(name)).hexdigest() != digest:
                    raise CandidateError("ZIP_ROLE_FILE_HASH_MISMATCH: " + name)
        if manifest.get("roles") != expected_roles:
            raise CandidateError("ZIP_ROLES_MANIFEST_MISMATCH")
        if set(names) != expected_names:
            raise CandidateError("ZIP_MEMBER_SET_MISMATCH")
        if (json.loads(archive.read("phase-runformal.json")) != formal_receipt
                or manifest.get("phase_runformal") != {
                    "receipt": "phase-runformal.json",
                    "receipt_sha256": hashlib.sha256(archive.read("phase-runformal.json")).hexdigest(),
                    "artifact_manifest_sha256": args.artifact_manifest_sha256,
                    "classification": formal_validated["classification"]}):
            raise CandidateError("ZIP_FORMAL_RECEIPT_MISMATCH")
        build = build_acceptance(document)
        if manifest.get("build_acceptance") != build or json.loads(archive.read("build-acceptance.json")) != build:
            raise CandidateError("ZIP_BUILD_ACCEPTANCE_MISMATCH")
        if json.loads(archive.read("known-limitations.json")) != {"status": "NOTRUN_OR_PARTIAL", "items": known_limitations(formal_validated)}:
            raise CandidateError("ZIP_LIMITATIONS_MISMATCH")
        expected_sums = "".join(f"{hashlib.sha256(archive.read(name)).hexdigest()}  {name}\n"
                                for name in sorted(names) if name != "SHA256SUMS.txt")
        if archive.read("SHA256SUMS.txt").decode("ascii") != expected_sums:
            raise CandidateError("ZIP_SHA256SUMS_MISMATCH")
        quickstart = manifest.get("handoff_documents", {})
        if quickstart.get("quickstart") != "docs/human-test-quickstart.md":
            raise CandidateError("ZIP_QUICKSTART_MANIFEST_BINDING_MISMATCH")
        if hashlib.sha256(archive.read("docs/human-test-quickstart.md")).hexdigest() != quickstart.get("quickstart_sha256"):
            raise CandidateError("ZIP_QUICKSTART_HASH_MISMATCH")
    return {"status": "ZIP_READBACK_VERIFIED_NOT_PUBLISHED", "zip": str(zip_path), "members": len(names), "published": False}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--artifact-manifest", type=Path, required=True)
    ap.add_argument("--artifact-manifest-sha256", required=True)
    ap.add_argument("--formal-runtime", type=Path, required=True)
    ap.add_argument("--formal-runtime-sha256", required=True)
    ap.add_argument("--roles", default=",".join(ALL_ROLES))
    ap.add_argument("--output-dir", type=Path)
    ap.add_argument("--verify-zip", type=Path)
    args = ap.parse_args(argv)
    try:
        if (args.output_dir is None) == (args.verify_zip is None):
            raise CandidateError("EXACTLY_ONE_OF_OUTPUT_OR_VERIFY_ZIP_REQUIRED")
        result = verify_zip(args) if args.verify_zip is not None else package(args)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (OSError, CandidateError, ValueError, KeyError, TypeError, IndexError, zipfile.BadZipFile) as exc:
        print(json.dumps({"status": "BLOCKED", "reason": str(exc), "published": False}, ensure_ascii=False))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
