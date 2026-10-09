extends "res://ui/ui_layer.gd"
## 游戏 HUD（A「检修图版」）：左上目标、右上时代标签、中间准星和交互提示、上方状态提示、右下按键提示。
## 只读状态、只显示，不判定机关成败。两种用法：
##   1. bind_service(service)：跟随公共程序 state_service 的 state_changed / feedback / level_completed 自动更新；
##   2. 直接调用 set_level / set_era / show_status / show_interaction 等方法（预览、过场）。

signal status_shown(kind: String, title: String)

const Text := preload("res://ui/ui_text.gd")
const Glyph := preload("res://ui/widgets/ui_glyph.gd")
const MAX_TOASTS := 3

@export var show_key_hints := true:
	set(value):
		show_key_hints = value
		if is_node_ready():
			_key_hints.visible = value
@export var debug_visible := false:
	set(value):
		debug_visible = value
		if is_node_ready():
			_debug.visible = value
@export var toast_seconds := 2.8

@onready var _switch_fx: Control = %SwitchFx
@onready var _crosshair: Control = %Crosshair
@onready var _objective: PanelContainer = %Objective
@onready var _objective_title: Label = %ObjectiveTitle
@onready var _objective_done: Control = %ObjectiveDone
@onready var _step: Label = %Step
@onready var _counter: Label = %Counter
@onready var _era_tag: PanelContainer = %EraTag
@onready var _era_glyph: Control = %EraGlyph
@onready var _era_name: Label = %EraName
@onready var _era_alias: Label = %EraAlias
@onready var _era_hint_row: Control = %EraHintRow
@onready var _era_hint: Label = %EraHint
@onready var _era_blocked_row: Control = %EraBlockedRow
@onready var _era_blocked: Label = %EraBlocked
@onready var _toasts: VBoxContainer = %Toasts
@onready var _key_hints: Control = %KeyHints
@onready var _debug: Label = %Debug
## 交互提示（ui/interaction_prompt.tscn 的实例）
@onready var prompt: PanelContainer = %Prompt
## 左下一行小字，给主场景放普通说明（兼容旧的 notice）
@onready var notice_label: Label = %Notice

var service: Node
var era := "present"
var level_id := ""
var _flags := {}
var _era_style: StyleBox
var _fx_tween: Tween
var _era_tween: Tween
var _blocked_left := 0.0
var _suppressed := {}


func _ready() -> void:
	super._ready()
	_era_style = _era_tag.get_theme_stylebox("panel").duplicate()
	_era_tag.add_theme_stylebox_override("panel", _era_style)
	_key_hints.visible = show_key_hints
	_debug.visible = debug_visible
	_switch_fx.progress = 1.0
	_era_blocked_row.visible = false
	set_era(era, false)


func _process(delta: float) -> void:
	if _blocked_left > 0.0:
		_blocked_left -= delta
		if _blocked_left <= 0.0:
			_era_blocked_row.visible = false
			_era_hint_row.visible = true
	if is_instance_valid(service):
		set_suppressed("puzzle_ui", service.input_mode == "puzzle_ui")


# ---------------------------------------------------------------- 接公共程序

## 跟随公共程序的状态。service 需要有 state_changed / feedback / level_completed 信号、
## input_mode、active_level、snapshot()（即 core/state_service.gd）。
func bind_service(s: Node) -> void:
	if is_instance_valid(service):
		service.state_changed.disconnect(_on_state_changed)
		service.feedback.disconnect(_on_feedback)
		service.level_completed.disconnect(_on_level_completed)
	service = s
	service.state_changed.connect(_on_state_changed)
	service.feedback.connect(_on_feedback)
	service.level_completed.connect(_on_level_completed)
	if not str(service.active_level).is_empty():
		_on_state_changed(service.active_level, service.snapshot())


func _on_state_changed(id: String, state: Dictionary) -> void:
	var flags: Dictionary = state.get("flags", {})
	if id != level_id:
		reset_transients()
		set_level(id, flags)
		set_era(state.get("era", "present"), false)
		return
	for key in _flags:
		if _flags[key] and not flags.get(key, false):
			reset_transients()   # 有 flag 退回去了：重来或回检查点，旧提示一起收掉
			break
	if state.get("era", era) != era:
		set_era(state.era, true)
	for key in flags:
		if flags[key] and not _flags.get(key, false) and Text.FLAG_NOTE.has(key):
			var note: Array = Text.FLAG_NOTE[key]
			show_status(note[0], note[1], note[2])
	set_level(id, flags)


func _on_feedback(result: Dictionary) -> void:
	if result.get("accepted", true):
		return
	var reason := str(result.get("reason", ""))
	if reason == "unsafe_switch":
		var note: Array = Text.REASON_NOTE[reason]
		show_era_blocked(note[1])
		return
	if Text.REASON_NOTE.has(reason):
		var note: Array = Text.REASON_NOTE[reason]
		show_status(note[0], note[1], note[2])


func _on_level_completed(id: String) -> void:
	if id != level_id:
		return
	_set_objective_completed()
	show_status(Text.COMPLETED_NOTE[0], Text.COMPLETED_NOTE[1], Text.COMPLETED_NOTE[2])


# ---------------------------------------------------------------- 目标

## 按关卡和 flags 显示目标：标题 + 当前这一步 + “第几步 / 共几步”。
func set_level(id: String, flags: Dictionary = {}) -> void:
	level_id = id
	_flags = flags.duplicate()
	var objective: Dictionary = Text.OBJECTIVES.get(id, {})
	if objective.is_empty():
		set_objective(Text.level_name(id))
		return
	var steps: Array = objective.steps
	for i in steps.size():
		if not flags.get(steps[i][1], false):
			set_objective(objective.title, steps[i][0], i + 1, steps.size())
			return
	_set_objective_completed(objective.title)


## 直接设目标；step 为空时只显示标题。
func set_objective(title: String, step := "", index := 0, total := 0) -> void:
	_objective_title.text = title
	_objective_done.visible = false
	_step.text = step
	_step.get_parent().visible = not step.is_empty()
	_counter.text = "%d / %d" % [index, total] if total > 0 else ""


func _set_objective_completed(title := "") -> void:
	if not title.is_empty():
		_objective_title.text = title
	_objective_done.visible = true
	_step.text = Text.COMPLETED_NOTE[1]
	_step.get_parent().visible = true
	_counter.text = "✓"


# ---------------------------------------------------------------- 时代

## 时代标签：present = 暮色石板灰、空心镜片；past = 晨光桃、实心镜片（用户 10-08：过去暖亮、现在灰暗）。animate 时播 480 ms 快门 + 刻度环。
func set_era(new_era: String, animate := true) -> void:
	era = "past" if new_era == "past" else "present"
	var color := Tokens.era_color(era)
	if _era_tween and _era_tween.is_valid():
		_era_tween.kill()
	if animate:
		_show_era_switching(color)
		_era_tween = create_tween()
		_era_tween.tween_interval(motion(Tokens.T_ERA) * 0.5)
		_era_tween.tween_callback(_show_era_stable.bind(color))
		_play_switch_fx(color)
	else:
		_stop_switch_fx()
		_show_era_stable(color)


func _stop_switch_fx() -> void:
	if _fx_tween and _fx_tween.is_valid():
		_fx_tween.kill()
	_switch_fx.progress = 1.0


## 收掉所有临时显示：状态提示、交互提示、无法切换的原因、切换效果。换关和重来时用。
func reset_transients() -> void:
	clear_status()
	hide_interaction()
	_blocked_left = 0.0
	_era_blocked_row.visible = false
	_era_hint_row.visible = true
	_stop_switch_fx()
	_show_era_stable(Tokens.era_color(era))


func _show_era_stable(color: Color) -> void:
	_era_glyph.kind = "glasses_past" if era == "past" else "glasses_present"
	_era_glyph.color = color
	_era_name.text = Text.ERA_NAME[era]
	_era_alias.text = Text.ERA_ALIAS[era]
	_era_alias.add_theme_color_override("font_color", color)
	_era_hint.text = Text.ERA_HINT[era]
	_era_style.accent_color = color
	_era_style.border_color = Tokens.BORDER


func _show_era_switching(color: Color) -> void:
	_era_glyph.kind = "glasses_past" if era == "past" else "glasses_present"
	_era_glyph.color = Tokens.GOLD
	_era_name.text = "切换中"
	_era_alias.text = "→ " + Text.ERA_NAME[era]
	_era_alias.add_theme_color_override("font_color", color)
	_era_style.accent_color = Tokens.GOLD
	_era_style.border_color = Tokens.GOLD


func _play_switch_fx(color: Color) -> void:
	if _fx_tween and _fx_tween.is_valid():
		_fx_tween.kill()
	_switch_fx.color = color
	_switch_fx.progress = 0.0
	_fx_tween = create_tween()
	_fx_tween.tween_property(_switch_fx, "progress", 1.0, motion(Tokens.T_ERA))


## 预览／截图用：把切换效果停在某个进度（0–1）。
func preview_switch(target_era: String, progress: float) -> void:
	era = "past" if target_era == "past" else "present"
	if _fx_tween and _fx_tween.is_valid():
		_fx_tween.kill()
	_show_era_switching(Tokens.era_color(era))
	_switch_fx.color = Tokens.era_color(era)
	_switch_fx.progress = progress


## 时代标签里短暂显示“⊘ 无法切换”的原因（默认 1.6 秒）。
func show_era_blocked(text: String, seconds := 1.6) -> void:
	_era_blocked.text = text
	_era_blocked_row.visible = true
	_era_hint_row.visible = false
	_blocked_left = seconds


# ---------------------------------------------------------------- 交互提示

func show_interaction(device_id: String, action: String, blocked_reason := "") -> void:
	if _suppressed.is_empty():
		prompt.show_device(device_id, action, blocked_reason)


func hide_interaction() -> void:
	prompt.hide_prompt()


# ---------------------------------------------------------------- 状态提示

## kind：success ✓ / error ✕ / warn ! / info i / blocked ⊘ / busy ◌。形状、文字、色条一起区分。
func show_status(kind: String, title: String, body := "", seconds := -1.0) -> void:
	for child in _toasts.get_children():
		if child.get_meta("title", "") == title and not child.is_queued_for_deletion():
			_dismiss(child, 0.0)
	while _toasts.get_child_count() >= MAX_TOASTS:
		var oldest := _toasts.get_child(0)
		_toasts.remove_child(oldest)
		oldest.queue_free()
	var toast := _make_toast(kind, title, body)
	_toasts.add_child(toast)
	toast.modulate.a = 0.0
	var tween := toast.create_tween()
	tween.tween_property(toast, "modulate:a", 1.0, motion(Tokens.T_HOVER))
	tween.tween_interval(toast_seconds if seconds < 0.0 else seconds)
	tween.tween_property(toast, "modulate:a", 0.0, motion(Tokens.T_PANEL))
	tween.tween_callback(toast.queue_free)
	status_shown.emit(kind, title)


## 按公共程序的 reason 显示提示（open_puzzle_ui 这类不走 feedback 信号的结果用）。表里没有的不提示。
func show_reason(reason: String) -> void:
	_on_feedback({"accepted": false, "reason": reason})


## 再显示一次某个 flag 的提示（例如重读铭牌）。
func show_flag_note(flag: String) -> void:
	if Text.FLAG_NOTE.has(flag):
		var note: Array = Text.FLAG_NOTE[flag]
		show_status(note[0], note[1], note[2])


## 显示文案表里的一条 [种类, 标题, 说明]。
func show_note(note: Array) -> void:
	show_status(note[0], note[1], note[2] if note.size() > 2 else "")


func clear_status() -> void:
	for child in _toasts.get_children():
		_toasts.remove_child(child)
		child.queue_free()


## 当前还在显示的状态提示标题（测试用）。
func status_titles() -> PackedStringArray:
	var out := PackedStringArray()
	for child in _toasts.get_children():
		if not child.is_queued_for_deletion():
			out.append(child.get_meta("title", ""))
	return out


func _dismiss(toast: Node, _delay: float) -> void:
	_toasts.remove_child(toast)
	toast.queue_free()


func _make_toast(kind: String, title: String, body: String) -> PanelContainer:
	var accent := Tokens.status_color(kind)
	var toast := PanelContainer.new()
	toast.theme_type_variation = &"ToastPlate"
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	toast.set_meta("title", title)
	toast.set_meta("kind", kind)
	var style: StyleBox = _toasts.get_theme_stylebox("panel", &"ToastPlate").duplicate()
	style.accent_color = accent
	if kind in ["warn", "blocked"]:
		style.hatch_color = Color(accent, 0.10)
	toast.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_child(row)
	var icon := Glyph.new()
	icon.kind = kind if kind in ["check", "cross"] else {"success": "check", "error": "cross"}.get(kind, kind)
	icon.color = accent
	icon.custom_minimum_size = Vector2(22, 22)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 2)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)
	var head := Label.new()
	head.theme_type_variation = &"ToastTitle"
	head.text = title
	texts.add_child(head)
	if not body.is_empty():
		var sub := Label.new()
		sub.theme_type_variation = &"ToastBody"
		sub.text = body
		texts.add_child(sub)
	return toast


# ---------------------------------------------------------------- 其他

## 设备面板、对话、残差率打开时收起探索 HUD（目标、准星、交互提示、按键提示）。
func set_suppressed(reason: String, on: bool) -> void:
	if on == _suppressed.has(reason):
		return
	if on:
		_suppressed[reason] = true
	else:
		_suppressed.erase(reason)
	var show_world := _suppressed.is_empty()
	_objective.visible = show_world
	_crosshair.visible = show_world
	_era_tag.visible = show_world
	_key_hints.visible = show_world and show_key_hints
	if not show_world:
		prompt.hide_prompt()


func is_suppressed() -> bool:
	return not _suppressed.is_empty()


func set_debug_text(text: String) -> void:
	_debug.text = text
