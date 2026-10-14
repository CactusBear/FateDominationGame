extends Node

const Bootstrap = preload("res://scripts/net/server/server_bootstrap.gd")
const Channel = preload("res://scripts/net/server/server_console_channel.gd")
const View = preload("res://scripts/io/native_capability_view.gd")
var checks:int = 0
var failures:Array = []

func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ",ok," ",label)
	if not ok: failures.append(label)

func _ready() -> void:
	var boot:Dictionary = Bootstrap.NATIVE_METHOD_CONTRACT
	var channel:Dictionary = Channel.NATIVE_METHOD_CONTRACT
	check(boot == channel,"bootstrap and status contracts cannot drift")
	var source = load("res://scripts/io/native_method_contract.gd")
	check(source != null,"single explicit source exists")
	if source != null:
		var declared:Dictionary = source.REQUIRED_METHODS
		check(boot == declared and channel == declared,"consumers match actual source declaration")
	check(boot.keys() == ["FateServerSignals","FateProcessOwner","FateAtomicFileReplace","FateCollectionIdentity"],"original four classes and order unchanged")
	var count:int = 0
	for methods in boot.values(): count += methods.size()
	check(count == 13 and boot.FateProcessOwner == ["available","spawn","state","verify","terminate","release"],"original thirteen methods and owner six unchanged")
	check(not boot.FateProcessOwner.has("tree_observe") and not boot.FateAtomicFileReplace.has("remove_verified"),"additional wrapper methods never default required")
	check(View.observe(boot) == View.observe(channel),"ClassDB observation shares bootstrap contract")
	var observed:Dictionary = View.observe(boot)
	check(observed.values().all(func(value): return value.exists and value.can_instantiate and value.methods.values().all(func(present): return present)),"original DLL exposes all declared capabilities")
	print("RESULT ",JSON.stringify({"suite":"round64_native_contract","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
