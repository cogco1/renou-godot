extends SceneTree
## 主场景 integration_lab 接上 UI 后的实机截图（要窗口和 GPU，用 ui/tools/capture_ui.ps1 -Lab 跑）：
##   Godot --path . --resolution 1920x1080 --script res://ui/tests/lab_capture.gd -- --ui-capture=<输出目录>
## 走真实的公共程序请求和玩家位置，不直接改 flags；只为截图摆位置和朝向。

var lab: Node3D
var out_dir := ""
var shots := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-capture="):
			out_dir = arg.trim_prefix("--ui-capture=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	lab = load("res://scenes/integration_lab.tscn").instantiate()
	root.add_child(lab)
	_run.call_deferred()


func frames(n := 3) -> void:
	for i in n:
		await physics_frame


func wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func place(p: Vector3, yaw_deg := 0.0, pitch_deg := -6.0) -> void:
	lab.player.position = p
	lab.player.velocity = Vector3.ZERO
	await frames(4)
	lab.player.rotation.y = deg_to_rad(yaw_deg)
	lab.player.camera.rotation.x = deg_to_rad(pitch_deg)
	await frames(2)


func era(target: String) -> Dictionary:
	await frames(2)
	return lab.send("era.switch.request", {"target_era": target})


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	shots += 1
	var path := out_dir.path_join("lab_%02d_%s.png" % [shots, name])
	print("captured ", path, " err=", image.save_png(path))


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	await frames(10)
	# 03 配电小院
	lab.select_level(2)
	await frames(8)
	lab.notice.text = ""
	await place(Vector3(0, 0.04, 0.7), 40.0)
	await wait(0.4)
	await shot("cabinet_present_start")
	await era("past")
	await wait(0.18)
	await shot("cabinet_switching_to_past")
	await wait(0.6)
	await frames(2)
	lab.interact_nearest()
	await wait(0.4)
	await shot("cabinet_past_read_plaque")
	await era("present")
	await wait(0.7)
	await frames(2)
	lab.interact_nearest()
	await frames(2)
	lab.code_panel.press_digit("0")
	lab.code_panel.press_digit("4")
	await wait(0.35)
	await shot("cabinet_panel")
	lab.code_panel.press_digit("1")
	lab.code_panel.press_digit("1")
	lab.code_input.text_submitted.emit(lab.code_input.text)
	await wait(0.4)
	await shot("cabinet_wrong_code")
	await frames(2)
	lab.interact_nearest()
	await frames(2)
	lab.code_input.text = "0427"
	lab.code_input.text_submitted.emit(lab.code_input.text)
	await wait(0.4)
	await shot("cabinet_code_ok")
	await place(Vector3(0, 0.04, -1.3), 60.0)
	await wait(3.2)
	await shot("cabinet_start_button_prompt")
	lab.interact_nearest()
	await wait(0.4)
	await shot("cabinet_power_on")
	# 01 断桥：站在过去的桥面上，切回现在会落空
	lab.select_level(0)
	await frames(8)
	await place(Vector3(0, 0.04, 2.0), 0.0, -10.0)
	await era("past")
	await wait(0.7)
	await place(Vector3(0, 0.04, -8.5), 0.0, -10.0)
	await era("present")
	await wait(0.3)
	await shot("bridge_switch_blocked")
	# 02 检修通道：现在，阀门只在过去能关
	lab.select_level(1)
	await frames(8)
	await place(Vector3(0, 0.04, 0.6), 50.0)
	await wait(0.4)
	await shot("valve_present_blocked_prompt")
	quit(0)
