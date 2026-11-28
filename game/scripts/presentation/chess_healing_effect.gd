extends Control

signal contact
signal released

const UI = preload("res://scripts/presentation/card_ui.gd")
const GREEN := Color("a6edb7")
const CORE := Color("e6ffd2")
const FLIGHT := 0.155
const RELEASE := 0.370
const NUMBER_HOLD := 1.10

var restored: Array[Dictionary]
var tiles: Array[Button]
var launch: Vector2
var target: int
var reduced: bool
var elapsed := 0.0
var landed := false
var land_time: float
var numbers: Array[PanelContainer] = []

func play(event: Dictionary, start: Vector2, board_tiles: Array[Button], reduce: bool) -> void:
	name = "ChessHealingEffect"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 30
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	restored = event.restored
	tiles = board_tiles
	launch = start
	target = event.target
	reduced = reduce
	land_time = 0.0 if reduced else FLIGHT
	var release_time := 0.11 if reduced else RELEASE

	var animation := create_tween()
	if reduced:
		_land()
	else:
		animation.tween_method(_animate, 0.0, land_time, land_time)
		animation.tween_callback(_land)
	animation.tween_method(_animate, land_time, release_time, release_time - land_time)
	animation.tween_callback(released.emit)
	animation.tween_method(_animate, release_time, land_time + NUMBER_HOLD, land_time + NUMBER_HOLD - release_time)
	animation.tween_callback(queue_free)

func _land() -> void:
	landed = true
	for result in restored:
		var number := PanelContainer.new()
		number.name = "HealAmount%d" % result.square
		number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := UI.box(Color("183b2e"), GREEN, 5, 5)
		style.content_margin_left = 12
		style.content_margin_right = 12
		style.shadow_color = Color(GREEN, 0.27)
		style.shadow_size = 5
		number.add_theme_stylebox_override("panel", style)
		add_child(number)
		var label := UI.label(number, "生命 +%d" % result.amount, 23, CORE)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		numbers.append(number)
	_animate(land_time)
	contact.emit()

func _tile_rect(square: int) -> Rect2:
	var tile := tiles[square]
	var transform := get_global_transform_with_canvas().affine_inverse() * tile.get_global_transform_with_canvas()
	return transform * Rect2(Vector2.ZERO, tile.size)

func _animate(time: float) -> void:
	elapsed = time
	if landed:
		var age := elapsed - land_time
		var lift := 0.0 if reduced else 22.0 * smoothstep(0.0, NUMBER_HOLD, age)
		for index in numbers.size():
			var frame := numbers[index]
			var tile := _tile_rect(restored[index].square)
			var caption_size := frame.get_combined_minimum_size()
			frame.position = Vector2(tile.get_center().x - caption_size.x * 0.5,
				maxf(6.0, tile.position.y + tile.size.y * 0.16 - lift))
			frame.modulate.a = 1.0 - smoothstep(0.78, NUMBER_HOLD, age)
	queue_redraw()

func _draw() -> void:
	if tiles.is_empty():
		return
	if not landed:
		var progress := smoothstep(0.0, FLIGHT, elapsed)
		var target_center := _tile_rect(target).get_center()
		var head := _flight_point(target_center, progress)
		var tail := _flight_point(target_center, maxf(0.0, progress - 0.20))
		draw_line(tail, head, Color(GREEN, 0.38), 11.0, true)
		draw_line(tail, head, Color(GREEN, 0.8), 3.0, true)
		draw_circle(head, 10.0, Color(GREEN, 0.25), true, -1.0, true)
		draw_circle(head, 5.5, CORE, true, -1.0, true)
		return
	var age := elapsed - land_time
	var glow := 1.0 - smoothstep(0.0, (0.18 if reduced else 0.46), age)
	if glow <= 0.0:
		return
	for result in restored:
		_draw_landing(_tile_rect(result.square), age, glow)

func _flight_point(destination: Vector2, progress: float) -> Vector2:
	return launch.lerp(destination, progress) + Vector2(20.0, -8.0) * sin(PI * progress)

func _draw_landing(tile: Rect2, age: float, glow: float) -> void:
	var point := tile.get_center() + Vector2(0, tile.size.y * 0.1)
	var spread := 1.0 if reduced else lerpf(0.52, 1.3, smoothstep(0.0, 0.46, age))
	var radius := minf(89.0, tile.size.x * 0.31) * spread
	draw_set_transform(point, 0.0, Vector2(1, 0.36))
	draw_circle(Vector2.ZERO, radius * 0.92, Color(GREEN, glow * 0.16), true, -1.0, true)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(GREEN, glow * 0.32), 7.0, true)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(CORE, glow * 0.83), 2.0, true)
	draw_set_transform(Vector2.ZERO)
	if reduced:
		return
	for index in 8:
		var direction := Vector2.from_angle(0.27 + TAU * float(index) / 8.0)
		var spark := point + direction * Vector2(radius * 0.69, 8.0 + age * 24.0) - Vector2(0, age * 65.0)
		draw_circle(spark, 2.6, Color(CORE, glow), true, -1.0, true)
