extends Node
## Sole owner of puzzle state. State reads return deep copies.
signal state_changed(level_id: String, state: Dictionary)
signal level_completed(level_id: String)
signal feedback(result: Dictionary)
const VERSION := "1.0"
var _manifests: Dictionary = {}
var _states: Dictionary = {}
var _checkpoints: Dictionary = {}
var _notified: Dictionary = {}
var active_level := ""
var input_mode := "gameplay"
var _adapter: Node
var _ui_device := ""
var _last_frame := -1

func register_level(m: Dictionary) -> Dictionary:
	if m.get("contract_version") != VERSION: return result(false, "contract_mismatch")
	var id: String = m.get("level_id", "")
	if id not in ["mvp_bridge", "mvp_valve", "mvp_cabinet"]: return result(false, "unknown_level")
	var seen := {}
	for d in m.get("devices", []):
		if seen.has(d.device_id): return result(false, "duplicate_device")
		seen[d.device_id] = true
	if _manifests.has(id): return result(false, "duplicate_level")
	_manifests[id] = m.duplicate(true)
	_states[id] = m.initial_state.duplicate(true)
	_notified[id] = false
	return result(true)

func activate(id: String, adapter: Node) -> Dictionary:
	if not _states.has(id): return result(false, "unknown_level")
	if is_instance_valid(_adapter): _adapter.cancel_transients()
	active_level = id
	_adapter = adapter
	_ui_device = ""
	_last_frame = -1
	_restore_mode()
	_publish()
	_adapter.reset_player(_states[id].checkpoint_id if _checkpoints.has(id) else null)
	return result(true)

func snapshot(id: String = "") -> Dictionary:
	return _states.get(active_level if id.is_empty() else id, {}).duplicate(true)

func manifest() -> Dictionary:
	return _manifests[active_level].duplicate(true)

func is_complete(id: String = "") -> bool:
	if id.is_empty(): id = active_level
	for key in _manifests[id].completion.required_flags:
		if _states[id].flags.get(key) != _manifests[id].completion.required_flags[key]: return false
	return true

func world_enabled() -> bool: return input_mode in ["gameplay", "completed"]
func result(accepted: bool, reason = null) -> Dictionary: return {"accepted": accepted, "reason": reason}

func _device(id: String) -> Dictionary:
	for d in _manifests[active_level].devices:
		if d.device_id == id: return d
	return {}

func _device_check(id: String) -> Dictionary:
	var d := _device(id)
	if d.is_empty(): return result(false, "unknown_device")
	if _states[active_level].era not in d.available_eras: return result(false, "wrong_era")
	return result(true)

func open_puzzle_ui(id: String) -> Dictionary:
	var checked := _device_check(id)
	if not checked.accepted: return checked
	if not world_enabled(): return result(false, "input_blocked")
	if id != "cabinet": return result(false, "unknown_action")
	if not _adapter.in_range(id): return result(false, "out_of_range")
	_ui_device = id
	input_mode = "puzzle_ui"
	return result(true)

func cancel_puzzle_ui() -> void:
	_ui_device = ""
	_restore_mode()
	_adapter.cancel_transients()

func request(event: Dictionary) -> Dictionary:
	var outcome := _request(event)
	feedback.emit(outcome)
	return outcome

func _request(event: Dictionary) -> Dictionary:
	if event.get("event_type") == "level.completed": return result(false, "output_only_event")
	if event.get("level_id", "") != active_level: return result(false, "inactive_level")
	var kind: String = event.get("event_type", "")
	if kind == "reset.request": return _reset(event.get("reset_mode", ""))
	var st: Dictionary = _states[active_level]
	if kind == "checkpoint.reached":
		var cp: String = event.get("device_id", "")
		if not _adapter.valid_checkpoint(cp): return result(false, "unknown_device")
		if not world_enabled(): return result(false, "input_blocked")
		if not _adapter.checkpoint_in_range(cp): return result(false, "out_of_range")
		st.checkpoint_id = cp
		_checkpoints[active_level] = st.duplicate(true)
		_publish()
		return result(true)
	if kind == "era.switch.request":
		var target: String = event.get("target_era", "")
		if target not in ["present", "past"]: return result(false, "invalid_era")
		if not world_enabled(): return result(false, "input_blocked")
		if target == st.era: return result(true)
		if _last_frame == Engine.get_physics_frames(): return result(false, "input_blocked")
		if not _adapter.switch_safety(target): return result(false, "unsafe_switch")
		_last_frame = Engine.get_physics_frames()
		input_mode = "switching"
		st.era = target
		if active_level == "mvp_bridge" and target == "present" and st.flags.bridge_crossed_past and _adapter.at_far_landing():
			st.flags.bridge_returned_present = true
		_publish()
		_restore_mode()
		return result(true)
	if kind != "interact.request": return result(false, "unknown_event")
	var id: String = event.get("device_id", "")
	var checked := _device_check(id)
	if not checked.accepted: return checked
	var action: String = event.get("action", "")
	var code_submit := id == "cabinet" and action == "submit_code"
	if code_submit:
		if input_mode != "puzzle_ui" or _ui_device != id: return result(false, "input_blocked")
	elif not world_enabled(): return result(false, "input_blocked")
	if _last_frame == Engine.get_physics_frames(): return result(false, "input_blocked")
	if not _adapter.in_range(id):
		if code_submit: cancel_puzzle_ui()
		return result(false, "out_of_range")
	if action not in _device(id).actions: return result(false, "unknown_action")
	var flags: Dictionary = st.flags
	match active_level + "/" + id + "/" + action:
		"mvp_bridge/far_landing/enter": flags.bridge_crossed_past = true
		"mvp_bridge/exit_trigger/enter":
			if not flags.bridge_crossed_past: return result(false, "prerequisites_unmet")
			flags.exit_reached = true
		"mvp_valve/valve/close": flags.valve_closed_past = true
		"mvp_valve/exit_trigger/enter":
			if not flags.valve_closed_past: return result(false, "prerequisites_unmet")
			flags.exit_reached = true
		"mvp_cabinet/plaque/read": flags.clue_seen = true
		"mvp_cabinet/cabinet/submit_code":
			var config: Dictionary = _device(id).get("config", {})
			var expected = config.get("test_code") if config.get("test_mode", false) else config.get("final_code")
			cancel_puzzle_ui()
			if not expected is String or expected.is_empty(): return result(false, "config_missing")
			var submitted = event.get("value")
			if not submitted is String or submitted.is_empty() or submitted != expected: return result(false, "wrong_code")
			flags.cabinet_unlocked = true
		"mvp_cabinet/start_button/press":
			if not flags.cabinet_unlocked: return result(false, "prerequisites_unmet")
			flags.power_on = true
		"mvp_cabinet/exit_trigger/enter":
			if not flags.power_on: return result(false, "prerequisites_unmet")
			flags.exit_reached = true
		_:
			if action != "inspect": return result(false, "unknown_action")
	_last_frame = Engine.get_physics_frames()
	_publish()
	if is_complete() and not _notified[active_level]:
		_notified[active_level] = true
		input_mode = "completed"
		level_completed.emit(active_level)
	return result(true)

func _reset(mode: String) -> Dictionary:
	if mode not in ["checkpoint", "restart_level"]: return result(false, "invalid_reset_mode")
	input_mode = "resetting"
	_ui_device = ""
	_adapter.cancel_transients()
	if mode == "restart_level": _checkpoints.erase(active_level)
	_states[active_level] = _checkpoints.get(active_level, _manifests[active_level].initial_state).duplicate(true)
	_last_frame = -1
	_notified[active_level] = is_complete()
	_publish()
	_adapter.reset_player(_states[active_level].checkpoint_id)
	_restore_mode()
	return result(true)

func _restore_mode() -> void:
	input_mode = "completed" if not active_level.is_empty() and is_complete() else "gameplay"

func _publish() -> void:
	_adapter.rebuild(snapshot())
	state_changed.emit(active_level, snapshot())
