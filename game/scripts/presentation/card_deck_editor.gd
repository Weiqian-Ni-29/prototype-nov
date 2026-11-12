extends VBoxContainer

signal completed(deck: Array)
signal cancelled

const Cards = preload("res://scripts/domain/card_catalog.gd")
const UI = preload("res://scripts/presentation/card_ui.gd")
var available: Array[String]
var deck: Array
var selected := ""
var kind := "all"
var type_buttons := {}
var search: LineEdit
var attribute: OptionButton
var count_label: Label
var grid: GridContainer
var detail: VBoxContainer
var slots: VBoxContainer
var total: Label
var meter: ProgressBar
var done: Button
var guidance: Label
var error: Label
var in_encounter := false

func setup(actors: Dictionary, current: Array, encounter: bool, width: float, opponent: String = "") -> void:
	name = "CardDeckEditor"
	deck = current.duplicate()
	available = Cards.collection(actors)
	in_encounter = encounter
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var heading := HBoxContainer.new()
	add_child(heading)
	UI.label(heading, "卡组编辑", 29, UI.GOLD).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.label(heading, "开局抽 3 张 · 之后每回合抽 1 张", 16, UI.MUTED)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	add_child(body)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 2.1
	body.add_child(left)
	var controls := HBoxContainer.new()
	left.add_child(controls)
	count_label = UI.label(controls, "卡片收藏", 18, UI.GOLD)
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search = LineEdit.new()
	search.placeholder_text = "搜索卡名或效果"
	search.custom_minimum_size.x = 150
	search.text_changed.connect(func(_value): _filter())
	controls.add_child(search)
	attribute = OptionButton.new()
	attribute.add_item("全部属性")
	attribute.set_item_metadata(0, "")
	for element in Cards.ELEMENTS:
		if element == "gravity":
			continue
		attribute.add_item(Cards.ELEMENTS[element] + "属性")
		attribute.set_item_metadata(attribute.item_count - 1, element)
	attribute.item_selected.connect(func(_index): _filter())
	controls.add_child(attribute)
	var filters := HBoxContainer.new()
	left.add_child(filters)
	for id in Cards.KINDS:
		var button := UI.button(filters, Cards.KINDS[id], _select_kind.bind(id))
		button.toggle_mode = true
		type_buttons[id] = button
	detail = UI.panel(left)
	var scroll := UI.scroll(left)
	grid = GridContainer.new()
	grid.name = "CardCollection"
	grid.columns = 4 if width >= 900 else 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 7)
	grid.add_theme_constant_override("v_separation", 7)
	scroll.add_child(grid)
	var right := UI.panel(body)
	var right_frame := right.get_parent() as Control
	right_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_frame.custom_minimum_size.x = 240
	var deck_title := HBoxContainer.new()
	right.add_child(deck_title)
	UI.label(deck_title, "远征卡组", 21, UI.GOLD).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	total = UI.label(deck_title, "", 17, UI.GOLD)
	total.name = "DeckCount"
	meter = ProgressBar.new()
	meter.max_value = Cards.DECK_SIZE
	meter.show_percentage = false
	meter.custom_minimum_size.y = 5
	right.add_child(meter)
	_loadout(right, {"portrait": "hero"}, "旅人", "主战者 · 开局站场")
	_loadout(right, {"icon": "life_seed"}, "生命之种", "遗器 · 己方生命上限 +2")
	if encounter and not opponent.is_empty():
		UI.label(right, "敌方主战者 · " + opponent, 15, UI.ORANGE, true)
	var listing := UI.scroll(right)
	slots = VBoxContainer.new()
	slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	listing.add_child(slots)
	guidance = UI.label(right, "", 14, UI.MUTED, true)
	error = UI.label(right, "", 14, UI.ORANGE, true)
	error.hide()
	done = UI.button(right, "开始战斗" if encounter else "保存卡组", func(): completed.emit(deck.duplicate()))
	done.name = "ConfirmCardDeck"
	UI.accent(done)
	UI.button(right, "返回遭遇" if encounter else "返回地图", func(): cancelled.emit())
	_filter()
	_render_deck()

func show_error(message: String) -> void:
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

func _filter() -> void:
	for id in type_buttons:
		type_buttons[id].set_pressed_no_signal(id == kind)
	var element: String = attribute.get_item_metadata(attribute.selected)
	var query := search.text.strip_edges().to_lower()
	var results: Array[String] = []
	for id in available:
		var card := Cards.definition(id)
		if (kind == "all" or card.kind == kind) and (element.is_empty() or card.get("element") == element) \
				and (query.is_empty() or query in (str(card.name) + str(card.trait)).to_lower()):
			results.append(id)
	if selected not in results:
		selected = results[0] if not results.is_empty() else ""
	count_label.text = "卡片收藏  %d 张" % results.size()
	UI.clear(grid)
	for id in results:
		_add_tile(id)
	_render_selection()

func _add_tile(id: String) -> void:
	var card := Cards.definition(id)
	var button := UI.button(grid, "", _choose.bind(id))
	button.name = "Collection_" + id
	button.custom_minimum_size = Vector2(92, 125)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.accessibility_name = card.name
	button.tooltip_text = card.trait
	var tint: Color = {"partner": Color("294639"), "weapon": Color("494033"), "defense": Color("344b50"), "spell": Color("3a4659")}[card.kind]
	button.add_theme_stylebox_override("normal", UI.box(tint, UI.GOLD if id == selected else Color("687f70")))
	button.add_theme_stylebox_override("hover", UI.box(tint.lightened(0.09), UI.GOLD))
	var content := VBoxContainer.new()
	UI.button_body(button, content)
	content.add_theme_constant_override("separation", 3)
	UI.art(content, card, Vector2(0, 62))
	UI.label(content, card.name, 16).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UI.label(content, "%s · %d/%d" % [Cards.KINDS[card.kind], deck.count(id), Cards.limit(id)], 14, UI.MUTED)

func _choose(id: String) -> void:
	selected = id
	_filter()
	var button := grid.get_node_or_null("Collection_" + id) as Button
	if button != null:
		button.grab_focus()

func _render_selection() -> void:
	UI.clear(detail)
	if selected.is_empty():
		UI.label(detail, "没有符合条件的卡牌。", 16, UI.MUTED)
		return
	var card := Cards.definition(selected)
	var row := HBoxContainer.new()
	detail.add_child(row)
	UI.art(row, card, Vector2(58, 61))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	UI.label(text, card.name, 19, UI.GOLD)
	if card.kind == "partner":
		UI.label(text, Cards.stats(card), 14, UI.MUTED, true)
	UI.label(text, card.trait, 14, UI.INK, true)
	var full := deck.size() >= Cards.DECK_SIZE
	var capped := deck.count(selected) >= Cards.limit(selected)
	var add := UI.button(row, "已达同名上限" if capped else "牌组已满" if full else "＋ 加入牌组", _add_card.bind(selected))
	add.name = "AddDeckCard"
	add.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add.disabled = full or capped
	UI.accent(add)

func _add_card(id: String) -> void:
	if deck.size() >= Cards.DECK_SIZE or deck.count(id) >= Cards.limit(id):
		return
	deck.append(id)
	_filter()
	_render_deck()
	var add := detail.find_child("AddDeckCard", true, false) as Button
	if add != null and not add.disabled:
		add.grab_focus()

func _remove_card(id: String) -> void:
	var index := deck.find(id)
	if index < 0:
		return
	deck.remove_at(index)
	_filter()
	_render_deck()
	var remove := slots.find_child("Remove_" + id, true, false) as Button
	if remove != null:
		remove.grab_focus()

func _render_deck() -> void:
	total.text = "%d / %d 张" % [deck.size(), Cards.DECK_SIZE]
	meter.value = deck.size()
	var missing := Cards.DECK_SIZE - deck.size()
	guidance.text = "再加入 %d 张即可出战。" % missing if missing > 0 else "牌组就绪。"
	done.disabled = in_encounter and missing > 0
	UI.clear(slots)
	for id in available:
		var count := deck.count(id)
		if count == 0:
			continue
		var card := Cards.definition(id)
		var row := HBoxContainer.new()
		slots.add_child(row)
		UI.art(row, card, Vector2(32, 34))
		UI.label(row, card.name, 15).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI.label(row, "×%d" % count, 15, UI.GOLD)
		var remove := UI.button(row, "−", _remove_card.bind(id))
		remove.name = "Remove_" + id
		remove.accessibility_name = "从牌组移除一张" + card.name
