extends PanelContainer
## 交互提示：［E］动词 物件名；不能用时换成 ⊘ 动词 物件名 · 原因。
## 只负责显示：能不能用由接线方（关卡／主场景）根据公共程序的状态决定后传进来。

const Text := preload("res://ui/ui_text.gd")
const Tokens := preload("res://ui/ui_tokens.gd")

@onready var _key_cap: PanelContainer = %KeyCap
@onready var _key_label: Label = %KeyLabel
@onready var _blocked_icon: Control = %BlockedIcon
@onready var _verb: Label = %Verb
@onready var _target: Label = %Target
@onready var _reason: Label = %Reason

## 当前显示内容的签名；内容不变时重复调用不会重播淡入。
var signature := ""
var _tween: Tween


func _ready() -> void:
	visible = false
	modulate.a = 0.0


## 可交互：［key］verb target
func show_prompt(verb: String, target: String, key := "E") -> void:
	_apply("ok|%s|%s|%s" % [key, verb, target], verb, target, key, "")


## 不可交互：⊘ verb target · reason
func show_blocked(verb: String, target: String, reason: String) -> void:
	_apply("blocked|%s|%s|%s" % [verb, target, reason], verb, target, "", reason)


## 用公共接口的 device_id / action 显示；blocked_reason 为空表示可用。
func show_device(device_id: String, action: String, blocked_reason := "", key := "E") -> void:
	var verb := Text.action_verb(action)
	var target := Text.device_name(device_id)
	if blocked_reason.is_empty():
		show_prompt(verb, target, key)
	else:
		show_blocked(verb, target, blocked_reason)


func hide_prompt() -> void:
	if signature.is_empty():
		return
	signature = ""
	_kill_tween()
	visible = false
	modulate.a = 0.0


func _apply(sig: String, verb: String, target: String, key: String, reason: String) -> void:
	if sig == signature and visible:
		return
	signature = sig
	var blocked := not reason.is_empty()
	_key_cap.visible = not blocked
	_key_label.text = key
	_blocked_icon.visible = blocked
	_verb.text = verb
	_target.text = target
	_target.add_theme_color_override("font_color", Tokens.TEXT_MUTED if blocked else Tokens.GOLD)
	_verb.add_theme_color_override("font_color", Tokens.TEXT_MUTED if blocked else Tokens.PAPER)
	_reason.visible = blocked
	_reason.text = "· " + reason
	if not visible:
		visible = true
		_kill_tween()
		_tween = create_tween()
		_tween.tween_property(self, "modulate:a", 1.0, Tokens.T_HOVER)


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
