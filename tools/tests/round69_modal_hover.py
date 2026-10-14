"""One GUI owner; immutable production input, sole-guard RED and current gates."""
import sys
sys.dont_write_bytecode = True
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import uuid

REPO = Path(__file__).resolve().parents[2]

def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

r = load_module('round69_isolated', REPO / 'tools/run_isolated_godot_test.py')
e = load_module('round69_evidence', REPO / 'tools/tests/test_round29_integrated_evidence.py')
b = load_module('round69_browsing', REPO / 'tools/tests/round64_shared_browsing.py')
OWNED_TESTS = ['tests/round69_modal_hover_test.gd', 'tests/round69_modal_hover_test.tscn', 'tests/battle_play_groups_test.gd']
BOARD = 'scripts/game_scene/battle_board_v2.gd'

SPECIAL_VIEWER_SCRIPT = '''extends Node
var checks := 0
var failures: Array[String] = []
var board
func check(ok: bool, label: String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)
func _ready() -> void:
	call_deferred("run")
func run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("window"):
		check(false, "independent viewer requires real window")
		finish(); return
	board = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()
	get_tree().root.add_child(board)
	for pid in GameData.player_data_library:
		board._seat_controller.set_kind(int(pid), SeatController.REMOTE)
	GameProgress.reset_progress()
	EffectManager.reset_runtime()
	await get_tree().create_timer(0.8).timeout
	var models: Dictionary = {}
	for object in GameData.objects:
		if object is BaseCard and object._name in ["jewel_card", "yin_qi_bullet"]:
			models[object._name] = object
		if object is BaseSkill and not object._is_awakened and not models.has("unawakened_skill"):
			models.unawakened_skill = object
	for master in GameData.loaded_masters:
		for object in master._other_things:
			if object is BaseCard and object._name == "jewel_card": models.jewel_card = object
	for key in ["jewel_card", "yin_qi_bullet", "unawakened_skill"]:
		check(models.has(key), "actual loader instance exists " + key)
	if not failures.is_empty(): finish(); return
	var owner := -1
	for pid in GameData.player_data_library:
		if int(pid) != board._local_player_id: owner = int(pid); break
	check(owner >= 0, "independent normal source observer differs from owner")
	if owner < 0: finish(); return
	var real_cards: Array = []
	for key in ["jewel_card", "yin_qi_bullet", "unawakened_skill"]:
		var card: BaseCard = CloneObject.new().exec(models[key])
		card.set_concealed(true)
		real_cards.append(card)
		check(not card._card_back_img.is_empty() and LoadHelper.texture_exists(card._card_back_img), "loader declared back exists " + key)
	GameData.player_data_library[owner].discard = real_cards
	board._source.invalidate()
	var source: Dictionary = board._source.read_view()
	var projected: Array = []
	for player in source.players:
		if int(player.id) == owner: projected = player.discard
	check(projected.size() == 3, "normal source exposes exactly three hidden backs")
	if projected.size() != 3: finish(); return
	board._show_card_browser("声明卡背独立查看器", projected)
	await get_tree().process_frame
	await get_tree().process_frame
	var row: Control = board.get_node("CardBrowser/Panel/CardScroll/Row")
	check(row.get_child_count() == 3, "normal CardBrowser renders all three real source slots")
	for i in mini(3, row.get_child_count()):
		var card: Dictionary = projected[i]
		var img: TextureRect = row.get_child(i).get_node("Img")
		var texture_path: String = img.texture.resource_path if img.texture != null else ""
		var exact: bool = img.texture != null and not texture_path.is_empty() and texture_path == str(card.get("back_image", "")) and texture_path == real_cards[i]._card_back_img
		check(exact, "source declared back equals actual texture " + str(i))
		check(not card.get("visible", true) and not card.has("image") and not card.has("name") and not card.has("description") and texture_path != real_cards[i]._card_img, "source and normal slot never reveal face " + str(i))
		check(img.is_visible_in_tree() and img.get_global_rect().size.x > 0 and img.get_global_rect().size.y > 0, "normal viewer slot is visible " + str(i))
		print("VISUAL_GATE ", JSON.stringify({"label": "independent-viewer-" + str(i), "passed": exact and texture_path != real_cards[i]._card_img, "source_back_image": card.get("back_image"), "texture_resource_path": texture_path, "actual_model_name": real_cards[i]._name, "face_hidden": texture_path != real_cards[i]._card_img}))
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png("res://tests/runtime_reports/round72-special-viewer.png") == OK, "independent normal viewer native screenshot saved")
	finish()
func finish() -> void:
	if is_instance_valid(board): board.queue_free()
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
'''

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def records(text, prefix):
    return [json.loads(line[len(prefix):]) for line in text.splitlines() if line.startswith(prefix)]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', required=True, help='immutable physical E snapshot, not live repository')
    parser.add_argument('--label', required=True)
    parser.add_argument('--red-only', action='store_true', help='fixture diagnostic, no current window acceptance')
    parser.add_argument('--current-final', action='store_true', help='one final current matrix after separately archived input controls; never modifies production')
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z0-9-]+', args.label):
        raise ValueError('invalid label')
    source = r.physical_e(args.source)
    if source == REPO.resolve():
        raise ValueError('requires separate immutable production input')
    input_record = json.loads((source / 'source-manifest.json').read_text(encoding='utf-8'))
    source_hashes = input_record['hashes']
    parent = r.physical_e('E:/scratch') / ('round69-modal-hover-' + args.label)
    parent.mkdir(exist_ok=True)
    token = uuid.uuid4().hex
    root = parent / ('isolated-' + token)
    root.mkdir()
    gen = root / 'generated'; gen.mkdir()
    evidence = root / 'evidence'; evidence.mkdir()
    target = gen / 'project'; target.mkdir()
    m = {'run_id':token, 'generated':str(gen), 'root':str(root), 'immutable_source':str(source), 'processes':[], 'suites':[], 'cleanup':'not_started', 'passed':False,
         'scope':'modal regression and original geometry; producer privacy revision requires a distinct future freeze', 'no_user_pid_28100':True}
    budgets = {'seconds':180, 'bytes':8589934592, 'min_free':1073741824}
    env = os.environ.copy()
    for key in ['APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'TMPDIR']:
        path = gen / key.lower(); path.mkdir(); env[key] = str(path)
    fixture = gen / 'fixtures'; fixture.mkdir()
    env['FATE_TEST_SCRATCH_ROOT'] = fixture.as_posix()
    env.pop('HERMES_RECOVERY_VALIDATION_ROOT', None)
    m['isolated_environment'] = {key:env[key] for key in ['APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR']}
    files = [Path(x) for x in source_hashes]
    frozen = {}
    current_board = None
    try:
        for rel in files:
            if sha(source / rel) != source_hashes[rel.as_posix()]:
                raise ValueError('immutable input drift: ' + rel.as_posix())
            dest = target / rel; dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source / rel, dest)
        # Explicit owned test overlay only. Never reread mutable board/builder/mirror.
        for rel in OWNED_TESTS:
            shutil.copyfile(REPO / rel, target / rel)
        m['source_hashes'] = {p.as_posix():sha(target / p) for p in files}
        m['owned_source_hashes'] = {p:sha(REPO / p) for p in OWNED_TESTS}
        m['runner_dependencies'] = {p.relative_to(REPO).as_posix():sha(p) for p in [Path(__file__), REPO/'tools/tests/round64_shared_browsing.py', REPO/'tools/run_isolated_godot_test.py', REPO/'tools/tests/test_round29_integrated_evidence.py']}
        config, transform = e.transform_isolated_editor_vcs((target/'project.godot').read_text(encoding='utf-8-sig'))
        (target/'project.godot').write_text(config, encoding='utf-8')
        m['editor_transform'] = transform
        (target/'tests/round64_shared_browsing_test.gd').write_text(b.BROWSING_SCRIPT, encoding='utf-8')
        (target/'tests/round64_shared_browsing_test.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://tests/round64_shared_browsing_test.gd" id="1"]\n[node name="Round64Browsing" type="Node"]\nscript = ExtResource("1")\n', encoding='utf-8')
        m['browsing_script_sha256'] = sha(target/'tests/round64_shared_browsing_test.gd')
        frozen = {p.as_posix():sha(target/p) for p in files}
        engine_source = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe')
        engine = gen/'Godot.exe'; shutil.copyfile(engine_source, engine)
        m['engine_sha256'] = sha(engine)
        if sha(engine_source) != m['engine_sha256']: raise ValueError('engine copy drift')
        probe = gen/'probe'; probe.mkdir()
        app = re.search(r'^\[application\]\s*\n(.*?)(?=^\[|\Z)',config,re.M|re.S)[1]
        threads = re.search(r'^\[threading\]\s*\n(.*?)(?=^\[|\Z)',config,re.M|re.S)[1]
        (probe/'project.godot').write_text('config_version=5\n[application]\n'+app+'\n[threading]\n'+threads,encoding='utf-8')
        (probe/'probe.gd').write_text(r.PROBE_SCRIPT,encoding='utf-8')
        out,err,code = r.execute([str(engine),'--headless','--path',str(probe),'--script','res://probe.gd','--',token,'main',str(gen)],env,gen,evidence,'probe',budgets,m['processes'])
        if code or re.search(r'SCRIPT ERROR|ERROR:',out+err): raise ValueError('physical E probe failed')
        m['physical_probes'] = r.verify_probe(out,gen,token)
        out,err,code = r.execute([str(engine),'--headless','--editor','--import','--path',str(target)],env,gen,evidence,'import',budgets,m['processes'])
        if code or re.search(r'SCRIPT ERROR|ERROR:',out+err): raise ValueError('import failed')
        # Script check-only bypasses project autoloads; load the actual scene instead.
        # Its explicit headless rejection exits before creating a board or GUI.
        out,err,code = r.execute([str(engine),'--headless','--path',str(target),'--scene','res://tests/round69_modal_hover_test.tscn'],env,gen,evidence,'fixture-scene-parse',budgets,m['processes'])
        result = r.analyze(out,err,code)
        if code != 1 or re.search(r'SCRIPT ERROR|ERROR:',out+err) or not result.get('result') or result['result']['failures'] != ['requires real window with explicit window argument']:
            raise ValueError('target scene preflight failed')
        reports = target/'tests/runtime_reports'; reports.mkdir(parents=True,exist_ok=True)

        def suite(label, scene, headless=False):
            command = [str(engine)] + (['--headless'] if headless else []) + ['--fixed-fps','60','--path',str(target),'--scene','res://tests/'+scene+'.tscn']
            if not headless: command += ['--','window']
            out,err,code = r.execute(command,env,gen,evidence,label,budgets,m['processes'])
            item = {'mode':label,'command':command,'exit_code':code,'analysis':r.analyze(out,err,code),
                    'modal_records':records(out,'MODAL_REGRESSION '),'visual_gate_records':records(out,'VISUAL_GATE ')}
            m['suites'].append(item)
            gallery = evidence/label; gallery.mkdir()
            for path in reports.glob('*.png'): shutil.copyfile(path,gallery/path.name)
            for path in reports.glob('*.png'): path.unlink()
            print(json.dumps(item,ensure_ascii=False),flush=True)
            return item

        current_board = (target/BOARD).read_bytes()
        newline = b'\r\n' if b'\r\n' in current_board else b'\n'
        anchor = b'func _handle_scroll_hover(event: InputEvent) -> void:' + newline + b'\tif not event is InputEventMouseMotion or event.relative.is_zero_approx():' + newline + b'\t\treturn' + newline
        guard = b'\tif _native_modal_visible():' + newline + b'\t\treturn' + newline
        if current_board.count(anchor+guard) != 1: raise ValueError('sole hover guard anchor mismatch')
        old_board = current_board.replace(anchor+guard,anchor,1)
        m['board_versions'] = {'current_sha256':hashlib.sha256(current_board).hexdigest(), 'sole_guard_removed_sha256':hashlib.sha256(old_board).hexdigest(), 'only_removed_bytes':guard.decode('utf-8')}
        archive = evidence/'board-versions'; archive.mkdir()
        (archive/'current.gd').write_bytes(current_board)
        (archive/'sole-guard-removed.gd').write_bytes(old_board)
        if args.current_final:
            (target/'tests/round72_special_viewer_test.gd').write_text(SPECIAL_VIEWER_SCRIPT, encoding='utf-8')
            (target/'tests/round72_special_viewer_test.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://tests/round72_special_viewer_test.gd" id="1"]\n[node name="Round72SpecialViewer" type="Node"]\nscript = ExtResource("1")\n', encoding='utf-8')
            m['special_viewer_script_sha256'] = sha(target/'tests/round72_special_viewer_test.gd')
            m['current_final'] = True
        else:
            (target/BOARD).write_bytes(old_board)
            red = suite('modal-sole-guard-red','round69_modal_hover_test')
            (target/BOARD).write_bytes(current_board)
            if sha(target/BOARD) != m['board_versions']['current_sha256']: raise ValueError('board byte restoration failed')
            failures = red['analysis'].get('result',{}).get('failures',[]) if red['analysis'].get('result') else []
            expected = [mode+' '+suffix for mode in ['local','network'] for suffix in ['modal motion across other strips keeps original target','close preserves original target without reselection']]
            required = [mode+' modal motion across other strips keeps original target' for mode in ['local','network']]
            m['red_exclusive'] = red['exit_code']==1 and set(required).issubset(failures) and set(failures).issubset(expected) and 'engine_error' not in red['analysis']['reasons']
            m['red_failure_contract'] = {'required':required,'allowed_causal_close_invariants':expected}
            if not m['red_exclusive']: raise ValueError('RED not exclusively modal hover invariants')
        if not args.red_only:
            headless = suite('groups-headless','battle_play_groups_test',True)
            groups = suite('groups-window','battle_play_groups_test')
            modal = suite('modal-current-window','round69_modal_hover_test')
            browsing = suite('browsing-window','round64_shared_browsing_test')
            special = suite('special-viewer-window','round72_special_viewer_test') if args.current_final else None
            m['modalregression'] = {'passed':modal['analysis']['passed'], 'status':'PASS' if modal['analysis']['passed'] else 'FAIL', 'current_only':args.current_final}
            m['geometry'] = {'passed':headless['analysis']['passed'] and groups['analysis']['passed'], 'status':'PASS' if headless['analysis']['passed'] and groups['analysis']['passed'] else 'FAIL'}
            visual = headless['visual_gate_records'] + groups['visual_gate_records'] + (special['visual_gate_records'] if special else [])
            m['fullvisual'] = {'passed':bool(visual) and all(x['passed'] for x in visual), 'records':visual, 'native_review':'separate same-freeze full and crop review required; numeric gate is not native review'}
            all_suites = [headless,groups,modal,browsing] + ([special] if special else [])
            m['logic_passed'] = all(x['analysis']['passed'] for x in all_suites)
            m['actual_check_total'] = sum(x['analysis']['result']['checks'] for x in all_suites if x['analysis'].get('result'))
            m['passed'] = m['logic_passed'] and (args.current_final or m['red_exclusive']) and m['fullvisual']['passed']
        m['freeze_drift'] = {p:[value,sha(target/p)] for p,value in frozen.items() if sha(target/p)!=value}
        m['owned_source_drift'] = {p:[value,sha(REPO/p)] for p,value in m['owned_source_hashes'].items() if sha(REPO/p)!=value}
        m['outside_drift_observation'] = {p:[value,sha(REPO/p) if (REPO/p).is_file() else None] for p,value in source_hashes.items() if p not in OWNED_TESTS and (not (REPO/p).is_file() or sha(REPO/p)!=value)}
        m['outside_drift_policy'] = 'hash-only observation, not consumed by this immutable run; independently owned concurrent writes do not explain its outcomes'
        m['mutable_producer_content_consumed_after_freeze'] = False
    except Exception as exc:
        m['error'] = repr(exc)
    finally:
        if current_board is not None: (target/BOARD).write_bytes(current_board)
        archive = evidence/'frozen-inputs'; archive.mkdir()
        for rel in files:
            if (target/rel).exists() and rel.suffix in {'.gd','.tscn','.godot','.gdextension'}:
                dest=archive/rel;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(target/rel,dest)
        for pattern in ['tests/round64_shared_browsing_test.*', 'tests/round72_special_viewer_test.*']:
            for path in target.glob(pattern):
                shutil.copyfile(path,archive/'tests'/path.name)
        logs = gen/'appdata/FateDomination/logs'
        if logs.exists(): shutil.copytree(logs,evidence/'engine-logs')
        m['log_diagnostics'] = [{'path':p.relative_to(evidence).as_posix(),'errors':len(re.findall(r'SCRIPT ERROR|SHADER ERROR|^\s*ERROR:',p.read_text(encoding='utf-8'),re.M)),'warnings':len(re.findall(r'^\s*WARNING:',p.read_text(encoding='utf-8'),re.M))} for p in evidence.rglob('*.log')]
        m['clean_error_warning_gate'] = all(x['errors']==0 and x['warnings']==0 for x in m['log_diagnostics'])
        m['passed'] = m['passed'] and m['clean_error_warning_gate'] and not m.get('freeze_drift',{}) and not m.get('owned_source_drift',{})
        m['artifacts'] = [{'path':p.relative_to(evidence).as_posix(),'sha256':sha(p),'bytes':p.stat().st_size} for p in evidence.rglob('*') if p.is_file()]
        m['artifact_readback'] = all(sha(evidence/x['path'])==x['sha256'] for x in m['artifacts'])
        (root/'manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
        if all(x.get('exited') and x.get('active_owned_processes')==0 for x in m['processes']) and m['artifact_readback']:
            r.delete_owned(gen,root);m['cleanup']='generated_removed'
        (root/'manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
        print(json.dumps({'manifest':str(root/'manifest.json'),'passed':m['passed'],'modalregression':m.get('modalregression'),'geometry':m.get('geometry'),'fullvisual':m.get('fullvisual'),'red_exclusive':m.get('red_exclusive'),'error':m.get('error'),'cleanup':m['cleanup'],'artifact_readback':m['artifact_readback']},ensure_ascii=False),flush=True)
    return 0 if m['passed'] or (args.red_only and m.get('red_exclusive') and m['clean_error_warning_gate'] and not m.get('error')) else 1

if __name__ == '__main__':
    raise SystemExit(main())
