extends "res://ui/ui_layer.gd"
## 配电箱密码面板（纸底）。只收输入、发请求：
##   submitted(code) → 接线方调用公共程序 interact("cabinet", "submit_code", code)；
##   cancelled       → 接线方调用 service.cancel_puzzle_ui()。
## 密码对不对由公共程序判定；面板只检查位数够不够。正式密码 0427（用户 10-07 定），但面板里不写死。
## 键盘：数字键输入、Backspace 删除、Enter 确认；Esc 由主场景统一处理（handle_escape 只给预览用）。

signal submitted(code: String)
signal cancelled

const Glyph := preload("res://ui/widgets/ui_glyph.gd")
const Text := preload("res://ui/ui_text.gd")

@export_range(1, 8) var code_length := 4:
	set(value):
		code_length = value
		if is_node_ready():
			_build_slots()
## 只在预览场景里打开：面板自己处理 Esc。正式接线时 Esc 由主场景的 _input 处理。
@export var handle_escape := false

## 实际收键盘输入的 LineEdit（透明，挂在面板里）。测试和接线可以直接用它。
@onready var line_edit: LineEdit = %CodeInput
@onready var _sheet: Control = %Sheet
@onready var _title: Label = %Title
@onready var _tag: Label = %Tag
@onready var _slots: HBoxContainer = %Slots
@onready var _note_icon: Control = %NoteIcon
@onready var _note_title: Label = %NoteTitle
@onready var _note_body: Label = %NoteBody
@onready var _keypad: GridContainer = %Keypad
@onready var _cancel: Button = %CancelButton

var device_id := "cabinet"
var _confirm: Button
var _filtering := false
var _tween: Tween


func _ready() -> void:
	super._ready()
	visible = false
	_build_slots()
	_build_keypad()
	line_edit.max_length = 0   # 位数由 _on_text_changed 过滤，先截断会把非数字算进位数
	line_edit.text_changed.connect(_on_text_changed)
	line_edit.text_submitted.connect(_on_text_submitted)
	_cancel.pressed.connect(func(): cancelled.emit())
	_refresh()


func _input(event: InputEvent) -> void:
	if not visible or not handle_escape:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		cancelled.emit()


## 打开面板并把键盘焦点给输入框。
func open(id := "cabinet") -> void:
	device_id = id
	clear()
	set_note("info", Text.PANEL_NOTE_TITLE % code_length, Text.PANEL_NOTE_BODY)
	visible = true
	line_edit.grab_focus()
	if line_edit.has_method("edit"):
		line_edit.call("edit")
	_sheet.modulate.a = 0.0
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_sheet, "modulate:a", 1.0, motion(Tokens.T_PANEL))


func close() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_sheet.modulate.a = 1.0
	visible = false
	clear()
	line_edit.release_focus()


func clear() -> void:
	_set_text("")


## 面板里的说明条：kind = info / error / warn / success。
func set_note(kind: String, title: String, body := "") -> void:
	_note_icon.kind = {"success": "check", "error": "cross"}.get(kind, kind)
	var color: Color = {"success": Tokens.MOSS_INK, "error": Tokens.SIGNAL_INK, "warn": Tokens.OCHRE}.get(kind, Tokens.INK)
	_note_icon.color = color
	_note_title.text = title
	_note_body.text = body
	_note_body.visible = not body.is_empty()


func set_titles(title: String, tag: String) -> void:
	_title.text = title
	_tag.text = tag


func press_digit(digit: String) -> void:
	if line_edit.text.length() < code_length:
		_set_text(line_edit.text + digit)


func backspace() -> void:
	_set_text(line_edit.text.left(-1) if not line_edit.text.is_empty() else "")


func confirm() -> void:
	_on_text_submitted(line_edit.text)


func _on_text_changed(new_text: String) -> void:
	if _filtering:
		return
	var digits := ""
	for ch in new_text:
		if ch >= "0" and ch <= "9":
			digits += ch
	_set_text(digits.left(code_length))


func _on_text_submitted(text: String) -> void:
	if text.length() < code_length:
		set_note("warn", Text.PANEL_SHORT, "")
		line_edit.grab_focus()
		return
	submitted.emit(text)


func _set_text(value: String) -> void:
	_filtering = true
	if line_edit.text != value:
		line_edit.text = value
	line_edit.caret_column = value.length()
	_filtering = false
	_refresh()


func _refresh() -> void:
	var text := line_edit.text
	for i in _slots.get_child_count():
		var slot := _slots.get_child(i) as PanelContainer
		var digit := slot.get_child(0) as Label
		var filled := i < text.length()
		digit.text = text[i] if filled else "·"
		digit.theme_type_variation = &"CodeDigit" if filled else &"CodeDigitEmpty"
		slot.theme_type_variation = &"CodeSlotActive" if i == mini(text.length(), code_length - 1) and visible else &"CodeSlot"
	if _confirm:
		_confirm.disabled = text.length() < code_length


func _build_slots() -> void:
	for child in _slots.get_children():
		_slots.remove_child(child)
		child.queue_free()
	for i in code_length:
		var slot := PanelContainer.new()
		slot.theme_type_variation = &"CodeSlot"
		slot.custom_minimum_size = Vector2(64, 0)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var digit := Label.new()
		digit.theme_type_variation = &"CodeDigitEmpty"
		digit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		digit.text = "·"
		slot.add_child(digit)
		_slots.add_child(slot)
	if line_edit:
		_set_text(line_edit.text.left(code_length))


func _build_keypad() -> void:
	for label in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "删除", "0", "确认"]:
		var button := Button.new()
		button.text = label
		button.custom_minimum_size = Vector2(0, 60)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE   # 键盘焦点留在输入框
		match label:
			"删除":
				button.theme_type_variation = &"PaperKeyQuiet"
				button.pressed.connect(backspace)
			"确认":
				button.theme_type_variation = &"PaperKeyPrimary"
				button.pressed.connect(confirm)
				_confirm = button
			_:
				button.theme_type_variation = &"PaperKey"
				button.pressed.connect(press_digit.bind(label))
		_keypad.add_child(button)
