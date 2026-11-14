extends HBoxContainer

signal item_selected(item_id: String)

const ITEMS = preload("res://assets/ui/inventory-items.png")
const COIN = preload("res://assets/ui/lamp-coin.svg")
const EQUIPMENT_FINISH = preload("res://scripts/presentation/equipment_finish.gdshader")
const ICON_REGIONS = {
	"trail_food": Vector2i(930, 73),
	"trail_blade": Vector2i(1388, 52),
	"padded_coat": Vector2i(57, 492),
	"lamp_charm": Vector2i(501, 492),
}
const GAP = 10
const SLOT_SIZE = 92

var filters := HBoxContainer.new()
var details: VBoxContainer
var selected_id := ""
var grid := GridContainer.new()
var grid_scroll := ScrollContainer.new()
var detail_scroll := ScrollContainer.new()
var group := ButtonGroup.new()
var slot_size := SLOT_SIZE
var normal: StyleBoxFlat
var hover: StyleBoxFlat
var selected: StyleBoxFlat
var empty: StyleBoxFlat

func setup(width: float, accent: Color) -> void:
	add_theme_constant_override("separation", 16)
	var detail_width := clampf(width * 0.32, 156, 280)
	var grid_width := width - detail_width - 33
	# Reserve space for the scrollbar so a full grid fits at the same width as an empty one.
	grid.columns = clampi(floori((grid_width - 18 + GAP) / (SLOT_SIZE + GAP)), 1, 5)
	slot_size = clampi(floori((grid_width - 18 - (grid.columns - 1) * GAP) / grid.columns), 32, SLOT_SIZE)
	grid.name = "InventoryGrid"
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = slot_size * grid.columns + GAP * (grid.columns - 1) + 18
	left.add_theme_constant_override("separation", 12)
	add_child(left)
	filters.hide()
	left.add_child(filters)
	grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_scroll.follow_focus = true
	left.add_child(grid_scroll)
	grid_scroll.add_child(grid)
	var divider := ColorRect.new()
	divider.color = Color("465b4f")
	divider.custom_minimum_size.x = 1
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(divider)
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.custom_minimum_size.x = detail_width
	detail_scroll.follow_focus = true
	add_child(detail_scroll)
	details = VBoxContainer.new()
	details.name = "InventoryDetails"
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 8)
	detail_scroll.add_child(details)
	normal = _slot_style(Color("172923"), Color("465b4f"))
	hover = _slot_style(Color("293e33"), accent.darkened(0.25))
	selected = _slot_style(Color("354839"), accent, 2)
	empty = _slot_style(Color("172923"), Color("3e5046"))

static func icon(key: String) -> Texture2D:
	if key == "lamp_coin":
		return COIN
	if not ICON_REGIONS.has(key):
		var path := "res://assets/ui/item-icons/%s.png" % key
		return load(path) as Texture2D if ResourceLoader.exists(path, "Texture2D") else null
	var texture := AtlasTexture.new()
	texture.atlas = ITEMS
	texture.region = Rect2(Vector2(ICON_REGIONS[key]), Vector2(352, 352))
	texture.filter_clip = true
	return texture

static func item_image(texture: Texture2D, level: int = 0) -> TextureRect:
	var art := TextureRect.new()
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if level > 0 and texture != null:
		var material := ShaderMaterial.new()
		material.shader = EQUIPMENT_FINISH
		material.set_shader_parameter("level", float(level))
		if texture is AtlasTexture:
			var atlas := texture as AtlasTexture
			var atlas_size := atlas.atlas.get_size()
			material.set_shader_parameter("region", Vector4(
				atlas.region.position.x / atlas_size.x, atlas.region.position.y / atlas_size.y,
				atlas.region.size.x / atlas_size.x, atlas.region.size.y / atlas_size.y))
		art.material = material
	return art

func set_items(entries: Array[Dictionary], selection: String = "") -> void:
	_clear(grid)
	var selected_slot: Button
	for entry in entries:
		var item_id: String = entry.id
		var slot := Button.new()
		slot.custom_minimum_size = Vector2(slot_size, slot_size)
		slot.tooltip_text = entry.title
		slot.accessibility_name = entry.title
		slot.toggle_mode = true
		slot.button_group = group
		var texture := icon(entry.icon)
		slot.expand_icon = true
		slot.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var caption: String = entry.get("caption", "")
		slot.add_theme_constant_override("icon_max_width", slot_size - (28 if not caption.is_empty() else 14))
		slot.add_theme_stylebox_override("normal", normal)
		slot.add_theme_stylebox_override("hover", hover)
		slot.add_theme_stylebox_override("pressed", selected)
		slot.add_theme_stylebox_override("hover_pressed", selected)
		slot.add_theme_stylebox_override("focus", _slot_style(Color.TRANSPARENT, Color("e8e4d1"), 2))
		grid.add_child(slot)
		var level: int = entry.get("level", 0)
		if level > 0:
			var art := item_image(texture, level)
			slot.add_child(art)
			art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			art.offset_left = 7
			art.offset_right = -7
			art.offset_top = 5
			art.offset_bottom = -23
		else:
			slot.icon = texture
		var count: int = entry.get("count", 0)
		var badge: String = entry.get("badge", "")
		var count_width := 0.0
		if count > 0:
			var quantity := _slot_label(slot, str(count), 15)
			count_width = quantity.get_minimum_size().x
			quantity.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_KEEP_SIZE)
			quantity.offset_right = -6
			quantity.offset_bottom = -4
			quantity.offset_left = -6 - count_width
			quantity.offset_top = -4 - quantity.get_minimum_size().y
		if not caption.is_empty():
			slot.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			var name_label := _slot_label(slot, caption, 13)
			name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			name_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_KEEP_SIZE)
			name_label.offset_left = 6
			name_label.offset_right = -6 if count_width == 0 else -10 - count_width
			name_label.offset_bottom = -4
			name_label.offset_top = -4 - name_label.get_minimum_size().y
		if not badge.is_empty():
			var status := _slot_label(slot, badge, 11)
			status.add_theme_color_override("font_color", Color("dec38e"))
			status.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_KEEP_SIZE)
			status.offset_right = -6
			status.offset_left = -6 - status.get_minimum_size().x
			status.offset_top = 3
			status.offset_bottom = 3 + status.get_minimum_size().y
		slot.pressed.connect(_select.bind(item_id))
		if item_id == selection:
			selected_slot = slot
	var visible_slots := maxi(3, ceili(float(entries.size()) / grid.columns)) * grid.columns
	for i in range(entries.size(), visible_slots):
		var blank := Panel.new()
		blank.custom_minimum_size = Vector2(slot_size, slot_size)
		blank.mouse_filter = Control.MOUSE_FILTER_IGNORE
		blank.add_theme_stylebox_override("panel", empty)
		grid.add_child(blank)
	grid_scroll.scroll_vertical = 0
	if selected_slot != null:
		selected_slot.set_pressed_no_signal(true)
		_reveal_slot(selected_slot)
	_select(selection if selected_slot != null else "")

func _reveal_slot(slot: Button) -> void:
	await get_tree().process_frame
	if is_instance_valid(slot) and slot.get_parent() == grid:
		grid_scroll.ensure_control_visible(slot)

func _select(item_id: String) -> void:
	selected_id = item_id
	_clear(details)
	detail_scroll.scroll_vertical = 0
	item_selected.emit(item_id)

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _slot_label(slot: Button, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_shadow_color", Color("101a15"))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(label)
	return label

func _slot_style(background: Color, border: Color, border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(7)
	return style
