extends Control

signal impact(cue: String)
signal finished

const UI = preload("res://scripts/presentation/card_ui.gd")
const PLATE_INSET = 4.0
const WINDUP = 0.105
const MELEE_CONTACT = 0.185
const MELEE_HOLD = 0.045
const RANGED_HOLD = 0.030
const GOLD = Color("ffbc5f")
const CYAN = Color("8ce9ff")
const WHITE = Color("fff5da")

var attack: Dictionary
var source_tile: Control
var target_tile: Control
var build_face: Callable
var attacker: Panel
var defender: Panel
var particles: Node2D
var losses: HBoxContainer
var ranged: bool
var arrow: bool
var contact_time: float
var duration: float
var elapsed := 0.0
var contacted := false
var direction: Vector2
var muzzle: Vector2
var strike_point: Vector2

func play(event: Dictionary, source: Control, target: Control, face: Callable) -> void:
	attack = event
	source_tile = source
	target_tile = target
	build_face = face
	ranged = attack.attacker.get("attack_delivery", "melee") == "ranged"
	arrow = ranged and attack.attacker.get("attack_projectile") == "arrow"
	contact_time = 0.235 + 0.035 * float(attack.distance - 1) if ranged else MELEE_CONTACT
	duration = contact_time + (0.54 if attack.lethal else 0.475)
	name = "ChessAttackEffect"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 10
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	defender = _plate("Defender", attack.defender)
	attacker = _plate("Attacker", attack.attacker)
	particles = Node2D.new()
	particles.draw.connect(_draw_particles)
	add_child(particles)
	losses = HBoxContainer.new()
	losses.name = "DamageNumbers"
	losses.add_theme_constant_override("separation", 5)
	losses.mouse_filter = Control.MOUSE_FILTER_IGNORE
	losses.hide()
	add_child(losses)
	_animate(0.0)

	var tween := create_tween()
	tween.tween_method(_animate, 0.0, contact_time, contact_time)
	tween.tween_callback(_on_contact)
	tween.tween_method(_animate, contact_time, duration, duration - contact_time)
	tween.tween_callback(finished.emit)

func _plate(node_name: String, unit: Dictionary) -> Panel:
	var plate := Panel.new()
	plate.name = node_name
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var color := Color("526f5b") if unit.side == 0 else Color("775943")
	var style := UI.box(color, UI.GOLD, 0, 5)
	style.shadow_color = Color(0.07, 0.09, 0.06, 0.7)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 3)
	plate.add_theme_stylebox_override("panel", style)
	add_child(plate)
	build_face.call(plate, unit, "")
	return plate

func _on_contact() -> void:
	contacted = true
	var unit: Dictionary = attack.defender.duplicate()
	unit.hp = attack.hp
	unit.armor = attack.armor
	UI.clear(defender)
	build_face.call(defender, unit, "")
	if attack.armor_loss > 0:
		_add_loss("护甲 −%d" % attack.armor_loss, CYAN)
	if attack.hp_loss > 0:
		_add_loss("生命 −%d" % attack.hp_loss, Color("ff9c88"))
	if losses.get_child_count() == 0:
		_add_loss("未造成伤害", Color("e0e1d2"))
	losses.show()
	impact.emit("chess_block" if attack.hp_loss == 0 else "chess_shot" if ranged else "chess_strike")
	_animate(contact_time)

func _add_loss(value: String, color: Color) -> void:
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_theme_stylebox_override("panel", UI.box(Color("252925"), color, 5, 5))
	losses.add_child(pill)
	var label := UI.label(pill, value, 18, color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _tile_rect(tile: Control) -> Rect2:
	var canvas_to_local := get_global_transform_with_canvas().affine_inverse()
	var tile_to_local := canvas_to_local * tile.get_global_transform_with_canvas()
	return (tile_to_local * Rect2(Vector2.ZERO, tile.size)).grow(-PLATE_INSET)

func _animate(time: float) -> void:
	elapsed = time
	var source := _tile_rect(source_tile)
	var target := _tile_rect(target_tile)
	var start := source.get_center()
	var end := target.get_center()
	direction = start.direction_to(end)
	var source_edge := _edge_distance(source.size, direction)
	var target_edge := _edge_distance(target.size, direction)
	var back := start - direction * minf(20.0, source_edge * 0.28)
	var collision := start + direction * maxf(0.0, start.distance_to(end) - source_edge - target_edge + 12.0)
	muzzle = start + direction * source_edge * 0.32
	strike_point = end - direction * (target_edge - (18.0 if ranged else 5.0))

	var attacker_pos := start
	var defender_pos := end
	var tilt := 0.0
	var attacker_scale := 1.0
	var defender_scale := 1.0
	var defender_alpha := 1.0
	var tilt_sign := -1.0 if direction.x < -0.1 or (absf(direction.x) <= 0.1 and direction.y < 0.0) else 1.0
	if not contacted:
		if ranged:
			attacker_scale += 0.026 * sin(PI * _progress(time, 0.0, contact_time))
		elif time < WINDUP:
			var pull := _ease_out(_progress(time, 0.0, WINDUP))
			attacker_pos = start.lerp(back, pull)
			tilt = tilt_sign * -0.042 * pull
		else:
			var rush := pow(_progress(time, WINDUP, contact_time), 2.05)
			attacker_pos = back.lerp(collision, rush)
			tilt = tilt_sign * lerpf(-0.042, 0.028, rush)
			attacker_scale += 0.026 * rush
	else:
		var age := time - contact_time
		var hold := RANGED_HOLD if ranged else MELEE_HOLD
		var recoil := _progress(age, hold, hold + 0.21)
		var rebound := cos(recoil * 2.5 * PI) * pow(1.0 - recoil, 2.0)
		defender_pos += direction * (5.0 if ranged else 11.0) * rebound
		defender_scale -= 0.026 * rebound
		if not ranged:
			attacker_pos = collision.lerp(start, _ease_out(recoil))
			attacker_scale += 0.026 * rebound
			tilt = 0.028 * tilt_sign * rebound
		if attack.lethal:
			defender_alpha = 1.0 - _progress(age, hold, 0.19)
			defender_scale -= 0.09 * (1.0 - defender_alpha)
			var occupy := _ease_out(_progress(age, 0.19, 0.415))
			attacker_pos = (start if ranged else collision).lerp(end, occupy)
			tilt = 0.028 * tilt_sign * (1.0 - occupy) if not ranged else 0.0
		var float_size := losses.get_combined_minimum_size()
		var float_x := target.position.x + target.size.x * 0.70 - float_size.x / 2.0
		losses.position = Vector2(clampf(float_x, 4.0, maxf(4.0, size.x - float_size.x - 4.0)),
			maxf(5.0, target.position.y + 20.0 - 43.0 * _ease_out(_progress(time, contact_time, duration))))
		losses.modulate.a = 1.0 - _progress(time, duration - 0.12, duration)

	_pose(attacker, attacker_pos, source.size, attacker_scale, tilt)
	_pose(defender, defender_pos, target.size, defender_scale)
	defender.modulate.a = defender_alpha
	particles.queue_redraw()

func _pose(plate: Control, center: Vector2, plate_size: Vector2, zoom: float, tilt: float = 0.0) -> void:
	plate.size = plate_size
	plate.position = center - plate_size * 0.5
	plate.pivot_offset = plate_size * 0.5
	plate.scale = Vector2.ONE * zoom
	plate.rotation = tilt

func _draw_particles() -> void:
	if direction.is_zero_approx():
		return
	if contacted:
		_draw_burst(elapsed - contact_time)
	elif ranged:
		_draw_projectile()
	elif elapsed >= WINDUP:
		var strength := pow(_progress(elapsed, WINDUP, contact_time), 2.0)
		var tail := attacker.position + attacker.size * 0.5 - direction * _edge_distance(attacker.size, direction)
		var across := direction.orthogonal()
		for lane in [-1.0, 0.0, 1.0]:
			var tip := tail + across * float(lane) * 18.0
			particles.draw_line(tip - direction * (24.0 + strength * 28.0), tip, Color(GOLD, strength * 0.55), 2.0, true)

func _draw_projectile() -> void:
	var across := direction.orthogonal()
	if elapsed < WINDUP:
		var glow := _progress(elapsed, 0.035, WINDUP)
		particles.draw_circle(muzzle, 13.0 * glow, Color(CYAN, 0.19 * glow), true, -1.0, true)
		particles.draw_line(muzzle - across * 8.0 * glow, muzzle + across * 8.0 * glow, Color(WHITE, glow), 2.0, true)
		return
	var travel := _progress(elapsed, WINDUP, contact_time)
	var head := muzzle.lerp(strike_point, travel)
	var tail := head - direction * minf(66.0, 13.0 + muzzle.distance_to(head))
	particles.draw_line(tail, head, Color(CYAN, 0.25), 12.0 if not arrow else 8.0, true)
	particles.draw_line(tail.lerp(head, 0.28), head, CYAN, 4.0, true)
	particles.draw_line(head - direction * 22.0, head, WHITE, 2.5, true)
	if arrow:
		var tip := head - direction * 10.0
		particles.draw_colored_polygon(PackedVector2Array([head, tip + across * 5.0, tip - across * 5.0]), Color("ffe4a6"))
	else:
		particles.draw_circle(head, 9.0, Color(CYAN, 0.3), true, -1.0, true)
		particles.draw_circle(head, 4.0, WHITE, true, -1.0, true)

func _draw_burst(age: float) -> void:
	var fade := 1.0 - _progress(age, 0.0, 0.25)
	if fade <= 0.0:
		return
	var tint := CYAN if ranged or attack.hp_loss == 0 else GOLD
	var radius := (29.0 if ranged else 43.0) * _ease_out(1.0 - fade)
	particles.draw_circle(strike_point, 21.0 + radius * 0.55, Color(tint, fade * 0.12), true, -1.0, true)
	particles.draw_circle(strike_point, 11.0 + radius * 0.46, Color(tint, fade * 0.28), true, -1.0, true)
	particles.draw_circle(strike_point, 4.0 + fade * 6.0, Color(WHITE, fade * fade), true, -1.0, true)
	particles.draw_arc(strike_point, 7.0 + radius, 0.0, TAU, 32, Color(tint, fade * 0.7), 2.0 + fade * 2.0, true)
	for i in (8 if ranged else 12):
		var ray := direction.rotated(float(i) * 2.39996)
		var length := (19.0 if ranged else 28.0) + float(i % 3) * 8.0
		var near := strike_point + ray * radius * (0.38 + float(i % 4) * 0.13)
		var far := near + ray * length * (0.45 + 1.0 - fade)
		particles.draw_line(near, far, Color(tint, fade * 0.84), 2.0 + fade * 2.0, true)
		particles.draw_line(near, near.lerp(far, 0.56), Color(WHITE, fade), 1.5, true)

static func _edge_distance(plate_size: Vector2, along: Vector2) -> float:
	return 0.5 * minf(plate_size.x / maxf(0.001, absf(along.x)), plate_size.y / maxf(0.001, absf(along.y)))

static func _progress(value: float, start: float, end: float) -> float:
	return clampf(inverse_lerp(start, end, value), 0.0, 1.0)

static func _ease_out(value: float) -> float:
	return 1.0 - pow(1.0 - value, 3.0)
