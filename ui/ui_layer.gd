extends CanvasLayer
## UI 图层基类：按 1920×1080 设计，运行时按窗口等比缩放（不改 project.godot）。
## 子节点里名为 Root 的 Control 会被设成“窗口尺寸 ÷ 缩放”，里面按锚点布局。

const Tokens := preload("res://ui/ui_tokens.gd")

## 设置页的 UI 缩放（80%–150%）。
@export_range(0.8, 1.5, 0.05) var ui_scale := 1.0:
	set(value):
		ui_scale = value
		if is_inside_tree():
			_fit()
## 减少动态效果：动画一律改 120 ms 淡入淡出，数字直接出结果。
@export var reduced_motion := false

var root: Control


func _ready() -> void:
	root = get_node_or_null("Root") as Control
	get_viewport().size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	if root == null:
		return
	var view := get_viewport().get_visible_rect().size
	var s := minf(view.x / Tokens.BASE_SIZE.x, view.y / Tokens.BASE_SIZE.y) * ui_scale
	if s <= 0.0:
		return
	transform = Transform2D.IDENTITY.scaled(Vector2(s, s))
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.position = Vector2.ZERO
	root.size = view / s


## 动画时长：减少动态效果时统一成淡入淡出时长。
func motion(seconds: float) -> float:
	return Tokens.T_FADE if reduced_motion else seconds
