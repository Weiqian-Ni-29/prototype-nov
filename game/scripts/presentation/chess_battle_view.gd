extends Control

signal acted
signal attack_impact(cue: String)
signal retreat_requested
signal menu_requested

const Battle = preload("res://scripts/domain/chess_battle.gd")
const AttackEffect = preload("res://scripts/presentation/chess_attack_effect.gd")
const Cards = preload("res://scripts/domain/card_catalog.gd")
const Gear = preload("res://scripts/domain/gear_catalog.gd")
const UI = preload("res://scripts/presentation/card_ui.gd")
const CROWN = preload("res://assets/ui/crown-badge.svg")
const ATTACK_ICON = preload("res://assets/ui/chess-attack.png")
const HEALTH_ICON = preload("res://assets/ui/chess-health.png")
const ARMOR_ICON = preload("res://assets/ui/chess-armor.png")
const RETREAT_ICON = preload("res://assets/ui/chess-retreat.svg")
const MENU_ICON = preload("res://assets/ui/story-main-menu.svg")
const CARD_BACK = preload("res://assets/ui/lantern-card-back.webp")
const MANA_CRYSTAL = preload("res://assets/ui/mana-crystal.png")
const MANA_LIT = Color("8deaff")
const MANA_SPENT = Color("63798d")
const STAT_SIZE = 38
const STAT_INSET = 6
const GRID_LINE = 2
const SLOT_LABELS = {"weapon": "武器", "armor": "护甲", "accessory": "饰品"}
const SLOT_ICONS = {"weapon": "trail_blade", "armor": "padded_coat", "accessory": "lamp_charm"}
const HAND_CARD_WIDTH = 114.0
const HAND_CARD_HEIGHT = HAND_CARD_WIDTH * 7.0 / 5.0
const DECK_CARD_SIZE = Vector2(84.0, 84.0 * 7.0 / 5.0)
const DECK_STACK_OFFSET = Vector2(4, 3)
const DRAW_LIFT = 0.09
const DRAW_REVEAL = 0.22
const DRAW_LAND = 0.34
const DRAW_DURATION = 0.45
const DRAW_STAGGER = 0.08

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
var menu: Button
var end_turn_button: Button
var cast_button: Button
var enemy_deck_back: TextureRect
var enemy_cards: Label
var enemy_mana_ratio: Label
var mana_ratio: Label
var mana_row: VBoxContainer
var mana_crystals: Array[TextureRect] = []
var hand: Control
var pile: Label
var deck_layers: Array[TextureRect] = []
var empty_deck: Panel
var hand_label: Label
var hand_buttons: Array[Button] = []
var hand_ids: Array = []
var hand_generation := 0
var pending_animation := 0
var draws_before_departure := 0
var lifting_from_deck := 0
var fan_expansion := 0.0
var hovered := -1
var animating: Array[int] = []
var hover_detail: PanelContainer
var hover_detail_body: VBoxContainer
var detail_serial := 0
var detail_kind := ""
var detail_index := -1
var detail_slot := ""
var attack_effect: AttackEffect

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
	var battlefield := HBoxContainer.new()
	battlefield.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battlefield.add_theme_constant_override("separation", 10)
	layout.add_child(battlefield)
	var board_panel := UI.panel(battlefield, Color("203b32"))
	var board_frame := board_panel.get_parent() as Control
	board_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		tile.gui_input.connect(_tile_mouse_input.bind(square))
		cells.append(tile)
	hint = UI.label(board_panel, "", 15, UI.GOLD, true)
	_build_battle_controls(battlefield)

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
	_build_deck(hand_table)
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
	if is_attack_playing():
		return
	var usable: bool = battle.can_act()
	menu.disabled = false
	retreat.disabled = not usable or battle.river
	end_turn_button.disabled = not usable
	end_turn_button.text = "敌方回合" if battle.turn == Battle.ENEMY else "结束回合"
	cast_button.visible = usable and -1 in battle.card_targets(Battle.PLAYER, selected_card)
	if cast_button.visible:
		cast_button.tooltip_text = "打出" + battle.definition(battle.hands[Battle.PLAYER][selected_card]).name
	var legal := _legal()
	var equipment_slot := _selected_equipment_slot()
	for square in cells.size():
		_render_tile(cells[square], square, legal.get(square, ""))
	if cast_button.visible:
		hint.text = "点击右侧「确认出牌」%s。" % cast_button.tooltip_text
	elif selected_square >= 0:
		hint.text = "绿格可移动或部署 · 橙格可攻击"
	elif selected_card >= 0:
		hint.text = "选择高亮棋子装备，替换下来的装备牌会回到手牌。" if not equipment_slot.is_empty() else "选择高亮目标出牌。"
	elif not usable:
		hint.text = ""
		if battle.turn == Battle.ENEMY:
			var message: String = battle.last_enemy_action.get("message", "")
			hint.text = "敌方行动中。" if message.is_empty() else "敌方 · " + message
	elif not battle.can_move_piece():
		hint.text = "本回合已走棋。可继续出牌，或结束回合。"
	else:
		hint.text = "可出牌，或选一枚己方棋子移动或普攻。"
	_render_hand()
	_update_enemy_resources()
	_update_draw_counts()
	_update_mana_display()
	if detail_kind == "unit" and hover_detail.visible:
		if battle.board[detail_index].is_empty():
			_hide_detail()
		else:
			_show_unit_detail(detail_index, detail_slot)
	_show_turn_banner()

func is_attack_playing() -> bool:
	return attack_effect != null

func present_action() -> void:
	if is_attack_playing():
		return
	var event: Dictionary = battle.take_attack()
	if event.is_empty():
		render()
		return
	_hide_detail()
	if turn_banner_tween != null:
		turn_banner_tween.kill()
	turn_banner.hide()
	menu.disabled = true
	retreat.disabled = true
	end_turn_button.disabled = true
	end_turn_button.text = "敌方回合" if battle.turn == Battle.ENEMY else "结束回合"
	cast_button.hide()
	hint.text = "%s 攻击 %s" % [event.attacker.name, event.defender.name]
	for square in cells.size():
		_render_tile(cells[square], square, "", square == event.from or square == event.target)
		cells[square].disabled = true
	for button in hand_buttons:
		button.disabled = true
	_update_enemy_resources()
	attack_effect = AttackEffect.new()
	add_child(attack_effect)
	attack_effect.impact.connect(attack_impact.emit)
	attack_effect.finished.connect(_finish_attack)
	attack_effect.play(event, cells[event.from], cells[event.target], _build_piece_face)

func _finish_attack() -> void:
	attack_effect.hide()
	attack_effect.queue_free()
	attack_effect = null
	render()

func _legal() -> Dictionary:
	if not battle.can_act():
		return {}
	if selected_square >= 0:
		return battle.moves(selected_square) if battle.can_move_piece() else {}
	var result := {}
	if selected_card >= 0:
		var card: Dictionary = battle.definition(battle.hands[Battle.PLAYER][selected_card])
		for square in battle.card_targets(Battle.PLAYER, selected_card):
			if square >= 0:
				result[square] = "deploy" if card.kind == "partner" else "spell_hit" if card.has("damage") else "equip"
	return result

func _selected_equipment_slot() -> String:
	var cards: Array = battle.hands[Battle.PLAYER]
	if selected_card < 0 or selected_card >= cards.size():
		return ""
	return Cards.equipment_slot(battle.definition(cards[selected_card]))

func _select_tile(square: int) -> void:
	if is_attack_playing() or not battle.can_act():
		return
	if _legal().has(square):
		var accepted: bool = battle.play(selected_card, square) if selected_card >= 0 else battle.move(selected_square, square)
		if accepted:
			_notify_action()
		return
	if not battle.board[square].is_empty():
		selected_card = -1
		selected_square = square if battle.can_move_piece() and selected_square != square and battle.board[square].side == Battle.PLAYER else -1
		render()

func _select_card(index: int) -> void:
	if is_attack_playing() or not battle.can_act() or _card_is_drawing(index):
		return
	var card: Dictionary = battle.definition(hand_ids[index])
	if card.cost > battle.mana[Battle.PLAYER]:
		hint.text = "法力不足 · 需要 %d 点，当前 %d 点。" % [card.cost, battle.mana[Battle.PLAYER]]
		return
	selected_square = -1
	selected_card = -1 if selected_card == index else index
	render()

func _notify_action() -> void:
	selected_square = -1
	selected_card = -1
	hovered = -1
	present_action()
	acted.emit()

func _icon_button(actions: HBoxContainer, node_name: String, label: String, icon: Texture2D, callback: Callable) -> Button:
	var button := UI.button(actions, "", callback)
	button.name = node_name
	button.icon = icon
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", 24)
	button.custom_minimum_size = Vector2(48, 40)
	button.tooltip_text = label
	button.accessibility_name = label
	return button

func _render_tile(tile: Button, square: int, action: String, hide_face: bool = false) -> void:
	var unit: Dictionary = battle.board[square]
	var empty := unit.is_empty()
	var row := floori(float(square) / Battle.COLS)
	var col := square % Battle.COLS
	var square_label := ("敌方" if row < 2 else "己方") + Battle.square_name(square)
	var light := (row + col) % 2 == 0
	var tint := (Color("5b493b") if light else Color("483a31")) if row < 2 else (Color("375648") if light else Color("29453b"))
	var border := Color("a48a69") if row < 2 else Color("7f9b86")
	var enemy_action: Dictionary = battle.last_enemy_action
	if not empty and not hide_face:
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
	elif not hide_face and square == enemy_action.get("target", -1):
		tint = tint.lightened(0.14)
		border = UI.ORANGE
	elif not hide_face and square == enemy_action.get("from", -1):
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
	if hide_face:
		tile.text = ""
		tile.accessibility_name = square_label
		return
	if empty:
		tile.text = "+" if action == "deploy" else "●" if action == "move" else ""
		tile.accessibility_name = square_label + "空格"
		return
	tile.text = ""
	_build_piece_face(tile, unit, action)
	var stats := "攻 %d · 血 %d/%d · 甲 %d" % [battle.attack_power(unit), unit.hp, unit.hp_max, unit.armor]
	var accessible_parts: Array[String] = [square_label, unit.name]
	if unit.leader:
		accessible_parts.append("主战者")
	var element_name: String = Cards.ELEMENTS.get(unit.element, "")
	if not element_name.is_empty():
		accessible_parts.append(element_name + "属性")
	for slot in Gear.SLOTS:
		var item: Dictionary = battle.equipment_at(unit, slot)
		accessible_parts.append("%s %s" % [SLOT_LABELS[slot], item.get("name", "空槽")])
	accessible_parts.append(stats)
	tile.accessibility_name = " ".join(accessible_parts)

func _build_piece_face(tile: Control, unit: Dictionary, action: String) -> void:
	var content := HBoxContainer.new()
	content.name = "PieceFace"
	UI.button_body(tile, content, STAT_INSET)
	content.offset_right = -STAT_INSET - STAT_SIZE - 2
	content.add_theme_constant_override("separation", 8)
	var identity := VBoxContainer.new()
	identity.name = "Identity"
	identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_theme_constant_override("separation", 2)
	content.add_child(identity)
	var heading := HBoxContainer.new()
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_theme_constant_override("separation", 3)
	identity.add_child(heading)
	if unit.leader:
		var crown_space := Control.new()
		crown_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crown_space.custom_minimum_size.x = 23
		heading.add_child(crown_space)
	UI.add_element_icon(heading, unit.element)
	var title := UI.label(heading, unit.name, 17)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UI.art(identity, unit, Vector2.ZERO).size_flags_vertical = Control.SIZE_EXPAND_FILL
	if action == "attack":
		var damage := UI.label(identity, "可攻击 · %d" % battle.attack_power(battle.board[selected_square]), 12, UI.ORANGE)
		damage.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		damage.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var rack := HBoxContainer.new()
	rack.name = "EquipmentSlots"
	rack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rack.add_theme_constant_override("separation", 5)
	content.add_child(rack)
	var targeted_slot := _selected_equipment_slot() if action == "equip" else ""
	for slot in Gear.SLOTS:
		_build_equipment_slot(rack, slot, battle.equipment_at(unit, slot), targeted_slot == slot)
	var size_identity := func():
		identity.custom_minimum_size.x = clampf(tile.size.x * 0.26, 54.0, 144.0)
	content.resized.connect(size_identity)
	size_identity.call()
	if unit.leader:
		_mark_commander(tile)
	var attack: int = battle.attack_power(unit)
	_stat_badge(tile, "Attack", ATTACK_ICON, attack, Control.PRESET_BOTTOM_LEFT)
	_stat_badge(tile, "Health", HEALTH_ICON, unit.hp, Control.PRESET_BOTTOM_RIGHT, 4)
	_stat_badge(tile, "Armor", ARMOR_ICON, unit.armor, Control.PRESET_TOP_RIGHT)

func _build_equipment_slot(rack: HBoxContainer, slot: String, item: Dictionary, targeted: bool) -> void:
	var equipped := not item.is_empty()
	var cell := VBoxContainer.new()
	cell.name = slot
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_theme_constant_override("separation", 2)
	rack.add_child(cell)
	var category := UI.label(cell, SLOT_LABELS[slot], 13, UI.GREEN if targeted else UI.GOLD)
	category.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	category.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var fill := Color(0.12, 0.08, 0.04, 0.35 if equipped else 0.17)
	var border := UI.GREEN if targeted else Color("b0996d") if equipped else Color(0.7, 0.61, 0.46, 0.42)
	frame.add_theme_stylebox_override("panel", UI.box(fill, border, 3, 4))
	cell.add_child(frame)
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 0)
	frame.add_child(content)
	var art := UI.art(content, item if equipped else {"icon": SLOT_ICONS[slot]}, Vector2.ZERO)
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if not equipped:
		art.self_modulate = Color(0.88, 0.85, 0.76, 0.28)
	var caption: String = item.name.get_slice(" · ", 0) if equipped else "空槽"
	var label := UI.label(content, caption, 12, UI.INK if equipped else Color("c3b090"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cell.resized.connect(func(): label.visible = cell.size.x >= 57.0)

func _stat_badge(tile: Control, badge_name: String, icon: Texture2D, value: int, corner: int, text_y: int = 0) -> void:
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

func _mark_commander(tile: Control) -> void:
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

func _build_battle_controls(parent: HBoxContainer) -> void:
	var rail := VBoxContainer.new()
	rail.name = "ChessMana"
	rail.add_theme_constant_override("separation", 5)
	parent.add_child(rail)
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 4)
	rail.add_child(navigation)
	retreat = _icon_button(navigation, "ChessRetreat", "撤退", RETREAT_ICON, func():
		if not is_attack_playing():
			retreat_requested.emit())
	menu = _icon_button(navigation, "ChessMainMenu", "主菜单", MENU_ICON, func():
		if not is_attack_playing():
			menu_requested.emit())
	var enemy := UI.panel(rail, Color("352e29"), Color("8b7057"))
	enemy.get_parent().name = "ChessEnemyResources"
	enemy.add_theme_constant_override("separation", 3)
	var enemy_title := UI.label(enemy, "敌方", 15, UI.ORANGE)
	enemy_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var cards := HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 6)
	enemy.add_child(cards)
	var back_slot := Control.new()
	back_slot.custom_minimum_size = Vector2(29, 40)
	cards.add_child(back_slot)
	enemy_deck_back = _card_back()
	back_slot.add_child(enemy_deck_back)
	enemy_deck_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	enemy_cards = UI.label(cards, "", 12, UI.INK)
	enemy_cards.name = "EnemyCardCounts"
	enemy_cards.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var enemy_mana := HBoxContainer.new()
	enemy_mana.alignment = BoxContainer.ALIGNMENT_CENTER
	enemy.add_child(enemy_mana)
	var crystal := _crystal()
	crystal.custom_minimum_size = Vector2(16, 19)
	enemy_mana.add_child(crystal)
	enemy_mana_ratio = UI.label(enemy_mana, "", 15, UI.INK)
	enemy_mana_ratio.name = "EnemyManaRatio"
	cast_button = UI.button(rail, "确认出牌", func():
		if not is_attack_playing() and battle.play(selected_card, -1):
			_notify_action())
	cast_button.name = "CastChessSpell"
	cast_button.add_theme_font_size_override("font_size", 15)
	UI.accent(cast_button)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail.add_child(spacer)
	var title := UI.label(rail, "法力水晶", 15, UI.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mana_row = VBoxContainer.new()
	mana_row.name = "ManaCrystals"
	mana_row.add_theme_constant_override("separation", 2)
	rail.add_child(mana_row)
	var ratio_plate := PanelContainer.new()
	ratio_plate.add_theme_stylebox_override("panel", UI.box(Color("233c35"), Color("83856b"), 3, 5))
	rail.add_child(ratio_plate)
	mana_ratio = UI.label(ratio_plate, "", 21, UI.INK)
	mana_ratio.name = "ManaRatio"
	mana_ratio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_turn_button = UI.button(rail, "结束回合", func():
		if not is_attack_playing() and battle.end_turn():
			_notify_action())
	end_turn_button.name = "ChessEndTurn"
	end_turn_button.custom_minimum_size.y = 42
	end_turn_button.add_theme_font_size_override("font_size", 16)
	UI.accent(end_turn_button)

func _update_enemy_resources() -> void:
	var held: int = battle.hands[Battle.ENEMY].size()
	var remaining: int = battle.piles[Battle.ENEMY].size()
	var current: int = battle.mana[Battle.ENEMY]
	var capacity: int = battle.mana_capacity[Battle.ENEMY]
	enemy_cards.text = "手牌 %d\n牌库 %d" % [held, remaining]
	enemy_deck_back.visible = remaining > 0
	enemy_mana_ratio.text = "%d/%d" % [current, capacity]
	enemy_mana_ratio.accessibility_name = "敌方法力 %d，本回合上限 %d" % [current, capacity]

func _update_mana_display() -> void:
	var capacity: int = battle.mana_capacity[Battle.PLAYER]
	var current: int = battle.mana[Battle.PLAYER]
	while mana_crystals.size() < capacity:
		var crystal := _crystal()
		crystal.custom_minimum_size.y = 24
		mana_row.add_child(crystal)
		mana_row.move_child(crystal, 0)
		mana_crystals.append(crystal)
	for index in mana_crystals.size():
		var crystal := mana_crystals[index]
		crystal.visible = index < capacity
		crystal.self_modulate = Color.WHITE if index < current else MANA_SPENT
	mana_ratio.text = "%d/%d" % [current, capacity]
	mana_ratio.accessibility_name = "可用法力 %d，本回合上限 %d" % [current, capacity]

func _crystal() -> TextureRect:
	var crystal := TextureRect.new()
	crystal.texture = MANA_CRYSTAL
	crystal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crystal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crystal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return crystal

func _build_deck(parent: HBoxContainer) -> void:
	var column := VBoxContainer.new()
	column.name = "ChessDeck"
	column.custom_minimum_size.x = 106
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(column)
	var stack := Control.new()
	stack.custom_minimum_size.y = DECK_CARD_SIZE.y + 8
	column.add_child(stack)
	empty_deck = Panel.new()
	empty_deck.mouse_filter = Control.MOUSE_FILTER_IGNORE
	empty_deck.position = Vector2(7, 0)
	empty_deck.size = DECK_CARD_SIZE
	empty_deck.add_theme_stylebox_override("panel", UI.box(Color("192f28"), Color("567465"), 0, 7))
	stack.add_child(empty_deck)
	for depth in range(2, -1, -1):
		var layer := _card_back()
		layer.position = Vector2(7, 0) + DECK_STACK_OFFSET * depth
		layer.size = DECK_CARD_SIZE
		stack.add_child(layer)
		deck_layers.push_front(layer)
	pile = UI.label(column, "", 14, UI.INK)
	pile.name = "ChessPile"
	pile.custom_minimum_size.y = 40
	pile.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _card_back() -> TextureRect:
	var back := TextureRect.new()
	back.texture = CARD_BACK
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return back

func _update_draw_counts() -> void:
	var remaining: int = battle.piles[Battle.PLAYER].size() + draws_before_departure
	pile.text = "牌库 %d 张" % remaining
	if remaining == 0:
		pile.text += "\n下次疲劳 %d" % (battle.fatigue[Battle.PLAYER] + 1)
	for depth in deck_layers.size():
		deck_layers[depth].visible = depth >= lifting_from_deck and depth < remaining
	empty_deck.visible = remaining == 0
	hand_label.text = "手牌  %d 张" % _resting_card_count()

func _render_hand() -> void:
	var current: Array = battle.hands[Battle.PLAYER]
	if current != hand_ids:
		UI.clear(hand)
		hand_buttons.clear()
		animating.clear()
		lifting_from_deck = 0
		fan_expansion = 0.0
		hovered = -1
		if detail_kind == "card":
			_hide_detail()
		hand_ids = current.duplicate()
		for i in hand_ids.size():
			var entry: Dictionary = battle.definition(hand_ids[i])
			var button := UI.button(hand, "", _select_card.bind(i))
			button.name = "HandCard%d" % i
			button.accessibility_name = "%s，%d 费" % [entry.name, entry.cost]
			button.mouse_entered.connect(_hover_card.bind(i))
			button.mouse_exited.connect(_unhover_card.bind(i))
			var face := Control.new()
			UI.button_body(button, face, 0)
			var content := VBoxContainer.new()
			content.mouse_filter = Control.MOUSE_FILTER_IGNORE
			face.add_child(content)
			content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			content.offset_left = 8
			content.offset_right = -8
			content.offset_top = 12
			content.offset_bottom = -8
			content.add_theme_constant_override("separation", 2)
			UI.art(content, entry, Vector2.ZERO).size_flags_vertical = Control.SIZE_EXPAND_FILL
			var short_name: String = entry.name.get_slice(" · ", 0) if entry.kind == "equipment" else entry.name
			var title := UI.label(content, short_name, 16)
			title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			var kind := UI.label(content, ("临时 · " if entry.get("temporary", false) else "") + Cards.KINDS[entry.kind], 13, UI.MUTED)
			kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var cost_badge := _crystal()
			cost_badge.name = "ManaCost"
			cost_badge.size = Vector2(25, 32)
			face.add_child(cost_badge)
			cost_badge.position = Vector2(4, 4)
			var cost := UI.label(cost_badge, str(entry.cost), 19, Color("fff8e8"))
			cost.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			cost.add_theme_color_override("font_outline_color", Color("172433"))
			cost.add_theme_constant_override("outline_size", 4)
			hand_buttons.append(button)
		pending_animation = mini(int(battle.draw_count), hand_ids.size())
		draws_before_departure = pending_animation
		battle.draw_count = 0
		_queue_fan()
	for i in hand_buttons.size():
		var button := hand_buttons[i]
		var card: Dictionary = battle.definition(hand_ids[i])
		var tint: Color = {"partner": Color("294639"), "weapon": Color("494033"), "equipment": Color("494033"), "defense": Color("344b50"), "spell": Color("3a4659")}[card.kind]
		var affordable: bool = card.cost <= battle.mana[Battle.PLAYER]
		var face := button.get_child(0) as Control
		var cost_badge := face.get_node("ManaCost") as TextureRect
		cost_badge.self_modulate = Color.WHITE if affordable else MANA_SPENT
		if not affordable:
			tint = tint.darkened(0.22)
		for state in ["normal", "disabled", "hover", "pressed"]:
			var highlighted: bool = i == selected_card or state in ["hover", "pressed"]
			var border := Color("68736e")
			if affordable:
				border = UI.GOLD if highlighted else MANA_LIT if battle.can_act() else Color("96957a")
			button.add_theme_stylebox_override(state, UI.box(tint, border, 6, 8))
		var in_flight := _card_is_drawing(i)
		button.disabled = in_flight or not battle.can_act()
		if i >= hand_buttons.size() - pending_animation:
			button.hide()
		elif not in_flight:
			_pose_card(i)

func _queue_fan() -> void:
	hand_generation += 1
	_layout_fan.call_deferred(hand_generation)

func _layout_fan(generation: int) -> void:
	if generation != hand_generation or not is_inside_tree():
		return
	var drawn := pending_animation
	pending_animation = 0
	for i in range(hand_buttons.size() - drawn, hand_buttons.size()):
		animating.append(i)
		_start_draw(i, (i - (hand_buttons.size() - drawn)) * DRAW_STAGGER)
	for i in hand_buttons.size():
		if i not in animating:
			_pose_card(i)

func _resting_card_count() -> int:
	return hand_buttons.size() - animating.size() - pending_animation

func _card_is_drawing(index: int) -> bool:
	return index in animating or index >= hand_buttons.size() - pending_animation

func _start_draw(index: int, delay: float) -> void:
	var button := hand_buttons[index]
	var front := button.get_child(0) as Control
	var back := _card_back()
	back.name = "DrawCardBack"
	button.add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	front.hide()
	button.self_modulate.a = 0.0
	button.size = Vector2(HAND_CARD_WIDTH, HAND_CARD_HEIGHT)
	button.pivot_offset = button.size * 0.5
	button.z_index = 30
	var sample := _animate_draw.bind(index, front, back)
	var flight := button.create_tween()
	if delay > 0.0:
		flight.tween_interval(delay)
	flight.tween_callback(func():
		sample.call(0.0)
		button.show()
		lifting_from_deck += 1
		_update_draw_counts())
	flight.tween_method(sample, 0.0, DRAW_LIFT, DRAW_LIFT)
	flight.tween_callback(func():
		lifting_from_deck -= 1
		draws_before_departure -= 1
		_update_draw_counts())
	flight.tween_method(sample, DRAW_LIFT, DRAW_DURATION, DRAW_DURATION - DRAW_LIFT)
	flight.tween_callback(func():
		animating.erase(index)
		back.queue_free()
		button.scale = Vector2.ONE
		button.self_modulate.a = 1.0
		fan_expansion = 0.0
		for i in _resting_card_count():
			_pose_card(i)
		button.disabled = is_attack_playing() or not battle.can_act()
		_update_draw_counts())

func _animate_draw(time: float, index: int, front: Control, back: TextureRect) -> void:
	var button := hand_buttons[index]
	var origin := hand.get_global_transform().affine_inverse() * deck_layers[0].global_position + DECK_CARD_SIZE * 0.5
	var travel := smoothstep(DRAW_LIFT, DRAW_LAND, time)
	var settle := smoothstep(DRAW_LAND, DRAW_DURATION, time)
	var lift := lerpf(12.0 * smoothstep(0.0, DRAW_LIFT, time), 18.0, travel) * (1.0 - settle)
	lift += 24.0 * sin(PI * travel)
	var target := _fan_position(index, index + 1, false) + button.pivot_offset + Vector2(14.0 * (1.0 - settle), 0)
	var flip := smoothstep(DRAW_REVEAL, DRAW_LAND, time)
	var show_front := flip >= 0.5
	var base_scale := lerpf(DECK_CARD_SIZE.x / HAND_CARD_WIDTH, 1.0, travel)
	button.position = origin.lerp(target, travel) - button.pivot_offset - Vector2(0, lift)
	button.scale = Vector2(maxf(0.04, absf(cos(PI * flip))) * base_scale, base_scale)
	button.rotation = deg_to_rad(_fan_curve(index, index + 1) * 8.0) * settle
	back.visible = not show_front
	front.visible = show_front
	button.self_modulate.a = 1.0 if show_front else 0.0
	if index == animating[0] and time >= DRAW_LAND:
		fan_expansion = settle
		for i in _resting_card_count():
			_pose_card(i)

func _pose_card(index: int) -> void:
	if index >= hand_buttons.size():
		return
	var button := hand_buttons[index]
	var count := _resting_card_count() + fan_expansion
	var raised := index == hovered or index == selected_card
	button.size = Vector2(HAND_CARD_WIDTH, HAND_CARD_HEIGHT)
	button.pivot_offset = button.size * 0.5
	button.position = _fan_position(index, count, raised)
	button.rotation = 0.0 if raised else deg_to_rad(_fan_curve(index, count) * 8.0)
	button.z_index = 24 if raised else 0

func _fan_position(index: int, count: float, raised: bool) -> Vector2:
	# Allow room for the two outside corners when the cards tilt.
	var available := maxf(0.0, hand.size.x - HAND_CARD_WIDTH - 48.0)
	var span := minf(HAND_CARD_WIDTH * 0.92, available / maxf(1.0, count - 1.0))
	var offset := index - (count - 1.0) * 0.5
	var curve := _fan_curve(index, count)
	var resting_y := hand.size.y - HAND_CARD_HEIGHT - 13.0
	return Vector2((hand.size.x - HAND_CARD_WIDTH) * 0.5 + offset * span,
		resting_y - 16.0 if raised else resting_y + curve * curve * 4.0)

func _fan_curve(index: int, count: float) -> float:
	var center := (count - 1.0) * 0.5
	return (index - center) / maxf(1.0, center)

func _hover_card(index: int) -> void:
	if is_attack_playing() or _card_is_drawing(index):
		return
	if battle.can_act():
		hovered = index
		_pose_card(index)
	_show_card_detail(index)

func _unhover_card(index: int) -> void:
	if hovered == index:
		hovered = -1
		_pose_card(index)
	if detail_kind == "card" and detail_index == index:
		_hide_detail()

func _hover_tile(square: int) -> void:
	_inspect_tile_at(square, get_global_mouse_position())

func _tile_mouse_input(event: InputEvent, square: int) -> void:
	if event is InputEventMouseMotion:
		_inspect_tile_at(square, cells[square].get_global_transform() * event.position)

func _inspect_tile_at(square: int, point: Vector2) -> void:
	if is_attack_playing() or battle.board[square].is_empty():
		return
	var slot := ""
	var rack := cells[square].get_node_or_null("PieceFace/EquipmentSlots")
	if rack != null:
		for cell in rack.get_children():
			if cell.get_global_rect().has_point(point):
				slot = str(cell.name)
				break
	if detail_kind != "unit" or detail_index != square or detail_slot != slot:
		_show_unit_detail(square, slot)

func _unhover_tile(square: int) -> void:
	if detail_kind == "unit" and detail_index == square:
		_hide_detail()

func _show_unit_detail(square: int, slot: String = "") -> void:
	detail_kind = "unit"
	detail_index = square
	detail_slot = slot
	var tile := cells[square]
	var unit: Dictionary = battle.board[square]
	if slot.is_empty():
		_show_detail(tile, func(): _fill_unit_detail(unit))
	else:
		var source := tile.get_node("PieceFace/EquipmentSlots/" + slot) as Control
		_show_detail(source, func(): _fill_equipment_detail(unit, square, slot))

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
	detail_slot = ""
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
	UI.label(title, entry.name, 19, UI.GOLD, true)

func _fill_unit_detail(unit: Dictionary) -> void:
	_detail_header(unit, ("敌方" if unit.side == Battle.ENEMY else "己方") + ("主战者" if unit.leader else "棋子"),
		UI.ORANGE if unit.side == Battle.ENEMY else UI.GREEN)
	UI.element_summary(hover_detail_body, unit.element, "攻 %d · 血 %d/%d · 甲 %d" % [
		battle.attack_power(unit), unit.hp, unit.hp_max, unit.armor])
	_section("移动与攻击")
	UI.label(hover_detail_body, _movement_text(unit, true), 13, UI.INK, true)
	var talent := _split_talent(unit.trait)
	if not talent.rules.is_empty():
		_section("特性")
		UI.label(hover_detail_body, talent.rules, 13, UI.INK, true)
	var equipment: Array[String] = []
	for slot in Gear.SLOTS:
		var item: Dictionary = battle.equipment_at(unit, slot)
		if not item.is_empty():
			equipment.append("%s · %s" % [SLOT_LABELS[slot], item.name])
	if not equipment.is_empty():
		_section("当前装备")
		UI.label(hover_detail_body, "\n".join(equipment), 13, UI.GREEN, true)
	if not talent.talent.is_empty():
		_section("角色天赋")
		UI.label(hover_detail_body, talent.talent, 13, UI.GREEN, true)
	if unit.leader and unit.side == Battle.ENEMY and not battle.revealed_enemy.is_empty():
		_section("已知敌方手牌")
		var names: Array[String] = []
		for id in battle.revealed_enemy:
			names.append(battle.definition(id).name)
		UI.label(hover_detail_body, "、".join(names), 13, UI.INK, true)

func _fill_equipment_detail(unit: Dictionary, square: int, slot: String) -> void:
	var item: Dictionary = battle.equipment_at(unit, slot)
	var category: String = SLOT_LABELS[slot]
	if item.is_empty():
		_detail_header({"name": "空槽", "icon": SLOT_ICONS[slot]}, category, UI.MUTED)
		if unit.side == Battle.PLAYER:
			UI.label(hover_detail_body, "可打出一张%s牌来装备。" % category, 13, UI.INK, true)
		return
	var status := category + " · 已装备"
	if item.get("temporary", false):
		status += " · 临时"
	_detail_header(item, status, UI.GREEN)
	_section("装备效果")
	UI.element_summary(hover_detail_body, item.get("element", ""), item.trait, 13, UI.INK)
	if not battle.can_act():
		return
	if _selected_equipment_slot() == slot and square in battle.card_targets(Battle.PLAYER, selected_card):
		UI.label(hover_detail_body, "点击替换，原装备牌回到手牌。", 13, UI.GREEN, true)

func _fill_card_detail(card: Dictionary) -> void:
	_detail_header(card, ("临时 · " if card.get("temporary", false) else "") + Cards.KINDS[card.kind] + "牌", UI.MUTED)
	var cost_text := "费用 %d" % card.cost
	var affordable: bool = card.cost <= battle.mana[Battle.PLAYER]
	UI.label(hover_detail_body, cost_text if affordable else cost_text + " · 法力不足", 14, MANA_LIT if affordable else UI.ORANGE)
	var summary := _card_stats(card)
	if not summary.is_empty():
		UI.element_summary(hover_detail_body, card.get("element", ""), summary)
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
			return "伤害 %d 点%s" % [int(card.damage),
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
