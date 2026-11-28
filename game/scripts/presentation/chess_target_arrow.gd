extends Control

const SNAP_TIME := 0.078
const CONFIRM_TIME := 0.090
const INVALID := Color("efae9d")
const SHADOW := Color("18241d")
const SAMPLES := 24

var origin: Rect2
var destination: Rect2
var tip := Vector2.ZERO
var color := Color.WHITE
var valid := false
var confirming := false
var snap_tween: Tween

func _ready() -> void:
	name = "ChessTargetArrow"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 25
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hide()

func rect_in_layer(control: Control) -> Rect2:
	var transform := get_global_transform_with_canvas().affine_inverse() * control.get_global_transform_with_canvas()
	return transform * Rect2(Vector2.ZERO, control.size)

func point_in_layer(control: Control, point: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * (control.get_global_transform_with_canvas() * point)

func aim(source: Rect2, target: Rect2, pointer: Vector2, tint: Color, allowed: bool, snap_now: bool) -> void:
	if confirming:
		return
	var new_target := not visible or origin != source or destination != target or not valid
	origin = source
	destination = target
	color = tint
	valid = allowed
	show()
	if not valid or snap_now:
		_stop_snap()
		_set_tip(target.get_center() if valid else pointer)
	elif new_target:
		_stop_snap()
		_set_tip(pointer)
		snap_tween = create_tween()
		snap_tween.tween_method(_set_tip, tip, target.get_center(), SNAP_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func confirm(source: Rect2, target: Rect2, tint: Color, reduced: bool) -> void:
	if reduced:
		clear_preview()
		return
	aim(source, target, target.get_center(), tint, true, true)
	confirming = true
	var release := create_tween()
	release.tween_property(self, "modulate:a", 0.0, CONFIRM_TIME)
	release.tween_callback(func():
		confirming = false
		hide()
		modulate.a = 1.0)

func clear_preview() -> void:
	if confirming:
		return
	_stop_snap()
	hide()

func _stop_snap() -> void:
	if snap_tween != null:
		snap_tween.kill()
		snap_tween = null

func _set_tip(point: Vector2) -> void:
	tip = point
	queue_redraw()

func _draw() -> void:
	var start := origin.get_center()
	var toward := start.direction_to(tip)
	var length := start.distance_to(tip)
	if length < 12.0:
		return
	start += toward * minf(origin.size.y * 0.27, length * 0.23)
	var end := tip - toward * (13.0 if valid else 8.0)
	var distance := start.distance_to(end)
	var bend := minf(36.0, distance * 0.20) * (-1.0 if toward.y > 0.12 else 1.0)
	var control := start.lerp(end, 0.5) + toward.orthogonal() * bend
	var points := PackedVector2Array()
	for index in (SAMPLES + 1):
		var progress := float(index) / SAMPLES
		points.append(start.lerp(control, progress).lerp(control.lerp(end, progress), progress))
	if valid:
		draw_rect(destination.grow(-2.0), Color(color, 0.9), false, 2.0, true)
		draw_polyline(points, Color(color, 0.17), 11.0, true)
		draw_polyline(points, SHADOW, 6.0, true)
		draw_polyline(points, Color(color, 0.94), 3.2, true)
		_draw_head(end, control.direction_to(end))
		var mark := destination.get_center()
		draw_circle(mark, 15.0, Color(color, 0.15), true, -1.0, true)
		draw_arc(mark, 13.0, 0.0, TAU, 32, color, 1.7, true)
		var diamond := PackedVector2Array([mark + Vector2(0, -4), mark + Vector2(4, 0), mark + Vector2(0, 4),
			mark + Vector2(-4, 0), mark + Vector2(0, -4)])
		draw_polyline(diamond, color, 1.5, true)
	else:
		draw_rect(destination.grow(-2.0), Color(INVALID, 0.64), false, 1.4, true)
		for index in range(0, SAMPLES, 3):
			draw_line(points[index], points[index + 2], Color(SHADOW, 0.86), 4.5, true)
			draw_line(points[index], points[index + 2], Color(INVALID, 0.81), 2.0, true)
		draw_line(tip - Vector2(5, 5), tip + Vector2(5, 5), INVALID, 1.8, true)
		draw_line(tip - Vector2(5, -5), tip + Vector2(5, -5), INVALID, 1.8, true)
	draw_circle(start, 4.8, SHADOW, true, -1.0, true)
	draw_arc(start, 4.1, 0.0, TAU, 20, color if valid else INVALID, 1.6, true)

func _draw_head(end: Vector2, direction: Vector2) -> void:
	var base := end - direction * 18.0
	var side := direction.orthogonal() * 7.5
	draw_colored_polygon(PackedVector2Array([end + direction * 2, base + side,
		base + direction * 5, base - side]), color.lightened(0.16))
