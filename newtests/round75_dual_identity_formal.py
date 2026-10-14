"""仅 E 盘、旧候选正式身份按钮信号链；不读取/输出身份明文。"""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
from ctypes import wintypes as w

REPO = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
sys.path.insert(0, str(REPO / 'tools'))
from run_isolated_godot_test import OwnedJob

ROOT = Path('E:/Caches/Hermes/cache/scratch/round75-dual-identity-formal-20261010-saidentity')
SOURCE = Path('E:/Caches/Hermes/cache/scratch/round71-human-test-candidate-validation-v3/client')
PROTECTED = {17120, 28100}
ARTIFACTS = ['FateDomination.exe', 'FateDomination.pck',
             'libfate_server_signals.windows.template_release.x86_64.dll',
             'libwebrtc_native.windows.template_release.x86_64.dll', 'START-CLIENT.cmd']


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def identity_snapshot(root):
    result = {}
    for role in ('host', 'guest'):
        directory = root / 'test-users' / role / 'appdata/FateDomination/net_identity'
        if directory.exists():
            assert directory.resolve().is_relative_to(root.resolve()), 'IDENTITY_PATH_ESCAPE'
        files = {}
        for path in sorted(directory.rglob('*')) if directory.exists() else []:
            assert not path.is_symlink() and path.resolve().is_relative_to(root.resolve()), 'IDENTITY_LINK'
            if path.is_file():
                files[str(path.relative_to(directory))] = sha(path)
        result[role] = {'directory': str(directory), 'exists': directory.is_dir(),
                        'file_count': len(files), 'files': files}
    return result


def compare(snapshot):
    host, guest = snapshot['host'], snapshot['guest']
    names = sorted(set(host['files']) & set(guest['files']))
    return {'nonempty_both': host['exists'] and guest['exists'] and bool(names)
            and host['file_count'] > 0 and guest['file_count'] > 0,
            'paths_distinct': host['directory'] != guest['directory'],
            'same_names': sorted(host['files']) == sorted(guest['files']) and bool(names),
            'sha_distinct': bool(names) and all(host['files'][name] != guest['files'][name] for name in names),
            'rows': [{'file': name, 'host_sha256': host['files'][name],
                      'guest_sha256': guest['files'][name]} for name in names]}


def run():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--approve-root', required=True)
    args = parser.parse_args()
    assert Path(args.approve_root).resolve() == ROOT.resolve(), 'EXACT_ROOT_APPROVAL_REQUIRED'
    assert ROOT.resolve().drive.upper() == 'E:' and not ROOT.exists(), 'FRESH_E_ROOT_REQUIRED'
    assert {x.name for x in SOURCE.iterdir()} == set(ARTIFACTS + ['data']), 'SOURCE_LAYOUT_CHANGED_STOP'
    assert not SOURCE.is_symlink() and not (SOURCE / 'data').is_symlink(), 'SOURCE_LINK_STOP'
    source_files = sorted(path for path in SOURCE.rglob('*') if path.is_file())
    assert all(not path.is_symlink() for path in source_files), 'SOURCE_FILE_LINK_STOP'
    before_source = {str(path.relative_to(SOURCE)): sha(path) for path in source_files}
    ROOT.mkdir()
    shutil.copytree(SOURCE, ROOT / 'client')
    assert before_source == {name: sha(ROOT / 'client' / name) for name in before_source}, 'COPY_SHA_MISMATCH'
    driver = ROOT / 'identity_formal_driver.gd'
    shutil.copyfile(REPO / 'newtests/round75_identity_formal_driver.gd', driver)
    (ROOT / 'controls').mkdir()
    for role in ('host', 'guest'):
        for leaf in ('appdata', 'localappdata', 'temp'):
            (ROOT / 'test-users' / role / leaf).mkdir(parents=True)
    evidence = {'old_artifact': True, 'nonfinal': True, 'headless': True, 'gui_input_verified': False,
                'source': str(SOURCE), 'root': str(ROOT), 'protected_pids': sorted(PROTECTED),
                'source_hashes_before': before_source, 'driver_sha256': sha(driver),
                'runs': [], 'snapshots': [], 'forced_termination': False, 'watchdog_seconds': 180}
    outfile = ROOT / 'evidence.json'
    job = OwnedJob()
    kernel = job.kernel
    kernel.OpenProcess.argtypes = [w.DWORD, w.BOOL, w.DWORD]
    kernel.OpenProcess.restype = w.HANDLE
    kernel.GetExitCodeProcess.argtypes = [w.HANDLE, ctypes.POINTER(w.DWORD)]
    kernel.GetExitCodeProcess.restype = w.BOOL
    handles = {}
    processes = {}
    start = time.monotonic()

    def save():
        outfile.write_text(json.dumps(evidence, ensure_ascii=False, indent=2), encoding='utf-8')

    def job_state():
        class Accounting(ctypes.Structure):
            _fields_ = [('times', ctypes.c_int64 * 4), ('faults', w.DWORD),
                        ('total', w.DWORD), ('active', w.DWORD), ('terminated', w.DWORD)]
        value = Accounting()
        assert kernel.QueryInformationJobObject(job.handle, 1, ctypes.byref(value), ctypes.sizeof(value), None)
        buffer = ctypes.create_string_buffer(8192)
        assert kernel.QueryInformationJobObject(job.handle, 3, buffer, len(buffer), None)
        count = int.from_bytes(buffer.raw[4:8], 'little')
        width = ctypes.sizeof(ctypes.c_size_t)
        pids = [int.from_bytes(buffer.raw[8+i*width:8+(i+1)*width], 'little') for i in range(count)]
        assert not PROTECTED.intersection(pids), 'PROTECTED_PID_IN_JOB_STOP'
        for pid in pids:
            if pid not in handles:
                handle = kernel.OpenProcess(0x1000 | 0x100000, False, pid)
                if handle:
                    handles[pid] = handle
        return {'total': value.total, 'active': value.active,
                'terminated': value.terminated, 'pids': pids}

    def snapshot(label):
        value = {'label': label, 'elapsed_seconds': round(time.monotonic() - start, 3),
                 'job': job_state(), 'identity': identity_snapshot(ROOT)}
        evidence['snapshots'].append(value)
        save()
        return value

    def bounded_wait(predicate, label):
        deadline = time.monotonic() + 45
        while not predicate():
            job_state()
            assert time.monotonic() < deadline and time.monotonic()-start < 180, 'WATCHDOG_' + label
            for name, item in processes.items():
                process = item['process']
                if not item.get('exit_requested') and process.poll() is not None:
                    raise AssertionError('UNEXPECTED_EXIT_' + name + '_' + str(process.returncode))
            time.sleep(.1)

    def launch(role, label):
        env = os.environ.copy()
        for variable, leaf in [('APPDATA', 'appdata'), ('LOCALAPPDATA', 'localappdata'),
                               ('TEMP', 'temp'), ('TMP', 'temp'), ('TMPDIR', 'temp')]:
            env[variable] = str(ROOT / 'test-users' / role / leaf)
        control = ROOT / 'controls' / label
        control.mkdir()
        env['FD_PROOF_ROLE'] = role
        env['FD_PROOF_CONTROL'] = str(control)
        env['GODOT_DISABLE_CRASH_HANDLER'] = '1'
        log = ROOT / (label + '.engine.log')
        command = ('"C:\\Windows\\System32\\cmd.exe" /d /s /c ""' +
                   str(ROOT / 'client/START-CLIENT.cmd') + '" --headless --audio-driver Dummy '
                   '--rendering-method gl_compatibility --max-fps 30 --script "' + str(driver) +
                   '" --log-file "' + str(log) + '""')
        out = (ROOT / (label + '.stdout.log')).open('wb')
        err = (ROOT / (label + '.stderr.log')).open('wb')
        process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=out, stderr=err,
                                   creationflags=0x4 | 0x08000000)
        assert process.pid not in PROTECTED
        item = {'process': process, 'stdout': out, 'stderr': err, 'control': control}
        processes[label] = item
        record = {'label': label, 'role': role, 'command': command, 'cwd': str(ROOT),
                  'environment': {name: env[name] for name in ['APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP',
                                  'TMPDIR', 'FD_PROOF_ROLE', 'FD_PROOF_CONTROL']},
                  'launcher_pid': process.pid, 'job_attached_before_resume': False}
        item['record'] = record
        evidence['runs'].append(record)
        save()
        job.attach_resume(process)
        record['job_attached_before_resume'] = True
        snapshot(label + '_attached')
        bounded_wait(lambda: (control / 'ready').exists(), label + '_ready')
        snapshot(label + '_ready')
        print('READY', label, 'launcher_pid=' + str(process.pid), flush=True)

    def repeat(label):
        control = processes[label]['control']
        (control / 'repeat').write_text('repeat', encoding='ascii')
        bounded_wait(lambda: (control / 'repeated').exists(), label + '_repeat')
        return snapshot(label + '_repeated')

    def exit_run(label):
        item = processes[label]
        item['exit_requested'] = True
        (item['control'] / 'exit').write_text('exit', encoding='ascii')
        bounded_wait(lambda: item['process'].poll() is not None, label + '_exit')
        item['record']['launcher_exit_code'] = item['process'].wait(timeout=5)
        item['stdout'].close()
        item['stderr'].close()
        assert item['record']['launcher_exit_code'] == 0, 'NONZERO_LAUNCHER_EXIT_' + label
        snapshot(label + '_exited')

    try:
        empty = snapshot('empty_baseline')
        assert not compare(empty['identity'])['nonempty_both'], 'BASELINE_NOT_EMPTY'
        assert all(value['file_count'] == 0 for value in empty['identity'].values()), 'BASELINE_HAS_IDENTITY'
        launch('host', 'host')
        host_only = snapshot('host_generated_before_guest')
        assert host_only['identity']['host']['file_count'] > 0, 'HOST_IDENTITY_MISSING'
        launch('guest', 'guest')
        both = snapshot('coexisting_generated')
        result = compare(both['identity'])
        evidence['comparison'] = result
        assert all(result[key] for key in ('nonempty_both', 'paths_distinct', 'same_names', 'sha_distinct')), 'DUAL_IDENTITY_COMPARE_FAILED'
        assert host_only['identity']['host']['files'] == both['identity']['host']['files'], 'GUEST_OVERWROTE_HOST'
        assert all(processes[name]['process'].poll() is None for name in ('host', 'guest')), 'NO_COEXISTENCE'
        baseline = both['identity']
        for label in ('host', 'guest'):
            value = repeat(label)
            assert all(value['identity'][role]['files'] == baseline[role]['files'] for role in baseline), 'REAPPLY_OVERWROTE_IDENTITY'
        exit_run('guest')
        exit_run('host')
        bounded_wait(lambda: job.active() == 0, 'first_pair_job0')
        snapshot('first_pair_job0')
        launch('guest', 'guest-reopen')
        reopened = snapshot('sequential_guest_reopen')
        assert all(reopened['identity'][role]['files'] == baseline[role]['files'] for role in baseline), 'REOPEN_OVERWROTE_IDENTITY'
        exit_run('guest-reopen')
        bounded_wait(lambda: job.active() == 0, 'final_job0')
        evidence['identity_generated_both'] = True
        evidence['no_identity_overwrite'] = True
        evidence['coexistence_observed'] = True
        evidence['sequential_reopen_observed'] = True
    except Exception as exc:
        evidence['failure'] = type(exc).__name__ + ': ' + str(exc)
        print('PROOF_FAILURE=' + evidence['failure'], flush=True)
    finally:
        state = job_state()
        if state['active']:
            evidence['forced_termination'] = True
            job.stop()
        for label, item in processes.items():
            process = item['process']
            if process.poll() is None:
                process.kill()
                evidence['forced_termination'] = True
            item['record']['launcher_exit_code'] = process.wait(timeout=10)
            item['stdout'].close()
            item['stderr'].close()
        final = snapshot('final')
        evidence['job_final'] = final['job']
        evidence['Job0'] = final['job']['active'] == 0
        evidence['observed_process_exit_codes'] = []
        for pid, handle in handles.items():
            code = w.DWORD()
            ok = kernel.GetExitCodeProcess(handle, ctypes.byref(code))
            evidence['observed_process_exit_codes'].append({'pid': pid, 'exit_code': code.value if ok else None})
            kernel.CloseHandle(handle)
        job.close()
        evidence['source_hashes_after'] = {str(path.relative_to(SOURCE)): sha(path) for path in source_files}
        evidence['source_unchanged'] = before_source == evidence['source_hashes_after']
        evidence['copied_artifacts_unchanged'] = all(sha(ROOT / 'client' / name) == before_source[name] for name in ARTIFACTS)
        evidence['logs'] = []
        for label, item in processes.items():
            exe_pids = []
            for suffix in ('engine', 'stdout', 'stderr'):
                path = ROOT / (label + '.' + suffix + '.log')
                if not path.exists():
                    continue
                lines = path.read_text(encoding='utf-8', errors='replace').splitlines()
                keys = []
                for index, line in enumerate(lines, 1):
                    if line.startswith('IDENTITY_PROOF ') or line.startswith('Godot Engine v'):
                        # 不枚举节点、身份属性或凭据；驱动仅输出预定公开字段。
                        keys.append({'line': index, 'text': line})
                    if line.startswith('IDENTITY_PROOF ENV '):
                        exe_pids.append(json.loads(line[len('IDENTITY_PROOF ENV '):])['pid'])
                evidence['logs'].append({'path': str(path), 'sha256': sha(path), 'line_count': len(lines),
                                        'SCRIPT ERROR': sum('SCRIPT ERROR' in line for line in lines),
                                        'Parse Error': sum('Parse Error' in line for line in lines),
                                        'ERROR:': sum('ERROR:' in line for line in lines),
                                        'key_lines': keys})
            item['record']['exe_pids'] = sorted(set(exe_pids))
        evidence['overall_acceptance'] = (not evidence.get('failure') and not evidence['forced_termination']
            and evidence.get('identity_generated_both') and evidence.get('no_identity_overwrite')
            and evidence['Job0'] and evidence['source_unchanged'] and evidence['copied_artifacts_unchanged']
            and all(entry['exit_code'] == 0 for entry in evidence['observed_process_exit_codes'])
            and all(not log[key] for log in evidence['logs'] for key in ('SCRIPT ERROR', 'Parse Error', 'ERROR:')))
        save()
        print(json.dumps({'evidence': str(outfile), 'overall_acceptance': evidence['overall_acceptance'],
                          'Job0': evidence['Job0'], 'forced_termination': evidence['forced_termination'],
                          'runs': evidence['runs'], 'comparison': evidence.get('comparison'),
                          'process_exit_codes': evidence['observed_process_exit_codes']}, ensure_ascii=False, indent=2), flush=True)
    return 0 if evidence['overall_acceptance'] else 1


if __name__ == '__main__':
    sys.exit(run())
