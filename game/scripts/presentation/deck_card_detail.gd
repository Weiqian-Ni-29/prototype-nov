extends ColorRect

signal dismiss_requested
signal dismissed

const UI = preload("res://scripts/presentation/card_ui.gd")
const SHADE := Color(0.025, 0.055, 0.048, 0.82)
const OPEN_TIME := 0.27
const CLOSE_TIME := 0.21

var frame: PanelContainer
var art: Panel
var info: VBoxContainer
var heading: Label
var meta: HBoxContainer
var description: VBoxContainer
var feedback: Label
var actions: HBoxContainer
var close_button: Button
var closing := false
var motion: Tween
var centered := Vector2.ZERO

func _ready() -> void:
	name = "DeckCardDetail"
	color = Color(SHADE, 0)
	gui_input.connect(_backdrop_input)
	frame = PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UI.box(Color("192f28"), Color("a59165"), 14, 12))
	add_child(frame)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	frame.add_child(columns)
	art = Panel.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_child(art)
	info = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 9)
	columns.add_child(info)

	var header := HBoxContainer.new()
	info.add_child(header)
	heading = UI.label(header, "", 29, UI.GOLD)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	close_button = UI.button(header, "×", func(): dismiss_requested.emit())
	close_button.name = "CloseDeckCardDetail"
	close_button.accessibility_name = "关闭卡牌详情"
	close_button.tooltip_text = "关闭详情 · Esc"
	close_button.custom_minimum_size.x = 40
	meta = HBoxContainer.new()
	info.add_child(meta)
	var body_scroll := UI.scroll(info)
	description = VBoxContainer.new()
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.add_child(description)
	feedback = UI.label(info, "", 15, UI.GREEN, true)
	feedback.hide()
	actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	info.add_child(actions)
	get_viewport().size_changed.connect(_fit)
	get_viewport().gui_focus_changed.connect(_keep_focus)
	_fit()

func show_art(card: Dictionary) -> void:
	UI.clear(art)
	var tint := Color("254238")
	match card.kind:
		"equipment", "weapon": tint = Color("484131")
		"defense": tint = Color("2a454a")
		"spell": tint = Color("303d51")
	art.add_theme_stylebox_override("panel", UI.box(tint, Color("617f6b"), 0, 8))
	var image := UI.art(art, card, Vector2.ZERO, true)
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [SIDE_TOP, SIDE_LEFT, SIDE_BOTTOM, SIDE_RIGHT]:
		image.set_offset(side, 9 if side == SIDE_TOP or side == SIDE_LEFT else -9)

func _fit() -> void:
	size = get_viewport_rect().size
	var frame_size := Vector2(780, 400).min(size - Vector2(44, 44))
	art.custom_minimum_size.x = frame_size.x * 0.45
	frame.size = frame_size
	frame.pivot_offset = frame.size * 0.5
	centered = (size - frame.size) * 0.5
	if motion != null and motion.is_running():
		motion.kill()
		if closing:
			dismissed.emit()
			return
	frame.position = centered
	frame.scale = Vector2.ONE
	frame.modulate.a = 1.0
	info.modulate.a = 1.0
	color = SHADE

func open_from(source: Rect2, reduced_motion: bool) -> void:
	close_button.grab_focus()
	if reduced_motion:
		return
	var origin := _zoom_pose(source)
	frame.position = Vector2(origin.x, origin.y)
	frame.scale = Vector2.ONE * origin.z
	frame.modulate.a = 0.56
	info.modulate.a = 0.0
	color.a = 0.0
	motion = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	motion.tween_property(frame, "position", centered, OPEN_TIME)
	motion.tween_property(frame, "scale", Vector2.ONE, OPEN_TIME)
	motion.tween_property(frame, "modulate:a", 1.0, OPEN_TIME * 0.7)
	motion.tween_property(info, "modulate:a", 1.0, 0.18).set_delay(0.07)
	motion.tween_property(self, "color:a", SHADE.a, OPEN_TIME)

func close_to(target: Rect2, reduced_motion: bool) -> void:
	if closing:
		return
	closing = true
	if reduced_motion:
		dismissed.emit()
		return
	if motion != null:
		motion.kill()
	var landing := _zoom_pose(target)
	motion = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	motion.tween_property(frame, "position", Vector2(landing.x, landing.y), CLOSE_TIME)
	motion.tween_property(frame, "scale", Vector2.ONE * landing.z, CLOSE_TIME)
	motion.tween_property(frame, "modulate:a", 0.06, CLOSE_TIME)
	motion.tween_property(info, "modulate:a", 0.0, 0.10)
	motion.tween_property(self, "color:a", 0.0, CLOSE_TIME)
	motion.chain().tween_callback(dismissed.emit)

func _zoom_pose(target: Rect2) -> Vector3:
	if not target.has_area():
		return Vector3(centered.x, centered.y, 0.86)
	var art_size := Vector2(art.custom_minimum_size.x, frame.size.y - 28)
	var zoom := clampf(minf(target.size.x / art_size.x, target.size.y / art_size.y), 0.09, 0.57)
	var art_center := Vector2(14.0 + art_size.x * 0.5, frame.size.y * 0.5) - frame.pivot_offset
	var point := target.get_center() - frame.pivot_offset - art_center * zoom
	return Vector3(point.x, point.y, zoom)

func _backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if event.pressed:
			dismiss_requested.emit()

func _keep_focus(control: Control) -> void:
	if is_inside_tree() and not is_ancestor_of(control):
		close_button.grab_focus.call_deferred()

func _input(event: InputEvent) -> void:
	var next := event.is_action_pressed("ui_focus_next", false, true)
	if not next and not event.is_action_pressed("ui_focus_prev", false, true):
		return
	var controls: Array[Button] = []
	for control in find_children("*", "Button", true, false):
		if control.is_visible_in_tree() and not control.disabled:
			controls.append(control)
	var current := controls.find(get_viewport().gui_get_focus_owner())
	controls[posmod(current + (1 if next else -1), controls.size())].grab_focus()
	get_viewport().set_input_as_handled()
