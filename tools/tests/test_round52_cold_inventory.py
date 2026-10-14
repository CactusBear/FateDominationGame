"""Real current cold snapshot regression, no engine invocation."""
import sys, unittest
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'release'))
import freeze_prepare
ROOT=Path('E:/FateCandidates/round52-current-roles-20261010-sa1/source-snapshot')

class ColdInventory(unittest.TestCase):
    def test_explicit_cold_keeps_import_hints_without_requiring_old_cache(self):
        try:
            selected=freeze_prepare.inventory(ROOT, [], 'signaling', cold=True)
        except (TypeError, ValueError) as exc:
            self.fail('explicit cold production inventory must not inherit cache: '+str(exc))
        self.assertIn('icon.svg.import', selected)
        self.assertFalse(any(p.startswith('.godot/') for p in selected))
        self.assertIn('addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll',selected)
        self.assertFalse(any(p.startswith(('data/','scripts/system/','scripts/match/')) for p in selected))
    def test_default_inventory_still_rejects_missing_cached_dependency(self):
        with self.assertRaisesRegex(ValueError,'缺少白名单/依赖文件'):
            freeze_prepare.inventory(ROOT, [], 'signaling')

if __name__=='__main__':unittest.main()
