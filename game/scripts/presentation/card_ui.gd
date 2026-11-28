extends RefCounted

const Cards = preload("res://scripts/domain/card_catalog.gd")
const InventoryPage = preload("res://scripts/presentation/inventory_page.gd")
const SHIELD = preload("res://assets/ui/shield-badge.svg")
const BOW = preload("res://assets/ui/chess-bow.svg")
const CARD_FRAME = preload("res://assets/ui/card-art/frame.png")
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

static func cost_badge(parent: Node, cost: int) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.name = "CardCost"
	badge.custom_minimum_size = Vector2(28, 26)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.add_theme_stylebox_override("panel", box(Color("244f51"), Color("6b9a94"), 2, 5))
	parent.add_child(badge)
	var caption := label(badge, str(cost), 16, Color("d6efea"))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return badge

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

static func art(parent: Node, entry: Dictionary, minimum: Vector2, full_portrait: bool = false) -> Control:
	var texture: Texture2D
	var portrait: String = entry.get("portrait", "")
	if not portrait.is_empty():
		var path := "res://assets/portraits/%s.png" % portrait
		if ResourceLoader.exists(path, "Texture2D"):
			var original := load(path) as Texture2D
			texture = original
			if not full_portrait:
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
	var illustration: String = entry.get("art", icon)
	if texture == null and not illustration.is_empty():
		var path := "res://assets/ui/card-art/%s.webp" % illustration
		if ResourceLoader.exists(path, "Texture2D"):
			texture = load(path) as Texture2D
	if texture == null:
		texture = SHIELD if icon == "shield" else BOW if icon == "chess_bow" else InventoryPage.icon(icon)
	var image := InventoryPage.item_image(texture, int(entry.get("level", 0)))
	image.custom_minimum_size = minimum
	parent.add_child(image)
	return image

static func frame(parent: Control) -> void:
	var border := NinePatchRect.new()
	border.texture = CARD_FRAME
	border.draw_center = false
	border.patch_margin_left = 9
	border.patch_margin_right = 9
	border.patch_margin_top = 9
	border.patch_margin_bottom = 9
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(border)
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	border.set_offset(SIDE_LEFT, 1)
	border.set_offset(SIDE_TOP, 1)
	border.set_offset(SIDE_RIGHT, -1)
	border.set_offset(SIDE_BOTTOM, -1)

static func attack_tag(parent: Node, entry: Dictionary, font_size: int = 12) -> PanelContainer:
	var ranged := Cards.is_ranged(entry)
	var ink := Color("acdce6") if ranged else Color("f0cda2")
	var tag := PanelContainer.new()
	tag.name = "AttackType"
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := box(Color("253c42") if ranged else Color("493729"),
		Color("517783") if ranged else Color("82654b"), 0, 3)
	style.content_margin_left = 3
	style.content_margin_right = 3
	tag.add_theme_stylebox_override("panel", style)
	parent.add_child(tag)
	var caption := label(tag, Cards.attack_type(entry), font_size, ink)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return tag

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
