extends Control

const UI = preload("res://scripts/presentation/card_ui.gd")
const FACE_SIZE := Vector2(86, 106)
const ADD_LIGHT := Color("b4edc3")
const REMOVE_LIGHT := Color("f5bd78")

var face: PanelContainer
var source: Vector2
var target: Rect2
var tint: Color
var joining: bool
var from_drag: bool
var reduced: bool
var arc: float
var duration: float
var arrival: float
var elapsed := 0.0

static func card_face(card: Dictionary, light: Color, font: Font) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = FACE_SIZE
	var style := UI.box(Color("284136"), light, 4, 7)
	style.shadow_color = Color(light, 0.28)
	style.shadow_size = 9
	panel.add_theme_stylebox_override("panel", style)
	var body := VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(body)
	UI.art(body, card, Vector2.ZERO).size_flags_vertical = Control.SIZE_EXPAND_FILL
	var caption := UI.label(body, card.name, 12, UI.INK)
	caption.add_theme_font_override("font", font)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return panel

func play(card: Dictionary, start: Vector2, destination: Rect2, adding: bool, dropped: bool, reduce_motion: bool) -> void:
	name = "DeckCardTransfer"
	source = start
	target = destination
	joining = adding
	from_drag = dropped
	reduced = reduce_motion
	tint = ADD_LIGHT if joining else REMOVE_LIGHT
	var distance := start.distance_to(target.get_center())
	arc = minf(23.0, distance * 0.24 + 10.0) if from_drag else minf(88.0, distance * 0.19 + 18.0)
	duration = (0.25 if joining else 0.28) if from_drag else (0.44 if joining else 0.46)
	arrival = duration * (0.55 if from_drag else 0.66)
	if reduced:
		duration = 0.24
		arrival = 0.0
	else:
		face = card_face(card, tint, get_theme_font("font"))
		add_child(face)
		face.size = FACE_SIZE
		face.pivot_offset = FACE_SIZE * 0.5
	_animate(0)
	var motion := create_tween()
	motion.tween_method(_animate, 0.0, duration, duration)
	motion.tween_callback(queue_free)

func _flight(progress: float) -> Vector2:
	return source.lerp(target.get_center(), progress) - Vector2(0, 4.0 * arc * progress * (1.0 - progress))

func _animate(time: float) -> void:
	elapsed = time
	if face != null:
		var pace := clampf(time / arrival, 0.0, 1.0)
		var step := smoothstep(0.0, 1.0, pace)
		face.position = _flight(step) - FACE_SIZE * 0.5
		face.scale = Vector2.ONE * lerpf(0.75 + 0.27 * sin(PI * pace), 0.30, pow(pace, 3.0))
		face.rotation = signf(target.get_center().x - source.x) * sin(PI * pace) * 0.16
		face.modulate.a = 1.0 - smoothstep(0.78, 1.0, pace)
	queue_redraw()

func _draw() -> void:
	var center := target.get_center()
	if not reduced and elapsed < arrival:
		var pace := clampf(elapsed / arrival, 0.0, 1.0)
		var step := smoothstep(0.0, 1.0, pace)
		var tail := maxf(step - 0.31, 0.0)
		var points := 5 if from_drag else 11
		for index in points:
			var fraction := float(index + 1) / points
			var from := _flight(lerpf(tail, step, float(index) / points))
			var to := _flight(lerpf(tail, step, fraction))
			var glow := sin(PI * pace) * fraction
			draw_line(from, to, Color(tint, glow * 0.34), 10.0, true)
			draw_circle(from + Vector2(0, float(index % 3 - 1) * 5.0), 1.8 + fraction, Color(tint, glow), true, -1, true)
		return

	var fade := clampf((elapsed - arrival) / (duration - arrival), 0.0, 1.0)
	draw_rect(target.grow(1), Color(tint, 0.76 * (1.0 - fade)), false, 2.0, true)
	draw_rect(target, Color(tint, 0.15 * (1.0 - fade)))
	if reduced:
		return
	var radius := lerpf(10.0, 43.0 if joining else 48.0, sqrt(fade))
	draw_arc(center, radius, 0, TAU, 40, Color(tint, 0.50 * (1.0 - fade)), 2.0, true)
	var sparks := 7 if from_drag else 12
	for index in sparks:
		var direction := Vector2.from_angle(TAU * index / sparks)
		var spread := 12.0 + sqrt(fade) * (16.0 + float(index % 4) * 8.0)
		var point := center + direction * spread - Vector2(0, fade * 9.0)
		draw_circle(point, lerpf(3.2, 0.8, fade), Color(tint, 0.95 * (1.0 - fade)), true, -1, true)
