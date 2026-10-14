"""Single owned scene freeze; preserve each RED independently on physical E."""
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
import subprocess
import uuid

REPO = Path(__file__).resolve().parents[2]
def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod
r = load_module('round60_isolated', REPO / 'tools/run_isolated_godot_test.py')
e = load_module('round60_integrated', REPO / 'tools/tests/test_round29_integrated_evidence.py')
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
BROWSING_SCRIPT = 'extends Node\nvar checks := 0\nvar failures: Array[String] = []\nvar host\nvar guest\nvar board\nvar identity = preload("res://tests/net_window_identity_fixture.gd").new()\nvar port_fixture = preload("res://tests/network_test_port_fixture.gd").new()\nvar received: Array = []\nfunc check(ok: bool, label: String) -> void:\n\tchecks += 1\n\tprint("CHECK ", label, " ", ok)\n\tif not ok: failures.append(label)\nfunc _ready() -> void:\n\tcall_deferred("run")\nfunc _process(delta: float) -> void:\n\tif host != null: host.poll(delta)\nfunc wait_for(predicate: Callable) -> bool:\n\tfor i in 600:\n\t\tif guest != null: guest.poll()\n\t\tif predicate.call(): return true\n\t\tawait get_tree().process_frame\n\treturn false\nfunc click(node: Control, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:\n\tvar point: Vector2 = node.get_global_rect().get_center()\n\tget_viewport().warp_mouse(point)\n\tvar motion := InputEventMouseMotion.new()\n\tmotion.position = point\n\tmotion.global_position = point\n\tget_viewport().push_input(motion, true)\n\tawait get_tree().process_frame\n\tvar event := InputEventMouseButton.new()\n\tevent.position = point\n\tevent.global_position = point\n\tevent.button_index = button\n\tevent.pressed = true\n\tget_viewport().push_input(event, true)\n\tevent.pressed = false\n\tget_viewport().push_input(event, true)\n\tfor i in 3: await get_tree().process_frame\nfunc shot(name: String) -> void:\n\tawait RenderingServer.frame_post_draw\n\tcheck(get_viewport().get_texture().get_image().save_png("res://tests/runtime_reports/round64-" + name + ".png") == OK, "截图 " + name)\nfunc state() -> Array:\n\tvar out: Array = [GameProgress.current_round, GameProgress.current_player_id, GameProgress.current_phase_index, GameLog.query({}, null, -1).size(), MapData.event_discard.duplicate()]\n\tfor pid in GameData.player_data_library:\n\t\tvar data: Dictionary = GameData.player_data_library[pid]\n\t\tout.append([data.magic.number, data.score.number, data.played_cards.duplicate(), data.hand_cards.duplicate(), data.location])\n\treturn out\nfunc browser(mode: String, grouped: Dictionary) -> void:\n\tvar baseline: Array = state()\n\tfor entry in [["Shinto", "shinto", "新都"], ["Miyama", "miyama", "深山町"], ["Other", "other", "其他"]]:\n\t\tawait click(board.get_node("Piles/EventPile/Open"))\n\t\tcheck(board.get_node("EventDiscardMenu").visible, mode + " 原生菜单打开 " + entry[1])\n\t\tawait click(board.get_node("EventDiscardMenu/Choices/" + entry[0]))\n\t\tvar expected: Array = grouped.get(entry[1], [])\n\t\tvar title: String = ("%s · 事件弃牌" if mode == "local" else "公共事件弃牌 · %s") % entry[2]\n\t\tcheck(board.get_node("CardBrowser").visible and not board.get_node("EventDiscardMenu").visible, mode + " 分类点击打开浏览器并收菜单")\n\t\tcheck(board.get_node("CardBrowser/Panel/Title").text == "%s · %d" % [title, expected.size()], mode + " 原标题文本 " + entry[1])\n\t\tvar row: Control = board.get_node("CardBrowser/Panel/CardScroll/Row")\n\t\tcheck(row.get_child_count() == expected.size(), mode + " 完整分类数量 " + entry[1])\n\t\tvar order_ok: bool = row.get_child_count() == expected.size()\n\t\tfor i in mini(row.get_child_count(), expected.size()):\n\t\t\tvar slot: Control = row.get_child(i)\n\t\t\tvar card: Dictionary = expected[i]\n\t\t\torder_ok = order_ok and slot.get_meta("card").id == card.id\n\t\t\tvar texture: Texture2D = slot.get_node("Img").texture\n\t\t\tvar image: String = card.image if card.get("visible",false) and not card.get("concealed",true) else card.get("back_image", "")\n\t\t\tcheck(texture != null and texture.resource_path == image, mode + " 原公开权限贴图 " + entry[1] + str(i))\n\t\tcheck(order_ok, mode + " source数组顺序 " + entry[1])\n\t\tif entry[1] == "shinto": await shot(mode + "-shinto")\n\t\tawait click(board.get_node("CardBrowser/Panel/Close"))\n\t\tcheck(not board.get_node("CardBrowser").visible, mode + " 原生关闭")\n\tcheck(state() == baseline, mode + " 浏览不修改规则或身份状态")\nfunc run() -> void:\n\tif DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("window"):\n\t\tcheck(false, "必须真实窗口 -- window")\n\t\tfinish(); return\n\tboard = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()\n\tget_tree().root.add_child(board)\n\tfor pid in GameData.player_data_library:\n\t\tboard._seat_controller.set_kind(int(pid), SeatController.REMOTE)\n\tawait get_tree().create_timer(0.8).timeout\n\tGameProgress.reset_progress()\n\tEffectManager.reset_runtime()\n\tGameProgress.is_game_over = false\n\tGameProgress.current_player_id = GameData.player_id\n\tGameProgress.current_phase_index = GameProgress.phases.find(GameProgress.phases.filter(func(p): return p.get("name") == "action")[0])\n\tMapData.active_situation = null\n\tMapData.event_discard.clear()\n\tfor item in [["shinto-second",MapData.shinto],["miyama",MapData.miyama],["shinto-first",MapData.shinto]]:\n\t\tvar card := BaseEvent.new(item[0], "res://data/attacks/basic/luck/luck.png")\n\t\tcard.from = item[1]\n\t\tcard._zoom_kind = "card"\n\t\tcard.set_concealed(false)\n\t\tMapData.event_discard.append(card)\n\tboard.refresh_all_ui()\n\tawait get_tree().create_timer(0.6).timeout\n\tvar local_view: Dictionary = board._source.read_view()\n\tvar legacy: Array = MapData.event_discard.filter(func(c): return c is BaseEvent and c.get_from() == MapData.shinto)\n\tcheck(local_view.event_discard_by_source.shinto.map(func(c): return c.name) == legacy.map(func(c): return c._name), "本地旧过滤与source分类完整顺序等价")\n\tawait browser("local", local_view.event_discard_by_source)\n\tboard.queue_free()\n\tawait get_tree().process_frame\n\tboard = null\n\thost = load("res://scripts/net/session/lobby_session.gd").new()\n\tguest = load("res://scripts/net/session/lobby_session.gd").new()\n\thost.blobs.cache.root = OS.get_environment("FATE_TEST_SCRATCH_ROOT").path_join("host-cache")\n\tguest.blobs.cache.root = OS.get_environment("FATE_TEST_SCRATCH_ROOT").path_join("guest-cache")\n\tcheck(port_fixture.reserve_udp() == OK, "OS分配独占回环UDP端口")\n\tvar listen: Error = port_fixture.handoff(func(port): return host.host(port,"Round64",{"capacity":2,"minimum":1,"ai_count":0,"selection_mode":"test"},"127.0.0.1"))\n\tcheck(listen == OK, "真实ENet监听")\n\tif listen != OK: finish(); return\n\tcheck(identity.install(host,guest), "已有内存RSA身份挑战夹具")\n\tcheck(guest.join("127.0.0.1", port_fixture.port, "Round64Guest") == OK, "真实ENet连接")\n\tvar authenticated: bool = await wait_for(func(): return guest.identity_authenticated and guest.view.get("members",[]).size() == 2)\n\tcheck(authenticated, "真实认证成员前置")\n\tif not authenticated: finish(); return\n\thost.match_authority.started = true\n\thost.match_authority.controllers = {GameData.player_id:guest.peer_id()}\n\thost.match_authority.driver.seats.default_kind = SeatController.REMOTE\n\tfor pid in GameData.player_data_library: host.match_authority.driver.seats.set_kind(int(pid),SeatController.REMOTE)\n\thost.room.phase = "playing"\n\thost._bind_match()\n\thost._publish_match()\n\tcheck(await wait_for(func(): return not guest.read_match().is_empty()), "权威过滤快照经真实ENet接收")\n\tif guest.read_match().is_empty(): finish(); return\n\tboard = load("res://assets/scenes/game_scene/battle_board_v2.tscn").instantiate()\n\tboard.network_session = guest\n\tget_tree().root.add_child(board)\n\tawait get_tree().create_timer(0.8).timeout\n\tvar network_view: Dictionary = guest.read_match()\n\tcheck(board._source.read_view().event_discard_by_source == network_view.event_discard_by_source, "network source只读会话投影")\n\thost.transport.message_received.connect(func(_sender, message): received.append(str(message.get("kind",""))))\n\tawait browser("network", network_view.event_discard_by_source)\n\tcheck(not received.any(func(kind): return kind.begins_with("match_") and kind != "match_preview"), "网络浏览不提交match命令")\n\tprint("NETWORK_RECEIVED ", JSON.stringify(received))\n\tfinish()\nfunc finish() -> void:\n\tif is_instance_valid(board): board.queue_free()\n\tif guest != null: guest.close()\n\tif host != null: host.close()\n\tidentity.release()\n\tport_fixture.close()\n\tprint("RESULT checks=",checks," failures=",failures)\n\tget_tree().quit(0 if failures.is_empty() else 1)\n'

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--label', required=True)
    ap.add_argument('--window', action='store_true')
    ap.add_argument('--baseline', action='store_true')
    args = ap.parse_args()
    if not re.fullmatch(r'[a-z0-9-]+', args.label): raise ValueError('invalid label')
    parent = r.physical_e('E:/scratch') / ('round64-shared-browsing-' + args.label)
    parent.mkdir(exist_ok=True)
    token = uuid.uuid4().hex
    root = parent / ('isolated-' + token)
    root.mkdir()
    gen = root / 'generated'; gen.mkdir()
    evidence = root / 'evidence'; evidence.mkdir()
    target = gen / 'project'; target.mkdir()
    m = {'root': str(root), 'run_id': token, 'generated': str(gen), 'processes': [], 'suites': [], 'cleanup': 'not_started', 'passed': False}
    budgets = {'seconds': 180, 'bytes': 8589934592, 'min_free': 1073741824}
    env = os.environ.copy()
    for key in ('APPDATA', 'LOCALAPPDATA'):
        folder = gen / key.lower(); folder.mkdir(); env[key] = str(folder)
    temporary = gen / 'temp'; temporary.mkdir()
    for key in ('TEMP', 'TMP', 'TMPDIR'):
        env[key] = str(temporary)
    m['isolated_environment'] = {key: env[key] for key in ('APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'TMPDIR')}
    m['runner_dependencies'] = {p.relative_to(REPO).as_posix(): sha(p) for p in (
        Path(__file__), REPO / 'tools/run_isolated_godot_test.py', REPO / 'tools/tests/test_round29_integrated_evidence.py')}
    m['visual_acceptance'] = 'not_certified_by_logic_PASS; native_fullscreen_and_crop_review_required'
    fixture = gen / 'fixtures'; fixture.mkdir()
    env['FATE_TEST_SCRATCH_ROOT'] = fixture.as_posix()
    env.pop('HERMES_RECOVERY_VALIDATION_ROOT', None)
    files = []
    try:
        includes = ['project.godot', 'scripts', 'assets', 'data', 'game_data', 'addons', 'json_maker', 'icon.svg',
                    'tests/battle_play_groups_test.gd', 'tests/battle_play_groups_test.tscn',
                    'tests/net_window_identity_fixture.gd', 'tests/network_test_port_fixture.gd']
        files = [p for p in r.source_files(REPO, includes) if not (p.suffix == '.dll' and p.name.startswith('~'))]
        before = {p.as_posix(): sha(REPO / p) for p in files}
        for p in files:
            dest = target / p; dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(REPO / p, dest)
            if sha(dest) != before[p.as_posix()]: raise ValueError('freeze drift: ' + str(p))
        m['source_hashes'] = before
        config, transform = e.transform_isolated_editor_vcs((target / 'project.godot').read_text(encoding='utf-8-sig'))
        (target / 'project.godot').write_text(config, encoding='utf-8')
        m['editor_transform'] = transform
        if args.baseline:
            test_path = target / 'tests/battle_play_groups_test.gd'
            original = test_path.read_text(encoding='utf-8')
            diagnostic = '\tprint("LIFECYCLE ", JSON.stringify({"processing":board.is_processing(), "fly_count":board._fly_layer.get_child_count(), "busy":board._fly_busy, "queues":board._fly_queues.values().map(func(q): return q.size()), "slot_alpha":region.get_children().map(func(g): return g.get_node("Cards/Row").get_children().map(func(c): return c.modulate.a)), "tweens":get_tree().get_processed_tweens().map(func(t): return {"running":t.is_running(), "elapsed":t.get_total_elapsed_time()})}))\n'
            anchor = '\tif DisplayServer.get_name() != "headless":\n'
            test_path.write_text(original.replace(anchor, diagnostic + anchor, 1), encoding='utf-8')
            m['test_transform'] = 'baseline passive lifecycle observations only'

        if not args.baseline:
            (target / 'tests/round64_shared_browsing_test.gd').write_text(BROWSING_SCRIPT, encoding='utf-8')
            (target / 'tests/round64_shared_browsing_test.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://tests/round64_shared_browsing_test.gd" id="1"]\n[node name="Round64Browsing" type="Node"]\nscript = ExtResource("1")\n', encoding='utf-8')
            m['generated_test_sha256'] = sha(target / 'tests/round64_shared_browsing_test.gd')
        frozen = {p.as_posix(): sha(target / p) for p in files}
        engine_source = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe')
        engine = gen / 'Godot.exe'; shutil.copyfile(engine_source, engine)
        m['engine_sha256'] = sha(engine)
        if m['engine_sha256'] != sha(engine_source): raise ValueError('engine drift')
        probe = gen / 'probe'; probe.mkdir()
        app = re.search(r'^\[application\]\s*\n(.*?)(?=^\[|\Z)', config, re.M | re.S)[1]
        threads = re.search(r'^\[threading\]\s*\n(.*?)(?=^\[|\Z)', config, re.M | re.S)[1]
        (probe / 'project.godot').write_text('config_version=5\n[application]\n'+app+'\n[threading]\n'+threads, encoding='utf-8')
        (probe / 'probe.gd').write_text(r.PROBE_SCRIPT, encoding='utf-8')
        out, err, code = r.execute([str(engine), '--headless', '--path', str(probe), '--script', 'res://probe.gd', '--', token, 'main', str(gen)], env, gen, evidence, 'probe', budgets, m['processes'])
        if code or re.search(r'SCRIPT ERROR|ERROR:', out + err): raise ValueError('physical probe failed')
        m['physical_probes'] = r.verify_probe(out, gen, token)
        out, err, code = r.execute([str(engine), '--headless', '--editor', '--import', '--path', str(target)], env, gen, evidence, 'import', budgets, m['processes'])
        if code or re.search(r'SCRIPT ERROR|ERROR:', out + err): raise ValueError('import failed')
        (target / 'tests/runtime_reports').mkdir(parents=True, exist_ok=True)
        for mode in ['headless'] + (['window'] if args.window else []):
            command = [str(engine)] + (['--headless'] if mode == 'headless' else []) + ['--fixed-fps', '60', '--path', str(target), '--scene', 'res://tests/battle_play_groups_test.tscn']
            if mode == 'window': command += ['--', 'window']
            out, err, code = r.execute(command, env, gen, evidence, mode, budgets, m['processes'])
            visual_records = [json.loads(line.split('VISUAL_GATE ', 1)[1]) for line in out.splitlines() if line.startswith('VISUAL_GATE ')]
            m['suites'].append({'mode': mode, 'command': command, 'exit_code': code, 'analysis': r.analyze(out, err, code), 'visual_gate_records': visual_records})
            print(json.dumps(m['suites'][-1], ensure_ascii=False), flush=True)
            # Collect independent target modes without retrying a failure.
        if not args.baseline and args.window:
            command = [str(engine), '--fixed-fps', '60', '--path', str(target), '--scene', 'res://tests/round64_shared_browsing_test.tscn', '--', 'window']
            out, err, code = r.execute(command, env, gen, evidence, 'browsing-window', budgets, m['processes'])
            m['suites'].append({'mode':'browsing-window','command':command,'exit_code':code,'analysis':r.analyze(out,err,code)})
            print(json.dumps(m['suites'][-1], ensure_ascii=False), flush=True)
        m['source_drift'] = {p.as_posix(): [before[p.as_posix()], sha(REPO / p)] for p in files if sha(REPO / p) != before[p.as_posix()]}
        m['freeze_drift'] = {p.as_posix(): [frozen[p.as_posix()], sha(target / p)] for p in files if sha(target / p) != frozen[p.as_posix()]}
        m['passed'] = len(m['suites']) == ((2 if args.baseline else 3) if args.window else 1) and all(x['analysis']['passed'] for x in m['suites']) and not m['source_drift'] and not m['freeze_drift']
        m['logic_passed'] = m['passed']
        records = [item for suite in m['suites'] for item in suite.get('visual_gate_records', [])]
        m['visual_gate'] = {'passed': bool(records) and all(item['passed'] for item in records), 'native_review': 'required_separately', 'records': records}
        m['passed'] = m['logic_passed'] and m['visual_gate']['passed']
    except Exception as exc:
        m['error'] = repr(exc)
    finally:
        archive = evidence / 'frozen-inputs'; archive.mkdir()
        for p in files:
            if p.suffix in {'.gd', '.tscn', '.godot', '.gdextension'}:
                dest = archive / p; dest.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(target / p, dest)
        for p in target.glob('tests/runtime_reports/*.png'): shutil.copyfile(p, evidence / p.name)
        for p in target.glob('tests/round64_shared_browsing_test.*'): shutil.copyfile(p, archive / 'tests' / p.name)
        logs = gen / 'appdata/FateDomination/logs'
        if logs.exists(): shutil.copytree(logs, evidence / 'engine-logs')
        m['log_diagnostics'] = [{
            'path': p.relative_to(evidence).as_posix(),
            'errors': len(re.findall(r'SCRIPT ERROR|SHADER ERROR|^\s*ERROR:', p.read_text(encoding='utf-8'), re.M)),
            'warnings': len(re.findall(r'^\s*WARNING:', p.read_text(encoding='utf-8'), re.M))
        } for p in evidence.rglob('*.log')]
        m['clean_error_warning_gate'] = all(x['errors'] == 0 and x['warnings'] == 0 for x in m['log_diagnostics'])
        m['passed'] = m['passed'] and m['clean_error_warning_gate']
        m['artifacts'] = [{'path': p.relative_to(evidence).as_posix(), 'sha256': sha(p), 'bytes': p.stat().st_size} for p in evidence.rglob('*') if p.is_file()]
        m['artifact_readback'] = all(sha(evidence / x['path']) == x['sha256'] for x in m['artifacts'])
        (root / 'manifest.json').write_text(json.dumps(m, ensure_ascii=False, indent=2), encoding='utf-8')
        if all(x.get('exited') and x.get('active_owned_processes') == 0 for x in m['processes']) and m['artifact_readback']:
            r.delete_owned(gen, root); m['cleanup'] = 'generated_removed'
        (root / 'manifest.json').write_text(json.dumps(m, ensure_ascii=False, indent=2), encoding='utf-8')
        print(json.dumps({'manifest': str(root / 'manifest.json'), 'passed': m['passed'], 'error': m.get('error'), 'cleanup': m['cleanup'], 'artifact_readback': m['artifact_readback']}, ensure_ascii=False), flush=True)
    return 0 if m['passed'] else 1
if __name__ == '__main__': raise SystemExit(main())
