extends Control

signal acted
signal retreat_requested
signal menu_requested

const Battle = preload("res://scripts/domain/chess_battle.gd")
const Cards = preload("res://scripts/domain/card_catalog.gd")
const UI = preload("res://scripts/presentation/card_ui.gd")
const CROWN = preload("res://assets/ui/crown-badge.svg")
const ATTACK_ICON = preload("res://assets/ui/chess-attack.png")
const HEALTH_ICON = preload("res://assets/ui/chess-health.png")
const ARMOR_ICON = preload("res://assets/ui/chess-armor.png")
const STAT_SIZE = 38
const STAT_INSET = 6
const GRID_LINE = 2
const HAND_CARD_WIDTH = 114.0
const HAND_CARD_HEIGHT = HAND_CARD_WIDTH * 7.0 / 5.0

var battle: RefCounted
var cells: Array[Button] = []
var selected_square := -1
var selected_card := -1
var turn_banner: PanelContainer
var turn_banner_text: Label
var turn_banner_tween: Tween
var displayed_turn := -1
var hint: Label
var retreat: Button
var wait_button: Button
var cast_button: Button
var hand: Control
var pile: Label
var hand_label: Label
var hand_buttons: Array[Button] = []
var hand_ids: Array = []
var hand_generation := 0
var pending_animation := 0
var hovered := -1
var animating: Array[int] = []
var hover_detail: PanelContainer
var hover_detail_body: VBoxContainer
var detail_serial := 0
var detail_kind := ""
var detail_index := -1

func setup(model: RefCounted, scene: Texture2D) -> void:
	name = "ChessBattle"
	battle = model
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color("132923")
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if scene != null:
		var image := TextureRect.new()
		image.texture = scene
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.modulate.a = 0.28
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(image)
		image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frame := MarginContainer.new()
	add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		frame.add_theme_constant_override("margin_" + side, 15)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 9)
	frame.add_child(layout)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 4)
	layout.add_child(actions)
	wait_button = UI.button(actions, "让过", func():
		if battle.pass_turn():
			_notify_action())
	cast_button = UI.button(actions, "", func():
		if battle.play(selected_card, -1):
			_notify_action())
	cast_button.name = "CastChessSpell"
	UI.accent(cast_button)
	retreat = UI.button(actions, "撤退", func(): retreat_requested.emit())
	var menu := UI.button(actions, "主菜单", func(): menu_requested.emit())
	for button in [wait_button, cast_button, retreat, menu]:
		button.custom_minimum_size.y = 30
		button.add_theme_font_size_override("font_size", 15)
		for state in ["normal", "hover", "pressed", "disabled"]:
			var style := button.get_theme_stylebox(state).duplicate() as StyleBox
			style.content_margin_left = 8
			style.content_margin_right = 8
			style.content_margin_top = 3
			style.content_margin_bottom = 3
			button.add_theme_stylebox_override(state, style)

	var board_panel := UI.panel(layout, Color("203b32"))
	var board_frame := board_panel.get_parent() as Control
	board_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.name = "ChessGrid"
	grid.columns = Battle.COLS
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	board_panel.add_child(grid)
	for square in Battle.ROWS * Battle.COLS:
		var tile := UI.button(grid, "", _select_tile.bind(square))
		tile.name = "ChessSquare%d" % square
		tile.custom_minimum_size = Vector2(102, 88)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tile.mouse_entered.connect(_hover_tile.bind(square))
		tile.mouse_exited.connect(_unhover_tile.bind(square))
		cells.append(tile)
	hint = UI.label(board_panel, "", 15, UI.GOLD, true)

	var footer := UI.panel(layout)
	var hand_header := HBoxContainer.new()
	footer.add_child(hand_header)
	hand_label = UI.label(hand_header, "", 18, UI.GOLD)
	hand_label.name = "ChessHandCount"
	hand_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.label(hand_header, "点牌抬起 · 选择高亮目标", 14, UI.MUTED)
	var hand_table := HBoxContainer.new()
	footer.add_child(hand_table)
	hand = Control.new()
	hand.name = "ChessHand"
	hand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand.custom_minimum_size.y = 177
	hand.resized.connect(_queue_fan)
	hand_table.add_child(hand)
	var pile_box := UI.panel(hand_table, Color("304e41"), UI.GOLD)
	(pile_box.get_parent() as Control).custom_minimum_size.x = 98
	(pile_box.get_parent() as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UI.label(pile_box, "◇", 26, UI.GOLD).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pile = UI.label(pile_box, "", 14, UI.INK, true)
	pile.name = "ChessPile"
	pile.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	turn_banner = PanelContainer.new()
	turn_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_banner.custom_minimum_size = Vector2(300, 68)
	center.add_child(turn_banner)
	turn_banner_text = UI.label(turn_banner, "", 30, UI.GOLD)
	turn_banner_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_banner_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_banner.hide()
	hover_detail = PanelContainer.new()
	hover_detail.name = "ChessHoverDetail"
	hover_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_detail.custom_minimum_size = Vector2(300, 0)
	hover_detail.z_index = 60
	hover_detail.hide()
	hover_detail.add_theme_stylebox_override("panel", UI.box(Color("1d3329"), UI.GOLD, 8, 5))
	add_child(hover_detail)
	hover_detail_body = VBoxContainer.new()
	hover_detail_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_detail_body.add_theme_constant_override("separation", 4)
	hover_detail.add_child(hover_detail_body)
	render()

func _show_turn_banner() -> void:
	if not battle.outcome.is_empty() or battle.reveal_pending:
		turn_banner.hide()
		return
	if displayed_turn == battle.turn:
		return
	displayed_turn = battle.turn
	if turn_banner_tween != null:
		turn_banner_tween.kill()
	var player_turn := displayed_turn == Battle.PLAYER
	var accent := UI.GREEN if player_turn else UI.ORANGE
	turn_banner.add_theme_stylebox_override("panel", UI.box(Color("213b33") if player_turn else Color("49352c"), accent, 18, 9))
	turn_banner_text.add_theme_color_override("font_color", accent)
	turn_banner_text.text = "我方回合" if player_turn else "敌方回合"
	turn_banner.modulate.a = 0.0
	turn_banner.show()
	turn_banner_tween = create_tween()
	turn_banner_tween.tween_property(turn_banner, "modulate:a", 1.0, 0.14)
	turn_banner_tween.tween_interval(0.55)
	turn_banner_tween.tween_property(turn_banner, "modulate:a", 0.0, 0.22)
	turn_banner_tween.tween_callback(turn_banner.hide)

func render() -> void:
	var usable: bool = battle.can_act()
	retreat.disabled = not usable or battle.river
	wait_button.visible = usable and battle.must_pass()
	cast_button.visible = usable and -1 in battle.card_targets(Battle.PLAYER, selected_card)
	if cast_button.visible:
		cast_button.text = "打出" + battle.definition(battle.hands[Battle.PLAYER][selected_card]).name
	var legal := _legal()
	for square in cells.size():
		_render_tile(cells[square], square, legal.get(square, ""))
	if cast_button.visible:
		hint.text = "点击右上角「%s」完成这一手。" % cast_button.text
	elif selected_square >= 0:
		hint.text = "绿格可移动或部署 · 橙格可攻击"
	elif selected_card >= 0:
		hint.text = "选择高亮目标完成这一手"
	else:
		hint.text = "选择一张手牌或一枚己方棋子。"
	hand_label.text = "手牌  %d 张" % battle.hands[Battle.PLAYER].size()
	pile.text = "牌库 %d 张" % battle.piles[Battle.PLAYER].size()
	if battle.piles[Battle.PLAYER].is_empty():
		pile.text += "\n下次疲劳 %d" % (battle.fatigue[Battle.PLAYER] + 1)
	_render_hand()
	if detail_kind == "unit" and hover_detail.visible:
		if battle.board[detail_index].is_empty():
			_hide_detail()
		else:
			_show_detail(cells[detail_index], func(): _fill_unit_detail(battle.board[detail_index]))
	_show_turn_banner()

func _legal() -> Dictionary:
	if not battle.can_act():
		return {}
	if selected_square >= 0:
		return battle.moves(selected_square)
	var result := {}
	if selected_card >= 0:
		var card: Dictionary = battle.definition(battle.hands[Battle.PLAYER][selected_card])
		for square in battle.card_targets(Battle.PLAYER, selected_card):
			if square >= 0:
				result[square] = "deploy" if card.kind == "partner" else "spell_hit" if card.has("damage") else "equip"
	return result

func _select_tile(square: int) -> void:
	if not battle.can_act():
		return
	if _legal().has(square):
		var accepted: bool = battle.play(selected_card, square) if selected_card >= 0 else battle.move(selected_square, square)
		if accepted:
			_notify_action()
		return
	if not battle.board[square].is_empty():
		selected_card = -1
		selected_square = square if selected_square != square and battle.board[square].side == Battle.PLAYER else -1
		render()

func _select_card(index: int) -> void:
	if not battle.can_act():
		return
	selected_square = -1
	selected_card = -1 if selected_card == index else index
	render()

func _notify_action() -> void:
	selected_square = -1
	selected_card = -1
	hovered = -1
	render()
	acted.emit()

func _render_tile(tile: Button, square: int, action: String) -> void:
	var unit: Dictionary = battle.board[square]
	var empty := unit.is_empty()
	var row := floori(float(square) / Battle.COLS)
	var col := square % Battle.COLS
	var square_label := ("敌方" if row < 2 else "己方") + Battle.square_name(square)
	var light := (row + col) % 2 == 0
	var tint := (Color("5b493b") if light else Color("483a31")) if row < 2 else (Color("375648") if light else Color("29453b"))
	var border := Color("a48a69") if row < 2 else Color("7f9b86")
	var enemy_action: Dictionary = battle.last_enemy_action
	if not empty:
		tint = tint.lightened(0.05)
		border = UI.GOLD
	if square == selected_square:
		tint = Color("4a6656")
	elif action in ["attack", "spell_hit"]:
		tint = Color("76513c")
		border = UI.ORANGE
	elif not action.is_empty():
		tint = Color("426e56")
		border = UI.GREEN
	elif square == enemy_action.get("target", -1):
		tint = tint.lightened(0.14)
		border = UI.ORANGE
	elif square == enemy_action.get("from", -1):
		border = Color("c99264")
	var style := UI.box(tint, border, 0, 0)
	# An occupied square owns its edge against an empty one. For matching neighbors,
	# only the square on the left or above draws the shared edge.
	var left_edge: bool = col == 0 or (not empty and battle.board[square - 1].is_empty())
	var right_edge: bool = col == Battle.COLS - 1 or not empty or battle.board[square + 1].is_empty()
	var top_edge: bool = row == 0 or (row != 2 and not empty and battle.board[square - Battle.COLS].is_empty())
	var bottom_edge: bool = row == Battle.ROWS - 1 or not empty or battle.board[square + Battle.COLS].is_empty()
	style.border_width_left = GRID_LINE if left_edge else 0
	style.border_width_right = GRID_LINE if right_edge else 0
	style.border_width_top = GRID_LINE if top_edge else 0
	style.border_width_bottom = GRID_LINE + 1 if row == 1 else GRID_LINE if bottom_edge else 0
	for state in ["normal", "pressed", "disabled"]:
		tile.add_theme_stylebox_override(state, style)
	var hover_style := style.duplicate() as StyleBoxFlat
	hover_style.bg_color = tint.lightened(0.09)
	tile.add_theme_stylebox_override("hover", hover_style)
	tile.disabled = not battle.can_act() or empty and action.is_empty()
	UI.clear(tile)
	if empty:
		tile.text = "+" if action == "deploy" else "●" if action == "move" else ""
		tile.accessibility_name = square_label + "空格"
		return
	tile.text = ""
	var content := HBoxContainer.new()
	UI.button_body(tile, content, STAT_INSET)
	content.offset_left = STAT_INSET + 20
	content.offset_right = -STAT_INSET - STAT_SIZE
	content.add_theme_constant_override("separation", 8)
	UI.art(content, unit, Vector2(118, 0))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(text)
	UI.label(text, unit.name, 19).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var details: String = Cards.ELEMENTS.get(unit.element, "物理")
	if not unit.weapon.is_empty():
		details += " · " + battle._weapon(unit).name
	UI.label(text, details, 13, UI.GOLD).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if action == "attack":
		var damage := UI.label(text, "可攻击 · %d 伤害" % battle.attack_power(battle.board[selected_square]), 13, UI.ORANGE)
		damage.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if unit.leader:
		_mark_commander(tile)
	var attack: int = battle.attack_power(unit)
	_stat_badge(tile, "Attack", ATTACK_ICON, attack, Control.PRESET_BOTTOM_LEFT)
	_stat_badge(tile, "Health", HEALTH_ICON, unit.hp, Control.PRESET_BOTTOM_RIGHT, 4)
	_stat_badge(tile, "Armor", ARMOR_ICON, unit.armor, Control.PRESET_TOP_RIGHT)
	var stats := "攻 %d · 血 %d/%d · 甲 %d" % [attack, unit.hp, unit.hp_max, unit.armor]
	var accessible_name: String = unit.name + (" 主战者" if unit.leader else "")
	tile.accessibility_name = "%s %s %s %s" % [square_label, accessible_name, details, stats]

func _stat_badge(tile: Button, badge_name: String, icon: Texture2D, value: int, corner: int, text_y: int = 0) -> void:
	var badge := TextureRect.new()
	badge.name = badge_name
	badge.texture = icon
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.size = Vector2(STAT_SIZE, STAT_SIZE)
	tile.add_child(badge)
	badge.set_anchors_and_offsets_preset(corner, Control.PRESET_MODE_KEEP_SIZE, STAT_INSET)
	var digits := str(value)
	var number := UI.label(badge, digits, clampi(22 - digits.length() * 3, 10, 19), Color("fff0cf"))
	number.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	number.offset_top = text_y
	number.offset_bottom = text_y
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number.add_theme_color_override("font_outline_color", Color("251912"))
	number.add_theme_constant_override("outline_size", 4)

func _mark_commander(tile: Button) -> void:
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", UI.box(UI.GOLD, Color("1d3329"), 1, 5))
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(plate)
	var crown := TextureRect.new()
	crown.texture = CROWN
	crown.custom_minimum_size = Vector2(20, 17)
	crown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(crown)
	plate.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, STAT_INSET)

func _render_hand() -> void:
	var current: Array = battle.hands[Battle.PLAYER]
	if current != hand_ids:
		UI.clear(hand)
		hand_buttons.clear()
		animating.clear()
		hovered = -1
		_hide_detail()
		hand_ids = current.duplicate()
		for i in hand_ids.size():
			var entry: Dictionary = battle.definition(hand_ids[i])
			var button := UI.button(hand, "", _select_card.bind(i))
			button.name = "HandCard%d" % i
			button.accessibility_name = entry.name
			button.mouse_entered.connect(_hover_card.bind(i))
			button.mouse_exited.connect(_unhover_card.bind(i))
			var content := VBoxContainer.new()
			UI.button_body(button, content, 8)
			content.add_theme_constant_override("separation", 2)
			UI.art(content, entry, Vector2.ZERO).size_flags_vertical = Control.SIZE_EXPAND_FILL
			var short_name: String = entry.name.get_slice(" · ", 0) if entry.kind == "equipment" else entry.name
			var title := UI.label(content, short_name, 16)
			title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			var kind := UI.label(content, ("临时 · " if entry.get("temporary", false) else "") + Cards.KINDS[entry.kind], 13, UI.MUTED)
			kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hand_buttons.append(button)
		pending_animation = mini(int(battle.draw_count), hand_ids.size())
		battle.draw_count = 0
		_queue_fan()
	for i in hand_buttons.size():
		var button := hand_buttons[i]
		var card: Dictionary = battle.definition(hand_ids[i])
		var tint: Color = {"partner": Color("294639"), "weapon": Color("494033"), "equipment": Color("494033"), "defense": Color("344b50"), "spell": Color("3a4659")}[card.kind]
		for state in ["normal", "disabled", "hover", "pressed"]:
			var highlighted: bool = i == selected_card or state in ["hover", "pressed"]
			button.add_theme_stylebox_override(state, UI.box(tint, UI.GOLD if highlighted else Color("96957a"), 6, 8))
		button.disabled = not battle.can_act()
		if i not in animating:
			_pose_card(i)

func _queue_fan() -> void:
	hand_generation += 1
	_layout_fan.call_deferred(hand_generation)

func _layout_fan(generation: int) -> void:
	if generation != hand_generation or not is_inside_tree():
		return
	var drawn := pending_animation
	pending_animation = 0
	for i in hand_buttons.size():
		if i in animating:
			continue
		_pose_card(i)
		if i < hand_buttons.size() - drawn:
			continue
		var button := hand_buttons[i]
		var finish := button.position
		var angle := button.rotation
		button.position = Vector2(hand.size.x + 8, 47)
		button.rotation = 0.13
		button.modulate.a = 0.0
		animating.append(i)
		var flight := button.create_tween().set_parallel()
		var delay := float(i - (hand_buttons.size() - drawn)) * 0.08
		flight.tween_property(button, "position", finish, 0.34).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		flight.tween_property(button, "rotation", angle, 0.34).set_delay(delay)
		flight.tween_property(button, "modulate:a", 1.0, 0.22).set_delay(delay)
		flight.finished.connect(func():
			if is_instance_valid(button) and button in hand_buttons:
				animating.erase(i)
				_pose_card(i))

func _pose_card(index: int) -> void:
	if index >= hand_buttons.size():
		return
	var button := hand_buttons[index]
	# Allow room for the two outside corners when the cards tilt.
	var available := maxf(0.0, hand.size.x - HAND_CARD_WIDTH - 48.0)
	var span := minf(HAND_CARD_WIDTH * 0.92, available / maxi(1, hand_buttons.size() - 1))
	var center := float(hand_buttons.size() - 1) / 2.0
	var offset := float(index) - center
	var curve := offset / maxf(1.0, center)
	var raised := index == hovered or index == selected_card
	var resting_y := hand.size.y - HAND_CARD_HEIGHT - 13.0
	button.size = Vector2(HAND_CARD_WIDTH, HAND_CARD_HEIGHT)
	button.pivot_offset = Vector2(HAND_CARD_WIDTH * 0.5, HAND_CARD_HEIGHT - 12.0)
	button.position = Vector2((hand.size.x - HAND_CARD_WIDTH) * 0.5 + offset * span,
		resting_y - 16.0 if raised else resting_y + curve * curve * 4.0)
	button.rotation = 0.0 if raised else deg_to_rad(curve * 8.0)
	button.z_index = 24 if raised else index

func _hover_card(index: int) -> void:
	if battle.can_act() and index not in animating:
		hovered = index
		_pose_card(index)
	if index not in animating:
		_show_card_detail(index)

func _unhover_card(index: int) -> void:
	if hovered == index:
		hovered = -1
		_pose_card(index)
	if detail_kind == "card" and detail_index == index:
		_hide_detail()

func _hover_tile(square: int) -> void:
	if not battle.board[square].is_empty():
		_show_unit_detail(square)

func _unhover_tile(square: int) -> void:
	if detail_kind == "unit" and detail_index == square:
		_hide_detail()

func _show_unit_detail(square: int) -> void:
	detail_kind = "unit"
	detail_index = square
	_show_detail(cells[square], func(): _fill_unit_detail(battle.board[square]))

func _show_card_detail(index: int) -> void:
	if index < 0 or index >= hand_ids.size() or index >= hand_buttons.size():
		return
	detail_kind = "card"
	detail_index = index
	_show_detail(hand_buttons[index], func(): _fill_card_detail(battle.definition(hand_ids[index])))

func _hide_detail() -> void:
	detail_serial += 1
	detail_kind = ""
	detail_index = -1
	hover_detail.hide()

func _show_detail(source: Control, filler: Callable) -> void:
	detail_serial += 1
	var serial := detail_serial
	UI.clear(hover_detail_body)
	filler.call()
	_ignore_mouse(hover_detail)
	hover_detail.size = Vector2(300, 0)
	hover_detail.position = Vector2(-4000, -4000)
	hover_detail.show()
	await get_tree().process_frame
	if serial != detail_serial:
		return
	if not is_instance_valid(source) or not source.is_visible_in_tree():
		_hide_detail()
		return
	hover_detail.size = Vector2(300, maxi(hover_detail.get_combined_minimum_size().y, 40.0))
	var bounds := get_global_rect()
	var rect := source.get_global_rect()
	var place := Vector2(rect.position.x, rect.position.y - hover_detail.size.y - 10)
	if place.y < bounds.position.y:
		place.y = mini(rect.position.y + rect.size.y + 10, bounds.position.y + bounds.size.y - hover_detail.size.y)
	place.x = clampf(place.x, bounds.position.x, bounds.position.x + bounds.size.x - hover_detail.size.x)
	hover_detail.position = place

func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)

func _section(title: String) -> void:
	UI.label(hover_detail_body, title, 13, UI.GOLD)

func _detail_header(entry: Dictionary, kind: String, accent: Color) -> void:
	var head := HBoxContainer.new()
	hover_detail_body.add_child(head)
	UI.art(head, entry, Vector2(44, 46))
	var title := VBoxContainer.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	UI.label(title, kind, 13, accent)
	UI.label(title, entry.name, 19, UI.GOLD)

func _fill_unit_detail(unit: Dictionary) -> void:
	_detail_header(unit, ("敌方" if unit.side == Battle.ENEMY else "己方") + ("主战者" if unit.leader else "棋子"),
		UI.ORANGE if unit.side == Battle.ENEMY else UI.GREEN)
	UI.label(hover_detail_body, "%s属性 · 攻 %d · 血 %d/%d · 甲 %d" % [Cards.ELEMENTS.get(unit.element, "物理"),
		battle.attack_power(unit), unit.hp, unit.hp_max, unit.armor], 14, UI.MUTED, true)
	_section("移动与攻击")
	UI.label(hover_detail_body, _movement_text(unit, true), 13, UI.INK, true)
	var talent := _split_talent(unit.trait)
	if not talent.rules.is_empty():
		_section("特性")
		UI.label(hover_detail_body, talent.rules, 13, UI.INK, true)
	var gear: Dictionary = unit.get("gear", {})
	if not gear.is_empty():
		_section("当前装备")
		for slot in gear:
			var item: Dictionary = gear[slot]
			UI.label(hover_detail_body, "· " + item.name, 14, UI.GREEN, true)
			UI.label(hover_detail_body, item.trait, 12, UI.MUTED, true)
	if not talent.talent.is_empty():
		_section("角色天赋")
		UI.label(hover_detail_body, talent.talent, 13, UI.GREEN, true)
	if unit.leader and unit.side == Battle.ENEMY and not battle.revealed_enemy.is_empty():
		_section("已知敌方手牌")
		var names: Array[String] = []
		for id in battle.revealed_enemy:
			names.append(battle.definition(id).name)
		UI.label(hover_detail_body, "、".join(names), 13, UI.INK, true)

func _fill_card_detail(card: Dictionary) -> void:
	_detail_header(card, ("临时 · " if card.get("temporary", false) else "") + Cards.KINDS[card.kind] + "牌", UI.MUTED)
	var summary := _card_stats(card)
	if not summary.is_empty():
		UI.label(hover_detail_body, summary, 14, UI.MUTED, true)
	if card.kind == "partner":
		_section("移动与攻击")
		UI.label(hover_detail_body, _movement_text(card, false), 13, UI.INK, true)
	var talent := _split_talent(card.trait)
	_section("技能说明")
	UI.label(hover_detail_body, talent.rules, 13, UI.INK, true)
	if not talent.talent.is_empty():
		_section("角色天赋")
		UI.label(hover_detail_body, talent.talent, 13, UI.GREEN, true)

func _split_talent(entry: String) -> Dictionary:
	if not "\n天赋 · " in entry:
		return {"rules": entry, "talent": ""}
	var parts := entry.split("\n天赋 · ", true, 1)
	return {"rules": parts[0].strip_edges(false, true), "talent": "天赋 · " + parts[1]}

func _movement_text(entry: Dictionary, live: bool) -> String:
	var slowed: bool = live and int(entry.get("slow_until", 0)) >= battle.round_number
	var walking := maxi(int(entry.get("move", 1)), int(entry.get("ready_move", 0)))
	if slowed:
		walking = 1
	var diagonal: bool = entry.get("diagonal", false)
	var move_text := "移动 · 横竖走 1 格" if walking <= 1 else "移动 · 横竖最多走 %d 格，路径须畅通" % walking
	if diagonal or entry.get("ready_diagonal", false):
		move_text += "，可斜走 1 格"
	if entry.get("bend_move", false):
		move_text += "，可斜绕 1 格"
	if slowed:
		move_text += "（减速中）"
	var reach: int = battle._attack_range(entry) if live else maxi(int(entry.get("range", 1)), int(entry.get("move", 1)))
	var attack_text := "攻击 · 横竖直线 %d 格" % reach
	if reach > 1:
		attack_text += "，路径须畅通"
	if diagonal:
		attack_text += "，可斜攻 1 格"
	var healing := int(entry.get("heal", 0))
	if healing > 0:
		attack_text += "；落位时治疗相邻缺血最多的友方 %d 点" % healing
	return move_text + "\n" + attack_text

func _card_stats(card: Dictionary) -> String:
	if card.kind == "partner":
		return Cards.stats(card)
	if card.kind == "spell":
		if card.has("weather"):
			var climate: Dictionary = Cards.WEATHER[card.weather]
			return "天气 · %s · %s" % [climate.name, climate.hint]
		if card.has("damage"):
			return "%s属性 · 伤害 %d 点%s" % [Cards.ELEMENTS.get(card.element, "物理"), int(card.damage),
				" · 施加减速" if card.get("slow", false) else ""]
		if card.has("heal"):
			return "治疗 %d 点生命" % int(card.heal)
	if card.kind == "defense":
		var guard: Array[String] = ["护甲 + %d" % int(card.get("armor", 0))]
		if card.has("heal"):
			guard.append("回复 %d 点生命" % int(card.heal))
		if card.get("column", false):
			guard.append("同列己方生效")
		if card.get("row", false):
			guard.append("同排己方生效")
		return " · ".join(guard)
	if card.kind == "weapon" or card.get("slot", "") == "weapon":
		var weapon: Array[String] = []
		if card.has("attack"):
			weapon.append("攻击 + %d" % int(card.attack))
		if int(card.get("range", 0)) >= 2:
			weapon.append("直线射程 %d 格" % int(card.range))
		return " · ".join(weapon)
	var gear: Array[String] = []
	if card.has("armor"):
		gear.append("护甲 + %d" % int(card.armor))
	if card.has("hp_bonus"):
		gear.append("生命上限 + %d" % int(card.hp_bonus))
	if card.has("heal"):
		gear.append("装备时回复 %d 点" % int(card.heal))
	return " · ".join(gear)
