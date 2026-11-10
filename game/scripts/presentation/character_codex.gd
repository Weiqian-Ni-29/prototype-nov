extends PanelContainer

const Catalog = preload("res://scripts/domain/catalog.gd")
const Gear = preload("res://scripts/domain/gear_catalog.gd")
const SYMBOLS = preload("res://assets/ui/codex-symbols.svg")
const POSES = {"": "常规", "serious": "严肃", "friendly": "友善", "grief": "悲伤", "anger": "愤怒", "surprise": "惊讶", "battle": "战斗"}
const FILTERS = ["全部", "已入队", "见过未加入"]
const TABS = ["概览", "装备", "技能", "故事"]
const SLOT_NAMES = {"weapon": "武器", "armor": "护甲", "accessory": "饰品"}
const STAT_NAMES = {"attack": "攻击", "defense": "防御", "speed": "速度"}

var game: Node
var state: Dictionary
var roster: VBoxContainer
var portrait: TextureButton
var poses: HBoxContainer
var heading: HBoxContainer
var details: VBoxContainer
var footer: HBoxContainer
var filter_buttons: Array[Button] = []
var tab_buttons: Array[Button] = []
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
	var close = game._button(bar, "×", game._close_character_codex)
	close.name = "CloseCodex"
	close.tooltip_text = "关闭角色图鉴"
	box.add_child(HSeparator.new())
	var columns = HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 14)
	box.add_child(columns)
	_build_roster(columns)
	_build_portrait(columns)
	_build_details(columns)
	_render_roster()
	_render_character()
	if selected_row != null:
		selected_row.grab_focus()

func _build_roster(columns: HBoxContainer) -> void:
	var list_column = VBoxContainer.new()
	list_column.custom_minimum_size.x = 206
	list_column.add_theme_constant_override("separation", 8)
	columns.add_child(list_column)
	var first_row = HBoxContainer.new()
	list_column.add_child(first_row)
	for i in FILTERS.size():
		var parent: Container = first_row if i < 2 else list_column
		var button: Button = game._button(parent, FILTERS[i], _set_filter.bind(i))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		filter_buttons.append(button)
	var found = 0
	for id in Catalog.COMPANIONS:
		found += int(_known(id))
	game._text(list_column, "已相遇 %d / %d" % [found, Catalog.COMPANIONS.size()], 13, game.muted)
	roster = game._scroll_content(list_column)
	roster.name = "CodexRoster"
	roster.get_parent().horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	roster.get_parent().follow_focus = true
	columns.add_child(VSeparator.new())

func _build_portrait(columns: HBoxContainer) -> void:
	var center = VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size.x = 230
	center.add_theme_constant_override("separation", 9)
	columns.add_child(center)
	var frame = PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", game._style(Color("263a30"), Color("51604c"), 6))
	center.add_child(frame)
	var gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color("586047"), Color("22352d")])
	var glow = GradientTexture2D.new()
	glow.gradient = gradient
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.51, 0.37)
	glow.fill_to = Vector2(0.98, 0.96)
	frame.add_child(_texture(glow))
	portrait = TextureButton.new()
	portrait.name = "CodexPortrait"
	portrait.ignore_texture_size = true
	portrait.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	portrait.tooltip_text = "放大立绘"
	portrait.pressed.connect(_open_zoom)
	frame.add_child(portrait)
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
	var ids: Array = game.run.joined_ids()
	for id in Catalog.COMPANIONS:
		if _known(id) and not game.run.actor(id).joined:
			ids.append(id)
	if state.filter == 0:
		for id in Catalog.COMPANIONS:
			if not _known(id):
				ids.append(id)
	for id in ids:
		var joined: bool = game.run.actor(id).joined
		if (state.filter == 1 and not joined) or (state.filter == 2 and joined):
			continue
		var known = _known(id)
		var thumb = _portrait_thumb(id) if known else _symbol(3)
		var button: Button = game._button(roster, _name_for(id) + ("\n" + _status(id) if known else ""), _select_character.bind(id))
		button.name = "CodexActor_" + id if known else "CodexUnknown"
		button.icon = thumb
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 48)
		button.custom_minimum_size.y = 58
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		_select_style(button, state.actor == id)
		if state.actor == id:
			selected_row = button
	if roster.get_child_count() == 0:
		game._text(roster, "还没有见过未加入的伙伴。", 15, game.muted)

func _set_filter(filter: int) -> void:
	state.filter = filter
	var actor: Dictionary = game.run.actor(state.actor)
	if filter == 1 and not actor.joined:
		_select_character(game.run.joined_ids()[0])
	elif filter == 2 and (actor.joined or not _known(state.actor)):
		for id in Catalog.COMPANIONS:
			if _known(id) and not game.run.actor(id).joined:
				_select_character(id)
				return
	_render_roster()
	_render_character()

func _select_character(id: String) -> void:
	state.actor = id
	state.pose = ""
	_render_roster()
	_render_character()
	if selected_row != null:
		selected_row.grab_focus()

func _render_character() -> void:
	var id: String = state.actor
	var known = _known(id)
	var actor: Dictionary = game.run.actor(id)
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
		2: _skills(id)
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
	game._text(details, "%sHP %d/%d · MP %d/%d\n充能 %d%%" % [condition, actor.hp, actor.hp_max, actor.mp, actor.mp_max, actor.energy], 16)
	game._text(details, "攻击 %d · 防御 %d · 速度 %d" % [game.run.stat(id, "attack"), game.run.stat(id, "defense"), game.run.stat(id, "speed")], 16)

func _equipment(id: String) -> void:
	var actor: Dictionary = game.run.actor(id)
	if not actor.joined:
		game._text(details, "尚未加入远征队。", 16, game.muted)
		return
	for slot in Gear.SLOTS:
		var uid: String = actor.equipment.get(slot, "")
		var item: Dictionary = game.run.data.gear_instances.get(uid, {})
		var card = PanelContainer.new()
		card.add_theme_stylebox_override("panel", game._style(Color("203a34"), Color("4c6051"), 6))
		details.add_child(card)
		var content = VBoxContainer.new()
		card.add_child(content)
		var row = HBoxContainer.new()
		content.add_child(row)
		var icon = _texture(_symbol(Gear.SLOTS.find(slot)), Vector2(48, 48))
		row.add_child(icon)
		var labels = VBoxContainer.new()
		labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(labels)
		game._text(labels, SLOT_NAMES[slot], 13, game.muted)
		if item.is_empty():
			game._text(labels, "未装备", 17)
			continue
		var definition: Dictionary = Gear.DATA[item.definition_id]
		game._text(labels, definition.name, 18, game.gold)
		var quality: String = Gear.QUALITY_NAMES[Gear.QUALITIES.find(item.quality)]
		var summary: Array[String] = ["%s +%d" % [quality, item.enhance_level]]
		for stat in definition.stats:
			summary.append("%s +%d" % [STAT_NAMES[stat], Gear.bonus(item, stat)])
		game._text(labels, " · ".join(summary), 14)
		var expanded = VBoxContainer.new()
		content.add_child(expanded)
		expanded.hide()
		game._text(expanded, definition.effect, 15)
		if not definition.set_id.is_empty():
			var set_info: Dictionary = Gear.SETS[definition.set_id]
			var count: int = game.run.set_count(id, definition.set_id)
			game._text(labels, "%s · %d / 3" % [set_info.name, count], 14, game.muted)
			if not set_info.two.is_empty():
				game._text(expanded, ("已激活 · " if count >= 2 else "未激活 · ") + set_info.two, 15)
			if not set_info.three.is_empty():
				game._text(expanded, ("已激活 · " if count >= 3 else "未激活 · ") + set_info.three, 15)
		game._button(row, "详情", func(): expanded.visible = not expanded.visible)
	var manage: Button = game._button(footer, "管理装备", game._inventory_dialog.bind(id, 1), game.run.data.status != "exploring")
	manage.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _skills(id: String) -> void:
	var actor: Dictionary = game.run.actor(id)
	if not actor.joined:
		game._text(details, "入队后可查看这位角色的技能。", 16, game.muted)
		return
	for skill in [["普通攻击", "attack"], ["主动技能", actor.skill], ["终结技", actor.ultimate]]:
		var heading_text: String = skill[0] if skill[1] == "attack" else skill[0] + " · " + Catalog.SKILLS[skill[1]].name
		game._text(details, heading_text, 18, game.gold)
		var description = Catalog.skill_description(skill[1])
		if skill[0] == "终结技":
			description += "。充能到 100% 后可释放。"
		game._text(details, description, 16)
	var passive = Catalog.passive_description(id)
	game._text(details, "专长", 18, game.gold)
	game._text(details, "暂无额外专长。" if passive.is_empty() else passive, 16)

func _stories(id: String) -> void:
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

func _portrait_thumb(id: String) -> Texture2D:
	var texture: Texture2D = game._story_portrait(id)
	if texture == null:
		return _symbol(3)
	var size = texture.get_size()
	var side = minf(size.x, size.y) * 0.5
	var atlas = AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(Vector2((size.x - side) * 0.5, size.y * 0.02), Vector2(side, side))
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
