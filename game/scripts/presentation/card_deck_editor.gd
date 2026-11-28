extends VBoxContainer

signal completed(deck: Array)
signal cancelled

const Relics = preload("res://scripts/domain/relic_catalog.gd")
const Cards = preload("res://scripts/domain/card_catalog.gd")
const UI = preload("res://scripts/presentation/card_ui.gd")
const COST_LABELS = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10+"]
const CARD_SIZE := Vector2(160, 224)
const CARD_GAP := 8
const WIDE_LAYOUT := 1100.0

class CardDrag:
	var id: String

	func _init(card_id: String) -> void:
		id = card_id

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
var detail: VBoxContainer
var add_button: Button
var deck_scroll: ScrollContainer
var slots: VBoxContainer
var deck_title: Label
var cost_bars: Array[ProgressBar] = []
var cost_counts: Array[Label] = []
var total: Label
var done: Button
var guidance: Label
var error: Label
var in_encounter := false
var run_model: RefCounted
var dragging_card := false

func setup(actors: Dictionary, current: Array, encounter: bool, opponent: String = "",
		expedition: RefCounted = null, back_label: String = "") -> void:
	name = "CardDeckEditor"
	deck = current.duplicate()
	roster = actors
	run_model = expedition
	available = Cards.collection(actors, _card_state())
	in_encounter = encounter
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	var heading := HBoxContainer.new()
	add_child(heading)
	UI.label(heading, "卡组编辑", 29, UI.GOLD).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.label(heading, "洗牌后抽 3 张 · 之后每回合抽 1 张", 16, UI.MUTED)
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
	detail = UI.panel(left)
	collection_scroll = UI.scroll(left)
	collection_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	collection_scroll.resized.connect(_fit_card_width)
	var collection := VBoxContainer.new()
	collection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	collection_scroll.add_child(collection)
	grid = GridContainer.new()
	grid.name = "CardCollection"
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
	deck_scroll.set_drag_forwarding(Callable(), _can_drop_card, _drop_card)
	slots = VBoxContainer.new()
	slots.mouse_filter = Control.MOUSE_FILTER_PASS
	slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_scroll.add_child(slots)
	right.add_child(HSeparator.new())
	_build_cost_distribution(right)
	guidance = UI.label(right, "", 14, UI.MUTED, true)
	error = UI.label(right, "", 14, UI.ORANGE, true)
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
	error.add_theme_color_override("font_color", UI.ORANGE)
	error.text = message
	error.show()

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
	_render_selection()

func _add_tile(id: String) -> void:
	var card := Cards.owned_definition(id, roster, _card_state())
	var button := UI.button(grid, "", _choose.bind(id))
	button.name = "Collection_" + _node_suffix(id)
	button.custom_minimum_size = Vector2(card_width, CARD_SIZE.y)
	button.toggle_mode = true
	button.set_pressed_no_signal(id == selected)
	button.set_drag_forwarding(_drag_card.bind(button, id), Callable(), Callable())
	var tint: Color = {"partner": Color("294639"), "weapon": Color("494033"), "equipment": Color("494033"), "defense": Color("344b50"), "spell": Color("3a4659")}[card.kind]
	button.add_theme_stylebox_override("normal", UI.box(tint, Color("687f70")))
	button.add_theme_stylebox_override("hover", UI.box(tint.lightened(0.09), UI.GOLD))
	var active := UI.box(tint.lightened(0.06), UI.GOLD)
	active.set_border_width_all(2)
	button.add_theme_stylebox_override("pressed", active)
	button.add_theme_stylebox_override("hover_pressed", active)
	_render_tile_face(button, id, card)

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
	button.tooltip_text = card.name + " · " + category
	_update_tile_quantity(button, id, card)

func _update_tile_quantity(button: Button, id: String, card: Dictionary) -> void:
	var count := deck.count(id)
	var limit := Cards.limit(id)
	button.get_node("Face/Status/DeckCopies").text = "%d/%d" % [count, limit]
	button.accessibility_name = "%s，%d 费，已入组 %d 张，上限 %d 张" % [card.name, card.cost, count, limit]

func _node_suffix(id: String) -> String:
	return id.replace(":", "_")

func _tile(id: String) -> Button:
	return grid.get_node_or_null("Collection_" + _node_suffix(id)) as Button

func _choose(id: String) -> void:
	var previous := _tile(selected)
	if previous != null:
		previous.set_pressed_no_signal(false)
	selected = id
	_tile(id).set_pressed_no_signal(true)
	_render_selection()

func _render_selection() -> void:
	add_button = null
	UI.clear(detail)
	if selected.is_empty():
		UI.label(detail, "未选中卡牌", 16, UI.MUTED)
		return
	var card := Cards.owned_definition(selected, roster, _card_state())
	var row := HBoxContainer.new()
	detail.add_child(row)
	UI.art(row, card, Vector2(72, 78))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	UI.label(text, card.name, 19, UI.GOLD, true)
	var meta := HBoxContainer.new()
	text.add_child(meta)
	UI.cost_badge(meta, card.cost)
	UI.label(meta, Cards.KINDS[card.kind], 14, UI.MUTED)
	if not Cards.card_attack_type(card).is_empty():
		UI.attack_tag(meta, card)
	if card.kind == "partner":
		UI.label(text, Cards.stats(card), 14, UI.MUTED, true)
	UI.label(text, card.trait, 14, UI.INK, true)
	if card.kind == "equipment" and run_model != null:
		var uid := selected.trim_prefix("gear:")
		var owner: String = run_model.data.gear_instances[uid].owner.id
		var quote: Dictionary = run_model.enhancement_quote(owner, uid)
		if quote.ok:
			var upgrade := UI.button(text, "强化至 +%d · %d 灯铢" % [int(card.level) + 1, int(quote.price)],
				_enhance_card.bind(selected, owner, uid))
			upgrade.name = "EnhanceDeckCard"
			upgrade.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			upgrade.disabled = int(quote.price) > int(run_model.data.lamp_coins)
			if upgrade.disabled:
				upgrade.tooltip_text = "灯铢不足"
		else:
			UI.label(text, quote.message, 13, UI.MUTED, true)
	add_button = UI.button(row, "", _add_card.bind(selected, true))
	add_button.name = "AddDeckCard"
	add_button.custom_minimum_size.x = 142
	add_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UI.accent(add_button)
	_update_add_button()

func _update_add_button() -> void:
	if add_button == null:
		return
	add_button.disabled = deck.count(selected) >= Cards.limit(selected)
	add_button.text = "已达同名上限" if add_button.disabled else "＋ 加入牌组"

func _enhance_card(id: String, owner: String, uid: String) -> void:
	var result: Dictionary = run_model.enhance_card(owner, uid)
	if not result.ok:
		show_error(result.message)
		return
	_render_tile_face(_tile(id), id, Cards.owned_definition(id, roster, _card_state()))
	_render_selection()
	_render_deck()
	error.add_theme_color_override("font_color", UI.GREEN)
	error.text = result.message
	error.show()
	var upgrade := detail.find_child("EnhanceDeckCard", true, false) as Button
	if upgrade != null and not upgrade.disabled:
		upgrade.grab_focus()
	else:
		_tile(id).grab_focus()

func _drag_card(_position: Vector2, button: Button, id: String) -> Variant:
	var card := Cards.owned_definition(id, roster, _card_state())
	var preview := PanelContainer.new()
	preview.add_theme_stylebox_override("panel", UI.box(Color("213b33"), UI.GOLD, 8))
	var label := UI.label(preview, "%s · %d 费" % [card.name, card.cost], 16)
	label.add_theme_font_override("font", get_theme_font("font"))
	button.set_drag_preview(preview)
	dragging_card = true
	deck_scroll.add_theme_stylebox_override("panel", UI.box(Color("244139"), UI.GREEN, 0))
	return CardDrag.new(id)

func _can_drop_card(_position: Vector2, data: Variant) -> bool:
	return data is CardDrag and data.id in available

func _drop_card(_position: Vector2, data: CardDrag) -> void:
	_add_card(data.id, false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and dragging_card:
		dragging_card = false
		deck_scroll.remove_theme_stylebox_override("panel")
		if not get_viewport().gui_is_drag_successful():
			show_error("请将卡牌拖到右侧牌表。")

func _add_card(id: String, focus_add: bool) -> void:
	if deck.count(id) >= Cards.limit(id):
		show_error("这张牌已达同名上限。")
		return
	deck.append(id)
	_refresh_deck(id)
	if focus_add:
		if add_button.disabled:
			_tile(id).grab_focus()
		else:
			add_button.grab_focus()

func _remove_card(id: String) -> void:
	var index := deck.find(id)
	if index < 0:
		return
	var row := slots.get_node("Remove_" + _node_suffix(id))
	var previous_row := row.get_index()
	deck.remove_at(index)
	_refresh_deck(id)
	var remove := slots.get_child(mini(previous_row, slots.get_child_count() - 1)) as Button
	if remove != null:
		remove.grab_focus()
	else:
		deck_title.grab_focus()

func _refresh_deck(id: String) -> void:
	error.hide()
	var button := _tile(id)
	if button != null:
		_update_tile_quantity(button, id, Cards.owned_definition(id, roster, _card_state()))
	_update_add_button()
	_render_deck()

func _render_deck() -> void:
	total.text = "%d 张" % deck.size()
	var missing := Cards.MIN_DECK_SIZE - deck.size()
	guidance.text = "已满足出战条件 · 至少 %d 张" % Cards.MIN_DECK_SIZE
	if missing > 0:
		guidance.text = ("再加入 %d 张即可出战。" if in_encounter else "当前为草稿，再加入 %d 张即可出战。") % missing
	done.disabled = in_encounter and missing > 0
	var scroll := deck_scroll.scroll_vertical
	UI.clear(slots)
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
	for entry in entries:
		var count: int = counts[entry.id]
		distribution[_cost_bucket(entry.card.cost) - 1] += count
		_add_deck_row(entry.id, entry.card, count)
	if entries.is_empty():
		UI.label(slots, "从左侧加入卡牌", 15, UI.MUTED)
	var largest := maxi(1, distribution.max())
	for index in distribution.size():
		cost_bars[index].max_value = largest
		cost_bars[index].value = distribution[index]
		cost_bars[index].accessibility_name = "%s，%d 张" % [_cost_bucket_name(index), distribution[index]]
		cost_counts[index].text = str(distribution[index])
	deck_scroll.set_deferred("scroll_vertical", scroll)

func _add_deck_row(id: String, card: Dictionary, count: int) -> void:
	var remove := UI.button(slots, "", _remove_card.bind(id))
	remove.name = "Remove_" + _node_suffix(id)
	remove.accessibility_name = "%s，%d 费，%d 张。移除一张" % [card.name, card.cost, count]
	remove.tooltip_text = card.name + " · 移除一张"
	remove.set_drag_forwarding(Callable(), _can_drop_card, _drop_card)
	var row := HBoxContainer.new()
	UI.button_body(remove, row, 4)
	UI.cost_badge(row, card.cost)
	var art := UI.art(row, card, Vector2(27, 28))
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var title := UI.label(row, card.name, 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UI.label(row, "×%d" % count, 15, UI.GOLD)
	UI.label(row, "−", 18, UI.ORANGE)
