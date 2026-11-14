extends HBoxContainer

const CardUI = preload("res://scripts/presentation/card_ui.gd")
const GOLD = Color("dec38e")
const INK = Color("e8e4d1")
const MUTED = Color("a2b3a7")

var details: VBoxContainer
var detail_scroll: ScrollContainer

func setup(items: Array[Dictionary], detail_title: String = "物品详情") -> void:
	name = "RewardItems"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 18)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.05
	add_child(left)
	_label(left, "本次获得", 16, MUTED)
	var list := _scroll_column(left)
	list.add_theme_constant_override("separation", 8)

	add_child(VSeparator.new())
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)
	_label(right, detail_title, 16, MUTED)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _style(Color("1b322d"), Color("536c60"), 12))
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(frame)
	details = _scroll_column(frame)
	detail_scroll = details.get_parent()
	details.name = "RewardDetails"
	details.add_theme_constant_override("separation", 8)

	var group := ButtonGroup.new()
	var first: Button
	for item in items:
		var button := _row(item, group)
		list.add_child(button)
		if first == null:
			first = button
	if first != null:
		first.set_pressed_no_signal(true)
		_select(items[0])

func _row(item: Dictionary, group: ButtonGroup) -> Button:
	var button := Button.new()
	button.custom_minimum_size.y = 69
	button.toggle_mode = true
	button.button_group = group
	button.accessibility_name = "%s ×%d" % [item.title, item.count]
	button.add_theme_stylebox_override("normal", _style(Color("2b463e"), Color("587367")))
	button.add_theme_stylebox_override("hover", _style(Color("36544a"), Color("a2b3a7")))
	button.add_theme_stylebox_override("pressed", _style(Color("3c5144"), GOLD))
	button.add_theme_stylebox_override("hover_pressed", _style(Color("3c5144"), GOLD))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	button.add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_top = 7
	row.offset_right = -12
	row.offset_bottom = -7
	CardUI.art(row, item, Vector2(52, 0))
	var caption := VBoxContainer.new()
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.alignment = BoxContainer.ALIGNMENT_CENTER
	caption.add_theme_constant_override("separation", 1)
	row.add_child(caption)
	_label(caption, item.title, 18, INK)
	_label(caption, item.category, 14, MUTED)
	var quantity := _label(row, "×%d" % item.count, 17, GOLD)
	quantity.autowrap_mode = TextServer.AUTOWRAP_OFF
	button.pressed.connect(_select.bind(item))
	return button

func _select(item: Dictionary) -> void:
	for child in details.get_children():
		details.remove_child(child)
		child.queue_free()
	detail_scroll.scroll_vertical = 0
	CardUI.art(details, item, Vector2(0, 108)).name = "RewardIllustration"
	_label(details, item.title, 21, GOLD)
	_label(details, item.effect, 16, INK)
	if not item.story.is_empty():
		details.add_child(HSeparator.new())
		_label(details, item.story, 15, MUTED)

func _scroll_column(parent: Container) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	parent.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	return column

func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _style(background: Color, border: Color, margin: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.set_content_margin_all(margin)
	return style
