extends VBoxContainer

signal trade_requested
signal refresh_requested
signal return_requested

const InventoryPage = preload("res://scripts/presentation/inventory_page.gd")
const Relics = preload("res://scripts/domain/relic_catalog.gd")
const GOLD = Color("dec38e")
const INK = Color("e8e4d1")
const MUTED = Color("a2b3a7")
const FILTERS = {"all": "全部", "item": "补给", "gear": "装备牌", "spell": "法术牌谱", "relic": "遗器"}

var run: RefCounted
var trader: String
var offers: Dictionary
var buying := true
var category := "all"
var selected: Dictionary
var quantity := 1
var voucher := ""

var catalog_title: Label
var grid: GridContainer
var catalog_scroll: ScrollContainer
var empty_catalog: Label
var detail_panel: PanelContainer
var detail_scroll: ScrollContainer
var detail: VBoxContainer
var voucher_picker: OptionButton
var unit_price: Label
var quantity_value: Label
var remaining: Label
var warning: Label
var decrease: Button
var increase: Button
var confirm: Button
var refresh: Button
var filter_buttons := {}
var slot_group := ButtonGroup.new()

func setup(expedition: RefCounted, actor_id: String, stock: Dictionary, width: float, feedback: String, resume: Dictionary) -> void:
	name = "ShopView"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	run = expedition
	trader = actor_id
	offers = stock
	buying = resume.get("buying", true)
	category = resume.get("category", "all")
	var actor: Dictionary = run.actor(trader)

	var header := HBoxContainer.new()
	add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	_label(heading, run.location_name(actor.position), 29, GOLD)
	_label(heading, "交易者 · " + actor.name, 15, MUTED)
	var wallet := PanelContainer.new()
	wallet.add_theme_stylebox_override("panel", _style(Color("1d322d"), Color("887b58"), 8))
	header.add_child(wallet)
	var balance := HBoxContainer.new()
	balance.add_theme_constant_override("separation", 8)
	wallet.add_child(balance)
	_icon(balance, "lamp_coin", Vector2(26, 26))
	var funds := VBoxContainer.new()
	balance.add_child(funds)
	_label(funds, "远征队持有", 13, MUTED)
	_label(funds, "%d 灯铢" % int(run.data.lamp_coins), 19, GOLD).name = "ShopBalance"

	var navigation := HBoxContainer.new()
	add_child(navigation)
	var modes := ButtonGroup.new()
	for direction in [true, false]:
		var tab := _button(navigation, "买入" if direction else "卖出", _change_mode.bind(direction))
		tab.custom_minimum_size.x = 105
		_toggle(tab, modes)
		tab.set_pressed_no_signal(direction == buying)
	navigation.add_spacer(false)
	var cost: int = run.shop_refresh_cost(actor.position)
	refresh = _button(navigation, "刷新货物 · %d 灯铢" % cost, func(): refresh_requested.emit())
	refresh.name = "RefreshShop"
	refresh.disabled = int(run.data.lamp_coins) < cost
	refresh.tooltip_text = ("还差 %d 灯铢。\n" % (cost - int(run.data.lamp_coins)) if refresh.disabled else "") \
		+ "补充补给并更换装备和遗器。每次刷新后，这家店的下次刷新费用增加 1 灯铢。"
	add_child(HSeparator.new())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	add_child(body)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.48
	body.add_child(left)
	var tools := HFlowContainer.new()
	left.add_child(tools)
	catalog_title = _label(tools, "", 17, INK)
	catalog_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var filters := ButtonGroup.new()
	for key in FILTERS:
		var filter := _button(tools, FILTERS[key], _change_category.bind(key))
		filter.custom_minimum_size.y = 32
		_toggle(filter, filters)
		filter_buttons[key] = filter
	catalog_scroll = _scroll(left)
	grid = GridContainer.new()
	grid.name = "ShopGrid"
	grid.columns = 3 if width >= 850 else 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 9)
	grid.add_theme_constant_override("v_separation", 9)
	catalog_scroll.add_child(grid)
	empty_catalog = _label(left, "这个分类暂无物品。", 16, MUTED)
	empty_catalog.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_details(body)

	add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	add_child(footer)
	_button(footer, "返回节点", func(): return_requested.emit())
	if not feedback.is_empty():
		_label(footer, feedback, 15, GOLD, true).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_render_catalog(resume.get("id", ""))

func selection() -> Dictionary:
	return {"buying": buying, "category": category, "id": selected.get("id", "")}

func _build_details(parent: HBoxContainer) -> void:
	detail_panel = PanelContainer.new()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.custom_minimum_size.x = 272
	detail_panel.add_theme_stylebox_override("panel", _style(Color("1b322c"), Color("637768"), 13))
	parent.add_child(detail_panel)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 7)
	detail_panel.add_child(right)
	detail_scroll = _scroll(right)
	detail = VBoxContainer.new()
	detail.name = "ShopDetails"
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(detail)
	warning = _label(right, "", 14, Color("efbd8b"), true)
	warning.name = "ShopWarning"
	voucher_picker = OptionButton.new()
	voucher_picker.name = "ShopVoucher"
	voucher_picker.accessibility_name = "交易凭券"
	voucher_picker.item_selected.connect(func(index: int):
		voucher = str(voucher_picker.get_item_metadata(index))
		_update_order())
	right.add_child(voucher_picker)
	right.add_child(HSeparator.new())

	unit_price = _order_row(right, "单价")
	var row := HBoxContainer.new()
	right.add_child(row)
	_label(row, "数量", 15, MUTED).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	decrease = _button(row, "−", _step.bind(-1))
	decrease.accessibility_name = "减少数量"
	quantity_value = _label(row, "", 17, INK)
	quantity_value.name = "ShopQuantity"
	quantity_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quantity_value.custom_minimum_size.x = 36
	increase = _button(row, "+", _step.bind(1))
	increase.accessibility_name = "增加数量"
	for button in [decrease, increase]:
		button.custom_minimum_size = Vector2(36, 34)
	remaining = _order_row(right, "交易后持有")
	remaining.name = "ShopProjectedBalance"
	confirm = _button(right, "", func(): trade_requested.emit())
	confirm.name = "ConfirmTrade"
	confirm.custom_minimum_size.y = 44
	confirm.add_theme_stylebox_override("normal", _style(Color("dbc28b"), GOLD, 8))
	confirm.add_theme_stylebox_override("hover", _style(Color("eed6a1"), GOLD, 8))
	confirm.add_theme_stylebox_override("pressed", _style(Color("c6aa72"), GOLD, 8))
	for role in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		confirm.add_theme_color_override(role, Color("1b3029"))

func _change_mode(direction: bool) -> void:
	if buying == direction:
		return
	buying = direction
	category = "all"
	_render_catalog(selected.get("id", ""))

func _change_category(key: String) -> void:
	category = key
	_render_catalog(selected.get("id", ""))

func _render_catalog(preferred: String) -> void:
	refresh.visible = buying
	catalog_title.text = "商店库存" if buying else run.actor(trader).name + "的背包"
	for key in filter_buttons:
		filter_buttons[key].set_pressed_no_signal(key == category)
	_clear(grid)
	var candidates: Array = offers[buying].filter(func(entry): return category == "all" or entry.kind == category)
	empty_catalog.visible = candidates.is_empty()
	catalog_scroll.visible = not candidates.is_empty()
	detail_panel.visible = not candidates.is_empty()
	catalog_scroll.scroll_vertical = 0
	var fallback := 0
	for index in candidates.size():
		if candidates[index].id == preferred:
			fallback = index
	for index in candidates.size():
		var button := _card(candidates[index])
		grid.add_child(button)
		if index == fallback:
			button.set_pressed_no_signal(true)
	if candidates.is_empty():
		selected = {}
	else:
		_show_item(candidates[fallback])

func _card(entry: Dictionary) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(100, 152)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.accessibility_name = entry.title
	button.pressed.connect(_show_item.bind(entry))
	_toggle(button, slot_group)
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 2)
	button.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 10
	content.offset_right = -10
	content.offset_top = 6
	content.offset_bottom = -6
	_icon(content, entry.icon, Vector2(0, 66), entry.get("level", 0))
	var title := _label(content, entry.title, 16, INK)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.tooltip_text = entry.title
	_label(content, entry.get("grade", entry.category), 13, MUTED).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var divider := HSeparator.new()
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(divider)
	var meta := HBoxContainer.new()
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(meta)
	_icon(meta, "lamp_coin", Vector2(15, 15))
	var quoted: Dictionary = _quote(entry)
	_label(meta, str(int(quoted.price)), 14, GOLD).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(meta, "%d 件" % int(entry.count), 13, MUTED)
	return button

func _show_item(entry: Dictionary) -> void:
	selected = entry
	quantity = 1
	voucher = ""
	_clear(detail)
	detail_scroll.scroll_vertical = 0
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	detail.add_child(row)
	_icon(row, entry.icon, Vector2(100, 100), entry.get("level", 0))
	var title := VBoxContainer.new()
	title.alignment = BoxContainer.ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	_label(title, "%s · %s" % [entry.category, entry.grade] if entry.has("grade") else entry.category, 14, MUTED, true)
	_label(title, entry.title, 24, GOLD, true)
	var count := "库存 %d 件 · 已持有 %d 件" % [entry.count, entry.owned] if buying else "持有 %d 件" % entry.count
	_label(title, count, 14, MUTED, true)
	_label(detail, entry.effect, 16, INK, true)
	if not entry.story.is_empty():
		_label(detail, entry.story, 14, MUTED, true)
	voucher_picker.clear()
	voucher_picker.add_item("不使用凭券")
	voucher_picker.set_item_metadata(0, "")
	voucher_picker.select(0)
	voucher_picker.visible = voucher_picker.item_count > 1
	_update_order()

func _quote(entry: Dictionary, amount: int = 1, coupon: String = "") -> Dictionary:
	if entry.kind == "spell":
		return {"ok": true, "unit_price": entry.base, "additional_unit_price": entry.base, "price": entry.base}
	return run.shop_quote(entry.base, buying, amount, entry.id if entry.kind == "gear" else "", coupon)

func _update_order() -> void:
	var quote := _quote(selected, 1, voucher)
	var balance := int(run.data.lamp_coins)
	var maximum := int(selected.count)
	var message := ""
	if selected.get("equipped", false):
		maximum = 0
		message = "请先卸下选中的装备。"
	elif buying:
		if quote.unit_price > balance:
			maximum = 0
			message = "还差 %d 灯铢。" % (quote.unit_price - balance)
		else:
			maximum = mini(maximum, 1 + floori(float(balance - quote.unit_price) / quote.additional_unit_price))
	quantity = clampi(quantity, 1, maximum) if maximum > 0 else 0
	if not buying and selected.kind == "relic" and run.has_relic(selected.id) and quantity == selected.count:
		message = "售出最后一件会解除共鸣。"
	warning.text = message
	warning.visible = not message.is_empty()
	var total: int = quote.unit_price + quote.additional_unit_price * (quantity - 1) if quantity > 0 else 0
	unit_price.text = "%d 灯铢" % quote.unit_price
	if quantity > 1 and quote.unit_price != quote.additional_unit_price:
		unit_price.text = "首件 %d · 其余 %d 灯铢" % [quote.unit_price, quote.additional_unit_price]
	quantity_value.text = str(quantity) if quantity > 0 else "—"
	remaining.text = "%d 灯铢" % (balance - total if buying else balance + total) if quantity > 0 else "—"
	decrease.disabled = quantity <= 1
	increase.disabled = quantity >= maximum
	confirm.disabled = quantity == 0
	confirm.text = ("灯铢不足" if buying else "暂不可出售") if quantity == 0 \
		else "%s · %s%d 灯铢" % ["确认买入" if buying else "确认卖出", "" if buying else "+", total]

func _step(delta: int) -> void:
	quantity += delta
	_update_order()

func _order_row(parent: VBoxContainer, title: String) -> Label:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_label(row, title, 15, MUTED).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return _label(row, "", 16, INK)

func _scroll(parent: Container) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	parent.add_child(scroll)
	return scroll

func _toggle(button: Button, group: ButtonGroup) -> void:
	button.toggle_mode = true
	button.button_group = group
	button.add_theme_stylebox_override("normal", _style(Color("203830"), Color("526c5f"), 7))
	button.add_theme_stylebox_override("hover", _style(Color("2c463b"), MUTED, 7))
	button.add_theme_stylebox_override("pressed", _style(Color("384c3e"), GOLD, 7))
	button.add_theme_stylebox_override("hover_pressed", _style(Color("384c3e"), GOLD, 7))

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 38
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _label(parent: Node, text: String, size: int, color: Color, wrap: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _icon(parent: Node, key: String, minimum: Vector2, level: int = 0) -> void:
	var art := InventoryPage.item_image(InventoryPage.icon(key), level)
	art.custom_minimum_size = minimum
	parent.add_child(art)

func _style(background: Color, border: Color, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(margin)
	return style

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
