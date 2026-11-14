extends RefCounted

const Cards = preload("res://scripts/domain/card_catalog.gd")
const InventoryPage = preload("res://scripts/presentation/inventory_page.gd")
const SHIELD = preload("res://assets/ui/shield-badge.svg")
const ELEMENT_ICONS = {
	"earth": preload("res://assets/ui/chess-elements/earth.svg"),
	"fire": preload("res://assets/ui/chess-elements/fire.svg"),
	"water": preload("res://assets/ui/chess-elements/water.svg"),
	"ice": preload("res://assets/ui/chess-elements/ice.svg"),
	"wind": preload("res://assets/ui/chess-elements/wind.svg"),
	"lightning": preload("res://assets/ui/chess-elements/lightning.svg"),
}
const ELEMENT_SIZE = 24
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

static func add_element_icon(parent: Node, element: String) -> void:
	if not ELEMENT_ICONS.has(element):
		return
	var badge := TextureRect.new()
	badge.name = "ElementIcon"
	badge.texture = ELEMENT_ICONS[element]
	badge.custom_minimum_size = Vector2(ELEMENT_SIZE, ELEMENT_SIZE)
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.accessibility_name = Cards.ELEMENTS[element] + "属性"
	parent.add_child(badge)

static func element_summary(parent: Node, element: String, text: String, size: int = 14, color: Color = MUTED) -> void:
	if not ELEMENT_ICONS.has(element):
		label(parent, text, size, color, true)
		return
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	add_element_icon(row, element)
	var summary := label(row, text, size, color, true)
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

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

static func art(parent: Node, entry: Dictionary, minimum: Vector2) -> Control:
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
	var enemy: String = entry.get("enemy_art", "")
	if texture == null and not enemy.is_empty():
		var art_path := "res://assets/portraits/enemies/%s.png" % enemy
		if ResourceLoader.exists(art_path, "Texture2D"):
			texture = load(art_path) as Texture2D
	var icon: String = entry.get("icon", "")
	if icon in ["rain", "sun"]:
		var emblem := label(parent, "☂" if icon == "rain" else "☀", 37, Color("b8def0") if icon == "rain" else GOLD)
		emblem.custom_minimum_size = minimum
		emblem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		emblem.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		return emblem
	if texture == null:
		texture = SHIELD if icon == "shield" else InventoryPage.icon(icon)
	var image := InventoryPage.item_image(texture, int(entry.get("level", 0)))
	image.custom_minimum_size = minimum
	parent.add_child(image)
	return image

static func clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

static func button_body(button: Control, content: Control, margin: float = 5.0) -> void:
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = margin
	content.offset_top = margin
	content.offset_right = -margin
	content.offset_bottom = -margin
