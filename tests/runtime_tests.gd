extends Node
## Real Godot tests. Semantic cases teleport fixtures; routes use Input + move_and_slide.
var lab
var rows: Array = []
var failed := 0

func check(id: String, passed: bool, detail: String, tier: String = "engine_semantics") -> void:
	rows.append({"test_id":id,"passed":passed,"tier":tier,"detail":detail})
	if not passed: failed += 1
	print(("PASS " if passed else "FAIL ") + id + " | " + detail)

func frames(count: int = 3) -> void:
	for i in count: await get_tree().physics_frame

func place(p: Vector3) -> void:
	lab.player.position = p
	lab.player.velocity = Vector3.ZERO
	await frames(5)

func switch_to(era: String) -> Dictionary:
	await frames()
	return lab.send("era.switch.request",{"target_era":era})

func action(id: String, verb: String, value = null) -> Dictionary:
	await frames()
	return lab.interact(id,verb,value)

func reset() -> void:
	lab.send("reset.request",{"reset_mode":"restart_level"})
	await frames(5)

func walk_to(z: float, limit: int = 600) -> bool:
	Input.action_press("move_forward")
	var reached := false
	for i in limit:
		await frames(1)
		if lab.player.position.z <= z:
			reached = true
			break
	Input.action_release("move_forward")
	await frames(3)
	return reached

func key(action_name: String) -> void:
	Input.action_press(action_name)
	await frames(2)
	Input.action_release(action_name)
	await frames(3)

func run(target) -> void:
	lab = target
	await frames(10)
	lab.auto_triggers = false
	lab.select_level(1)
	await frames(8)
	check("startup_floor",lab.player.is_on_floor(),"Candidate main scene loaded; 1.8 m capsule grounded","engine_physics")
	var copy = lab.service.snapshot()
	copy.flags.valve_closed_past = true
	check("snapshot_isolation",not lab.service.snapshot().flags.valve_closed_past,"Public snapshot mutation cannot write authority")
	var dup = lab.service.manifest()
	dup.devices.append(dup.devices[0].duplicate(true))
	var fresh = preload("res://core/state_service.gd").new()
	add_child(fresh)
	check("duplicate_device",fresh.register_level(dup).reason == "duplicate_device","Duplicate IDs refused before registration")
	fresh.queue_free()
	var r = lab.send("level.completed")
	check("output_only",r.reason == "output_only_event","No player-forged completion")
	r = await action("missing","close")
	check("unknown_device",r.reason == "unknown_device","Unknown stable ID refused")
	r = await action("valve","close")
	check("era_before_range",r.reason == "wrong_era","present valve unavailable even when out of range")
	r = await switch_to("past")
	check("safe_switch",r.accepted and lab.service.snapshot().era == "past","Ground/capsule queries accept safe platform","engine_physics")
	r = await action("valve","close")
	check("range_enforced",r.reason == "out_of_range","Spawn > 2.5 m from device","engine_physics")
	await place(Vector3(0,0.04,0.8))
	r = await action("valve","close")
	check("valve_close",r.accepted and lab.service.snapshot().flags.valve_closed_past,"Real in-range past close changes flag")
	r = lab.interact("valve","close")
	check("same_frame_debounce",r.reason == "input_blocked","Second accepted-world-operation attempt in same physics frame refused")
	r = await action("valve","close")
	check("idempotent_close",r.accepted and lab.service.snapshot().flags.valve_closed_past,"Later repeated close never toggles open")
	r = await switch_to("present")
	check("valve_persists",r.accepted and not lab.hazard_active and lab.gate.position.z == -5.0,"present rebuild removes steam and closes SIDE isolation leaf")
	await place(Vector3(0,0.04,1))
	r = lab.send("checkpoint.reached",{"device_id":"Anchors/Checkpoint"})
	var saved = lab.service.snapshot()
	await switch_to("past")
	lab.send("reset.request",{"reset_mode":"checkpoint"})
	await frames(4)
	check("checkpoint_snapshot",lab.service.snapshot() == saved and lab.player.position.distance_to(Vector3(0,0,1)) < 0.2,"Restores complete era/flags snapshot plus actual checkpoint position")
	lab.select_level(0)
	await frames(8)
	await reset()
	await switch_to("past")
	await place(Vector3(0,0.04,-8))
	var before = lab.service.snapshot()
	var before_pos = lab.player.position
	r = await switch_to("present")
	check("no_target_ground",r.reason == "unsafe_switch" and lab.service.snapshot() == before and lab.player.position.distance_to(before_pos) < 0.1,"Bridge center: no target ground; no teleport or flag change","engine_physics")
	await place(Vector3(0,4,-8))
	r = await switch_to("present")
	check("airborne_rejected",r.reason == "unsafe_switch","Airborne player cannot switch","engine_physics")
	await reset()
	lab.select_level(1)
	await frames(8)
	check("level_state_retention",lab.service.snapshot() == saved,"Switching active scene retains other level runtime state")
	await reset()
	check("restart_clears",not lab.service.snapshot().flags.valve_closed_past and lab.service.snapshot().checkpoint_id == null and lab.hazard_active,"Restart resets flag, era, checkpoint and derived hazard")
	lab.select_level(2)
	await frames(8)
	await place(Vector3(0,0.04,0.7))
	check("open_ui",lab.service.open_puzzle_ui("cabinet").accepted,"Present and true device range required")
	var ui_pos = lab.player.position
	Input.action_press("move_forward")
	await frames(20)
	Input.action_release("move_forward")
	r = await switch_to("past")
	check("ui_blocks_world",r.reason == "input_blocked" and lab.player.position.distance_to(ui_pos) < 0.001,"Movement and era switch blocked while UI owns input","engine_physics")
	r = await action("cabinet","submit_code","")
	check("empty_code",r.reason == "wrong_code" and lab.service.world_enabled(),"Empty input not accepted; world control restored")
	lab.service.open_puzzle_ui("cabinet")
	r = await action("cabinet","submit_code","bad")
	check("wrong_code",r.reason == "wrong_code" and lab.service.input_mode == "gameplay","Wrong code retry has no soft lock")
	lab.service.open_puzzle_ui("cabinet")
	r = await action("cabinet","submit_code","0427")
	check("known_code_without_clue",r.accepted and lab.service.snapshot().flags.cabinet_unlocked and not lab.service.snapshot().flags.clue_seen,"Explicit fixture code unlocks without artificial clue_seen prerequisite")
	lab.service.open_puzzle_ui("cabinet")
	r = await action("cabinet","submit_code","bad")
	check("wrong_after_unlock",r.reason == "wrong_code" and lab.service.snapshot().flags.cabinet_unlocked,"Wrong later attempt does not relock")
	lab.service.open_puzzle_ui("cabinet")
	lab.send("reset.request",{"reset_mode":"checkpoint"})
	check("reset_cancels_ui",lab.service.world_enabled() and not lab.code_panel.visible and not lab.service.snapshot().flags.cabinet_unlocked,"No checkpoint: initial state+spawn; resets UI lock")
	await place(Vector3(0,0.04,-2))
	r = await action("start_button","press")
	check("button_prerequisite",r.reason == "prerequisites_unmet","No start before unlock")
	await switch_to("past")
	lab._box("TargetOnlyBlocker",Vector3(1.8,0.9,3),Vector3(1,1.8,1),Color.RED,"present")
	lab.rebuild(lab.service.snapshot())
	await place(Vector3(1.8,0.04,3))
	r = await switch_to("present")
	check("capsule_wall_rejected",r.reason == "unsafe_switch","Standing on safe past ground, target-era obstacle occupies full player capsule","engine_physics")
	# Isolated production config test with authoritative core + spatial adapter.
	var prod = preload("res://core/state_service.gd").new()
	add_child(prod)
	var prod_manifest = JSON.parse_string(FileAccess.get_file_as_string("res://inputs/cabinet.manifest.functional.json"))
	prod.register_level(prod_manifest)
	prod.activate("mvp_cabinet",lab)
	await place(Vector3(0,0.04,0.7))
	prod.open_puzzle_ui("cabinet")
	var ev = {"event_type":"interact.request","level_id":"mvp_cabinet","device_id":"cabinet","action":"submit_code","value":"0427"}
	r = prod.request(ev)
	check("production_code_missing",r.reason == "config_missing" and not prod.snapshot().flags.cabinet_unlocked,"test_mode=false plus final_code=null cannot accept fixture code")
	prod.queue_free()
	await reset()
	await place(Vector3(0,0.04,-15))
	r = await action("exit_trigger","enter")
	check("unsolved_exit",r.reason == "prerequisites_unmet" and not lab.service.is_complete(),"Actual exit range cannot bypass unsolved cabinet; no direct completion")
	await switch_to("past")
	r = await action("exit_trigger","enter")
	check("exit_wrong_era_priority",r.reason == "wrong_era","Past present-only exit reports era before prerequisites")
	await reset()
	await place(Vector3(0,0.04,0.7))
	lab.interact_nearest()
	r = await action("start_button","press")
	check("ui_blocks_interact",r.reason == "input_blocked","UI blocks world interaction before range/prerequisites")
	var escape = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await frames(3)
	check("escape_ui_focus",lab.service.world_enabled() and not lab.code_panel.visible,"Real Escape event cancels focused LineEdit via _input")
	await reset()
	await _physical_routes()
	if "--capture" in OS.get_cmdline_user_args():
		lab.select_level(1)
		await frames(10)
		await reset()
		await key("switch_era")
		await walk_to(0.8)
		await key("interact")
		await key("switch_era")
		lab.player.camera.rotation.x = -0.08
		lab.notice.text = "ACTUAL GODOT STANDALONE FRAME | automated WASD/Q/E route | valve closed, present route safe"
		await RenderingServer.frame_post_draw
		var image = get_viewport().get_texture().get_image()
		var error = image.save_png("res://evidence/standalone_valve.png")
		check("rendered_capture",error == OK,"Actual non-headless Godot viewport after automated player input","engine_render")
	await _era_lighting_profiles()
	var report = {"engine":Engine.get_version_info().string,"entry":"res://scenes/integration_lab.tscn","scope":"primitive independent candidate","human_manual_play":"not_run","exported_build":"not_run","source_asset_import":"not_run","passed":rows.size()-failed,"failed":failed,"results":rows}
	var output = "res://evidence/runtime-render-results.json" if "--capture" in OS.get_cmdline_user_args() else "res://evidence/runtime-results.json"
	var file = FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("MVP_TEST_SUMMARY " + str(rows.size()-failed) + "/" + str(rows.size()) + " passed")
	get_tree().quit(0 if failed == 0 else 1)

func _physical_routes() -> void:
	lab.auto_triggers = true
	# Both bridge runs use production player input and real triggers, no teleport.
	for attempt in range(2):
		lab.select_level(0)
		await frames(8)
		await reset()
		var count = lab.completions.mvp_bridge
		await key("switch_era")
		var crossed = await walk_to(-16.0)
		await key("switch_era")
		var exited = await walk_to(-20.0)
		check("bridge_route_"+str(attempt+1),crossed and exited and lab.service.is_complete() and lab.service.snapshot().flags.bridge_returned_present and lab.completions.mvp_bridge == count+1,"W/Q/W through continuous past bridge, real far trigger, present exit; start to finish","engine_player_route")
		await frames(15)
		check("bridge_completion_once_"+str(attempt+1),lab.completions.mvp_bridge == count+1,"Remaining in exit does not repeat completion")
		var pos = lab.player.position
		await key("switch_era")
		Input.action_press("move_back")
		await frames(10)
		Input.action_release("move_back")
		check("completed_free_"+str(attempt+1),lab.player.position.z > pos.z+0.1 and lab.service.snapshot().era == "past","completed allows movement and safe switch","engine_player_route")
	lab.select_level(0)
	await frames(8)
	await reset()
	await walk_to(-3.8)
	var reset_before = lab.reset_count
	Input.action_press("move_forward")
	await key("jump")
	for i in 240:
		await frames(1)
		if lab.reset_count > reset_before: break
	Input.action_release("move_forward")
	check("present_gap_fall",lab.reset_count > reset_before and not lab.service.snapshot().flags.bridge_crossed_past and lab.player.position.z > -2,"Present gap cannot be jumped with this player; actual fall restores checkpoint","engine_player_route")
	lab.select_level(1)
	await frames(8)
	await reset()
	var steam_reset = lab.reset_count
	Input.action_press("move_forward")
	for i in 300:
		await frames(1)
		if lab.reset_count > steam_reset: break
	Input.action_release("move_forward")
	await frames(4)
	check("steam_failure_recovery",lab.reset_count > steam_reset and lab.hazard_active and not lab.service.snapshot().flags.valve_closed_past and lab.player.position.z > 0,"Walking unsolved present steam triggers the shared checkpoint reset; hazard/state rebuilt","engine_player_route")
	for attempt in range(2):
		lab.select_level(1)
		await frames(8)
		await reset()
		await key("switch_era")
		await walk_to(0.8)
		await key("interact")
		await key("switch_era")
		var count = lab.completions.mvp_valve
		var exited = await walk_to(-15)
		check("valve_route_"+str(attempt+1),exited and lab.service.is_complete() and lab.completions.mvp_valve == count+1,"Spawn/Q/W/E/Q/W: past valve, present physical route, real exit trigger","engine_player_route")
	lab.select_level(2)
	await frames(8)
	await reset()
	await key("switch_era")
	await walk_to(0.8)
	await key("interact")
	await key("switch_era")
	await key("interact")
	# Submit UI via its real LineEdit signal; no direct flag injection.
	lab.code_input.text = "0427"
	lab.code_input.text_submitted.emit(lab.code_input.text)
	await frames(5)
	await walk_to(-1.9)
	await key("interact")
	var exited = await walk_to(-15)
	check("cabinet_route",exited and lab.service.is_complete() and lab.service.snapshot().flags.clue_seen,"Spawn to clue, real UI submit signal, button and open-door collision route","engine_player_route")
	check("cabinet_lights_collision",lab.door.position.y > 4 and lab.lights[0].light_energy > 0,"Present flag projects into both door body+mesh transform and working lights","engine_physics")

func _era_lighting_profiles() -> void:
	# era_lighting v002 (视效): the "city" profile works on a copy of the preset environment and restores the island
	# values when switched back; the preset resources themselves never change
	var el = load("res://era_lighting/era_lighting.tscn").instantiate()
	add_child(el)
	await frames(2)
	var past: EraPreset = el.preset("past")
	var island_fog: float = past.environment.fog_density
	var we: WorldEnvironment = el.get_node("WorldEnvironment")
	var sun: DirectionalLight3D = el.get_node("Sun")
	el.profile = "city"
	await frames(1)
	check("era_city_fog", we.environment != past.environment and is_equal_approx(we.environment.fog_density, island_fog * past.city_fog_density_scale) and is_equal_approx(past.environment.fog_density, island_fog), "City profile scales the fog on a copy (%.5f -> %.5f); preset untouched" % [island_fog, we.environment.fog_density])
	check("era_city_shadow", is_equal_approx(sun.directional_shadow_max_distance, past.city_shadow_max_distance), "City profile sun shadows reach %.0f m" % sun.directional_shadow_max_distance)
	check("era_city_no_volumetric", not we.environment.volumetric_fog_enabled, "City profile keeps volumetric fog off")
	el.set_era("present")
	await frames(1)
	var present: EraPreset = el.preset("present")
	check("era_city_switch", is_equal_approx(we.environment.fog_density, present.environment.fog_density * present.city_fog_density_scale), "Era switch inside the city profile uses the present preset")
	el.profile = "island"
	await frames(1)
	check("era_island_restored", we.environment == present.environment and is_equal_approx(sun.directional_shadow_max_distance, present.shadow_max_distance), "Back to the island profile: preset environment and shadow distance again")
	el.queue_free()
	await frames(1)
