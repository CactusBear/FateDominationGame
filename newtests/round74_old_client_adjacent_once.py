"""One authorized old-artifact startup attempt; existing round53 APIs only."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO))
from tools.diagnostics.round53_exported_runtime import (
    run_client_startup, validate_client_startup_receipt,
)

ROOT = Path('E:/Caches/Hermes/cache/scratch/g05-client-startup-round74-adjacent-once-sa53')
MANIFEST = Path('E:/FateCandidates/round71-build-only-4f7fb4194e19acdf-91306a82/manifest.json')
MANIFEST_SHA = '0ed4780f6c7291ee44dd8af1183de83bebc9d4b7b0ac14708b25fc9d62b45bb9'
ORIGINAL = Path('E:/Caches/Hermes/cache/scratch/g05-client-startup-round71-once-sa53/runtime.json')
ORIGINAL_SHA = '0a3c83d03b9ec7f42659ba07ebc0b4b50ea56d2d99e40e72b52dd0be849c4a44'
MODULE = REPO / 'tools/diagnostics/round53_exported_runtime.py'


def digest(path):
    with path.open('rb') as handle:
        return hashlib.file_digest(handle, 'sha256').hexdigest()


def main():
    if ROOT.exists():
        raise RuntimeError('Owned output already exists: no retry/no overwrite')
    if digest(MANIFEST) != MANIFEST_SHA or digest(ORIGINAL) != ORIGINAL_SHA:
        raise RuntimeError('Pinned manifest/original receipt mismatch: no launch')
    module_sha = digest(MODULE)
    outcome = {'stage': 'client-startup', 'old_artifact': True, 'nonfinal': True,
               'invocation': subprocess.list2cmdline([sys.executable, '-B', str(Path(__file__).resolve())]),
               'runner_file_sha256': digest(Path(__file__)), 'module_sha256_before': module_sha,
               'original_receipt': str(ORIGINAL), 'original_receipt_sha256_before': ORIGINAL_SHA,
               'api_calls': ['run_client_startup(..., old_artifact=True)',
                             'validate_client_startup_receipt(..., require_current=False)',
                             'validate_client_startup_receipt(..., require_current=True)'],
               'attempt_limit': 1, 'not_covered': ['GUI', 'network', 'save', 'recovery']}
    # This is the sole launch call; failures are read back, never retried.
    try:
        receipt = run_client_startup(ROOT, MANIFEST, MANIFEST_SHA, old_artifact=True)
    except Exception as error:
        outcome['run_api_exception'] = str(error)
        target = ROOT / 'runtime.json'
        if not target.is_file():
            print(json.dumps(outcome, ensure_ascii=False))
            return 1
        receipt = json.loads(target.read_text(encoding='utf-8'))
    target = ROOT / 'runtime.json'
    outcome['receipt_path'] = str(target)
    outcome['receipt_sha256'] = digest(target)
    outcome['stage_receipt'] = receipt.get('stages', {}).get('client-startup')
    outcome['classification'] = receipt.get('classification')
    outcome['identity'] = receipt.get('identity')
    outcome['source_bound_run'] = receipt.get('source_bound_run')
    outcome['isolated_environment'] = receipt.get('isolated_environment')
    outcome['runs'] = receipt.get('runs', [])
    for current, label in ((False, 'evidence_validation'), (True, 'current_gate_validation')):
        try:
            outcome[label] = {'accepted': True, 'result': validate_client_startup_receipt(
                receipt, MANIFEST, MANIFEST_SHA, require_current=current)}
        except Exception as error:
            outcome[label] = {'accepted': False, 'error': str(error)}
    outcome['receipt_unchanged_by_validation'] = digest(target) == outcome['receipt_sha256']
    outcome['original_receipt_sha256_after'] = digest(ORIGINAL)
    outcome['original_receipt_unchanged'] = digest(ORIGINAL) == ORIGINAL_SHA
    outcome['module_sha256_after'] = digest(MODULE)
    outcome['module_unchanged'] = digest(MODULE) == module_sha
    outcome['log_key_lines'] = {}
    pattern = re.compile(r'Godot Engine v|Loading resource: res://assets/scenes/main_menu/opening_background|'
                         r'SCRIPT ERROR|SHADER ERROR|^\s*(?:ERROR|FATAL):|GDExtension|dynamic library|DLL|'
                         r'XR:|Orphan|leaked', re.I)
    for stream in ('stdout', 'stderr', 'engine'):
        path = ROOT / 'logs' / ('client-startup.' + stream + '.log')
        if path.is_file():
            outcome['log_key_lines'][stream] = [line for line in
                path.read_text(encoding='utf-8', errors='replace').splitlines() if pattern.search(line)]
    outcome['wrapper_exit_code'] = 0 if (
        receipt.get('exit_code') == 0 and outcome['evidence_validation']['accepted']
        and not outcome['current_gate_validation']['accepted']
        and outcome['receipt_unchanged_by_validation']
        and outcome['original_receipt_unchanged'] and outcome['module_unchanged']) else 1
    (ROOT / 'caller-evidence.json').write_text(
        json.dumps(outcome, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(outcome, ensure_ascii=False, indent=2))
    return outcome['wrapper_exit_code']


if __name__ == '__main__':
    raise SystemExit(main())
