#!/usr/bin/env python3
"""Replace only the Windows server console wrapper after a release export."""
from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import shutil
import tempfile

DEFAULT_SHA256 = "fc20507547a8b75f1bb5e23ba0300da7554f257339f0b6fd31a8e5399b8254cb"
TARGET_NAME = "FateServer.console.exe"
ENGINE_ROOTS = ("d:/godot4/", "c:/program files/godot/")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def reject_engine_path(path: Path) -> None:
    normalized = path.resolve().as_posix().lower()
    if any(normalized.startswith(root) for root in ENGINE_ROOTS):
        raise SystemExit(f"拒绝写入官方 engine/安装路径: {path}")


def replace(server_dir: Path, wrapper: Path, expected: str) -> Path:
    server_dir = server_dir.resolve()
    wrapper = wrapper.resolve()
    reject_engine_path(server_dir)
    if not server_dir.is_dir():
        raise SystemExit(f"服务端导出目录不存在: {server_dir}")
    engine = server_dir / "FateServer.exe"
    target = server_dir / TARGET_NAME
    backup = server_dir / (TARGET_NAME + ".official-backup")
    if not engine.is_file():
        raise SystemExit(f"缺少相邻服务端 engine: {engine}")
    if not wrapper.is_file():
        raise SystemExit(f"wrapper 不存在: {wrapper}")
    actual = sha256(wrapper)
    if actual.lower() != expected.lower():
        raise SystemExit(f"wrapper SHA-256 不匹配: {actual}")
    if target.exists() and not target.is_file():
        raise SystemExit(f"目标不是普通文件: {target}")
    if target.exists() and not backup.exists():
        shutil.copy2(target, backup)
    with tempfile.NamedTemporaryFile(prefix=".FateServer.console.", suffix=".tmp", dir=server_dir, delete=False) as handle:
        temp = Path(handle.name)
    try:
        shutil.copy2(wrapper, temp)
        os.replace(temp, target)
    finally:
        if temp.exists():
            temp.unlink()
    if sha256(target).lower() != expected.lower():
        raise SystemExit(f"替换后 SHA-256 不匹配: {target}")
    return target


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--server-dir", required=True, type=Path)
    parser.add_argument("--wrapper", required=True, type=Path)
    parser.add_argument("--expected-sha256", default=DEFAULT_SHA256)
    args = parser.parse_args()
    target = replace(args.server_dir, args.wrapper, args.expected_sha256)
    print(f"wrapper replaced: {target}")
    print(f"sha256: {sha256(target)}")


if __name__ == "__main__":
    main()
