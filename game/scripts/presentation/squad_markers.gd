extends Node2D
## Screen-space locator for the only playable map figure.
const COLOR = Color("63b6ff")
var point = Vector2.ZERO

func update_position(camera: Camera3D, doll: Node3D, enabled: bool) -> void:
	hide()
	if not enabled or not is_instance_valid(doll):
		return
	var anchor = doll.global_position + Vector3.UP * 0.52
	if camera.is_position_behind(anchor):
		return
	var projected = camera.unproject_position(anchor)
	if not get_viewport_rect().grow(30).has_point(projected):
		return
	point = projected - Vector2(0, 15)
	point.x = clampf(point.x, 20, get_viewport_rect().size.x - 20)
	point.y = clampf(point.y, 115, get_viewport_rect().size.y - 25)
	show()
	queue_redraw()

func _draw() -> void:
	var triangle = PackedVector2Array([point + Vector2(-13, -8.45), point + Vector2(13, -8.45), point + Vector2(0, 13)])
	draw_circle(point, 19, Color(COLOR, 0.16), true, -1, true)
	draw_colored_polygon(triangle, COLOR)
	triangle.append(triangle[0])
	draw_polyline(triangle, Color("fff7df"), 3.0, true)
