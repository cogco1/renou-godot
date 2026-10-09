extends SceneTree
## Headless acceptance tests for BigSlidingGate and TransferPlatform (behaviour spec v001).
## Godot_v4.7.2-stable_win64_console.exe --headless --path <repo> --script res://mechanisms/steamhall/tests/test_steamhall_mechanisms.gd
## Exit code 0 = all pass. Runs at Engine.time_scale = 10 so the 6 s / 5.8 s / 3 s transients finish quickly.

var fails := 0
var passes := 0
var events: Array[String] = []


func _initialize() -> void:
	Engine.time_scale = 10.0
	_run.call_deferred()


func check(name: String, ok: bool, detail := "") -> void:
	if ok:
		passes += 1
		print("PASS ", name)
	else:
		fails += 1
		print("FAIL ", name, "  ", detail)


func wait_game(seconds: float) -> void:
	# Physics-process timer: ticks in step with the TWEEN_PROCESS_PHYSICS transients, so a busy
	# machine (capped physics steps per frame) can't let the timer run ahead of the tweens.
	await create_timer(seconds, true, true).timeout


func _run() -> void:
	await _test_gate()
	await _test_platform()
	await _test_skins()
	await _test_demo_loads()
	print("TOTAL pass=%d fail=%d" % [passes, fails])
	quit(1 if fails > 0 else 0)


func _test_gate() -> void:
	var g := BigSlidingGate.new()
	root.add_child(g)
	await process_frame
	g.gate_motion_finished.connect(func(c: bool) -> void: events.append("gate_finished_%s" % c))
	# 1 present, open: stacked, hazard on
	g.apply_state(false, "present")
	var stacked := true
	for i in g.leaf_count:
		stacked = stacked and is_equal_approx(g.leaf_x(i), 0.0)
	check("gate present open: all leaves stacked", stacked)
	check("gate present open: hazard active", g.hazard_active and g.get_node("AREA_SteamCorridor").monitoring)
	var acs: CollisionShape3D = g.get_node("AREA_SteamCorridor").get_child(0)
	var half: Vector3 = (acs.shape as BoxShape3D).size * 0.5
	check("gate steam area spans pier face -> far wall (local z 0..depth)",
			is_equal_approx(acs.position.z - half.z, 0.0) and is_equal_approx(acs.position.z + half.z, g.steam_depth_m),
			str(acs.position.z - half.z) + ".." + str(acs.position.z + half.z))
	# 2 closed: leaves tile 40 m
	g.apply_state(true, "present")
	check("gate closed: last leaf at 32 m", is_equal_approx(g.leaf_x(4), 32.0), str(g.leaf_x(4)))
	check("gate closed: hazard off", not g.hazard_active and not g.get_node("AREA_SteamCorridor").monitoring)
	# past open: no hazard
	g.apply_state(false, "past")
	check("gate past open: no hazard", not g.hazard_active)
	# play_close: 6 s transient reaches closed and signals once
	g.apply_state(true, "past")
	g.play_close()
	check("gate play_close starts from open", g.progress() < 0.05)
	await wait_game(6.6)
	check("gate play_close reaches closed", is_equal_approx(g.progress(), 1.0), str(g.progress()))
	check("gate finished signal", events.count("gate_finished_true") == 1, str(events))
	# cancel mid-way jumps to terminal (closed)
	g.play_close()
	await wait_game(1.0)
	g.cancel_transients()
	check("gate cancel_transients -> terminal closed", is_equal_approx(g.progress(), 1.0))
	# era toggling never reopens
	for k in 5:
		g.apply_state(true, "present" if k % 2 == 0 else "past")
	check("gate 5 era switches stay closed", g.is_closed() and is_equal_approx(g.progress(), 1.0))
	# leaves carry collision on layer 1 and move with the pivot
	var leaf: AnimatableBody3D = g.get_node("PIVOT_IsolationGate/Leaf_4")
	check("gate leaf collision layer 1", leaf.collision_layer == 1)
	# stack_at_end mirrors the stack
	var g2 := BigSlidingGate.new()
	g2.stack_at_end = true
	root.add_child(g2)
	await process_frame
	g2.apply_state(false, "present")
	check("gate stack_at_end: open stack at span end", is_equal_approx(g2.leaf_x(3), 32.0), str(g2.leaf_x(3)))
	g2.apply_state(true, "present")
	check("gate stack_at_end: closed leaf 4 at 0", is_equal_approx(g2.leaf_x(4), 0.0), str(g2.leaf_x(4)))
	g.queue_free()
	g2.queue_free()


func _test_platform() -> void:
	var p := TransferPlatform.new()
	root.add_child(p)
	await process_frame
	p.platform_locked.connect(func() -> void: events.append("locked"))
	p.platform_aligned.connect(func() -> void: events.append("aligned"))
	p.shutter_dropped.connect(func() -> void: events.append("shutter"))
	p.apply_state(false, "present")
	check("platform start parked", is_equal_approx(p.deck_x(), -p.travel_m), str(p.deck_x()))
	var r := p.lever_request("present")
	check("lever present seized", not r.accepted and r.reason == "seized", str(r))
	r = p.lever_request("past")
	check("lever past accepted", r.accepted, str(r))
	p.apply_state(false, "past")
	p.play_lock_sequence()
	await wait_game(6.5)
	check("platform aligned after sequence", is_equal_approx(p.deck_x(), 0.0), str(p.deck_x()))
	check("pins locked after sequence", is_equal_approx(p.pins_progress(), 1.0), str(p.pins_progress()))
	check("lever at detent 3", p.detent == 3)
	check("aligned + locked signals once each", events.count("aligned") == 1 and events.count("locked") == 1, str(events))
	r = p.lever_request("past")
	check("lever already_locked", not r.accepted and r.reason == "already_locked", str(r))
	# back to present: aligned and locked, shutter armed but not down until the player steps on the deck
	p.apply_state(true, "present")
	check("present after lock: still aligned", is_equal_approx(p.deck_x(), 0.0))
	check("present after lock: shutter not yet down", not p.shutter_blocking())
	p.notify_player_on_deck()
	await wait_game(3.5)
	check("shutter dropped after first step", p.shutter_blocking() and events.count("shutter") == 1, str(events))
	# past hides the shutter and its collision; present restores it down immediately
	p.apply_state(true, "past")
	var sh: AnimatableBody3D = p.get_node("MOV_Shutter")
	check("past: shutter hidden, no collision", not sh.visible and sh.collision_layer == 0)
	p.apply_state(true, "present")
	check("present again: shutter down at once", p.shutter_blocking())
	r = p.lever_request("present")
	check("lever present + locked -> seized (era checked first)", not r.accepted and r.reason == "seized", str(r))
	# level restart: flag back to false clears the shutter memory; relock + step plays the drop again
	p.apply_state(false, "present")
	p.apply_state(false, "past")
	p.play_lock_sequence()
	await wait_game(6.5)
	p.apply_state(true, "present")
	check("after restart: shutter armed again, not down", not p.shutter_blocking())
	p.notify_player_on_deck()
	await wait_game(3.5)
	check("after restart: shutter drop plays again", p.shutter_blocking() and events.count("shutter") == 2, str(events))
	# cancel mid-sequence jumps to terminal
	p.reset_shutter_memory()
	p.apply_state(false, "past")
	p.play_lock_sequence()
	await wait_game(1.5)
	p.cancel_transients()
	check("cancel mid-sequence -> terminal aligned", is_equal_approx(p.deck_x(), 0.0) and is_equal_approx(p.pins_progress(), 1.0))
	# lever range helper
	check("lever_in_range near pedestal", p.lever_in_range(p.to_global(p.lever_offset + Vector3(-1.0, 0, 0))))
	check("lever_in_range far away", not p.lever_in_range(p.to_global(Vector3(0, 0, 0))))
	# deck and rails collision
	var deck: AnimatableBody3D = p.get_node("MOV_TransferDeck")
	check("deck collision layer 1", deck.collision_layer == 1)
	p.queue_free()


func _count_meshes(n: Node) -> int:
	var k := 1 if n is MeshInstance3D else 0
	for c in n.get_children():
		k += _count_meshes(c)
	return k


func _test_skins() -> void:
	# 建模 C8 / C4 skins: visible meshes only; collision, names, pivots and states unchanged
	var g: BigSlidingGate = (load("res://mechanisms/steamhall/big_sliding_gate.tscn") as PackedScene).instantiate()
	g.stack_at_end = true
	root.add_child(g)
	await process_frame
	var leaf0: AnimatableBody3D = g.get_node("PIVOT_IsolationGate/Leaf_0")
	check("gate skin attached to every leaf + track", g.has_skin() and leaf0.has_node("Skin_present") and leaf0.has_node("Skin_past")
			and g.get_node("PIVOT_IsolationGate/Leaf_4").has_node("Skin_past") and g.has_node("PIVOT_IsolationGate/TrackSkin_present"))
	check("gate skin has meshes", _count_meshes(leaf0.get_node("Skin_present")) >= 2, str(_count_meshes(leaf0.get_node("Skin_present"))))
	var shape := (leaf0.get_child(0) as CollisionShape3D).shape as BoxShape3D
	check("gate leaf collision unchanged under skin", shape.size.is_equal_approx(Vector3(8, 7, 0.25)), str(shape.size))
	g.apply_state(false, "past")
	check("gate past shows past skin only", leaf0.get_node("Skin_past").visible and not leaf0.get_node("Skin_present").visible)
	g.apply_state(true, "present")
	check("gate present shows present skin, still closes", leaf0.get_node("Skin_present").visible and g.is_closed()
			and is_equal_approx(g.leaf_x(4), 0.0))
	g.queue_free()
	var p: TransferPlatform = (load("res://mechanisms/steamhall/transfer_platform.tscn") as PackedScene).instantiate()
	root.add_child(p)
	await process_frame
	var deck: AnimatableBody3D = p.get_node("MOV_TransferDeck")
	var dskin: Node3D = deck.get_node_or_null("Skin_present")
	check("platform deck skin under the deck body, +0.25 m", dskin != null and is_equal_approx(dskin.position.y, 0.25)
			and _count_meshes(dskin) >= 3, str(dskin.position if dskin else null))
	var pins_skinned := 0
	for pin in p._pins:                  # the second pin gets an auto name (@MOV_LockPin@n), so use the list
		if pin.has_node("Skin_present") and pin.has_node("Skin_past"):
			pins_skinned += 1
	check("platform both lock pins skinned, rails + housings skinned", pins_skinned == 2 and p.has_node("RailsSkin_present")
			and p.has_node("LockPinHousingsSkin_present"), str(pins_skinned))
	p.apply_state(true, "past")
	check("platform past skin + still aligned/locked", deck.get_node("Skin_past").visible and not dskin.visible
			and is_equal_approx(p.deck_x(), 0.0) and is_equal_approx(p.pins_progress(), 1.0))
	p.queue_free()


func _test_demo_loads() -> void:
	var scene: PackedScene = load("res://mechanisms/steamhall/demo/demo_steamhall.tscn")
	check("demo scene loads", scene != null)
	if scene == null:
		return
	var d := scene.instantiate()
	root.add_child(d)
	await process_frame
	await process_frame
	check("demo has both mechanisms", d.get_node_or_null("BigSlidingGate") != null and d.get_node_or_null("TransferPlatform") != null)
	# drive the demo's own flags the way an adapter would
	d.era = "past"
	d.rebuild()
	d.player.global_position = d.valve_pos + Vector3(-1.5, 0.1, -0.5)
	d._interact()
	check("demo: valve in past closes the gate", d.flags.valve_closed_past and d.gate.is_closed())
	d.player.global_position = d.platform.to_global(d.platform.lever_offset + Vector3(-0.8, 0.1, 0))
	d._interact()
	await wait_game(6.5)
	check("demo: lever in past locks the platform", d.flags.platform_locked_past and is_equal_approx(d.platform.deck_x(), 0.0))
	d.queue_free()
