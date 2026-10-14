"""把 data/ 目录复制到导出输出目录旁边。

设计要求：导出后玩家能在游戏目录里看到 data/ 文件夹，直接改 JSON、加卡、换图。
所以 data/ 被 export_presets.cfg 的 exclude_filter 排除出 pck，
需要这个脚本在导出后把它原样拷到 exe 同级。

用法：
    python tools/copy_data_after_export.py --project 工程目录 --output-dir 输出目录
    python tools/copy_data_after_export.py --project 工程目录 --preset "预设完整名称"
必须显式选择目标；本工具不执行导出，也不清理目标旧文件。
"""

import argparse
import json
import os
import re
import shutil
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = PROJECT_ROOT / "data"
PRESETS = PROJECT_ROOT / "export_presets.cfg"

# Godot 导入产物，不需要跟着发布（运行时用 Image 读原图）
SKIP_SUFFIXES = {".import"}


def output_for_preset(name: str, project_root: Path) -> Path:
    """只读取 preset.N 的名字和路径，不解析 Godot 的多行 options 值。"""
    sections: dict[str, dict[str, str]] = {}
    current = None
    presets = project_root / "export_presets.cfg"
    for line in presets.read_text(encoding="utf-8-sig").splitlines():
        line = line.strip()
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            current = None
            if re.fullmatch(r"preset\.\d+", section):
                if section in sections:
                    raise ValueError(f"重复 preset 节：{section}")
                current = sections[section] = {}
        elif current is not None and "=" in line:
            key, raw = line.split("=", 1)
            key = key.strip()
            if key in {"name", "export_path"}:
                if key in current:
                    raise ValueError(f"重复 preset 字段：{key}")
                value = json.loads(raw.strip())
                if not isinstance(value, str):
                    raise ValueError(f"preset 字段必须是字符串：{key}")
                current[key] = value
    matches = [values for values in sections.values() if values.get("name") == name]
    if len(matches) != 1:
        raise ValueError(f"preset 名不存在或不唯一：{name}")
    raw = matches[0].get("export_path", "")
    if not raw.strip() or raw.endswith(("/", "\\")):
        raise ValueError(f"preset 没有可用的导出文件路径：{name}；请显式传入输出目录")
    executable = Path(raw)
    if not executable.is_absolute():
        if executable.drive or executable.root:
            raise ValueError("拒绝不完整的绝对导出路径")
        executable = project_root / executable
    # 不 resolve 链接，交由复制前的安全边界检查拒绝路径重定向。
    return Path(os.path.abspath(executable)).parent


def resolve_output_dir(argv: list[str]) -> tuple[Path, Path]:
    parser = argparse.ArgumentParser(description=__doc__, prog=argv[0])
    parser.add_argument("--project", required=True, help="数据来源工程目录")
    parser.add_argument("output_dir", nargs="?", help="显式输出目录（兼容原位置参数）")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--output-dir", dest="named_output")
    group.add_argument("--preset", help="export_presets.cfg 中精确且唯一的 preset 名")
    args = parser.parse_args(argv[1:])
    if sum(value is not None for value in (args.output_dir, args.named_output, args.preset)) != 1:
        parser.error("必须且只能显式传入输出目录或 --preset 名称")
    value = next(value for value in (args.output_dir, args.named_output, args.preset) if value is not None)
    if not value.strip():
        parser.error("目标参数不得为空")
    if args.preset is not None:
        return output_for_preset(value, Path(args.project).absolute()), Path(args.project).absolute()
    return Path(value).absolute(), Path(args.project).absolute()


def reject_redirects(path: Path) -> None:
    """拒绝现存路径链中的 symlink/junction；不先 resolve 掩盖跳转。"""
    for part in (path, *path.parents):
        if part.is_symlink() or part.is_junction():
            raise ValueError(f"拒绝链接或 junction 路径：{part}")


def copy_data(dest_root: Path, project_root: Path) -> tuple[int, int]:
    project_root = Path(os.path.abspath(project_root))
    data_dir = project_root / "data"
    dest_root = Path(os.path.abspath(dest_root))
    reject_redirects(dest_root)
    reject_redirects(project_root)
    reject_redirects(data_dir)
    if not project_root.is_dir():
        raise ValueError(f"找不到工程目录：{project_root}")
    if not data_dir.is_dir():
        raise ValueError(f"找不到 data 目录：{data_dir}")
    dest = dest_root / "data"
    source = data_dir.resolve()
    if dest == source or dest.is_relative_to(source) or source.is_relative_to(dest):
        raise ValueError("源 data 与目标 data 不可重叠")
    reject_redirects(dest)
    if dest_root.exists() and not dest_root.is_dir():
        raise ValueError(f"输出不是目录：{dest_root}")
    if dest.exists() and not dest.is_dir():
        raise ValueError(f"目标 data 不是目录：{dest}")
    # 全量预检后才写入；固定清单防止边扫描边复制。
    plan = []
    copied = 0
    skipped = 0
    for src in data_dir.rglob("*"):
        reject_redirects(src)
        if src.is_dir():
            continue
        if src.suffix in SKIP_SUFFIXES:
            skipped += 1
            continue
        if not src.is_file():
            raise ValueError(f"源路径不是普通文件：{src}")
        target = dest / src.relative_to(data_dir)
        reject_redirects(target)
        if target.exists() and (not target.is_file() or target.stat().st_nlink > 1):
            raise ValueError(f"目标不是独占普通文件：{target}")
        if any(parent.exists() and not parent.is_dir() for parent in target.parents):
            raise ValueError(f"目标父路径不是目录：{target}")
        plan.append((src, target))
    dest.mkdir(parents=True, exist_ok=True)
    for src, target in plan:
        reject_redirects(src)
        reject_redirects(target)
        if target.exists() and target.stat().st_nlink > 1:
            raise ValueError(f"目标不是独占普通文件：{target}")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, target)
        copied += 1
    return copied, skipped


def main() -> None:
    try:
        dest_root, project_root = resolve_output_dir(sys.argv)
        copied, skipped = copy_data(dest_root, project_root)
    except (OSError, ValueError) as error:
        raise SystemExit(f"复制失败：{error}") from error
    print(f"data -> {dest_root / 'data'}")
    print(f"已复制 {copied} 个文件，跳过 {skipped} 个 .import")


if __name__ == "__main__":
    main()
