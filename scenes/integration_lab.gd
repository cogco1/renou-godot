extends Node3D
## Primitive adapter/reference. Level teams replace geometry in their own adapters.
const StateService = preload("res://core/state_service.gd")
const Player = preload("res://core/player.gd")
const QUERY_COMMON := 65536
const QUERY_PRESENT := 131072
const QUERY_PAST := 262144
var service: Node
var player: CharacterBody3D
var world: Node3D
var anchors: Node3D
var moving: Node3D
var solids: Array = []
var devices: Dictionary = {}
var trigger_boxes: Dictionary = {}
var labels: Array = []
var index := 0
var level_ids := ["mvp_bridge", "mvp_valve", "mvp_cabinet"]
var hud: Label
var notice: Label
var code_panel: PanelContainer
var code_input: LineEdit
var wheel: Node3D
var gate: Node3D
var door: Node3D
var steam: MeshInstance3D
var lights: Array = []
var hazard_active := false
var ready_to_play := false
var auto_triggers := true
var completions: Dictionary = {}
var last_checkpoint_overlap := false
var reset_count := 0
var mouse_before_ui := Input.MOUSE_MODE_VISIBLE

func _ready() -> void:
	_setup_input()
	service = StateService.new()
	add_child(service)
	for id in level_ids:
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://contracts/" + id + ".json"))
		var r: Dictionary = service.register_level(manifest)
		assert(r.accepted, str(r))
		completions[id] = 0
	service.level_completed.connect(func(id):
		completions[id] += 1
		notice.text = "COMPLETED | " + id + " | Free movement / Q / restart still available")
	service.feedback.connect(func(r):
		if not r.accepted: notice.text = "Request rejected: " + str(r.reason))
	_setup_ui()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -25, 0)
	light.light_energy = 1.6
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("253143")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c2d4e7")
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	player = Player.new()
	player.name = "Player"
	player.service = service
	add_child(player)
	var requested := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="): requested = clampi(int(arg.trim_prefix("--level=")) - 1, 0, 2)
	select_level(requested)
	if "--test" in OS.get_cmdline_user_args() or "--capture" in OS.get_cmdline_user_args():
		var runner = load("res://tests/runtime_tests.gd").new()
		add_child(runner)
		runner.call_deferred("run", self)

func _setup_input() -> void:
	var keys := {"move_forward":KEY_W,"move_back":KEY_S,"move_left":KEY_A,"move_right":KEY_D,"jump":KEY_SPACE,"interact":KEY_E,"switch_era":KEY_Q,"checkpoint_reset":KEY_R,"restart_level":KEY_T}
	for action in keys:
		if not InputMap.has_action(action): InputMap.add_action(action)
		var key := InputEventKey.new()
		key.physical_keycode = keys[action]
		InputMap.action_add_event(action, key)

func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = Label.new()
	hud.position = Vector2(24, 18)
	hud.size = Vector2(1230, 160)
	hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.add_theme_font_size_override("font_size", 18)
	canvas.add_child(hud)
	notice = Label.new()
	notice.position = Vector2(24, 640)
	notice.size = Vector2(1230, 75)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.add_theme_font_size_override("font_size", 18)
	canvas.add_child(notice)
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.position = Vector2(635, 352)
	canvas.add_child(crosshair)
	code_panel = PanelContainer.new()
	code_panel.position = Vector2(380, 245)
	code_panel.custom_minimum_size = Vector2(520, 180)
	canvas.add_child(code_panel)
	var box := VBoxContainer.new()
	code_panel.add_child(box)
	var title := Label.new()
	title.text = "LOCAL TEST ONLY: 0427\nFinal story code is UNCONFIRMED\nEnter: submit | Escape: cancel"
	box.add_child(title)
	code_input = LineEdit.new()
	code_input.placeholder_text = "Test code"
	box.add_child(code_input)
	code_input.text_submitted.connect(submit_code)
	var submit := Button.new()
	submit.text = "Submit"
	submit.pressed.connect(func(): submit_code(code_input.text))
	box.add_child(submit)
	code_panel.hide()

func select_level(which: int) -> void:
	ready_to_play = false
	cancel_transients()
	if is_instance_valid(world): world.free()
	solids.clear()
	devices.clear()
	trigger_boxes.clear()
	labels.clear()
	lights.clear()
	wheel = null
	gate = null
	door = null
	steam = null
	index = which
	world = Node3D.new()
	world.name = "Level"
	add_child(world)
	anchors = Node3D.new()
	anchors.name = "Anchors"
	world.add_child(anchors)
	moving = Node3D.new()
	moving.name = "Moving"
	world.add_child(moving)
	_anchor("Entry", Vector3(0, 0.04, 4))
	_anchor("Spawn", Vector3(0, 0.04, 3))
	_anchor("SafeReturn", Vector3(0, 0.04, 3))
	_anchor("Checkpoint", Vector3(0, 0.04, 1))
	var exit_z := -20.0 if index == 0 else -15.0
	_anchor("Exit", Vector3(0, 0.04, exit_z))
	trigger_boxes["exit_trigger"] = AABB(Vector3(-2, -0.2, exit_z - 1), Vector3(4, 2.5, 2))
	devices["exit_trigger"] = Vector3(0, 1, exit_z)
	_box("ExitMarker", Vector3(0, 0.03, exit_z), Vector3(3, 0.06, 1.5), Color("72cca5"), "none")
	_sign("EXIT", Vector3(0, 2.5, exit_z))
	_box("Scale_1m", Vector3(2.5, 0.5, 3), Vector3(0.15, 1, 0.15), Color("f0d56a"), "common")
	_sign("1 m", Vector3(2.5, 1.35, 3))
	_box("CheckpointMarker", Vector3(0, 0.025, 1), Vector3(1.4, 0.05, 1.4), Color("65a6db"), "none")
	_sign("CHECKPOINT", Vector3(0, 2.7, 1))
	if index == 0: _build_bridge()
	else:
		_box("Floor", Vector3(0,-0.3,-7), Vector3(6,0.6,24), Color("566578"), "common")
		_box("LeftWall", Vector3(-3.15,1.5,-7), Vector3(0.3,3,24), Color("64758a"), "common")
		_box("RightWall", Vector3(3.15,1.5,-7), Vector3(0.3,3,24), Color("64758a"), "common")
		if index == 1: _build_valve()
		else: _build_cabinet()
	var r: Dictionary = service.activate(level_ids[index], self)
	assert(r.accepted)
	last_checkpoint_overlap = false
	notice.text = "Independent primitive integration candidate | Click to capture mouse"
	ready_to_play = true

func _anchor(n: String, p: Vector3) -> void:
	var marker := Marker3D.new()
	marker.name = n
	marker.position = p
	anchors.add_child(marker)

func _build_bridge() -> void:
	_box("NearLanding", Vector3(0,-0.3,1), Vector3(6,0.6,8), Color("566578"), "common")
	_box("FarLanding", Vector3(0,-0.3,-18), Vector3(6,0.6,8), Color("566578"), "common")
	_box("PastBridge", Vector3(0,-0.15,-8.5), Vector3(3,0.3,11), Color("bca978"), "past")
	_box("PresentStubA", Vector3(0,-0.15,-3.8), Vector3(3,0.3,1.6), Color("888078"), "present")
	_box("PresentStubB", Vector3(0,-0.15,-13.2), Vector3(3,0.3,1.6), Color("888078"), "present")
	for x in [-1.55,1.55]:
		_box("PastRail",Vector3(x,0.65,-8.5),Vector3(0.1,1.3,11),Color("8b9ca8"),"past")
	trigger_boxes["far_landing"] = AABB(Vector3(-2.8,-0.2,-22), Vector3(5.6,2.5,7.5))
	devices["far_landing"] = Vector3(0,1,-16)
	_sign("Q: PAST BRIDGE | 7.8 m PRESENT GAP",Vector3(0,3,-3))

func _build_valve() -> void:
	_box("ValveShell", Vector3(-2,1,0), Vector3(0.7,2,0.7), Color("81735a"), "common")
	wheel = Node3D.new()
	wheel.name = "ValvePivot"
	wheel.position = Vector3(-1.55,1.3,0)
	moving.add_child(wheel)
	_box("Wheel", Vector3.ZERO, Vector3(0.1,0.7,0.7), Color("de9b53"), "common", wheel)
	devices["valve"] = Vector3(-1.35,1.3,0)
	gate = Node3D.new()
	gate.name = "IsolationPivot"
	gate.position = Vector3(-2.85,1.4,-5)
	moving.add_child(gate)
	_box("IsolationLeaf",Vector3.ZERO,Vector3(0.15,2.6,2),Color("907c62"),"common",gate)
	devices["isolation_gate"] = Vector3(-2.6,1.4,-5)
	steam = _box("SteamHazard",Vector3(0,1,-8),Vector3(5.8,2,2),Color(0.8,0.85,0.9,0.4),"none")
	devices["steam_hazard"] = Vector3(0,1,-8)
	trigger_boxes["steam_hazard"] = AABB(Vector3(-3,-0.2,-9), Vector3(6,2.5,2))
	_sign("E: CLOSE VALVE IN PAST\nISOLATION LEAF STAYS BESIDE THE ROUTE",Vector3(0,3,-1))

func _build_cabinet() -> void:
	_box("CabinetShell",Vector3(-2,1,0),Vector3(0.7,2,1),Color("687c80"),"common")
	_box("PastPlaque",Vector3(-1.57,1.4,0),Vector3(0.08,0.45,0.7),Color("e3cf91"),"past")
	devices["plaque"] = Vector3(-1.4,1.4,0)
	devices["cabinet"] = Vector3(-1.4,1.4,0)
	_box("PresentPanel",Vector3(-1.57,1.4,0),Vector3(0.08,0.45,0.7),Color("5595b0"),"present")
	_box("StartButton",Vector3(-2,1.2,-2),Vector3(0.5,0.5,0.5),Color("6cbd8c"),"present")
	devices["start_button"] = Vector3(-1.6,1.2,-2)
	door = Node3D.new()
	door.name = "ExitDoorPivot"
	door.position = Vector3(0,1.5,-10)
	moving.add_child(door)
	_box("PresentDoor",Vector3.ZERO,Vector3(6,3,0.3),Color("677c8d"),"present",door)
	_box("PastDoor_ProvisionalClosed",Vector3(0,1.5,-10),Vector3(6,3,0.3),Color("8d8272"),"past")
	for z in [-3,-12]:
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(0,2.5,z)
		lamp.omni_range = 7
		lamp.light_color = Color("ffe6b5")
		world.add_child(lamp)
		lights.append(lamp)
	_sign("PAST: READ PLAQUE | PRESENT: INPUT THEN BUTTON\nLOCAL TEST CODE 0427 - NOT STORY APPROVED",Vector3(0,3,-1))

func _box(n: String, p: Vector3, size: Vector3, color: Color, era: String, parent: Node3D = null) -> MeshInstance3D:
	if parent == null: parent = world
	var body := StaticBody3D.new()
	body.name = n
	body.position = p
	body.collision_layer = 0
	body.collision_mask = 0
	parent.add_child(body)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if color.a < 1: mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat
	body.add_child(mesh)
	if era != "none":
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
		solids.append({"body":body,"era":era})
	return mesh

func _sign(text: String, p: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = p
	label.font_size = 32
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	world.add_child(label)
	labels.append(label)

func rebuild(state: Dictionary) -> void:
	hazard_active = false
	for item in solids:
		var active: bool = item.era == "common" or item.era == state.era
		var query: int = QUERY_COMMON if item.era == "common" else (QUERY_PRESENT if item.era == "present" else QUERY_PAST)
		item.body.collision_layer = query | (1 if active else 0)
		item.body.visible = active
	if index == 1:
		wheel.rotation.x = PI * 0.5 if state.flags.valve_closed_past else 0.0
		gate.position.z = -5.0 if state.flags.valve_closed_past else -7.0
		hazard_active = state.era == "present" and not state.flags.valve_closed_past
		steam.visible = hazard_active
	elif index == 2:
		door.position.y = 4.6 if state.flags.power_on else 1.5
		for lamp in lights: lamp.light_energy = 2.0 if state.era == "present" and state.flags.power_on else 0.0
	else: hazard_active = false

func _query_mask(era: String) -> int:
	return QUERY_COMMON | (QUERY_PRESENT if era == "present" else QUERY_PAST)

func switch_safety(target: String) -> bool:
	if not player.is_on_floor(): return false
	var space := get_world_3d().direct_space_state
	var mask := _query_mask(target)
	# Five support probes: center and capsule footprint. No teleport on failure.
	for offset in [Vector3.ZERO,Vector3(0.24,0,0),Vector3(-0.24,0,0),Vector3(0,0,0.24),Vector3(0,0,-0.24)]:
		var foot: Vector3 = player.global_position + offset
		var ray := PhysicsRayQueryParameters3D.create(foot + Vector3.UP * 0.15, foot - Vector3.UP * 0.3, mask)
		ray.exclude = [player.get_rid()]
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or hit.normal.dot(Vector3.UP) < 0.8: return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = player.shape
	query.transform = Transform3D(Basis.IDENTITY, player.global_position + Vector3.UP * 0.94)
	query.collision_mask = mask
	query.exclude = [player.get_rid()]
	query.margin = 0.005
	if not space.intersect_shape(query, 1).is_empty(): return false
	if index == 1 and target == "present" and not service.snapshot().flags.valve_closed_past and trigger_boxes.steam_hazard.has_point(player.global_position): return false
	return true

func in_range(id: String) -> bool:
	if trigger_boxes.has(id): return trigger_boxes[id].has_point(player.global_position)
	if not devices.has(id): return false
	var origin: Vector3 = player.camera.global_position
	var target: Vector3 = devices[id]
	if origin.distance_to(target) > 2.5: return false
	var ray := PhysicsRayQueryParameters3D.create(origin, target, 1)
	ray.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.is_empty() or hit.position.distance_to(target) < 0.25

func at_far_landing() -> bool:
	return index == 0 and trigger_boxes.far_landing.has_point(player.global_position)
func valid_checkpoint(id: String) -> bool: return id == "Anchors/Checkpoint"
func checkpoint_in_range(_id: String) -> bool:
	return player.global_position.distance_to(anchors.get_node("Checkpoint").global_position) < 1.0
func reset_player(checkpoint_id) -> void:
	var node := "Checkpoint" if checkpoint_id != null else "Spawn"
	player.global_position = anchors.get_node(node).global_position
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	last_checkpoint_overlap = checkpoint_id != null
	reset_count += 1
func cancel_transients() -> void:
	if is_instance_valid(code_panel):
		code_panel.hide()
		code_input.text = ""
	if DisplayServer.get_name() != "headless": Input.mouse_mode = mouse_before_ui
	# No delayed state writers or animations in MVP. Future tweens must be killed here.

func send(kind: String, extra: Dictionary = {}) -> Dictionary:
	var event := {"event_type":kind,"level_id":level_ids[index]}
	event.merge(extra)
	return service.request(event)
func interact(id: String, action: String, value = null) -> Dictionary:
	return send("interact.request",{"device_id":id,"action":action,"value":value})
func submit_code(value: String) -> void:
	var r := interact("cabinet","submit_code",value)
	notice.text = "Cabinet unlocked. E at start button." if r.accepted else "Code result: " + str(r.reason) + " | E to retry"
func interact_nearest() -> void:
	var best := ""
	var distance := INF
	for id in devices:
		if id in ["exit_trigger","far_landing","steam_hazard","isolation_gate"]: continue
		if in_range(id):
			var d: float = player.camera.global_position.distance_to(devices[id])
			if d < distance:
				distance = d
				best = id
	if best.is_empty():
		notice.text = "No device in range (2.5 m / line of sight)"
		return
	if index == 2 and best in ["cabinet","plaque"]:
		best = "plaque" if service.snapshot().era == "past" else "cabinet"
	if best == "cabinet":
		var r: Dictionary = service.open_puzzle_ui(best)
		if r.accepted:
			mouse_before_ui = Input.mouse_mode
			code_panel.show()
			code_input.grab_focus()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else: notice.text = str(r.reason)
	else:
		var action: String = {"valve":"close","plaque":"read","start_button":"press"}[best]
		var r := interact(best,action)
		if r.accepted: notice.text = "LOCAL TEST CLUE: 0427" if best == "plaque" else best + ": accepted"

func _input(event: InputEvent) -> void:
	if not ready_to_play: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if service.input_mode == "puzzle_ui": service.cancel_puzzle_ui()
			else: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if service.world_enabled():
			if event.keycode in [KEY_1,KEY_2,KEY_3]: select_level(event.keycode - KEY_1)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and service.world_enabled(): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(_delta: float) -> void:
	if not ready_to_play: return
	if Input.is_action_just_pressed("restart_level") and service.world_enabled(): send("reset.request",{"reset_mode":"restart_level"})
	elif Input.is_action_just_pressed("checkpoint_reset") and service.world_enabled(): send("reset.request",{"reset_mode":"checkpoint"})
	elif Input.is_action_just_pressed("switch_era"):
		send("era.switch.request",{"target_era":"past" if service.snapshot().era == "present" else "present"})
	elif Input.is_action_just_pressed("interact") and service.world_enabled(): interact_nearest()
	if player.position.y < -5 or (hazard_active and trigger_boxes.steam_hazard.has_point(player.position)):
		send("reset.request",{"reset_mode":"checkpoint"})
		notice.text = "Failure recovered from checkpoint / initial state"
	if auto_triggers and service.world_enabled():
		var cp := checkpoint_in_range("Anchors/Checkpoint")
		if cp and not last_checkpoint_overlap: send("checkpoint.reached",{"device_id":"Anchors/Checkpoint"})
		last_checkpoint_overlap = cp
		if index == 0 and at_far_landing() and service.snapshot().era == "past" and not service.snapshot().flags.bridge_crossed_past: interact("far_landing","enter")
		if in_range("exit_trigger") and not service.snapshot().flags.exit_reached: interact("exit_trigger","enter")
	var state: Dictionary = service.snapshot()
	hud.text = "PRIMITIVE / GODOT 4.7.2 / LOCAL CANDIDATE\n" + level_ids[index] + " | " + state.era.to_upper() + " | " + service.input_mode + "\nWASD / mouse / Space | E interact | Q era | R checkpoint | T restart | 1/2/3 level\n" + str(state.flags)
