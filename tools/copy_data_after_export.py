"""把 data/ 目录复制到导出输出目录旁边。

设计要求：导出后玩家能在游戏目录里看到 data/ 文件夹，直接改 JSON、加卡、换图。
所以 data/ 被 export_presets.cfg 的 exclude_filter 排除出 pck，
需要这个脚本在导出后把它原样拷到 exe 同级。

用法：
    python tools/copy_data_after_export.py [输出目录]
不传参数时默认用 export_presets.cfg 里 preset.0 的 export_path 所在目录。
"""

import shutil
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = PROJECT_ROOT / "data"
PRESETS = PROJECT_ROOT / "export_presets.cfg"

# Godot 导入产物，不需要跟着发布（运行时用 Image 读原图）
SKIP_SUFFIXES = {".import"}


def resolve_output_dir(argv: list[str]) -> Path:
    if len(argv) > 1:
        return Path(argv[1]).resolve()
    if not PRESETS.exists():
        raise SystemExit("找不到 export_presets.cfg，请手动传入输出目录")
    for line in PRESETS.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("export_path="):
            raw = line.split("=", 1)[1].strip().strip('"')
            if not raw:
                break
            exe_path = (PROJECT_ROOT / raw) if not Path(raw).is_absolute() else Path(raw)
            return exe_path.resolve().parent
    raise SystemExit("export_presets.cfg 里没有可用的 export_path，请手动传入输出目录")


def copy_data(dest_root: Path) -> tuple[int, int]:
    if not DATA_DIR.is_dir():
        raise SystemExit(f"找不到 data 目录：{DATA_DIR}")
    dest = dest_root / "data"
    copied = 0
    skipped = 0
    for src in DATA_DIR.rglob("*"):
        if src.is_dir():
            continue
        if src.suffix in SKIP_SUFFIXES:
            skipped += 1
            continue
        target = dest / src.relative_to(DATA_DIR)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, target)
        copied += 1
    return copied, skipped


def main() -> None:
    dest_root = resolve_output_dir(sys.argv)
    dest_root.mkdir(parents=True, exist_ok=True)
    copied, skipped = copy_data(dest_root)
    print(f"data -> {dest_root / 'data'}")
    print(f"已复制 {copied} 个文件，跳过 {skipped} 个 .import")


if __name__ == "__main__":
    main()
