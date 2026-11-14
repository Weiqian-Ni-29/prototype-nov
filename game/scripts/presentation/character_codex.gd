extends PanelContainer

const Catalog = preload("res://scripts/domain/catalog.gd")
const Cards = preload("res://scripts/domain/card_catalog.gd")
const Chess = preload("res://scripts/domain/chess_battle.gd")
const Gear = preload("res://scripts/domain/gear_catalog.gd")
const SYMBOLS = preload("res://assets/ui/codex-symbols.svg")
const POSES = {"": "常规", "serious": "严肃", "friendly": "友善", "grief": "悲伤", "anger": "愤怒", "surprise": "惊讶", "battle": "战斗"}
const FILTERS = ["全部", "已入队", "见过未加入"]
const TABS = ["概览", "装备", "棋子", "故事"]
const GRID_COLUMNS = 5
const SLOT_NAMES = {"weapon": "武器", "armor": "护甲", "accessory": "饰品"}
const STAT_NAMES = {"attack": "攻击", "defense": "防御", "speed": "速度"}
const BACKDROP_ATLASES = {
	"journey": ["hero", "ember", "tide", "frost_archer", "storm_caller", "stone_guard"],
	"allegiances": ["ironforge", "granite", "mistleaf", "ashhorn", "oathguard", "cloudscale"],
	"war-and-gods": ["fieldmedic", "siltguard", "seasons", "earth_god", "sky_god", "snowforge"],
}
const STORY_BACKDROPS = {
	"cen": "ruins", "lorne": "wetlands", "eve": "village_plains", "grit": "cover",
	"wind_runner": "road", "willow": "woodland", "highdrake": "highland", "longroad": "drylands",
}

var game: Node
var state: Dictionary
var content: VBoxContainer
var roster: Container
var roster_empty: Label
var portrait_frame: Control
var backdrop: TextureRect
var portrait: TextureButton
var poses: HBoxContainer
var heading: HBoxContainer
var details: VBoxContainer
var footer: HBoxContainer
var filter_buttons: Array[Button] = []
var tab_buttons: Array[Button] = []
var view_buttons: Array[Button] = []
var selected_row: Button
var zoom: ColorRect

func setup(host: Node, navigation: Dictionary) -> void:
	game = host
	state = navigation
	add_theme_stylebox_override("panel", game._style(Color("1a322e"), Color("5a6855"), 10))
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var bar = HBoxContainer.new()
	box.add_child(bar)
	game._text(bar, "角色图鉴", 28, game.gold)
	_build_view_switch(bar)
	var close = game._button(bar, "×", game._close_character_codex)
	close.name = "CloseCodex"
	close.tooltip_text = "关闭角色图鉴"
	box.add_child(HSeparator.new())
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(content)
	_set_view(state.grid)
	if selected_row != null:
		selected_row.grab_focus()

func _build_view_switch(bar: HBoxContainer) -> void:
	var shell = PanelContainer.new()
	shell.name = "CodexViewSwitch"
	shell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var outline: StyleBoxFlat = game._style(Color("1a322e"), game.gold, 12)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		outline.set_content_margin(side, 1)
	shell.add_theme_stylebox_override("panel", outline)
	bar.add_child(shell)
	var segments = HBoxContainer.new()
	segments.add_theme_constant_override("separation", 0)
	shell.add_child(segments)
	var group = ButtonGroup.new()
	for grid in [false, true]:
		var button: Button = game._button(segments, "", _set_view.bind(grid))
		button.name = "CodexGridView" if grid else "CodexListView"
		button.tooltip_text = "格子视图" if grid else "列表视图"
		button.accessibility_name = button.tooltip_text
		button.custom_minimum_size = Vector2(51, 36)
		button.toggle_mode = true
		button.button_group = group
		button.icon = _symbol(5 if grid else 4)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 28)
		var colors = {"normal": Color("1a322e"), "hover": Color("30483c"), "pressed": game.gold}
		for variant in colors:
			var style: StyleBoxFlat = game._style(colors[variant], Color.TRANSPARENT, 0)
			for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
				style.set_content_margin(side, 0)
			style.set_corner_radius(CORNER_TOP_RIGHT if grid else CORNER_TOP_LEFT, 11)
			style.set_corner_radius(CORNER_BOTTOM_RIGHT if grid else CORNER_BOTTOM_LEFT, 11)
			button.add_theme_stylebox_override(variant, style)
		button.add_theme_color_override("icon_normal_color", game.gold)
		button.add_theme_color_override("icon_hover_color", game.gold)
		button.add_theme_color_override("icon_pressed_color", Color("18332e"))
		button.add_theme_color_override("icon_hover_pressed_color", Color("18332e"))
		view_buttons.append(button)

func _set_view(grid: bool) -> void:
	state.grid = grid
	for i in view_buttons.size():
		view_buttons[i].set_pressed_no_signal(i == int(grid))
	game._clear(content)
	filter_buttons.clear()
	tab_buttons.clear()
	if grid:
		var filters = HBoxContainer.new()
		filters.add_theme_constant_override("separation", 8)
		content.add_child(filters)
		_build_filters(filters)
		content.add_child(HSeparator.new())
		_build_roster(content, true)
	else:
		_build_list()
	_render_roster()
	if not grid:
		_render_character()

func _build_list() -> void:
	var columns = HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 14)
	content.add_child(columns)
	var list_column = VBoxContainer.new()
	list_column.custom_minimum_size.x = 206
	list_column.add_theme_constant_override("separation", 8)
	columns.add_child(list_column)
	_build_filters(list_column)
	_build_roster(list_column, false)
	columns.add_child(VSeparator.new())
	_build_portrait(columns)
	_build_details(columns)

func _build_filters(parent: Container) -> void:
	var row = parent
	if parent is VBoxContainer:
		row = HBoxContainer.new()
		parent.add_child(row)
	for i in FILTERS.size():
		var target = parent if i == 2 else row
		var button: Button = game._button(target, FILTERS[i], _set_filter.bind(i))
		if parent is VBoxContainer:
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			button.custom_minimum_size.x = 116
		button.toggle_mode = true
		filter_buttons.append(button)
	var found = 0
	for id in Catalog.COMPANIONS:
		found += int(_known(id))
	var count: Label = game._text(parent, "已相遇 %d / %d" % [found, Catalog.COMPANIONS.size()], 13, game.muted)
	if parent is HBoxContainer:
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func _build_roster(parent: Container, grid: bool) -> void:
	var rows: VBoxContainer = game._scroll_content(parent)
	rows.get_parent().horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows.get_parent().follow_focus = true
	roster_empty = game._text(rows, "还没有见过未加入的伙伴。", 15, game.muted)
	if grid:
		var cards = GridContainer.new()
		cards.columns = GRID_COLUMNS
		cards.add_theme_constant_override("h_separation", 12)
		cards.add_theme_constant_override("v_separation", 12)
		rows.add_child(cards)
		roster = cards
	else:
		roster = VBoxContainer.new()
		roster.add_theme_constant_override("separation", 9)
		rows.add_child(roster)
	roster.name = "CodexRoster"

func _build_portrait(columns: HBoxContainer) -> void:
	var center = VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size.x = 230
	center.add_theme_constant_override("separation", 9)
	columns.add_child(center)
	portrait_frame = ColorRect.new()
	portrait_frame.name = "CodexPortraitFrame"
	portrait_frame.color = Color("263a30")
	portrait_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait_frame.clip_contents = true
	portrait_frame.resized.connect(_fit_portrait)
	center.add_child(portrait_frame)
	backdrop = _texture(null)
	backdrop.name = "CodexPortraitBackdrop"
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait_frame.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait = TextureButton.new()
	portrait.name = "CodexPortrait"
	portrait.ignore_texture_size = true
	portrait.stretch_mode = TextureButton.STRETCH_SCALE
	portrait.tooltip_text = "放大立绘"
	portrait.pressed.connect(_open_zoom)
	portrait_frame.add_child(portrait)
	poses = HBoxContainer.new()
	poses.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(poses)
	columns.add_child(VSeparator.new())

func _build_details(columns: HBoxContainer) -> void:
	var pane = VBoxContainer.new()
	pane.custom_minimum_size.x = 365
	pane.add_theme_constant_override("separation", 11)
	columns.add_child(pane)
	heading = HBoxContainer.new()
	pane.add_child(heading)
	var tabs = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 3)
	pane.add_child(tabs)
	for i in TABS.size():
		var button: Button = game._button(tabs, TABS[i], _set_tab.bind(i))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		tab_buttons.append(button)
	pane.add_child(HSeparator.new())
	details = game._scroll_content(pane)
	details.name = "CodexDetails"
	details.get_parent().horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	footer = HBoxContainer.new()
	pane.add_child(footer)

func _known(id: String) -> bool:
	return id == "hero" or game.run.actor(id).joined or game.run.data.story[id].get("met", false)

func _status(id: String) -> String:
	if not _known(id):
		return "尚未相遇"
	if game.run.actor(id).joined:
		return "已入队"
	return "已相遇"

func _name_for(id: String) -> String:
	if not _known(id):
		return "？？？"
	if id == "hero":
		return "伊文洛" if game.narrative.hero_identity_known() else "旅人"
	return game.run.actor(id).name

func _render_roster() -> void:
	game._clear(roster)
	selected_row = null
	for i in filter_buttons.size():
		_select_style(filter_buttons[i], i == int(state.filter))
	var ids = _visible_ids()
	roster_empty.visible = ids.is_empty()
	if ids.is_empty():
		return
	for id in ids:
		var known = _known(id)
		var button: Button
		if state.grid:
			button = _build_card(id, known)
		else:
			button = game._button(roster, _name_for(id) + ("\n" + _status(id) if known else ""), _select_character.bind(id))
			button.icon = _portrait_thumb(id) if known else _symbol(3)
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width", 48)
			button.custom_minimum_size.y = 58
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.toggle_mode = true
			_select_style(button, state.actor == id)
		button.name = "CodexActor_" + id if known else "CodexUnknown"
		if state.actor == id:
			selected_row = button
	if state.grid:
		for i in range(ids.size(), GRID_COLUMNS):
			var blank = Control.new()
			blank.custom_minimum_size.x = 88
			blank.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			blank.mouse_filter = Control.MOUSE_FILTER_IGNORE
			roster.add_child(blank)

func _visible_ids() -> Array[String]:
	var ids: Array[String] = []
	if state.filter != 2:
		ids.append_array(game.run.joined_ids())
	for id in Catalog.COMPANIONS:
		if state.filter != 1 and _known(id) and not game.run.actor(id).joined:
			ids.append(id)
	if state.filter == 0:
		for id in Catalog.COMPANIONS:
			if not _known(id):
				ids.append(id)
	return ids

func _build_card(id: String, known: bool) -> Button:
	var title = _name_for(id)
	var selected: bool = state.actor == id
	var button: Button = game._button(roster, "", _select_character.bind(id))
	button.accessibility_name = title + " · " + _status(id)
	button.custom_minimum_size = Vector2(88, 224)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var border: Color = game.gold if selected else Color("536456")
	var normal: StyleBoxFlat = game._style(Color("203a34"), border, 8)
	normal.set_border_width_all(2)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", game._style(Color("30483c"), game.gold, 8))
	button.add_theme_stylebox_override("pressed", game._style(Color("3b4f40"), game.gold, 8))
	var body = VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 3)
	button.add_child(body)
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 4
	body.offset_top = 4
	body.offset_right = -4
	body.offset_bottom = -6
	var art = ColorRect.new()
	art.color = Color("32483c")
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.clip_contents = true
	body.add_child(art)
	if known:
		_fill_card_art(art, _character_backdrop(id), Color(0.6, 0.65, 0.61))
	_fill_card_art(art, _portrait_thumb(id, 1.3) if known else _symbol(3),
		Color.WHITE if known else Color(0.31, 0.41, 0.35))
	var name_label: Label = game._text(body, title, 18, game.gold if selected else Color("e8e4d1"))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if known:
		var status_label: Label = game._text(body, _status(id), 13, game.muted)
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		name_label.custom_minimum_size.y = 48
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return button

func _fill_card_art(parent: Control, texture: Texture2D, tint: Color) -> void:
	var layer = _texture(texture)
	layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	layer.modulate = tint
	parent.add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _set_filter(filter: int) -> void:
	state.filter = filter
	var ids = _visible_ids()
	if not ids.is_empty() and state.actor not in ids:
		state.actor = ids[0]
		state.pose = ""
	roster_empty.get_parent().get_parent().scroll_vertical = 0
	_render_roster()
	if not state.grid:
		_render_character()

func _select_character(id: String) -> void:
	if state.actor != id:
		state.pose = ""
	state.actor = id
	if state.grid:
		_set_view(false)
	else:
		_render_roster()
		_render_character()
	if selected_row != null:
		selected_row.grab_focus()

func _render_character() -> void:
	var id: String = state.actor
	var known = _known(id)
	var actor: Dictionary = game.run.actor(id)
	backdrop.texture = _character_backdrop(id) if known and selected_row != null else null
	game._clear(heading)
	game._clear(poses)
	if selected_row == null:
		game._text(heading, "暂无角色", 27, game.gold)
		_update_portrait(id, false)
		_set_tab(int(state.tab))
		return
	game._text(heading, _name_for(id), 27, game.gold)
	var badge = PanelContainer.new()
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var badge_style: StyleBoxFlat = game._style(Color("30443a"), Color("5a6855"), 6)
	badge_style.content_margin_top = 4
	badge_style.content_margin_bottom = 4
	badge.add_theme_stylebox_override("panel", badge_style)
	heading.add_child(badge)
	var status: Label = game._text(badge, _status(id), 15, game.muted)
	status.autowrap_mode = TextServer.AUTOWRAP_OFF
	_render_poses(id, actor.joined)
	_update_portrait(id, known)
	_set_tab(int(state.tab))

func _render_poses(id: String, joined: bool) -> void:
	game._clear(poses)
	if not joined or not ResourceLoader.exists("res://assets/portraits/" + id + "_poses.png"):
		return
	var normal: Button = game._button(poses, "常规", _set_pose.bind(id, ""))
	normal.custom_minimum_size.x = 76
	normal.toggle_mode = true
	_select_style(normal, state.pose == "")
	var expressions = MenuButton.new()
	expressions.text = "表情" if state.pose in ["", "battle"] else POSES[state.pose]
	expressions.custom_minimum_size = Vector2(76, 38)
	expressions.add_theme_stylebox_override("normal", game._style(Color("29413c"), Color("536456"), 6))
	poses.add_child(expressions)
	var keys = POSES.keys().slice(1, -1)
	for key in keys:
		expressions.get_popup().add_item(POSES[key])
	expressions.get_popup().index_pressed.connect(func(index: int): _set_pose(id, keys[index]))
	var battle: Button = game._button(poses, "战斗", _set_pose.bind(id, "battle"))
	battle.custom_minimum_size.x = 76
	battle.toggle_mode = true
	_select_style(battle, state.pose == "battle")

func _set_pose(id: String, pose: String) -> void:
	state.pose = pose
	_update_portrait(id, true)
	_render_poses(id, true)

func _update_portrait(id: String, known: bool) -> void:
	portrait.texture_normal = game._story_portrait(id, state.pose) if known else _symbol(3)
	portrait.disabled = not known or portrait.texture_normal == null
	portrait.modulate = Color.WHITE if known else Color(0.7, 0.76, 0.72, 0.65)
	_fit_portrait()

func _fit_portrait() -> void:
	if not is_instance_valid(portrait) or portrait.texture_normal == null:
		return
	var frame_size = portrait_frame.size
	var source_size = Vector2(portrait.texture_normal.get_size())
	if portrait.disabled:
		portrait.size = Vector2.ONE * minf(frame_size.x, frame_size.y) * 0.42
		portrait.position = (frame_size - portrait.size) * 0.5
	else:
		# Keep the head in frame and let the lower edge crop the transparent margin.
		var overscan = 1.025 if state.pose.is_empty() else 1.075
		portrait.size = source_size * (frame_size.y * overscan / source_size.y)
		portrait.position = Vector2((frame_size.x - portrait.size.x) * 0.5, 0)

func _character_backdrop(id: String) -> Texture2D:
	if id in STORY_BACKDROPS:
		return load("res://assets/story/" + STORY_BACKDROPS[id] + ".png")
	for name in BACKDROP_ATLASES:
		var index: int = BACKDROP_ATLASES[name].find(id)
		if index >= 0:
			var sheet: Texture2D = load("res://assets/ui/codex/" + name + ".webp")
			var tile = Vector2(sheet.get_size()) / Vector2(3, 2)
			var region = AtlasTexture.new()
			region.atlas = sheet
			region.region = Rect2(Vector2(index % 3, floori(float(index) / 3.0)) * tile, tile)
			region.filter_clip = true
			return region
	return null

func _set_tab(index: int) -> void:
	state.tab = index
	for i in tab_buttons.size():
		_select_style(tab_buttons[i], i == index)
	game._clear(details)
	game._clear(footer)
	details.get_parent().scroll_vertical = 0
	var id: String = state.actor
	if selected_row == null:
		game._text(details, "这个分类目前没有角色。", 16, game.muted)
		return
	if not _known(id):
		game._text(details, "在远征途中遇见这位角色后，就能查阅已公开的资料。", 16, game.muted)
		return
	match index:
		0: _overview(id)
		1: _equipment(id)
		2: _piece(id)
		3: _stories(id)

func _overview(id: String) -> void:
	var actor: Dictionary = game.run.actor(id)
	var race = str(actor.get("race", "身份未明"))
	var title = str(actor.get("title", ""))
	if id == "hero":
		var revealed: bool = game.narrative.hero_identity_known()
		race = "神" if revealed else "身份未明"
		title = "死神" if revealed else "旅人"
	elif race == "神":
		title += "的化身"
	game._text(details, title + " · " + race, 19, game.gold)
	var element = str(actor.get("element", "none"))
	game._text(details, "属性 · " + Catalog.ELEMENT_NAMES.get(element, "无常规属性"), 16)
	var introduction = "在村庄醒来的旅人，会用重力魔法。" if id == "hero" else "在这次远征中遇见的伙伴。"
	if id == "hero" and game.narrative.hero_identity_known():
		introduction = "想起自己姓名和来历的死神，能用重力引渡亡魂。"
	elif id != "hero" and game.run.data.story[id].get("codex_past_read", false):
		introduction = game.narrative.CHARACTER_BEHAVIOR[id][0]
	game._text(details, introduction, 16)
	if not actor.joined:
		return
	game._text(details, "当前状态", 19, game.gold)
	var condition = "重伤 · " if actor.hp <= 0 else ""
	game._text(details, "%sHP %d/%d · MP %d/%d" % [condition, actor.hp, actor.hp_max, actor.mp, actor.mp_max], 16)

func _equipment(id: String) -> void:
	if not game.run.actor(id).joined:
		game._text(details, "尚未加入远征队。", 16, game.muted)
		return
	game._text(details, "装备编入全队卡组，开战后可打给任意友方棋子。", 16)
	for uid in game.run.gear_owned("actor", id):
		var item: Dictionary = game.run.data.gear_instances[uid]
		var card := Gear.card(item)
		game._text(details, card.name, 18, game.gold)
		game._text(details, card.trait, 15)
	var manage: Button = game._button(footer, "管理装备牌", game._inventory_dialog.bind(id, 1), game.run.data.status != "exploring")
	manage.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _piece(id: String) -> void:
	var piece := Chess.commander_definition(game.run) if id == "hero" else Cards.owned_definition(id, game.run.data.actors)
	game._text(details, "主战者 · 开局登场" if id == "hero" else "伙伴 · 部署至己方半场", 18, game.gold)
	game._text(details, Cards.stats(piece), 16)
	game._text(details, piece.trait, 16)
	if id == "cen":
		game._text(details, "森林采集时多拿一份。", 16)
	elif id == "grit":
		game._text(details, "可辨识已发现敌方主战者的属性。", 16)
	if id != "hero":
		_breakthroughs(id)

func _breakthroughs(id: String) -> void:
	var person: Dictionary = game.run.actor(id)
	var rank := int(person.get("breakthrough", 0))
	game._text(details, "突破 %d / 3 · 持有 %d 灯铢" % [rank, game.run.data.lamp_coins], 18, game.gold)
	var talent := Cards.breakthrough_talent(id)
	for index in Cards.BREAKTHROUGH_PRICES.size():
		var benefit: String = Cards.BREAKTHROUGH_BENEFITS[index]
		if index == 2:
			benefit = "攻击 +1 · " + talent.name
		var cost := "已完成" if index < rank else "%d 灯铢" % Cards.BREAKTHROUGH_PRICES[index]
		game._text(details, "%d 阶 · %s · %s" % [index + 1, benefit, cost], 15, game.ink if index < rank else game.muted)
	if rank < 3:
		game._text(details, talent.text, 15, game.muted)
	if not person.joined:
		game._text(details, "招募后解锁伙伴牌和突破。", 15, game.muted)
	elif rank < Cards.BREAKTHROUGH_PRICES.size():
		var quote: Dictionary = game.run.breakthrough_quote(id)
		var feedback: Label = game._text(details, str(quote.get("message", "")), 15, game.gold)
		feedback.visible = not quote.ok
		var upgrade: Button = game._button(footer, "突破至 %d 阶 · %d 灯铢" % [rank + 1, Cards.BREAKTHROUGH_PRICES[rank]], func():
			var result: Dictionary = game.run.breakthrough_companion(id, rank)
			if result.ok:
				game._refresh()
				_set_tab(2)
			else:
				feedback.text = result.message
				feedback.show(), not quote.ok)
		upgrade.name = "ConfirmCompanionBreakthrough"
		upgrade.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _stories(id: String) -> void:
	if id != "hero" and game.run.actor(id).joined and game.run.data.status == "exploring" \
			and game.narrative.encounter_intro(game.selected_id, id).ok:
		game._button(footer, "交谈", game._talk.bind(id)).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var records: Array = game.narrative.character_records(id)
	for record in records:
		game._text(details, record.title, 18, game.gold)
		var body: String = record.get("body", "")
		if body.is_empty():
			game._text(details, record.hint, 15, game.muted)
		else:
			game._button(details, "阅读 · " + record.title, game._read_character_record.bind(id, record))

func _select_style(button: Button, selected: bool) -> void:
	button.set_pressed_no_signal(selected)
	button.add_theme_stylebox_override("pressed", game._style(Color("34483a"), game.gold, 6))
	button.add_theme_color_override("font_pressed_color", game.gold)

func _symbol(index: int) -> Texture2D:
	var atlas = AtlasTexture.new()
	atlas.atlas = SYMBOLS
	atlas.region = Rect2(64 * index, 0, 64, 64)
	atlas.filter_clip = true
	return atlas

func _portrait_thumb(id: String, aspect: float = 1.0) -> Texture2D:
	var texture: Texture2D = game._story_portrait(id)
	if texture == null:
		return _symbol(3)
	var size = texture.get_size()
	var side = minf(size.x, size.y) * 0.5
	var atlas = AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(Vector2((size.x - side) * 0.5, size.y * 0.02), Vector2(side, side / aspect))
	atlas.filter_clip = true
	return atlas

func _texture(texture: Texture2D, minimum: Vector2 = Vector2.ZERO) -> TextureRect:
	var image = TextureRect.new()
	image.texture = texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if minimum != Vector2.ZERO else TextureRect.STRETCH_SCALE
	image.custom_minimum_size = minimum
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image

func _open_zoom() -> void:
	if is_instance_valid(zoom) or portrait.disabled:
		return
	zoom = ColorRect.new()
	zoom.name = "CodexPortraitZoom"
	zoom.color = Color(0.05, 0.09, 0.08, 0.98)
	game.modal_layer.add_child(zoom)
	zoom.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fill_card_art(zoom, backdrop.texture, Color(0.52, 0.58, 0.55))
	var image = _texture(portrait.texture_normal, Vector2.ONE)
	zoom.add_child(image)
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.offset_top = 48
	image.offset_bottom = -24
	var close: Button = game._button(zoom, "关闭立绘", close_zoom)
	close.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	close.position.x -= 130
	close.position.y = 12
	close.grab_focus()

func close_zoom() -> bool:
	if not is_instance_valid(zoom):
		return false
	game.modal_layer.remove_child(zoom)
	zoom.queue_free()
	zoom = null
	portrait.grab_focus()
	return true
