extends Node3D
## UI 预览：在一个占位 3D 场景上看 HUD、交互提示、密码面板、残差率的各个状态。
## 不连公共程序，只调用 UI 自己的方法；文案和状态都是演示。
##   打开：Godot 编辑器里运行本场景（F6），按 1–0 切状态，Esc 关密码面板。
##   截图：Godot --path . --resolution 1920x1080 res://ui/preview/ui_preview.tscn -- --ui-capture=<输出目录>

const STATES := [
	"01_explore_present",
	"02_explore_past_plaque",
	"03_era_switching",
	"04_switch_blocked",
	"05_cabinet_panel",
	"06_code_ok",
	"07_wrong_code",
	"08_valve_closed",
	"09_completed",
	"10_residual",
]

@onready var hud: CanvasLayer = $HUD
@onready var panel: CanvasLayer = $CabinetPanel
@onready var residual: CanvasLayer = $ResidualScreen

var _env: Environment
var _sun: DirectionalLight3D
var _past_props: Array[Node3D] = []
var _present_props: Array[Node3D] = []


func _ready() -> void:
	_build_world()
	panel.handle_escape = true
	panel.cancelled.connect(func(): panel.close(); hud.set_suppressed("puzzle_ui", false))
	panel.submitted.connect(func(code): panel.close(); hud.set_suppressed("puzzle_ui", false); hud.show_status("info", "提交了 " + code, "预览不判定对错"))
	var capture_dir := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-capture="):
			capture_dir = arg.trim_prefix("--ui-capture=")
	if capture_dir.is_empty():
		apply_state(STATES[0])
	else:
		_capture_all.call_deferred(capture_dir)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var i: int = event.keycode - KEY_1 if event.keycode != KEY_0 else 9
		if event.keycode >= KEY_0 and event.keycode <= KEY_9 and i < STATES.size():
			apply_state(STATES[i])


func apply_state(state: String) -> void:
	residual.stop()
	panel.close()
	hud.set_suppressed("puzzle_ui", false)
	hud.reset_transients()
	hud.notice_label.text = "UI 预览 · 演示状态 " + state
	match state:
		"01_explore_present":
			_set_world_era("present")
			hud.set_level("mvp_cabinet", {})
			hud.set_era("present", false)
			hud.show_interaction("plaque", "read", "过去才能用")
		"02_explore_past_plaque":
			_set_world_era("past")
			hud.set_level("mvp_cabinet", {"clue_seen": true})
			hud.set_era("past", false)
			hud.show_status("info", "铭牌上的密码", "0427")
			hud.show_interaction("plaque", "read")
		"03_era_switching":
			_set_world_era("past")
			hud.set_level("mvp_cabinet", {})
			hud.preview_switch("past", 0.32)
		"04_switch_blocked":
			_set_world_era("present")
			hud.set_level("mvp_bridge", {"bridge_crossed_past": true})
			hud.set_era("present", false)
			hud.show_era_blocked("此处无法切换", 30.0)
		"05_cabinet_panel":
			_set_world_era("present")
			hud.set_level("mvp_cabinet", {"clue_seen": true})
			hud.set_era("present", false)
			hud.set_suppressed("puzzle_ui", true)
			panel.open()
			panel.press_digit("0")
			panel.press_digit("4")
		"06_code_ok":
			_set_world_era("present")
			hud.set_level("mvp_cabinet", {"clue_seen": true, "cabinet_unlocked": true})
			hud.set_era("present", false)
			hud.show_status("success", "密码正确", "启动按钮已解锁")
			hud.show_interaction("start_button", "press")
		"07_wrong_code":
			_set_world_era("present")
			hud.set_level("mvp_cabinet", {"clue_seen": true})
			hud.set_era("present", false)
			hud.show_status("error", "密码不对", "按 E 重试")
			hud.show_interaction("cabinet", "submit_code")
		"08_valve_closed":
			_set_world_era("past")
			hud.set_level("mvp_valve", {"valve_closed_past": true})
			hud.set_era("past", false)
			hud.show_status("success", "阀门已关闭", "隔离门闭合，蒸汽被隔在设备间")
		"09_completed":
			_set_world_era("present")
			hud.set_level("mvp_cabinet", {"clue_seen": true, "cabinet_unlocked": true, "power_on": true, "exit_reached": true})
			hud.set_era("present", false)
			hud.show_status("success", "通路已恢复", "可以自由走动，按 T 重来")
		"10_residual":
			residual.show_result(0.000024)


func _capture_all(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	get_window().size = Vector2i(1920, 1080)
	await get_tree().create_timer(0.5).timeout
	for state in STATES:
		apply_state(state)
		await get_tree().create_timer(0.45).timeout
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var path := dir.path_join("ui_" + state + ".png")
		var err := image.save_png(path)
		print("captured ", path, " ", image.get_size(), " err=", err)
	get_tree().quit()


# ---------------------------------------------------------------- 占位 3D 场景

func _build_world() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_energy = 0.7
	_env.fog_enabled = true
	_env.fog_density = 0.02
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-38, -30, 0)
	add_child(_sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.62, 4.5)
	cam.rotation_degrees = Vector3(-4, 0, 0)
	cam.fov = 70
	cam.current = true
	add_child(cam)
	_box(Vector3(0, -0.25, -6), Vector3(14, 0.5, 26), Color("4a4f52"))
	_box(Vector3(-6.5, 3, -6), Vector3(1, 6, 26), Color("5b5550"))
	_box(Vector3(6.5, 3, -6), Vector3(1, 6, 26), Color("57524c"))
	_box(Vector3(-2.4, 1.1, -1.5), Vector3(1.2, 2.2, 0.8), Color("687c80"))          # 配电箱
	_box(Vector3(0, 2.0, -14), Vector3(8, 4, 0.4), Color("6d6a62"))                  # 大门
	for z in [-4.0, -8.0, -12.0]:
		_box(Vector3(4.2, 1.5, z), Vector3(0.4, 3, 0.4), Color("7a6e5e"))
	_past_props.append(_box(Vector3(-1.75, 1.45, -1.5), Vector3(0.06, 0.45, 0.6), Color("e3cf91")))   # 过去的铭牌
	_present_props.append(_box(Vector3(-1.75, 1.45, -1.5), Vector3(0.06, 0.45, 0.6), Color("5595b0")))  # 现在的面板


func _box(p: Vector3, s: Vector3, c: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = s
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = 0.9
	mesh.material_override = mat
	mesh.position = p
	add_child(mesh)
	return mesh


func _set_world_era(era: String) -> void:
	var past := era == "past"
	_env.background_color = Color("9fb8b4") if past else Color("2b2a33")
	_env.ambient_light_color = Color("d6e6df") if past else Color("b98a6a")
	_env.fog_light_color = Color("b9cdc8") if past else Color("4a3a36")
	_sun.light_color = Color("fff3dc") if past else Color("ffb27a")
	_sun.light_energy = 1.4 if past else 0.8
	for n in _past_props:
		n.visible = past
	for n in _present_props:
		n.visible = not past
