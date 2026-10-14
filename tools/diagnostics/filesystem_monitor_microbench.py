"""Frozen legacy safety oracle, with timing/scale measurements disabled.

User cancelled speed measurements before any benchmark execution. The original
functions below remain an oracle for differential correctness tests only.
"""
from contextlib import contextmanager
import importlib.util
import os
from pathlib import Path
import stat
from unittest.mock import patch

MODULE = Path(__file__).parents[1] / 'run_isolated_godot_test.py'
spec = importlib.util.spec_from_file_location('microbench_runner', MODULE)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
SafetyError = runner.SafetyError


def legacy_no_links(path):
    """Reject every existing ancestor reparse point, including Windows junctions."""
    path = Path(os.path.abspath(path))
    for part in (path, *path.parents):
        if part.exists() or part.is_symlink():
            try:
                info = part.lstat()
            except FileNotFoundError:
                continue
            if stat.S_ISLNK(info.st_mode) or getattr(info, 'st_file_attributes', 0) & 0x400:
                raise SafetyError('link/reparse point: ' + str(part))
    return path


def legacy_tree_bytes(root):
    total = 0
    for directory, dirs, names in os.walk(root, followlinks=False):
        legacy_no_links(directory)
        for name in dirs + names:
            legacy_no_links(Path(directory) / name)
        for name in names:
            try:
                total += (Path(directory) / name).stat().st_size
            except FileNotFoundError:
                # Live engine atomic rename/unlink is normal during import.
                continue
    return total


@contextmanager
def metadata_calls():
    """Count API requests, not kernel syscalls (no timing measurement).

    Python 3.14 Windows exists/islink bypass os.stat: instrument predicates too.
    """
    counts = {'stat_follow': 0, 'stat_nofollow': 0, 'lstat': 0,
              'path_exists': 0, 'path_islink': 0}
    original_stat, original_lstat = os.stat, os.lstat
    original_exists, original_islink = os.path.exists, os.path.islink

    def counted_stat(*args, **kwargs):
        counts['stat_follow' if kwargs.get('follow_symlinks', True) else 'stat_nofollow'] += 1
        return original_stat(*args, **kwargs)

    def counted_lstat(*args, **kwargs):
        counts['lstat'] += 1
        return original_lstat(*args, **kwargs)

    def counted_exists(*args, **kwargs):
        counts['path_exists'] += 1
        return original_exists(*args, **kwargs)

    def counted_islink(*args, **kwargs):
        counts['path_islink'] += 1
        return original_islink(*args, **kwargs)

    with patch('os.stat', counted_stat), patch('os.lstat', counted_lstat), \
         patch('os.path.exists', counted_exists), patch('os.path.islink', counted_islink):
        yield counts
