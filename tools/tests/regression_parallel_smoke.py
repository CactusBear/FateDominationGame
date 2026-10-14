"""Explicit two-task correctness smoke and reusable Windows process adapter.

No timing comparison; uses two copies of EXISTING match_journal_test.tscn.
The caller, not the scheduler, declares this narrow headless suite parallel-safe.
"""
import argparse
import ctypes
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import uuid
from regression_parallel_scheduler import Resources, Task, run


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def load_frozen(path):
    spec = importlib.util.spec_from_file_location('frozen_isolated_runner', path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def job_limits(job, resources):
    """Hard aggregate memory/CPU caps for wrapper AND every nested descendant."""
    from ctypes import wintypes as w
    class Basic(ctypes.Structure):
        _fields_ = [('process_time', ctypes.c_int64), ('job_time', ctypes.c_int64),
                    ('flags', w.DWORD), ('minimum_working_set', ctypes.c_size_t),
                    ('maximum_working_set', ctypes.c_size_t), ('active_limit', w.DWORD),
                    ('affinity', ctypes.c_size_t), ('priority', w.DWORD), ('scheduling', w.DWORD)]
    class Extended(ctypes.Structure):
        _fields_ = [('basic', Basic), ('io', ctypes.c_uint64 * 6),
                    ('process_memory', ctypes.c_size_t), ('job_memory', ctypes.c_size_t),
                    ('peak_process_memory', ctypes.c_size_t), ('peak_job_memory', ctypes.c_size_t)]
    limits = Extended()
    limits.basic.flags = 0x2000 | 0x200  # kill-on-close + job aggregate memory
    limits.job_memory = resources.memory
    if not job.kernel.SetInformationJobObject(job.handle, 9, ctypes.byref(limits), ctypes.sizeof(limits)):
        raise ctypes.WinError(ctypes.get_last_error())
    class Cpu(ctypes.Structure):
        _fields_ = [('flags', w.DWORD), ('rate', w.DWORD)]
    cpu = Cpu(1 | 4, max(1, min(10000, math.floor(resources.cpu * 10000 / os.cpu_count()))))
    if not job.kernel.SetInformationJobObject(job.handle, 15, ctypes.byref(cpu), ctypes.sizeof(cpu)):
        raise ctypes.WinError(ctypes.get_last_error())


class OwnedProcess:
    """One scheduler handle; original runner remains the scene/result authority.

    env/cwd are per subprocess, never mutate parent environment/current directory.
    Any init failure synchronously stops the already-owned root before raising.
    """
    def __init__(self, generic, command, env, cwd, evidence, resources, timeout,
                 record, result_reader):
        self.generic, self.root, self.resources = generic, Path(cwd), resources
        self.timeout, self.started = timeout, time.monotonic()
        self.record, self.result_reader = record, result_reader
        self.paths = [Path(evidence) / 'runner.stdout.log', Path(evidence) / 'runner.stderr.log']
        self.streams, self.proc, self.job, self.finished = [], None, None, None
        self.record.update(command=list(command), exited=False, launch_registered=True)
        try:
            self.job = generic.OwnedJob()
            job_limits(self.job, resources)
            self.streams = [p.open('wb') for p in self.paths]
            self.proc = subprocess.Popen(command, env=dict(env), cwd=self.root,
                                         stdout=self.streams[0], stderr=self.streams[1], creationflags=4)
            self.record['pid'] = self.proc.pid
            self.job.attach_resume(self.proc)
        except BaseException:
            try:
                if self.job is not None and self.job.active(): self.job.stop()
                if self.proc is not None:
                    if self.proc.poll() is None: self.proc.kill()
                    self.proc.wait(timeout=15)
                self.record.update(exited=True, active_owned_processes=0)
            finally:
                for stream in self.streams: stream.close()
                if self.job is not None: self.job.close()
            raise

    def cancel(self):
        if self.finished is not None: return
        self.record['cancelled'] = True
        self.job.stop()  # suspended root was assigned before resume; no PID/name sweep
        self.proc.wait(timeout=15)

    def poll(self):
        reason = None
        if time.monotonic() - self.started > self.timeout: reason = 'outer_timeout'
        elif self.generic.tree_bytes(self.root) > self.resources.disk: reason = 'case_disk_budget'
        if reason:
            self.record['budget_failure'] = reason
            self.cancel()
        return self.proc.poll() is not None and self.job.active() == 0

    def finish(self):
        if self.finished is not None: return dict(self.finished)
        try:
            code = self.proc.wait(timeout=15)
            active = self.job.active()
            if active:
                raise RuntimeError('owned descendants still active at finish')
            for stream in self.streams: stream.close()
            self.job.wait_log_release(self.paths)
            self.record.update(exit_code=code, active_owned_processes=active,
                               exited=True, log_handles_released=True)
            try:
                row = dict(self.result_reader(code))
            except Exception as exc:
                row = {'passed': False, 'error': 'result/evidence: ' + repr(exc)}
            row.update(job0=True, exit_code=code, cancelled=self.record.get('cancelled', False))
            if self.record.get('cancelled') or self.record.get('budget_failure'): row['passed'] = False
            self.finished = row
            return dict(row)
        finally:
            for stream in self.streams: stream.close()
            self.job.close()


def scene_result(generic, root, evidence, code):
    """Read exact original-runner receipt; do not reinterpret RESULT or CHECK."""
    # Job0 is established by OwnedProcess before this callback. Preserve partial
    # generic evidence even when cancellation prevented its final JSON summary.
    for candidate in (root / 'runs').glob('isolated-*'):
        candidate = generic.contained(candidate, root)
        destination = evidence / ('retained-' + candidate.name)
        destination.mkdir()
        receipt = candidate / 'manifest.json'
        if receipt.is_file(): shutil.copyfile(generic.no_links(receipt), destination / 'manifest.json')
        inner_evidence = candidate / 'evidence'
        if inner_evidence.is_dir():
            generic.tree_bytes(inner_evidence)
            shutil.copytree(inner_evidence, destination / 'evidence')
    summary = json.loads((evidence / 'runner.stdout.log').read_text(encoding='utf-8'),
                         object_pairs_hook=generic.unique_fields)
    path = generic.contained(summary['manifest'], root)
    manifest = json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=generic.unique_fields)
    archive = evidence / 'original_runner'
    archive.mkdir()
    shutil.copyfile(path, archive / 'manifest.json')
    # The entire outer Job is zero before copying, never scan a live publisher.
    shutil.copytree(path.parent / 'evidence', archive / 'evidence')
    inner_job0 = bool(manifest['processes']) and all(
        p.get('exited') is True and p.get('active_owned_processes') == 0 and
        p.get('log_handles_released') is True for p in manifest['processes'])
    passed = (code == 0 and summary.get('passed') is True and manifest.get('passed') is True
              and manifest.get('cleanup') == 'generated_removed' and inner_job0)
    return {'passed': passed, 'original_manifest': str(archive / 'manifest.json'),
            'inner_job0': inner_job0, 'analysis': manifest.get('analysis'),
            'original_error': manifest.get('error'), 'original_cleanup': manifest.get('cleanup'),
            'user_probes': manifest.get('user_probes')}


def smoke(args):
    source, approved, engine = Path(args.project), Path(args.root), Path(args.godot)
    # Freeze generic bytes exactly ONCE before launch; never hot-load repo changes.
    raw_generic = (source / 'tools/run_isolated_godot_test.py').read_bytes()
    generic_hash = hashlib.sha256(raw_generic).hexdigest()
    # Bootstrap only the frozen bytes. All actual paths are validated by that copy.
    import types
    generic = types.ModuleType('frozen_isolated_runner')
    exec(compile(raw_generic, '<frozen-generic-' + generic_hash + '>', 'exec'), generic.__dict__)
    approved = generic.physical_e(approved)
    source = generic.physical_e(source)
    engine = generic.physical_e(engine)
    budget = Resources(args.cpu, args.memory_bytes, args.max_bytes)
    quota = Resources(args.case_cpu, args.case_memory_bytes, args.case_max_bytes)
    if budget.cpu > os.cpu_count(): raise ValueError('CPU budget exceeds machine logical CPUs')
    if any(getattr(quota, k) > getattr(budget, k) for k in ('cpu', 'memory', 'disk')):
        raise ValueError('case reservation exceeds global budget')
    if shutil.disk_usage(approved).free < args.min_free_bytes:
        raise ValueError('insufficient global free space before setup')
    token = uuid.uuid4().hex
    owner = approved / ('isolated-' + token)
    owner.mkdir()
    generated, evidence = owner / 'generated', owner / 'evidence'
    generated.mkdir()
    evidence.mkdir()
    tool = generated / 'frozen_runner.py'
    tool.write_bytes(raw_generic)
    records = []
    manifest = {'run_id': token, 'generated': str(generated), 'processes': records,
                'generic_sha256': generic_hash, 'generic_origin': str(source / 'tools/run_isolated_godot_test.py'),
                'budget': budget.__dict__, 'case_reservation': quota.__dict__, 'passed': False,
                'mode': 'correctness_smoke_only_no_speed_measurement', 'copy_policy': 'independent_copy_no_hardlinks',
                'ports': 'none: existing journal suite does not bind external ports', 'source_files': []}
    result = None
    try:
        # Narrow standalone project, existing scene and script unchanged. Preserve
        # application identity and 20-thread pool; no production/full-game claim.
        original = (source / 'project.godot').read_text(encoding='utf-8-sig')
        blocks = []
        for section in ('application', 'threading'):
            match = re.search(r'^\[' + section + r'\]\s*\n(.*?)(?=^\[|\Z)', original, re.M | re.S)
            if not match: raise ValueError('required smoke configuration section missing')
            lines = [x for x in match[1].splitlines() if not x.startswith(('run/main_scene', 'config/icon='))]
            blocks.append('[' + section + ']\n' + '\n'.join(lines))
        config = ('config_version=5\n' + '\n'.join(blocks) + '\n').encode('utf-8')
        names = ['tests/match_journal_test.tscn', 'tests/match_journal_test.gd', 'scripts/match/match_journal.gd']
        snapshot = {name: generic.contained(source / name, source).read_bytes() for name in names}
        snapshot['project.godot'] = config
        manifest.update(project_configuration_transformation='standalone application/threading; remove missing main_scene/icon; omit other sections',
                        original_project_sha256=digest(source / 'project.godot'),
                        engine_sha256=digest(engine))
        for name, raw in snapshot.items():
            manifest['source_files'].append({'path': name, 'sha256': hashlib.sha256(raw).hexdigest(), 'bytes': len(raw)})
        cases = {}
        for key in ('journal-A', 'journal-B'):
            case = generated / key
            case.mkdir()
            project, runs, tools = case / 'project', case / 'runs', case / 'tools'
            for folder in (project, runs, tools): folder.mkdir()
            for name, raw in snapshot.items():
                target = project / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(raw)
            local_tool = tools / 'runner.py'
            local_tool.write_bytes(raw_generic)
            local_engine = tools / engine.name
            shutil.copyfile(engine, local_engine)
            if digest(local_tool) != generic_hash or digest(local_engine) != manifest['engine_sha256']:
                raise ValueError('frozen tool/engine copy hash mismatch')
            env = os.environ.copy()
            for name in ('APPDATA', 'LOCALAPPDATA', 'TMP', 'TEMP', 'TMPDIR'):
                target = case / name.lower()
                target.mkdir()
                env[name] = str(target)
            out = evidence / key
            out.mkdir()
            command = [sys.executable, '-B', str(local_tool), '--project', str(project),
                       '--scene', 'res://tests/match_journal_test.tscn', '--root', str(runs),
                       '--godot', str(local_engine), '--freeze', '--include', 'tests/match_journal_test.gd',
                       '--include', 'scripts/match/match_journal.gd', '--timeout', str(args.timeout),
                       '--max-bytes', str(quota.disk), '--min-free-bytes', str(args.min_free_bytes)]
            cases[key] = (case, env, out, command)
        tasks = [Task(key, quota, known_parallel=True) for key in cases]
        handles = []
        def launch(task):
            case, env, out, command = cases[task.key]
            record = {'label': task.key}
            records.append(record)  # registration precedes any OS launch
            handle = OwnedProcess(generic, command, env, case, out, quota, args.outer_timeout,
                                  record, lambda code: scene_result(generic, case, out, code))
            handles.append(handle)
            return handle
        def monitor():
            size = generic.tree_bytes(owner)  # includes inputs, completed logs, temp and evidence
            manifest['peak_observed_bytes'] = max(size, manifest.get('peak_observed_bytes', 0))
            if size > budget.disk: return 'global_disk_budget'
            if shutil.disk_usage(owner).free < args.min_free_bytes: return 'global_free_space_budget'
        result = run(tasks, launch, budget=budget, jobs=args.jobs,
                     cancelled=lambda: bool(args.cancel_file and Path(args.cancel_file).exists()), monitor=monitor)
        manifest['scheduler'] = result
        manifest['passed'] = result['passed']
        # Record isolated source hashes AFTER execution as well as before copying.
        for key, (case, _, _, _) in cases.items():
            for name, raw in snapshot.items():
                if (case / 'project' / name).read_bytes() != raw:
                    raise ValueError('case input mutated: ' + key + '/' + name)
            if digest(case / 'tools' / 'runner.py') != generic_hash:
                raise ValueError('case frozen generic mutated')
    except BaseException as exc:
        manifest['passed'] = False
        manifest['error'] = repr(exc)
    finally:
        # Snapshot evidence then consume ONLY this UUID tree after ALL outer Jobs0.
        # On uncertainty retain it; cleanup errors never replace the original error.
        (owner / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
        try:
            if records and all(p.get('exited') is True and p.get('active_owned_processes') == 0 for p in records):
                generic.delete_owned(generated, owner)
                manifest['cleanup'] = 'generated_removed'
            else:
                manifest['cleanup'] = 'retained_ownership_unproven_or_no_launch'
                manifest['passed'] = False
        except Exception as exc:
            manifest['cleanup'] = 'retained: ' + repr(exc)
            manifest['passed'] = False
        (owner / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'passed': manifest['passed'], 'manifest': str(owner / 'manifest.json'),
                      'generic_sha256': generic_hash, 'cleanup': manifest['cleanup']}, ensure_ascii=False))
    return 0 if manifest['passed'] else 1


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('project', 'root', 'godot'): p.add_argument('--' + name, required=True)
    p.add_argument('--jobs', type=int, choices=(1, 2, 4), default=1)
    for name in ('cpu', 'memory-bytes', 'max-bytes', 'case-cpu', 'case-memory-bytes', 'case-max-bytes', 'min-free-bytes'):
        p.add_argument('--' + name, type=int, required=True)
    p.add_argument('--timeout', type=float, required=True)
    p.add_argument('--outer-timeout', type=float, required=True)
    p.add_argument('--cancel-file')
    args = p.parse_args()
    if any(not math.isfinite(x) or x <= 0 for x in (args.timeout, args.outer_timeout)) or args.min_free_bytes < 0:
        p.error('invalid explicit time/free-space budget')
    return smoke(args)


if __name__ == '__main__':
    raise SystemExit(main())
