"""Round32 isolated project.godot VCS transformation unit checks."""
from pathlib import Path
import hashlib
import importlib.util


PROJECT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "round29_integrated_evidence", PROJECT / "tools/tests/test_round29_integrated_evidence.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def sha256_text(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def section(text, name):
    lines = text.splitlines(keepends=True)
    start = next(i for i, line in enumerate(lines) if line.strip() == name)
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("[")), len(lines))
    return "".join(lines[start:end])


def test_isolated_editor_vcs_transformation_is_explicit_and_narrow():
    source = (PROJECT / "project.godot").read_text(encoding="utf-8-sig")
    transformed, record = MODULE.transform_isolated_editor_vcs(source)

    assert 'version_control/plugin_name="GitPlugin"' not in section(transformed, "[editor]")
    assert 'version_control/autoload_on_startup=false' in section(transformed, "[editor]")
    assert section(source, "[threading]") == section(transformed, "[threading]")
    assert 'worker_pool/max_threads=20' in section(transformed, "[threading]")
    assert record["scope"] == "isolated_project_copy_only"
    assert record["authorized_section"] == "[editor]"
    assert record["authorized_fields"] == [
        "version_control/plugin_name",
        "version_control/autoload_on_startup",
    ]
    assert record["source_sha256"] == sha256_text(source)
    assert record["transformed_sha256"] == sha256_text(transformed)
    assert record["changed_sections"] == ["[editor]"]
    assert record["unauthorized_changes"] == []


def test_transformation_rejects_missing_authorized_editor_fields():
    source = "config_version=5\n\n[editor]\nversion_control/autoload_on_startup=true\n"
    try:
        MODULE.transform_isolated_editor_vcs(source)
    except ValueError as exc:
        assert "plugin_name" in str(exc)
    else:
        raise AssertionError("missing authorized GitPlugin field was accepted")


if __name__ == "__main__":
    for test in (test_isolated_editor_vcs_transformation_is_explicit_and_narrow,
                 test_transformation_rejects_missing_authorized_editor_fields):
        test()
    print("round32 transformation unit: PASS")
