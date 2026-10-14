"""G04 冻结安全契约；仅 Hermes scratch 夹具。"""
import json
import os
from pathlib import Path
import tempfile
import unittest
from tools.tests.test_release_prepare import load, ROOT, SCRATCH

freeze = load('freeze_under_test', ROOT / 'tools/release/freeze_prepare.py')

class FreezeTests(unittest.TestCase):
    def test_manifest_never_overwrites_source_or_existing_file(self):
        with tempfile.TemporaryDirectory(dir=SCRATCH) as tmp:
            base = Path(tmp); source = base / 'source'; source.mkdir()
            for rel in freeze.FILES:
                (source / rel).write_text('original', encoding='utf-8')
            for manifest in (source / 'project.godot', base / 'existing.json'):
                manifest.write_text('original', encoding='utf-8')
                with self.assertRaises(ValueError):
                    freeze.prepare(source, base / 'target', manifest)
                self.assertEqual(manifest.read_text(encoding='utf-8'), 'original')
                self.assertFalse((base / 'target').exists())

    def test_freeze_strips_only_development_config_and_keeps_runtime_resources(self):
        with tempfile.TemporaryDirectory(dir=SCRATCH) as tmp:
            base = Path(tmp); source = base / 'source'; source.mkdir()
            files = {
                'project.godot': '[autoload]\nGame="*res://scripts/game.gd"\n_mcp_game_helper="*res://addons/godot_ai/runtime/game_helper.gd"\n[editor_plugins]\nenabled=PackedStringArray("res://addons/godot_ai/plugin.cfg")\n[editor]\nversion_control/plugin_name="GitPlugin"\nversion_control/autoload_on_startup=true\n',
                'export_presets.cfg': '[preset.0]\nname="Client"\nplatform="Windows Desktop"\nexport_path="../old.exe"\n[preset.0.options]\nbinary_format/embed_pck=false\n[preset.1]\nname="Linux"\nplatform="Linux"\n',
                'icon.svg': '', 'icon.svg.import': '', 'scripts/game.gd': '',
                'assets/runtime.cfg': 'runtime=true',
                'addons/webrtc_native/webrtc_native.gdextension': '[libraries]\nwindows.release.x86_64="lib/native.dll"\nwindows.debug.x86_64="lib/native-debug.dll"\nlinux.release.x86_64="lib/native.so"\n',
                'addons/webrtc_native/lib/native-debug.dll': 'debug-native',
                'addons/webrtc_native/lib/native.dll': 'native',
                'assets/image.png.import': '[remap]\npath="res://.godot/imported/image.ctex"\n',
                '.godot/imported/image.ctex': 'texture', '.godot/imported/image.md5': 'digest',
            }
            for rel, text in files.items():
                path = source / rel; path.parent.mkdir(parents=True, exist_ok=True); path.write_text(text, encoding='utf-8')
            freeze.prepare(source, base / 'target', base / 'manifest.json')
            target = base / 'target'
            self.assertNotIn('_mcp_game_helper', (target / 'project.godot').read_text())
            self.assertIn('Game=', (target / 'project.godot').read_text())
            self.assertNotIn('GitPlugin', (target / 'project.godot').read_text())
            self.assertNotIn('version_control/autoload_on_startup=true', (target / 'project.godot').read_text())
            self.assertNotIn('addons/godot_ai', (target / 'project.godot').read_text())
            self.assertNotIn('platform="Linux"', (target / 'export_presets.cfg').read_text())
            self.assertIn('include_filter="assets/runtime.cfg"', (target / 'export_presets.cfg').read_text())
            self.assertNotIn('../old.exe', (target / 'export_presets.cfg').read_text())
            for rel in ('assets/runtime.cfg', 'addons/webrtc_native/lib/native.dll', 'addons/webrtc_native/lib/native-debug.dll', '.godot/imported/image.ctex', '.godot/imported/image.md5'):
                self.assertTrue((target / rel).is_file(), '冻结遗漏运行/导出资源: ' + rel)
                self.assertEqual((target / rel).read_bytes(), (source / rel).read_bytes())
            self.assertEqual((source / 'project.godot').read_text(), files['project.godot'])
            freeze.verify(target, base / 'manifest.json')
            manifest_path = base / 'manifest.json'
            value = json.loads(manifest_path.read_text(encoding='utf-8'))
            (target / 'project.godot').write_text('[autoload]\n_mcp_game_helper="*res://addons/godot_ai/runtime/game_helper.gd"\n')
            value['files']['project.godot'] = freeze.sha(target / 'project.godot')
            manifest_path.write_text(json.dumps(value), encoding='utf-8')
            with self.assertRaises(ValueError): freeze.verify(target, manifest_path)
            (target / 'scripts/extra.gd').write_text('tampered')
            with self.assertRaises(ValueError): freeze.verify(target, base / 'manifest.json')

    def test_release_and_audit_reject_output_overwrite_and_invalid_preset(self):
        release = load('release_security', ROOT / 'tools/release/release_prepare.py')
        audit = load('audit_security', ROOT / 'tools/release/package_audit.py')
        with tempfile.TemporaryDirectory(dir=SCRATCH) as tmp:
            base = Path(tmp); project = base / 'project'; project.mkdir()
            (project / 'export_presets.cfg').write_text('[preset.0]\nname="Client"\nplatform="Windows Desktop"\ndedicated_server=false\n[preset.0.options]\nbinary_format/embed_pck=false\n')
            existing = base / 'existing'; existing.mkdir()
            with self.assertRaises(ValueError): release.plan(project, existing, base / 'godot.exe', 'Client')
            with self.assertRaises(ValueError): release.plan(project, base / 'output', base / 'godot.exe', 'Missing')
            with self.assertRaises(ValueError): release.plan(project, base / 'output', base / 'godot.exe', 'Client', role='server')
            with self.assertRaises(ValueError): audit.audit(project, base / 'package', project / 'export_presets.cfg', 'Client')
            manifest = base / 'plan.json'; manifest.write_text('original')
            with self.assertRaises(ValueError): release.main(['--project',str(project),'--output',str(base/'output'),'--godot',str(base/'godot.exe'),'--preset','Client','--manifest',str(manifest)])
            self.assertEqual(manifest.read_text(), 'original')

    def test_real_junction_boundary_and_dry_run_rejections(self):
        import subprocess
        from tools.release.path_safety import new_output
        with tempfile.TemporaryDirectory(dir=SCRATCH) as tmp:
            base = Path(tmp); outside = base / 'outside'; outside.mkdir()
            link = base / 'link'
            result = subprocess.run(['cmd.exe','/c','mklink','/J',str(link),str(outside)], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            try:
                for path in (link / 'new.json', link / 'project', link):
                    with self.assertRaises(ValueError): new_output(path, scratch=True)
                self.assertEqual(list(outside.iterdir()), [])
            finally: os.rmdir(link)
            with self.assertRaises(ValueError): new_output(ROOT / 'never-freeze-here', scratch=True)
            project = base / 'project'
            preset = outside / 'export_presets.cfg'
            preset.write_text('[preset.0]\nname="Client"\nplatform="Windows Desktop"\n[preset.0.options]\nbinary_format/embed_pck=false\n')
            result = subprocess.run(['cmd.exe','/c','mklink','/J',str(project),str(outside)], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            try:
                audit = load('audit_link_preset', ROOT / 'tools/release/package_audit.py')
                with self.assertRaises(ValueError): audit.preset_options(project,'Client')
            finally: os.rmdir(project)
            with self.assertRaises(ValueError): freeze.prepare(base / 'source', base / 'target', base / 'target/manifest.json', dry_run=True)
            self.assertFalse((base / 'target').exists())

    def test_zero_exit_godot_parse_errors_are_blocked(self):
        release = load('release_log_gate', ROOT / 'tools/release/release_prepare.py')
        self.assertTrue(hasattr(release, 'check_export_log'), '缺少导出日志错误门禁')
        for message in (b'SCRIPT ERROR: Parse Error', b'ERROR: Failed to load script', b'ERROR: Cannot get class'):
            with self.assertRaises(ValueError): release.check_export_log(message)
        release.check_export_log(b'Godot Engine\nExport completed')

if __name__ == '__main__': unittest.main()
