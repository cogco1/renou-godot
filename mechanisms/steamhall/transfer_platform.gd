class_name TransferPlatform
extends Node3D
## Rail transfer platform + three-detent relay lever + system shutter (storyboard S3-01..03).
##
## Persistent state is only (platform_locked_past, era); everything else is derived:
##   deck aligned + pins locked  <=> platform_locked_past       (both eras)
##   lever detent                = 3 if locked else 1
##   shutter down (present only) <=> platform_locked_past  (first step onto the deck plays the 3 s drop)
## Animations are transients: apply_state()/cancel_transients() jump to the terminal state.
##
## Local frame (Godot, Y up, metres) = world-aligned offsets from the ALIGNED deck centre top:
##   +X east (rail travel; parked position is at -travel_m), -Z north. Gap runs along Z: |z| < gap_m/2.
## City placement: origin = (-426.55, 9.70, -1006.5) in Godot = Blender (-426.55, 1006.5, 9.70).

signal lever_moved(detent: int)
signal platform_aligned()
signal platform_locked()
signal shutter_dropped()
signal fell_into_gap(body: Node3D)

@export var travel_m := 13.85
@export var deck_size := Vector3(3.6, 0.5, 6.0)
@export var gap_m := 5.4
@export var rail_length_m := 23.0
@export var lever_offset := Vector3(3.55, 0.0, -6.5)
@export var cabinet_offset := Vector3(4.25, 0.0, -4.7)
@export var pin_x := -2.6
@export var shutter_offset := Vector3(0.1, 0.0, 18.4)
@export var shutter_size := Vector2(3.4, 4.6)
@export var lever_reach_m := 1.6
@export var deck_seconds := 4.0
@export var shutter_seconds := 3.0
@export_flags_3d_physics var player_mask := 8

var locked := false
var era := "present"
var detent := 1
var shutter_down := false
var _shutter_armed := false
var _tween: Tween
var _shutter_tween: Tween
var _deck: AnimatableBody3D
var _deck_x := 0.0
var _deck_meshes: Array[MeshInstance3D] = []
var _pins: Array[Node3D] = []
var _lever_pivot: Node3D
var _lamps: Array[MeshInstance3D] = []
var _shutter: AnimatableBody3D
var _slats: Array[MeshInstance3D] = []
var _signal_lamps: Array[MeshInstance3D] = []
var _mat := {}


func _ready() -> void:
	_build()
	apply_state(false, "present")


# ------------------------------------------------------------------ public API
func apply_state(platform_locked_past: bool, era_name: String) -> void:
	_kill_tweens()
	if not platform_locked_past:
		shutter_down = false        # level restart clears the "already dropped" memory with the flag
	locked = platform_locked_past
	era = era_name
	_set_deck(0.0 if locked else -travel_m)
	_set_pins(1.0 if locked else 0.0)
	_set_lever(3 if locked else 1)
	var down := (era == "present") and locked
	_shutter_armed = down and not shutter_down   # first step onto the deck will play the drop
	_set_shutter(1.0 if shutter_down and down else 0.0)
	_apply_era_look()


func lever_request(era_name: String) -> Dictionary:
	## Era first (present lever is always rusted solid), then the one-way lock - same order as core.
	if era_name != "past":
		_jiggle_lever()
		return {"accepted": false, "reason": "seized"}
	if locked:
		return {"accepted": false, "reason": "already_locked"}
	return {"accepted": true, "reason": null}


## Call after lever_request() was accepted AND the adapter has written platform_locked_past = true.
func play_lock_sequence() -> void:
	_kill_tweens()
	locked = true
	_set_deck(-travel_m)
	_set_pins(0.0)
	_set_lever(1)
	_tween = create_tween()
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)     # deck is an AnimatableBody3D synced to physics
	_tween.tween_method(_lever_angle, -35.0, 0.0, 0.6)
	_tween.tween_callback(_on_detent.bind(2))
	_tween.tween_method(_set_deck, -travel_m, 0.0, deck_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(platform_aligned.emit)
	_tween.tween_method(_lever_angle, 0.0, 35.0, 0.4)
	_tween.tween_callback(_on_detent.bind(3))
	_tween.tween_method(_set_pins, 0.0, 1.0, 0.8)
	_tween.tween_callback(platform_locked.emit)


## Present era, platform locked: the system closes the direct doorway once the player is on the deck.
func notify_player_on_deck() -> void:
	if not _shutter_armed or era != "present" or not locked:
		return
	_shutter_armed = false
	if _shutter_tween and _shutter_tween.is_valid():
		_shutter_tween.kill()
	_shutter_tween = create_tween()
	_shutter_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_shutter_tween.tween_method(_set_shutter, 0.0, 1.0, shutter_seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_shutter_tween.parallel().tween_method(_run_signal_lamps, 0.0, float(_signal_lamps.size()), shutter_seconds)
	_shutter_tween.tween_callback(_on_shutter_done)


func cancel_transients() -> void:
	var was_dropping := _shutter_tween != null and _shutter_tween.is_valid()
	_kill_tweens()
	if was_dropping:
		shutter_down = true
	apply_state(locked, era)


func deck_x() -> float:
	return _deck_x


func pins_progress() -> float:
	return _pins[0].get_meta("p", 0.0) if _pins.size() > 0 else 0.0


func shutter_progress() -> float:
	return _shutter.get_meta("p", 0.0)


func shutter_blocking() -> bool:
	return (_shutter.collision_layer & 1) != 0 and shutter_progress() > 0.95


func lever_in_range(world_pos: Vector3) -> bool:
	var lp := to_global(lever_offset)
	var d := world_pos - lp
	return Vector2(d.x, d.z).length() <= lever_reach_m and absf(d.y) < 2.0


func _on_deck_sensor(_body: Node3D) -> void:
	notify_player_on_deck()


func reset_shutter_memory() -> void:
	## Normally not needed: apply_state(false, ...) already clears the memory on a level restart.
	shutter_down = false


# ------------------------------------------------------------------ internals
func _on_detent(d: int) -> void:
	detent = d
	lever_moved.emit(d)


func _on_shutter_done() -> void:
	shutter_down = true
	shutter_dropped.emit()


func _kill_tweens() -> void:
	for t in [_tween, _shutter_tween]:
		if t and t.is_valid():
			t.kill()
	_tween = null
	_shutter_tween = null


func _set_deck(x: float) -> void:
	_deck_x = x
	_deck.position = Vector3(x, -deck_size.y * 0.5, 0.0)


func _set_pins(p: float) -> void:
	for pin in _pins:
		pin.set_meta("p", p)
		pin.position.x = pin.get_meta("x0") + 0.8 * p


func _set_lever(d: int) -> void:
	detent = d
	_lever_angle({1: -35.0, 2: 0.0, 3: 35.0}[d])


func _lever_angle(deg: float) -> void:
	_lever_pivot.rotation_degrees = Vector3(0, 0, -deg)


func _jiggle_lever() -> void:
	if _tween and _tween.is_valid():
		return
	_tween = create_tween()
	_tween.tween_method(_lever_angle, -35.0, -31.0, 0.1)
	_tween.tween_method(_lever_angle, -31.0, -35.0, 0.2)


func _set_shutter(p: float) -> void:
	p = clampf(p, 0.0, 1.0)
	_shutter.set_meta("p", p)
	var n := _slats.size()
	var h := shutter_size.y / float(n)
	for i in n:
		# slat i (0 = top) drops with a small stagger; fully down at p = 1
		var local_p := clampf(p * 1.4 - float(n - 1 - i) * 0.4 / float(n), 0.0, 1.0)
		var y_down := shutter_size.y - (float(i) + 0.5) * h
		var y_up := shutter_size.y - 0.5 * h
		_slats[i].position.y = lerpf(y_up, y_down, local_p)
		_slats[i].visible = local_p > 0.01 or i == 0
	var present := era == "present"
	_shutter.visible = present and locked
	_shutter.collision_layer = 1 if (present and locked and p > 0.95) else 0


func _run_signal_lamps(t: float) -> void:
	for i in _signal_lamps.size():
		_signal_lamps[i].material_override = _mat.amber if int(t) == i else _mat.lamp_off


func _apply_era_look() -> void:
	var past := era == "past"
	for m in _deck_meshes:
		m.material_override = _mat.deck_past if past else _mat.deck_present
	for i in _lamps.size():
		_lamps[i].material_override = _mat.amber if (past or i == 0) else _mat.lamp_off
	for l in _signal_lamps:
		l.material_override = _mat.amber


func _make_mat(c: Color, rough := 0.7, metal := 0.4, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _box_col(body: CollisionObject3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	body.add_child(cs)


func _build() -> void:
	_mat.deck_past = _make_mat(Color("3d4144"), 0.55, 0.5)
	_mat.deck_present = _make_mat(Color("6b3a22"), 0.9, 0.2)
	_mat.steel = _make_mat(Color("1c1e20"), 0.6, 0.6)
	_mat.trim = _make_mat(Color("0e5a55"), 0.45, 0.2)
	_mat.amber = _make_mat(Color(1.0, 0.55, 0.12), 0.4, 0.0, 6.0)
	_mat.lamp_off = _make_mat(Color("2a2420"), 0.6, 0.2)
	var hw := deck_size.x * 0.5
	var hl := deck_size.z * 0.5
	# rails: wedge-topped beams (sides steeper than 45 deg -> not standable)
	var rails := StaticBody3D.new()
	rails.name = "Rails"
	rails.collision_layer = 1
	add_child(rails)
	var x0 := -travel_m - hw - 1.0
	var x1 := x0 + rail_length_m
	for zz in [-gap_m * 0.5 + 0.2, gap_m * 0.5 - 0.2]:
		_box(rails, Vector3(x1 - x0, 0.5, 0.4), Vector3((x0 + x1) * 0.5, -deck_size.y - 0.25, zz), _mat.steel)
		var cs := CollisionShape3D.new()
		var wedge := ConvexPolygonShape3D.new()
		wedge.points = PackedVector3Array([
			Vector3(x0, -deck_size.y - 0.5, zz - 0.2), Vector3(x0, -deck_size.y - 0.5, zz + 0.2), Vector3(x0, -deck_size.y + 0.1, zz),
			Vector3(x1, -deck_size.y - 0.5, zz - 0.2), Vector3(x1, -deck_size.y - 0.5, zz + 0.2), Vector3(x1, -deck_size.y + 0.1, zz)])
		cs.shape = wedge
		rails.add_child(cs)
	# deck (moving) with side railings, turquoise side beams, four amber beacons, step-on sensor
	_deck = AnimatableBody3D.new()
	_deck.name = "MOV_TransferDeck"
	_deck.collision_layer = 1
	_deck.collision_mask = 0
	_deck.sync_to_physics = true
	add_child(_deck)
	_box_col(_deck, deck_size, Vector3.ZERO)
	_deck_meshes.append(_box(_deck, deck_size, Vector3.ZERO, _mat.deck_present))
	for sx in [-1.0, 1.0]:
		_box(_deck, Vector3(0.24, 0.25, deck_size.z), Vector3(sx * hw, -0.2, 0), _mat.trim)
		_box_col(_deck, Vector3(0.08, 1.1, deck_size.z), Vector3(sx * (hw - 0.05), deck_size.y * 0.5 + 0.55, 0))
		_box(_deck, Vector3(0.06, 0.06, deck_size.z), Vector3(sx * (hw - 0.05), deck_size.y * 0.5 + 1.1, 0), _mat.steel)
		for sz in [-1.0, 1.0]:
			_box(_deck, Vector3(0.06, 1.1, 0.06), Vector3(sx * (hw - 0.05), deck_size.y * 0.5 + 0.55, sz * (hl - 0.05)), _mat.steel)
			_box(_deck, Vector3(0.16, 0.16, 0.16), Vector3(sx * (hw - 0.05), deck_size.y * 0.5 + 1.2, sz * (hl - 0.05)), _mat.amber)
	var sensor := Area3D.new()
	sensor.name = "DeckSensor"
	sensor.collision_layer = 0
	sensor.collision_mask = player_mask
	var scs := CollisionShape3D.new()
	var sbs := BoxShape3D.new()
	sbs.size = Vector3(deck_size.x - 0.4, 1.5, deck_size.z - 0.4)
	scs.shape = sbs
	scs.position = Vector3(0, deck_size.y * 0.5 + 0.75, 0)
	sensor.add_child(scs)
	sensor.body_entered.connect(_on_deck_sensor)
	_deck.add_child(sensor)
	# lock pins on both landings (slide +X into the deck side when locked)
	for zz in [-gap_m * 0.5 - 0.35, gap_m * 0.5 + 0.35]:
		var house := _box(self, Vector3(0.4, 0.85, 0.5), Vector3(pin_x, 0.425, zz), _mat.steel)
		house.name = "LockPinHousing"
		var pin := Node3D.new()
		pin.name = "MOV_LockPin"
		pin.set_meta("x0", pin_x + 0.3)
		pin.position = Vector3(pin_x + 0.3, 0.7 - deck_size.y * 0.5, zz)
		add_child(pin)
		_box(pin, Vector3(0.6, 0.18, 0.18), Vector3(0.3, 0, 0), _mat.trim)
		_pins.append(pin)
	# relay cabinet + lever pedestal + handle pivot (three detents)
	var cab := StaticBody3D.new()
	cab.name = "RelayCabinet"
	cab.collision_layer = 1
	cab.position = cabinet_offset
	add_child(cab)
	_box(cab, Vector3(0.6, 1.9, 1.2), Vector3(0, 0.95, 0), _mat.steel)
	_box_col(cab, Vector3(0.6, 1.9, 1.2), Vector3(0, 0.95, 0))
	_box(cab, Vector3(0.62, 0.08, 1.24), Vector3(0, 1.88, 0), _mat.trim)
	for i in 3:
		_lamps.append(_box(cab, Vector3(0.06, 0.12, 0.12), Vector3(-0.32, 1.65, -0.3 + 0.3 * i), _mat.lamp_off))
	var ped := StaticBody3D.new()
	ped.name = "LeverPedestal"
	ped.collision_layer = 1
	ped.position = lever_offset
	add_child(ped)
	_box(ped, Vector3(0.5, 1.0, 0.5), Vector3(0, 0.5, 0), _mat.steel)
	_box_col(ped, Vector3(0.5, 1.0, 0.5), Vector3(0, 0.5, 0))
	_lever_pivot = Node3D.new()
	_lever_pivot.name = "MOV_LeverHandle"
	_lever_pivot.position = Vector3(0, 1.0, 0)
	ped.add_child(_lever_pivot)
	_box(_lever_pivot, Vector3(0.07, 0.9, 0.07), Vector3(0, 0.45, 0), _mat.trim)
	_box(_lever_pivot, Vector3(0.16, 0.16, 0.16), Vector3(0, 0.92, 0), _mat.trim)
	# system shutter at the direct doorway (present only)
	_shutter = AnimatableBody3D.new()
	_shutter.name = "MOV_Shutter"
	_shutter.collision_layer = 0
	_shutter.collision_mask = 0
	_shutter.position = shutter_offset
	add_child(_shutter)
	_box_col(_shutter, Vector3(shutter_size.x, shutter_size.y, 0.2), Vector3(0, shutter_size.y * 0.5, 0))
	_box(_shutter, Vector3(shutter_size.x + 0.4, 0.4, 0.5), Vector3(0, shutter_size.y + 0.2, 0), _mat.steel)
	var n := 6
	for i in n:
		_slats.append(_box(_shutter, Vector3(shutter_size.x, shutter_size.y / float(n) - 0.03, 0.15), Vector3.ZERO, _mat.steel))
	for i in 6:
		_signal_lamps.append(_box(self, Vector3(0.12, 0.12, 0.12), Vector3(4.2, 2.6, shutter_offset.z - 3.0 - 2.5 * i), _mat.amber))
	# fall reset volume under the gap
	var fall := Area3D.new()
	fall.name = "AREA_FallReset"
	fall.collision_layer = 0
	fall.collision_mask = player_mask
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(rail_length_m + 4.0, 3.0, gap_m)
	fcs.shape = fbs
	fcs.position = Vector3((x0 + x1) * 0.5, -4.5, 0)
	fall.add_child(fcs)
	fall.body_entered.connect(fell_into_gap.emit)
	add_child(fall)
