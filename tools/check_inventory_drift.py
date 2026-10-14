#!/usr/bin/env python
"""Read-only A01 inventory check. Exit: 0 clean, 1 changes, 2 input error."""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import sys


def load_baseline(path):
    """Validate the inventory before trusting its paths or digests."""
    inventory = json.loads(path.read_text(encoding="utf-8-sig"))
    files = inventory.get("files")
    if not isinstance(files, list):
        raise ValueError("inventory.files must be a list")
    baseline = {}
    for entry in files:
        if not isinstance(entry, dict):
            raise ValueError("inventory file entry must be an object")
        name, digest = entry.get("path"), entry.get("sha256")
        if not isinstance(name, str):
            raise ValueError("inventory path must be a string")
        parts = PurePosixPath(name).parts
        if (not parts or parts[0] != "scripts" or ".." in parts
                or "\\" in name or not name.endswith(".gd")
                or PurePosixPath(name).as_posix() != name):
            raise ValueError(f"invalid inventory script path: {name!r}")
        if name in baseline:
            raise ValueError(f"duplicate inventory path: {name}")
        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
            raise ValueError(f"invalid SHA256 for {name}")
        baseline[name] = digest
    if inventory.get("script_count") != len(baseline):
        raise ValueError("inventory.script_count does not match files length")
    return baseline


def scan_scripts(root):
    """Hash exact file bytes; line-ending changes intentionally count."""
    directory = root / "scripts"
    if not directory.is_dir():
        raise ValueError(f"scripts directory missing: {directory}")
    current = {}
    for path in sorted(directory.rglob("*.gd")):
        if not path.resolve(strict=True).is_relative_to(root.resolve(strict=True)):
            raise ValueError(f"script outside authorized root: {path}")
        if path.is_file():
            current[path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    return current


def compare(baseline, current):
    """Keep set comparison separate from filesystem and output handling."""
    return {
        "new": sorted(current.keys() - baseline.keys()),
        "gone": sorted(baseline.keys() - current.keys()),
        "drift": sorted(name for name in baseline.keys() & current.keys()
                        if baseline[name] != current[name]),
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1],
                        help="repository root (defaults to this script's repository)")
    parser.add_argument("--inventory", type=Path,
                        help="inventory path (relative paths resolve against root)")
    parser.add_argument("--json", action="store_true", help="emit machine-readable verification")
    args = parser.parse_args(argv)
    inventory = args.inventory or Path("docs/refactoring-coupling-inventory.json")
    try:
        root = args.root.resolve(strict=True)
        if not inventory.is_absolute():
            inventory = root / inventory
        baseline = load_baseline(inventory)
        current = scan_scripts(root)
        changes = compare(baseline, current)
    except (OSError, UnicodeError, ValueError, TypeError, AttributeError) as error:
        if args.json:
            print(json.dumps({"status": "ERROR", "exit_code": 2, "error": str(error)}, ensure_ascii=False))
        else:
            print(f"ERROR: {error}", file=sys.stderr)
        return 2
    if args.json:
        code = int(any(changes.values()))
        print(json.dumps({"status": "FAIL" if code else "PASS", "exit_code": code,
                          "root": root.as_posix(), "inventory": inventory.as_posix(),
                          "baseline_count": len(baseline), "current_count": len(current),
                          **changes}, ensure_ascii=False))
        return code
    print(f"inventory: {inventory.as_posix()}")
    print(f"baseline scripts: {len(baseline)}")
    print(f"current scripts: {len(current)}")
    for kind, names in changes.items():
        print(f"{kind} ({len(names)}):")
        for name in names:
            print(f"  {name}")
            if kind == "drift":
                print(f"    expected: {baseline[name]}")
                print(f"    actual:   {current[name]}")
    return int(any(changes.values()))


if __name__ == "__main__":
    sys.exit(main())
