extends Control

signal acted
signal retreat_requested
signal menu_requested

const Battle = preload("res://scripts/domain/chess_battle.gd")
const Cards = preload("res://scripts/domain/card_catalog.gd")
const UI = preload("res://scripts/presentation/card_ui.gd")
var battle: RefCounted
var cells: Array[Button] = []
var selected_square := -1
var selected_card := -1
var inspected_square := 10
var phase: Label
var weather: Label
var inspection: VBoxContainer
var log_text: Label
var hint: Label
var retreat: Button
var wait_button: Button
var hand: Control
var pile: Label
var hand_label: Label
var hand_buttons: Array[Button] = []
var hand_ids: Array = []
var hand_generation := 0
var pending_animation := 0
var hovered := -1
var animating: Array[int] = []

func setup(model: RefCounted, title: String, scene: Texture2D) -> void:
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
	var header := UI.panel(layout)
	var headline := HBoxContainer.new()
	header.add_child(headline)
	UI.label(headline, title, 26, UI.GOLD).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	phase = UI.label(headline, "", 18, UI.GREEN)
	phase.name = "ChessTurn"
	var target := HBoxContainer.new()
	header.add_child(target)
	UI.label(target, "击倒%s获胜 · 旅人倒下即失败" % battle.commanders[Battle.ENEMY].name, 16, UI.GOLD, true).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	retreat = UI.button(target, "撤退", func(): retreat_requested.emit())
	UI.button(target, "主菜单", func(): menu_requested.emit())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	layout.add_child(body)
	var board_panel := UI.panel(body, Color("203b32"))
	var board_frame := board_panel.get_parent() as Control
	board_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_frame.size_flags_stretch_ratio = 2.7
	var grid := GridContainer.new()
	grid.name = "ChessGrid"
	grid.columns = 4
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	board_panel.add_child(grid)
	UI.label(grid, "")
	for lane in ["左路", "中路", "右路"]:
		var label := UI.label(grid, lane, 15, UI.MUTED)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for row in Battle.ROWS:
		var rank := UI.label(grid, ["敌方\n后排", "敌方\n前排", "己方\n前排", "己方\n后排"][row],
			15, UI.ORANGE if row < 2 else UI.GREEN)
		rank.custom_minimum_size.x = 58
		rank.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		for col in Battle.COLS:
			var square := row * Battle.COLS + col
			var tile := UI.button(grid, "", _select_tile.bind(square))
			tile.name = "ChessSquare%d" % square
			tile.custom_minimum_size = Vector2(102, 88)
			tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
			cells.append(tile)
	hint = UI.label(board_panel, "", 15, UI.GOLD, true)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.custom_minimum_size.x = 245
	body.add_child(side)
	var env := UI.panel(side)
	weather = UI.label(env, "", 16, UI.MUTED, true)
	weather.name = "ChessWeather"
	var relic := UI.panel(side)
	var relic_row := HBoxContainer.new()
	relic.add_child(relic_row)
	UI.art(relic_row, {"icon": "life_seed"}, Vector2(40, 42))
	var relic_text := VBoxContainer.new()
	relic_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	relic_row.add_child(relic_text)
	UI.label(relic_text, "遗器 · 生命之种", 16, UI.GOLD)
	UI.label(relic_text, "己方棋子的生命上限 +2", 14, UI.MUTED, true)
	if battle.run.has_relic("lamp_badge"):
		UI.label(relic, "护灯徽章 · 己方棋子入场时获得护甲", 14, UI.MUTED, true)
	inspection = UI.panel(side)
	var record := UI.panel(side)
	(record.get_parent() as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	UI.label(record, "战斗记录", 17, UI.GOLD)
	var log_scroll := UI.scroll(record)
	log_text = UI.label(log_scroll, "", 15, UI.MUTED, true)
	log_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_text.name = "ChessLog"
	wait_button = UI.button(side, "让过", func():
		if battle.pass_turn(): _notify_action())
	wait_button.hide()

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
	render()

func render() -> void:
	var usable: bool = battle.can_act()
	var turn_text := "本回合可走 1 手" if usable else "对方正在走一手"
	if not battle.outcome.is_empty():
		turn_text = {"victory": "敌方主战者倒下", "defeat": "己方主战者倒下", "retreat": "已撤退"}[battle.outcome]
	phase.text = "第 %d 轮 · %s" % [battle.round_number, turn_text]
	retreat.disabled = not usable or battle.river
	wait_button.visible = usable and battle.must_pass()
	var climate: Dictionary = Cards.WEATHER.get(battle.weather, {})
	weather.text = "☀  晴朗 · 属性伤害无修正" if climate.is_empty() else "%s%s\n%s" % [
		climate.name, " · 剩余 %d 轮" % battle.weather_rounds if battle.weather_rounds > 0 else "", climate.hint]
	var legal := _legal()
	for square in cells.size():
		_render_tile(cells[square], square, legal.get(square, ""))
	hint.text = "绿格可移动或部署 · 橙格可攻击" if selected_square >= 0 else \
		"选择高亮目标完成这一手" if selected_card >= 0 else "选择一张手牌或一枚己方棋子。"
	_render_inspection()
	log_text.text = "\n".join(battle.log_lines.slice(-6))
	hand_label.text = "手牌  %d 张" % battle.hands[Battle.PLAYER].size()
	pile.text = "牌库 %d 张" % battle.piles[Battle.PLAYER].size()
	if battle.piles[Battle.PLAYER].is_empty():
		pile.text += "\n下次疲劳 %d" % (battle.fatigue[Battle.PLAYER] + 1)
	_render_hand()

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
				result[square] = "deploy" if card.kind == "partner" else "equip"
	return result

func _select_tile(square: int) -> void:
	if not battle.can_act():
		return
	if _legal().has(square):
		var accepted: bool = battle.play(selected_card, square) if selected_card >= 0 else battle.move(selected_square, square)
		if accepted:
			inspected_square = selected_square if selected_square >= 0 and not battle.board[selected_square].is_empty() else square
			_notify_action()
		return
	if not battle.board[square].is_empty():
		inspected_square = square
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
	var light := (row + square % Battle.COLS) % 2 == 0
	var tint := (Color("5b493b") if light else Color("483a31")) if row < 2 else (Color("375648") if light else Color("29453b"))
	var border := Color("886d58") if row < 2 else Color("638473")
	if unit.get("leader", false) or square == selected_square:
		border = UI.GOLD
	if action == "attack":
		tint = Color("76513c")
		border = UI.ORANGE
	elif not action.is_empty():
		tint = Color("426e56")
		border = UI.GREEN
	for state in ["normal", "pressed", "disabled"]:
		tile.add_theme_stylebox_override(state, UI.box(tint, border, 6, 4))
	tile.add_theme_stylebox_override("hover", UI.box(tint.lightened(0.09), border, 6, 4))
	tile.disabled = not battle.can_act() or empty and action.is_empty()
	UI.clear(tile)
	if empty:
		tile.text = "+" if action == "deploy" else "●" if action == "move" else "·"
		tile.accessibility_name = Battle.square_name(square) + "空格"
		return
	tile.text = ""
	var content := HBoxContainer.new()
	UI.button_body(tile, content)
	UI.art(content, unit, Vector2(56, 60))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(text)
	UI.label(text, unit.name, 17).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var attribute: String = Cards.ELEMENTS.get(unit.element, "物理")
	var role := ("主战者 · " if unit.leader else "") + attribute
	if not unit.weapon.is_empty():
		role += " · " + Cards.ACTIONS[unit.weapon].name
	UI.label(text, role, 13, UI.GOLD if unit.leader else UI.MUTED, true)
	var stats := "攻 %d · 血 %d/%d · 甲 %d" % [battle.attack_power(unit), unit.hp, unit.hp_max, unit.armor]
	UI.label(text, stats, 14, UI.INK, true)
	if action == "attack":
		UI.label(text, "可攻击 · %d 伤害" % battle.attack_power(battle.board[selected_square]), 13, UI.ORANGE)
	tile.accessibility_name = "%s %s %s" % [unit.name, role, stats]
	tile.tooltip_text = unit.trait

func _render_inspection() -> void:
	UI.clear(inspection)
	if selected_card >= 0:
		var card: Dictionary = battle.definition(battle.hands[Battle.PLAYER][selected_card])
		_inspect(card, Cards.KINDS[card.kind] + "牌")
		if card.kind == "partner":
			UI.label(inspection, Cards.stats(card), 14, UI.MUTED, true)
			UI.label(inspection, "部署到己方高亮空格。", 14, UI.GREEN, true)
		if card.kind == "spell":
			var cast := UI.button(inspection, "打出" + card.name, func():
				if battle.play(selected_card, -1): _notify_action())
			cast.name = "CastChessSpell"
			UI.accent(cast)
		return
	var unit: Dictionary = battle.board[inspected_square]
	if unit.is_empty():
		unit = battle.commanders[Battle.PLAYER]
	_inspect(unit, "主战者" if unit.leader else "场上棋子")
	if selected_square >= 0:
		UI.label(inspection, "攻击先扣护甲，击倒才占格。", 14, UI.MUTED, true)

func _inspect(entry: Dictionary, kind: String) -> void:
	var row := HBoxContainer.new()
	inspection.add_child(row)
	UI.art(row, entry, Vector2(40, 42))
	var title := VBoxContainer.new()
	row.add_child(title)
	UI.label(title, kind, 13, UI.MUTED)
	UI.label(title, entry.name, 18, UI.GOLD)
	UI.label(inspection, entry.trait, 15, UI.INK, true)

func _render_hand() -> void:
	var current: Array = battle.hands[Battle.PLAYER]
	if current != hand_ids:
		UI.clear(hand)
		hand_buttons.clear()
		animating.clear()
		hovered = -1
		hand_ids = current.duplicate()
		for i in hand_ids.size():
			var entry: Dictionary = battle.definition(hand_ids[i])
			var button := UI.button(hand, "", _select_card.bind(i))
			button.name = "HandCard%d" % i
			button.tooltip_text = entry.trait
			button.accessibility_name = entry.name
			button.mouse_entered.connect(_hover_card.bind(i))
			button.mouse_exited.connect(_unhover_card.bind(i))
			var content := VBoxContainer.new()
			UI.button_body(button, content)
			UI.art(content, entry, Vector2(0, 83))
			UI.label(content, entry.name, 16)
			UI.label(content, Cards.KINDS[entry.kind], 13, UI.MUTED)
			hand_buttons.append(button)
		pending_animation = mini(int(battle.draw_count), hand_ids.size())
		battle.draw_count = 0
		_queue_fan()
	for i in hand_buttons.size():
		var button := hand_buttons[i]
		var card: Dictionary = battle.definition(hand_ids[i])
		var tint: Color = {"partner": Color("294639"), "weapon": Color("494033"), "defense": Color("344b50"), "spell": Color("3a4659")}[card.kind]
		for state in ["normal", "disabled", "hover"]:
			button.add_theme_stylebox_override(state, UI.box(tint, UI.GOLD if i == selected_card or state == "hover" else Color("78917c")))
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
	var card_width := clampf(hand.size.x * 0.13, 82, 138)
	var span := minf(83, maxf(12, (hand.size.x - card_width - 22) / maxi(1, hand_buttons.size() - 1)))
	var center := float(hand_buttons.size() - 1) / 2.0
	var offset := float(index) - center
	var curve := offset / maxf(1.0, center)
	var raised := index == hovered or index == selected_card
	button.size = Vector2(card_width, 139)
	button.pivot_offset = Vector2(card_width / 2.0, 122)
	button.position = Vector2(hand.size.x / 2.0 - card_width / 2.0 + offset * span, 1.0 if raised else 17.0 + curve * curve * 14.0)
	button.rotation = 0.0 if raised else deg_to_rad(curve * 10)
	button.z_index = 24 if raised else index

func _hover_card(index: int) -> void:
	if battle.can_act() and index not in animating:
		hovered = index
		_pose_card(index)

func _unhover_card(index: int) -> void:
	if hovered == index:
		hovered = -1
		_pose_card(index)
