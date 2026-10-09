class_name BigSlidingGate
extends Node3D
## 40 m telescoping isolation gate for the main steam gallery (mvp_valve, city version).
##
## Drop-in for the single 2.4 m leaf: device_id stays "isolation_gate", the moving parent is
## "PIVOT_IsolationGate", the hazard area is "AREA_SteamCorridor", the flag is valve_closed_past.
## State is derived only from (valve_closed_past, era); the close animation is a transient.
##
## Local frame (Godot, Y up): the span runs along +X from 0 to span_m. Leaves slide along +X.
## Track layers stack towards +Z, and +Z is the passage side where the steam spills.
## Open  = every leaf stacked over [0, leaf_w].  Closed = leaf i covers [i*leaf_w, (i+1)*leaf_w].

signal gate_motion_started(closing: bool)
signal gate_motion_finished(closed: bool)
signal steam_body_entered(body: Node3D)

@export var span_m := 40.0
@export var height_m := 7.0
@export var leaf_count := 5
@export var leaf_thickness := 0.25
@export var track_spacing := 0.3
@export var close_seconds := 6.0
@export var steam_depth_m := 8.7
@export var steam_height_m := 4.1
@export var door_in_door := true
## false: open stack sits at local x = 0 and leaves extend towards +X.
## true:  open stack sits at local x = span_m and leaves extend towards 0 (city: stack at the north end).
@export var stack_at_end := false
@export_flags_3d_physics var player_mask := 8
## Optional visible skins (建模 C8: skins/PROP_SteamHallGate40_present / _past .glb). The GLB root frame is this
## node's frame and its Leaf_i nodes sit at the leaf centres, so each Leaf_i's meshes are re-parented under the
## matching leaf body. Only the box meshes are replaced: collision, node names, pivots and states stay the same.
@export var skin_present: PackedScene
@export var skin_past: PackedScene

var hazard_active := false
var _closed := false
var _era := "present"
var _progress := 0.0
var _tween: Tween
var _pivot: Node3D
var _leaves: Array[AnimatableBody3D] = []
var _leaf_meshes: Array[MeshInstance3D] = []
var _frame_meshes: Array[MeshInstance3D] = []
var _inset_meshes: Array[MeshInstance3D] = []
var _skins := {}                     # era -> Array[Node3D] (one holder per leaf + the track skin)
var _steam_area: Area3D
var _steam_fx: CPUParticles3D
var _mat := {}


func _ready() -> void:
	_build()
	_attach_skins()
	apply_state(false, "present")


func has_skin() -> bool:
	return not _skins.is_empty()


func leaf_width() -> float:
	return span_m / float(leaf_count)


func is_closed() -> bool:
	return _closed


func progress() -> float:
	return _progress


## Synchronous: puts everything in the terminal state for these flags (call from adapter.rebuild()).
func apply_state(valve_closed_past: bool, era: String) -> void:
	_kill_tween()
	_closed = valve_closed_past
	_era = era
	_set_progress(1.0 if _closed else 0.0)
	_apply_era_look()
	_update_hazard()


## Visual transient after the past-era valve close was accepted and the flag is already written.
func play_close() -> void:
	_kill_tween()
	_closed = true
	_update_hazard()
	_set_progress(0.0)
	gate_motion_started.emit(true)
	_tween = create_tween()
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)     # leaves are AnimatableBody3D synced to physics
	_tween.tween_method(_set_progress, 0.0, 1.0, close_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.finished.connect(func() -> void: gate_motion_finished.emit(true))


func cancel_transients() -> void:
	_kill_tween()
	_set_progress(1.0 if _closed else 0.0)


func leaf_x(i: int) -> float:
	## Left edge (local X) of leaf i at the current progress.
	var x := float(i) * leaf_width() * _progress
	return span_m - leaf_width() - x if stack_at_end else x


# ------------------------------------------------------------------ internals
func _on_steam_body_entered(b: Node3D) -> void:
	if hazard_active:
		steam_body_entered.emit(b)



func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null


func _set_progress(p: float) -> void:
	_progress = clampf(p, 0.0, 1.0)
	var w := leaf_width()
	for i in _leaves.size():
		_leaves[i].position = Vector3(leaf_x(i) + w * 0.5, height_m * 0.5,
				float(i) * track_spacing + leaf_thickness * 0.5)
	if _steam_fx:
		# steam leaves through whatever is still open
		var covered := float(_leaves.size() - 1) * w * _progress + w
		var open_len := maxf(span_m - covered, 0.0)
		var open_mid := open_len * 0.5 if stack_at_end else covered + open_len * 0.5
		_steam_fx.position = Vector3(open_mid, 1.2, _track_depth() + 0.2)
		_steam_fx.emission_box_extents = Vector3(maxf(open_len * 0.5, 0.05), 1.6, 0.6)
		_steam_fx.emitting = hazard_active and open_len > 0.5


func _track_depth() -> float:
	return float(leaf_count - 1) * track_spacing + leaf_thickness


func _update_hazard() -> void:
	hazard_active = (_era == "present") and not _closed
	if _steam_area:
		_steam_area.monitoring = hazard_active
	if _steam_fx:
		_steam_fx.visible = hazard_active
		_steam_fx.emitting = hazard_active


func _apply_era_look() -> void:
	var leaf_mat: StandardMaterial3D = _mat.past_leaf if _era == "past" else _mat.present_leaf
	for m in _leaf_meshes:
		m.material_override = leaf_mat
	for m in _frame_meshes:
		m.material_override = _mat.frame
	if _skins.is_empty():
		return
	var shown_era: String = _era if _skins.has(_era) else _skins.keys()[0]    # one skin only: both eras
	for e in _skins:
		for n in _skins[e]:
			n.visible = (e == shown_era)


func _attach_skins() -> void:
	for e in ["present", "past"]:
		var ps: PackedScene = skin_present if e == "present" else skin_past
		if ps == null:
			continue
		var inst := ps.instantiate()
		var holders: Array[Node3D] = []
		for i in _leaves.size():
			var src := inst.find_child("Leaf_%d" % i, true, false) as Node3D
			if src == null:
				push_warning("BigSlidingGate skin '%s' has no Leaf_%d" % [e, i])
				continue
			holders.append(_move_children(src, _leaves[i], "Skin_%s" % e, Transform3D.IDENTITY))
		var track := inst.find_child("Track", true, false) as Node3D
		if track:
			holders.append(_move_children(track, _pivot, "TrackSkin_%s" % e, track.transform))
		inst.free()
		_skins[e] = holders
	if _skins.is_empty():
		return
	for m in _leaf_meshes + _frame_meshes + _inset_meshes:
		m.visible = false


func _move_children(src: Node3D, dst: Node3D, holder_name: String, xf: Transform3D) -> Node3D:
	## Moves src's children under a new holder below dst; their transforms stay relative to src.
	var holder := Node3D.new()
	holder.name = holder_name
	holder.transform = xf
	dst.add_child(holder)
	for c in src.get_children():
		_clear_owner(c)                  # nodes leave the imported scene: drop its owner (no inconsistent-owner warnings)
		src.remove_child(c)
		holder.add_child(c)
	return holder


func _clear_owner(n: Node) -> void:
	n.owner = null
	for c in n.get_children():
		_clear_owner(c)


func _make_mat(c: Color, rough := 0.7, metal := 0.4) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _box_mesh(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _build() -> void:
	_mat.past_leaf = _make_mat(Color("3b3f42"), 0.55, 0.5)       # dark painted steel
	_mat.present_leaf = _make_mat(Color("6a3a22"), 0.9, 0.2)     # rust
	_mat.frame = _make_mat(Color("0e5a55"), 0.45, 0.2)           # turquoise enamel: operable gear
	_mat.inset = _make_mat(Color("24282a"), 0.6, 0.4)
	var steam_mat := StandardMaterial3D.new()
	steam_mat.albedo_color = Color(0.93, 0.94, 0.96, 0.4)
	steam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	steam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	steam_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mat.steam = steam_mat

	_pivot = Node3D.new()
	_pivot.name = "PIVOT_IsolationGate"
	add_child(_pivot)
	var w := leaf_width()
	for i in leaf_count:
		var body := AnimatableBody3D.new()
		body.name = "Leaf_%d" % i
		body.collision_layer = 1
		body.collision_mask = 0
		body.sync_to_physics = true
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(w, height_m, leaf_thickness)
		shape.shape = bs
		body.add_child(shape)
		_leaf_meshes.append(_box_mesh(body, Vector3(w, height_m, leaf_thickness), Vector3.ZERO, _mat.present_leaf))
		# riveted-panel rhythm: two horizontal rails on each leaf
		for yy in [-height_m * 0.25, height_m * 0.25]:
			_frame_meshes.append(_box_mesh(body, Vector3(w, 0.12, leaf_thickness + 0.04), Vector3(0, yy, 0), _mat.frame))
		if door_in_door and i == 0:          # the fixed leaf carries the personnel door
			_inset_meshes.append(_box_mesh(body, Vector3(2.4, 2.7, leaf_thickness + 0.02), Vector3(0, -height_m * 0.5 + 1.35, 0), _mat.inset))
		_pivot.add_child(body)
		_leaves.append(body)
	# static top track over the whole span (one beam per layer, merged)
	var track := StaticBody3D.new()
	track.name = "Track"
	track.collision_layer = 0
	_pivot.add_child(track)
	_frame_meshes.append(_box_mesh(track, Vector3(span_m, 0.3, _track_depth() + 0.2),
			Vector3(span_m * 0.5, height_m + 0.15, _track_depth() * 0.5), _mat.frame))
	# hazard area: the whole passage from the pier face (local z 0) - it overlaps the track strip on purpose,
	# so the open part of the strip south of the stacked leaves is covered too
	_steam_area = Area3D.new()
	_steam_area.name = "AREA_SteamCorridor"
	_steam_area.collision_layer = 0
	_steam_area.collision_mask = player_mask
	var acs := CollisionShape3D.new()
	var area_box := BoxShape3D.new()
	area_box.size = Vector3(span_m, steam_height_m, steam_depth_m)
	acs.shape = area_box
	acs.position = Vector3(span_m * 0.5, steam_height_m * 0.5, steam_depth_m * 0.5)
	_steam_area.add_child(acs)
	_steam_area.body_entered.connect(_on_steam_body_entered)
	add_child(_steam_area)
	# steam particles (CPU: works in GL Compatibility)
	_steam_fx = CPUParticles3D.new()
	_steam_fx.name = "SteamFX"
	_steam_fx.amount = 900
	_steam_fx.lifetime = 4.0
	_steam_fx.preprocess = 4.0
	_steam_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_steam_fx.direction = Vector3(0, 0.25, 1)
	_steam_fx.spread = 25.0
	_steam_fx.initial_velocity_min = 1.2
	_steam_fx.initial_velocity_max = 2.6
	_steam_fx.gravity = Vector3(0, 0.35, 0)
	_steam_fx.damping_min = 0.2
	_steam_fx.damping_max = 0.5
	_steam_fx.scale_amount_min = 2.5
	_steam_fx.scale_amount_max = 5.0
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = _mat.steam
	_steam_fx.mesh = q
	add_child(_steam_fx)
