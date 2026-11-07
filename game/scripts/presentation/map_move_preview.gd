extends Control

const INK = Color("30271f")
const GOLD = Color("ffe3a0")
var camera: Camera3D
var actor: Node3D
var destination: Vector3
var costs: Array[String] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	hide()

func show_path(mover: Node3D, endpoint: Vector3, captions: Array[String]) -> void:
	actor = mover
	destination = endpoint
	costs = captions
	show()
	queue_redraw()

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

func _draw() -> void:
	if not is_instance_valid(actor) or not is_instance_valid(camera):
		return
	var feet = camera.unproject_position(actor.global_position)
	var tip = camera.unproject_position(destination)
	var direction = feet.direction_to(tip)
	var side = Vector2(direction.y, -direction.x)
	var distance = feet.distance_to(tip)
	if distance > 4.0:
		var arrow_length = minf(15.0, distance * 0.35)
		var tail = tip - direction * arrow_length
		var start = feet + direction * minf(8.0, distance * 0.15)
		draw_dashed_line(start, tail, INK, 6.0, 9.0, true, true)
		draw_dashed_line(start, tail, GOLD, 3.0, 9.0, true, true)
		var arrow = PackedVector2Array([tip, tail + side * arrow_length * 0.44, tail - side * arrow_length * 0.44])
		draw_colored_polygon(arrow, GOLD)
		arrow.append(tip)
		draw_polyline(arrow, INK, 1.5, true)
	var font = get_theme_default_font()
	var font_size = 19
	var center = feet.lerp(tip, 0.63) + side * 30.0
	for i in costs.size():
		var line = costs[i]
		var width = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var baseline = center + Vector2(-width * 0.5, 7.0 + i * 23.0)
		draw_string_outline(font, baseline, line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, INK)
		draw_string(font, baseline, line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, GOLD)
