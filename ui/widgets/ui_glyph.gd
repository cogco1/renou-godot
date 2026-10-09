@tool
extends Control
## 线形小图形（24 px 栅格），全部用代码画，缩放不糊：
## 状态图标 check / cross / warn / info / blocked / busy，
## 眼镜符号 glasses_present（裸眼）/ glasses_past（戴镜），
## 准星 crosshair、刻度尺 ruler、时代切换效果 switch_fx（用 progress 驱动）。

@export_enum("check", "cross", "warn", "info", "blocked", "busy", "glasses_present", "glasses_past", "crosshair", "ruler", "switch_fx") var kind := "info":
	set(value):
		kind = value
		queue_redraw()
@export var color := Color("efe6cf"):
	set(value):
		color = value
		queue_redraw()
@export var line_width := 2.0:
	set(value):
		line_width = value
		queue_redraw()
## switch_fx 用：0 = 刚切换，1 = 结束。
@export_range(0.0, 1.0) var progress := 1.0:
	set(value):
		progress = value
		queue_redraw()


func _draw() -> void:
	match kind:
		"check", "cross", "info", "blocked", "busy", "warn":
			_draw_status()
		"glasses_present", "glasses_past":
			_draw_glasses(kind == "glasses_past")
		"crosshair":
			_draw_crosshair()
		"ruler":
			_draw_ruler()
		"switch_fx":
			_draw_switch_fx()


func _draw_status() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var w := line_width
	var box := Rect2(o + Vector2(w, w) * 0.5, Vector2(s, s) - Vector2(w, w))
	match kind:
		"check":
			draw_rect(box, color, false, w)
			draw_polyline(PackedVector2Array([o + Vector2(0.25, 0.52) * s, o + Vector2(0.43, 0.70) * s, o + Vector2(0.76, 0.30) * s]), color, w)
		"cross":
			draw_rect(box, color, false, w)
			draw_line(o + Vector2(0.30, 0.30) * s, o + Vector2(0.70, 0.70) * s, color, w)
			draw_line(o + Vector2(0.70, 0.30) * s, o + Vector2(0.30, 0.70) * s, color, w)
		"warn":
			var tri := PackedVector2Array([o + Vector2(0.5, 0.06) * s, o + Vector2(0.96, 0.92) * s, o + Vector2(0.04, 0.92) * s])
			draw_colored_polygon(tri, color)
			draw_line(o + Vector2(0.5, 0.36) * s, o + Vector2(0.5, 0.64) * s, Color("1d1812"), w)
			draw_rect(Rect2(o + Vector2(0.5, 0.74) * s - Vector2(w, w) * 0.5, Vector2(w, w)), Color("1d1812"))
		"info":
			draw_arc(o + Vector2(s, s) * 0.5, s * 0.5 - w * 0.5, 0.0, TAU, 32, color, w, true)
			draw_line(o + Vector2(0.5, 0.44) * s, o + Vector2(0.5, 0.74) * s, color, w)
			draw_rect(Rect2(o + Vector2(0.5, 0.28) * s - Vector2(w, w) * 0.5, Vector2(w, w)), color)
		"blocked":
			var c := o + Vector2(s, s) * 0.5
			draw_arc(c, s * 0.5 - w * 0.5, 0.0, TAU, 32, color, w, true)
			draw_line(c + Vector2(-0.32, 0.32) * s, c + Vector2(0.32, -0.32) * s, color, w)
		"busy":
			var c := o + Vector2(s, s) * 0.5
			for i in 8:
				if i % 2 == 0:
					draw_arc(c, s * 0.5 - w * 0.5, i * TAU / 8.0, (i + 1) * TAU / 8.0, 6, color, w, true)


## 眼镜像素符号：裸眼 = 空心镜片；戴镜 = 实心镜片。
func _draw_glasses(on: bool) -> void:
	var u := minf(size.x / 24.0, size.y / 12.0)
	var o := (size - Vector2(24.0, 12.0) * u) * 0.5
	var w := maxf(line_width, u * 1.5)
	var lens_l := Rect2(o + Vector2(1, 3) * u, Vector2(8, 6) * u)
	var lens_r := Rect2(o + Vector2(15, 3) * u, Vector2(8, 6) * u)
	if on:
		draw_rect(lens_l, color)
		draw_rect(lens_r, color)
	else:
		draw_rect(lens_l.grow(-w * 0.5), color, false, w)
		draw_rect(lens_r.grow(-w * 0.5), color, false, w)
	draw_rect(Rect2(o + Vector2(9, 4) * u, Vector2(6, 1.5) * u), color)
	draw_rect(Rect2(o + Vector2(0, 3) * u, Vector2(1, 1.5) * u), color)
	draw_rect(Rect2(o + Vector2(23, 3) * u, Vector2(1, 1.5) * u), color)


func _draw_crosshair() -> void:
	var c := size * 0.5
	var faint := Color(color, color.a * 0.45)
	draw_rect(Rect2(c - Vector2(5, 5), Vector2(10, 10)), color, false, 1.5)
	draw_line(c + Vector2(-22, 0), c + Vector2(-10, 0), faint, 1.0)
	draw_line(c + Vector2(10, 0), c + Vector2(22, 0), faint, 1.0)
	draw_line(c + Vector2(0, -22), c + Vector2(0, -10), faint, 1.0)
	draw_line(c + Vector2(0, 10), c + Vector2(0, 22), faint, 1.0)


func _draw_ruler() -> void:
	var y := size.y - 1.0
	draw_line(Vector2(0, y), Vector2(size.x, y), color, 1.0)
	var step := 24.0
	var i := 0
	var x := 0.0
	while x <= size.x + 0.5:
		var h := size.y if i % 4 == 0 else size.y * 0.5
		draw_line(Vector2(x, y), Vector2(x, y - h + 1.0), color, 1.0)
		x += step
		i += 1


## 时代切换：快门从上下合拢处张开，刻度环绕准星扫一圈，染上目标时代的颜色。
func _draw_switch_fx() -> void:
	if progress >= 1.0:
		return
	var t := clampf(progress, 0.0, 1.0)
	var open := 1.0 - pow(1.0 - t, 3.0)
	var bar := size.y * 0.5 * 0.42 * (1.0 - open)
	var shade := Color(0.0314, 0.0353, 0.0353, 0.92 * (1.0 - t * 0.6))
	draw_rect(Rect2(0, 0, size.x, bar), shade)
	draw_rect(Rect2(0, size.y - bar, size.x, bar), shade)
	draw_rect(Rect2(0, bar, size.x, 2.0), Color(color, 0.8 * (1.0 - t)))
	draw_rect(Rect2(0, size.y - bar - 2.0, size.x, 2.0), Color(color, 0.8 * (1.0 - t)))
	draw_rect(Rect2(Vector2.ZERO, size), Color(color, 0.10 * (1.0 - t)))
	var c := size * 0.5
	var r := lerpf(64.0, 150.0, open)
	var ticks := 48
	var shown := int(ceil(ticks * open))
	for i in shown:
		var a := -PI * 0.5 + TAU * float(i) / ticks
		var inner := r - (14.0 if i % 4 == 0 else 7.0)
		draw_line(c + Vector2(cos(a), sin(a)) * inner, c + Vector2(cos(a), sin(a)) * r, Color(color, 0.9 * (1.0 - t)), 2.0)
