extends SceneTree
## UI 自测（无界面）：
##   Godot --headless --path . --script res://ui/tests/ui_tests.gd
## 只测 ui/ 下的子场景，以及它们跟真实 core/state_service.gd 的信号对不对得上；
## 接进主场景后的整关测试仍由 tests/runtime_tests.gd 负责。

const HudScene := preload("res://ui/hud.tscn")
const PromptScene := preload("res://ui/interaction_prompt.tscn")
const PanelScene := preload("res://ui/cabinet_panel.tscn")
const ResidualScene := preload("res://ui/residual_screen.tscn")
const StateService := preload("res://core/state_service.gd")
const Theme_ := preload("res://ui/theme.tres")


## 公共程序要的 adapter 方法，全部放行，只记调用。
class StubAdapter extends Node:
	var cancelled := 0
	func in_range(_id: String) -> bool: return true
	func switch_safety(_era: String) -> bool: return true
	func at_far_landing() -> bool: return false
	func valid_checkpoint(_id: String) -> bool: return true
	func checkpoint_in_range(_id: String) -> bool: return true
	func rebuild(_state: Dictionary) -> void: pass
	func reset_player(_cp) -> void: pass
	func cancel_transients() -> void: cancelled += 1


var results: Array = []
var failed := 0


func _initialize() -> void:
	_run.call_deferred()


func check(id: String, ok: bool, note := "") -> void:
	results.append({"id": id, "ok": ok, "note": note})
	if not ok:
		failed += 1
	print(("PASS  " if ok else "FAIL  ") + id + ("" if ok else "  | " + note))


func frames(n := 2) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _run() -> void:
	await frames()
	_test_theme()
	await _test_prompt()
	await _test_hud_direct()
	await _test_hud_with_service()
	await _test_cabinet()
	await _test_residual()
	print("UI tests: %d/%d passed" % [results.size() - failed, results.size()])
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-results="):
			var f := FileAccess.open(arg.trim_prefix("--ui-results="), FileAccess.WRITE)
			f.store_string(JSON.stringify({"engine": Engine.get_version_info().string, "passed": results.size() - failed, "total": results.size(), "results": results}, "  "))
			f.close()
	quit(1 if failed else 0)


func _test_theme() -> void:
	var sb: StyleBox = Theme_.get_stylebox("panel", "PanelContainer")
	check("theme_notch_stylebox", sb != null and sb.get_script() != null and sb.get("notch") == 6, str(sb))
	check("theme_paper_plate", Theme_.get_stylebox("panel", "PlatePaper").get("notch") == 10)
	check("theme_type_variations", Theme_.get_type_variation_base("PanelTitle") == &"Label" and Theme_.get_type_variation_base("PaperKey") == &"Button")
	var font: Font = Theme_.get_font("font", "PanelTitle")
	check("theme_fonts", font != null and Theme_.default_font != null and Theme_.default_font_size == 18)
	check("theme_sizes_follow_spec", Theme_.get_font_size("font_size", "PromptLabel") == 20 and Theme_.get_font_size("font_size", "ObjectiveTitle") == 30 and Theme_.get_font_size("font_size", "PanelTitle") == 40 and Theme_.get_font_size("font_size", "ResidualDigits") == 120)


func _test_prompt() -> void:
	var prompt: PanelContainer = PromptScene.instantiate()
	root.add_child(prompt)
	await frames()
	check("prompt_hidden_at_start", not prompt.visible)
	prompt.show_device("valve", "close")
	await frames()
	check("prompt_device_text", prompt.visible and prompt.get_node("%Verb").text == "关闭" and prompt.get_node("%Target").text == "蒸汽阀门" and prompt.get_node("%KeyCap").visible)
	prompt.show_device("plaque", "read", "需在过去操作")
	await frames()
	check("prompt_blocked", prompt.get_node("%BlockedIcon").visible and not prompt.get_node("%KeyCap").visible and prompt.get_node("%Reason").text.contains("需在过去操作"))
	var sig: String = prompt.signature
	prompt.show_device("plaque", "read", "需在过去操作")
	check("prompt_same_content_no_restart", prompt.signature == sig)
	prompt.hide_prompt()
	check("prompt_hide", not prompt.visible)
	prompt.queue_free()


func _test_hud_direct() -> void:
	var hud: CanvasLayer = HudScene.instantiate()
	root.add_child(hud)
	await frames()
	check("hud_default_present", hud.get_node("%EraName").text == "现在" and hud.get_node("%EraHint").text == "戴上眼镜")
	hud.set_era("past", false)
	check("hud_era_past", hud.get_node("%EraName").text == "过去" and hud.get_node("%EraAlias").text == "β" and hud.get_node("%EraHint").text == "摘下眼镜")
	hud.set_era("present", true)
	check("hud_era_switching_label", hud.get_node("%EraName").text == "切换中")
	await create_timer(0.6).timeout
	check("hud_era_switch_settles", hud.get_node("%EraName").text == "现在" and hud.get_node("%SwitchFx").progress >= 1.0)
	hud.set_level("mvp_cabinet", {"clue_seen": false})
	check("hud_objective_first_step", hud.get_node("%ObjectiveTitle").text == "配电小院" and hud.get_node("%Step").text == "在过去调查铭牌" and hud.get_node("%Counter").text == "1 / 4")
	hud.set_level("mvp_cabinet", {"clue_seen": true, "cabinet_unlocked": true})
	check("hud_objective_progress", hud.get_node("%Counter").text == "3 / 4" and hud.get_node("%Step").text.contains("启动按钮"))
	hud.show_status("success", "测试一", "说明")
	hud.show_status("error", "测试二")
	hud.show_status("info", "测试三")
	hud.show_status("warn", "测试四")
	check("hud_toast_cap", hud.status_titles().size() == 3 and not hud.status_titles().has("测试一"), str(hud.status_titles()))
	hud.show_interaction("cabinet", "submit_code")
	await frames()
	check("hud_prompt_via_hud", hud.prompt.visible and hud.prompt.get_node("%Verb").text == "打开")
	hud.set_suppressed("dialogue", true)
	check("hud_suppress_hides_world_hud", not hud.get_node("%Objective").visible and not hud.get_node("%Crosshair").visible and not hud.prompt.visible)
	hud.set_suppressed("dialogue", false)
	check("hud_suppress_restores", hud.get_node("%Objective").visible and hud.get_node("%Crosshair").visible)
	hud.show_era_blocked("无法切换时代", 0.2)
	check("hud_era_blocked_shown", hud.get_node("%EraBlockedRow").visible and not hud.get_node("%EraHintRow").visible)
	await create_timer(0.4).timeout
	check("hud_era_blocked_clears", not hud.get_node("%EraBlockedRow").visible and hud.get_node("%EraHintRow").visible)
	hud.queue_free()


func _test_hud_with_service() -> void:
	var service: Node = StateService.new()
	root.add_child(service)
	var adapter := StubAdapter.new()
	root.add_child(adapter)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://contracts/mvp_cabinet.json"))
	check("service_register", service.register_level(manifest).accepted)
	var hud: CanvasLayer = HudScene.instantiate()
	root.add_child(hud)
	await frames()
	service.activate("mvp_cabinet", adapter)
	hud.bind_service(service)
	await frames()
	check("bind_level_objective", hud.level_id == "mvp_cabinet" and hud.get_node("%Counter").text == "1 / 4")
	service.request({"event_type": "era.switch.request", "level_id": "mvp_cabinet", "target_era": "past"})
	await frames()
	check("bind_era_follows_service", hud.era == "past")
	service.request({"event_type": "interact.request", "level_id": "mvp_cabinet", "device_id": "plaque", "action": "read"})
	await frames()
	check("bind_flag_toast_clue", hud.status_titles().has("获得线索") and hud.get_node("%Counter").text == "2 / 4", str(hud.status_titles()))
	service.request({"event_type": "interact.request", "level_id": "mvp_cabinet", "device_id": "start_button", "action": "press"})
	await frames()
	check("bind_reason_wrong_era", hud.status_titles().has("当前时代无法操作"), str(hud.status_titles()))
	service.request({"event_type": "era.switch.request", "level_id": "mvp_cabinet", "target_era": "present"})
	await frames()
	check("bind_open_ui_suppresses", service.open_puzzle_ui("cabinet").accepted)
	await frames()
	check("bind_puzzle_ui_hides_world_hud", hud.is_suppressed() and not hud.get_node("%Objective").visible)
	service.request({"event_type": "interact.request", "level_id": "mvp_cabinet", "device_id": "cabinet", "action": "submit_code", "value": "1111"})
	await frames()
	check("bind_wrong_code_toast", hud.status_titles().has("密码错误") and not hud.is_suppressed(), str(hud.status_titles()))
	service.open_puzzle_ui("cabinet")
	await frames()
	service.request({"event_type": "interact.request", "level_id": "mvp_cabinet", "device_id": "cabinet", "action": "submit_code", "value": "0427"})
	await frames()
	check("bind_code_ok_toast", hud.status_titles().has("密码正确") and hud.get_node("%Counter").text == "3 / 4", str(hud.status_titles()))
	service.request({"event_type": "interact.request", "level_id": "mvp_cabinet", "device_id": "start_button", "action": "press"})
	await frames()
	service.request({"event_type": "interact.request", "level_id": "mvp_cabinet", "device_id": "exit_trigger", "action": "enter"})
	await frames()
	check("bind_completed", hud.status_titles().has("通路已恢复") and hud.get_node("%ObjectiveDone").visible, str(hud.status_titles()))
	service.request({"event_type": "reset.request", "level_id": "mvp_cabinet", "reset_mode": "restart_level"})
	await frames()
	check("bind_restart_resets_objective", hud.get_node("%Counter").text == "1 / 4" and not hud.get_node("%ObjectiveDone").visible and hud.era == "present")
	hud.queue_free()
	service.queue_free()
	adapter.queue_free()


func _test_cabinet() -> void:
	var panel: CanvasLayer = PanelScene.instantiate()
	root.add_child(panel)
	await frames()
	var got := []
	var cancels := [0]
	panel.submitted.connect(func(code): got.append(code))
	panel.cancelled.connect(func(): cancels[0] += 1)
	check("panel_hidden_at_start", not panel.visible)
	panel.open()
	await frames()
	check("panel_open_focus", panel.visible and panel.line_edit.has_focus())
	panel.line_edit.text = "04a2x79"
	panel.line_edit.text_changed.emit(panel.line_edit.text)
	check("panel_digits_only_and_length", panel.line_edit.text == "0427", panel.line_edit.text)
	panel.line_edit.text_submitted.emit(panel.line_edit.text)
	check("panel_submit_signal", got == ["0427"], str(got))
	panel.clear()
	panel.press_digit("0")
	panel.press_digit("4")
	panel.confirm()
	check("panel_short_code_not_submitted", got.size() == 1 and panel.get_node("%NoteTitle").text == "密码位数不足")
	panel.backspace()
	check("panel_backspace", panel.line_edit.text == "0")
	for d in ["4", "2", "7"]:
		panel.press_digit(d)
	panel.confirm()
	check("panel_keypad_submit", got.size() == 2 and got[1] == "0427", str(got))
	panel.get_node("%CancelButton").pressed.emit()
	check("panel_cancel_signal", cancels[0] == 1)
	panel.close()
	check("panel_close_clears", not panel.visible and panel.line_edit.text == "")
	panel.queue_free()


func _test_residual() -> void:
	var screen: CanvasLayer = ResidualScene.instantiate()
	root.add_child(screen)
	await frames()
	var done := [false]
	screen.finished.connect(func(): done[0] = true)
	screen.hold_seconds = 0.2
	screen.jitter_steps = 3
	screen.play(0.000021, 0.000024)
	await create_timer(0.25).timeout
	check("residual_visible_while_playing", screen.visible and screen.playing)
	var waited := 0.0
	while not done[0] and waited < 6.0:
		await create_timer(0.1).timeout
		waited += 0.1
	check("residual_finished", done[0] and not screen.visible, "waited %.1f s" % waited)
	check("residual_final_text", screen.get_node("%Value").text == "0.000024", screen.get_node("%Value").text)
	screen.reduced_motion = true
	done[0] = false
	screen.play(0.000021, 0.000024)
	waited = 0.0
	while not done[0] and waited < 3.0:
		await create_timer(0.1).timeout
		waited += 0.1
	check("residual_reduced_motion", done[0] and waited < 1.5, "waited %.1f s" % waited)
	screen.queue_free()
