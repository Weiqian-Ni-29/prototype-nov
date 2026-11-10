extends Control

const TITLE_COLOR = Color("fff0c5")
const SHADE_COLOR = Color(0.07, 0.14, 0.12, 0.91)

func show_day(day: int, rainy: bool) -> void:
	dismiss()
	var notice := Control.new()
	notice.name = "MapNotice"
	notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice.modulate.a = 0.0
	add_child(notice)
	notice.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var glow := Color(0.65, 0.78, 1.0, 0.15) if rainy else Color(1.0, 0.80, 0.39, 0.17)
	_gradient(notice, Rect2(0.16, 0.117, 0.84, 0.34), glow, Vector2(0.52, 0), Vector2(0.52, 0.86))
	_gradient(notice, Rect2(0.28, 0.163, 0.62, 0.16), SHADE_COLOR, Vector2(0.5, 0.5), Vector2(1, 0.5))
	var caption := VBoxContainer.new()
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.alignment = BoxContainer.ALIGNMENT_CENTER
	caption.add_theme_constant_override("separation", 4)
	notice.add_child(caption)
	_region(caption, Rect2(0.23, 0.163, 0.72, 0.16))
	var title_row := HBoxContainer.new()
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 22)
	caption.add_child(title_row)
	_title_rule(title_row)
	title_row.add_child(_label("第 %d 天" % day, 53, TITLE_COLOR))
	_title_rule(title_row)
	caption.add_child(_label("精力已恢复", 21, Color("e9dec2")))
	var animation := notice.create_tween()
	animation.tween_property(notice, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_SINE)
	animation.tween_interval(0.95)
	animation.tween_property(notice, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_SINE)
	animation.tween_callback(notice.queue_free)

func dismiss() -> void:
	for notice in get_children():
		remove_child(notice)
		notice.queue_free()

func _region(control: Control, region: Rect2) -> void:
	control.set_anchor_and_offset(SIDE_RIGHT, region.end.x, 0)
	control.set_anchor_and_offset(SIDE_BOTTOM, region.end.y, 0)
	control.set_anchor_and_offset(SIDE_LEFT, region.position.x, 0)
	control.set_anchor_and_offset(SIDE_TOP, region.position.y, 0)

func _gradient(parent: Control, region: Rect2, color: Color, center: Vector2, edge: Vector2) -> void:
	var colors := Gradient.new()
	colors.offsets = PackedFloat32Array([0.0, 0.44, 1.0])
	colors.colors = PackedColorArray([color, Color(color, color.a * 0.75), Color(color, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = colors
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = center
	texture.fill_to = edge
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	_region(rect, region)

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.10, 0.08, 0.8))
	label.add_theme_constant_override("outline_size", 3)
	return label

func _title_rule(row: HBoxContainer) -> void:
	var line := ColorRect.new()
	line.color = Color("eac680a0")
	line.custom_minimum_size = Vector2(88, 1)
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
