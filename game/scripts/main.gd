extends Node
const Run = preload("res://scripts/domain/expedition.gd")
const Catalog = preload("res://scripts/domain/catalog.gd")
const Hex = preload("res://scripts/domain/hex_map.gd")
const Combat = preload("res://scripts/domain/battle.gd")
const Story = preload("res://scripts/domain/narrative.gd")
const Relics = preload("res://scripts/domain/relic_catalog.gd")
const Gear = preload("res://scripts/domain/gear_catalog.gd")
const CharacterCodex = preload("res://scripts/presentation/character_codex.gd")
var item_operation_serial = 0
const Nodes = preload("res://scripts/domain/map_nodes.gd")
const OpeningStory = preload("res://scripts/domain/opening_story.gd")
const StoryPortrait = preload("res://scripts/presentation/story_portrait.gdshader")
const World = preload("res://scripts/presentation/world_view.gd")
const MapMovePreview = preload("res://scripts/presentation/map_move_preview.gd")
const InventoryPage = preload("res://scripts/presentation/inventory_page.gd")
const DayTransition = preload("res://scripts/presentation/day_transition.gd")
const FontAsset = preload("res://assets/fonts/NotoSansSC.ttf")
const Sound = preload("res://scripts/presentation/sound.gd")
enum Screen { MENU, OPENING_STORY, EXPEDITION }
const OBJECTIVE_ICON = preload("res://assets/ui/expedition-objective.svg")
const LAMP_COIN_ICON = preload("res://assets/ui/lamp-coin.svg")
const SHIELD_ICON = preload("res://assets/ui/shield-badge.svg")
const SHIELD_BADGE_SIZE = Vector2(29, 31)
const CREW_PANEL_WIDTH = 288
const STORY_TERRAIN = {
	"plains": "road", "forest": "woodland", "mountain": "highland", "ruins": "ruins",
	"desert": "drylands", "swamp": "wetlands",
}
const CREW_PORTRAIT_BACKGROUNDS = {
	"gravity": Color("17161e"),
	"fire": Color("773831"),
	"water": Color("24536e"),
	"wind": Color("376452"),
	"ice": Color("496978"),
	"lightning": Color("513b69"),
	"earth": Color("5e482f"),
	"normal": Color("3d4741"),
}
var run = Run.new()
var view: Node3D
var ui: Control
var modal_layer: Control
var combat: RefCounted
var selected_id = "hero"
var selected_cell = ""
var move_target = ""
var map_traveling = false
var travel_clock: Dictionary = {}
var move_preview = MapMovePreview.new()
var day_transition = DayTransition.new()
var day_transition_pending := false
var crew_collapsed = false
var chosen_seed = ""
var opening_seed = 20261104
var selected_target = "enemy_0"
var screen_state = Screen.MENU
var battle_timer = 0.0
var toast_text = ""
var narrative: RefCounted
var dialogue_subject = ""
var character_codex_state: Dictionary = {}
var story_history: Array[Dictionary] = []
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
	day_transition.theme = theme
	day_transition.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(day_transition)
	day_transition.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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

func _shortcut_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	var codex = modal_layer.get_node_or_null("CharacterCodex")
	if codex != null:
		get_viewport().set_input_as_handled()
		if not codex.close_zoom():
			_close_character_codex()
		return
	var layer = modal_layer.get_node_or_null("StoryHistory")
	if layer == null:
		layer = modal_layer.get_node_or_null("StoryScreen")
	if layer == null:
		return
	var close = layer.find_child("StoryCancel", true, false) as Button
	if close != null:
		get_viewport().set_input_as_handled()
		close.pressed.emit()

func _enemy_hp_bar(parent: Node, hp: float, maximum: float) -> void:
	var bar = ProgressBar.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.value = hp / maxf(1.0, maximum) * 100
	bar.show_percentage = false
	bar.custom_minimum_size.y = 6
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
		_crew_panel()
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
	if FileAccess.file_exists(run.save_path):
		_button(box, "继续上次远征", _continue_run)
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
	day_transition_pending = false
	day_transition.dismiss()
	character_codex_state = {}
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
	story_history.clear()
	_show_opening(Screen.OPENING_STORY)
	opening_seed = randi() if chosen_seed.is_empty() else _seed_value()
	var generated = Hex.generate(opening_seed)
	var terrain: String = generated.tiles[generated.start].terrain
	_opening_world_page(terrain, OpeningStory.world_pages(), 0)

func _opening_world_page(terrain: String, pages: Array[Dictionary], index: int) -> void:
	var page = pages[index]
	_show_story("维洛丹", "旁白", page.text, page.scene, [], [],
		func(_option: String):
			if index + 1 < pages.size():
				_opening_world_page(terrain, pages, index + 1)
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
	var pose: String = poses[index]
	# The dwarf's serious pose includes a bridge sketch.
	if villager == "villager_dwarf" and pose == "serious":
		pose = ""
	var pages = OpeningStory.dialogue(terrain)
	var page = pages[index]
	_show_story(local[0], page[0], page[1], "village_" + terrain,
		[_story_portrait("hero", "serious")] if page[0] == "旅人" else [_story_portrait(villager, pose)], [],
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
	day_transition_pending = false
	day_transition.dismiss()
	character_codex_state = {}
	_close_modal()
	if screen_state != Screen.OPENING_STORY:
		story_history.clear()
	var value = opening_seed if screen_state == Screen.OPENING_STORY else _seed_value()
	run.new_run(value, "wayfarer")
	map_traveling = false
	travel_clock.clear()
	combat = null
	_clear_map_move()
	view.reset()
	selected_id = "hero"
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
	day_transition_pending = false
	day_transition.dismiss()
	character_codex_state = {}
	story_history.clear()
	map_traveling = false
	travel_clock.clear()
	combat = null
	_clear_map_move()
	toast_text = ""
	view.reset()
	selected_id = "hero"
	selected_cell = run.actor(selected_id).position
	screen_state = Screen.EXPEDITION
	view.refresh(run, selected_id, selected_cell)
	view.focus_cell(selected_cell)
	_refresh()
	if not run.data.pending_battle.is_empty():
		_show_encounter_intro()
	elif run.data.has("pending_victory"):
		_victory_dialog()
	elif run.data.status == "exploring":
		_show_arrival()

func _header(screen: Vector2) -> void:
	var box = _panel(ui, Rect2(20, 17, screen.x - 40, 88))
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	var title = VBoxContainer.new()
	title.custom_minimum_size.x = 190
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.alignment = BoxContainer.ALIGNMENT_CENTER
	title.add_theme_constant_override("separation", 0)
	row.add_child(title)
	_text(title, "维洛丹", 29, gold)
	var wallet = HBoxContainer.new()
	wallet.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	wallet.add_theme_constant_override("separation", 6)
	wallet.tooltip_text = "远征队灯铢"
	title.add_child(wallet)
	var coin = TextureRect.new()
	coin.texture = LAMP_COIN_ICON
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.custom_minimum_size = Vector2(22, 22)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wallet.add_child(coin)
	var balance = _text(wallet, str(int(run.data.lamp_coins)), 16, gold)
	balance.name = "LampCoinBalance"
	balance.autowrap_mode = TextServer.AUTOWRAP_OFF
	balance.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	balance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var weather = "细雨" if travel_clock.get("weather", run.data.weather) == "rain" else "晴朗"
	var exploration = floori(100.0 * run.data.explored.size() / run.data.tiles.size())
	var conditions = "第 %d 天 · %s" % [travel_clock.get("day", run.data.day), weather]
	if combat == null and run.data.status == "exploring":
		var tile = run.data.tiles[run.actor(selected_id).position]
		conditions += " · " + Catalog.terrain_name(tile.terrain)
	var status = _text(row, "%s\n探索度：%d%%" % [conditions, exploration], 16)
	status.name = "DayConditions"
	status.autowrap_mode = TextServer.AUTOWRAP_OFF
	status.custom_minimum_size.x = 168
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
	if combat == null and run.data.status == "exploring" and run.boss_known():
		_button(row, "定位战神", func():
			_clear_map_move()
			selected_cell = run.data.boss
			view.focus_cell(selected_cell)
			_refresh())
	_button(row, "设置/帮助", _settings_dialog)
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


func _crew_panel() -> void:
	var box = _panel(ui, Rect2(20, 120, CREW_PANEL_WIDTH, 56))
	if not crew_collapsed:
		var panel: PanelContainer = box.get_parent()
		panel.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -20.0)
	var heading = HBoxContainer.new()
	box.add_child(heading)
	_text(heading, "远征队", 24, gold).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_button(heading, "展开" if crew_collapsed else "收起", func():
		crew_collapsed = not crew_collapsed
		_refresh())
	if crew_collapsed:
		return
	_text(box, "点相邻格预览 · 再点确认", 13, muted)
	_crew_stamina(box)
	var roster = _scroll_content(box)
	roster.get_parent().horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	roster.add_theme_constant_override("separation", 6)
	for id in run.joined_ids():
		_crew_member(roster, id)
	var cell: String = run.actor(selected_id).position
	var codex_button = _button(box, "角色", _show_character_codex)
	if not character_codex_state.is_empty():
		codex_button.add_theme_stylebox_override("normal", _style(Color("34483a"), gold, 6))
		codex_button.add_theme_color_override("font_color", gold)
	var action = _button(box, "行动", _cell_actions)
	action.tooltip_text = _node_title(cell)
	_button(box, "背包", _inventory_dialog.bind(selected_id))

func _crew_stamina(parent: VBoxContainer) -> void:
	var row = HBoxContainer.new()
	parent.add_child(row)
	var steps = HBoxContainer.new()
	steps.name = "CrewStamina"
	steps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	steps.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	steps.add_theme_constant_override("separation", 4)
	row.add_child(steps)
	var remaining: int = travel_clock.get("steps", run.remaining_steps())
	var bright = _bar_style(Color("91c970"))
	var faded = _bar_style(Color("47604c"))
	for i in Run.STEPS_PER_DAY:
		var segment = Panel.new()
		segment.custom_minimum_size.y = 7
		segment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		segment.add_theme_stylebox_override("panel", bright if i < remaining else faded)
		steps.add_child(segment)
	_crew_meter_label(row, "精力")

func _crew_member(parent: VBoxContainer, id: String) -> void:
	var a = run.actor(id)
	var button = _button(parent, "", _select_actor.bind(id))
	button.name = "CrewMember_" + id
	button.custom_minimum_size.y = 106
	button.accessibility_name = a.name
	if a.hp <= 0:
		button.tooltip_text = "%s · 重伤" % a.name
	if selected_id != id:
		button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())

	var content = HBoxContainer.new()
	button.add_child(content)
	_member_status(content, id, int(a.hp))
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 5
	content.offset_right = -5
	content.offset_top = 3
	content.offset_bottom = -3

func _member_status(content: HBoxContainer, id: String, shown_hp: int) -> VBoxContainer:
	var a = run.actor(id)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 12)
	var identity = VBoxContainer.new()
	identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.custom_minimum_size.x = 80
	identity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	identity.add_theme_constant_override("separation", 2)
	content.add_child(identity)
	var element: String = "gravity" if id == "hero" else a.element
	var background: Color = CREW_PORTRAIT_BACKGROUNDS.get(element, CREW_PORTRAIT_BACKGROUNDS.normal)
	var portrait = Panel.new()
	portrait.name = "Portrait"
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.custom_minimum_size.y = 72
	portrait.add_theme_stylebox_override("panel", _style(background, background.lightened(0.30), 5))
	identity.add_child(portrait)
	var texture = _story_portrait(str(a.get("portrait", id)))
	if texture != null:
		var dimensions = Vector2(texture.get_size())
		var width = dimensions.x * 0.54
		var face = AtlasTexture.new()
		face.atlas = texture
		face.region = Rect2((dimensions.x - width) * 0.5, 0, width, minf(width, dimensions.y))
		face.filter_clip = true
		var image = TextureRect.new()
		image.texture = face
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.add_child(image)
		image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		image.offset_left = 1
		image.offset_right = -1
		image.offset_top = 1
		image.offset_bottom = -1

	var caption = _text(identity, a.name, 12, ink if shown_hp > 0 else muted)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var meters = VBoxContainer.new()
	meters.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meters.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meters.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meters.add_theme_constant_override("separation", 5)
	content.add_child(meters)
	_crew_meter(meters, "HP", shown_hp, a.hp_max, Color("e16562"))
	_crew_meter(meters, "MP", a.mp, a.mp_max, Color("65a6e6"))
	_crew_meter(meters, "充能", a.energy, Catalog.ENERGY_MAX, Color("eea353"))
	return meters

func _crew_meter(parent: VBoxContainer, caption: String, amount: float, maximum: float, color: Color) -> void:
	var row = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var bar = ProgressBar.new()
	bar.accessibility_name = caption
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.custom_minimum_size.y = 7
	bar.max_value = maxf(1.0, maximum)
	bar.value = amount
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", _bar_style(Color("3b524b")))
	bar.add_theme_stylebox_override("fill", _bar_style(color))
	row.add_child(bar)
	var value_label = _crew_meter_label(row, "%d/%d" % [int(amount), int(maximum)])
	value_label.custom_minimum_size.x = 58
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

func _crew_meter_label(parent: HBoxContainer, caption: String) -> Label:
	var label = _text(parent, caption, 12)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.custom_minimum_size.x = 32
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _cell_actions() -> void:
	var actor = run.actor(selected_id)
	var cell: String = actor.position
	var t = run.data.tiles[cell]
	var node = run.node_at(cell)
	var title = _node_title(cell)
	var has_encounter = run.knows_encounter(cell)
	var dialog = _modal(title, 570, 580)
	var box = _scroll_content(dialog)
	_text(box, "%s · 坐标 %s" % [Catalog.terrain_name(t.terrain), cell], 14, muted)
	var route: Dictionary = run.data.route_records.get(selected_id, {})
	if not route.is_empty():
		_text(box, "引路绳路线 · %d 步 · %s" % [route.path.size() - 1, " → ".join(route.path)], 15, muted)
	for key in run.data.map_intel:
		if str(key).begins_with("cache:"):
			_text(box, "藏物点标记 · " + str(key).trim_prefix("cache:"), 15, muted)
		elif str(key).begins_with("encounter:"):
			var info = run.data.map_intel[key]
			var elements: Array = info.elements.map(func(element): return Catalog.ELEMENT_NAMES.get(element, element))
			_text(box, "遭遇拓片 · %s · %d 个敌人 · %s" % [str(key).trim_prefix("encounter:"), info.count, "、".join(elements)], 15, muted)
	if not has_encounter and (t.site.is_empty() or (t.site == "boss" and not run.boss_known())) and not Nodes.story(node).is_empty():
		_button(box, "查看节点剧情", _node_dialog)
	if has_encounter:
		_text(box, "决战 · 已平息 %d 处纷争" % run.data.peace.size() if t.enemies.has("war_god") else "驻守敌人", 18, Color("e4ab87"))
		_text(box, "每场最多四名队员同时出战。", 14, muted)
		for enemy in t.enemies:
			_text(box, Catalog.ENEMIES[enemy].name + " · " + Catalog.ENEMIES[enemy].role, 14, muted)
			if run.actor("grit").joined and run.actor("grit").hp > 0 and run.actor("grit").position == cell:
				var definition = run.war_god_stats() if enemy == "war_god" else Catalog.ENEMIES[enemy]
				_text(box, "砾牙辨识：HP %d · 攻击 %d · 速度 %d" % [definition.hp, definition.attack, definition.speed], 13, gold)
		var requires_hero = t.enemies.has("war_god") and "hero" not in run.same_cell(cell, true)
		if requires_hero:
			_text(box, "旅人必须亲自迎战。", 15, muted)
		_button(box, "查看遭遇剧情", _open_current_encounter, run.same_cell(cell, true).is_empty() or requires_hero)
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
		_button(box, "采集", func(): _close_modal(); _run_action(run.collect(selected_id)))
	var relic: String = run.relic_sites.get(cell, "")
	if node.get("kind") != "cache" and not relic.is_empty() and t.enemies.is_empty() and not run.data.relic_claims.has("site:" + cell):
		_button(box, "调查" + Relics.SITES[relic][0], func():
			_close_modal()
			var result = run.investigate_relic(selected_id)
			_run_action(result)
			if result.ok and not _show_relic_intro():
				_notice(result.message))
	_button(box, "使用道具", _item_dialog.bind(selected_id))
	_button(dialog, "关闭", _close_modal)

func _node_title(cell: String) -> String:
	return run.location_name(cell)

func _site_impression() -> void:
	var cell: String = run.actor(selected_id).position
	var terrain: String = run.data.tiles[cell].terrain
	_show_story(_node_title(cell), "村民", "你回来啦。来喝口水吧。路上遇到难事的话，也可以坐下慢慢说。",
		STORY_TERRAIN[terrain], [], [_node_option("leave", "谢谢，我得继续赶路了。", true)], func(_choice: String): _close_modal(),
		{"结束交谈": _close_modal}, _node_tint())

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
			return "送别时，%s伸出手，给亡魂指了条离开这里的路。\n\n%s" % [run.actor("hero").name, conclusion]
		return conclusion
	if node.get("investigated", false):
		return str(event.investigation)
	return str(event.intro)

func _node_option(id: String, label: String, spoken: bool = false) -> Dictionary:
	return {"id": id, "text": label, "spoken": spoken}

func _node_dialog(feedback: String = "") -> void:
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
	var title = "%s · %s" % [_node_title(cell), event.title]
	var options: Array = []
	if not _node_resolved(node, tile):
		match node.kind:
			"trade":
				options.append(_node_option("trade", "查看货物 · 持有 %d 灯铢" % run.data.lamp_coins))
			"supply":
				options.append(_node_option("collect", "取用%s ×%d" % [Catalog.item_name(tile.resource), tile.quantity]))
			"rest":
				options.append(_node_option("pack", "带走一份" + Catalog.item_name(node.item)))
			"choice":
				options.append(_node_option("work", "%s · 得 %d 灯铢" % [event.work, node.coins]))
				options.append(_node_option("work_alternative", "%s · 得 %d 灯铢" % [event.alternative, node.coins]))
			"haunt":
				if not node.get("investigated", false):
					options.append(_node_option("inspect", event.investigation_label))
				elif "hero" in run.same_cell(cell, true):
					options.append(_node_option("settle", event.work))
					options.append(_node_option("settle_alternative", event.alternative))
				else:
					text += "\n已经问清了亡者牵挂的事，等旅人来了，再陪亡者告别。"
			"cache":
				options.append(_node_option("search", "搜寻旧物"))
			"battle", "elite":
				if run.knows_encounter(cell):
					options.append(_node_option("fight", "选择阵容并交战"))
	if not tile.npc.is_empty() and tile.npc != selected_id and run.actor(tile.npc).position == cell and tile.enemies.is_empty():
		options.append(_node_option("talk", "和%s交谈" % run.actor(tile.npc).name))
	options.append(_node_option("leave", "返回地图"))
	if not feedback.is_empty():
		_show_story(title, "旁白", text, STORY_TERRAIN[tile.terrain], [], [],
			func(_option: String):
				_show_story(title, "行动结果", feedback, STORY_TERRAIN[tile.terrain], [], options, _node_choice, {}, _node_tint()),
			{}, _node_tint())
	else:
		_show_story(title, "旁白", text, STORY_TERRAIN[tile.terrain], [], options, _node_choice, {}, _node_tint())

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
			_open_current_encounter(false)
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

func _footer(screen: Vector2) -> void:
	var box = _panel(ui, Rect2(20, screen.y - 140, screen.x - 40, 122))
	_text(box, toast_text if toast_text != "" else "旅途记录", 15, gold)
	var lines: Array[String] = []
	for line in run.data.log.slice(maxi(0, run.data.log.size() - 3)):
		lines.append(str(line))
	_text(box, "\n".join(lines), 14, muted)

func _clear_map_move() -> void:
	move_target = ""

func _select_actor(id: String, center_camera: bool = true) -> void:
	if map_traveling:
		return
	_clear_map_move()
	selected_id = id
	selected_cell = run.actor(id).position
	if center_camera:
		view.focus_cell(selected_cell)
	_refresh()

func _select_cell(id: String) -> void:
	if map_traveling or screen_state != Screen.EXPEDITION or combat != null or run.data.status != "exploring" or modal_layer.get_child_count() > 0:
		return
	if id == move_target and not id.is_empty():
		_move_selected()
		return
	var source: String = run.actor("hero").position
	selected_cell = id
	move_target = id if Hex.is_land(run.data.tiles, id) and id in Hex.neighbors(source, run.data.tiles) else ""
	_refresh()

func _show_move_preview() -> void:
	var caption = "移动 1 格"
	if run.remaining_steps() == 1:
		caption += " · 抵达后进入第 %d 天" % (int(run.data.day) + 1)
	var endpoint = Hex.world(move_target)
	endpoint.y = view.board_surface.height_at(endpoint) + 0.05
	move_preview.show_path(view.dolls["hero"], endpoint, [caption])

func _move_selected() -> void:
	if map_traveling:
		return
	var destination = move_target
	var first_visit = not run.has_visited(destination)
	var previous_clock := {"day": run.data.day, "weather": run.data.weather, "steps": run.remaining_steps()}
	_clear_map_move()
	var result = run.move(destination)
	var day_changed: bool = result.ok and run.data.day != previous_clock.day
	if result.ok:
		day_transition.dismiss()
		map_traveling = true
		if day_changed:
			travel_clock = previous_clock
		selected_id = "hero"
		selected_cell = destination
		if first_visit and not Nodes.story(run.node_at(destination)).is_empty():
			run.data.pending_arrival = {"actor": "hero", "cell": destination}
	_run_action(result)
	if not result.ok:
		return
	view.follow_map_movement("hero")
	var expedition: Dictionary = run.data
	while view.is_map_moving():
		await get_tree().process_frame
		if not is_same(run.data, expedition):
			return
	map_traveling = false
	travel_clock.clear()
	if day_changed:
		_refresh()
	else:
		_update_world_input()
	if result.get("battle", false):
		_show_encounter_intro()
	else:
		_show_arrival()
	if day_changed:
		day_transition_pending = true
		_show_day_transition()

func _show_day_transition() -> void:
	if not day_transition_pending or not view.is_processing_unhandled_input() \
			or combat != null or not run.data.pending_battle.is_empty():
		return
	day_transition_pending = false
	day_transition.show_day(run.data.day, run.data.weather == "rain")
	sound.play("day")
	for indicator_name in ["DayConditions", "CrewStamina"]:
		var indicator := ui.find_child(indicator_name, true, false) as Control
		if indicator == null:
			continue
		var pulse := indicator.create_tween()
		pulse.tween_property(indicator, "modulate", Color(1.26, 1.22, 1.08), 0.18)
		pulse.tween_property(indicator, "modulate", Color.WHITE, 0.46)

func _show_arrival() -> void:
	if not _show_chapter() and not _show_relic_intro(_show_arrival_node):
		_show_arrival_node()

func _show_arrival_node() -> void:
	if not run.data.has("pending_arrival"):
		_show_npc_encounter(selected_id)
		return
	var arrival: Dictionary = run.data.pending_arrival
	run.data.erase("pending_arrival")
	run.save_game()
	if selected_id == arrival.actor and run.actor(selected_id).position == arrival.cell:
		_node_dialog()

func _run_action(result: Dictionary) -> void:
	toast_text = "已完成。" if result.ok else str(result.get("message", "无法执行。"))
	if result.ok and run.data.status != "battle":
		var saved = run.save_game()
		if not saved.ok:
			toast_text = "这次操作已完成，游戏没能保存。 " + str(saved.message)
	_refresh()
	if not result.ok and combat == null and run.data.status == "exploring" and modal_layer.get_child_count() == 0:
		_notice(toast_text)

func _modal(title: String, width: float = 650, height: float = 520) -> VBoxContainer:
	day_transition.dismiss()
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
	if not title.is_empty():
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
	ui.process_mode = Node.PROCESS_MODE_DISABLED if map_traveling else Node.PROCESS_MODE_INHERIT
	var can_target = combat != null and combat.outcome.is_empty()
	var can_explore = not view.battle_mode and run.data.status == "exploring"
	view.set_world_input_enabled(not map_traveling and screen_state == Screen.EXPEDITION and view.visible
		and modal_layer.get_child_count() == 0 and (can_target or can_explore))
	if day_transition_pending and can_explore and view.is_processing_unhandled_input():
		# Closing one modal may open another before the map is shown.
		_show_day_transition.call_deferred()

func _notice(message: String, dismiss: Callable = Callable()) -> void:
	var box = _modal("旅途提示", 620, 270)
	_text(box, message, 18)
	_button(box, "知道了", dismiss if dismiss.is_valid() else _close_modal)

func _confirm(title: String, message: String, action: Callable) -> void:
	var box = _modal(title, 700, 480)
	_text(box, message, 17)
	_button(box, "确认", func(): _close_modal(); action.call())
	_button(box, "取消，继续远征", _close_modal)

func _show_character_codex() -> void:
	if character_codex_state.is_empty():
		character_codex_state = {"actor": selected_id, "tab": 0, "filter": 0, "pose": "", "grid": false,
			"move_target": move_target}
	_clear(modal_layer)
	ui.show()
	view.show()
	view.set_process(true)
	move_preview.hide()
	var shade = ColorRect.new()
	shade.color = Color(0.025, 0.07, 0.065, 0.18)
	modal_layer.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var codex = CharacterCodex.new()
	codex.name = "CharacterCodex"
	modal_layer.add_child(codex)
	codex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var screen = get_viewport().get_visible_rect().size
	var beside_crew = 20 + CREW_PANEL_WIDTH + 14
	codex.offset_left = beside_crew if screen.x >= beside_crew + 920 and run.data.status == "exploring" else 20
	codex.offset_top = 120
	codex.offset_right = -20
	codex.offset_bottom = -20
	codex.setup(self, character_codex_state)
	_refresh()

func _close_character_codex() -> void:
	move_target = character_codex_state.get("move_target", "")
	character_codex_state = {}
	_close_modal()
	_refresh()

func _read_character_record(id: String, record: Dictionary) -> void:
	var read_history = {"speaker": record.title, "pages": {}}
	_show_story(record.title, "角色图鉴", record.body, _story_scene_at(run.actor(id).position),
		[_story_portrait(id)], [], func(_option: String): _show_character_codex(),
		{"返回角色图鉴": _show_character_codex}, Color.WHITE, 0, read_history)

func _inventory_dialog(id: String, current_tab: int = 0, selected_item: String = "", feedback: String = "") -> void:
	var box = _modal("", 900, 550)
	var panel: PanelContainer = box.get_parent()
	var frame := _style(Color("20352e"), Color("5a6855"), 10)
	frame.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", frame)
	var header := HBoxContainer.new()
	box.add_child(header)
	_text(header, run.actor(id).name + " · 背包", 27, gold).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if character_codex_state.is_empty():
		_button(header, "关闭", _close_modal).flat = true
	else:
		_button(header, "返回角色图鉴", _show_character_codex).flat = true
	box.add_child(HSeparator.new())

	var tabs := TabContainer.new()
	tabs.name = "InventoryTabs"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var tab_body := _style(Color.TRANSPARENT, Color.TRANSPARENT, 0)
	tab_body.set_content_margin_all(0)
	tab_body.content_margin_top = 16
	tabs.add_theme_stylebox_override("panel", tab_body)
	var tab_style := _style(Color.TRANSPARENT, Color.TRANSPARENT, 0)
	tabs.add_theme_stylebox_override("tab_unselected", tab_style)
	tabs.add_theme_stylebox_override("tab_hovered", tab_style)
	var active_tab := _style(Color.TRANSPARENT, gold, 0)
	active_tab.set_border_width_all(0)
	active_tab.border_width_bottom = 2
	tabs.add_theme_stylebox_override("tab_selected", active_tab)
	tabs.add_theme_color_override("font_selected_color", gold)
	tabs.add_theme_color_override("font_unselected_color", ink)
	box.add_child(tabs)
	var width := panel.size.x - frame.content_margin_left - frame.content_margin_right
	for title in ["消耗品", "装备", "遗器"]:
		var page := InventoryPage.new()
		page.name = title
		tabs.add_child(page)
		page.setup(width, gold)
	tabs.current_tab = current_tab
	_inventory_consumables(tabs.get_child(0), id, selected_item if current_tab == 0 else "")
	_inventory_gear(tabs.get_child(1), id, selected_item if current_tab == 1 else "", feedback if current_tab == 1 else "")
	_inventory_relics(tabs.get_child(2), id, selected_item if current_tab == 2 else "", feedback if current_tab == 2 else "")

func _inventory_heading(content: VBoxContainer, title: String, icon_key: String) -> void:
	var texture := InventoryPage.icon(icon_key)
	if texture != null:
		var icon := TextureRect.new()
		icon.texture = texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		icon.custom_minimum_size = Vector2(110, 110)
		content.add_child(icon)
	_text(content, title, 24, gold)

func _inventory_consumables(page: InventoryPage, id: String, selection: String) -> void:
	var a = run.actor(id)
	var entries: Array[Dictionary] = []
	for item in a.inventory:
		if a.inventory[item] > 0:
			entries.append({"id": item, "title": Catalog.item_name(item), "icon": item, "count": a.inventory[item]})
	page.item_selected.connect(func(item: String):
		var content := page.details
		if item.is_empty():
			_text(content, "暂无物品。" if entries.is_empty() else "选择一个物品查看详情。", 16, muted)
			return
		var definition: Dictionary = Catalog.ITEMS.get(item, {})
		_inventory_heading(content, Catalog.item_name(item), item)
		var purpose := str(definition.get("description", "暂无用途说明。"))
		if item == "salve" and run.has_relic("herbal_case"):
			purpose += " 青枝药匣使恢复量提高 25%。"
		_text(content, purpose, 16)
		var actions := HFlowContainer.new()
		actions.add_theme_constant_override("h_separation", 8)
		content.add_child(actions)
		if definition.has("hp") or definition.has("mp"):
			var use := _button(actions, "使用", _item_dialog.bind(id, item), a.hp <= 0 or run.data.status != "exploring")
			use.custom_minimum_size.x = 144
			use.add_theme_stylebox_override("normal", _style(Color("50563c"), gold.darkened(0.38), 6))
		if run.same_cell(a.position).size() > 1:
			_button(actions, "交接", _transfer_dialog.bind(id, item)))
	page.set_items(entries, selection)

func _inventory_gear(page: InventoryPage, id: String, selection: String, feedback: String) -> void:
	var filter := OptionButton.new()
	for label in ["所有槽位", "武器", "护甲", "饰品"]:
		filter.add_item(label)
	filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.filters.add_child(filter)
	var set_filter := OptionButton.new()
	set_filter.add_item("所有套装")
	for set_id in Gear.SETS:
		set_filter.add_item(Gear.SETS[set_id].name)
	set_filter.fit_to_longest_item = false
	set_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.filters.add_child(set_filter)
	page.filters.show()
	var instances: Array = run.gear_owned("actor", id)
	instances.sort_custom(func(a, b):
		var left: int = Gear.QUALITIES.find(run.data.gear_instances[a].quality)
		var right: int = Gear.QUALITIES.find(run.data.gear_instances[b].quality)
		return int(a) < int(b) if left == right else left > right)
	var entries: Array[Dictionary] = []
	page.item_selected.connect(func(uid: String):
		if uid.is_empty():
			_text(page.details, "暂无符合条件的装备。" if entries.is_empty() else "选择一件装备查看详情。", 16, muted)
			return
		_gear_detail(page.details, id, uid, feedback if uid == selection else ""))
	var refresh_grid := func(selected: String):
		entries.clear()
		for uid in instances:
			var item = run.data.gear_instances[uid]
			var definition = Gear.DATA[item.definition_id]
			if filter.selected > 0 and definition.slot != Gear.SLOTS[filter.selected - 1]:
				continue
			if set_filter.selected > 0 and definition.set_id != Gear.SETS.keys()[set_filter.selected - 1]:
				continue
			var equipped: bool = uid in run.actor(id).equipment.values()
			entries.append({"id": uid, "title": Gear.label(item), "icon": definition.slot,
				"caption": definition.name, "badge": "已装备" if equipped else ""})
		page.set_items(entries, selected)
	filter.item_selected.connect(func(_index: int): refresh_grid.call(page.selected_id))
	set_filter.item_selected.connect(func(_index: int): refresh_grid.call(page.selected_id))
	refresh_grid.call(selection)

func _gear_detail(content: VBoxContainer, id: String, uid: String, feedback: String) -> void:
	var item = run.data.gear_instances[uid]
	var definition = Gear.DATA[item.definition_id]
	var a = run.actor(id)
	_inventory_heading(content, Gear.label(item), definition.slot)
	if not feedback.is_empty():
		_text(content, feedback, 16, gold)
	var current_uid: String = a.equipment[definition.slot]
	var stat_labels = {"attack": "攻击", "defense": "防御", "speed": "速度"}
	for stat in definition.stats:
		var current_value = 0 if current_uid.is_empty() else Gear.bonus(run.data.gear_instances[current_uid], stat)
		_text(content, "%s +%d · 当前同槽 +%d" % [stat_labels[stat], Gear.bonus(item, stat), current_value], 17, gold)
	_text(content, definition.effect, 16)
	if not definition.set_id.is_empty():
		var pieces: int = run.set_count(id, definition.set_id)
		var suite = Gear.SETS[definition.set_id]
		_text(content, "%s · %d / 3" % [suite.name, pieces], 18, gold)
		if not suite.two.is_empty():
			_text(content, ("已激活 · " if pieces >= 2 else "未激活 · ") + suite.two, 16)
		if not suite.three.is_empty():
			_text(content, ("已激活 · " if pieces >= 3 else "未激活 · ") + suite.three, 16)
	_button(content, "阅读装备故事", func():
		_show_story(definition.name, "器物故事", definition.story, _story_scene_at(a.position),
			[], [], func(_option: String): _inventory_dialog(id, 1, uid), {}))
	var equip_action = _item_command(run.equip.bind(id, uid))
	_button(content, "卸下" if current_uid == uid else "装备", func():
		var result = equip_action.call()
		_run_action(result)
		_inventory_dialog(id, 1, uid, result.get("message", "")))
	for other in run.same_cell(a.position):
		if other == id or current_uid == uid:
			continue
		var transfer_action = _item_command(run.gear_transfer.bind(id, other, uid))
		_button(content, "交给 " + run.actor(other).name, func():
			var result = transfer_action.call()
			_run_action(result)
			_inventory_dialog(id, 1, uid, result.get("message", "")))
	_text(content, "持有 %d 灯铢" % run.data.lamp_coins, 16, gold)
	for voucher in [""] + _vouchers("enhancement_fee"):
		var quote = run.enhancement_quote(id, uid, voucher)
		if not quote.ok:
			if voucher.is_empty():
				_text(content, quote.message, 15, muted)
			continue
		var stat: String = definition.stats.keys()[0]
		if voucher.is_empty():
			_text(content, "强化后%s +%d" % [stat_labels[stat], Gear.bonus(item, stat, int(item.enhance_level) + 1)], 15, muted)
		var enhance_action = _item_command(run.enhance.bind(id, uid, voucher))
		var enhance := _button(content, "强化至 +%d · %d 灯铢%s" % [
			int(item.enhance_level) + 1, quote.price,
			" · " + Relics.DATA[voucher].name if not voucher.is_empty() else ""], func():
			var result = enhance_action.call()
			_run_action(result)
			_inventory_dialog(id, 1, uid, result.get("message", "")), run.data.lamp_coins < quote.price)
		enhance.tooltip_text = enhance.text
		enhance.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

func _inventory_relics(page: InventoryPage, id: String, selection: String, feedback: String) -> void:
	var entries: Array[Dictionary] = []
	for type in ["P", "C", "L"]:
		for relic in Relics.DATA:
			var entry = Relics.DATA[relic]
			if entry.type != type or not run.data.relic_seen.has(relic):
				continue
			var count: int = int(run.data.relic_inventory.get(relic, 0))
			var badge := "共鸣中" if run.has_relic(relic) else ("已发现" if count == 0 else "")
			entries.append({"id": relic, "title": entry.name, "icon": "relic",
				"caption": entry.name, "count": count, "badge": badge})
	page.item_selected.connect(func(relic: String):
		if relic.is_empty():
			_text(page.details, "本次远征尚未获得遗器。" if entries.is_empty() else "选择一件遗器查看详情。", 16, muted)
			return
		_relic_detail(page.details, id, relic, feedback if relic == selection else ""))
	page.set_items(entries, selection)

func _relic_detail(content: VBoxContainer, id: String, relic: String, feedback: String) -> void:
	var entry = Relics.DATA[relic]
	var a = run.actor(id)
	_inventory_heading(content, entry.name, "relic")
	if not feedback.is_empty():
		_text(content, feedback, 16, gold)
	var kind: String = {"P": "持续", "C": "消耗", "L": "永久"}[entry.type]
	_text(content, kind + (" · 共鸣中" if relic in run.data.relic_attunement else ""), 15, muted)
	if entry.type == "P":
		_text(content, "全队共鸣 · %d / 6" % run.data.relic_attunement.size(), 15, muted)
	_text(content, entry.effect, 17)
	_text(content, "主要来源 · " + _relic_source(entry.source), 15, muted)
	if run.has_relic(relic):
		_relic_information(content, id, relic)
	_button(content, "阅读遗器故事", func():
		_show_story(entry.name, "器物故事", entry.story, _story_scene_at(a.position),
			[], [], func(_option: String): _inventory_dialog(id, 2, relic), {}))
	var count: int = int(run.data.relic_inventory.get(relic, 0))
	if count > 0 and Relics.is_active(relic):
		if entry.type == "P":
			var execute = _item_command(run.attune_relic.bind(id, relic))
			_button(content, "解除共鸣" if run.has_relic(relic) else "共鸣", func():
				var result = execute.call()
				_run_action(result)
				_inventory_dialog(id, 2, relic, result.get("message", "")))
		elif entry.hook == "transaction_use":
			_text(content, "在交易或强化时选择使用此凭券。", 16, muted)
		else:
			_relic_use_buttons(content, id, relic)

func _relic_information(content: VBoxContainer, actor_id: String, relic: String) -> void:
	var a = run.actor(actor_id)
	var origin: String = a.position
	var entry = Relics.DATA[relic]
	match relic:
		"survey_tally":
			var visits: int = run.data.visited.size()
			var upcoming: Array = [20, 60, 100].filter(func(value): return value > visits)
			_text(content, "已经走过 %d 格 · %s" % [visits, "里程碑已全部达成" if upcoming.is_empty() else "下一个 %d 格" % upcoming[0]], 16, gold)
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
				_text(content, "附近还没发现精英战斗地点。", 16, muted)
			else:
				var cell: String = candidates[0]
				var offset = Hex.coord(cell) - Hex.coord(origin)
				_text(content, "最近精英方向 %+d,%+d · 相距 %d 格" % [offset.x, offset.y, Hex.distance(Hex.coord(origin), Hex.coord(cell))], 16, gold)
		"terrain_caliper":
			for cell in run.data.explored:
				if cell != origin and Hex.is_land(run.data.tiles, cell) and Hex.distance(Hex.coord(origin), Hex.coord(cell)) <= entry.params.radius:
					var terrain: String = run.data.tiles[cell].terrain
					_text(content, "%s · %s" % [cell, Catalog.terrain_name(terrain)], 15, muted)
		"cloud_almanac":
			var forecast: Array = run.weather_forecast(2)
			_text(content, "明天预计%s · 后天预计%s" % ["有雨" if forecast[0] == "rain" else "无雨", "有雨" if forecast[1] == "rain" else "无雨"], 16, gold)
		"honest_ledger":
			var node = run.node_at(origin)
			if node.get("kind") == "choice":
				_text(content, "当地委托 · " + ("已领取" if not node.result.is_empty() else "可处理"), 16, gold)
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
			_inventory_dialog(id, 2, relic, result.get("message", "")))

func _transfer_dialog(owner: String, item: String) -> void:
	var box = _modal("同地交接 · " + Catalog.item_name(item), 650, 540)
	_text(box, "每次交接一件。已装备的物品需先卸下。", 17, muted)
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
	_text(box, "战斗中使用道具不占正常行动。", 16, muted)
	if from_backpack:
		_text(box, "要把背包里的「%s」给谁用？只能选在场的人。" % Catalog.item_name(item_id), 16, gold)
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

func _open_current_encounter(show_intro: bool = true) -> void:
	var cell: String = run.actor(selected_id).position
	run.data.pending_battle = {"position": cell, "ambush": false, "origin": cell, "npc": ""}
	run.save_game()
	if show_intro:
		_show_encounter_intro()
	else:
		_formation_dialog()

func _show_encounter_intro() -> void:
	var encounter: Dictionary = run.data.pending_battle
	if not encounter.npc.is_empty():
		_formation_dialog()
		return
	var cell: String = encounter.position
	var tile: Dictionary = run.data.tiles[cell]
	var node = run.node_at(cell)
	var title = _node_title(cell)
	var body: String
	var portraits: Array = [_story_portrait(selected_id, "serious")]
	if tile.enemies.has("war_god"):
		title += " · 战鼓"
		body = "鼓声从营里传来。你在路上听过同样的鼓点，每响一下，那些想逃走的士兵就握紧了手里的武器。现在鼓就在眼前。卡德兰挡在通往鼓台的路上，伸手取下了自己的兵器。"
		portraits.append(_story_portrait("war_god", "serious"))
	else:
		var event = Nodes.story(node)
		if node.get("kind") in ["battle", "elite"] and not event.is_empty():
			title += " · " + str(event.title)
			body = str(event.intro)
		else:
			var enemies = "、".join(tile.enemies.map(func(id): return Catalog.ENEMIES[id].name))
			body = "%s挡住了去路。你停下脚步，握紧了武器。" % enemies
		if encounter.ambush:
			body += "\n\n敌人从遮蔽物后抢先扑了出来。"
	_show_story(title, "旁白", body, _story_scene_at(cell), portraits,
		[_node_option("formation", "选择出战阵容")], func(_option: String): _formation_dialog(), {}, _node_tint())

func _formation_dialog() -> void:
	var encounter = run.data.pending_battle
	var box = _modal("选择出战阵容 · 最多四人", 700, 620)
	_text(box, "最多四名队员同时出战，其他能行动的队员可以做候补。", 17, muted)
	var chosen: Array = []
	var lineup = _scroll_content(box)
	for id in run.same_cell(encounter.position, true):
		var toggle = CheckBox.new()
		toggle.text = "%s · HP %d/%d" % [run.actor(id).name, run.actor(id).hp, run.actor(id).hp_max]
		if chosen.size() < 4:
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
	_text(box, "已经遇到敌人了，开打后可以选择撤退。", 14, muted)

func _battle_ui(screen: Vector2) -> void:
	view.refresh_battle(run, combat)
	view.set_battle_target(selected_target)
	var battle_bottom = screen.y - 20
	var side_height = battle_bottom - 120
	var left_outer = _panel(ui, Rect2(20, 120, CREW_PANEL_WIDTH, side_height))
	_text(left_outer, "出战角色", 24, gold)
	var left = _scroll_content(left_outer)
	left.get_parent().horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_theme_constant_override("separation", 6)
	var acting_id = view.presentation_actor(combat.current)
	for id in combat.active:
		_battle_member(left, id, id == acting_id)
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
	auto.tooltip_text = "开启后，队员会自己决定怎么打。"
	var items = _button(quick_actions, "道具", func(): _item_dialog(combat.current), not is_friendly)
	items.tooltip_text = "使用当前角色背包中的恢复道具。\n可给在场队友使用，不占正常行动。"
	quick_actions.position = Vector2(enemy_panel_x - quick_actions.get_combined_minimum_size().x - 12, 120)

	var commands_x = CREW_PANEL_WIDTH + 40.0
	var center = _panel(ui, Rect2(commands_x, battle_bottom - 155, enemy_panel_x - commands_x - 20.0, 155))
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
		swap.tooltip_text = "让候补换下当前队员，占用这次正常行动。"
	var retreat_hint = "撤退会返回出发地。出过战的队员各损失生命上限的 10%，敌人会恢复。"
	var retreat = _button(commands, "撤退", func(): _confirm("撤退？", retreat_hint, func(): _run_action(combat.retreat()); _finish_battle()), combat.river or combat.madness.has(combat.current))
	retreat.tooltip_text = retreat_hint
	var field = combat.field_view()
	var context = "场地：" + Catalog.terrain_name(field.terrain)
	var field_names = {"frozen": "冰面", "charged": "导电", "wind_barrier": "风障", "root_cover": "根掩"}
	for state in field_names:
		if field.fields.has(state):
			context += " · %s %d 行动" % [field_names[state], field.fields[state]]
	if combat.madness.has(combat.current):
		context += " · 当前角色陷入疯狂，会自行攻击"
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

func _battle_member(parent: VBoxContainer, id: String, acting: bool) -> void:
	var a = run.actor(id)
	var shown_hp = view.display_hp(id, int(a.hp))
	var shown_shield = view.display_shield(id, int(a.shield))
	var status: Array[String] = []
	if acting:
		status.append("行动中")
	if shown_hp <= 0:
		status.append("重伤")
	if combat.madness.has(id):
		status.append("疯狂")
	if shown_hp > 0 and combat.haste_turns.has(id):
		status.append("提速")

	var panel = PanelContainer.new()
	panel.name = "BattleMember_" + id
	var style = _style(Color("29413c"), gold if acting else Color("536456"), 6)
	style.content_margin_left = 5
	style.content_margin_right = 5
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var card = VBoxContainer.new()
	card.add_theme_constant_override("separation", 4)
	panel.add_child(card)
	var content = HBoxContainer.new()
	card.add_child(content)
	var meters = _member_status(content, id, shown_hp)
	meters.add_theme_constant_override("separation", 3)
	_battle_status_row(meters, id, " · ".join(status), shown_shield)
	var skill_name: String = Catalog.SKILLS[a.ultimate].name
	var ultimate = _button(card, "终结技 · " + skill_name, _ultimate.bind(id),
		a.energy < Catalog.ENERGY_MAX or a.hp <= 0 or combat.madness.has(id))
	ultimate.tooltip_text = "%s\n%s\n充能达到 100%% 时可释放，不占正常行动。" % [skill_name, Catalog.skill_description(a.ultimate)]

func _battle_status_row(parent: VBoxContainer, id: String, status: String, shield: int) -> void:
	var row = HBoxContainer.new()
	row.name = "BattleStatus_" + id
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var label = _text(row, status, 11, muted)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Keep the same amount of space when the shield is depleted.
	var slot = Control.new()
	slot.custom_minimum_size = SHIELD_BADGE_SIZE
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(slot)
	if shield <= 0:
		return
	var badge = TextureRect.new()
	badge.name = "ShieldBadge_" + id
	badge.accessibility_name = "护盾 %d" % shield
	badge.texture = SHIELD_ICON
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(badge)
	badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var amount = _text(badge, str(shield), 12, Color.WHITE)
	amount.name = "Amount"
	amount.add_theme_color_override("font_outline_color", Color("231f1b"))
	amount.add_theme_constant_override("outline_size", 2)
	amount.autowrap_mode = TextServer.AUTOWRAP_OFF
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	amount.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	amount.offset_bottom = -3
	var font = amount.get_theme_font("font")
	var font_size = amount.get_theme_font_size("font_size")
	while font_size > 1 and font.get_string_size(amount.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > SHIELD_BADGE_SIZE.x - 7.0:
		font_size -= 1
	amount.add_theme_font_size_override("font_size", font_size)

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
	var status = "已击败" if shown_hp <= 0 else "蓄力中！" if enemy.charged else "等待行动"
	if shown_hp > 0 and enemy.slow > 0:
		status += " · 减速"
	_text(card, "HP %d/%d · %s\n%s" % [shown_hp, enemy.hp_max, status, enemy.role], 14, muted)
	_enemy_hp_bar(card, shown_hp, enemy.hp_max)

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
			toast_text = "等眼前的动作结束，就会放出终结技。"
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
		_button(box, run.actor(id).name + " · HP %d" % run.actor(id).hp, func(): _close_modal(); _run_action(combat.swap(id)); _after_combat_step())
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
		_text(content, ("再次获得遗器 · " if result.get("relic_duplicate", false) else "发现遗器 · ") + Relics.DATA[result.relic].name, 17, gold)
	if result.get("coins", 0) > 0:
		_text(content, "获得 %d 灯铢" % result.coins, 17, gold)
	if result.salve_receiver.is_empty() and result.relic.is_empty() and result.get("coins", 0) <= 0:
		_text(content, "这场没有战利品。", 17, muted)
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
		else:
			_show_arrival())
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
		["留下的人", "你在路边歇脚，一个赶车的人过来问你见没见过他爹。“我爹已经下葬了，可他每天夜里还去找旧路口。那段路早就断了，他走不通，又绕回来。我们请过祭司，也重新葬过他，一点用都没有。”\n\n你想起以前也有许多人找不到路，走过来向你求助。你记得自己伸手牵过他们。你下意识抬了抬手，脚边的石子竟跟着升了起来。你把手放下，石子才落回地上。"],
		["停不下来的战鼓", "一个士兵从军营逃出来，胳膊还在流血。他说，敌人都撤了，军营里的鼓还在敲。一听见那段鼓声，连受伤的人也站起来追了出去。\n\n远处的战鼓又响起来了。“将军说这是卡德兰给的勇气。可我明明想放下刀，手就是不听话。”他说着就拔了刀。你一抬手，刀沉进泥里，他才松开手。\n\n等鼓声停了，士兵也缓过来了。你想起这股力量能同时压住好几把刀。从前听见同样的鼓声时，你就这样拦过一队人。"],
		["桌上那杯酒", "夜里，你梦见自己站在一张长桌旁。桌子对面的人递给你一杯酒。你没喝，先问他为什么还要让两边的人打下去。\n\n“坐下再说。”他挥手叫侍从出去。你刚要开口，让他放过那些被战鼓逼着打仗的人，眼前就闪过一道红光。你抬手去挡，接着听见一声碎响。\n\n你醒过来，手还举在半空。那间屋子你去过，桌子对面的人你也认识，可一时想不起他是谁。"],
		["鼓声从哪里来", "你遇到一个从前线逃出来的鼓手，就问起伤兵听见的那段战鼓。他一听就认出来了。军官曾把他绑在鼓边，对面的兵都丢下武器了，也不准他停。\n\n“山口后面有座大营，那里的鼓自己会响。营里一亮红光，我们这边和敌营的鼓就都跟着响。”他拿树枝在地上画出回营的路。\n\n你拿出地图，照着他画的河湾和山口找到了大营。卡德兰就在那儿。要让那些被逼着打仗的人回家，你得先让那面鼓停下来。"],
	]

func _show_chapter() -> bool:
	var chapter = run.pending_chapter()
	if chapter == 0 or selected_id != "hero" or run.actor("hero").hp <= 0:
		return false
	var page = _chapter_pages()[chapter - 1]
	_show_story(page[0], "旅途见闻", page[1], _story_scene_at(run.actor(selected_id).position), [_story_portrait("hero")], [],
		func(_option: String):
			run.finish_chapter(chapter)
			run.save_game()
			_close_modal()
			_refresh()
			_show_arrival(), {})
	return true

func _final_battle_page(index: int) -> void:
	var pages = [
		["旅人", "这道红光……侍从已经出去了，桌上的酒还没人喝。卡德兰，是你杀了我。"],
		["旁白", "武器落下以后，你就什么也不记得了。现在你又能感觉到冥界，也终于知道自己后来去了哪里。\n\n你的身体在冥界重新长了出来，可你一直没醒。后来，有人为了逃难召唤恶魔，打开了一条通往冥界的路。你也被带了出来。村民就是那时候找到你的。你也是到现在才知道，自己死了还能回来。"],
		["卡德兰", "我把你的身体毁得一块都不剩。葬礼办了一场又一场，没有一个亡魂被接走。你怎么还能站在这里？"],
		["旅人", "我也不知道自己还能回来。这一路，我连名字都想不起。\n\n我是伊文洛，死神。那些死去的人还在等我给他们带路。卡德兰，把你的鼓停下。"],
		["卡德兰", "停下？城里求我守住粮仓，城外求我打破城门。你叫我答应哪边？\n\n我两边都答应。他们打得越久，我就越强。你回来得太晚了。"],
		["旅人", "他们已经丢下武器了，你还让他们追着打。\n\n你想打，就冲我来。别再逼他们拿刀。"],
		["旁白", "你伸出手，用重力把战场上的亡魂托了起来。那个一直挥着断剑的士兵松开了手，顺着你指的路去了冥界。\n\n卡德兰举起武器，你挡在还活着的人身前。"],
		["伊文洛", "都留在我身后，别碰河水。"],
		["旁白", "冥河在卡德兰脚下涌出。你用重力拦住河水，给同行的人留了一块能站稳的地方。一截落进河里的断枪迅速锈烂，沉下去，连碎屑都没有浮起。\n\n冥河能夺走人的力量，也能把东西整个吞掉。就算是你的同伴，掉进去也一样。你得把水挡在岸外。卡德兰已经站不稳了，握着武器的手也开始发抖。"],
	]
	var page = pages[index]
	var river_revealed = index == pages.size() - 1
	var scene = "final_memory" if index < 2 else "finale" if river_revealed else _story_scene_at(run.data.boss)
	var portraits = [] if index < 2 else [_story_portrait("hero", "battle"), _story_portrait("war_god", "surprise" if river_revealed else "anger")]
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
		portraits: Array, options: Array, on_choice: Callable, actions: Dictionary, tint: Color = Color.WHITE,
		page_index: int = 0, history_entry: Dictionary = {}, on_last_page: Callable = Callable()) -> void:
	day_transition.dismiss()
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

	var has_pair = portraits.size() - portraits.count(null) > 1
	var portrait_width = 0.39 if has_pair else 0.43
	var portrait_top = 0.24 if has_pair else 0.20
	for i in portraits.size():
		if portraits[i] == null:
			continue
		var slot = AspectRatioContainer.new()
		slot.ratio = float(portraits[i].get_width()) / portraits[i].get_height()
		slot.alignment_vertical = AspectRatioContainer.ALIGNMENT_END
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(slot)
		var center = 0.23 + 0.30 * i
		# Keep the head in the scene and the cut edge beneath the dialogue shade.
		_story_region(slot, center - portrait_width * 0.5, portrait_top, center + portrait_width * 0.5, 0.88)
		var actor_image = TextureRect.new()
		actor_image.name = "StoryActor%d" % i
		actor_image.texture = portraits[i]
		actor_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		actor_image.stretch_mode = TextureRect.STRETCH_SCALE
		actor_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(actor_image)

	var gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.14, 0.53, 0.74, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.02, 0.03, 0.04, 0.74), Color(0.02, 0.03, 0.04, 0.0),
		Color(0.02, 0.03, 0.04, 0.06), Color(0.02, 0.03, 0.04, 0.73), Color(0.02, 0.03, 0.04, 0.82),
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
	header.mouse_filter = Control.MOUSE_FILTER_PASS
	header.add_theme_constant_override("separation", 10)
	overlay.add_child(header)
	_story_region(header, 0.05, 0.035, 0.95, 0.087)
	var heading = _text(header, "剧情  /  " + title, 17, gold)
	heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	heading.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	var dialogue = Control.new()
	dialogue.name = "Dialogue"
	dialogue.mouse_filter = Control.MOUSE_FILTER_PASS
	overlay.add_child(dialogue)
	_story_region(dialogue, 0.05, 0.74, 0.60, 0.955)
	var speaker_label = _text(dialogue, speaker, 22, gold)
	speaker_label.name = "StorySpeaker"
	_story_region(speaker_label, 0, 0, 1, 0)
	var separator = HSeparator.new()
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue.add_child(separator)
	separator.position.y = speaker_label.get_minimum_size().y + 8
	separator.size.x = dialogue.size.x
	var heading_height = separator.position.y + separator.get_minimum_size().y + 8
	var text_label = _text(dialogue, "", 20, ink)
	text_label.name = "StoryText"
	text_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if speaker == "旁白":
		speaker_label.hide()
		separator.hide()
		# Move the body up while keeping the same space for each page of text.
		text_label.offset_bottom = -heading_height
	else:
		text_label.offset_top = heading_height
	var pages = _story_text_pages(body, text_label)
	text_label.text = pages[page_index].strip_edges()
	if page_index == pages.size() - 1 and on_last_page.is_valid():
		on_last_page.call()
	if history_entry.is_empty():
		history_entry = {"speaker": speaker, "pages": {}}
		story_history.append(history_entry)
	history_entry.pages[page_index] = pages[page_index]
	var counter = _text(header, "第 %d / %d 页" % [page_index + 1, pages.size()], 15, muted)
	counter.name = "PageCounter"
	counter.autowrap_mode = TextServer.AUTOWRAP_OFF
	counter.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	header.add_spacer(false).mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button(header, "历史对话", _show_story_history.bind(overlay))
	for label in actions:
		var button = _button(header, label, actions[label])
		if label in ["结束交谈", "返回角色图鉴"]:
			button.name = "StoryCancel"
	var turn_page = func(index: int):
		_show_story(title, speaker, body, scene, portraits, options, on_choice, actions, tint, index, history_entry, on_last_page)
	var navigation = HBoxContainer.new()
	navigation.name = "StoryNavigation"
	navigation.mouse_filter = Control.MOUSE_FILTER_PASS
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
	choices.add_theme_constant_override("separation", 10)
	option_scroll.add_child(choices)
	var first_enabled: Button
	for option in options:
		if not option.get("enabled", true):
			continue
		var choose = on_choice.bind(str(option.id))
		if option.get("spoken", false):
			choose = _speak_story_reply.bind(title, scene, portraits, str(option.text), choose, tint)
		var button = _button(choices, str(option.text), choose)
		if button.text == "结束交谈" and not actions.has("结束交谈"):
			button.name = "StoryCancel"
		_style_story_reply(button)
		if first_enabled == null:
			first_enabled = button
	if first_enabled != null:
		first_enabled.grab_focus()

func _speak_story_reply(title: String, scene: String, portraits: Array, line: String, choose: Callable, tint: Color) -> void:
	_show_story(title, run.actor(selected_id).name, line, scene, portraits, [],
		func(_option: String): choose.call(), {}, tint)

func _style_story_reply(button: Button) -> void:
	button.custom_minimum_size.y = 60
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_stylebox_override("normal", _story_reply_box(Color("171a18dc"), Color("8c7e669e")))
	button.add_theme_stylebox_override("hover", _story_reply_box(Color("38342bdf"), Color("b7a584")))
	button.add_theme_stylebox_override("pressed", _story_reply_box(Color("4d4232ef"), Color("dec38e")))
	button.add_theme_stylebox_override("focus", _story_reply_box(Color("74644d7c"), Color("c6b391")))
	var marker = ColorRect.new()
	marker.color = Color("d9a45c")
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(marker)
	marker.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	marker.offset_left = 5
	marker.offset_right = 9
	marker.offset_top = 8
	marker.offset_bottom = -8
	marker.hide()
	button.focus_entered.connect(marker.show)
	button.focus_exited.connect(marker.hide)

func _story_reply_box(background: Color, border: Color) -> StyleBoxFlat:
	var style = _style(background, border, 2)
	style.content_margin_left = 21
	style.content_margin_right = 18
	return style

func _show_story_history(story: Control) -> void:
	var previous_focus = get_viewport().gui_get_focus_owner()
	story.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	var story_controls = [story.get_node("Dialogue"), story.get_node("StoryNavigation")]
	var choices = story.get_node_or_null("StoryChoices")
	if choices != null:
		story_controls.append(choices)
	for control in story_controls:
		control.hide()
	var backdrop = ColorRect.new()
	backdrop.name = "StoryHistory"
	backdrop.color = Color(0, 0, 0, 0.20)
	backdrop.mouse_force_pass_scroll_events = false
	modal_layer.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel = PanelContainer.new()
	panel.name = "HistoryPanel"
	panel.add_theme_stylebox_override("panel", _style(Color("353638de"), Color("898b90"), 12))
	backdrop.add_child(panel)
	_story_region(panel, 0.18, 0.12, 0.82, 0.88)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var header = HBoxContainer.new()
	box.add_child(header)
	_text(header, "历史对话", 25, ink)
	var close = _button(header, "关闭", func():
		modal_layer.remove_child(backdrop)
		backdrop.queue_free()
		story.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
		for control in story_controls:
			control.show()
		if is_instance_valid(previous_focus):
			previous_focus.grab_focus())
	close.name = "StoryCancel"
	box.add_child(HSeparator.new())

	var content = _scroll_content(box)
	var scroll: ScrollContainer = content.get_parent()
	scroll.name = "HistoryScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	for entry in story_history:
		var page_numbers = entry.pages.keys()
		page_numbers.sort()
		var text = ""
		for index in page_numbers:
			text += entry.pages[index]
		if not text.strip_edges().is_empty():
			_text(content, entry.speaker, 15, gold)
			_text(content, text.strip_edges(), 17)
			content.add_child(HSeparator.new())
	var bar = scroll.get_v_scroll_bar()
	bar.changed.connect(func(): scroll.scroll_vertical = int(bar.max_value), CONNECT_ONE_SHOT)
	close.grab_focus()

func _story_texture(scene: String) -> Texture2D:
	var path = "res://assets/story/" + scene
	if scene.get_extension().is_empty():
		path += ".png"
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

func _render_dialogue(response: String = "", record_past: bool = false) -> void:
	var was_met: bool = run.data.story.get(dialogue_subject, {}).get("met", false)
	var d = narrative.dialogue(selected_id, dialogue_subject)
	if not d.ok:
		_notice(d.message)
		return
	var person = run.actor(dialogue_subject)
	var pose = "grief" if person.hp <= 0 else str(d.pose)
	var speaker: String = d.speaker if response.is_empty() else person.name
	var text: String = d.text if response.is_empty() else response
	var portraits = [_story_portrait(selected_id), _story_portrait(dialogue_subject, pose)]
	var scene = _story_scene_at(run.actor(selected_id).position)
	if not response.is_empty() and not record_past and not run.relic_intro().is_empty():
		_show_story(d.title, speaker, text, scene, portraits, [],
			func(_option: String): _show_relic_intro(_render_dialogue), {"结束交谈": _show_relic_intro})
	else:
		var on_read = Callable()
		if record_past:
			on_read = _record_character_dialogue.bind(dialogue_subject, "codex_past_read", true)
		elif response.is_empty() and not person.joined and not run.data.story[dialogue_subject].has("codex_first_meeting"):
			on_read = _record_character_dialogue.bind(dialogue_subject, "codex_first_meeting", text)
		_show_story(d.title, speaker, text, scene, portraits, d.options, _story_choice,
			{"结束交谈": _close_modal}, Color.WHITE, 0, {}, on_read)
	if not was_met:
		run.save_game()

func _record_character_dialogue(id: String, key: String, value: Variant) -> void:
	var record: Dictionary = run.data.story[id]
	if not record.has(key):
		record[key] = value
		run.save_game()

func _personal_quest() -> void:
	var quest = narrative.personal_quest(selected_id, dialogue_subject)
	if not quest.ok:
		_notice(quest.message)
		return
	var person = run.actor(dialogue_subject)
	var portraits = [_story_portrait(selected_id), _story_portrait(dialogue_subject, quest.get("pose", "serious"))]
	var scene = _story_scene_at(person.position)
	var actions = {"结束交谈": _close_modal} if quest.options.size() == 1 else {"再想一想": _render_dialogue}
	_show_story(quest.title, person.name, quest.text, scene, portraits, quest.options,
		_story_choice, actions)

func _story_choice(option_id: String) -> void:
	if option_id == "duel":
		var person = run.actor(dialogue_subject)
		var scene = _story_scene_at(person.position)
		_show_story(person.name, person.name, "真要交手？双方都可能受伤。", scene, [_story_portrait(dialogue_subject, "battle")],
			[_node_option("start_duel", "我想清楚了，来吧。", true), _node_option("back", "我收回刚才的话，今天先不打。", true)],
			func(choice: String):
				if choice == "start_duel":
					_story_choice(choice)
				else:
					_render_dialogue(), {"结束交谈": _close_modal})
		return
	var result = narrative.choose(selected_id, dialogue_subject, "duel" if option_id == "start_duel" else option_id)
	if not result.ok:
		_notice(result.message, _render_dialogue)
		return
	if option_id in ["join", "start_duel", "personal_a", "personal_b"]:
		run.save_game()
	var response: String = result.get("response", "")
	if response.is_empty() and _show_relic_intro(_render_dialogue):
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
	else:
		_refresh()
		_render_dialogue(response, option_id == "past")

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

func _summary(screen: Vector2) -> void:
	var box = _panel(ui, Rect2(300, 135, screen.x - 600, screen.y - 300))
	_text(box, "战争结束" if run.data.status == "won" else "远征终止", 36, gold)
	_text(box, "第 %d 天 · 到访 %d 格 · 战斗 %d 场" % [run.data.day, run.data.visited.size(), run.data.battles], 18)
	if run.data.status == "failed":
		_text(box, run.data.flags.get("failure_reason", "远征失败。"), 20, muted)
	else:
		_text(box, narrative.main_ending().title, 25, gold)
	var met_count = Catalog.COMPANIONS.keys().filter(func(id): return run.data.story[id].met).size()
	_text(box, "结局里还记下了路上遇到的 %d 个人后来怎么样了。" % met_count, 18, muted)
	_button(box, "查看结局剧情", _ending_story)
	_button(box, "角色", _show_character_codex)
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
		_confirm("返回菜单？", "进度会留在开战前。下次继续远征时，会从头打这一场。", func():
			combat = null
			view.end_battle()
			_show_opening(Screen.MENU))
	else:
		run.save_game()
		_show_opening(Screen.MENU)

func _guide() -> void:
	_notice("点相邻格预览，再点一次确认。伙伴跟随旅人一起移动，每走五格自动进入第二天。\n\n点「行动」可以查看脚下的地点。疗伤和回魔需要消耗补给，灯铢由全队共享。\n\n最多四人同时出战。换上候补会用掉这次正常行动，终结技充能满了就能放。从沿途的故事和遭遇里找线索，找到并击败战神。")

func _settings_dialog() -> void:
	var box = _modal("设置与操作", 650, 430)
	if screen_state == Screen.EXPEDITION:
		_text(box, "地图种子 %s" % run.data.seed, 15, muted)
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
