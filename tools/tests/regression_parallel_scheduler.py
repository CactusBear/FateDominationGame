"""Stable bounded scheduler API (integration owner may import directly).

Resources(cpu: int, memory: int, disk: int): positive caller-defined reservations.
Task(key: str, resources: Resources, known_parallel=False,
     exclusive_keys=frozenset(), exclusive=False).
run(tasks, launch, *, budget: Resources, jobs=1, cancelled=lambda: False,
    monitor=lambda: None, interval=0.05) -> JSON-serializable report.

Policy: jobs is 1/2/4; undeclared capability or exclusive=True is a FIFO global
barrier. Otherwise disjoint exclusive_keys and SUM of all active reservations
must fit the ONE budget. Caller declares GUI/performance/longrecovery/native-lock
helpers exclusive until proven; never infer capability from rule/no_dependencies.

Callbacks run only on the calling thread. launch(task) returns an owned handle:
 poll()->bool (done including descendants), cancel()->None (synchronous own-only
 stop), finish()->dict with passed:bool and job0:bool. launch must synchronously
 clean up before raising. Ordinary failed results collect; callback exceptions,
 unproven Job0, aggregate monitor failure or user cancel stop further dispatch.
 cancelled() is rechecked before EACH launch; true means no later launch.
 monitor()->None|str is called before EACH launch and on every scheduler cycle:
 caller must include fixed inputs + completed evidence + active jobs in its disk
 accounting, enforce actual process-tree memory/CPU limits, and return a reason
 on aggregate excess. Reservations are admission, NOT an OS disk quota. Subtract
 fixed owner bytes from the original 8GiB envelope; do not grant 8GiB to each job.

Report results retain plan order; expected == executed disjoint-union notrun,
 results keys == executed, checked by accounted. Attempted launch belongs in
 executed even if it raises. errors preserve first and cleanup errors. No Godot,
 scene inspection, filesystem, environment changes or RESULT parser lives here.
"""
from dataclasses import dataclass
import math
import time


@dataclass(frozen=True)
class Resources:
    cpu: int
    memory: int
    disk: int

    def __post_init__(self):
        if any(type(x) is not int or x <= 0 for x in (self.cpu, self.memory, self.disk)):
            raise ValueError('resource budgets must be explicit positive integers')


@dataclass(frozen=True)
class Task:
    key: str
    resources: Resources
    known_parallel: bool = False
    exclusive_keys: frozenset = frozenset()
    exclusive: bool = False

    def __post_init__(self):
        if not isinstance(self.key, str) or not self.key or not isinstance(self.resources, Resources):
            raise ValueError('nonempty key and Resources required')
        if type(self.known_parallel) is not bool or type(self.exclusive) is not bool:
            raise ValueError('capability flags must be booleans')
        if not isinstance(self.exclusive_keys, frozenset) or any(
                not isinstance(k, str) or not k for k in self.exclusive_keys):
            raise ValueError('exclusive_keys must be a frozenset of nonempty strings')


def run(tasks, launch, *, budget, jobs=1, cancelled=lambda: False,
        monitor=lambda: None, interval=0.05):
    """Serial by default. Results are returned in original plan order.

    monitor returns a failure reason (or None); it is called before every launch.
    All callbacks and manifest/result aggregation run on this one calling thread.
    """
    tasks = list(tasks)
    if type(jobs) is not int or jobs not in (1, 2, 4):
        raise ValueError('jobs must be 1, 2 or 4')
    if not isinstance(budget, Resources) or not math.isfinite(interval) or interval < 0:
        raise ValueError('explicit Resources budget and finite nonnegative interval required')
    if len({t.key for t in tasks}) != len(tasks):
        raise ValueError('duplicate task key')
    for task in tasks:
        if not task.key or any(getattr(task.resources, k) > getattr(budget, k)
                               for k in ('cpu', 'memory', 'disk')):
            raise ValueError('task exceeds global budget or has empty key')
    pending, active, rows, executed, errors = list(tasks), {}, {}, [], []
    stop_reason = None

    def failure(stage, exc):
        nonlocal stop_reason
        errors.append({'stage': stage, 'error': repr(exc)})
        stop_reason = stop_reason or stage + '_failure'

    def gate():
        nonlocal stop_reason
        if stop_reason:
            return
        try:
            if cancelled():
                stop_reason = 'user_cancel'
            reason = monitor()
            if reason:
                stop_reason = stop_reason or str(reason)
        except (Exception, KeyboardInterrupt) as exc:
            failure('gate', exc)

    def complete(key, handle, abort=False):
        nonlocal stop_reason
        cleanup_errors = []
        if abort:
            try:
                handle.cancel()
            except (Exception, KeyboardInterrupt) as exc:
                failure('cancel:' + key, exc)
                cleanup_errors.append(repr(exc))
        try:
            row = dict(handle.finish())
        except (Exception, KeyboardInterrupt) as exc:
            failure('finish:' + key, exc)
            original_error = repr(exc)
            try:
                handle.cancel()
                row = dict(handle.finish())
                row.update(passed=False, error=original_error)
            except (Exception, KeyboardInterrupt) as cleanup_exc:
                failure('finish_cleanup:' + key, cleanup_exc)
                cleanup_errors.append(repr(cleanup_exc))
                row = {'passed': False, 'job0': False, 'error': original_error}
        if abort or cleanup_errors:
            row['passed'] = False
            row['cancelled'] = True
        if cleanup_errors:
            row['cleanup_errors'] = cleanup_errors
        row['key'] = key
        rows[key] = row
        if row.get('job0') is not True:
            stop_reason = stop_reason or 'ownership_unproven'
        del active[key]

    def compatible(task):
        if not active:
            return True
        if not task.known_parallel or task.exclusive:
            return False
        if any(not t.known_parallel or t.exclusive for t, _ in active.values()):
            return False
        if any(task.exclusive_keys & t.exclusive_keys for t, _ in active.values()):
            return False
        return all(sum(getattr(t.resources, k) for t, _ in active.values()) +
                   getattr(task.resources, k) <= getattr(budget, k)
                   for k in ('cpu', 'memory', 'disk'))

    while pending or active:
        gate()
        if stop_reason:
            for key, (_, handle) in list(active.items()):
                complete(key, handle, abort=True)
            break
        while pending and len(active) < jobs:
            task = pending[0]  # no bypass of an exclusive barrier
            if not compatible(task):
                break
            gate()
            if stop_reason:
                break
            pending.pop(0)
            executed.append(task.key)  # attempted launch is never silently notrun
            try:
                active[task.key] = (task, launch(task))
            except (Exception, KeyboardInterrupt) as exc:
                failure('launch:' + task.key, exc)
                rows[task.key] = {'key': task.key, 'passed': False, 'job0': False,
                                  'error': repr(exc)}
                break
        for key, (_, handle) in list(active.items()):
            if stop_reason:
                break
            try:
                done = handle.poll()
            except (Exception, KeyboardInterrupt) as exc:
                failure('poll:' + key, exc)
                break
            if done:
                complete(key, handle)
        if active and not stop_reason:
            try:
                time.sleep(interval)
            except KeyboardInterrupt as exc:
                failure('interrupt', exc)
    gate()  # final archived/completed evidence remains inside the global envelope
    expected = [t.key for t in tasks]
    notrun = [t.key for t in pending]
    accounted = (set(expected) == set(executed) | set(notrun) and
                 not set(executed) & set(notrun) and set(rows) == set(executed))
    return {'passed': bool(accounted and not stop_reason and not notrun and all(
                r.get('passed') is True and r.get('job0') is True for r in rows.values())),
            'jobs': jobs, 'expected': expected, 'executed': executed, 'notrun': notrun,
            'accounted': accounted, 'errors': errors,
            'results': [rows[k] for k in expected if k in rows], 'stop_reason': stop_reason}
