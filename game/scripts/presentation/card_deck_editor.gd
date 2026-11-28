extends VBoxContainer

signal completed(deck: Array)
signal cancelled

const Relics = preload("res://scripts/domain/relic_catalog.gd")
const Cards = preload("res://scripts/domain/card_catalog.gd")
const UI = preload("res://scripts/presentation/card_ui.gd")
const DetailView = preload("res://scripts/presentation/deck_card_detail.gd")
const Transfer = preload("res://scripts/presentation/deck_card_transfer.gd")
const COST_LABELS = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10+"]
const CARD_SIZE := Vector2(160, 224)
const CARD_GAP := 8
const WIDE_LAYOUT := 1100.0
const DOUBLE_CLICK_TIME := 0.30
const DRAG_THRESHOLD := 8
const DECK_HINT := "拖入牌表加入 · 拖回收藏移除"

class CardButton extends Button:
	var card_id: String
	var from_deck: bool

class CardDrag:
	var id: String
	var from_deck: bool

	func _init(card_id: String, from_list: bool) -> void:
		id = card_id
		from_deck = from_list

var available: Array[String]
var roster: Dictionary
var deck: Array
var selected := ""
var kind := "all"
var type_buttons := {}
var cost_filter := 0
var cost_buttons: Array[Button] = []
var search: LineEdit
var count_label: Label
var collection_scroll: ScrollContainer
var grid: GridContainer
var card_width := CARD_SIZE.x
var empty_collection: Label
var detail: DetailView
var detail_id := ""
var detail_source: CardButton
var add_button: Button
var remove_button: Button
var deck_scroll: ScrollContainer
var slots: VBoxContainer
var deck_title: Label
var cost_bars: Array[ProgressBar] = []
var cost_counts: Array[Label] = []
var total: Label
var done: Button
var guidance: Label
var error: Label
var hint: Label
var in_encounter := false
var run_model: RefCounted
var reduce_motion := false
var click_timer: Timer
var pending_card: CardButton
var pressed_card: CardButton
var second_press := false
var active_drag: CardDrag
var drop_outline: Panel

func setup(actors: Dictionary, current: Array, encounter: bool, opponent: String = "",
		expedition: RefCounted = null, back_label: String = "", reduced_motion: bool = false) -> void:
	name = "CardDeckEditor"
	deck = current.duplicate()
	roster = actors
	run_model = expedition
	available = Cards.collection(actors, _card_state())
	in_encounter = encounter
	reduce_motion = reduced_motion
	var viewport := get_viewport()
	var previous_threshold := viewport.get_drag_threshold()
	viewport.set_drag_threshold(DRAG_THRESHOLD)
	tree_exiting.connect(func(): viewport.set_drag_threshold(previous_threshold), CONNECT_ONE_SHOT)
	click_timer = Timer.new()
	click_timer.one_shot = true
	click_timer.wait_time = DOUBLE_CLICK_TIME
	click_timer.timeout.connect(_show_pending_detail)
	add_child(click_timer)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	var heading := HBoxContainer.new()
	add_child(heading)
	UI.label(heading, "卡组编辑", 29, UI.GOLD).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.label(heading, "洗牌后抽 3 张 · 之后每回合抽 1 张", 16, UI.MUTED)
	UI.label(self, "单击查看大图 · 双击或拖拽增减卡牌", 14, UI.MUTED)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	add_child(body)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)
	_build_collection(left)
	var right := UI.panel(body)
	var right_frame := right.get_parent() as Control
	_build_deck_panel(right, opponent, back_label)
	resized.connect(_fit_columns.bind(right_frame))
	_fit_columns(right_frame)
	_filter()
	_render_deck()
	search.grab_focus()

func _build_collection(left: VBoxContainer) -> void:
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	left.add_child(controls)
	count_label = UI.label(controls, "卡片收藏", 18, UI.GOLD)
	search = LineEdit.new()
	search.placeholder_text = "搜索卡名、效果或攻击类型"
	search.accessibility_name = search.placeholder_text
	search.custom_minimum_size.x = 150
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(_value): _filter())
	controls.add_child(search)
	var filters := HBoxContainer.new()
	left.add_child(filters)
	for id in Cards.KINDS:
		if id == "weapon":
			continue
		var button := UI.button(filters, Cards.KINDS[id], _select_kind.bind(id))
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		type_buttons[id] = button
	collection_scroll = UI.scroll(left)
	collection_scroll.name = "CollectionDropArea"
	collection_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	collection_scroll.resized.connect(_fit_card_width)
	_bind_drop_zone(collection_scroll, false)
	var collection := VBoxContainer.new()
	collection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	collection_scroll.add_child(collection)
	grid = GridContainer.new()
	grid.name = "CardCollection"
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", CARD_GAP)
	grid.add_theme_constant_override("v_separation", CARD_GAP)
	collection.add_child(grid)
	empty_collection = UI.label(collection, "没有符合条件的卡牌", 17, UI.MUTED)
	empty_collection.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var costs := HBoxContainer.new()
	costs.add_theme_constant_override("separation", 6)
	left.add_child(costs)
	UI.label(costs, "费用", 16, UI.GOLD)
	for bucket in COST_LABELS.size() + 1:
		var text: String = "全部" if bucket == 0 else COST_LABELS[bucket - 1]
		var button := UI.button(costs, text, _select_cost.bind(bucket))
		button.name = "CostFilter%d" % bucket
		button.accessibility_name = "全部费用" if bucket == 0 else _cost_bucket_name(bucket - 1)
		button.toggle_mode = true
		button.custom_minimum_size.x = 42
		cost_buttons.append(button)
	var spacer := costs.add_spacer(false)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.button(costs, "清空筛选", _clear_filters).name = "ClearCardFilters"

func _build_deck_panel(right: VBoxContainer, opponent: String, back_label: String) -> void:
	var heading := HBoxContainer.new()
	right.add_child(heading)
	deck_title = UI.label(heading, "远征卡组", 21, UI.GOLD)
	deck_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_title.focus_mode = Control.FOCUS_CLICK
	total = UI.label(heading, "", 17, UI.GOLD)
	total.name = "DeckCount"
	_loadout(right, {"portrait": "hero"}, "旅人", "主战者 · 开局站场")
	if run_model != null and run_model.data.relic_effect_flags.has("life_seed_applied"):
		_loadout(right, {"icon": "life_seed"}, "生命之种", "己方战棋生命上限 +1")
	if run_model != null and in_encounter:
		_preparation_controls(right)
	if in_encounter and not opponent.is_empty():
		UI.label(right, "敌方主战者 · " + opponent, 15, UI.ORANGE, true)
	right.add_child(HSeparator.new())
	deck_scroll = UI.scroll(right)
	deck_scroll.name = "DeckDropArea"
	deck_scroll.custom_minimum_size.y = 44
	_bind_drop_zone(deck_scroll, true)
	slots = VBoxContainer.new()
	slots.mouse_filter = Control.MOUSE_FILTER_PASS
	slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_scroll.add_child(slots)
	right.add_child(HSeparator.new())
	_build_cost_distribution(right)
	guidance = UI.label(right, "", 14, UI.MUTED, true)
	var status := VBoxContainer.new()
	right.add_child(status)
	hint = UI.label(status, DECK_HINT, 14, UI.MUTED, true)
	error = UI.label(status, "", 14, UI.ORANGE, true)
	error.name = "DeckFeedback"
	error.hide()
	var actions := HBoxContainer.new()
	right.add_child(actions)
	var back := UI.button(actions, "返回远征" if back_label.is_empty() else back_label, func(): cancelled.emit())
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done = UI.button(actions, "开始战斗" if in_encounter else "保存卡组", func(): completed.emit(deck.duplicate()))
	done.name = "ConfirmCardDeck"
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.accent(done)

func _build_cost_distribution(parent: VBoxContainer) -> void:
	UI.label(parent, "费用分布", 16, UI.GOLD)
	var chart := HBoxContainer.new()
	chart.add_theme_constant_override("separation", 3)
	parent.add_child(chart)
	for index in COST_LABELS.size():
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 2)
		chart.add_child(column)
		var count := UI.label(column, "", 12)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost_counts.append(count)
		var bar := ProgressBar.new()
		bar.name = "DeckCostBar%d" % (index + 1)
		bar.show_percentage = false
		bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.custom_minimum_size = Vector2(14, 34)
		bar.add_theme_stylebox_override("background", UI.box(Color("162c27"), Color("4d6a5f"), 0, 3))
		bar.add_theme_stylebox_override("fill", UI.box(Color("5f9b8e"), Color("88bdb0"), 0, 3))
		column.add_child(bar)
		cost_bars.append(bar)
		UI.label(column, COST_LABELS[index], 13, UI.MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _fit_columns(right_frame: Control) -> void:
	var wide := size.x >= WIDE_LAYOUT
	right_frame.custom_minimum_size.x = 300 if wide else 240
	grid.columns = 4 if wide else 3
	_fit_card_width()

func _fit_card_width() -> void:
	var gutter := collection_scroll.get_v_scroll_bar().get_combined_minimum_size().x
	var usable := collection_scroll.size.x - gutter - (grid.columns - 1) * CARD_GAP
	card_width = maxf(CARD_SIZE.x, floorf(usable / grid.columns))
	for tile in grid.get_children():
		tile.custom_minimum_size.x = card_width

func _card_state() -> Dictionary:
	return {} if run_model == null else run_model.data

func _preparation_controls(parent: VBoxContainer) -> void:
	var preps: Array = run_model.preparation_options()
	if not preps.is_empty():
		var choices := OptionButton.new()
		choices.name = "DeckPreparation"
		choices.add_item("战前准备 · 不携带")
		choices.set_item_metadata(0, "")
		for id in preps:
			var i := choices.item_count
			choices.add_item(Relics.DATA[id].name)
			choices.set_item_metadata(i, id)
			choices.set_item_tooltip(i, Relics.current_effect(id))
			if id == run_model.prepared_relic:
				choices.select(i)
		var detail_label := UI.label(parent, "", 13, UI.MUTED, true)
		parent.add_child(choices)
		choices.item_selected.connect(func(index: int):
			run_model.prepared_relic = choices.get_item_metadata(index)
			detail_label.text = Relics.current_effect(run_model.prepared_relic))
		detail_label.text = Relics.current_effect(run_model.prepared_relic)

func show_error(message: String) -> void:
	hint.hide()
	error.text = message
	error.show()
	if detail != null:
		detail.feedback.add_theme_color_override("font_color", UI.ORANGE)
		detail.feedback.text = message
		detail.feedback.show()

func _show_hint(message: String, tint: Color = UI.MUTED) -> void:
	error.hide()
	hint.add_theme_color_override("font_color", tint)
	hint.text = message
	hint.show()

func _loadout(parent: VBoxContainer, art: Dictionary, title: String, hint: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	UI.art(row, art, Vector2(35, 39))
	var text := VBoxContainer.new()
	row.add_child(text)
	UI.label(text, title, 15, UI.GOLD)
	UI.label(text, hint, 13, UI.MUTED)

func _select_kind(value: String) -> void:
	kind = value
	_filter()

func _select_cost(value: int) -> void:
	cost_filter = value
	_filter()

func _clear_filters() -> void:
	kind = "all"
	cost_filter = 0
	search.clear()
	_filter()

func _cost_bucket(cost: int) -> int:
	return mini(cost, COST_LABELS.size())

func _cost_bucket_name(index: int) -> String:
	return "10 费及以上" if index == COST_LABELS.size() - 1 else "%s 费" % COST_LABELS[index]

func _filter() -> void:
	for id in type_buttons:
		type_buttons[id].set_pressed_no_signal(id == kind)
	for bucket in cost_buttons.size():
		cost_buttons[bucket].set_pressed_no_signal(bucket == cost_filter)
	var query := search.text.strip_edges().to_lower()
	var results: Array[String] = []
	for id in available:
		var card := Cards.owned_definition(id, roster, _card_state())
		if (kind == "all" or card.kind == kind) \
				and (cost_filter == 0 or cost_filter == _cost_bucket(card.cost)) \
				and (query.is_empty() or query in ("%s %s %s" % [card.name, card.trait, Cards.card_attack_type(card)]).to_lower()):
			results.append(id)
	if selected not in results:
		selected = results[0] if not results.is_empty() else ""
	count_label.text = "卡片收藏  %d 张" % results.size()
	empty_collection.visible = results.is_empty()
	UI.clear(grid)
	for id in results:
		_add_tile(id)

func _add_tile(id: String) -> void:
	var card := Cards.owned_definition(id, roster, _card_state())
	var button := _card_button(grid, id, false)
	button.name = "Collection_" + _node_suffix(id)
	button.custom_minimum_size = Vector2(card_width, CARD_SIZE.y)
	button.toggle_mode = true
	button.set_pressed_no_signal(id == selected)
	var tint: Color = {"partner": Color("294639"), "weapon": Color("494033"), "equipment": Color("494033"), "defense": Color("344b50"), "spell": Color("3a4659")}[card.kind]
	button.add_theme_stylebox_override("normal", UI.box(tint, Color("687f70")))
	button.add_theme_stylebox_override("hover", UI.box(tint.lightened(0.09), UI.GOLD))
	var active := UI.box(tint.lightened(0.06), UI.GOLD)
	active.set_border_width_all(2)
	button.add_theme_stylebox_override("pressed", active)
	button.add_theme_stylebox_override("hover_pressed", active)
	_render_tile_face(button, id, card)

func _card_button(parent: Control, id: String, from_deck: bool) -> CardButton:
	var button := CardButton.new()
	button.card_id = id
	button.from_deck = from_deck
	button.custom_minimum_size.y = 39
	button.set_drag_forwarding(_drag_card.bind(button), _can_drop_card.bind(from_deck),
		_drop_card.bind(from_deck, button))
	button.gui_input.connect(_press_card.bind(button))
	button.pressed.connect(_open_detail.bind(button))
	parent.add_child(button)
	return button

func _render_tile_face(button: Button, id: String, card: Dictionary) -> void:
	UI.clear(button)
	UI.frame(button)
	var content := VBoxContainer.new()
	content.name = "Face"
	UI.button_body(button, content, 8)
	content.add_theme_constant_override("separation", 4)
	var art := UI.art(content, card, Vector2(0, 132)) as TextureRect
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if card.has("portrait"):
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.clip_contents = true
	var badge := UI.cost_badge(art, card.cost)
	badge.position = Vector2(3, 3)
	UI.label(content, card.name, 17).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var footer := HBoxContainer.new()
	footer.name = "Status"
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(footer)
	var category: String = Cards.KINDS[card.kind]
	UI.label(footer, category, 14, UI.MUTED).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.label(footer, "", 14, UI.GOLD).name = "DeckCopies"
	button.tooltip_text = "单击查看 %s · 双击加入" % card.name
	_update_tile_quantity(button, id, card)

func _update_tile_quantity(button: Button, id: String, card: Dictionary) -> void:
	var count := deck.count(id)
	var limit := Cards.limit(id)
	var copies := button.get_node("Face/Status/DeckCopies") as Label
	copies.text = "%d/%d" % [count, limit]
	copies.add_theme_color_override("font_color", UI.ORANGE if count >= limit else UI.GOLD)
	button.accessibility_name = "%s，%d 费，已入组 %d 张，上限 %d 张。查看详情" % [card.name, card.cost, count, limit]

func _node_suffix(id: String) -> String:
	return id.replace(":", "_")

func _tile(id: String) -> CardButton:
	return grid.get_node_or_null("Collection_" + _node_suffix(id)) as CardButton

func _deck_card(id: String) -> CardButton:
	return slots.get_node_or_null("Row_" + _node_suffix(id) + "/Card") as CardButton

func _choose(id: String) -> void:
	var tile := _tile(id)
	if tile == null:
		return
	var previous := _tile(selected)
	if previous != null:
		previous.set_pressed_no_signal(false)
	selected = id
	tile.set_pressed_no_signal(true)

func _open_detail(source: CardButton) -> void:
	if detail != null or not is_instance_valid(source) or not source.is_inside_tree():
		return
	_clear_pending()
	detail_source = source
	detail_id = source.card_id
	if not source.from_deck:
		_choose(detail_id)
	var origin := _visible_card_rect(source)
	detail = DetailView.new()
	detail.top_level = true
	detail.z_index = 30
	detail.dismiss_requested.connect(_close_detail)
	detail.dismissed.connect(_finish_detail)
	add_child(detail)
	_render_detail()
	detail.open_from(origin, reduce_motion)

func _close_detail() -> void:
	var target := _visible_card_rect(detail_source)
	if not target.has_area():
		var fallback := _tile(detail_id)
		target = _visible_card_rect(fallback)
		if target.has_area():
			detail_source = fallback
	detail.close_to(target, reduce_motion)

func _finish_detail() -> void:
	var closed := detail
	detail = null
	remove_child(closed)
	closed.queue_free()
	add_button = null
	remove_button = null
	if is_instance_valid(detail_source) and detail_source.is_inside_tree():
		_focus_without_scrolling(detail_source)
	else:
		deck_title.grab_focus()
	detail_source = null
	detail_id = ""

func _render_detail() -> void:
	var card := Cards.owned_definition(detail_id, roster, _card_state())
	detail.show_art(card)
	detail.heading.text = card.name
	UI.clear(detail.meta)
	UI.clear(detail.description)
	UI.clear(detail.actions)
	UI.cost_badge(detail.meta, card.cost)
	UI.label(detail.meta, Cards.KINDS[card.kind], 15, UI.MUTED)
	if not Cards.card_attack_type(card).is_empty():
		UI.attack_tag(detail.meta, card)
	if card.kind == "partner":
		UI.label(detail.description, Cards.stats(card), 16, UI.MUTED, true)
	UI.label(detail.description, "卡牌效果", 16, UI.GOLD)
	UI.label(detail.description, card.trait, 17, UI.INK, true)
	var copies := UI.label(detail.description, "", 15, UI.MUTED)
	copies.name = "DetailCopies"
	if card.kind == "equipment" and run_model != null:
		var uid := detail_id.trim_prefix("gear:")
		var owner: String = run_model.data.gear_instances[uid].owner.id
		var quote: Dictionary = run_model.enhancement_quote(owner, uid)
		if quote.ok:
			var upgrade := UI.button(detail.description, "强化至 +%d · %d 灯铢" % [int(card.level) + 1, int(quote.price)],
				_enhance_card.bind(detail_id, owner, uid))
			upgrade.name = "EnhanceDeckCard"
			upgrade.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			upgrade.disabled = int(quote.price) > int(run_model.data.lamp_coins)
			if upgrade.disabled:
				upgrade.tooltip_text = "灯铢不足"
		else:
			UI.label(detail.description, quote.message, 14, UI.MUTED, true)
	add_button = UI.button(detail.actions, "", func():
		if not detail.closing:
			_add_card(detail_id))
	add_button.name = "AddDeckCard"
	add_button.custom_minimum_size.x = 142
	UI.accent(add_button)
	remove_button = UI.button(detail.actions, "− 移除 1 张", func():
		if not detail.closing:
			_remove_card(detail_id, false))
	remove_button.name = "RemoveDetailCard"
	_update_detail_copies()

func _update_detail_copies() -> void:
	if detail == null:
		return
	var count := deck.count(detail_id)
	var limit := Cards.limit(detail_id)
	var restore_add := add_button.has_focus()
	var restore_remove := remove_button.has_focus()
	add_button.disabled = count >= limit
	add_button.text = "已达同名上限" if add_button.disabled else "＋ 加入牌组"
	remove_button.disabled = count == 0
	detail.description.get_node("DetailCopies").text = "卡组中 %d 张 · 同名上限 %d 张" % [count, limit]
	if restore_add and add_button.disabled:
		remove_button.grab_focus()
	if restore_remove and remove_button.disabled:
		add_button.grab_focus()

func _enhance_card(id: String, owner: String, uid: String) -> void:
	if detail.closing:
		return
	var result: Dictionary = run_model.enhance_card(owner, uid)
	if not result.ok:
		show_error(result.message)
		return
	var tile := _tile(id)
	if tile != null:
		_render_tile_face(tile, id, Cards.owned_definition(id, roster, _card_state()))
	_render_detail()
	_render_deck()
	_show_hint(result.message, UI.GREEN)
	detail.feedback.add_theme_color_override("font_color", UI.GREEN)
	detail.feedback.text = result.message
	detail.feedback.show()
	var upgrade := detail.find_child("EnhanceDeckCard", true, false) as Button
	if upgrade != null and not upgrade.disabled:
		upgrade.grab_focus()
	else:
		detail.close_button.grab_focus()

func _press_card(event: InputEvent, button: CardButton) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return
	button.accept_event()
	if event.pressed:
		_focus_without_scrolling(button)
		second_press = pending_card == button
		_clear_pending()
		pressed_card = button
	elif pressed_card == button:
		pressed_card = null
		var source := _visible_card_rect(button)
		if not source.has_point(button.get_global_transform() * event.position):
			return
		if second_press:
			_change_by_gesture(button.card_id, not button.from_deck, source.get_center(), false)
		else:
			pending_card = button
			click_timer.start()

func _input(event: InputEvent) -> void:
	if click_timer == null:
		return
	var viewport := get_viewport()
	if event.is_action_pressed("ui_cancel"):
		if detail != null:
			_close_detail()
		elif active_drag != null:
			viewport.gui_cancel_drag()
		elif is_instance_valid(pending_card) or is_instance_valid(pressed_card):
			_clear_pending()
			pressed_card = null
		else:
			return
		viewport.set_input_as_handled()
		return
	if active_drag != null and event is InputEventMouseMotion:
		_highlight_drop(event.position)
	if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
			and is_instance_valid(pending_card) and not _visible_card_rect(pending_card).has_point(event.position)):
		_clear_pending()

func _clear_pending() -> void:
	pending_card = null
	click_timer.stop()

func _show_pending_detail() -> void:
	var source := pending_card
	pending_card = null
	_open_detail(source)

func _visible_card_rect(button: CardButton) -> Rect2:
	if not is_instance_valid(button) or not button.is_visible_in_tree():
		return Rect2()
	var clip := deck_scroll if button.from_deck else collection_scroll
	return button.get_global_rect().intersection(clip.get_global_rect()).intersection(get_viewport_rect())

func _focus_without_scrolling(control: Control) -> void:
	var scroll := collection_scroll if collection_scroll.is_ancestor_of(control) else deck_scroll
	var follow := scroll.follow_focus
	scroll.follow_focus = false
	control.grab_focus()
	scroll.follow_focus = follow

func _bind_drop_zone(zone: Control, into_deck: bool) -> void:
	zone.set_drag_forwarding(Callable(), _can_drop_card.bind(into_deck), _drop_card.bind(into_deck, zone))

func _drag_card(_position: Vector2, button: CardButton) -> Variant:
	pressed_card = null
	_clear_pending()
	var card := Cards.owned_definition(button.card_id, roster, _card_state())
	var tint := Transfer.REMOVE_LIGHT if button.from_deck else Transfer.ADD_LIGHT
	button.set_drag_preview(Transfer.card_face(card, tint, get_theme_font("font")))
	active_drag = CardDrag.new(button.card_id, button.from_deck)
	drop_outline = Panel.new()
	drop_outline.top_level = true
	drop_outline.z_index = 5
	drop_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(drop_outline)
	_highlight_drop(get_global_mouse_position())
	return active_drag

func _highlight_drop(mouse: Vector2) -> void:
	var zone := collection_scroll if active_drag.from_deck else deck_scroll
	var rect := zone.get_global_rect()
	var hover := rect.has_point(mouse)
	var blocked := not active_drag.from_deck and deck.count(active_drag.id) >= Cards.limit(active_drag.id)
	var tint := UI.ORANGE if blocked else Transfer.REMOVE_LIGHT if active_drag.from_deck else Transfer.ADD_LIGHT
	drop_outline.position = rect.position
	drop_outline.size = rect.size
	var style := UI.box(Color(tint, 0.10 if hover else 0.04), Color(tint, 0.94 if hover else 0.65), 0, 6)
	style.set_border_width_all(2 if hover else 1)
	drop_outline.add_theme_stylebox_override("panel", style)

func _can_drop_card(_position: Vector2, data: Variant, into_deck: bool) -> bool:
	return data is CardDrag and data.from_deck != into_deck and data.id in available

func _drop_card(at: Vector2, data: CardDrag, into_deck: bool, zone: Control) -> void:
	_change_by_gesture(data.id, into_deck, zone.get_global_transform() * at, true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and click_timer != null:
		pressed_card = null
		_clear_pending()
		if active_drag != null:
			get_viewport().gui_cancel_drag()
	if what == NOTIFICATION_DRAG_END and active_drag != null:
		var returning := active_drag.from_deck
		active_drag = null
		remove_child(drop_outline)
		drop_outline.queue_free()
		drop_outline = null
		if not get_viewport().gui_is_drag_successful():
			show_error("已取消拖放。拖回左侧收藏区可移除。" if returning else "已取消拖放。拖到右侧牌表可加入。")

func _change_by_gesture(id: String, adding: bool, origin: Vector2, dropped: bool) -> void:
	var changed := _add_card(id) if adding else _remove_card(id)
	if not changed:
		return
	await get_tree().process_frame
	if not is_inside_tree() or is_queued_for_deletion():
		return
	var button := _deck_card(id) if adding else _tile(id)
	var destination := _visible_card_rect(button)
	if not destination.has_area():
		var zone := deck_scroll if adding else collection_scroll
		destination = zone.get_global_rect().intersection(get_viewport_rect())
	if not destination.has_area():
		return
	var effect := Transfer.new()
	effect.top_level = true
	effect.z_index = 8
	effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(effect)
	effect.play(Cards.owned_definition(id, roster, _card_state()), origin, destination, adding, dropped, reduce_motion)

func _add_card(id: String) -> bool:
	if deck.count(id) >= Cards.limit(id):
		show_error("这张牌已达同名上限。")
		return false
	deck.append(id)
	_refresh_deck(id, true)
	return true

func _remove_card(id: String, focus_list: bool = true) -> bool:
	var index := deck.find(id)
	if index < 0:
		return false
	var row := _deck_card(id)
	var row_index := row.get_parent().get_index() if row != null else 0
	var focused := get_viewport().gui_get_focus_owner()
	var use_minus := focused != null and str(focused.name).begins_with("Remove_")
	deck.remove_at(index)
	_refresh_deck(id, false)
	if focus_list:
		var next := slots.get_child(mini(row_index, slots.get_child_count() - 1)) as Control
		var target := (next.get_child(1 if use_minus else 0) as Control) if next is HBoxContainer else deck_title
		_focus_without_scrolling(target)
	return true

func _refresh_deck(id: String, added: bool) -> void:
	var card := Cards.owned_definition(id, roster, _card_state())
	var button := _tile(id)
	if button != null:
		_update_tile_quantity(button, id, card)
	if detail != null:
		detail.feedback.hide()
	_update_detail_copies()
	_render_deck()
	_show_hint("%s 1 张「%s」" % ["已加入" if added else "已移除", card.name], UI.GREEN)

func _render_deck() -> void:
	total.text = "%d 张" % deck.size()
	var missing := Cards.MIN_DECK_SIZE - deck.size()
	guidance.text = "已满足出战条件 · 至少 %d 张" % Cards.MIN_DECK_SIZE
	if missing > 0:
		guidance.text = ("再加入 %d 张即可出战。" if in_encounter else "当前为草稿，再加入 %d 张即可出战。") % missing
	done.disabled = in_encounter and missing > 0
	var scroll := deck_scroll.scroll_vertical
	var counts := {}
	for id in deck:
		counts[id] = int(counts.get(id, 0)) + 1
	var entries: Array[Dictionary] = []
	for index in available.size():
		var id := available[index]
		if counts.has(id):
			var card := Cards.owned_definition(id, roster, _card_state())
			entries.append({"id": id, "card": card, "order": index})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.order < b.order if a.card.cost == b.card.cost else a.card.cost < b.card.cost)
	var distribution: Array[int] = []
	distribution.resize(COST_LABELS.size())
	distribution.fill(0)
	for child in slots.get_children():
		if not counts.has(child.get_meta("card_id", "")):
			slots.remove_child(child)
			child.queue_free()
	for index in entries.size():
		var entry := entries[index]
		var count: int = counts[entry.id]
		distribution[_cost_bucket(entry.card.cost) - 1] += count
		var button := _deck_card(entry.id)
		if button == null:
			button = _add_deck_row(entry.id)
		slots.move_child(button.get_parent(), index)
		_update_deck_row(button, entry.card, count)
	if entries.is_empty():
		UI.label(slots, "从左侧加入卡牌", 15, UI.MUTED)
	var largest := maxi(1, distribution.max())
	for index in distribution.size():
		cost_bars[index].max_value = largest
		cost_bars[index].value = distribution[index]
		cost_bars[index].accessibility_name = "%s，%d 张" % [_cost_bucket_name(index), distribution[index]]
		cost_counts[index].text = str(distribution[index])
	deck_scroll.set_deferred("scroll_vertical", scroll)

func _add_deck_row(id: String) -> CardButton:
	var entry := HBoxContainer.new()
	entry.name = "Row_" + _node_suffix(id)
	entry.set_meta("card_id", id)
	entry.mouse_filter = Control.MOUSE_FILTER_PASS
	slots.add_child(entry)
	var button := _card_button(entry, id, true)
	button.name = "Card"
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var remove := UI.button(entry, "−", _remove_card.bind(id))
	remove.name = "Remove_" + _node_suffix(id)
	remove.custom_minimum_size.x = 32
	remove.add_theme_color_override("font_color", UI.ORANGE)
	_bind_drop_zone(remove, true)
	return button

func _update_deck_row(button: CardButton, card: Dictionary, count: int) -> void:
	button.accessibility_name = "%s，%d 费，卡组中 %d 张。查看详情" % [card.name, card.cost, count]
	button.tooltip_text = "单击查看 %s · 双击移除" % card.name
	var remove := button.get_parent().get_child(1) as Button
	remove.accessibility_name = "移除一张%s" % card.name
	remove.tooltip_text = remove.accessibility_name
	var copies := button.get_node_or_null("Face/Copies") as Label
	if copies != null and button.get_meta("shown_name", "") == card.name:
		copies.text = "×%d" % count
		return
	UI.clear(button)
	button.set_meta("shown_name", card.name)
	var row := HBoxContainer.new()
	row.name = "Face"
	UI.button_body(button, row, 4)
	UI.cost_badge(row, card.cost)
	var art := UI.art(row, card, Vector2(27, 28))
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var title := UI.label(row, card.name, 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UI.label(row, "×%d" % count, 15, UI.GOLD).name = "Copies"
