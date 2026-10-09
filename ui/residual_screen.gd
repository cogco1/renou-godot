extends "res://ui/ui_layer.gd"
## 残差率画面：黑屏 → 白底 → 数字跳动（每步 60 ms）→ 停在结果 → 淡出。全屏，盖住其余 HUD。
## 序章用法：play(0.000021, 0.000024)。数值和触发时机由剧情／关卡决定，这里只负责演出。
## 减少动态效果时直接出结果。

signal finished

## 停在结果上的时间（秒）
@export var hold_seconds := 1.8
## 数字跳动的步数（每步 60 ms）
@export var jitter_steps := 12
@export var decimals := 6
@export var caption := "残差率"

@onready var _black: ColorRect = %Black
@onready var _white: ColorRect = %White
@onready var _value: Label = %Value
@onready var _caption: Label = %Caption

var playing := false
var _run := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	super._ready()
	visible = false


func format_value(v: float) -> String:
	return ("%." + str(decimals) + "f") % v


func play(from_value: float, to_value: float) -> void:
	_run += 1
	var run := _run
	playing = true
	visible = true
	_caption.text = caption
	_value.text = format_value(from_value)
	_value.visible = false
	_caption.visible = false
	_white.visible = false
	_black.modulate.a = 0.0
	_white.modulate.a = 1.0
	var root_alpha := create_tween()
	root.modulate.a = 1.0
	root_alpha.tween_property(_black, "modulate:a", 1.0, motion(0.2))
	await root_alpha.finished
	if run != _run:
		return
	_white.visible = true
	_white.modulate.a = 0.0
	var white_in := create_tween()
	white_in.tween_property(_white, "modulate:a", 1.0, motion(0.2))
	await white_in.finished
	if run != _run:
		return
	_value.visible = true
	_caption.visible = true
	if not reduced_motion:
		await _wait(0.6)
		if run != _run:
			return
		var unit := pow(10.0, -decimals)
		for i in jitter_steps:
			_value.text = format_value(from_value + unit * _rng.randi_range(-3, 9))
			await _wait(Tokens.T_RESIDUAL_STEP)
			if run != _run:
				return
		var steps := int(round(absf(to_value - from_value) / unit))
		var dir := signf(to_value - from_value)
		for i in range(1, mini(steps, 40) + 1):
			_value.text = format_value(from_value + dir * unit * i * maxf(1.0, steps / 40.0))
			await _wait(Tokens.T_RESIDUAL_STEP * 2.0)
			if run != _run:
				return
	_value.text = format_value(to_value)
	await _wait(hold_seconds)
	if run != _run:
		return
	var out := create_tween()
	out.tween_property(root, "modulate:a", 0.0, motion(0.3))
	await out.finished
	if run != _run:
		return
	stop()
	finished.emit()


## 不播动画，直接停在结果画面（预览、截图、剪辑垫底用）。
func show_result(value: float) -> void:
	_run += 1
	playing = false
	visible = true
	root.modulate.a = 1.0
	_black.modulate.a = 1.0
	_white.visible = true
	_white.modulate.a = 1.0
	_caption.text = caption
	_caption.visible = true
	_value.visible = true
	_value.text = format_value(value)


## 立刻收起（不发 finished）。
func stop() -> void:
	_run += 1
	playing = false
	visible = false
	root.modulate.a = 1.0


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout
