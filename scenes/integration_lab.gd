extends Node3D
## Primitive adapter/reference. Level teams replace geometry in their own adapters.
const StateService = preload("res://core/state_service.gd")
const Player = preload("res://core/player.gd")
const HudScene = preload("res://ui/hud.tscn")
const CabinetPanelScene = preload("res://ui/cabinet_panel.tscn")
const UiText = preload("res://ui/ui_text.gd")
const UiTheme = preload("res://ui/theme.tres")
const EraLightingScene = preload("res://era_lighting/era_lighting.tscn")
const GateScene = preload("res://mechanisms/steamhall/big_sliding_gate.tscn")
const PlatformScene = preload("res://mechanisms/steamhall/transfer_platform.tscn")
## mvp_valve test island = the steam-gallery demo slice (mechanisms/steamhall/demo), turned 180 deg so the player
## still walks -Z from the lab spawn: demo (x, y, z) -> lab (4.35 - x, y, -62.5 - z). Valve station at z 0,
## 40 m gate along z -4 .. -44, relay lever on the north transfer landing (z -56), deck centre z -62.5, exit z -74.5.
const VALVE_DEMO_XF := Transform3D(Basis(Vector3.UP, PI), Vector3(4.35, 0.0, -62.5))
const VALVE_EXIT_Z := -74.5
const LEVER_CHECKPOINT := Vector3(0, 0.04, -53.0)
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
var hud: CanvasLayer  # res://ui/hud.tscn
var notice: Label  # hud.notice_label
var code_panel: CanvasLayer  # res://ui/cabinet_panel.tscn
var code_input: LineEdit  # code_panel.line_edit
var device_meta: Dictionary = {}  # device_id -> manifest entry, for prompts
var wheel: Node3D
var gate: BigSlidingGate        # mvp_valve: 40 m isolation gate (mechanisms/steamhall)
var platform: TransferPlatform  # mvp_valve: transfer platform + relay lever + shutter
var era_lighting: EraLighting   # 视效 presets; one WorldEnvironment + sun for the whole lab
var checkpoint_ids: Array = ["Anchors/Checkpoint"]
var door: Node3D
var steam: MeshInstance3D
var lights: Array = []
var hazard_active := false
var ready_to_play := false
var auto_triggers := true
var completions: Dictionary = {}
var last_checkpoint_overlap: Dictionary = {}  # checkpoint id -> player was inside last frame
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
	service.level_completed.connect(func(id): completions[id] += 1)
	# Rejections, flags and completion are shown by the HUD via bind_service().
	_setup_ui()
	# 视效's two-era lighting (past β / present α) replaces the lab's own light and environment; it follows the
	# state through bind_service() once the first level is active. Preset values belong to 视效 (res://era_lighting/).
	era_lighting = EraLightingScene.instantiate()
	add_child(era_lighting)
	player = Player.new()
	player.name = "Player"
	player.service = service
	add_child(player)
	var requested := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="): requested = clampi(int(arg.trim_prefix("--level=")) - 1, 0, 2)
	select_level(requested)
	era_lighting.bind_service(service)
	var args := OS.get_cmdline_user_args()
	if "--test" in args or "--capture" in args or "--valve-flow" in args:
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
	# UI scenes are owned by the UI lead (ui/README.md); this adapter only wires signals.
	hud = HudScene.instantiate()
	add_child(hud)
	hud.bind_service(service)
	notice = hud.notice_label
	code_panel = CabinetPanelScene.instantiate()
	add_child(code_panel)
	code_input = code_panel.line_edit
	code_panel.submitted.connect(submit_code)
	code_panel.cancelled.connect(func(): service.cancel_puzzle_ui())

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
	platform = null
	door = null
	steam = null
	checkpoint_ids = ["Anchors/Checkpoint"]
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
	var exit_z := -20.0 if index == 0 else (VALVE_EXIT_Z if index == 1 else -15.0)
	_anchor("Exit", Vector3(0, 0.04, exit_z))
	trigger_boxes["exit_trigger"] = AABB(Vector3(-2, -0.2, exit_z - 1), Vector3(4, 2.5, 2))
	devices["exit_trigger"] = Vector3(0, 1, exit_z)
	_box("ExitMarker", Vector3(0, 0.03, exit_z), Vector3(3, 0.06, 1.5), Color("72cca5"), "none")
	_sign("出口", Vector3(0, 2.5, exit_z))
	_box("Scale_1m", Vector3(2.5, 0.5, 3), Vector3(0.15, 1, 0.15), Color("f0d56a"), "common")
	_sign("1 m", Vector3(2.5, 1.35, 3))
	_box("CheckpointMarker", Vector3(0, 0.025, 1), Vector3(1.4, 0.05, 1.4), Color("65a6db"), "none")
	_sign("检查点", Vector3(0, 2.7, 1))
	if index == 0: _build_bridge()
	elif index == 1: _build_valve()
	else:
		_box("Floor", Vector3(0,-0.3,-7), Vector3(6,0.6,24), Color("566578"), "common")
		_box("LeftWall", Vector3(-3.15,1.5,-7), Vector3(0.3,3,24), Color("64758a"), "common")
		_box("RightWall", Vector3(3.15,1.5,-7), Vector3(0.3,3,24), Color("64758a"), "common")
		_build_cabinet()
	var r: Dictionary = service.activate(level_ids[index], self)
	assert(r.accepted)
	device_meta.clear()
	for d in service.manifest().devices: device_meta[d.device_id] = d
	last_checkpoint_overlap = {}
	notice.text = UiText.level_name(level_ids[index]) + " · " + UiText.START_NOTICE
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
	_sign("危险 · 桥面断裂",Vector3(0,3,-3))

func _build_valve() -> void:
	# Passage (demo frame, see VALVE_DEMO_XF): 8.7 m wide, north floor to the hoisting-well gap, south landing,
	# cross wall with the direct doorway (a locked fire door in both eras; the system shutter drops in front of it).
	var corridor := Node3D.new()
	corridor.name = "Corridor"
	corridor.transform = VALVE_DEMO_XF
	world.add_child(corridor)
	var w := 8.7
	var deck_x := 4.15
	var deck_col := Color("4a4c4f")
	var brick := Color("5a3b30")
	var steel := Color("1c1e20")
	_box("FloorNorth", Vector3(w*0.5,-0.2,-36.5), Vector3(w,0.4,67), deck_col, "common", corridor)   # z -70 .. -3
	_box("FloorSouth", Vector3(w*0.5,-0.2,11), Vector3(w,0.4,16), deck_col, "common", corridor)      # z 3 .. 19
	_box("EastWall", Vector3(w+0.3,4.5,-25), Vector3(0.6,9,90), brick, "common", corridor)
	_box("NorthWall", Vector3(w*0.5,4.5,-70.3), Vector3(w,9,0.6), brick, "common", corridor)
	_box("ParapetNorth", Vector3(0,0.55,-64.25), Vector3(0.1,1.1,11.5), steel, "common", corridor)
	_box("ParapetMid", Vector3(0,0.55,-10.75), Vector3(0.1,1.1,15.5), steel, "common", corridor)
	_box("ParapetSouth", Vector3(0,0.55,10.75), Vector3(0.1,1.1,15.5), steel, "common", corridor)
	for zz in [-3.1, 3.1]:   # funnel rails: only the deck lane (x 2.35 .. 5.95) and the pin housing are open
		_box("GapRailWest", Vector3(0.65,0.55,zz), Vector3(1.3,1.1,0.1), steel, "common", corridor)
		_box("GapRailEast", Vector3((deck_x+1.8+w)*0.5,0.55,zz), Vector3(w-deck_x-1.8,1.1,0.1), steel, "common", corridor)
	_box("CrossWallWest", Vector3((deck_x-1.4)*0.5-0.05,2.5,19), Vector3(deck_x-1.4,5,1), brick, "common", corridor)
	_box("CrossWallEast", Vector3((deck_x+1.6+w)*0.5,2.5,19), Vector3(w-deck_x-1.6,5,1), brick, "common", corridor)
	_box("CrossWallLintel", Vector3(deck_x,4.6,19), Vector3(3.2,0.8,1), brick, "common", corridor)
	_box("FireDoor", Vector3(deck_x,2.1,19.2), Vector3(3,4.2,0.2), Color("7a3b26"), "common", corridor)
	# Valve station: unchanged from the primitive (main handwheel = ValvePivot).
	_box("ValveShell", Vector3(-2,1,0), Vector3(0.7,2,0.7), Color("81735a"), "common")
	wheel = Node3D.new()
	wheel.name = "ValvePivot"
	wheel.position = Vector3(-1.55,1.3,0)
	moving.add_child(wheel)
	_box("Wheel", Vector3.ZERO, Vector3(0.1,0.7,0.7), Color("de9b53"), "common", wheel)
	devices["valve"] = Vector3(-1.35,1.3,0)
	# 40 m BigSlidingGate on the passage's west side in the demo (east wall here), stack at the valve end.
	gate = GateScene.instantiate()
	gate.name = "IsolationGate"        # -> Moving/IsolationGate/PIVOT_IsolationGate, AREA_SteamCorridor inside
	gate.stack_at_end = true
	gate.transform = VALVE_DEMO_XF * Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(0, 0, -18.5))
	moving.add_child(gate)
	gate.steam_body_entered.connect(_on_mechanism_hazard, CONNECT_DEFERRED)
	var steam_box: AABB = gate.global_transform * AABB(Vector3.ZERO, Vector3(gate.span_m, gate.steam_height_m, gate.steam_depth_m))
	steam_box.position.y -= 0.2   # the area starts at floor level; the player's feet can sit a hair below y 0
	steam_box.size.y += 0.2
	trigger_boxes["steam_hazard"] = steam_box
	devices["steam_hazard"] = steam_box.get_center()
	devices["isolation_gate"] = gate.global_transform * Vector3(gate.span_m * 0.5, 1.4, 0)
	# 联锁栏杆 (past only, 1.1 m; same as L2_BARRIER in the UE steam hall): keeps the player out of the leaf track band,
	# so a closing leaf can't push anyone into the slot between two tracks. Rail along the band's outer edge (gate
	# local z = band + 0.15) plus a cap at each end. Present needs none: open gate = steam, closed gate fills the band.
	var interlock := Node3D.new()
	interlock.name = "GateInterlock"
	interlock.transform = gate.transform
	moving.add_child(interlock)
	var rail_z: float = (gate.leaf_count - 1) * gate.track_spacing + gate.leaf_thickness + 0.15
	_box("L2_BARRIER_GateInterlock", Vector3(gate.span_m * 0.5, 0.55, rail_z), Vector3(gate.span_m + 0.7, 1.1, 0.1), steel, "past", interlock)
	for x in [-0.3, gate.span_m + 0.3]:
		_box("L2_BARRIER_GateInterlockEnd", Vector3(x, 0.55, rail_z * 0.5), Vector3(0.1, 1.1, rail_z), steel, "past", interlock)
	# Transfer section after the valve: platform, three-detent relay lever, lock pins, shutter, fall volume.
	platform = PlatformScene.instantiate()
	platform.name = "TransferPlatform"
	platform.transform = VALVE_DEMO_XF * Transform3D(Basis.IDENTITY, Vector3(deck_x, 0, 0))
	moving.add_child(platform)
	platform.fell_into_gap.connect(_on_mechanism_hazard, CONNECT_DEFERRED)
	devices["relay_lever"] = platform.to_global(platform.lever_offset) + Vector3.UP
	for root in [gate, platform]: _tag_common(root)
	# Second checkpoint on the north transfer landing, before the lever.
	_anchor("Checkpoint2", LEVER_CHECKPOINT)
	checkpoint_ids = ["Anchors/Checkpoint", "Anchors/Checkpoint2"]
	_box("Checkpoint2Marker", LEVER_CHECKPOINT - Vector3(0, 0.015, 0), Vector3(1.4,0.05,1.4), Color("65a6db"), "none")
	_sign("检查点", LEVER_CHECKPOINT + Vector3(0, 2.66, 0))
	_sign("检修隔离：关闭阀门，隔离门闭合",Vector3(0,3,-1))
	_sign("转运平台",devices["relay_lever"] + Vector3(0, 1.6, 0))

## Era-invariant mechanism bodies (gate leaves, deck, rails, relay cabinet, lever pedestal) answer the era-switch
## probes like "common" primitives. The shutter is present-only and the component drives its layer itself.
func _tag_common(root: Node) -> void:
	for n in root.find_children("*", "PhysicsBody3D", true, false):
		if n.name != "MOV_Shutter" and n.collision_layer & 1: n.collision_layer |= QUERY_COMMON

func _on_mechanism_hazard(body: Node3D) -> void:
	# steam_body_entered (present, gate open) / fell_into_gap -> back to the last checkpoint. Connected deferred
	# (the signals fire inside the physics flush); re-check, the poll in _physics_process may have reset already.
	if body != player or not ready_to_play or not service.world_enabled(): return
	var in_steam: bool = hazard_active and trigger_boxes.has("steam_hazard") and trigger_boxes.steam_hazard.has_point(player.position)
	if not in_steam and player.position.y > -1.0: return
	send("reset.request",{"reset_mode":"checkpoint"})
	hud.show_note(UiText.RECOVERED_NOTE)

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
	_sign("送电程序：输入密码 → 按下启动按钮",Vector3(0,3,-1))

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
	label.font = UiTheme.default_font  # CJK-capable UI body font
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
		# Both mechanisms are derived from flags + era only and jump to their terminal state here.
		wheel.rotation.x = PI * 0.5 if state.flags.valve_closed_past else 0.0
		gate.apply_state(state.flags.valve_closed_past, state.era)
		platform.apply_state(state.flags.platform_locked_past, state.era)
		hazard_active = gate.hazard_active
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
	if id == "relay_lever": return is_instance_valid(platform) and platform.lever_in_range(player.global_position)  # 1.6 m
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
func valid_checkpoint(id: String) -> bool: return id in checkpoint_ids
func checkpoint_in_range(id: String) -> bool:
	if not valid_checkpoint(id): return false
	return player.global_position.distance_to(anchors.get_node(id.trim_prefix("Anchors/")).global_position) < 1.0
func reset_player(checkpoint_id) -> void:
	var node: String = checkpoint_id.trim_prefix("Anchors/") if checkpoint_id != null else "Spawn"
	player.global_position = anchors.get_node(node).global_position
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	last_checkpoint_overlap = {}
	if checkpoint_id != null: last_checkpoint_overlap[checkpoint_id] = true
	reset_count += 1
func cancel_transients() -> void:
	if is_instance_valid(code_panel):
		code_panel.close()  # hides and clears the input
	if DisplayServer.get_name() != "headless": Input.mouse_mode = mouse_before_ui
	# Mechanism animations (gate close 6 s, lock sequence ~5.8 s, shutter 3 s) jump to their terminal state.
	if is_instance_valid(gate): gate.cancel_transients()
	if is_instance_valid(platform): platform.cancel_transients()

func send(kind: String, extra: Dictionary = {}) -> Dictionary:
	var event := {"event_type":kind,"level_id":level_ids[index]}
	event.merge(extra)
	return service.request(event)
func interact(id: String, action: String, value = null) -> Dictionary:
	var before: Dictionary = service.snapshot().get("flags", {})
	var r := send("interact.request",{"device_id":id,"action":action,"value":value})
	if index == 1 and is_instance_valid(gate):
		# Core has written the flag (and rebuild() put both mechanisms in their end state); now play the transient.
		if r.accepted and id == "valve" and not before.get("valve_closed_past", false): gate.play_close()          # 6 s
		elif r.accepted and id == "relay_lever" and not before.get("platform_locked_past", false): platform.play_lock_sequence()  # ~5.8 s
		elif r.reason == "seized" and id == "relay_lever": platform.lever_request("present")  # rusted: handle only jiggles
	return r
func submit_code(value: String) -> void:
	interact("cabinet","submit_code",value)  # HUD shows 密码正确 / 密码不对 from state + feedback
func nearest_device() -> String:
	var best := ""
	var distance := INF
	for id in devices:
		if id in ["exit_trigger","far_landing","steam_hazard","isolation_gate"]: continue
		if in_range(id):
			var d: float = player.camera.global_position.distance_to(devices[id])
			if d < distance:
				distance = d
				best = id
	if index == 2 and best in ["cabinet","plaque"]:
		best = "plaque" if service.snapshot().era == "past" else "cabinet"
	return best
func interact_nearest() -> void:
	var best := nearest_device()
	if best.is_empty(): return
	if best == "cabinet":
		var r: Dictionary = service.open_puzzle_ui(best)
		if r.accepted:
			mouse_before_ui = Input.mouse_mode
			hud.hide_interaction()
			code_panel.open(best)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else: hud.show_reason(str(r.reason))
	else:
		var action: String = {"valve":"close","relay_lever":"pull","plaque":"read","start_button":"press"}[best]
		var r := interact(best,action)
		if r.accepted and best == "plaque": hud.show_flag_note("clue_seen")  # show the code again on every read
## Interaction prompt for the nearest device; greyed out with a reason when it belongs to the other era.
func _update_prompt() -> void:
	var best := nearest_device() if service.world_enabled() else ""
	if best.is_empty() or not device_meta.has(best):
		hud.hide_interaction()
		return
	var meta: Dictionary = device_meta[best]
	var eras: Array = meta.get("available_eras", [])
	var blocked := ""
	if not eras.is_empty() and service.snapshot().era not in eras:
		blocked = UiText.ONLY_IN_ERA.get(eras[0], "")
	hud.show_interaction(best, meta.actions[0], blocked)

func _input(event: InputEvent) -> void:
	if not ready_to_play: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if service.input_mode == "puzzle_ui": service.cancel_puzzle_ui()
			else: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if service.world_enabled():
			if event.keycode in [KEY_1,KEY_2,KEY_3]: select_level(event.keycode - KEY_1)
		if event.keycode == KEY_F3: hud.debug_visible = not hud.debug_visible
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and service.world_enabled():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		notice.text = ""

func _physics_process(_delta: float) -> void:
	if not ready_to_play: return
	if Input.is_action_just_pressed("restart_level") and service.world_enabled(): send("reset.request",{"reset_mode":"restart_level"})
	elif Input.is_action_just_pressed("checkpoint_reset") and service.world_enabled(): send("reset.request",{"reset_mode":"checkpoint"})
	elif Input.is_action_just_pressed("switch_era"):
		send("era.switch.request",{"target_era":"past" if service.snapshot().era == "present" else "present"})
	elif Input.is_action_just_pressed("interact") and service.world_enabled(): interact_nearest()
	if player.position.y < -5 or (hazard_active and trigger_boxes.steam_hazard.has_point(player.position)):
		send("reset.request",{"reset_mode":"checkpoint"})
		hud.show_note(UiText.RECOVERED_NOTE)
	if auto_triggers and service.world_enabled():
		for id in checkpoint_ids:
			var cp := checkpoint_in_range(id)
			if cp and not last_checkpoint_overlap.get(id, false): send("checkpoint.reached",{"device_id":id})
			last_checkpoint_overlap[id] = cp
		if index == 0 and at_far_landing() and service.snapshot().era == "past" and not service.snapshot().flags.bridge_crossed_past: interact("far_landing","enter")
		if in_range("exit_trigger") and not service.snapshot().flags.exit_reached: interact("exit_trigger","enter")
	_update_prompt()
	if hud.debug_visible:  # F3
		var state: Dictionary = service.snapshot()
		hud.set_debug_text("PRIMITIVE / GODOT 4.7.2 / LOCAL CANDIDATE\n" + level_ids[index] + " | " + state.era.to_upper() + " | " + service.input_mode + "\nWASD / mouse / Space | E interact | Q era | R checkpoint | T restart | 1/2/3 level | F3 debug\n" + str(state.flags))
