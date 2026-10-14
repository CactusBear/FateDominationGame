"""Replay exact E-drive cursor cold-import evidence without launching Godot.

--expect-clean deliberately rejects baseline/withdraw logs, even with exit 0.
The suite verifies raw logs, frozen target SHA, distinct first-use roots,
real main/worker path authorization, Job0/no-kill receipts and runtime RESULT.
"""
from pathlib import Path
import argparse, hashlib, importlib.util, json, re, sys

BASE = Path('E:/scratch/continuous-next-wave/cursor-cold-import')
TARGET = 'scripts/system/global/cursor_replace.gd'
RUNNER_SHA = '3d05d2ef8cefd12f8753daa907b21797f5652267e3dc9dd174592fe8e0df5ddb'
BASELINE_SHA = '8dbba5b5810715efe3fe5fb14ef5165ca73b335c11812ab504ad7ffb474f6476'
LABELS = ['baseline', 'green01', 'green02', 'withdraw01', 'restored03', 'boundary01', 'missing01']

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def read(path):
    return json.loads(path.read_text(encoding='utf-8'))

def receipt(label):
    return read(Path(read(BASE / (label + '.location.json'))['manifest']))

def evidence(label):
    return Path(read(BASE / (label + '.location.json'))['owner']) / 'evidence'

def logs(label, phase):
    folder = evidence(label)
    return [(folder / (phase + '.' + stream + '.log')).read_text(encoding='utf-8')
            for stream in ['stdout', 'stderr']]

def errors(out, err):
    return [line for line in (out + '\n' + err).splitlines()
            if re.search(r'SCRIPT ERROR|SHADER ERROR|^\s*ERROR:', line)]

def clean(label):
    item = receipt(label)
    out, err = logs(label, 'cold-import')
    assert item['import']['exit_code'] == 0, label + ': nonzero exit'
    assert not errors(out, err), label + ': first cold import has engine errors despite exit 0'
    assert item['fresh_no_godot'] is True

def verify():
    helper = BASE / 'no-kill-helper.py'
    assert digest(helper) == RUNNER_SHA
    spec = importlib.util.spec_from_file_location('cursor_evidence_runner', helper)
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    fixed_sha = digest(BASE / 'candidate.gd.bytes')
    assert digest(BASE / 'before.gd.bytes') == BASELINE_SHA
    records = [receipt(label) for label in LABELS]
    roots = [row['project'] for row in records]
    assert len(set(roots)) == len(LABELS), 'cold roots must be physically distinct'
    for label, row in zip(LABELS, records):
        assert row['fresh_no_godot'] and row['tested_target_unchanged']
        assert not row.get('error') and not row['retained']
        assert row['cleanup'] == 'generated_removed_after_job0_log_release'
        assert not Path(row['generated']).exists()
        assert row['processes']
        for process in row['processes']:
            assert process['no_kill'] is True and process['exited'] is True
            assert process['active_owned_processes'] == 0 and process['log_handles_released'] is True
            assert not process.get('retained') and not process.get('budget_failure')
            assert process['exit_code'] is not None
            for key in ['APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'TMPDIR']:
                value = Path(process['environment'][key])
                assert value.drive.upper() == 'E:' and value.is_relative_to(Path(row['generated']))
            assert '--quit-after' in process['command']
            for snapshot in process['observation_logs']:
                saved = Path(snapshot['path'])
                assert digest(saved) == snapshot['sha256']
                stream = 'stdout' if saved.name.endswith('.stdout.log') else 'stderr'
                raw = evidence(label) / (process['label'] + '.' + stream + '.log')
                assert digest(raw) == snapshot['sha256'], 'raw logs must match original exit observation'
        probe = row['two_phase_probe']
        assert probe['authorization']['user_token_write_before_authorization'] is False
        assert len(probe['reports']) == len(probe['writes']) == 2
        for entry in probe['writes']:
            assert Path(entry['physical_path']).drive.upper() == 'E:'
            assert Path(entry['physical_path']).is_relative_to(Path(row['generated']))
            assert entry['worker_pool_max_threads'] == 20
    for label in ['baseline', 'withdraw01']:
        row = receipt(label)
        out, err = logs(label, 'cold-import')
        found = errors(out, err)
        assert len(found) == 8 and row['import']['exit_code'] == 0
        assert found == row['import']['errors']
        assert found.count('ERROR: Failed to create an autoload, script \'res://scripts/system/global/cursor_replace.gd\' is not compiling.') == 1
        for name in ['cursor_norm', 'cursor_pointing', 'cursor_disabled']:
            assert sum('Preload file "res://assets/images/ui/cursor/' + name + '.png" has no resource loaders' in line for line in found) == 2
    assert receipt('baseline')['tested_target_sha'] == BASELINE_SHA
    for label in ['green01', 'green02', 'restored03']:
        clean(label)
        row = receipt(label)
        assert row['tested_target_sha'] == fixed_sha
        out, err = logs(label, 'runtime')
        code = next(p['exit_code'] for p in row['processes'] if p['label'] == 'runtime')
        result = runner.analyze(out, err, code)
        assert result['passed'] and result['result']['checks'] == 21
        textures = [json.loads(line[len('TEXTURE '):]) for line in out.splitlines() if line.startswith('TEXTURE ')]
        assert len(textures) == 3
        assert {(x['field'], x['path'], x['width'], x['height']) for x in textures} == {
            ('cursor_norm', 'res://assets/images/ui/cursor/cursor_norm.png', 36, 52),
            ('pointing', 'res://assets/images/ui/cursor/cursor_pointing.png', 36, 52),
            ('cursor_disabled', 'res://assets/images/ui/cursor/cursor_disabled.png', 36, 52),
        }
    assert receipt('withdraw01')['restored_target_sha'] == fixed_sha
    clean('boundary01')
    boundary = receipt('boundary01')
    assert boundary['editor_ready_marker_count'] == 0 and boundary['runtime_ready_marker_count'] == 1
    out, err = logs('boundary01', 'runtime')
    assert out.count('CURSOR_READY_BOUNDARY_OBSERVED') == 1
    assert not errors(out, err)
    clean('missing01')
    out, err = logs('missing01', 'runtime')
    found = errors(out, err)
    assert len(found) == 3 and 'Resource file not found:' in found[0]
    assert '光标纹理加载失败：' in found[-1]
    assert receipt('missing01')['runtime']['passed'] is False
    assert receipt('missing01')['runtime']['result']['failures'] == ['cursor_norm is nonempty Texture2D']
    assert receipt('missing01')['restored_target_sha'] == fixed_sha
    layer = read(BASE / 'layer.json')
    assert layer['exit'] == 0 and not layer['result']['new'] and not layer['result']['stale']
    source = Path('E:/Projects/Godot/FateDominationGame-master')
    assert digest(source / TARGET) == fixed_sha
    for row in read(BASE / 'original-images.json'):
        assert digest(source / row['path'][len('res://'):]) == row['sha256']
    return {'passed': True, 'cold_roots': len(LABELS), 'production_fresh_green': 3,
            'target_sha256': fixed_sha, 'runtime_checks_each': 21,
            'negative_baseline_errors': 8, 'negative_withdraw_errors': 8,
            'missing_resource_errors': 3, 'layer_new': 0, 'window_used': False}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--expect-clean', choices=LABELS)
    args = parser.parse_args()
    try:
        if args.expect_clean:
            clean(args.expect_clean)
            result = {'passed': True, 'cold_label': args.expect_clean}
        else:
            result = verify()
        print(json.dumps(result, ensure_ascii=False))
    except (AssertionError, OSError, ValueError, KeyError) as exc:
        print(json.dumps({'passed': False, 'error': str(exc)}, ensure_ascii=False))
        sys.exit(1)
