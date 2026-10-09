extends Node3D
## Standalone demo of the two steam-gallery mechanisms (no state_service, no level contract changes).
## A 90 m slice of the east +5 maintenance passage, world-aligned like the city (Godot -Z = north):
##   valve station (z -62.5) -> 40 m BigSlidingGate on the west side (z -58.5 .. -18.5)
##   -> hoisting-well gap with TransferPlatform (deck centre z 0) -> south landing, direct doorway + shutter (z 18.4).
## Keys: WASD / mouse / Space, E interact, Q switch era, R checkpoint, T restart.

const Player = preload("res://core/player.gd")
const PASSAGE_W := 8.7
const DECK_X := 4.15            # deck centre: city x -426.55 vs passage west face -430.7

var era := "present"
var flags := {"valve_closed_past": false, "platform_locked_past": false, "exit_reached": false}
var checkpoint := Vector3(4.0, 0.1, -66.0)
var player: CharacterBody3D
var gate: BigSlidingGate
var platform: TransferPlatform
var hud: Label
var notice: Label
var env: WorldEnvironment
var sun: DirectionalLight3D
var valve_pos := Vector3(7.6, 0.0, -62.5)
var valve_wheel: Node3D
var _notice_t := 0.0


class StubService extends Node:
	func world_enabled() -> bool:
		return true


func _ready() -> void:
	_setup_input()
	_build_world()
	gate = (load("res://mechanisms/steamhall/big_sliding_gate.tscn") as PackedScene).instantiate()   # 建模 C8 skins
	gate.name = "BigSlidingGate"
	gate.stack_at_end = true
	gate.position = Vector3(0.0, 0.0, -18.5)          # south end; local +X -> north (-Z), local +Z -> passage (+X)
	gate.rotation_degrees.y = 90.0
	add_child(gate)
	gate.steam_body_entered.connect(_on_hazard)
	platform = (load("res://mechanisms/steamhall/transfer_platform.tscn") as PackedScene).instantiate()   # C4 skins
	platform.name = "TransferPlatform"
	platform.position = Vector3(DECK_X, 0.0, 0.0)
	add_child(platform)
	platform.fell_into_gap.connect(_on_hazard)
	platform.shutter_dropped.connect(func() -> void: _say("系统：卷帘落下（S3-03）"))
	var svc := StubService.new()
	add_child(svc)
	player = Player.new()
	player.name = "Player"
	player.service = svc
	add_child(player)
	_setup_ui()
	restart()
	var capture_dir := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--demo-capture="):
			capture_dir = arg.trim_prefix("--demo-capture=")
	if "--demo-smoke" in OS.get_cmdline_user_args():
		get_tree().create_timer(1.0).timeout.connect(_smoke_done)
	elif capture_dir != "":
		_capture.call_deferred(capture_dir)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ------------------------------------------------------------------ capture mode (proof shots for the PR)
func _shoot(dir: String, name: String, eye: Vector3, target: Vector3) -> void:
	player.set_physics_process(false)
	player.global_position = eye
	var d := (target - (eye + Vector3(0, 1.62, 0))).normalized()
	player.rotation = Vector3(0.0, atan2(-d.x, -d.z), 0.0)
	player.camera.rotation.x = asin(clampf(d.y, -1.0, 1.0))
	for i in 6:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(name + ".png"))
	print("CAPTURED ", name)


func _capture(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(0.5).timeout
	var v1 := Vector3(2.7, 0.0, -68.0)
	var v1t := Vector3(4.1, 1.0, -55.5)
	await _shoot(dir, "01_V1_present_gate_open_steam", v1, v1t)
	era = "past"
	rebuild()
	flags.valve_closed_past = true
	gate.apply_state(true, era)
	gate.play_close()
	await get_tree().create_timer(3.0).timeout
	await _shoot(dir, "02_V2_past_gate_closing_3s", v1, v1t)
	era = "present"
	rebuild()
	await _shoot(dir, "03_V3_present_gate_closed", v1, v1t)
	var s1 := Vector3(7.7, 0.0, -17.5)
	await _shoot(dir, "04_S3-01_present_platform_parked", s1, Vector3(-0.8, 0.5, 3.5))
	era = "past"
	rebuild()
	flags.platform_locked_past = true
	platform.play_lock_sequence()
	await get_tree().create_timer(3.0).timeout
	await _shoot(dir, "05_S3-02_past_platform_moving", Vector3(7.3, 0.0, -8.1), Vector3(0.7, 0.3, 2.5))
	await get_tree().create_timer(3.5).timeout
	await _shoot(dir, "06_S3-02_past_locked", Vector3(7.3, 0.0, -8.1), Vector3(0.7, 0.3, 2.5))
	era = "present"
	rebuild()
	platform.notify_player_on_deck()
	await get_tree().create_timer(1.6).timeout
	await _shoot(dir, "07_S3-03_present_shutter_dropping", Vector3(4.15, 0.05, -1.5), Vector3(4.15, 2.2, 18.4))
	await get_tree().create_timer(2.0).timeout
	await _shoot(dir, "08_S3-03_present_shutter_down", Vector3(4.15, 0.05, -1.5), Vector3(4.15, 2.2, 18.4))
	print("CAPTURE_DONE")
	get_tree().quit(0)


func _smoke_done() -> void:
	print("DEMO_SMOKE_OK era=%s gate_closed=%s deck_x=%.2f" % [era, gate.is_closed(), platform.deck_x()])
	get_tree().quit(0)


func restart() -> void:
	flags = {"valve_closed_past": false, "platform_locked_past": false, "exit_reached": false}
	era = "present"
	platform.reset_shutter_memory()
	checkpoint = Vector3(4.0, 0.1, -66.0)
	rebuild()
	_reset_player()


func rebuild() -> void:
	gate.cancel_transients()
	platform.cancel_transients()
	gate.apply_state(flags.valve_closed_past, era)
	platform.apply_state(flags.platform_locked_past, era)
	valve_wheel.rotation_degrees.z = 90.0 if flags.valve_closed_past else 0.0
	var past := era == "past"
	env.environment.ambient_light_color = Color("f3d9b4") if past else Color("8f8a9a")
	env.environment.background_color = Color("e9d2b0") if past else Color("5b5560")
	sun.rotation_degrees = Vector3(-12.0, 65.0, 0.0) if past else Vector3(-10.0, -105.0, 0.0)
	sun.light_color = Color("ffe2b8") if past else Color("ffb27a")


func _physics_process(delta: float) -> void:
	_notice_t = maxf(_notice_t - delta, 0.0)
	if _notice_t == 0.0:
		notice.text = ""
	if player.global_position.y < -3.0:
		_on_hazard(player)
	if not flags.exit_reached and era == "present" and flags.valve_closed_past and flags.platform_locked_past \
			and player.global_position.z > 8.0 and player.global_position.z < 16.0:
		flags.exit_reached = true
		_say("演示完成：两个机关都在过去改好，现在通路打通。")
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("switch_era"):
		era = "past" if era == "present" else "present"
		rebuild()
		_say("戴上眼镜：过去 β（清晨）" if era == "past" else "摘下眼镜：现在 α（黄昏）")
	elif event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("checkpoint_reset"):
		rebuild()
		_reset_player()
	elif event.is_action_pressed("restart_level"):
		restart()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _interact() -> void:
	var p := player.global_position
	if p.distance_to(valve_pos) < 2.6:
		if flags.valve_closed_past:
			_say("阀门已经关上了。")
		elif era != "past":
			_say("锈死了。")
		else:
			flags.valve_closed_past = true          # flag first, then the visual transient
			gate.apply_state(true, era)
			gate.play_close()
			valve_wheel.rotation_degrees.z = 90.0
			checkpoint = Vector3(4.0, 0.1, -14.0)
			_say("检修隔离：关闭阀门，隔离门闭合。（6 s）")
		return
	if platform.lever_in_range(p):
		var r := platform.lever_request(era)
		if not r.accepted:
			_say({"seized": "锈死了。", "already_locked": "平台已经锁定。"}.get(r.reason, str(r.reason)))
			return
		flags.platform_locked_past = true
		platform.play_lock_sequence()
		checkpoint = Vector3(6.0, 0.1, -6.0)
		_say("扳动拉杆：① 停放 → ② 对位 → ③ 锁定")
		return
	_say("附近没有可操作的东西。")


func _on_hazard(_body: Node3D) -> void:
	_say("回到检查点。")
	rebuild()
	_reset_player()


func _reset_player() -> void:
	player.global_position = checkpoint
	player.velocity = Vector3.ZERO
	player.rotation = Vector3(0.0, PI, 0.0)      # face south (+Z)


func _say(t: String) -> void:
	notice.text = t
	_notice_t = 3.0


func _update_hud() -> void:
	hud.text = "主蒸汽廊 机关演示 · %s\nvalve_closed_past=%s  platform_locked_past=%s  exit_reached=%s\n门：%s  蒸汽危险=%s  平台 x=%.2f  档位=%d  卷帘=%.0f%%\nWASD 走 · 空格 跳 · E 交互 · Q 切时代 · R 检查点 · T 重开" % [
		"过去 β" if era == "past" else "现在 α", flags.valve_closed_past, flags.platform_locked_past, flags.exit_reached,
		"关" if gate.is_closed() else "开", gate.hazard_active, platform.deck_x(), platform.detent, platform.shutter_progress() * 100.0]


# ------------------------------------------------------------------ static world
func _setup_input() -> void:
	var keys := {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "jump": KEY_SPACE,
		"interact": KEY_E, "switch_era": KEY_Q, "checkpoint_reset": KEY_R, "restart_level": KEY_T}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var key := InputEventKey.new()
		key.physical_keycode = keys[action]
		InputMap.action_add_event(action, key)


func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = Label.new()
	hud.position = Vector2(20, 14)
	hud.add_theme_font_size_override("font_size", 18)
	canvas.add_child(hud)
	notice = Label.new()
	notice.position = Vector2(20, 640)
	notice.add_theme_font_size_override("font_size", 22)
	canvas.add_child(notice)
	var cross := Label.new()
	cross.text = "+"
	cross.position = Vector2(635, 352)
	canvas.add_child(cross)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m


func _solid(size: Vector3, pos: Vector3, c: Color) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.position = pos
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c)
	b.add_child(mi)
	add_child(b)
	return b


func _build_world() -> void:
	env = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_energy = 0.7
	add_child(env)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	add_child(sun)
	var deck := Color("4a4c4f")
	var brick := Color("5a3b30")
	var gap := 2.7
	# passage floor: north part and south landing (G1 level = y 0), 0.4 m thick
	_solid(Vector3(PASSAGE_W, 0.4, 68.0 - gap), Vector3(PASSAGE_W * 0.5, -0.2, -(70.0 + gap) * 0.5), deck)
	_solid(Vector3(PASSAGE_W, 0.4, 19.0 - gap), Vector3(PASSAGE_W * 0.5, -0.2, (19.0 + gap) * 0.5), deck)
	# east outer wall, north end wall, west parapet outside the gate span, funnel rails at the gap
	_solid(Vector3(0.6, 9.0, 90.0), Vector3(PASSAGE_W + 0.3, 4.5, -25.0), brick)
	_solid(Vector3(PASSAGE_W, 9.0, 0.6), Vector3(PASSAGE_W * 0.5, 4.5, -70.3), brick)
	_solid(Vector3(0.1, 1.1, 11.5), Vector3(0.0, 0.55, -64.25), Color("1c1e20"))
	_solid(Vector3(0.1, 1.1, 15.8), Vector3(0.0, 0.55, -10.6), Color("1c1e20"))
	_solid(Vector3(0.1, 1.1, 16.0), Vector3(0.0, 0.55, 10.7), Color("1c1e20"))
	for zz in [-gap - 0.05, gap + 0.05]:
		_solid(Vector3(DECK_X - 1.8, 1.1, 0.1), Vector3((DECK_X - 1.8) * 0.5, 0.55, zz), Color("1c1e20"))
		_solid(Vector3(PASSAGE_W - DECK_X - 1.8, 1.1, 0.1), Vector3(DECK_X + 1.8 + (PASSAGE_W - DECK_X - 1.8) * 0.5, 0.55, zz), Color("1c1e20"))
	# cross wall with the direct doorway (3.0 x 4.2); the doorway itself is a locked fire door in both eras
	_solid(Vector3(DECK_X - 1.5 + 0.1, 5.0, 1.0), Vector3((DECK_X - 1.5 + 0.1) * 0.5 - 0.05, 2.5, 19.0), brick)
	_solid(Vector3(PASSAGE_W - DECK_X - 1.6, 5.0, 1.0), Vector3(DECK_X + 1.6 + (PASSAGE_W - DECK_X - 1.6) * 0.5, 2.5, 19.0), brick)
	_solid(Vector3(3.2, 0.8, 1.0), Vector3(DECK_X, 4.6, 19.0), brick)
	_solid(Vector3(3.0, 4.2, 0.2), Vector3(DECK_X, 2.1, 19.2), Color("7a3b26"))
	# valve station stub on the east wall, wheel facing north (turquoise = operable)
	_solid(Vector3(3.4, 2.6, 1.8), Vector3(valve_pos.x - 0.6, 1.3, valve_pos.z), Color("2a2c2e"))
	valve_wheel = Node3D.new()
	valve_wheel.position = Vector3(valve_pos.x - 0.2, 1.3, valve_pos.z - 1.0)
	add_child(valve_wheel)
	var w := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.36
	tor.outer_radius = 0.42
	w.mesh = tor
	w.rotation_degrees.x = 90.0
	w.material_override = _mat(Color("0e5a55"))
	valve_wheel.add_child(w)
	var lab := Label3D.new()
	lab.text = "阀站（E）\n现在：锈死；过去：关阀 → 大门闭合"
	lab.position = Vector3(valve_pos.x - 0.6, 3.2, valve_pos.z)
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(lab)
	var lab2 := Label3D.new()
	lab2.text = "三档拉杆（E）\n现在：锈死；过去：对位并锁定"
	lab2.position = Vector3(DECK_X + 3.55, 2.6, -6.5)
	lab2.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(lab2)
