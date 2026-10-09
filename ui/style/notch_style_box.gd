@tool
extends StyleBox
## A「检修图版」底板：四角各缺一个小方块（体素缺角），不用圆角、铆钉和厚框。
## 可选：边框、焦点双线内框、焦点 ▸ 标记、斜纹底（预警／不可用）、一侧色条（时代、状态）。
## 全部用轴对齐矩形拼，边框和填充互不重叠，半透明颜色不会叠深。

@export var bg_color := Color(0.0784, 0.0863, 0.0824, 0.78):
	set(value):
		bg_color = value
		emit_changed()
@export var border_color := Color(0.9373, 0.902, 0.8118, 0.22):
	set(value):
		border_color = value
		emit_changed()
@export_range(0, 8) var border_width := 1:
	set(value):
		border_width = value
		emit_changed()
## 缺角边长（像素）。规范是 6；纸页用 10。
@export_range(0, 24) var notch := 6:
	set(value):
		notch = value
		emit_changed()
## 焦点双线内框：透明表示不画。
@export var inner_frame_color := Color(0, 0, 0, 0):
	set(value):
		inner_frame_color = value
		emit_changed()
@export_range(0, 12) var inner_frame_inset := 3:
	set(value):
		inner_frame_inset = value
		emit_changed()
## 焦点 ▸ 标记，画在左侧框外：透明表示不画。
@export var marker_color := Color(0, 0, 0, 0):
	set(value):
		marker_color = value
		emit_changed()
## 斜纹：透明表示不画。
@export var hatch_color := Color(0, 0, 0, 0):
	set(value):
		hatch_color = value
		emit_changed()
@export_range(4, 32) var hatch_spacing := 9.0:
	set(value):
		hatch_spacing = value
		emit_changed()
## 一侧色条（时代标签底边、状态条左边）：透明表示不画。
@export var accent_color := Color(0, 0, 0, 0):
	set(value):
		accent_color = value
		emit_changed()
@export_enum("Left", "Top", "Right", "Bottom") var accent_side := 3:
	set(value):
		accent_side = value
		emit_changed()
@export_range(0, 12) var accent_width := 3:
	set(value):
		accent_width = value
		emit_changed()


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var n := float(mini(notch, int(minf(rect.size.x, rect.size.y) * 0.5)))
	var b := float(border_width) if border_color.a > 0.0 else 0.0
	if n > 0.0 and b > n:
		n = b
	if bg_color.a > 0.0:
		for r in _fill_rects(rect, n, b):
			RenderingServer.canvas_item_add_rect(to_canvas_item, r, bg_color)
	if hatch_color.a > 0.0:
		_draw_hatch(to_canvas_item, rect.grow(-(b + n * 0.5)))
	if b > 0.0:
		for r in _ring_rects(rect, n, b):
			RenderingServer.canvas_item_add_rect(to_canvas_item, r, border_color)
	if accent_color.a > 0.0 and accent_width > 0:
		RenderingServer.canvas_item_add_rect(to_canvas_item, _accent_rect(rect, n), accent_color)
	if inner_frame_color.a > 0.0:
		var inner := rect.grow(-(b + inner_frame_inset))
		if inner.size.x > 2.0 and inner.size.y > 2.0:
			for r in _ring_rects(inner, 0.0, 1.0):
				RenderingServer.canvas_item_add_rect(to_canvas_item, r, inner_frame_color)
	if marker_color.a > 0.0:
		var cy := rect.position.y + rect.size.y * 0.5
		var x := rect.position.x - 5.0
		var points := PackedVector2Array([Vector2(x - 6.0, cy - 5.0), Vector2(x, cy), Vector2(x - 6.0, cy + 5.0)])
		RenderingServer.canvas_item_add_polygon(to_canvas_item, points, PackedColorArray([marker_color]))


## 填充：边框以内的缺角形，分上、中、下三条。
static func _fill_rects(rect: Rect2, n: float, b: float) -> Array[Rect2]:
	var x := rect.position.x
	var y := rect.position.y
	var w := rect.size.x
	var h := rect.size.y
	var out: Array[Rect2] = []
	if n <= 0.0:
		_push(out, Rect2(x + b, y + b, w - 2.0 * b, h - 2.0 * b))
		return out
	_push(out, Rect2(x + n + b, y + b, w - 2.0 * (n + b), n))
	_push(out, Rect2(x + b, y + n + b, w - 2.0 * b, h - 2.0 * (n + b)))
	_push(out, Rect2(x + n + b, y + h - n - b, w - 2.0 * (n + b), n))
	return out


## 边框：沿缺角外形走一圈，按水平带拆成互不重叠的矩形（要求 n >= b）。
static func _ring_rects(rect: Rect2, n: float, b: float) -> Array[Rect2]:
	var x := rect.position.x
	var y := rect.position.y
	var w := rect.size.x
	var h := rect.size.y
	var out: Array[Rect2] = []
	if n <= 0.0:
		_push(out, Rect2(x, y, w, b))
		_push(out, Rect2(x, y + h - b, w, b))
		_push(out, Rect2(x, y + b, b, h - 2.0 * b))
		_push(out, Rect2(x + w - b, y + b, b, h - 2.0 * b))
		return out
	_push(out, Rect2(x + n, y, w - 2.0 * n, b))
	_push(out, Rect2(x + n, y + b, b, n - b))
	_push(out, Rect2(x + w - n - b, y + b, b, n - b))
	_push(out, Rect2(x, y + n, n + b, b))
	_push(out, Rect2(x + w - n - b, y + n, n + b, b))
	_push(out, Rect2(x, y + n + b, b, h - 2.0 * (n + b)))
	_push(out, Rect2(x + w - b, y + n + b, b, h - 2.0 * (n + b)))
	_push(out, Rect2(x, y + h - n - b, n + b, b))
	_push(out, Rect2(x + w - n - b, y + h - n - b, n + b, b))
	_push(out, Rect2(x + n, y + h - n, b, n - b))
	_push(out, Rect2(x + w - n - b, y + h - n, b, n - b))
	_push(out, Rect2(x + n, y + h - b, w - 2.0 * n, b))
	return out


func _accent_rect(rect: Rect2, n: float) -> Rect2:
	var a := float(accent_width)
	match accent_side:
		0:
			return Rect2(rect.position.x, rect.position.y + n, a, rect.size.y - 2.0 * n)
		1:
			return Rect2(rect.position.x + n, rect.position.y, rect.size.x - 2.0 * n, a)
		2:
			return Rect2(rect.end.x - a, rect.position.y + n, a, rect.size.y - 2.0 * n)
	return Rect2(rect.position.x + n, rect.end.y - a, rect.size.x - 2.0 * n, a)


## 45° 斜纹，裁在给定矩形里。
func _draw_hatch(item: RID, area: Rect2) -> void:
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return
	var x0 := area.position.x
	var y0 := area.position.y
	var x1 := area.end.x
	var y1 := area.end.y
	var c := x0 + y0 + hatch_spacing
	while c < x1 + y1:
		# 直线 x + y = c，与矩形求交
		var xs := maxf(x0, c - y1)
		var xe := minf(x1, c - y0)
		if xe > xs:
			RenderingServer.canvas_item_add_line(item, Vector2(xs, c - xs), Vector2(xe, c - xe), hatch_color, 1.5, true)
		c += hatch_spacing


static func _push(out: Array[Rect2], r: Rect2) -> void:
	if r.size.x > 0.0 and r.size.y > 0.0:
		out.append(r)
