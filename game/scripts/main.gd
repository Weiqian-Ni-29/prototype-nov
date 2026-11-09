extends Node
const Run = preload("res://scripts/domain/expedition.gd")
const Catalog = preload("res://scripts/domain/catalog.gd")
const Hex = preload("res://scripts/domain/hex_map.gd")
const Combat = preload("res://scripts/domain/battle.gd")
const Story = preload("res://scripts/domain/narrative.gd")
const Relics = preload("res://scripts/domain/relic_catalog.gd")
const Gear = preload("res://scripts/domain/gear_catalog.gd")
var item_operation_serial = 0
const Nodes = preload("res://scripts/domain/map_nodes.gd")
const OpeningStory = preload("res://scripts/domain/opening_story.gd")
const StoryPortrait = preload("res://scripts/presentation/story_portrait.gdshader")
const World = preload("res://scripts/presentation/world_view.gd")
const MapMovePreview = preload("res://scripts/presentation/map_move_preview.gd")
const FontAsset = preload("res://assets/fonts/NotoSansSC.ttf")
const Sound = preload("res://scripts/presentation/sound.gd")
enum Screen { MENU, OPENING_STORY, EXPEDITION }
const OBJECTIVE_ICON = preload("res://assets/ui/expedition-objective.svg")
const STORY_TERRAIN = {
	"plains": "road", "forest": "woodland", "mountain": "highland", "ruins": "ruins",
	"desert": "drylands", "swamp": "wetlands",
}
var run = Run.new()
var view: Node3D
var ui: Control
var modal_layer: Control
var combat: RefCounted
var selected_id = "hero"
var selected_cell = ""
var move_target = ""
var move_from_current_cell = false
var move_preview = MapMovePreview.new()
var moving_ids: Array = ["hero"]
var crew_collapsed = false
var chosen_seed = ""
var opening_seed = 20261104
var selected_target = "enemy_0"
var screen_state = Screen.MENU
var battle_timer = 0.0
var toast_text = ""
var narrative: RefCounted
var dialogue_subject = ""
var dialogue_response = ""
var dialogue_ready = false
var sound: Node
var gold = Color("dec38e")
var ink = Color("e8e4d1")
var muted = Color("a2b3a7")

func _ready() -> void:
	DisplayServer.window_set_title("维洛丹")
	sound = Sound.new()
	add_child(sound)
	view = World.new()
	add_child(view)
	view.cell_clicked.connect(_select_cell)
	view.squad_clicked.connect(_select_actor)
	view.enemy_clicked.connect(_select_battle_target)
	view.presentation_changed.connect(func(): call_deferred("_refresh"))
	view.sound_cue.connect(func(kind: String): sound.play(kind))
	var canvas = CanvasLayer.new()
	canvas.layer = 2
	add_child(canvas)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme = Theme.new()
	var font = FontVariation.new()
	font.base_font = FontAsset
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 500.0}
	font.variation_embolden = 0.25
	theme.default_font = font
	theme.default_font_size = 19
	theme.set_color("font_color", "Label", ink)
	theme.set_color("font_color", "Button", ink)
	theme.set_stylebox("normal", "Button", _style(Color("29413c"), Color("536456"), 6))
	theme.set_stylebox("hover", "Button", _style(Color("3a5146"), gold, 6))
	theme.set_stylebox("pressed", "Button", _style(Color("53604a"), gold, 6))
	theme.set_stylebox("disabled", "Button", _style(Color("22332f"), Color("34463d"), 6))
	theme.set_color("font_disabled_color", "Button", Color("718077"))
	theme.set_color("font_color", "TooltipLabel", ink)
	theme.set_stylebox("panel", "TooltipPanel", _style(Color("19332f"), gold.darkened(0.25), 8))
	theme.set_stylebox("panel", "PopupMenu", _style(Color("233c36"), gold, 6))
	theme.set_stylebox("normal", "LineEdit", _style(Color("213831"), Color("647460"), 5))
	theme.set_stylebox("background", "ProgressBar", _bar_style(Color("152d2b")))
	theme.set_stylebox("fill", "ProgressBar", _bar_style(Color("92aa7a")))
	move_preview.camera = view.camera
	move_preview.theme = theme
	canvas.add_child(move_preview)
	ui.theme = theme
	canvas.add_child(ui)
	modal_layer = Control.new()
	modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_layer.theme = theme
	canvas.add_child(modal_layer)
	run.new_run(20261104, "wayfarer")
	narrative = Story.new(run)
	get_viewport().size_changed.connect(func():
		if screen_state != Screen.EXPEDITION:
			_refresh())
	_refresh()
	if "--smoke" in OS.get_cmdline_user_args():
		run.save_path = "user://smoke-run.json"
		_start_new()
		get_tree().create_timer(4.0).timeout.connect(_smoke_capture)

func _style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0 else 0)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style

func _text(parent: Node, text: String, size: int = 17, color: Color = Color("e8e4d1")) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size + 2 if size < 25 else size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, callback: Callable, disabled: bool = false) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size.y = 38
	button.disabled = disabled
	button.pressed.connect(func(): sound.play("click"); callback.call())
	parent.add_child(button)
	return button

func _hp_bar(parent: Node, hp: float, maximum: float, enemy: bool = false) -> void:
	var bar = ProgressBar.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.value = hp / maxf(1.0, maximum) * 100
	bar.show_percentage = false
	bar.custom_minimum_size.y = 6
	if enemy:
		bar.add_theme_stylebox_override("fill", _bar_style(Color("bd8b6e")))
	parent.add_child(bar)

func _bar_style(color: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(3)
	return style

func _panel(parent: Node, rectangle: Rect2, background: Color = Color("19332ff2")) -> VBoxContainer:
	var panel = PanelContainer.new()
	panel.position = rectangle.position
	panel.size = rectangle.size
	panel.add_theme_stylebox_override("panel", _style(background, Color("5a6855"), 10))
	parent.add_child(panel)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	return box

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _scroll_content(parent: Node) -> VBoxContainer:
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 9)
	scroll.add_child(content)
	return content

func _refresh() -> void:
	_clear(ui)
	var screen = get_viewport().get_visible_rect().size
	var in_expedition = screen_state == Screen.EXPEDITION
	var world_visible = in_expedition and not modal_layer.has_node("StoryScreen")
	view.visible = world_visible
	view.set_process(world_visible)
	_update_world_input()
	move_preview.hide()
	if screen_state == Screen.MENU:
		_menu(screen)
		return
	if screen_state == Screen.OPENING_STORY:
		return
	view.refresh(run, selected_id, selected_cell)
	_header(screen)
	if combat != null:
		_battle_ui(screen)
	elif run.data.status in ["won", "failed"]:
		_summary(screen)
		_footer(screen)
	else:
		_crew_panel(screen)
		if not move_target.is_empty() and modal_layer.get_child_count() == 0:
			_show_move_preview()

func _menu(screen: Vector2) -> void:
	var cover = _opening_image(_story_texture("cover"))
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box = VBoxContainer.new()
	box.position = Vector2(screen.x * 0.06, screen.y * 0.24)
	box.size.x = minf(365, screen.x * 0.28)
	box.add_theme_constant_override("separation", 12)
	ui.add_child(box)
	_text(box, "维洛丹", 64, ink)
	_text(box, "VEYLODAN", 14, gold)
	_text(box, "从一座村庄醒来，找到结束战争的办法。", 18, ink)
	var new_run = _button(box, "开始新远征  →", _begin_opening_story)
	new_run.custom_minimum_size.y = 52
	new_run.add_theme_stylebox_override("normal", _style(Color("486054"), gold.darkened(0.2), 6))
	_button(box, "继续上次远征", _continue_run, not FileAccess.file_exists(run.save_path))
	_button(box, "地图种子", _seed_dialog)
	_button(box, "设置与操作指南", _settings_dialog)

func _opening_image(texture: Texture2D) -> TextureRect:
	var illustration = TextureRect.new()
	illustration.texture = texture
	illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	illustration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(illustration)
	return illustration

func _show_opening(state: Screen) -> void:
	screen_state = state
	_refresh()

func _seed_dialog() -> void:
	var box = _modal("地图种子", 500, 250)
	var field = LineEdit.new()
	field.text = chosen_seed
	field.placeholder_text = "留空时，每次出发随机生成"
	box.add_child(field)
	_button(box, "确定", func():
		chosen_seed = field.text.strip_edges()
		_close_modal())

func _begin_opening_story() -> void:
	_show_opening(Screen.OPENING_STORY)
	opening_seed = randi() if chosen_seed.is_empty() else _seed_value()
	var generated = Hex.generate(opening_seed)
	var terrain: String = generated.tiles[generated.start].terrain
	_opening_world_page(terrain, 0)

func _opening_world_page(terrain: String, index: int) -> void:
	var pages = OpeningStory.WORLD.split("\n\n")
	_show_story("诸神的战争", "旁白", pages[index], "world_intro", [], [],
		func(_option: String):
			if index + 1 < pages.size():
				_opening_world_page(terrain, index + 1)
			else:
				_village_page(terrain, 0),
		{"返回主菜单": _cancel_opening})

func _cancel_opening() -> void:
	_close_modal()
	_show_opening(Screen.MENU)

func _village_page(terrain: String, index: int) -> void:
	var local = OpeningStory.village(terrain)
	var villager = "villager_" + str(local[1])
	var poses = ["concerned", "", "serious", "serious", "", "farewell", "farewell"]
	var pages = OpeningStory.dialogue(terrain)
	var page = pages[index]
	_show_story(local[0], page[0], page[1], "village_" + terrain,
		[_story_portrait("hero", "serious")] if page[0] == "旅人" else [_story_portrait(villager, poses[index])], [],
		func(_option: String):
			if index + 1 < pages.size():
				_village_page(terrain, index + 1)
			else:
				_start_new(),
		{"返回主菜单": _cancel_opening})

func _seed_value() -> int:
	if chosen_seed.is_empty():
		return 20261104
	return int(chosen_seed) if chosen_seed.is_valid_int() else hash(chosen_seed)

func _start_new() -> void:
	_close_modal()
	var value = opening_seed if screen_state == Screen.OPENING_STORY else _seed_value()
	run.new_run(value, "wayfarer")
	combat = null
	_clear_map_move()
	view.reset()
	selected_id = "hero"
	moving_ids = ["hero"]
	selected_cell = run.data.start
	screen_state = Screen.EXPEDITION
	view.refresh(run, selected_id, selected_cell)
	view.focus_cell(selected_cell)
	toast_text = ""
	run.save_game()
	_refresh()

func _continue_run() -> void:
	var result = run.load_game()
	if not result.ok:
		_notice(result.message)
		return
	combat = null
	_clear_map_move()
	toast_text = ""
	view.reset()
	selected_id = "hero"
	moving_ids = _squad_movers("hero")
	selected_cell = run.actor("hero").position
	screen_state = Screen.EXPEDITION
	view.refresh(run, selected_id, selected_cell)
	view.focus_cell(selected_cell)
	_refresh()
	if not run.data.pending_battle.is_empty():
		_formation_dialog()
	elif run.data.has("pending_victory"):
		_victory_dialog()
	elif not _show_chapter() and not _show_relic_intro():
		_show_npc_encounter(selected_id)

func _header(screen: Vector2) -> void:
	var box = _panel(ui, Rect2(20, 17, screen.x - 40, 88))
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	_text(row, "维洛丹", 29, gold).custom_minimum_size.x = 190
	var weather = "细雨" if run.data.weather == "rain" else "晴朗"
	var exploration = floori(100.0 * run.data.explored.size() / run.data.tiles.size())
	var conditions = HBoxContainer.new()
	conditions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	conditions.add_theme_constant_override("separation", 20)
	row.add_child(conditions)
	_text(conditions, "第 %d 天  ·  %s\n探索度：%d%%" % [run.data.day, weather, exploration], 16).custom_minimum_size.x = 168
	if combat == null and run.data.status == "exploring":
		var tile = run.data.tiles[run.actor(selected_id).position]
		var terrain = _text(conditions, Catalog.terrain_name(tile.terrain), 18)
		terrain.autowrap_mode = TextServer.AUTOWRAP_OFF
		terrain.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		terrain.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var objective = HBoxContainer.new()
	objective.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	objective.add_theme_constant_override("separation", 10)
	row.add_child(objective)
	var marker = TextureRect.new()
	marker.texture = OBJECTIVE_ICON
	marker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	marker.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	marker.custom_minimum_size = Vector2(36, 36)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective.add_child(marker)
	_text(objective, _expedition_objective(), 16, gold).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_button(row, "设置/帮助", _settings_dialog)
	_button(row, "旅途手记", _journal)
	_button(row, "主菜单", _to_menu)

func _expedition_objective() -> String:
	if run.data.status in ["won", "failed"]:
		return "旅程已结束"
	return [
		"踏出旅程的第一步",
		"帮助被亡灵困扰的地方",
		"查清谁在延长战争",
		"找到战神的驻地",
		"击败战神卡德兰",
	][int(run.data.chapter)]


func _crew_panel(screen: Vector2) -> void:
	var box = _panel(ui, Rect2(20, 120, 244, 56 if crew_collapsed else screen.y - 275))
	var heading = HBoxContainer.new()
	box.add_child(heading)
	_text(heading, "远征队", 24, gold).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_button(heading, "展开" if crew_collapsed else "收起", func():
		crew_collapsed = not crew_collapsed
		_refresh())
	if crew_collapsed:
		return
	var hint = "点相邻格预览 · 再点确认" if move_from_current_cell else "点箭头选队 · 点相邻格移动"
	_text(box, hint + "\n远征队持有 %d 灯铢" % run.data.lamp_coins, 13, muted)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var roster = VBoxContainer.new()
	roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster.add_theme_constant_override("separation", 10)
	scroll.add_child(roster)
	for squad in run.squad_groups():
		var frame = PanelContainer.new()
		frame.name = "SquadFrame_" + str(squad.id)
		var color: Color = view.squad_markers.color_for_actor(squad.members[0])
		var style = _style(Color("294039") if selected_id in squad.members else Color("20352e"), color, 7)
		style.set_border_width_all(3 if selected_id in squad.members else 2)
		frame.add_theme_stylebox_override("panel", style)
		roster.add_child(frame)
		var member_box = VBoxContainer.new()
		frame.add_child(member_box)
		for id in squad.members:
			var a = run.actor(id)
			var row = HBoxContainer.new()
			member_box.add_child(row)
			var squad_color: Color = view.squad_markers.color_for_actor(id)
			var swatch = _text(row, "▼", 19, squad_color)
			swatch.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			swatch.tooltip_text = "同色箭头与边框标记同一小队"
			var toggle = CheckBox.new()
			toggle.button_pressed = id in moving_ids
			toggle.disabled = a.hp <= 0
			toggle.toggled.connect(_toggle_mover.bind(id))
			row.add_child(toggle)
			var text = ("◆ " if selected_id == id else "") + a.name + ("  重伤" if a.hp <= 0 else "")
			var button = _button(row, text, _select_actor.bind(id))
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if selected_id in squad.members:
				button.add_theme_stylebox_override("normal", _style(Color("354f48"), squad_color, 6))
			_text(member_box, "HP %d/%d   MP %d/%d\n精力 %d/%d  ·  充能 %d%%" % [a.hp, a.hp_max, a.mp, a.mp_max, a.ap, a.ap_max, a.energy], 13, muted)
			var bar = ProgressBar.new()
			bar.value = float(a.hp) / a.hp_max * 100
			bar.show_percentage = false
			bar.custom_minimum_size.y = 5
			member_box.add_child(bar)
	var cell: String = run.actor(selected_id).position
	var node = run.node_at(cell)
	var action = _button(box, "行动 · " + Nodes.label(node.get("kind", "story")), _cell_actions)
	action.tooltip_text = _node_title(cell)
	_button(box, "背包", _inventory_dialog.bind(selected_id))
	_button(box, "结束一天", _end_day_dialog)

func _cell_actions() -> void:
	var actor = run.actor(selected_id)
	var cell: String = actor.position
	var t = run.data.tiles[cell]
	var node = run.node_at(cell)
	var title = _node_title(cell)
	var dialog = _modal(title, 570, 580)
	var box = _scroll_content(dialog)
	_text(box, "%s · 坐标 %s" % [Catalog.terrain_name(t.terrain), cell], 14, muted)
	if (t.site.is_empty() or (t.site == "boss" and not run.boss_known())) and not Nodes.story(node).is_empty():
		_button(box, "查看节点剧情", _node_dialog)
	if run.knows_encounter(cell):
		_text(box, "决战 · 已平息 %d 处纷争" % run.data.peace.size() if t.enemies.has("war_god") else "驻守敌人", 18, Color("e4ab87"))
		_text(box, "首次上场每人 2 精力；同地最多四名角色出战。", 14, muted)
		for enemy in t.enemies:
			_text(box, Catalog.ENEMIES[enemy].name + " · " + Catalog.ENEMIES[enemy].role, 14, muted)
			if run.actor("grit").joined and run.actor("grit").hp > 0 and run.actor("grit").position == cell:
				var definition = run.war_god_stats() if enemy == "war_god" else Catalog.ENEMIES[enemy]
				_text(box, "砾牙辨识：HP %d · 攻击 %d · 速度 %d" % [definition.hp, definition.attack, definition.speed], 13, gold)
		var eligible = run.same_cell(cell, true).any(func(id): return Combat.can_deploy(run.actor(id), {}))
		var requires_hero = t.enemies.has("war_god") and ("hero" not in run.same_cell(cell, true) or run.actor("hero").ap < Catalog.BATTLE_AP)
		if requires_hero:
			_text(box, "需要旅人到场并保留 2 点精力。", 15, muted)
		_button(box, "选择阵容并交战", _open_current_encounter, not eligible or requires_hero)
	if t.npc != "" and t.npc != selected_id and run.actor(t.npc).position == cell and t.enemies.is_empty():
		var npc = run.actor(t.npc)
		_text(box, npc.name + " · " + npc.title, 18)
		_button(box, "交谈 / 个人故事", _talk.bind(t.npc))
	elif t.site == "start":
		_button(box, "看看村庄", _site_impression)
	for id in run.same_cell(cell):
		if id != "hero" and id != t.npc and id != selected_id:
			_button(box, "与 " + run.actor(id).name + " 交谈", _talk.bind(id))
	if t.quantity > 0 and (node.get("kind") != "supply" or not t.site.is_empty()):
		_text(box, "可采集：%s ×%d" % [Catalog.item_name(t.resource), t.quantity], 16, muted)
		_button(box, "采集 · 1 精力", func(): _close_modal(); _run_action(run.collect(selected_id)))
	var relic: String = run.relic_sites.get(cell, "")
	if node.get("kind") != "cache" and not relic.is_empty() and t.enemies.is_empty() and not run.data.relic_claims.has("site:" + cell):
		_button(box, "调查" + Relics.SITES[relic][0], func():
			_close_modal()
			var result = run.investigate_relic(selected_id)
			_run_action(result)
			if result.ok and not _show_relic_intro():
				_notice(result.message))
	_button(box, "使用道具 / 同地救援", _item_dialog.bind(selected_id))
	if actor.skill == "heal":
		_button(box, "治疗队友 · 1 精力 / 12 MP", _healing_dialog)
	_button(box, "拆分小队", _split_squad_dialog).disabled = run.squad_members(selected_id).size() < 2
	_button(dialog, "关闭", _close_modal)

func _node_title(cell: String) -> String:
	var tile = run.data.tiles[cell]
	if not tile.site.is_empty() and (tile.site != "boss" or run.boss_known()):
		return World._site_name(tile.site)
	return Nodes.story(run.node_at(cell)).get("title", Catalog.terrain_name(tile.terrain))

func _site_impression() -> void:
	var cell: String = run.actor(selected_id).position
	var terrain: String = run.data.tiles[cell].terrain
	_show_story(_node_title(cell), "村民", "你回来啦。来喝口水吧。路上遇到难事的话，也可以坐下慢慢说。",
		STORY_TERRAIN[terrain], [], [_node_option("leave", "返回地图")], func(_choice: String): _close_modal(), {}, _node_tint())

func _node_resolved(node: Dictionary, tile: Dictionary) -> bool:
	return not node.result.is_empty() or (node.kind == "supply" and tile.quantity <= 0) \
		or (node.kind in ["battle", "elite"] and tile.enemies.is_empty())

func _node_tint() -> Color:
	if run.data.weather == "rain":
		return Color(0.78, 0.88, 1.0)
	return Color.WHITE

func _node_description(node: Dictionary, tile: Dictionary, event: Dictionary) -> String:
	if _node_resolved(node, tile):
		var conclusion = Nodes.resolution(node)
		if node.kind == "haunt":
			return "旅人顺着灵魂牵动的方向伸手，周围的碎石微微浮起。一条肉眼看不见的归路，在亡者面前展开。\n\n" + conclusion
		return conclusion
	if node.get("investigated", false):
		return str(event.investigation)
	return str(event.intro)

func _node_option(id: String, label: String) -> Dictionary:
	return {"id": id, "text": label}

func _node_dialog(feedback: String = "", ready: bool = false) -> void:
	var cell: String = run.actor(selected_id).position
	var tile = run.data.tiles[cell]
	var node = run.node_at(cell)
	var event = Nodes.story(node)
	if event.is_empty():
		_cell_actions()
		return
	var text = _node_description(node, tile, event)
	var after_flag: String = event.get("after_flag", "")
	if not after_flag.is_empty() and run.data.flags.get(after_flag, false):
		text += "\n" + str(event.get("after_text", ""))
	var speaker: String = event.get("reaction_actor", "")
	if speaker in run.same_cell(cell, true) and event.has("reaction"):
		text += "\n%s说「%s」" % [run.actor(speaker).name, event.reaction]
	if run.data.leads.has(cell):
		text += "\n已把这里的线索记进手记。"
	if not feedback.is_empty():
		text += "\n" + feedback
	if node.kind in ["choice", "haunt"] and not _node_resolved(node, tile) and not ready and feedback.is_empty():
		_show_story(event.title, Catalog.terrain_name(tile.terrain), text, STORY_TERRAIN[tile.terrain], [], [],
			func(_option: String): _node_dialog("", true), {"返回地图": _close_modal}, _node_tint())
		return
	var options: Array = []
	if not _node_resolved(node, tile):
		match node.kind:
			"trade":
				options.append(_node_option("trade", "查看货物 · 持有 %d 灯铢" % run.data.lamp_coins))
			"supply":
				options.append(_node_option("collect", "采集%s ×%d · 1 精力" % [Catalog.item_name(tile.resource), tile.quantity]))
			"rest":
				options.append(_node_option("hp", "在此休整 · 同格可行动队员恢复 %d%% 生命" % run.recovery_percent(cell, "hp")))
				options.append(_node_option("mp", "在此调息 · 同格可行动队员恢复 %d%% 魔力" % run.recovery_percent(cell, "mp")))
				options.append(_node_option("pack", "带走一份" + Catalog.item_name(node.item)))
			"choice":
				options.append(_node_option("work", "%s · 1 精力 · 得 %d 灯铢" % [event.work, node.coins]))
				options.append(_node_option("work_alternative", "%s · 1 精力 · 得 %d 灯铢" % [event.alternative, node.coins]))
			"clue":
				options.append(_node_option("record", "记入旅途手记"))
			"haunt":
				if not node.get("investigated", false):
					options.append(_node_option("inspect", event.investigation_label))
				elif "hero" in run.same_cell(cell, true):
					options.append(_node_option("settle", event.work))
					options.append(_node_option("settle_alternative", event.alternative))
				else:
					text += "\n证据已经核实，等旅人到场再陪亡者告别。"
			"cache":
				options.append(_node_option("search", "搜寻旧物 · 1 精力"))
			"battle", "elite":
				if run.knows_encounter(cell):
					options.append(_node_option("fight", "选择阵容并交战"))
	if not tile.npc.is_empty() and tile.npc != selected_id and run.actor(tile.npc).position == cell and tile.enemies.is_empty():
		options.append(_node_option("talk", "和%s交谈" % run.actor(tile.npc).name))
	options.append(_node_option("leave", "返回地图"))
	_show_story(event.title, Catalog.terrain_name(tile.terrain) + " · " + Nodes.label(node.kind),
		text, STORY_TERRAIN[tile.terrain], [], options, _node_choice, {}, _node_tint())

func _node_choice(option: String) -> void:
	match option:
		"leave":
			if not _show_relic_intro():
				_close_modal()
		"trade":
			_shop_dialog()
		"talk":
			_talk(run.data.tiles[run.actor(selected_id).position].npc)
		"fight":
			_open_current_encounter()
		_:
			var result = run.use_node(selected_id, option)
			_run_action(result)
			if result.ok and option == "search" and _show_relic_intro(func(): _node_dialog(str(result.get("message", "")))):
				return
			_node_dialog("" if result.ok and option == "inspect" else str(result.get("message", "")))

func _shop_dialog(feedback: String = "") -> void:
	var trader = run.actor(selected_id)
	var node = run.node_at(trader.position)
	var box = _modal(_node_title(trader.position), 760, 660)
	_text(box, "远征队持有 %d 灯铢 · 交易者 %s" % [run.data.lamp_coins, trader.name], 17, gold)
	if not feedback.is_empty():
		_text(box, feedback, 15, muted)
	var list = _scroll_content(box)
	for buying in [true, false]:
		_text(list, "买入" if buying else "卖出", 20, gold)
		var supplies: Dictionary = node.stock if buying else trader.inventory
		_text(list, "补给", 16, muted)
		for id in supplies:
			if not Nodes.PRICES.has(id) or int(supplies[id]) <= 0:
				continue
			_shop_row(list, id, Catalog.item_name(id), Nodes.PRICES[id], int(supplies[id]), buying)
		_text(list, "装备", 16, muted)
		for uid in run.gear_owned("shop" if buying else "actor", trader.position if buying else selected_id):
			if not buying and uid in trader.equipment.values():
				continue
			var item = run.data.gear_instances[uid]
			_shop_row(list, uid, Gear.label(item), Gear.price(item), 1, buying, true)
		_text(list, "遗器", 16, muted)
		var relics: Dictionary = node.relic_stock if buying else run.data.relic_inventory
		for id in relics:
			if int(relics[id]) > 0:
				_shop_row(list, id, Relics.DATA[id].name, Relics.DATA[id].price, int(relics[id]), buying)
	_button(box, "返回节点", _node_dialog)

func _shop_row(list: Node, id: String, label: String, base: int, count: int, buying: bool, gear: bool = false) -> void:
	var quote = run.item_quote(base, "shop_buy" if buying else "shop_sell", id if gear else "")
	var detail = "%s · %d 灯铢 · %d 件" % [label, quote.price, count]
	if run.has_relic("price_pair_slip"):
		var buy_price = run.item_quote(base, "shop_buy", id if gear else "").price
		var sell_price = run.item_quote(base, "shop_sell", id if gear else "").price
		detail += " · 买 %d / 卖 %d" % [buy_price, sell_price]
	_button(list, detail,
		_shop_confirm.bind(id, label, base, buying, gear), buying and run.data.lamp_coins < quote.price and _vouchers("shop_buy").is_empty())

func _shop_confirm(id: String, label: String, base: int, buying: bool, gear: bool) -> void:
	var actor_id = selected_id
	var box = _modal(("买入 " if buying else "卖出 ") + label, 590, 420)
	if gear:
		_text(box, Gear.DATA[run.data.gear_instances[id].definition_id].effect, 16)
	elif Relics.DATA.has(id):
		_text(box, Relics.DATA[id].effect, 16)
		if not buying and run.has_relic(id) and int(run.data.relic_inventory[id]) == 1:
			_text(box, "售出最后一件会解除共鸣。", 17, gold)
	var channel = "shop_buy" if buying else "shop_sell"
	var vouchers = [""] + (_vouchers(channel) if buying else [])
	for voucher in vouchers:
		var quote = run.item_quote(base, channel, id if gear else "", voucher)
		if not quote.ok:
			continue
		var action = run.gear_trade.bind(actor_id, id, buying, voucher) if gear else run.trade.bind(actor_id, id, buying, voucher)
		var execute = _item_command(action)
		_button(box, "确认 · %d 灯铢%s" % [quote.price, " · " + Relics.DATA[voucher].name if not voucher.is_empty() else ""], func():
			var result = execute.call()
			_run_action(result)
			var message: String = result.get("message", "已完成。")
			if not result.ok or not _show_relic_intro(_shop_dialog.bind(message)):
				_shop_dialog(message), buying and run.data.lamp_coins < quote.price)
	_button(box, "返回商摊", _shop_dialog)

func _item_command(action: Callable) -> Callable:
	item_operation_serial += 1
	var id = "%d:%d" % [Time.get_ticks_usec(), item_operation_serial]
	return run.commit_item_operation.bind(id, int(run.data.item_revision), action)

func _vouchers(channel: String) -> Array:
	return run.data.relic_inventory.keys().filter(func(id):
		var entry = Relics.DATA[id]
		return entry.hook == "transaction_use" and entry.params.channel == channel)

func _split_squad_dialog() -> void:
	var members: Array = run.squad_members(selected_id)
	var dialog = _modal("拆分小队", 570, 520)
	_text(dialog, "勾选要组成新小队的角色。拆分不消耗精力；两队留在原地，抵达其他小队所在格时自动合队。", 16, muted)
	var list = _scroll_content(dialog)
	var chosen: Array = []
	var confirm = _button(dialog, "组成新小队", func():
		var result = run.split_squad(chosen)
		if result.ok:
			selected_id = chosen[0]
			moving_ids = _squad_movers(selected_id)
			_close_modal()
		_run_action(result))
	confirm.disabled = true
	for id in members:
		var toggle = CheckBox.new()
		toggle.text = run.actor(id).name
		toggle.name = "SplitMember_" + id
		list.add_child(toggle)
		toggle.toggled.connect(func(checked: bool):
			if checked: chosen.append(id)
			else: chosen.erase(id)
			confirm.disabled = chosen.is_empty() or chosen.size() == members.size())
	_button(dialog, "取消", _cell_actions)

func _footer(screen: Vector2) -> void:
	var box = _panel(ui, Rect2(20, screen.y - 140, screen.x - 40, 122))
	_text(box, toast_text if toast_text != "" else "旅途记录", 15, gold)
	var lines: Array[String] = []
	for line in run.data.log.slice(maxi(0, run.data.log.size() - 3)):
		lines.append(str(line).replace(" AP", " 精力").replace("行动点", "精力"))
	_text(box, "\n".join(lines), 14, muted)

func _clear_map_move() -> void:
	move_target = ""
	move_from_current_cell = false

func _toggle_mover(value: bool, id: String) -> void:
	_clear_map_move()
	if value:
		if run.actor(id).position != run.actor(selected_id).position:
			selected_id = id
			moving_ids = [id]
			selected_cell = run.actor(id).position
			view.focus_cell(selected_cell)
		elif id not in moving_ids:
			moving_ids.append(id)
	else:
		moving_ids.erase(id)
		if moving_ids.is_empty():
			moving_ids = [selected_id]
	_refresh()

func _squad_movers(id: String) -> Array:
	var healthy = run.squad_members(id).filter(func(member): return run.actor(member).hp > 0)
	# Keep a non-empty selection so movement preview can explain an all-down squad.
	return healthy if not healthy.is_empty() else [id]

func _select_actor(id: String, center_camera: bool = true) -> void:
	_clear_map_move()
	selected_id = id
	selected_cell = run.actor(id).position
	moving_ids = _squad_movers(id)
	if center_camera:
		view.focus_cell(selected_cell)
	_refresh()

func _select_cell(id: String) -> void:
	if screen_state != Screen.EXPEDITION or combat != null or run.data.status != "exploring" or modal_layer.get_child_count() > 0:
		return
	if id == move_target and not id.is_empty():
		_move_selected()
		return
	var source: String = run.actor(moving_ids[0]).position
	var adjacent = Hex.is_land(run.data.tiles, id) and id in Hex.neighbors(source, run.data.tiles)
	if id != source and not adjacent:
		var candidates = run.same_cell(id, true)
		if candidates.is_empty():
			candidates = run.same_cell(id)
		if not candidates.is_empty():
			_select_actor(candidates[0], false)
			return
	selected_cell = id
	move_from_current_cell = id == source
	move_target = id if adjacent else ""
	_refresh()

func _show_move_preview() -> void:
	var costs: Array[String] = []
	for id in moving_ids:
		var cost = "%d 精力" % run.move_cost(id, move_target)
		costs.append(cost if moving_ids.size() == 1 else run.actor(id).name + " " + cost)
	var endpoint = Hex.world(move_target)
	endpoint.y = view.board_surface.height_at(endpoint) + 0.05
	var origin: String = selected_id if selected_id in moving_ids else moving_ids[0]
	move_preview.show_path(view.dolls[origin], endpoint, costs)

func _move_selected() -> void:
	var destination = move_target
	var mover: String = selected_id if selected_id in moving_ids else moving_ids[0]
	_clear_map_move()
	var result = run.move(moving_ids, destination)
	if result.ok:
		selected_id = mover
		selected_cell = run.actor(mover).position
		moving_ids = _squad_movers(mover)
	_run_action(result)
	if not result.ok:
		return
	if selected_id in moving_ids:
		view.follow_map_movement(selected_id)
	if result.get("battle", false):
		_formation_dialog()
	elif not _show_chapter():
		_show_npc_encounter(selected_id if selected_id in moving_ids else moving_ids[0])
		if modal_layer.get_child_count() == 0:
			_show_relic_intro()

func _run_action(result: Dictionary) -> void:
	toast_text = "已完成。" if result.ok else str(result.get("message", "无法执行。"))
	if result.ok and run.data.status != "battle":
		var saved = run.save_game()
		if not saved.ok:
			toast_text = "操作已结算，但存档失败：" + str(saved.message)
	_refresh()
	if not result.ok and combat == null and run.data.status == "exploring" and modal_layer.get_child_count() == 0:
		_notice(toast_text)

func _modal(title: String, width: float = 650, height: float = 520) -> VBoxContainer:
	_clear_map_move()
	move_preview.hide()
	_clear(modal_layer)
	ui.show()
	view.visible = screen_state == Screen.EXPEDITION
	view.set_world_input_enabled(false)
	var backdrop = ColorRect.new()
	backdrop.color = Color(0.025, 0.07, 0.065, 0.82)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_layer.add_child(backdrop)
	var screen = get_viewport().get_visible_rect().size
	var size = Vector2(minf(width, screen.x - 70), minf(height, screen.y - 70))
	var box = _panel(modal_layer, Rect2((screen - size) * 0.5, size), Color("243b34"))
	_text(box, title, 27, gold)
	return box

func _close_modal() -> void:
	_clear(modal_layer)
	ui.show()
	var in_expedition = screen_state == Screen.EXPEDITION
	view.visible = in_expedition
	view.set_process(in_expedition)
	_update_world_input()

func _update_world_input() -> void:
	var can_target = combat != null and combat.outcome.is_empty()
	var can_explore = not view.battle_mode and run.data.status == "exploring"
	view.set_world_input_enabled(screen_state == Screen.EXPEDITION and view.visible
		and modal_layer.get_child_count() == 0 and (can_target or can_explore))

func _notice(message: String) -> void:
	var box = _modal("旅途提示", 620, 270)
	_text(box, message, 18)
	_button(box, "知道了", _close_modal)

func _confirm(title: String, message: String, action: Callable) -> void:
	var box = _modal(title, 700, 480)
	_text(box, message, 17)
	_button(box, "确认", func(): _close_modal(); action.call())
	_button(box, "取消，继续远征", _close_modal)

func _end_day_dialog() -> void:
	var remaining: Array[String] = []
	for id in run.joined_ids():
		if run.actor(id).ap > 0 and run.actor(id).hp > 0:
			remaining.append("%s %d 精力" % [run.actor(id).name, run.actor(id).ap])
	_confirm("结束这一天？", "尚余：" + " / ".join(remaining) + "\n\n全队进入次日，精力回各自上限。次日天气可能变化。生命与魔力靠节点、物资和治疗恢复。", func(): _run_action(run.end_day()))

func _inventory_dialog(id: String, current_tab: int = 0, selected_consumable: String = "") -> void:
	var a = run.actor(id)
	var box = _modal(a.name + " · 背包与装备", 850, 670)
	_text(box, "攻击 %d · 防御 %d · 速度 %d\n战斗外免费换装；物品只在同格交接，不刷新资源。" % [run.stat(id, "attack"), run.stat(id, "defense"), run.stat(id, "speed")], 16, muted)
	var slots: Array[String] = []
	for slot in ["weapon", "armor", "accessory"]:
		var item = str(a.equipment.get(slot, ""))
		slots.append({"weapon": "武器", "armor": "防具", "accessory": "饰品"}[slot] + "：" + (Gear.label(run.data.gear_instances[item]) if item != "" else "空"))
	_text(box, "  ·  ".join(slots), 17, gold)
	if id != "hero" and Story.BACKGROUNDS.has(id):
		_text(box, "%s · %s" % [a.race, Story.CHARACTER_BEHAVIOR[id][0]], 15, muted)
	var passive = Catalog.passive_description(id)
	if not passive.is_empty():
		_text(box, "专长 " + passive, 16, muted)
	_text(box, "技能 · " + Catalog.SKILLS[a.skill].name + "\n" + Catalog.skill_description(a.skill), 16, muted)
	_text(box, "终结技 · " + Catalog.SKILLS[a.ultimate].name + "\n" + Catalog.skill_description(a.ultimate) + "；满能量额外释放，不占正常行动。", 16, muted)
	var tabs = TabContainer.new()
	tabs.name = "InventoryTabs"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)
	var lists: Array[VBoxContainer] = []
	for title in ["消耗品", "装备", "遗器"]:
		var page = VBoxContainer.new()
		page.name = title
		tabs.add_child(page)
		var list = _scroll_content(page)
		list.get_parent().horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		lists.append(list)
	tabs.current_tab = current_tab
	var detail_panel = PanelContainer.new()
	detail_panel.add_theme_stylebox_override("panel", _style(Color("243b34"), Color("536456"), 6))
	tabs.get_child(0).add_child(detail_panel)
	var description = _text(detail_panel, "选择一件消耗品查看用途。", 16)
	description.name = "ConsumableDescription"
	description.custom_minimum_size.y = 48
	var cards = {}
	var row_style = _style(Color("20352e"), Color("465b4f"), 6)
	row_style.content_margin_top = 4
	row_style.content_margin_bottom = 4
	var selected_style = row_style.duplicate()
	selected_style.bg_color = Color("354c3e")
	selected_style.border_color = gold
	var select_consumable = func(item: String):
		for key in cards:
			cards[key].add_theme_stylebox_override("panel", selected_style if key == item else row_style)
		var purpose = str(Catalog.ITEMS.get(item, {}).get("description", "暂无用途说明。"))
		if item == "salve" and run.has_relic("herbal_case"):
			purpose += " 青枝药匣使恢复量提高 25%。"
		description.text = Catalog.item_name(item) + "\n" + purpose
	for item in a.inventory:
		if a.inventory[item] <= 0:
			continue
		var definition = Catalog.ITEMS.get(item, {})
		var row = HBoxContainer.new()
		var card = PanelContainer.new()
		card.focus_mode = Control.FOCUS_ALL
		card.add_theme_stylebox_override("panel", row_style)
		card.focus_entered.connect(select_consumable.bind(item))
		card.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				card.accept_event()
				card.grab_focus()
				select_consumable.call(item))
		cards[item] = card
		lists[0].add_child(card)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(row)
		var item_label = _text(row, Catalog.item_name(item) + " ×%d" % a.inventory[item], 16)
		item_label.size_flags_horizontal = Control.SIZE_FILL
		item_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		item_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		var holder = PanelContainer.new()
		holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tag_style = _style(Color("2a4038"), Color("64725e"), 6)
		tag_style.content_margin_top = 3
		tag_style.content_margin_bottom = 3
		holder.add_theme_stylebox_override("panel", tag_style)
		row.add_child(holder)
		_text(holder, "持有者 · " + a.name, 13, gold).autowrap_mode = TextServer.AUTOWRAP_OFF
		var spacer = Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(spacer)
		if definition.has("hp") or definition.has("mp"):
			_button(row, "使用", _item_dialog.bind(id, item), a.hp <= 0 or run.data.status != "exploring")
		if run.same_cell(a.position).size() > 1:
			_button(row, "交接", _transfer_dialog.bind(id, item))
	_gear_list(lists[1], id)
	if lists[0].get_child_count() == 0:
		_text(lists[0], "暂无物品。", 16, muted)
	if cards.is_empty():
		detail_panel.hide()
	elif cards.has(selected_consumable):
		select_consumable.call(selected_consumable)
	_relic_list(lists[2], id)
	_button(box, "关闭", _close_modal)

func _gear_list(list: VBoxContainer, id: String) -> void:
	var filter = OptionButton.new()
	for label in ["所有槽位", "武器", "护甲", "饰品"]:
		filter.add_item(label)
	list.add_child(filter)
	var set_filter = OptionButton.new()
	set_filter.add_item("所有套装")
	for set_id in Gear.SETS:
		set_filter.add_item(Gear.SETS[set_id].name)
	list.add_child(set_filter)
	var rows = VBoxContainer.new()
	list.add_child(rows)
	var refresh_rows = func(_index: int):
		_clear(rows)
		var instances: Array = run.gear_owned("actor", id)
		instances.sort_custom(func(a, b):
			var left: int = Gear.QUALITIES.find(run.data.gear_instances[a].quality)
			var right: int = Gear.QUALITIES.find(run.data.gear_instances[b].quality)
			return int(a) < int(b) if left == right else left > right)
		for uid in instances:
			var item = run.data.gear_instances[uid]
			var def = Gear.DATA[item.definition_id]
			if filter.selected > 0 and def.slot != Gear.SLOTS[filter.selected - 1]:
				continue
			if set_filter.selected > 0 and def.set_id != Gear.SETS.keys()[set_filter.selected - 1]:
				continue
			var equipped: bool = uid in run.actor(id).equipment.values()
			var suffix: String = (" · " + Gear.SETS[def.set_id].name) if not def.set_id.is_empty() else ""
			_button(rows, "%s%s%s" % [Gear.label(item), suffix, " · 已装备" if equipped else ""], _gear_detail.bind(id, uid))
		if rows.get_child_count() == 0:
			_text(rows, "暂无符合条件的装备。", 16, muted)
	filter.item_selected.connect(refresh_rows)
	set_filter.item_selected.connect(refresh_rows)
	refresh_rows.call(0)

func _gear_detail(id: String, uid: String, feedback: String = "") -> void:
	var item = run.data.gear_instances[uid]
	var definition = Gear.DATA[item.definition_id]
	var a = run.actor(id)
	var box = _modal(Gear.label(item), 780, 640)
	var content = _scroll_content(box)
	if not feedback.is_empty():
		_text(content, feedback, 16, gold)
	var current_uid: String = a.equipment[definition.slot]
	var stat_labels = {"attack": "攻击", "defense": "防御", "speed": "速度"}
	for stat in definition.stats:
		var current_value = 0 if current_uid.is_empty() else Gear.bonus(run.data.gear_instances[current_uid], stat)
		_text(content, "%s +%d · 当前同槽 +%d · 持有者 %s" % [stat_labels[stat], Gear.bonus(item, stat), current_value, a.name], 17, gold)
	_text(content, definition.effect, 16)
	if not definition.set_id.is_empty():
		var pieces: int = run.set_count(id, definition.set_id)
		var suite = Gear.SETS[definition.set_id]
		_text(content, "%s · %d / 3" % [suite.name, pieces], 18, gold)
		_text(content, ("已激活 · " if pieces >= 2 else "未激活 · ") + suite.two, 16)
		_text(content, ("已激活 · " if pieces >= 3 else "未激活 · ") + suite.three, 16)
	_button(content, "阅读装备故事", func():
		_show_story(definition.name, "器物故事", definition.story, _story_scene_at(a.position),
			[], [], func(_option: String): _gear_detail(id, uid), {}))
	var equip_action = _item_command(run.equip.bind(id, uid))
	_button(content, "卸下" if current_uid == uid else "装备", func():
		var result = equip_action.call()
		_run_action(result)
		_gear_detail(id, uid, result.get("message", "")))
	for other in run.same_cell(a.position):
		if other == id or current_uid == uid:
			continue
		var transfer_action = _item_command(run.gear_transfer.bind(id, other, uid))
		_button(content, "交给 " + run.actor(other).name, func():
			var result = transfer_action.call()
			_run_action(result)
			if result.ok:
				_inventory_dialog(id, 1)
			else:
				_gear_detail(id, uid, result.get("message", "")))
	_text(content, "持有 %d 灯铢" % run.data.lamp_coins, 16, gold)
	for voucher in [""] + _vouchers("enhancement_fee"):
		var quote = run.enhancement_quote(id, uid, voucher)
		if not quote.ok:
			if voucher.is_empty():
				_text(content, quote.message, 15, muted)
			continue
		var stat: String = definition.stats.keys()[0]
		var next_value = Gear.bonus(item, stat, int(item.enhance_level) + 1)
		var enhance_action = _item_command(run.enhance.bind(id, uid, voucher))
		_button(content, "强化至 +%d · %s +%d → +%d · %d 灯铢%s" % [
			int(item.enhance_level) + 1, stat_labels[stat], Gear.bonus(item, stat), next_value, quote.price,
			" · " + Relics.DATA[voucher].name if not voucher.is_empty() else ""], func():
			var result = enhance_action.call()
			_run_action(result)
			_gear_detail(id, uid, result.get("message", "")), run.data.lamp_coins < quote.price)
	_button(box, "返回装备", _inventory_dialog.bind(id, 1))

func _relic_list(list: VBoxContainer, id: String) -> void:
	_text(list, "全队共鸣 · %d / 6" % run.data.relic_attunement.size(), 18, gold)
	for i in 6:
		var label = "%d. 空位" % (i + 1)
		if i < run.data.relic_attunement.size():
			var relic: String = run.data.relic_attunement[i]
			_button(list, "%d. %s" % [i + 1, Relics.DATA[relic].name], _relic_detail.bind(id, relic))
		else:
			_text(list, label, 15, muted)
	if run.data.relic_seen.is_empty():
		_text(list, "本次远征尚未获得遗器。", 16, muted)
	for type in ["P", "C", "L"]:
		_text(list, {"P": "持续", "C": "消耗", "L": "永久"}[type], 17, gold)
		for relic in Relics.DATA:
			var entry = Relics.DATA[relic]
			if entry.type != type or not run.data.relic_seen.has(relic):
				continue
			var count: int = int(run.data.relic_inventory.get(relic, 0))
			var status = " · 共鸣中" if run.has_relic(relic) else ""
			_button(list, "%s · %s%s" % [entry.name, "×%d" % count if count > 0 else "已发现", status], _relic_detail.bind(id, relic))

func _relic_detail(id: String, relic: String, feedback: String = "") -> void:
	var entry = Relics.DATA[relic]
	var a = run.actor(id)
	var box = _modal(entry.name, 700, 590)
	var content = _scroll_content(box)
	if not feedback.is_empty():
		_text(content, feedback, 16, gold)
	_text(content, entry.effect, 17)
	_text(content, "主要来源 · " + _relic_source(entry.source), 15, muted)
	if run.has_relic(relic):
		_relic_information(content, id, relic)
	_button(content, "阅读遗器故事", func():
		_show_story(entry.name, "器物故事", entry.story, _story_scene_at(a.position),
			[], [], func(_option: String): _relic_detail(id, relic), {}))
	var count: int = int(run.data.relic_inventory.get(relic, 0))
	if count > 0:
		if entry.type == "P":
			var execute = _item_command(run.attune_relic.bind(id, relic))
			_button(content, "解除共鸣" if run.has_relic(relic) else "共鸣", func():
				var result = execute.call()
				_run_action(result)
				_relic_detail(id, relic, result.get("message", "")))
		elif entry.hook == "transaction_use":
			_text(content, "在交易或强化时选择使用此凭券。", 16, muted)
		else:
			_relic_use_buttons(content, id, relic)
	_button(box, "返回遗器", _inventory_dialog.bind(id, 2))

func _relic_information(content: VBoxContainer, actor_id: String, relic: String) -> void:
	var a = run.actor(actor_id)
	var origin: String = a.position
	var entry = Relics.DATA[relic]
	match relic:
		"survey_tally":
			var visits: int = run.data.visited.size()
			var upcoming: Array = [20, 60, 100].filter(func(value): return value > visits)
			_text(content, "已实际到访 %d 格 · %s" % [visits, "里程碑已全部达成" if upcoming.is_empty() else "下一个 %d 格" % upcoming[0]], 16, gold)
		"market_window":
			for cell in run.data.explored:
				var shop = run.node_at(cell)
				if shop.get("kind") != "trade":
					continue
				var labels: Array[String] = []
				for item in shop.stock:
					if shop.stock[item] > 0:
						labels.append("%s %d 灯铢" % [Catalog.item_name(item), run.item_quote(Nodes.PRICES[item], "shop_buy").price])
				for uid in run.gear_owned("shop", cell):
					var gear = run.data.gear_instances[uid]
					labels.append("%s %d 灯铢" % [Gear.label(gear), run.item_quote(Gear.price(gear), "shop_buy", uid).price])
				for id in shop.relic_stock:
					if shop.relic_stock[id] > 0:
						labels.append("%s %d 灯铢" % [Relics.DATA[id].name, run.item_quote(Relics.DATA[id].price, "shop_buy").price])
				_text(content, "%s · %s" % [cell, "、".join(labels)], 15, muted)
		"caution_compass":
			var candidates: Array = run.data.explored.keys().filter(func(cell):
				return not run.data.tiles[cell].hidden and run.node_at(cell).get("kind") == "elite" and not run.data.tiles[cell].enemies.is_empty() \
					and Hex.distance(Hex.coord(origin), Hex.coord(cell)) <= entry.params.radius)
			candidates.sort_custom(func(left, right):
				var ld = Hex.distance(Hex.coord(origin), Hex.coord(left))
				var rd = Hex.distance(Hex.coord(origin), Hex.coord(right))
				return left < right if ld == rd else ld < rd)
			if candidates.is_empty():
				_text(content, "附近未发现可公开的精英节点。", 16, muted)
			else:
				var cell: String = candidates[0]
				var offset = Hex.coord(cell) - Hex.coord(origin)
				_text(content, "最近精英方向 %+d,%+d · 相距 %d 格" % [offset.x, offset.y, Hex.distance(Hex.coord(origin), Hex.coord(cell))], 16, gold)
		"terrain_caliper":
			for cell in run.data.explored:
				if cell != origin and Hex.is_land(run.data.tiles, cell) and Hex.distance(Hex.coord(origin), Hex.coord(cell)) <= entry.params.radius:
					var terrain: String = run.data.tiles[cell].terrain
					_text(content, "%s · %s · 基础 %d → 实际 %d 精力" % [cell, Catalog.terrain_name(terrain), Catalog.TERRAIN[terrain].cost, run.move_cost(actor_id, cell)], 15, muted)
		"cloud_almanac":
			var forecast: Array = run.weather_forecast(2)
			_text(content, "明天预计%s · 后天预计%s" % ["有雨" if forecast[0] == "rain" else "无雨", "有雨" if forecast[1] == "rain" else "无雨"], 16, gold)
		"honest_ledger":
			var node = run.node_at(origin)
			if node.get("kind") == "choice":
				_text(content, "当地委托 · " + ("已领取" if not node.result.is_empty() else "同地且需要 1 精力"), 16, gold)
		"witness_slate":
			for record in run.data.map_intel.get("observed_enemy_actions", []):
				_text(content, "%s → %s · %s · HP −%d · 护盾 −%d" % [record.name, record.target,
					Catalog.ELEMENT_NAMES.get(record.element, record.element), record.damage, record.absorbed], 15, muted)

func _relic_source(source: String) -> String:
	if source.begins_with("recruit:"):
		return "指定伙伴首次同行"
	return {"shop": "商店", "commission": "委托", "field_cache": "藏物点",
		"exploration_milestone": "探索里程碑", "spirit_farewell": "亡灵送别"}.get(source, "探索")

func _relic_use_buttons(content: VBoxContainer, id: String, relic: String) -> void:
	var entry = Relics.DATA[relic]
	var targets = [""]
	if entry.params.get("targets") == "selected_other_healthy_joined_same_cell":
		targets = run.same_cell(run.actor(id).position, true)
		targets.erase(id)
	elif entry.hook in ["encounter_info_use", "route_use"]:
		targets = run.data.explored.keys().filter(func(cell): return Hex.is_land(run.data.tiles, cell) and cell != run.actor(id).position)
		targets.sort()
		if entry.hook == "encounter_info_use":
			var nearby = Hex.neighbors(run.actor(id).position, run.data.tiles)
			targets = targets.filter(func(cell): return cell in nearby and run.knows_encounter(cell))
	if targets.is_empty():
		_text(content, "当前没有可用目标。", 16, muted)
	for target in targets:
		var label = "使用"
		if not target.is_empty():
			label += " · " + (run.actor(target).name if run.data.actors.has(target) else Catalog.terrain_name(run.data.tiles[target].terrain) + " " + target)
		var execute = _item_command(run.use_relic.bind(id, relic, target))
		_button(content, label, func():
			var result = execute.call()
			_run_action(result)
			_relic_detail(id, relic, result.get("message", "")))

func _transfer_dialog(owner: String, item: String) -> void:
	var box = _modal("同地交接 · " + Catalog.item_name(item), 650, 540)
	_text(box, "每次交接一件，不消耗精力。已装备的物品需先卸下。", 17, muted)
	var content = _scroll_content(box)
	for other in run.same_cell(run.actor(owner).position):
		if other != owner:
			_button(content, "交给" + run.actor(other).name, func():
				var result = run.transfer(owner, other, item, 1)
				if result.ok:
					_run_action(result)
					_inventory_dialog(owner, 0, item)
				else:
					_text(content, result.message, 16, gold))
	_button(box, "返回背包", _inventory_dialog.bind(owner, 0, item))

func _item_dialog(user_id: String, item_id: String = "") -> void:
	var from_backpack = not item_id.is_empty()
	var box = _modal("使用道具 · " + run.actor(user_id).name, 650, 460)
	_text(box, "地图使用不耗精力；战斗中不占正常行动，可使用多件。", 16, muted)
	if from_backpack:
		_text(box, "从当前角色的背包使用「%s」，请选择同地目标。" % Catalog.item_name(item_id), 16, gold)
	var targets: Array = []
	if combat != null:
		targets = combat.active.duplicate()
	else:
		for id in run.data.actors:
			var a = run.actor(id)
			if a.position == run.actor(user_id).position and (a.joined or run.data.story.get(id, {}).get("met", false)):
				targets.append(id)
	var select = OptionButton.new()
	for id in targets:
		select.add_item("%s · HP %d/%d · MP %d/%d" % [run.actor(id).name, run.actor(id).hp, run.actor(id).hp_max, run.actor(id).mp, run.actor(id).mp_max])
	if from_backpack and user_id in targets:
		select.select(targets.find(user_id))
	box.add_child(select)
	var feedback = _text(box, "", 16, gold)
	feedback.hide()
	for item in ([item_id] if from_backpack else ["salve", "ether"]):
		var quantity = int(run.actor(user_id).inventory.get(item, 0))
		var name = Catalog.item_name(item)
		var button_text = "确认使用 %s ×1" % name if from_backpack else "%s ×%d" % [name, quantity]
		_button(box, button_text, func():
			var target = targets[select.selected]
			var result = combat.use_item(item, target) if combat != null else run.use_item(user_id, target, item)
			if not result.ok:
				feedback.text = result.message
				feedback.show()
				return
			_run_action(result)
			if combat != null:
				_after_combat_step()
			if from_backpack:
				_inventory_dialog(user_id, 0, item_id)
			else:
				_item_dialog(user_id), quantity <= 0 or targets.is_empty())
	if from_backpack:
		_button(box, "返回背包", _inventory_dialog.bind(user_id, 0, item_id))
	else:
		_button(box, "用完了，返回", _close_modal)

func _healing_dialog() -> void:
	var box = _modal("选择同地治疗对象", 620, 500)
	var candidates = run.same_cell(run.actor(selected_id).position)
	for id in Catalog.COMPANIONS:
		if id not in candidates and run.actor(id).position == run.actor(selected_id).position and run.data.story[id].met:
			candidates.append(id)
	for id in candidates:
		_button(box, "%s · %d/%d HP" % [run.actor(id).name, run.actor(id).hp, run.actor(id).hp_max], func(): _close_modal(); _run_action(run.heal_skill(selected_id, id)))
	_button(box, "取消", _close_modal)

func _open_current_encounter() -> void:
	var cell: String = run.actor(selected_id).position
	run.data.pending_battle = {"position": cell, "ambush": false, "origin": cell, "movers": [], "npc": ""}
	run.save_game()
	_formation_dialog()

func _formation_dialog() -> void:
	var encounter = run.data.pending_battle
	var box = _modal("选择出战阵容 · 最多四人", 700, 620)
	var node = run.node_at(encounter.position)
	if encounter.npc.is_empty() and node.get("kind") in ["battle", "elite"]:
		var event = Nodes.story(node)
		var tile = run.data.tiles[encounter.position]
		var scene = TextureRect.new()
		scene.texture = load("res://assets/story/" + STORY_TERRAIN[tile.terrain] + ".png")
		scene.custom_minimum_size.y = 86
		scene.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		scene.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		scene.modulate = _node_tint()
		box.add_child(scene)
		_text(box, event.title + " · " + _node_description(node, tile, event), 15, gold)
	var surprise = encounter.ambush or encounter.get("surprise", false)
	_text(box, "每人本场首次上场支付 2 精力；同地候补可换入。" + ("\n突发遭遇：精力不足仍可出战，最多扣至 0。" if surprise else ""), 17, muted)
	var chosen: Array = []
	var lineup = _scroll_content(box)
	for id in run.same_cell(encounter.position, true):
		var eligible = Combat.can_deploy(run.actor(id), encounter)
		var toggle = CheckBox.new()
		toggle.text = "%s · HP %d/%d · 精力 %d" % [run.actor(id).name, run.actor(id).hp, run.actor(id).hp_max, run.actor(id).ap]
		toggle.disabled = not eligible
		if eligible and chosen.size() < 4:
			chosen.append(id)
			toggle.button_pressed = true
		toggle.toggled.connect(func(value: bool):
			if value:
				if chosen.size() < 4:
					chosen.append(id)
				else:
					toggle.set_pressed_no_signal(false)
			else:
				chosen.erase(id))
		lineup.add_child(toggle)
	_button(box, "开始战斗", func():
		var battle = Combat.new()
		var result = battle.begin(run, encounter, chosen)
		if result.ok:
			_close_modal()
			combat = battle
			toast_text = ""
			selected_target = "enemy_0"
			view.begin_battle(run, combat)
			battle_timer = 0.8
			_refresh()
		else:
			toast_text = result.message
			_text(box, result.message, 16, gold))
	# An entered encounter must be resolved; cancellation of known movement occurs before entry.
	_text(box, "已进入遭遇，战斗中可选择撤退。", 14, muted)

func _battle_ui(screen: Vector2) -> void:
	view.refresh_battle(run, combat)
	view.set_battle_target(selected_target)
	var battle_bottom = screen.y - 20
	var side_height = battle_bottom - 120
	var left_outer = _panel(ui, Rect2(20, 120, 250, side_height))
	_text(left_outer, "出战角色", 24, gold)
	var left = _scroll_content(left_outer)
	left.add_theme_constant_override("separation", 4)
	for id in combat.active:
		var a = run.actor(id)
		var shown_hp = view.display_hp(id,int(a.hp))
		var shown_shield = view.display_shield(id,int(a.shield))
		var label = ("▶ " if view.presentation_actor(combat.current) == id else "") + a.name
		if shown_shield > 0:
			label += " · 盾%d" % shown_shield
		if combat.madness.has(id):
			label += " · 疯狂"
		if shown_hp > 0 and combat.haste_turns.has(id):
			label += " · 提速"
		var heading = HBoxContainer.new()
		left.add_child(heading)
		var portrait = _story_portrait(id, "grief" if shown_hp <= 0 else "anger" if combat.madness.has(id) else "battle")
		if portrait != null:
			var icon = TextureRect.new()
			icon.texture = portrait
			icon.custom_minimum_size = Vector2(32, 32)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			heading.add_child(icon)
		_text(heading, label, 19, ink if shown_hp > 0 else muted)
		_text(left, "HP %d/%d · MP %d/%d" % [shown_hp, a.hp_max, a.mp, a.mp_max], 14, muted)
		_hp_bar(left, shown_hp, a.hp_max)
		var ultimate = _button(left, "%d%% · " % a.energy + Catalog.SKILLS[a.ultimate].name, _ultimate.bind(id), a.energy < 100 or a.hp <= 0 or combat.madness.has(id))
		ultimate.tooltip_text = "%s\n%s\n充能达到 100%% 时可释放，不占正常行动。" % [Catalog.SKILLS[a.ultimate].name, Catalog.skill_description(a.ultimate)]
	var enemy_panel_x = screen.x - 330
	var right_outer = _panel(ui, Rect2(enemy_panel_x, 120, 310, side_height))
	_text(right_outer, "敌方阵容", 24, gold)
	var right = _scroll_content(right_outer)
	right.add_theme_constant_override("separation", 9)
	var counts = {}
	for enemy in combat.enemies.values():
		counts[enemy.name] = int(counts.get(enemy.name, 0)) + 1
	var display_names = {}
	var numbers = {}
	for id in combat.enemies:
		var e = combat.enemies[id]
		numbers[e.name] = int(numbers.get(e.name, 0)) + 1
		var name: String = e.name + (" %d号" % numbers[e.name] if counts[e.name] > 1 else "")
		display_names[id] = name
		_enemy_card(right, id, name)
	var timeline: Array[String] = []
	for entry in combat.timeline(6):
		timeline.append(display_names.get(entry.id, combat.unit(entry.id).name))
	if not timeline.is_empty():
		right_outer.add_child(HSeparator.new())
		_text(right_outer, "行动顺序\n" + " → ".join(timeline), 14, gold)
	var is_friendly = combat.current != "" and not combat.enemies.has(combat.current) and not combat.madness.has(combat.current) and combat.outcome == "" and battle_timer <= 0 and not view.is_animating()
	var quick_actions = HBoxContainer.new()
	quick_actions.add_theme_constant_override("separation", 8)
	ui.add_child(quick_actions)
	var auto = _button(quick_actions, "自动战斗", func(): combat.auto_mode = not combat.auto_mode; _refresh())
	auto.toggle_mode = true
	auto.set_pressed_no_signal(combat.auto_mode)
	auto.add_theme_stylebox_override("hover_pressed", auto.get_theme_stylebox("pressed"))
	auto.tooltip_text = "切换自动战斗，由队员自动选择并执行战斗指令。"
	var items = _button(quick_actions, "道具", func(): _item_dialog(combat.current), not is_friendly)
	items.tooltip_text = "使用当前角色背包中的恢复道具。\n可给在场队友使用，不占正常行动。"
	quick_actions.position = Vector2(enemy_panel_x - quick_actions.get_combined_minimum_size().x - 12, 120)

	var center = _panel(ui, Rect2(290, battle_bottom - 155, screen.x - 640, 155))
	center.get_parent().grow_vertical = Control.GROW_DIRECTION_BEGIN
	_text(center, view.presentation_title((combat.unit(combat.current).name + " 的行动") if combat.current != "" else "战斗结算"), 20, gold)
	var commands = HBoxContainer.new()
	center.add_child(commands)
	var actor_id = str(combat.current) if is_friendly else ""
	var attack = _button(commands, "普攻", func(): _combat_action("attack"), not is_friendly)
	attack.tooltip_text = "普通攻击\n" + _combat_skill_hint("attack", actor_id)
	var skill_id = str(combat.unit(combat.current).get("skill", "attack")) if combat.current in combat.active else "attack"
	var skill = _button(commands, Catalog.SKILLS[skill_id].name, func(): _combat_action(skill_id), not is_friendly)
	skill.tooltip_text = Catalog.SKILLS[skill_id].name + "\n" + _combat_skill_hint(skill_id, actor_id)
	var guard = _button(commands, "防守", func(): _combat_action("guard"), not is_friendly)
	guard.tooltip_text = "防守\n下次正常行动前受到的伤害降低，并获得 10% 充能。"
	if is_friendly and not combat.reserves().is_empty():
		var swap = _button(commands, "换人", _swap_dialog)
		swap.tooltip_text = "用同地候补换下当前角色，消耗本次正常行动。\n每名候补首次上场支付参战精力。"
	var retreat_hint = "已付精力不退还；本战出战者承受 10% 最大生命损伤，敌人恢复。"
	var retreat = _button(commands, "撤退", func(): _confirm("撤退？", retreat_hint, func(): _run_action(combat.retreat()); _finish_battle()), combat.river or combat.madness.has(combat.current))
	retreat.tooltip_text = retreat_hint
	var field = combat.field_view()
	var context = "场地：" + Catalog.terrain_name(field.terrain)
	var field_names = {"frozen": "冰面", "charged": "导电", "wind_barrier": "风障", "root_cover": "根掩"}
	for state in field_names:
		if field.fields.has(state):
			context += " · %s %d 行动" % [field_names[state], field.fields[state]]
	if combat.madness.has(combat.current):
		context += " · 当前角色失去判断，将自行攻击"
	if field.burning:
		context += " · 燃烧"
		if run.has_relic("field_dial"):
			context += "（持续至战斗结束，双方下一次灼烧 %.1f）" % maxf(0.0, combat.fire_tick - combat.clock)
	if field.wet:
		context += " · 潮湿 %d 行动" % int(field.fields.get("wet", 0))
	if is_friendly:
		var suites: Array[String] = []
		for id in Gear.SETS:
			var pieces: int = run.set_count(actor_id, id)
			if pieces >= 2:
				suites.append("%s %d 件" % [Gear.SETS[id].name, pieces])
		if not suites.is_empty():
			context += "\n生效套装 · " + "、".join(suites)
	if field.get("river", false):
		context += " · 冥河正在削弱战神"
	if is_friendly:
		context += "\n" + _combat_skill_hint(skill_id, actor_id)
	_text(center, context, 12, muted)
	if not toast_text.is_empty():
		_text(center, toast_text, 13, gold)

func _enemy_card(parent: VBoxContainer, id: String, title: String) -> void:
	var enemy = combat.enemies[id]
	var selected = selected_target == id and enemy.hp > 0
	var shown_hp = view.display_hp(id, int(enemy.hp))
	var panel = PanelContainer.new()
	panel.name = "EnemyCard_" + id
	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			panel.accept_event()
			_select_battle_target(id))
	panel.add_theme_stylebox_override("panel", _style(Color("31463d") if selected else Color("203b35"),
		gold if selected else Color("50675c"), 8))
	parent.add_child(panel)
	var card = VBoxContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_constant_override("separation", 4)
	panel.add_child(card)
	_button(card, ("◆ " if selected else "") + title, _select_battle_target.bind(id), enemy.hp <= 0)
	var status = "已击败" if shown_hp <= 0 else "蓄力中！" if enemy.charged else "行动蓄积"
	if shown_hp > 0 and enemy.slow > 0:
		status += " · 减速"
	_text(card, "HP %d/%d · %s\n%s" % [shown_hp, enemy.hp_max, status, enemy.role], 14, muted)
	_hp_bar(card, shown_hp, enemy.hp_max, true)

func _select_battle_target(id: String) -> void:
	if combat == null or combat.outcome != "" or id == selected_target or id not in combat.alive_enemies():
		return
	selected_target = id
	_refresh()

func _combat_skill_hint(skill_id: String, actor_id: String) -> String:
	var hint = Catalog.skill_description(skill_id)
	if not actor_id.is_empty():
		var price: int = combat.skill_cost(actor_id, skill_id)
		if price != int(Catalog.SKILLS[skill_id].mp):
			hint = hint.replace("%d MP" % Catalog.SKILLS[skill_id].mp, "%d MP" % price)
	if not actor_id.is_empty() and selected_target in combat.alive_enemies() and Catalog.SKILLS[skill_id].target == "enemy":
		hint += " · 预计基础伤害 %d（护盾和防守另计）" % combat.damage_preview(actor_id, selected_target, skill_id)
	return hint

func _combat_action(skill_id: String) -> void:
	if skill_id != "guard" and Catalog.SKILLS[skill_id].target == "ally":
		var box = _modal("选择技能目标", 600, 510)
		for id in combat.active:
			_button(box, run.actor(id).name + " · %d HP" % run.actor(id).hp, func(): _close_modal(); _perform_combat(skill_id, id))
		_button(box, "取消", _close_modal)
	else:
		_perform_combat(skill_id, selected_target)

func _perform_combat(skill_id: String, target: String) -> void:
	var result = combat.act(skill_id, target)
	toast_text = "" if result.ok else result.message
	_after_combat_step()

func _ultimate(id: String) -> void:
	var result = combat.request_ultimate(id, selected_target)
	if result.ok:
		if battle_timer > 0 or view.is_animating():
			toast_text = "终结技已排队，在当前动作结束后释放。"
			_refresh()
			return
		toast_text = ""
		combat.resolve_queued()
	else:
		toast_text = result.message
	_after_combat_step()

func _swap_dialog() -> void:
	var box = _modal("换入同地候补", 600, 500)
	for id in combat.reserves():
		_button(box, run.actor(id).name + " · HP %d · 精力 %d" % [run.actor(id).hp, run.actor(id).ap], func(): _close_modal(); _run_action(combat.swap(id)); _after_combat_step())
	_button(box, "取消", _close_modal)

func _after_combat_step() -> void:
	var presentation_events = combat.events.duplicate(true)
	combat.events.clear()
	battle_timer = 0.08
	if not combat.alive_enemies().has(selected_target) and not combat.alive_enemies().is_empty():
		selected_target = combat.alive_enemies()[0]
	view.animate_events(presentation_events)
	_refresh()

func _finish_battle() -> void:
	if combat == null or combat.outcome == "":
		return
	var victory = combat.outcome == "victory"
	combat = null
	selected_cell = run.actor(selected_id).position
	moving_ids = _squad_movers(selected_id)
	if victory:
		sound.play("victory")
		_victory_dialog()
		return
	view.end_battle()
	_refresh()
	if run.data.status == "failed":
		_ending_story()
	else:
		_show_relic_intro()

func _victory_dialog() -> void:
	var result: Dictionary = run.data.pending_victory
	var box = _modal("战斗胜利", 700, 530)
	box.get_parent().name = "VictoryScreen"
	ui.hide()
	var content = _scroll_content(box)
	_text(content, "已击败 %d 名敌人" % int(result.enemies), 19, muted)
	_text(content, "战利品", 20, gold)
	if not result.salve_receiver.is_empty():
		_text(content, "疗伤药 ×1 · %s 收入背包" % run.actor(result.salve_receiver).name, 17)
	if not result.relic.is_empty():
		_text(content, ("新增副本 · " if result.get("relic_duplicate", false) else "发现遗器 · ") + Relics.DATA[result.relic].name, 17, gold)
	if result.get("coins", 0) > 0:
		_text(content, "获得 %d 灯铢" % result.coins, 17, gold)
	if result.salve_receiver.is_empty() and result.relic.is_empty() and result.get("coins", 0) <= 0:
		_text(content, "本场没有新增战利品。", 17, muted)
	content.add_child(HSeparator.new())
	_text(content, "参战队员", 20, gold)
	for id in result.members:
		var actor = run.actor(id)
		var recovered = " · 倒下后已恢复至 1 HP" if id in result.revived else ""
		_text(content, "%s · HP %d/%d · MP %d/%d%s" % [actor.name, actor.hp, actor.hp_max, actor.mp, actor.mp_max, recovered], 16)
	var save_error = _text(box, "", 15, gold)
	save_error.hide()
	var next = _button(box, "继续远征", func():
		run.data.erase("pending_victory")
		var saved = run.save_game()
		if not saved.ok:
			run.data.pending_victory = result
			save_error.text = saved.message
			save_error.show()
			return
		if view.battle_mode:
			view.end_battle()
		_close_modal()
		_refresh()
		if run.data.status == "won":
			_ending_story()
		elif not _show_chapter() and not _show_relic_intro(_show_npc_encounter.bind(selected_id)):
			_show_npc_encounter(selected_id))
	next.grab_focus()

func _process(delta: float) -> void:
	if combat == null:
		return
	if combat.outcome != "":
		if not view.is_animating(): _finish_battle()
		return
	if modal_layer.get_child_count() > 0 or view.is_animating():
		return
	if combat.reveal_pending:
		_final_battle_page(0)
		return
	var was_playing = battle_timer > 0
	battle_timer -= delta
	if battle_timer <= 0 and not combat.queue.is_empty():
		toast_text = ""
		combat.resolve_queued()
		_after_combat_step()
		return
	if battle_timer <= 0 and (combat.enemies.has(combat.current) or combat.madness.has(combat.current) or combat.auto_mode):
		combat.step_auto()
		_after_combat_step()
	elif was_playing and battle_timer <= 0:
		_refresh()

func _chapter_pages() -> Array:
	return [
		["留下的人", "路边的行人指给你看：一位亡者反复走向断掉的路，却怎么也离不开。行人认得对方，说活人早已安葬了遗体，魂魄却仍留着。\n\n你想伸手接住那踉跄的身影，脚边的碎石竟随手势轻轻浮起。记忆里也曾有一只手握着你。你答应过，要让无处可去的亡者有一个归处。"],
		["失去的制衡", "两名逃难者在路边争抢水源。你把横在他们之间的刀压进土里，请双方说清来路：一边的井被滞留的亡魂困住，另一边的粮道毁于诸神交战。原本互通有无的村落，如今都怕先饿死。\n\n他们随身的旧约抄本提到，过去另有一股神明的势力约束诸方。那股力量消失后，卡德兰从扩大的纷争中不断获益。你记起了怎样将压住刀锋的力量铺开。"],
		["未完成的停战会", "一名保存旧碑拓片的行者请你辨认残字：卡德兰邀另一位神赴停战会，记录却止于神躯被毁的那天。碑文边的祭祀记录显示，从那以后，亡者再没有被接走。名字所在的一角早已破损。\n\n你记起自己曾走进同样的会场。你不是去夺取领地，而是要求诸方停止把灾难推给活人与亡者。那份承诺，至今还没有履行完。"],
		["找到战神", "一名刚离开卡德兰驻地的信使拦住你。信使带着盖有战神印记的征调书，也画下了亲自走过的道路。你们把图上的山口、河岸与已探明的地貌逐一核对，确认了驻地的位置。\n\n征调书要求继续争夺粮道。亡魂造成的灾厄没有受到约束，各方的恐惧与报复仍在滋养战神。你把驻地标进地图：要恢复制衡，也要让无处可去的亡者得到安息。"],
	]

func _show_chapter() -> bool:
	var chapter = run.pending_chapter()
	if chapter == 0 or selected_id != "hero" or run.actor("hero").hp <= 0:
		return false
	var page = _chapter_pages()[chapter - 1]
	_show_story(page[0], "旅人", page[1], _story_scene_at(run.actor(selected_id).position), [_story_portrait("hero")], [],
		func(_option: String):
			run.finish_chapter(chapter)
			run.save_game()
			_close_modal()
			_refresh()
			if not _show_chapter() and not _show_relic_intro():
				_show_npc_encounter(selected_id), {})
	return true

func _final_battle_page(index: int) -> void:
	var pages = [
		["旅人", "战神的武器亮起红光，朝你劈来。\n\n你想起来了。很久以前，他也是这样举起武器的。那一击杀了你。"],
		["旅人", "你是伊文洛，死亡之神。你既掌握死亡本身，也负责把亡魂引渡到冥界。一路使碎石浮起、让脚步变轻的重力，本就是你引导灵魂的权能。\n\n恢复的权能让你感知到冥界留下的痕迹：神躯毁灭后，只有你的死亡本质重新凝成肉身。这种特殊性，连当年的你自己也不知道。后来，一次为逃难者求援的恶魔召唤意外将昏迷的你带到现世。村民救下了你。"],
		["卡德兰", "你的肉体已经被我彻底摧毁，引渡也真的停止了。我亲自确认过！没有你的势力制衡，亡者滞留造成灾厄，活人为了水、粮食和报复打得更凶。我只需让纷争继续。\n\n我不知道你还能重生。连你当年，也从未说过还有这一条退路。"],
		["旁白", "你伸出手，用重力为亡魂指出通往冥界的方向。那些留在现世的灵魂终于有了归处；你没有把它们变成兵器，而是履行让亡者安息的承诺。\n\n灾厄失去了源头，但活人的伤口不会因此消失。此刻，你要先让眼前的战神失去继续逼迫诸方交战的力量。"],
		["旁白", "你将冥界的一部分引到战场，收住河界，留出仍属现世的岸地。冥河能够洗刷、剥夺、吞噬一切，不会天然分辨敌友。你留在岸上，以归来的权能挡住攻击，将河水约束在卡德兰脚下。\n\n河水逐步剥离战神的力量。现在，要亲手结束这一战。"],
	]
	var page = pages[index]
	var met_demon = Catalog.COMPANIONS.keys().any(func(id): return Catalog.COMPANIONS[id].race == "恶魔" and run.data.story[id].met)
	if index == 3 and met_demon:
		page[1] += "\n\n你也终于明白，恶魔在你身边感到熟悉，是因为它们认得故乡的气息。"
	var scene = "final_memory" if index < 2 else _story_scene_at(run.data.boss) if index == 2 else "finale"
	var portraits = [] if index < 2 else [_story_portrait("hero", "battle"), _story_portrait("war_god", "anger" if index == 2 else "surprise")]
	_show_story("记忆回来了", page[0], page[1], scene, portraits, [],
		func(_option: String):
			if index + 1 < pages.size():
				_final_battle_page(index + 1)
			else:
				combat.awaken_death_power()
				_close_modal()
				_refresh(), {})

func _show_npc_encounter(visitor: String) -> void:
	var cell: String = run.actor(visitor).position
	var id: String = run.data.tiles[cell].npc
	var npc = run.actor(id)
	if npc.is_empty() or npc.joined or npc.position != cell:
		return
	var intro = narrative.encounter_intro(visitor, id)
	if not intro.ok or run.data.story[id].met:
		return
	if selected_id != visitor:
		selected_id = visitor
		view.focus_cell(cell)
		_refresh()
	_node_dialog()

func _talk(id: String) -> void:
	var intro = narrative.encounter_intro(selected_id, id)
	if not intro.ok:
		_notice(intro.message)
		return
	_begin_dialogue(id)

func _begin_dialogue(id: String) -> void:
	dialogue_subject = id
	dialogue_response = ""
	dialogue_ready = false
	_render_dialogue()

func _story_region(control: Control, left: float, top: float, right: float, bottom: float) -> void:
	control.set_anchor_and_offset(SIDE_RIGHT, right, 0)
	control.set_anchor_and_offset(SIDE_BOTTOM, bottom, 0)
	control.set_anchor_and_offset(SIDE_LEFT, left, 0)
	control.set_anchor_and_offset(SIDE_TOP, top, 0)

func _story_text_pages(body: String, label: Label) -> PackedStringArray:
	var pages = PackedStringArray()
	var remaining = body
	var font = label.get_theme_font("font")
	var font_size = label.get_theme_font_size("font_size")
	var spacing = label.get_theme_constant("line_spacing")
	while not remaining.is_empty():
		var paragraph = TextParagraph.new()
		paragraph.width = label.size.x
		paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
		paragraph.add_string(remaining, font, font_size)
		var height = 0.0
		var end = 0
		for line in paragraph.get_line_count():
			var line_height = paragraph.get_line_size(line).y + (spacing if line > 0 else 0)
			if line > 0 and height + line_height > label.size.y:
				break
			height += line_height
			end = paragraph.get_line_range(line).y
		if end < remaining.length():
			var fitted_end = end
			var boundary = remaining.left(end).rfind("\n\n")
			if boundary >= end / 2:
				end = boundary + 2
			else:
				for index in range(end - 1, end / 2, -1):
					if remaining[index] in "。！？!?":
						end = index + 1
						if end < fitted_end and remaining[end] in "」』”\"":
							end += 1
						break
			while end < remaining.length() and remaining[end] in "\n\r \t":
				end += 1
		pages.append(remaining.left(end))
		remaining = remaining.substr(end)
	return pages if not pages.is_empty() else PackedStringArray([""])

func _show_story(title: String, speaker: String, body: String, scene: String,
		portraits: Array, options: Array, on_choice: Callable, actions: Dictionary, tint: Color = Color.WHITE, page_index: int = 0) -> void:
	_clear_map_move()
	move_preview.hide()
	_clear(modal_layer)
	ui.hide()
	view.hide()
	view.set_process(false)
	view.set_world_input_enabled(false)
	var overlay = ColorRect.new()
	overlay.name = "StoryScreen"
	overlay.color = Color("10191b")
	modal_layer.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background = TextureRect.new()
	background.texture = _story_texture(scene)
	background.modulate = tint
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	for i in portraits.size():
		if portraits[i] == null:
			continue
		var actor_image = TextureRect.new()
		actor_image.name = "StoryActor%d" % i
		actor_image.texture = portraits[i]
		actor_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		actor_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		actor_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(actor_image)
		var left = 0.10 + 0.28 * i
		_story_region(actor_image, left, 0.10, left + 0.28, 0.78)

	var gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.14, 0.53, 0.78, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.02, 0.03, 0.04, 0.74), Color(0.02, 0.03, 0.04, 0.0),
		Color(0.02, 0.03, 0.04, 0.06), Color(0.02, 0.03, 0.04, 0.91), Color(0.02, 0.03, 0.04, 0.98),
	])
	var shade_texture = GradientTexture2D.new()
	shade_texture.gradient = gradient
	shade_texture.fill_to = Vector2(0, 1)
	var shade = TextureRect.new()
	shade.texture = shade_texture
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	overlay.add_child(header)
	_story_region(header, 0.05, 0.035, 0.95, 0.087)
	_text(header, "剧情  /  " + title, 17, gold)
	for label in actions:
		_button(header, label, actions[label])

	var dialogue = Control.new()
	dialogue.name = "Dialogue"
	dialogue.mouse_filter = Control.MOUSE_FILTER_PASS
	overlay.add_child(dialogue)
	_story_region(dialogue, 0.05, 0.74, 0.60, 0.955)
	var speaker_label = _text(dialogue, speaker, 22, gold)
	_story_region(speaker_label, 0, 0, 1, 0)
	var separator = HSeparator.new()
	dialogue.add_child(separator)
	separator.position.y = speaker_label.get_minimum_size().y + 8
	separator.size.x = dialogue.size.x
	var text_label = _text(dialogue, "", 20, ink)
	text_label.name = "StoryText"
	text_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text_label.offset_top = separator.position.y + separator.get_minimum_size().y + 8
	var pages = _story_text_pages(body, text_label)
	text_label.text = pages[page_index].strip_edges()
	var counter = _text(header, "第 %d / %d 页" % [page_index + 1, pages.size()], 15, muted)
	counter.name = "PageCounter"
	var turn_page = func(index: int):
		_show_story(title, speaker, body, scene, portraits, options, on_choice, actions, tint, index)
	var navigation = HBoxContainer.new()
	navigation.name = "StoryNavigation"
	navigation.alignment = BoxContainer.ALIGNMENT_END
	navigation.add_theme_constant_override("separation", 12)
	overlay.add_child(navigation)
	_story_region(navigation, 0.64, 0.90, 0.95, 0.955)
	if page_index > 0:
		_button(navigation, "上一页", turn_page.bind(page_index - 1))
	if page_index < pages.size() - 1 or options.is_empty():
		var advance = func():
			if page_index < pages.size() - 1:
				turn_page.call(page_index + 1)
			else:
				on_choice.call("")
		_button(navigation, "下一页" if page_index < pages.size() - 1 else "继续", advance)
		header.mouse_filter = Control.MOUSE_FILTER_PASS
		overlay.focus_mode = Control.FOCUS_ALL
		overlay.gui_input.connect(func(event: InputEvent):
			var mouse_release = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed
			if mouse_release or (event.is_action_pressed("ui_accept") and not event.is_echo()):
				overlay.accept_event()
				advance.call())
		overlay.grab_focus()
		return

	var option_scroll = ScrollContainer.new()
	option_scroll.name = "StoryChoices"
	option_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	option_scroll.follow_focus = true
	overlay.add_child(option_scroll)
	_story_region(option_scroll, 0.64, 0.43, 0.95, 0.88)
	var choices = VBoxContainer.new()
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices.size_flags_vertical = Control.SIZE_EXPAND_FILL
	choices.alignment = BoxContainer.ALIGNMENT_END
	choices.add_theme_constant_override("separation", 6)
	option_scroll.add_child(choices)
	var first_enabled: Button
	for option in options:
		if not option.get("enabled", true):
			continue
		var button = _button(choices, str(option.text), on_choice.bind(str(option.id)))
		button.custom_minimum_size.y = 43
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_stylebox_override("normal", _style(Color("202b30f2"), Color("b4a079"), 2))
		button.add_theme_stylebox_override("hover", _style(Color("37464b"), gold, 2))
		if first_enabled == null:
			first_enabled = button
	if first_enabled != null:
		first_enabled.grab_focus()

func _story_texture(scene: String) -> Texture2D:
	var path = "res://assets/story/" + scene + ".png"
	return load(path) if ResourceLoader.exists(path) else load("res://assets/story/" + STORY_TERRAIN.get(scene.trim_prefix("village_"), "road") + ".png")

func _story_scene_at(position: String) -> String:
	return STORY_TERRAIN.get(run.data.tiles[position].terrain, "road")

func _story_portrait(id: String, pose: String = "") -> Texture2D:
	var villager = id.begins_with("villager_")
	var directory = "res://assets/portraits/"
	var atlas_path = directory + id + "_poses.png"
	if (villager or not pose.is_empty()) and ResourceLoader.exists(atlas_path):
		var sheet: Texture2D = load(atlas_path)
		var sprite = AtlasTexture.new()
		sprite.atlas = sheet
		var cell = Vector2(sheet.get_size()) / Vector2(2, 3)
		var index = {"concerned": 1, "serious": 2, "farewell": 3, "grief": 4, "battle": 5}.get(pose, 0) if villager else {"serious": 0, "friendly": 1, "grief": 2, "anger": 3, "surprise": 4, "battle": 5}.get(pose, 0)
		sprite.region = Rect2(Vector2(int(index) % 2, floori(float(index) / 2.0)) * cell, cell)
		sprite.filter_clip = true
		return sprite
	var path = directory + id + ".png"
	return load(path) if ResourceLoader.exists(path) else null

func _render_dialogue() -> void:
	var d = narrative.dialogue(selected_id, dialogue_subject)
	if not d.ok:
		_notice(d.message)
		return
	var pose = "friendly" if not dialogue_response.is_empty() and run.actor(dialogue_subject).joined else str(d.get("pose", ""))
	if run.actor(dialogue_subject).hp <= 0:
		pose = "grief"
	elif dialogue_ready and pose.is_empty():
		pose = "serious"
	var subject_portrait = _story_portrait(dialogue_subject, pose)
	var speaker = str(d.title).get_slice(" · ", 0)
	if subject_portrait == null or not dialogue_response.is_empty():
		speaker = "旁白"
	var text = d.text if dialogue_response.is_empty() else dialogue_response
	var portraits = [_story_portrait(selected_id), subject_portrait]
	var scene = _story_scene_at(run.actor(selected_id).position)
	if not dialogue_ready:
		_show_story(d.title, speaker, text, scene, portraits, [],
			func(_option: String):
				dialogue_ready = true
				_render_dialogue(), {"结束交谈": _close_modal})
	elif dialogue_response.is_empty():
		_show_story(d.title, "旁白", "你打算怎么回答？", scene, portraits, d.options, _story_choice, {"结束交谈": _close_modal})
	else:
		_show_story(d.title, speaker, text, scene, portraits, [],
			func(_option: String):
				dialogue_response = ""
				_render_dialogue(),
			{"结束交谈": _close_modal})
	run.save_game()

func _personal_quest(ready: bool = false) -> void:
	var quest = narrative.personal_quest(selected_id, dialogue_subject)
	if not quest.ok:
		_notice(quest.message)
		return
	var person = run.actor(dialogue_subject)
	var portraits = [_story_portrait(selected_id), _story_portrait(dialogue_subject, quest.get("pose", "serious"))]
	var scene = _story_scene_at(person.position)
	if ready:
		_show_story(quest.title, person.name, "这次，你们决定怎么做？", scene, portraits, quest.options,
			_story_choice, {"再想一想": _render_dialogue})
	else:
		_show_story(quest.title, person.name, quest.text, scene, portraits, [],
			func(_option: String): _personal_quest(true), {"返回交谈": _render_dialogue})

func _story_choice(option_id: String) -> void:
	if option_id == "duel":
		var person = run.actor(dialogue_subject)
		var scene = _story_scene_at(person.position)
		_show_story(person.name, person.name, "「真要交手？双方都可能受伤。」", scene, [_story_portrait(dialogue_subject, "battle")],
			[_node_option("start_duel", "开始交手"), _node_option("back", "先不打")],
			func(choice: String):
				if choice == "start_duel":
					_story_choice(choice)
				else:
					_render_dialogue(), {"结束交谈": _close_modal})
		return
	var result = narrative.choose(selected_id, dialogue_subject, "duel" if option_id == "start_duel" else option_id)
	if not result.ok:
		dialogue_response = result.message
		_render_dialogue()
		return
	if option_id == "join":
		moving_ids.append(dialogue_subject)
	run.save_game()
	if _show_relic_intro(func():
		dialogue_response = ""
		_render_dialogue()):
		return
	if result.get("close", false):
		_close_modal()
		_refresh()
	elif result.get("quest", false):
		_personal_quest()
	elif result.get("battle", false):
		_formation_dialog()
	elif result.has("rescue"):
		_item_dialog(selected_id)
	elif result.has("heal_dialog"):
		_healing_dialog()
	else:
		dialogue_response = str(result.get("response", "同行状态已更新。"))
		_refresh()
		_render_dialogue()

func _show_relic_intro(after: Callable = Callable()) -> bool:
	var intro = run.relic_intro()
	if intro.is_empty():
		return false
	var definition = Relics.DATA[intro.id]
	var scene = _story_scene_at(intro.position)
	var portraits = [_story_portrait(intro.finder), _story_portrait(intro.npc) if not intro.npc.is_empty() else null]
	var effect_page = intro.stage == 1
	var body: String = definition.effect if effect_page else definition.story
	if not effect_page and not intro.lead.is_empty():
		body = intro.lead + "\n\n" + body
	var speaker = ("已共鸣" if run.has_relic(intro.id) else "遗器效果") if effect_page else "旁白"
	_show_story("获得遗器 · " + definition.name, speaker, body, scene, portraits, [], func(_option: String):
		if not effect_page:
			intro.stage = 1
			run.save_game()
			_show_relic_intro(after)
			return
		run.data.relic_intros.pop_front()
		run.save_game()
		if not _show_relic_intro(after):
			_close_modal()
			_refresh()
			if not _show_chapter() and after.is_valid():
				after.call(), {})
	return true

func _journal() -> void:
	var box = _modal("旅途手记 · 线索与同行", 920, 720)
	var content = _scroll_content(box)
	_text(content, _expedition_objective(), 23, gold)
	_text(content, "地图种子 %s" % run.data.seed, 15, muted)
	for key in run.data.map_intel:
		if str(key).begins_with("cache:"):
			_text(content, "藏物点标记 · " + str(key).trim_prefix("cache:"), 15, muted)
		elif str(key).begins_with("encounter:"):
			var info = run.data.map_intel[key]
			var elements: Array = info.elements.map(func(element): return Catalog.ELEMENT_NAMES.get(element, element))
			_text(content, "遭遇拓片 · %s · %d 个敌人 · %s" % [str(key).trim_prefix("encounter:"), info.count, "、".join(elements)], 15, muted)
	var route = run.data.route_records.get(selected_id, {})
	if not route.is_empty():
		var steps: Array[String] = []
		for i in route.steps.size():
			steps.append("%s（%d）" % [route.path[i + 1], route.steps[i]])
		_text(content, "引路绳路线 · %d 精力 · %s → %s" % [route.cost, route.origin, " → ".join(steps)], 15, muted)
	if run.boss_known():
		_button(content, "在地图上定位战神", func(): _close_modal(); selected_cell = run.data.boss; view.focus_cell(selected_cell); _refresh())
	for chapter in range(int(run.data.chapter)):
		var page = _chapter_pages()[chapter]
		_text(content, page[0], 20, gold)
		_text(content, page[1], 16, muted)
	for id in Catalog.COMPANIONS:
		if run.data.story[id].met:
			var relation = "已同行" if run.actor(id).joined else "已见过"
			if run.actor(id).joined:
				relation += " · 已作出个人抉择" if not str(run.data.story[id].get("personal_choice", "")).is_empty() else " · 可同地谈谈心事"
			_text(content, "%s · %s" % [run.actor(id).name, relation], 18, muted)
	var clues: Array[String] = []
	for cell in run.data.nodes:
		var node = run.node_at(cell)
		if not run.data.leads.has(cell):
			continue
		var event = Nodes.story(node)
		if event.is_empty():
			continue
		var entry = str(event.title)
		if node.result == "record" or node.get("investigated", false):
			entry += "\n" + str(event.evidence)
		if not node.result.is_empty() and node.result != "record":
			entry += "\n" + Nodes.resolution(node)
		clues.append(entry)
	if not clues.is_empty():
		_text(content, "路上记录的线索", 20, gold)
		_text(content, "\n".join(clues), 16, muted)
	_text(content, "同地角色可当面交换亲历见闻，共享地图不传送物品。", 16, muted)
	_button(box, "合上手记", _close_modal)

func _summary(screen: Vector2) -> void:
	var box = _panel(ui, Rect2(300, 135, screen.x - 600, screen.y - 300))
	_text(box, "战争结束" if run.data.status == "won" else "远征终止", 36, gold)
	_text(box, "第 %d 天 · 到访 %d 格 · 战斗 %d 场" % [run.data.day, run.data.visited.size(), run.data.battles], 18)
	if run.data.status == "failed":
		_text(box, run.data.flags.get("failure_reason", "远征失败。"), 20, muted)
	else:
		_text(box, narrative.main_ending().title, 25, gold)
	var met_count = Catalog.COMPANIONS.keys().filter(func(id): return run.data.story[id].met).size()
	_text(box, "主线结局与 %d 位相识者的后续已记下。查看结局剧情，逐页读完这段旅途。" % met_count, 18, muted)
	_button(box, "查看结局剧情", _ending_story)
	_button(box, "返回主菜单", _to_menu)

func _ending_story() -> void:
	var ending: Dictionary = narrative.main_ending()
	var pages: Array[Dictionary] = [{
		"title": ending.title, "speaker": "旁白", "text": ending.text,
		"scene": _story_scene_at(run.actor("hero").position), "actor": "hero",
	}]
	for id in Catalog.COMPANIONS:
		if not run.actor(id).joined and not run.data.story[id].met:
			continue
		var epilogue: Dictionary = narrative.character_ending(id)
		pages.append({
			"title": "尾声 · " + epilogue.name, "speaker": "旁白", "text": epilogue.text,
			"scene": _story_scene_at(run.actor(id).position), "actor": id,
		})
	_ending_page(pages, 0)

func _ending_page(pages: Array[Dictionary], index: int) -> void:
	var page: Dictionary = pages[index]
	var last = index == pages.size() - 1
	_show_story(page.title, page.speaker, page.text, page.scene, [_story_portrait(page.actor, "grief" if run.actor(page.actor).hp <= 0 else "friendly")],
		[],
		func(_option: String):
			if last:
				_close_modal()
			else:
				_ending_page(pages, index + 1),
		{"返回远征记录": _close_modal})

func _to_menu() -> void:
	if combat != null:
		_confirm("返回菜单？", "未完成战斗将保留同一个战前检查点与随机状态；继续时重新进入本场遭遇。", func():
			combat = null
			view.end_battle()
			_show_opening(Screen.MENU))
	else:
		run.save_game()
		_show_opening(Screen.MENU)

func _guide() -> void:
	_notice("点队友所在格切换小队。移动时点相邻格预览精力，再点一次确认。要走到队友所在格，先点当前小队所在格。左栏可勾选同格角色同行。\n\n「行动」打开脚下的节点。歇脚点、药品和治疗技能恢复生命或魔力，结束一天恢复精力。灯铢由全队共享，买到的物品进入交易者背包。\n\n同地最多四人出战，候补换人占正常行动，终结技可插队。从沿途的故事和遭遇里找线索，找到并击败战神。")

func _settings_dialog() -> void:
	var box = _modal("设置与操作", 650, 430)
	_text(box, "音效音量（0 为静音）", 20, gold)
	var slider = HSlider.new()
	slider.min_value = 0
	slider.max_value = 1
	slider.step = 0.05
	slider.value = sound.volume
	slider.value_changed.connect(func(value: float): sound.set_volume(value))
	box.add_child(slider)
	_text(box, "按住左键拖动地图 · WASD 平移 · 滚轮缩放\n点地图切换小队，左侧可勾选同格成员同行。\n战场右上角可切换自动战斗和使用道具。", 18, muted)
	_button(box, "查看完整操作指南", _guide)
	_button(box, "制作与许可", _credits_dialog)
	if screen_state == Screen.EXPEDITION and combat == null and run.data.status == "exploring":
		_button(box, "放弃本次远征", func():
			_confirm("结束本次远征？", "这次旅程将在这里结束。", _abandon_run))
	_button(box, "返回", _close_modal)

func _abandon_run() -> void:
	run.data.status = "failed"
	run.data.flags.failure_reason = "你主动结束了本次远征。"
	run.save_game()
	_refresh()
	_ending_story()

func _credits_dialog() -> void:
	var box = _modal("制作与许可", 800, 650)
	var content = _scroll_content(box)
	_text(content, "维洛丹 · 试玩\n原创世界观、角色与肖像；原创怪物、适配、特效及合成音效。肖像由内置图像生成工具制作。\n\n人形模型、动作与自然地景：Kay Lousberg，CC0。\n狼基础模型：crownjoshua，CC0；本项目修复绑定并制作动作。\n粒子纹理：Kenney，CC0。\n字体：Noto Sans SC，SIL Open Font License。\n引擎：Godot " + Engine.get_version_info().string + "\n完整来源、许可与适配说明随试玩包附带。", 18)
	_text(content, Engine.get_license_text(), 14, muted)
	_button(box, "返回设置", _settings_dialog)

func _smoke_capture() -> void:
	get_viewport().get_texture().get_image().save_png("user://smoke.png")
	print("SMOKE_FRAME=", ProjectSettings.globalize_path("user://smoke.png"))
	if "--smoke-exit" in OS.get_cmdline_user_args():
		get_tree().quit()
