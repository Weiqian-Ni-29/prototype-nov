extends Control

signal finished

const UI = preload("res://scripts/presentation/card_ui.gd")
const STEP_START = 0.070
const STEP_TRAVEL = 0.180
const LONG_TRAVEL = 0.260
const STEP_LAND = 0.110
const REDUCED_HALF = 0.055
const INSET = 4.0

var source_tile: Control
var target_tile: Control
var via_tile: Control
var build_face: Callable
var settled_unit: Dictionary
var mover: Panel
var ghosts: Array[Panel] = []
var ground_cues: Node2D
var tint: Color
var pattern: String
var reduced_motion: bool
var travel_duration: float
var arrival_time: float
var duration: float
var elapsed := 0.0
var landed := false
var source_rect: Rect2
var target_rect: Rect2
var path: Array[Vector2] = []

func play(event: Dictionary, source: Control, target: Control, via: Control, after: Dictionary,
		face: Callable, reduce: bool) -> void:
	name = "ChessMovementEffect"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 10
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	source_tile = source
	target_tile = target
	via_tile = via
	build_face = face
	settled_unit = after
	pattern = event.pattern
	reduced_motion = reduce
	tint = Color("f5d598")
	if pattern == "straight":
		tint = Color("c2edc8")
	elif pattern == "diagonal":
		tint = Color("e2c9ff")
	travel_duration = LONG_TRAVEL if event.distance > 1 else STEP_TRAVEL
	arrival_time = REDUCED_HALF if reduced_motion else STEP_START + travel_duration
	duration = arrival_time + (REDUCED_HALF if reduced_motion else STEP_LAND)

	if not reduced_motion:
		for index in 2:
			var ghost := _plate("Afterimage%d" % index, Color(tint, 0.5), tint)
			var portrait := UI.art(ghost, event.mover, Vector2.ZERO)
			portrait.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
			portrait.anchor_right = 0.32
			ghosts.append(ghost)
	mover = _piece(event.mover)
	ground_cues = Node2D.new()
	ground_cues.z_index = 1
	ground_cues.draw.connect(_draw_ground)
	add_child(ground_cues)
	_animate(0.0)

	var animation := create_tween()
	animation.tween_method(_animate, 0.0, arrival_time, arrival_time)
	animation.tween_callback(_land)
	animation.tween_method(_animate, arrival_time, duration, duration - arrival_time)
	animation.tween_callback(finished.emit)

func _plate(node_name: String, fill: Color, rim: Color) -> Panel:
	var plate := Panel.new()
	plate.name = node_name
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", UI.box(fill, rim, 0, 5))
	add_child(plate)
	return plate

func _piece(unit: Dictionary) -> Panel:
	var fill := Color("526f5b") if unit.side == 0 else Color("775943")
	var plate := _plate("Mover", fill, UI.GOLD)
	plate.size = _tile_rect(target_tile if landed else source_tile).size
	var style := plate.get_theme_stylebox("panel") as StyleBoxFlat
	style.shadow_color = Color(0.07, 0.09, 0.06, 0.65)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 3)
	build_face.call(plate, unit, "")
	return plate

func _land() -> void:
	landed = true
	remove_child(mover)
	mover.queue_free()
	mover = _piece(settled_unit)
	_animate(arrival_time)

func _tile_rect(tile: Control) -> Rect2:
	var tile_to_local := get_global_transform_with_canvas().affine_inverse() * tile.get_global_transform_with_canvas()
	return (tile_to_local * Rect2(Vector2.ZERO, tile.size)).grow(-INSET)

func _animate(time: float) -> void:
	elapsed = time
	source_rect = _tile_rect(source_tile)
	target_rect = _tile_rect(target_tile)
	path.assign([source_rect.get_center(), target_rect.get_center()])
	if via_tile != null:
		path.insert(1, _tile_rect(via_tile).get_center())

	for ghost in ghosts:
		ghost.hide()
	if reduced_motion:
		_pose(mover, path[-1] if landed else path[0], target_rect.size if landed else source_rect.size, 1.0)
	elif landed:
		var settle := smoothstep(arrival_time, duration, elapsed)
		_pose(mover, path[-1] - Vector2(0, 5.0 * (1.0 - settle)), target_rect.size, lerpf(0.97, 1.0, settle))
	elif elapsed < STEP_START:
		var lift := smoothstep(0.0, STEP_START, elapsed)
		_pose(mover, path[0] - Vector2(0, 5.0 * lift), source_rect.size, 1.0 + 0.04 * lift)
	else:
		var progress := clampf((elapsed - STEP_START) / travel_duration, 0.0, 1.0)
		_pose(mover, _travel_point(progress), source_rect.size.lerp(target_rect.size, progress), lerpf(1.04, 0.97, pow(progress, 3.0)))
		for index in ghosts.size():
			var ghost := ghosts[index]
			var lag := 0.22 - float(index) * 0.10
			var behind := maxf(0.0, progress - lag)
			_pose(ghost, _travel_point(behind), source_rect.size.lerp(target_rect.size, behind), 0.95 + float(index) * 0.035)
			ghost.modulate.a = sin(PI * progress) * (0.13 + float(index) * 0.13)
			ghost.show()
	queue_redraw()
	ground_cues.queue_redraw()

func _travel_point(progress: float) -> Vector2:
	var step := smoothstep(0.0, 1.0, progress)
	var point := path[0].lerp(path[-1], step)
	if path.size() == 3:
		var first := path[0].distance_to(path[1])
		var corner := first / (first + path[1].distance_to(path[2]))
		point = path[0].lerp(path[1], step / corner) if step <= corner else path[1].lerp(path[2], (step - corner) / (1.0 - corner))
	var arc := 15.0 if pattern == "diagonal" else 4.0
	return point - Vector2(0, 5.0 + arc * sin(PI * progress))

func _pose(plate: Control, center: Vector2, dimensions: Vector2, zoom: float) -> void:
	plate.size = dimensions
	plate.position = center - dimensions * 0.5
	plate.pivot_offset = dimensions * 0.5
	plate.scale = Vector2.ONE * zoom

func _draw() -> void:
	if reduced_motion or landed or path.is_empty():
		return
	draw_rect(source_rect.grow(1.0), Color(tint, 0.48), false, 1.5, true)
	draw_rect(target_rect.grow(1.0), Color(tint, 0.64), false, 2.0, true)
	if elapsed < STEP_START or elapsed >= arrival_time:
		return
	var progress := (elapsed - STEP_START) / travel_duration
	var strength := sin(PI * progress)
	var tail := maxf(0.0, progress - (0.36 if pattern == "straight" else 0.25))
	var lanes := 3 if pattern == "straight" else 1
	for lane in lanes:
		var offset := float(lane - 1) * 12.0 if lanes == 3 else 0.0
		for index in 6:
			var a := _travel_point(lerpf(tail, progress, float(index) / 6.0))
			var b := _travel_point(lerpf(tail, progress, float(index + 1) / 6.0))
			var side := a.direction_to(b).orthogonal() * offset
			var alpha := (float(index + 1) / 6.0) * strength
			draw_line(a + side, b + side, Color(tint, alpha * 0.15), 10.0, true)
			draw_line(a + side, b + side, Color(tint, alpha * 0.58), 2.0, true)

func _draw_ground() -> void:
	if path.is_empty():
		return
	if reduced_motion:
		var pace := elapsed / REDUCED_HALF - float(landed)
		var square := target_rect if landed else source_rect
		ground_cues.draw_rect(square.grow(1.0), Color(tint, lerpf(0.9, 0.58, clampf(pace, 0.0, 1.0))), false, 3.0, true)
		return
	if not landed:
		if elapsed < STEP_START:
			_ring(source_rect, elapsed / STEP_START, 0.62)
		return
	var age := clampf((elapsed - arrival_time) / STEP_LAND, 0.0, 1.0)
	_ring(target_rect, age, 1.0)
	var foot := Vector2(target_rect.get_center().x, target_rect.end.y - 4.0)
	for index in 6:
		var direction := Vector2.from_angle(float(index) * TAU / 6.0 + 0.32)
		var point := foot + direction * Vector2(15.0 + age * 28.0, 4.0 + age * 8.0) - Vector2(0, age * 8.0)
		ground_cues.draw_circle(point, lerpf(2.3, 0.7, age), Color(tint, (1.0 - age) * 0.8), true, -1.0, true)

func _ring(tile: Rect2, progress: float, opacity: float) -> void:
	var foot := Vector2(tile.get_center().x, tile.end.y - 4.0)
	var radius := lerpf(20.0, clampf(tile.size.x * 0.27, 47.0, 79.0), smoothstep(0.0, 1.0, progress))
	var fade := (1.0 - progress) * opacity
	ground_cues.draw_set_transform(foot, 0.0, Vector2(1.0, 0.28))
	ground_cues.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(tint, fade * 0.24), 8.0, true)
	ground_cues.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(tint, fade), 2.5, true)
	ground_cues.draw_set_transform(Vector2.ZERO)
