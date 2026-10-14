"""发行文件系统边界：先校验，再创建；新输出一律独占。"""
import json
import os
from pathlib import Path


def scratch_root():
    return (Path(os.environ['LOCALAPPDATA']) / 'hermes/cache/scratch').resolve()


def checked(path):
    path = Path(path).absolute()
    # cache 根允许是已规范化的 Hermes junction；根下任何重定向均拒绝。
    resolved = path.resolve()
    root = scratch_root()
    for parent in (path, *path.parents):
        if parent == root: break
        if parent.exists() and (parent.is_symlink() or (hasattr(parent, 'is_junction') and parent.is_junction())):
            alias = Path(os.environ['LOCALAPPDATA']) / 'hermes/cache/scratch'
            if parent not in alias.parents and parent != alias:
                raise ValueError('拒绝链接/junction 路径: ' + str(parent))
    return resolved


def disjoint(a, b):
    return a != b and a not in b.parents and b not in a.parents


def new_output(path, protected=(), scratch=False, allowed_root=None):
    path = checked(path)
    if allowed_root is not None and checked(allowed_root) not in path.parents:
        raise ValueError('输出不在显式允许根目录内')
    if scratch and allowed_root is None and scratch_root() not in path.parents:
        raise ValueError('冻结输出仅允许 Hermes scratch')
    if path.exists(): raise ValueError('输出已存在，拒绝覆盖: ' + str(path))
    for item in protected:
        if not disjoint(path, checked(item)):
            raise ValueError('输出与受保护路径不可互相包含: ' + str(path))
    return path


def write_new_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('x', encoding='utf-8', newline='\n') as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
