from pathlib import Path
import difflib
import hashlib
import json

ROOT = Path('E:/Projects/Godot/FateDominationGame-master')
OUT = ROOT / 'scratch/native-process-ownership-v6'
OVERLAY = OUT / 'overlay'
BASE = OUT / 'baseline'


def change(path, transform):
    source = (ROOT / path).read_text(encoding='utf-8')
    destination = transform(source)
    (BASE / path).parent.mkdir(parents=True, exist_ok=True)
    if (BASE / path).exists():
        assert (BASE / path).read_bytes() == (ROOT / path).read_bytes(), 'Production baseline changed: ' + path
    else:
        (BASE / path).write_bytes((ROOT / path).read_bytes())
    (OVERLAY / path).parent.mkdir(parents=True, exist_ok=True)
    (OVERLAY / path).write_text(destination, encoding='utf-8', newline='\n')


def replace(source, old, new):
    assert source.count(old) == 1, old
    return source.replace(old, new)


def signals(source):
    source = replace(source, 'static void initialize_signals(ModuleInitializationLevel level) {', 'void register_fate_process_owner();\n\nstatic void initialize_signals(ModuleInitializationLevel level) {')
    return replace(source, '    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) GDREGISTER_CLASS(FateServerSignals);', '    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {\n        GDREGISTER_CLASS(FateServerSignals);\n        register_fate_process_owner();\n    }')


def build(source):
    return replace(source, 'if env["platform"] == "windows":\n    env.Append(LINKFLAGS=["-static-libgcc", "-static-libstdc++", "-static"])', 'if env["platform"] == "windows":\n    env.Append(LIBS=["bcrypt"])\n    if env.get("use_mingw", False):\n        env.Append(LINKFLAGS=["-static-libgcc", "-static-libstdc++", "-static"])')


def manager(source):
    start = source.index('## 只接受生命周期所有者')
    end = source.index('func instance_binding(', start)
    source = source[:start] + '''## 主管私有原生所有者；令牌只存于本机内存，不从恢复文件认领 PID。
var _process_owner:RefCounted
const PROCESS_OWNERSHIP_UNAVAILABLE:String = "原生工作进程所有权验证不可用；禁止启动、恢复或操作未验证的进程，原目录保留"

func process_ownership_available() -> bool:
	if _process_owner == null:
		if not ClassDB.class_exists("FateProcessOwner"): return false
		_process_owner = ClassDB.instantiate("FateProcessOwner")
	return _process_owner != null and _process_owner.call("available") == true

## -1 未知（不能当作已退出）；0 同一实例退出；1 同一实例运行中。
func _process_state(room:Dictionary) -> int:
	if _process_owner == null or not room.get("process_token") is String: return -1
	return int(_process_owner.call("state", room.process_token, int(room.pid)))

func _terminate_process(room:Dictionary) -> bool:
	if _process_owner == null or not room.get("process_token") is String: return false
	return _process_owner.call("terminate", room.process_token, int(room.pid)) == true

func _release_process(room:Dictionary) -> bool:
	if _process_owner == null or not room.get("process_token") is String: return false
	return _process_owner.call("release", room.process_token, int(room.pid)) == true

''' + source[end:]
    source = replace(source, '''	if not binding_matches(binding) or binding.pid <= 0 or not process_identity_verifier.is_valid(): return false
	# 必须为严格 bool true；错误码、字典或非零整数不构成验证成功。
	var verified:Variant = process_identity_verifier.call(binding.duplicate(true))
	return verified is bool and verified''', '''	if not binding_matches(binding) or binding.pid <= 0: return false
	var room:Dictionary = rooms[binding.room]
	if not room.get("process_token") is String: return false
	return _process_owner.call("verify", room.process_token, binding.pid) == true''')
    old = 'OS.create_process(OS.get_executable_path(), preload("res://scripts/net/server/server_bootstrap.gd").process_arguments(arguments))'
    assert source.count(old) == 2
    source = source.replace('var pid := ' + old, 'var spawned:Dictionary = _process_owner.call("spawn", OS.get_executable_path(), preload("res://scripts/net/server/server_bootstrap.gd").process_arguments(arguments))\n\tvar pid:int = int(spawned.get("pid", -1))')
    source = source.replace('var pid:=' + old, 'var spawned:Dictionary = _process_owner.call("spawn", OS.get_executable_path(), preload("res://scripts/net/server/server_bootstrap.gd").process_arguments(arguments))\n\tvar pid:int = int(spawned.get("pid", -1))')
    source = replace(source, '"port": port, "pid": pid,', '"port": port, "pid": pid, "process_token":spawned.token,')
    source = replace(source, '''		for room in rooms.values():
			if room.pid > 0: _write_supervisor(room)''', '''		for room in rooms.values():
			if room.error.is_empty() and _process_state(room) == 1: _write_supervisor(room)''')
    source = replace(source, '''		if room.ready or not room.error.is_empty():
			continue''', '''		if not room.error.is_empty():
			room.ready = false
			if not _terminate_process(room): room.error = "无法停止自己的房间进程；保留所有权与原目录"
			continue
		if room.ready: continue''')
    source = replace(source, '''				room.ready = true''', '''				room.ready = _process_state(room) == 1''')
    source = replace(source, '''		if room.pid <= 0 or not OS.is_process_running(room.pid):''', '''		var process_state:int = _process_state(room)
		if process_state != 1:''')
    source = replace(source, '''				room.error = "房间进程已经退出"''', '''				room.error = "房间进程已经退出" if process_state == 0 or room.pid <= 0 else PROCESS_OWNERSHIP_UNAVAILABLE''')
    source = replace(source, '\t\tif not room.error.is_empty():\n\t\t\tOS.kill(room.pid)', '\t\tif not room.error.is_empty():\n\t\t\tif not _terminate_process(room): room.error = "无法停止自己的房间进程；保留所有权与原目录"')
    source = replace(source, '''	if room.ready or (int(room.pid) > 0 and OS.is_process_running(int(room.pid))):
		error = "房间仍在运行"
		return false''', '''	if int(room.pid) > 0:
		var previous_state:int = _process_state(room)
		if previous_state != 0:
			error = "房间仍在运行" if previous_state == 1 else PROCESS_OWNERSHIP_UNAVAILABLE
			return false
	# discover_rooms 只登记 pid=-1；磁盘实例标识不授予任何 OS 进程所有权。''')
    source = replace(source, '''	room.pid = pid
	room.instance_id = instance_id''', '''	# 旧实例已由持有句柄确认退出，新实例成功创建后才释放旧句柄。
	if int(room.pid) > 0 and not _release_process(room):
		_process_owner.call("terminate", spawned.token, pid)
		_process_owner.call("release", spawned.token, pid)
		config.instance_id = room.instance_id
		write_configuration(config_path, config)
		error = "旧进程句柄释放失败；恢复失败关闭"
		return false
	room.pid = pid
	room.process_token = spawned.token
	room.instance_id = instance_id''')
    source = replace(source, '''	if pid > 0 and OS.is_process_running(pid) and OS.kill(pid) != OK:
		error = "无法停止自己的房间进程"
		return false''', '''	if pid > 0:
		if not _terminate_process(rooms[id]) or not _release_process(rooms[id]):
			error = "无法停止或释放自己的房间进程；保留登记与原目录"
			return false''')
    source = replace(source, '''		for room in rooms.values():
			if room.pid > 0 and OS.is_process_running(room.pid):
				OS.kill(room.pid)''', '''		close()
		# 原生 RAII 析构最后只对仍持有的 OS 身份清理，不按 PID 查询或认领。''')
    assert 'OS.create_process' not in source and 'OS.kill' not in source and 'OS.is_process_running' not in source
    return source

change('addons/fate_server_signals/src/server_signals.cpp', signals)
change('addons/fate_server_signals/SConstruct', build)
change('scripts/net/server/server_room_manager.gd', manager)


def gateway_test(source):
    return replace(source, '''	manager.process_identity_verifier = func(_binding:Dictionary): return 1
	_check(not manager.process_identity_verified(binding),"非 bool 验证结果拒绝")
	# 注入仅用于隔离消费者反例，不构成真实 OS 句柄验证证据。
	manager.process_identity_verifier = func(_binding:Dictionary): return true
	_check(manager.binding_matches(binding,true),"可信提供者消费者接线")''', '''	_check(not manager.process_identity_verified(binding),"合成 PID 不构成原生所有权")
	manager.rooms["room-a"].process_token = "forged"
	_check(not manager.binding_matches(binding,true),"伪造令牌与 ready 字符串不得授予所有权")''')


def ready_test(source):
    return replace(source, '''		check(not manager.process_identity_verifier.is_valid(), mode + ": OS verifier not configured by default")''', '''		check(not manager.rooms[instance].has("process_token"), mode + ": synthetic registration has no native capability")''')

change('tests/gateway_instance_binding_test.gd', gateway_test)
change('tests/authority_worker_acceptance_v4/ready_contract_test.gd', ready_test)

patch = []
manifest = {}
for file in sorted(OVERLAY.rglob('*')):
    if not file.is_file() or not (file.suffix in ('.cpp', '.hpp', '.gd') or file.name == 'SConstruct'): continue
    relative = file.relative_to(OVERLAY).as_posix()
    baseline = BASE / relative
    old = baseline.read_text(encoding='utf-8') if baseline.exists() else ''
    new = file.read_text(encoding='utf-8')
    patch.extend(difflib.unified_diff(old.splitlines(True), new.splitlines(True), fromfile='a/' + relative if baseline.exists() else '/dev/null', tofile='b/' + relative))
    manifest[relative] = {'baseline_sha256':hashlib.sha256(baseline.read_bytes()).hexdigest() if baseline.exists() else None, 'overlay_sha256':hashlib.sha256(file.read_bytes()).hexdigest()}
(OUT / 'ownership-v6.patch').write_text(''.join(patch), encoding='utf-8', newline='\n')
(OUT / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
print('overlay files:', len(manifest))
