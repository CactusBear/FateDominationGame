"""No-kill policy tests. Native effects are stubbed unless explicitly smoke-tested."""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

MODULE = Path(__file__).parents[1] / 'run_isolated_godot_test.py'
spec = importlib.util.spec_from_file_location('no_kill_runner', MODULE)
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)


class PolicyTests(unittest.TestCase):
    def test_no_kill_budget_retains_unknown_exit_and_stops_launch(self):
        import inspect
        self.assertIn('no_kill', inspect.signature(r.execute).parameters, 'explicit no-kill strategy missing')
        class Process:
            pid = 123
            _handle = 123
            def poll(self): return None
            def kill(self): raise AssertionError('kill forbidden')
            def terminate(self): raise AssertionError('terminate forbidden')
            def close(self): raise AssertionError('live handle must be retained')
        class Job:
            def __init__(self, *, no_kill=False):
                if not no_kill: raise AssertionError('no-kill not propagated')
            def launch(self, *args): return Process()
            def active(self): return 1
            def identities(self): return [{'pid':123, 'creation_time_100ns':456}]
            def stop(self): raise AssertionError('TerminateJobObject forbidden')
            def close(self): raise AssertionError('live job must be retained')
        with tempfile.TemporaryDirectory(dir=os.environ['ISOLATED_TEST_ROOT']) as name:
            base = Path(name)
            g, e = base / 'generated', base / 'evidence'
            g.mkdir(); e.mkdir()
            records = []
            with patch.object(r, 'OwnedJob', Job), patch.object(r, 'process_identity', return_value={'pid':123, 'creation_time_100ns':456}):
                with self.assertRaisesRegex(r.SafetyError, 'timeout'):
                    r.execute(['fake'], {}, g, e, 'timeout', {'seconds':0.001,'bytes':1000000,'min_free':0}, records, no_kill=True)
                self.assertIsNone(records[0]['exit_code'])
                self.assertFalse(records[0]['exited'])
                self.assertEqual(records[0]['active_owned_processes'], 1)
                self.assertTrue(records[0]['retained'])
                self.assertEqual(records[0]['owned_process_identities'][0]['creation_time_100ns'], 456)
                snapshot = e / 'timeout.observation.stdout.log'
                before = snapshot.read_bytes()
                (e / 'timeout.stdout.log').write_bytes(b'late output')
                self.assertEqual(snapshot.read_bytes(), before)
                with self.assertRaisesRegex(r.SafetyError, 'launch blocked'):
                    r.execute(['must-not-launch'], {}, g, e, 'next', {'seconds':1,'bytes':1000000,'min_free':0}, records, no_kill=True)
                self.assertEqual(len(records), 1)
            r.RETAINED.clear()  # fake handles only; never use to abandon real ownership


    def test_failures_and_all_budget_branches_never_cancel(self):
        class Process:
            pid = 123; _handle = 123
            def poll(self): return code
            def kill(self): raise AssertionError('kill forbidden')
            def terminate(self): raise AssertionError('terminate forbidden')
            def close(self): pass
        class Job:
            handle = 123
            def __init__(self, *, no_kill=False):
                if not no_kill: raise AssertionError('wrong policy')
            def launch(self, *args):
                if scenario == 'assign': raise OSError('atomic assignment refused before create')
                if scenario == 'postcreate':
                    self.launched_process = Process()
                    raise OSError('post-create release error')
                return Process()
            def active(self): return 0 if scenario == 'assign' else 1
            def identities(self): return [] if scenario == 'assign' else [{'pid':123,'creation_time_100ns':456}]
            def close(self):
                if scenario != 'assign': raise AssertionError('closing live job forbidden')
            def stop(self): raise AssertionError('TerminateJobObject forbidden')
            def wait_log_release(self, paths): pass
        for scenario, code in [('bytes',None),('space',None),('metadata',None),('assign',None),('postcreate',None),('known-root-exit',7)]:
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory(dir=os.environ['ISOLATED_TEST_ROOT']) as name:
                base=Path(name); g=base/'generated'; e=base/'evidence'; g.mkdir(); e.mkdir()
                records=[]
                from types import SimpleNamespace
                with patch.object(r,'OwnedJob',Job), patch.object(r,'process_identity',return_value={'pid':123,'creation_time_100ns':456}), \
                     patch.object(r.subprocess,'Popen',side_effect=AssertionError('legacy launch forbidden')), \
                     patch.object(r.os,'kill',side_effect=AssertionError('OS.kill forbidden')), \
                     patch.object(r,'tree_bytes',side_effect=PermissionError('metadata') if scenario=='metadata' else None,return_value=2000000 if scenario=='bytes' else 0), \
                     patch.object(r.shutil,'disk_usage',return_value=SimpleNamespace(free=0 if scenario=='space' else 1000)):
                    budgets={'seconds':0.01 if scenario=='known-root-exit' else 10,'bytes':1000000,'min_free':1}
                    with self.assertRaises((r.SafetyError,OSError)):
                        r.execute(['fake'],{},g,e,scenario,budgets,records,no_kill=True)
                    self.assertEqual(records[0]['exit_code'], code)
                    self.assertTrue(records[0]['launch_blocked'])
                    self.assertTrue(g.exists())
                    if scenario == 'assign':
                        self.assertFalse(records[0]['started'])
                        self.assertTrue(records[0]['exited'])
                    else:
                        self.assertTrue(records[0]['retained'])
                        self.assertEqual(records[0]['owned_process_identities'][0]['pid'],123)
                r.RETAINED.clear()  # exclusively fake handles

    def test_native_no_kill_job_limit_and_attach_stop_guards(self):
        if os.name != 'nt': self.skipTest('Windows')
        job = r.OwnedJob(no_kill=True)
        try:
            import ctypes as c
            # Job extended limits begins with BasicLimitInformation; LimitFlags offset 16.
            buffer = c.create_string_buffer(144)
            self.assertTrue(job.kernel.QueryInformationJobObject(job.handle,9,buffer,len(buffer),None))
            self.assertEqual(c.c_uint32.from_buffer(buffer,16).value & 0x2000,0)
            with patch.object(job.kernel,'TerminateJobObject',side_effect=AssertionError('termination API')), \
                 patch.object(job.kernel,'AssignProcessToJobObject',side_effect=AssertionError('non-atomic attach')):
                with self.assertRaisesRegex(r.SafetyError,'forbidden'): job.stop()
                with self.assertRaisesRegex(r.SafetyError,'atomic'): job.attach_resume(object())
        finally:
            self.assertEqual(job.active(),0)
            job.close()

    def test_late_receipt_does_not_rewrite_timeout_observation(self):
        import json
        class Process:
            _handle=1
            def poll(self): return 9
            def close(self): pass
        class Job:
            def active(self): return 0
            def identities(self): return []
            def wait_log_release(self, paths): pass
            def close(self): pass
        with tempfile.TemporaryDirectory(dir=os.environ['ISOLATED_TEST_ROOT']) as name:
            e=Path(name); out=e/'x.stdout.log'; err=e/'x.stderr.log'
            out.write_bytes(b'late natural'); err.write_bytes(b'')
            original={'label':'x','exit_code':None,'retained':True,'root_identity':{'pid':1,'creation_time_100ns':2}}
            path=e/'x.observation.json'; path.write_text(json.dumps(original))
            before=path.read_bytes()
            r.RETAINED['fake']=(Job(),Process(),out,err,original)
            late=r.observe_retained('fake',1)
            self.assertEqual(late['exit_code'],9)
            self.assertEqual(path.read_bytes(),before)
            self.assertIsNone(original['exit_code'])
            self.assertNotIn('fake',r.RETAINED)

    def test_atomic_job_list_failure_refuses_before_process_creation(self):
        if os.name != 'nt': self.skipTest('Windows')
        job=r.OwnedJob(no_kill=True)
        try:
            with tempfile.TemporaryDirectory(dir=os.environ['ISOLATED_TEST_ROOT']) as name:
                g=Path(name)
                with (g/'out').open('wb') as out, (g/'err').open('wb') as err, \
                     patch.object(job.kernel,'UpdateProcThreadAttribute',return_value=0), \
                     patch.object(job.kernel,'CreateProcessW',side_effect=AssertionError('must refuse before launch')), \
                     patch.object(job.kernel,'TerminateJobObject',side_effect=AssertionError('forbidden')):
                    with self.assertRaisesRegex(r.SafetyError,'JOB_LIST unavailable'):
                        job.launch(['not-executed'],{},g,out,err)
            self.assertEqual(job.active(),0)
        finally: job.close()

    def test_cli_policy_reaches_import_scene_and_source_drift_still_rejects(self):
        import types
        import json
        for drift in (False, True):
            with self.subTest(drift=drift), tempfile.TemporaryDirectory(dir=os.environ['ISOLATED_TEST_ROOT']) as name:
                base=Path(name); project=base/'source'; runs=base/'runs'; project.mkdir(); runs.mkdir()
                (project/'project.godot').write_text('[application]\nconfig/name="unit"\n')
                (project/'a.tscn').write_text('[gd_scene format=3]\n')
                (project/'fake.exe').write_bytes(b'not executable')
                args=types.SimpleNamespace(root=str(runs),project=str(project),godot=str(project/'fake.exe'),scene='res://a.tscn',timeout=1,max_bytes=1000000,min_free_bytes=0,freeze=True,include=[],no_kill=True,quit_after=60)
                calls=[]
                def execute(command,env,g,e,label,budgets,records,*,no_kill=False):
                    self.assertTrue(no_kill)
                    calls.append((label,command,env.copy()))
                    return 'CHECK yes true\nRESULT unit checks=1 failures=[]','',0
                real_copy=r.shutil.copyfile
                def copy(source,target,*a,**kw):
                    result=real_copy(source,target,*a,**kw)
                    if drift and Path(source)==project/'project.godot':
                        (project/'project.godot').write_text('[application]\nconfig/name="DRIFT"\n')
                    return result
                with patch.object(r,'run_two_phase_probe',return_value={'writes':[]}),patch.object(r,'execute',side_effect=execute),patch.object(r.shutil,'copyfile',side_effect=copy):
                    code=r.run(args)
                manifest=json.loads(next(runs.glob('*/manifest.json')).read_text(encoding='utf-8'))
                if drift:
                    self.assertEqual(code,1)
                    self.assertIn('source changed during freeze',manifest['error'])
                    self.assertEqual(calls,[])
                else:
                    self.assertEqual(code,0)
                    self.assertEqual([x[0] for x in calls],['import','scene'])
                    self.assertIn('--quit-after',calls[1][1])
                    self.assertEqual(calls[1][1][-1],'60')
                    self.assertTrue(all(Path(env['TMP']).drive.upper()=='E:' for _,_,env in calls))

    def test_invalid_report_prevents_authorized_write_launch(self):
        with tempfile.TemporaryDirectory(dir=os.environ['ISOLATED_TEST_ROOT']) as name:
            g=Path(name); probe=g/'probe'; probe.mkdir(); (probe/'project.godot').write_text('[application]\n')
            evidence=g/'evidence'; evidence.mkdir()
            with patch.object(r,'execute',return_value=('', '', 0)) as execute:
                with self.assertRaisesRegex(r.SafetyError,'missing real'):
                    r.run_two_phase_probe(Path('fake'),probe,{},g,evidence,'t',{},[])
                self.assertEqual(execute.call_count,1)
                self.assertTrue(execute.call_args.kwargs['no_kill'])
                self.assertFalse((evidence/'probe-authorization.json').exists())

    def test_probe_first_stage_only_reports_then_python_authorizes(self):
        self.assertTrue(hasattr(r, 'READONLY_PROBE_SCRIPT'), 'two-phase read-only script missing')
        self.assertNotIn('OS.kill', r.READONLY_PROBE_SCRIPT)
        self.assertNotIn('FileAccess.open("user://', r.READONLY_PROBE_SCRIPT)
        with tempfile.TemporaryDirectory(dir=os.environ['ISOLATED_TEST_ROOT']) as name:
            g = Path(name)
            path = g / 'data'; path.mkdir()
            import json
            rows = [{'role':role,'pid':pid,'path':str(path),'token':'t', 'phase':'report',
                     'worker_pool_max_threads':2, 'environment':{'APPDATA':str(g)}} for role,pid in [('main',1),('worker',2)]]
            output = '\n'.join('USER_PROBE '+json.dumps(x) for x in rows) + '\nOWNED_CHILD 2\nCHILD_EXITED 2\nCHILD_EXIT_CODE 0'
            approved = r.verify_report_probe(output, g, 't')
            self.assertEqual(len(approved), 2)
            self.assertEqual(list(path.iterdir()), [])
            rows[1]['path'] = 'C:/Users/Administrator'
            with self.assertRaises(r.SafetyError):
                r.verify_report_probe('\n'.join('USER_PROBE '+json.dumps(x) for x in rows), g, 't')


if __name__ == '__main__':
    unittest.main()
