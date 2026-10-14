extends Control

## 开场按键：入场未完成时跳到终态，完成后播放按键反馈与跃迁。
## 跃迁的全部节奏（停顿、冲刺、文字吸入、闪白、黑场）写在场景的 AnimationPlayer 里，
## 动画由场景显式配置；跃迁完成只发出 warped，不切换场景。

## 按任意键（或外部调用 start_warp）开始跃迁时发出。
signal warp_started
## 跃迁动画播完（画面已为纯黑）时发出。
signal warped

## 播放跃迁的 AnimationPlayer。
@export var warp_player: AnimationPlayer
## 跃迁动画名。
@export var warp_animation: StringName = &"warp"
## 用于判断文字入场是否完成的动画播放器。
@export var reveal_player: AnimationPlayer
## 按键确认反馈，由场景定义外观与时长。
@export var feedback_player: AnimationPlayer
@export var feedback_animation: StringName = &"press"
## 已预渲染的全屏转场；未配置时继续使用 warp_player 的程序化动画。
@export var transition_video: VideoStreamPlayer

## 跃迁开始时要停下的动画：非循环的先跳到终态再停，循环的直接暂停。
@export var stop_players: Array[AnimationPlayer] = []
## 跃迁开始时要定格的视频：暂停后停在当前帧、不再解码，跃迁全程只处理这一帧。
@export var freeze_videos: Array[VideoStreamPlayer] = []
## 进入场景时先显示一帧再隐藏的节点：提前编译跃迁着色器，避免按键瞬间编译导致首帧卡顿。
## 开场黑幕还在时完成，画面上看不到。
@export var warm_up_nodes: Array[CanvasItem] = []
## 跃迁播放中再次按键时直接跳到跃迁动画终态。
@export var allow_skip := true
## 跃迁完成后要切换到的场景。留空则只发 warped 信号、不切换（预览与测试状态）。
## warp_started 时开始后台线程预加载，warped 时若尚未加载完则停在终态画面等待。
@export_file("*.tscn") var next_scene: String = ""
## 预渲染视频中真实菜单开始出现的位置；到达后提前启动菜单，片尾时无缝交接。
@export var transition_menu_start_position := -1.0

var _started := false
var _entering := false
var _video_transition_active := false
var _warped_emitted := false
var _staged_next_scene: Node
var _next_scene_packed: PackedScene


func _ready() -> void:
	# worker 已由 LoadGame deferred 路由到 server_bootstrap；不能进入开场的 await 生命周期。
	if LoadGame.is_server_worker_process():
		return
	var hidden: Array[CanvasItem] = []
	for n in warm_up_nodes:
		if n != null and not n.visible:
			n.visible = true
			hidden.append(n)
	if hidden.is_empty():
		return
	# 等两帧：保证至少提交过一次绘制（headless 下 frame_post_draw 不触发，不能依赖它）
	await get_tree().process_frame
	await get_tree().process_frame
	for n in hidden:
		if not _started:
			n.visible = false


func _input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if not (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton):
		return
	if _started:
		get_viewport().set_input_as_handled()
		if allow_skip:
			skip_warp()
		return
	if _entering:
		return
	get_viewport().set_input_as_handled()
	if reveal_player != null and reveal_player.is_playing():
		var animation := reveal_player.get_animation(reveal_player.current_animation)
		if animation != null and animation.loop_mode == Animation.LOOP_NONE:
			reveal_player.seek(animation.length, true)
			reveal_player.pause()
			return
	_entering = true
	if _play_feedback():
		await feedback_player.animation_finished
	start_warp()


## 重播短反馈，避免连续按键叠加缩放。
func _play_feedback() -> bool:
	if feedback_player == null or not feedback_player.has_animation(feedback_animation):
		return false
	feedback_player.stop()
	feedback_player.play(feedback_animation)
	feedback_player.advance(0.0)
	return true


## 跃迁播放中直接跳到终态；终态之后照常发出 warped。未在播放时无效。
func skip_warp() -> void:
	if _video_transition_active and transition_video != null:
		_video_transition_active = false
		transition_video.stop()
		_discard_staged_scene()
		_complete_warp()
		return
	if not _started or warp_player == null or not warp_player.is_playing():
		return
	var anim := warp_player.get_animation(warp_player.current_animation)
	if anim != null:
		# advance 走完剩余时长，会正常发出 animation_finished；seek 到末尾不会
		warp_player.advance(anim.length - warp_player.current_animation_position)


## 开始跃迁。重复调用无效。
func start_warp() -> void:
	var use_transition_video := transition_video != null and transition_video.stream != null
	if _started or (not use_transition_video and (warp_player == null or not warp_player.has_animation(warp_animation))):
		return
	_started = true
	for p in stop_players:
		if p == null or not p.is_playing():
			continue
		var anim := p.get_animation(p.current_animation)
		if anim != null and anim.loop_mode == Animation.LOOP_NONE:
			p.seek(anim.length, true)
		p.pause()
	if _will_change_scene():
		ResourceLoader.load_threaded_request(next_scene)
	warp_started.emit()
	if transition_video != null and transition_video.stream != null:
		_video_transition_active = true
		transition_video.stream_position = 0.0
		transition_video.visible = true
		transition_video.play()
		# 首帧先真实绘制，再冻结原背景；headless 测试没有 post_draw 信号。
		if DisplayServer.get_name() == "headless":
			await get_tree().process_frame
		else:
			await RenderingServer.frame_post_draw
		for v in freeze_videos:
			if v != null:
				v.paused = true
		while _video_transition_active and transition_video.is_playing():
			if _staged_next_scene == null and transition_menu_start_position >= 0.0 and transition_video.stream_position >= transition_menu_start_position and _will_change_scene():
				await _stage_next_scene()
			await get_tree().process_frame
		if not _warped_emitted:
			_complete_warp()
		return
	for v in freeze_videos:
		if v != null:
			v.paused = true
	warp_player.play(warp_animation)
	await warp_player.animation_finished
	_complete_warp()


func _complete_warp() -> void:
	if _warped_emitted:
		return
	_warped_emitted = true
	warped.emit()
	if is_instance_valid(_staged_next_scene):
		var staged := _staged_next_scene
		_staged_next_scene = null
		get_tree().current_scene = staged
		queue_free()
	else:
		_change_to_next_scene()


func _stage_next_scene() -> void:
	while _video_transition_active:
		var status := ResourceLoader.load_threaded_get_status(next_scene)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			return
		await get_tree().process_frame
	if not _video_transition_active:
		return
	_next_scene_packed = ResourceLoader.load_threaded_get(next_scene) as PackedScene
	if _next_scene_packed == null:
		return
	var staged := _next_scene_packed.instantiate()
	var root := get_tree().root
	var opening_index := get_index()
	root.add_child(staged)
	root.move_child(staged, opening_index)
	_staged_next_scene = staged


func _discard_staged_scene() -> void:
	if is_instance_valid(_staged_next_scene):
		_staged_next_scene.queue_free()
	_staged_next_scene = null


## 只有声明了 next_scene 且本节点是当前场景根时才切换；
## 测试把场景 instantiate 成子节点时不预加载也不切换。
func _will_change_scene() -> bool:
	return next_scene != "" and get_tree() != null and get_tree().current_scene == self


## 跃迁终态后切换到 next_scene。
func _change_to_next_scene() -> void:
	if not _will_change_scene():
		return
	# load_threaded_get 在未加载完时阻塞到完成，画面停在跃迁终态
	var packed := _next_scene_packed
	if packed == null:
		packed = ResourceLoader.load_threaded_get(next_scene) as PackedScene
	if packed == null:
		push_error("无法加载场景：" + next_scene)
		return
	get_tree().change_scene_to_packed(packed)
