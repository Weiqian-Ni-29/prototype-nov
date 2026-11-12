extends RefCounted

const InventoryPage = preload("res://scripts/presentation/inventory_page.gd")
const SHIELD = preload("res://assets/ui/shield-badge.svg")
const GOLD = Color("dec38e")
const INK = Color("ede6cf")
const MUTED = Color("b1c3b5")
const GREEN = Color("aad5b6")
const ORANGE = Color("efb58f")

static func box(bg: Color, border: Color, margin: int = 6, radius: int = 6) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	return style

static func label(parent: Node, text: String, size: int = 16, color: Color = INK, wrap: bool = false) -> Label:
	var value := Label.new()
	value.text = text
	value.add_theme_font_size_override("font_size", size)
	value.add_theme_color_override("font_color", color)
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(value)
	return value

static func button(parent: Node, text: String, action: Callable) -> Button:
	var value := Button.new()
	value.text = text
	value.custom_minimum_size.y = 39
	value.pressed.connect(action)
	parent.add_child(value)
	return value

static func accent(button: Button) -> void:
	button.add_theme_stylebox_override("normal", box(Color("dac18c"), GOLD, 8))
	button.add_theme_stylebox_override("hover", box(Color("efd6a1"), GOLD, 8))
	button.add_theme_stylebox_override("pressed", box(Color("bc9f65"), GOLD, 8))
	for role in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(role, Color("1d3329"))

static func panel(parent: Node, color: Color = Color("213b33"), border: Color = Color("657e6c")) -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", box(color, border, 9))
	parent.add_child(frame)
	var content := VBoxContainer.new()
	frame.add_child(content)
	return content

static func scroll(parent: Container) -> ScrollContainer:
	var result := ScrollContainer.new()
	result.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.size_flags_vertical = Control.SIZE_EXPAND_FILL
	result.follow_focus = true
	parent.add_child(result)
	return result

static func art(parent: Node, entry: Dictionary, minimum: Vector2) -> void:
	var texture: Texture2D
	var portrait: String = entry.get("portrait", "")
	if not portrait.is_empty():
		var path := "res://assets/portraits/%s.png" % portrait
		if ResourceLoader.exists(path, "Texture2D"):
			var original := load(path) as Texture2D
			var cropped := AtlasTexture.new()
			cropped.atlas = original
			var size := original.get_size()
			cropped.region = Rect2(size.x * 0.17, 0, size.x * 0.66, size.y * 0.64)
			cropped.filter_clip = true
			texture = cropped
	var icon: String = entry.get("icon", "")
	if icon in ["rain", "sun"]:
		var emblem := label(parent, "☂" if icon == "rain" else "☀", 37, Color("b8def0") if icon == "rain" else GOLD)
		emblem.custom_minimum_size = minimum
		emblem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		emblem.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		return
	if texture == null:
		texture = SHIELD if icon == "shield" else InventoryPage.icon(icon)
	var image := InventoryPage.item_image(texture)
	image.custom_minimum_size = minimum
	parent.add_child(image)

static func clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

static func button_body(button: Button, content: Control, margin: float = 5.0) -> void:
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = margin
	content.offset_top = margin
	content.offset_right = -margin
	content.offset_bottom = -margin
