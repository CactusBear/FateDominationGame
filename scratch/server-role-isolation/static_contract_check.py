"""Source/config contract audit only: does not execute GDScript or start Godot."""
import ast
import configparser
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BOOT = (ROOT / 'scripts/net/server_bootstrap.gd').read_text(encoding='utf-8')
CLI = (ROOT / 'scripts/net/server_cli.gd').read_text(encoding='utf-8')

def constant(name):
    return ast.literal_eval(re.search(r'const ' + name + r':Array = (\[.*\])', BOOT)[1])

class SourceContract(unittest.TestCase):
    def test_shared_configuration(self):
        for method in ['read_configuration', 'configured_roles', 'configuration_error']:
            self.assertIn('server_bootstrap.gd").' + method + '(configuration' if method != 'read_configuration' else 'server_bootstrap.gd").read_configuration(path)', CLI)
        self.assertIn('section not in ["server", "data", "relay"]', BOOT)
        self.assertIn('key in ["data","relay"]: return null', BOOT)
        self.assertIn('key not in CONFIGURATION_FIELDS', BOOT)
        self.assertIn('signaling_only and key not in SIGNALING_FIELDS', BOOT)

    def test_no_fake_relay_isolation(self):
        self.assertNotIn('var gateway = preload', CLI)
        self.assertLess(CLI.index('if not roles.has("game"):'), CLI.index('gateway = load('))
        signal = BOOT.split('func _start_signaling(', 1)[1]
        self.assertLess(signal.index('if has_project_autoloads():'), signal.index('_signaling = load('))
        self.assertIn('ProjectSettings.get_property_list()', BOOT)
        self.assertIn('begins_with("autoload/")', BOOT)
        self.assertNotIn('rules_authority_started', BOOT)
        for forbidden in ['server_gateway.gd', 'room_state.gd', 'LoadHelper', 'server_room_manager.gd']:
            self.assertNotIn(forbidden, BOOT)
        self.assertEqual(CLI.count('if gateway != null: gateway.close()'), 2)

    def test_role_rejections_are_explicit(self):
        for snippet in ['not configuration.get("p2p_signaling",false) is bool', 'not configuration.roles is Array', 'configuration.roles.is_empty()', 'role not in ["game","relay"] or roles.has(role)', 'configuration.p2p_signaling != roles.has("relay")', 'not configuration.has("roles") or roles != ["relay"]', 'args.count(flag) != 1']:
            self.assertIn(snippet, BOOT)

    def test_policy_template_alignment(self):
        cfg = configparser.ConfigParser()
        cfg.read(ROOT / 'assets/config/server.cfg', encoding='utf-8')
        policy = (ROOT / 'scripts/net/server_policy_config.gd').read_text(encoding='utf-8')
        defaults = json.loads(re.search(r'const DEFAULTS:Dictionary = (\{.*?\})', policy, re.S)[1].replace(',\n}', '\n}'))
        for key, value in defaults.items():
            self.assertIn(key, constant('CONFIGURATION_FIELDS'))
            self.assertNotIn(key, constant('SIGNALING_FIELDS'))
            self.assertEqual(json.loads(cfg['server'][key]), value)
        self.assertIn('server_policy_config.gd").validate(configuration', CLI)

    def test_platform_signal_and_wrapper_contract(self):
        export = (ROOT / 'export_presets.cfg').read_text(encoding='utf-8')
        for number in [2, 3]:
            cfg = configparser.ConfigParser()
            for suffix in ['', '.options']:
                section = f'preset.{number}{suffix}'
                block = re.search(r'\[' + re.escape(section) + r'\]\n(.*?)(?=\n\[|\Z)', export, re.S)[1]
                cfg.read_string(f'[{section}]\n{block}')
            self.assertEqual(cfg[f'preset.{number}']['custom_features'], '"fate_server"')
            self.assertEqual(cfg[f'preset.{number}']['dedicated_server'], 'true')
            self.assertEqual(cfg[f'preset.{number}.options']['debug/export_console_wrapper'], '2')
        for source in [CLI, BOOT]:
            for entry in ['server_process_signals.gd', '.enable()', '.take_request()', '.disable()']:
                self.assertIn(entry, source)
        self.assertIn('if arguments[index] == "--":', BOOT)
        self.assertIn('result.append_array(arguments.slice(index))', BOOT)

    def test_counterexample_inventory(self):
        # Static classification from extracted source declarations, not a GDScript runtime substitute.
        cases = json.loads((Path(__file__).parent / 'config-counterexamples.json').read_text(encoding='utf-8'))
        self.assertEqual(len(cases), len({case['name'] for case in cases}))
        fields, signal = constant('CONFIGURATION_FIELDS'), constant('SIGNALING_FIELDS')
        for case in cases:
            with self.subTest(name=case['name']):
                kind = case['reject']
                if 'cfg' in case:
                    cfg = configparser.ConfigParser()
                    cfg.read_string(case['cfg'])
                    if kind == 'cfg_section': self.assertTrue(set(cfg.sections()) - {'server', 'data', 'relay'})
                    elif kind == 'cfg_override': self.assertTrue({'data', 'relay'} & set(cfg['server']))
                    else: self.assertTrue(set(cfg['server']) - set(fields))
                else:
                    value = case['configuration']
                    if kind == 'unknown_field': self.assertTrue(set(value) - set(fields))
                    elif kind == 'game_field': self.assertTrue(set(value) - set(signal))
                    else:
                        roles = value.get('roles')
                        old = value.get('p2p_signaling', True)
                        self.assertTrue(roles != ['relay'] or type(old) is not bool or old is False)
        print(f'STATIC_COUNTEREXAMPLES={len(cases)} (inventory only; runtime pending)')

if __name__ == '__main__':
    unittest.main(verbosity=2)
