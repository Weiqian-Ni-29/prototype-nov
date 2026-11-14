extends Node
const Run = preload("res://scripts/domain/expedition.gd")
const Catalog = preload("res://scripts/domain/catalog.gd")
const Hex = preload("res://scripts/domain/hex_map.gd")
const Chess = preload("res://scripts/domain/chess_battle.gd")
const Cards = preload("res://scripts/domain/card_catalog.gd")
const CardUI = preload("res://scripts/presentation/card_ui.gd")
const ChessView = preload("res://scripts/presentation/chess_battle_view.gd")
const DeckEditor = preload("res://scripts/presentation/card_deck_editor.gd")
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
const RewardItems = preload("res://scripts/presentation/reward_items.gd")
const ShopView = preload("res://scripts/presentation/shop_view.gd")
const DayTransition = preload("res://scripts/presentation/day_transition.gd")
const FontAsset = preload("res://assets/fonts/NotoSansSC.ttf")
const Sound = preload("res://scripts/presentation/sound.gd")
enum Screen { MENU, OPENING_STORY, EXPEDITION }
const OBJECTIVE_ICON = preload("res://assets/ui/expedition-objective.svg")
const LAMP_COIN_ICON = preload("res://assets/ui/lamp-coin.svg")
const STORY_HISTORY_ICON = preload("res://assets/ui/story-history.svg")
const STORY_MAIN_MENU_ICON = preload("res://assets/ui/story-main-menu.svg")
const STORY_SKIP_ICON = preload("res://assets/ui/story-skip.svg")
const CREW_PANEL_WIDTH = 230
const STORY_TERRAIN = {
	"plains": "road", "forest": "woodland", "mountain": "highland", "ruins": "ruins",
	"desert": "drylands", "swamp": "wetlands",
}
var run = Run.new()
var view: Node3D
var ui: Control
var modal_layer: Control
var combat: RefCounted
var chess_view: Control
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
	var world_visible = in_expedition and combat == null and not modal_layer.has_node("StoryScreen")
	view.visible = world_visible
	view.set_process(world_visible)
	_update_world_input()
	move_preview.hide()
	if screen_state == Screen.MENU:
		_menu(screen)
		return
	if screen_state == Screen.OPENING_STORY:
		return
	if combat != null:
		_show_chess_view()
		return
	view.refresh(run, selected_id, selected_cell)
	_header(screen)
	if run.data.status in ["won", "failed"]:
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
		{"返回主菜单": _cancel_opening}, Color.WHITE, 0, {}, Callable(), _village_page.bind(terrain, 0))

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
		{"返回主菜单": _cancel_opening}, Color.WHITE, 0, {}, Callable(), _start_new)

func _seed_value() -> int:
	if chosen_seed.is_empty():
		return 20261104
	return int(chosen_seed) if chosen_seed.is_valid_int() else hash(chosen_seed)

func _start_new() -> void:
	day_transition_pending = false
	day_transition.dismiss()
	character_codex_state = {}
	_close_modal()
	var from_story: bool = screen_state == Screen.OPENING_STORY
	if not from_story:
		story_history.clear()
	var value = opening_seed if from_story else _seed_value()
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
	if from_story:
		run.data.pending_story_rewards = {"source": _node_title(selected_cell), "kind": "starter_deck", "items": []}
	run.save_game()
	_refresh()
	if from_story:
		_show_pending_story_rewards()

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
	elif run.data.has("pending_story_rewards"):
		_show_pending_story_rewards()
	elif run.data.has("pending_victory"):
		_shop_dialog()
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
	var exploration: int = run.exploration_percent()
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
		"平定沿途的战斗遭遇",
		"查清谁在延长战争",
		"找到战神的驻地",
		"击败战神卡德兰",
	][int(run.data.chapter)]


func _crew_panel() -> void:
	var box = _panel(ui, Rect2(20, 120, CREW_PANEL_WIDTH, 56))
	box.get_parent().name = "ExpeditionControls"
	var heading := HBoxContainer.new()
	box.add_child(heading)
	var title := _text(heading, "远征", 24, gold)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_button(heading, "展开" if crew_collapsed else "收起", func():
		crew_collapsed = not crew_collapsed
		_refresh())
	if crew_collapsed:
		return
	_text(box, "点相邻格预览 · 再点确认", 13, muted)
	_crew_stamina(box)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	box.add_child(actions)
	var codex_button := _button(actions, "角色", _show_character_codex)
	if not character_codex_state.is_empty():
		codex_button.add_theme_stylebox_override("normal", _style(Color("34483a"), gold, 6))
		codex_button.add_theme_color_override("font_color", gold)
	_button(actions, "卡组", _deck_dialog if run.data.pending_battle.is_empty() else _show_encounter_intro)
	_button(actions, "背包", _inventory_dialog.bind(selected_id))
	for button in actions.get_children():
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

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
	var caption := _text(row, "精力", 13, muted)
	caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	caption.size_flags_horizontal = Control.SIZE_SHRINK_END
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func _node_title(cell: String) -> String:
	return run.location_name(cell)

func _node_interaction(cell: String) -> String:
	var tile: Dictionary = run.data.tiles[cell]
	if not tile.enemies.is_empty():
		return ""
	var node := run.node_at(cell)
	if tile.site.is_empty() or (tile.site == "boss" and not run.boss_known()):
		if node.get("result", "").is_empty():
			match node.get("kind"):
				"supply":
					return "collect"
				"cache":
					return "search"
	if tile.quantity > 0 and (node.get("kind") != "supply" or not tile.site.is_empty()):
		return "gather"
	if node.get("kind") != "cache" and run.relic_sites.has(cell) and not run.data.relic_claims.has("site:" + cell):
		return "investigate"
	return ""

func _enter_node(cell: String, interaction: String) -> void:
	var result: Dictionary
	match interaction:
		"collect", "search":
			result = run.use_node(selected_id, interaction)
		"gather":
			result = run.collect(selected_id)
		"investigate":
			result = run.investigate_relic(selected_id)
			var relic: String = result.get("relic", "")
			if not relic.is_empty():
				result.items = [{"kind": "relic", "id": relic, "count": 1}]
	var has_items: bool = result.ok and _queue_story_rewards(_node_title(cell), result.get("items", []))
	_run_action(result)
	if has_items:
		_show_pending_story_rewards()
	elif result.ok:
		_notice(result.message)

func _site_impression() -> void:
	var cell: String = run.actor(selected_id).position
	var terrain: String = run.data.tiles[cell].terrain
	_show_story(_node_title(cell), "村民", "你回来啦。来喝口水吧。路上遇到难事的话，也可以坐下慢慢说。",
		STORY_TERRAIN[terrain], [], [_node_option("leave", "谢谢，我得继续赶路了。", true)], func(_choice: String): _close_modal(),
		{"结束交谈": _close_modal}, _node_tint())

func _node_tint() -> Color:
	if run.data.weather == "rain":
		return Color(0.78, 0.88, 1.0)
	return Color.WHITE

func _node_option(id: String, label: String, spoken: bool = false) -> Dictionary:
	return {"id": id, "text": label, "spoken": spoken}

func _queue_story_rewards(source: String, items: Array) -> bool:
	if items.is_empty():
		return false
	run.data.pending_story_rewards = {"source": source, "items": items}
	return true

func _show_pending_story_rewards() -> void:
	var receipt: Dictionary = run.data.pending_story_rewards
	# Earlier opening receipts used the village name and listed its supplies.
	var starter_deck: bool = receipt.get("kind") == "starter_deck" or receipt.source == run.location_name(run.data.start)
	var box = _modal("", 780, 590)
	box.get_parent().name = "StoryRewards"
	_text(box, "获得初始卡组" if starter_deck else "获得物品", 29, gold).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text(box, "来自「%s」" % receipt.source, 16, muted).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(HSeparator.new())
	var rewards := RewardItems.new()
	box.add_child(rewards)
	rewards.setup(_starter_deck_entries() if starter_deck else _reward_entries(receipt.items),
		"卡牌详情" if starter_deck else "物品详情")
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(footer)
	if starter_deck:
		_button(footer, "查看卡组", _deck_dialog.bind(false, _show_pending_story_rewards)).custom_minimum_size = Vector2(144, 44)
	var save_error := _text(box, "", 15, gold)
	save_error.hide()
	var confirm := _button(footer, "返回商店  →" if run.data.has("pending_victory") else "返回地图  →", func():
		var introductions: Array = run.data.relic_intros
		_remove_reward_intros(receipt.items)
		run.data.erase("pending_story_rewards")
		var saved = run.save_game()
		if not saved.ok:
			run.data.pending_story_rewards = receipt
			run.data.relic_intros = introductions
			save_error.text = saved.message
			save_error.show()
			return
		_close_modal()
		_refresh()
		if run.data.has("pending_victory"):
			_shop_dialog()
		else:
			_show_day_transition())
	confirm.custom_minimum_size = Vector2(144, 44)
	confirm.add_theme_stylebox_override("normal", _style(Color("dbc18a"), gold, 6))
	confirm.add_theme_stylebox_override("hover", _style(Color("f0d69d"), gold, 6))
	confirm.add_theme_color_override("font_color", Color("1a302a"))
	confirm.add_theme_color_override("font_hover_color", Color("1a302a"))
	confirm.add_theme_color_override("font_focus_color", Color("1a302a"))
	confirm.grab_focus()

func _starter_deck_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var counts := {}
	for id in run.starter_card_deck():
		counts[id] = counts.get(id, 0) + 1
	for id in counts:
		var card := Cards.owned_definition(id, run.data.actors, run.data)
		entries.append({"title": card.name, "category": Cards.KINDS[card.kind] + "牌",
			"count": counts[id], "effect": card.trait, "story": card.get("story", ""),
			"icon": card.get("icon", ""), "portrait": card.get("portrait", ""), "level": card.get("level", 0)})
	return entries

func _remove_reward_intros(items: Array) -> void:
	var relic_ids := items.filter(func(item): return item.kind == "relic").map(func(item): return item.id)
	run.data.relic_intros = run.data.relic_intros.filter(func(intro): return intro.id not in relic_ids)

func _reward_entries(items: Array) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var stat_names := {"attack": "攻击", "defense": "防御", "speed": "速度"}
	for item in items:
		var id: String = item.id
		var entry := {"id": id, "kind": item.kind, "icon": id, "count": int(item.count), "story": ""}
		match item.kind:
			"item":
				var definition: Dictionary = Catalog.ITEMS[id]
				entry.merge({"title": definition.name, "category": "消耗品", "effect": definition.description})
				entry.story = definition.get("story", "")
			"relic":
				var definition: Dictionary = Relics.DATA[id]
				entry.merge({"title": definition.name, "category": item.get("status", "遗器"), "effect": Relics.current_effect(id)})
				entry.story = definition.story
			"gear":
				var gear: Dictionary = run.data.gear_instances[id]
				var card := Gear.card(gear)
				entry.merge({"title": card.name, "category": "装备牌", "effect": card.trait, "level": card.level})
				entry.element = card.element
				entry.icon = card.icon
				entry.story = card.story
			"spell":
				var card: Dictionary = Cards.ACTIONS[id]
				entry.merge({"title": card.name, "category": "法术牌谱", "effect": card.trait + " 购买后永久解锁到本次远征的卡牌收藏。"})
				entry.element = card.get("element", "")
				entry.icon = card.icon
			"companion":
				var card := Cards.owned_definition(id, run.data.actors)
				var talent := Cards.breakthrough_talent(id)
				entry.merge({"title": card.name, "category": "招募伙伴", "portrait": card.portrait, "element": card.element,
					"effect": "%s\n%s\n第三次突破 · %s：%s" % [Cards.stats(card), card.trait, talent.name, talent.text]})
			"coins":
				entry.merge({"title": "灯铢", "category": "货币", "effect": "可用于招募伙伴、突破和商店交易。"})
		entries.append(entry)
	return entries

func _shop_dialog(feedback: String = "", resume: Dictionary = {}) -> void:
	var trader_id: String = selected_id
	var box := _modal("", 1070, 680)
	var panel := box.get_parent() as Control
	var shop := ShopView.new()
	box.add_child(shop)
	shop.setup(run, trader_id, {true: _shop_offers(trader_id, true), false: _shop_offers(trader_id, false)},
		panel.size.x, feedback, resume)
	var buy_or_sell := _item_command(func():
		var item := shop.selected
		if item.kind == "gear":
			return run.gear_trade(trader_id, item.id, shop.buying, shop.voucher)
		if item.kind == "spell":
			return run.buy_spell(trader_id, item.id)
		if item.kind == "companion":
			return run.recruit_companion(item.id)
		return run.trade(trader_id, item.id, shop.buying, shop.voucher, shop.quantity))
	var restock := _item_command(run.refresh_shop.bind(trader_id))
	shop.trade_requested.connect(func():
		if shop.is_inside_tree() and not shop.confirm.disabled:
			_shop_action(buy_or_sell, shop.selection()))
	shop.refresh_requested.connect(func():
		if shop.is_inside_tree() and shop.buying and not shop.refresh.disabled:
			_shop_action(restock, shop.selection()))
	shop.return_requested.connect(_leave_battle_shop)
	shop.loot_requested.connect(_victory_dialog)

func _shop_action(action: Callable, resume: Dictionary) -> void:
	sound.play("click")
	var result: Dictionary = action.call()
	_run_action(result)
	if result.ok and run.data.has("pending_story_rewards"):
		_show_pending_story_rewards()
		return
	var message: String = result.get("message", toast_text)
	_shop_dialog(message, resume)

func _shop_offers(trader_id: String, buying: bool) -> Array[Dictionary]:
	var trader: Dictionary = run.actor(trader_id)
	var node: Dictionary = run.shop_at(trader.position)
	var items: Array[Dictionary] = []
	var supplies: Dictionary = node.stock if buying else trader.inventory
	for id in supplies:
		if Nodes.PRICES.has(id) and not Gear.DATA.has(id) and int(supplies[id]) > 0:
			items.append({"kind": "item", "id": id, "count": int(supplies[id])})
	for uid in run.gear_owned("shop" if buying else "actor", trader.position if buying else trader_id):
		items.append({"kind": "gear", "id": uid, "count": 1})
	var relics: Dictionary = node.relic_stock if buying else run.data.relic_inventory
	for id in relics:
		if int(relics[id]) > 0:
			items.append({"kind": "relic", "id": id, "count": int(relics[id])})
	if buying:
		for spell in run.spell_shop_offers(trader.position):
			items.append({"kind": "spell", "id": spell, "count": 1})
		for id in run.recruit_shop_offers(trader.position):
			items.append({"kind": "companion", "id": id, "count": 1})
	var entries := _reward_entries(items)
	for entry in entries:
		var id: String = entry.id
		match entry.kind:
			"item":
				entry.base = Nodes.PRICES[id]
				entry.category = "补给"
				entry.owned = int(trader.inventory.get(id, 0))
			"gear":
				var instance: Dictionary = run.data.gear_instances[id]
				entry.base = Gear.price(instance)
				entry.owned = 0 if buying else 1
				entry.title = Gear.DATA[instance.definition_id].name
				var grade: String = Gear.QUALITY_NAMES[Gear.QUALITIES.find(instance.quality)]
				entry.grade = "%s +%d" % [grade, int(instance.enhance_level)]
			"companion":
				entry.base = run.recruit_shop_price(trader.position)
				entry.owned = 0
			"spell":
				entry.base = run.spell_shop_price()
				entry.owned = 0
			"relic":
				entry.base = Relics.DATA[id].price
				entry.owned = int(run.data.relic_inventory.get(id, 0))
				if not buying and run.has_relic(id):
					entry.grade = "共鸣中"
	return entries

func _item_command(action: Callable) -> Callable:
	item_operation_serial += 1
	var id = "%d:%d" % [Time.get_ticks_usec(), item_operation_serial]
	return run.commit_item_operation.bind(id, int(run.data.item_revision), action)

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
	if id == source:
		_reopen_current_node(source)
		return
	selected_cell = id
	move_target = id if Hex.is_land(run.data.tiles, id) and id in Hex.neighbors(source, run.data.tiles) else ""
	_refresh()

func _reopen_current_node(cell: String) -> void:
	if not run.data.tiles[cell].enemies.is_empty():
		_open_current_encounter()
		return
	var interaction := _node_interaction(cell)
	if not interaction.is_empty():
		_enter_node(cell, interaction)
	elif cell == run.data.start:
		_site_impression()
	else:
		_clear_map_move()
		selected_cell = cell
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
		if not _node_interaction(destination).is_empty():
			run.data.pending_arrival = {"actor": selected_id, "cell": destination}
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
		return
	var arrival: Dictionary = run.data.pending_arrival
	run.data.erase("pending_arrival")
	if selected_id == arrival.actor and run.actor(selected_id).position == arrival.cell:
		var interaction := _node_interaction(arrival.cell)
		if not interaction.is_empty():
			_enter_node(arrival.cell, interaction)
			return
	run.save_game()

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
	view.visible = screen_state == Screen.EXPEDITION and combat == null
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
	view.visible = in_expedition and combat == null
	view.set_process(view.visible)
	_update_world_input()

func _update_world_input() -> void:
	ui.process_mode = Node.PROCESS_MODE_DISABLED if map_traveling else Node.PROCESS_MODE_INHERIT
	var can_explore = combat == null and run.data.status == "exploring"
	view.set_world_input_enabled(not map_traveling and screen_state == Screen.EXPEDITION and view.visible
		and modal_layer.get_child_count() == 0 and can_explore)
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

func _inventory_heading(content: VBoxContainer, title: String, icon_key: String, level: int = 0) -> void:
	var texture := InventoryPage.icon(icon_key)
	if texture != null:
		var icon := InventoryPage.item_image(texture, level)
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
		_text(content, purpose, 16)
		if definition.has("story"):
			_text(content, definition.story, 15, muted)
		if run.same_cell(a.position).size() > 1:
			_button(content, "交接", _transfer_dialog.bind(id, item)).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN)
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
			var in_deck: bool = "gear:" + str(uid) in run.card_deck()
			entries.append({"id": uid, "title": Gear.label(item), "icon": item.definition_id, "level": int(item.enhance_level),
				"caption": definition.name, "badge": "已编入卡组" if in_deck else ""})
		page.set_items(entries, selected)
	filter.item_selected.connect(func(_index: int): refresh_grid.call(page.selected_id))
	set_filter.item_selected.connect(func(_index: int): refresh_grid.call(page.selected_id))
	refresh_grid.call(selection)

func _gear_detail(content: VBoxContainer, id: String, uid: String, feedback: String) -> void:
	var item = run.data.gear_instances[uid]
	var definition = Gear.DATA[item.definition_id]
	var a = run.actor(id)
	_inventory_heading(content, Gear.label(item), item.definition_id, int(item.enhance_level))
	if not feedback.is_empty():
		_text(content, feedback, 16, gold)
	_text(content, Gear.card(item).trait, 17, gold)
	_text(content, "在卡组编辑中编入，战斗时打出。每枚棋子每个装备槽只能装备一件。", 15, muted)
	_button(content, "阅读装备故事", func():
		_show_story(definition.name, "器物故事", definition.story, _story_scene_at(a.position),
			[], [], func(_option: String): _inventory_dialog(id, 1, uid), {}))
	_text(content, "持有 %d 灯铢" % run.data.lamp_coins, 16, gold)
	var quote: Dictionary = run.enhancement_quote(id, uid)
	if not quote.ok:
		_text(content, quote.message, 15, muted)
		return
	var preview: Dictionary = item.duplicate()
	preview.enhance_level += 1
	_text(content, "强化后：" + Gear.card(preview).trait, 15, muted)
	_button(content, "强化至 +%d · %d 灯铢" % [int(preview.enhance_level), quote.price], func():
		var result: Dictionary = run.enhance_card(id, uid)
		_run_action(result)
		_inventory_dialog(id, 1, uid, result.get("message", "")), run.data.lamp_coins < quote.price)


func _inventory_relics(page: InventoryPage, id: String, selection: String, feedback: String) -> void:
	var entries: Array[Dictionary] = []
	for type in ["P", "C", "L"]:
		for relic in Relics.DATA:
			var entry = Relics.DATA[relic]
			if entry.type != type or not run.data.relic_seen.has(relic):
				continue
			var count: int = int(run.data.relic_inventory.get(relic, 0))
			var badge := "共鸣中" if run.has_relic(relic) else ("已发现" if count == 0 else "")
			entries.append({"id": relic, "title": entry.name, "icon": relic,
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
	_inventory_heading(content, entry.name, relic)
	if not feedback.is_empty():
		_text(content, feedback, 16, gold)
	var kind: String = {"P": "持续", "C": "消耗", "L": "永久"}[entry.type]
	_text(content, kind + (" · 共鸣中" if relic in run.data.relic_attunement else ""), 15, muted)
	if entry.type == "P":
		_text(content, "全队共鸣 · %d / 6" % run.data.relic_attunement.size(), 15, muted)
	_text(content, Relics.current_effect(relic), 17)
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
		elif entry.type == "C":
			_text(content, "在开战前的卡组页面携带；每场最多携带一件。", 16, muted)
		else:
			var execute = _item_command(run.use_relic.bind(id, relic))
			_button(content, "启用生命之种", func():
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

func _open_current_encounter(show_intro: bool = true) -> void:
	var cell: String = run.actor(selected_id).position
	if run.data.pending_battle.is_empty():
		run.data.pending_battle = {"position": cell, "ambush": false, "origin": cell, "npc": ""}
		run.save_game()
	if show_intro:
		_show_encounter_intro()
	else:
		_deck_dialog(true)

func _show_encounter_intro() -> void:
	var encounter: Dictionary = run.data.pending_battle
	var cell: String = encounter.position
	if "war_god" not in run.data.tiles[cell].enemies:
		_deck_dialog(true)
		return
	var body := "鼓声从营里传来。你在路上听过同样的鼓点，每响一下，那些想逃走的士兵就握紧了手里的武器。现在鼓就在眼前。卡德兰挡在通往鼓台的路上，伸手取下了自己的兵器。"
	var portraits := [_story_portrait("hero", "serious"), _story_portrait("war_god", "serious")]
	_show_story(_node_title(cell) + " · 战鼓", "旁白", body, _story_scene_at(cell), portraits,
		[_node_option("deck", "编辑卡组与开战")], func(_option: String): _deck_dialog(true), {}, _node_tint())

func _deck_dialog(encounter: bool = false, back_to_rewards: Callable = Callable()) -> void:
	var pending: Dictionary = run.data.pending_battle
	if encounter and pending.is_empty():
		return
	var box := _modal("", 1110, 740)
	var editor := DeckEditor.new()
	box.add_child(editor)
	var opponent := ""
	if encounter:
		var enemies: Array = run.data.tiles[pending.position].enemies
		if not pending.npc.is_empty():
			opponent = run.actor(pending.npc).name
		elif not enemies.is_empty():
			opponent = Catalog.ENEMIES["war_god" if "war_god" in enemies else enemies[0]].name
			if "war_god" not in enemies and run.node_at(pending.position).get("kind") == "elite":
				opponent += " · 精英险地"
		var exploration: int = run.exploration_percent()
		var tier := Chess.difficulty_tier(exploration, Chess.is_elite_encounter(run, pending.position, pending), "war_god" in enemies)
		opponent += " · %s（探索度 %d%%）" % [Chess.difficulty_name(tier), exploration]
		if pending.ambush:
			opponent += " · 伏击先手"
	editor.setup(run.data.actors, run.card_deck(), encounter, (box.get_parent() as Control).size.x,
		opponent, run, "返回奖励" if back_to_rewards.is_valid() else "")
	editor.completed.connect(func(deck: Array):
		var saved: Dictionary = run.save_card_deck(deck)
		if not saved.ok:
			editor.show_error(saved.message)
			return
		if encounter:
			var model := Chess.new()
			var started := model.begin(run, pending, deck)
			if not started.ok:
				editor.show_error(started.message)
				return
			_close_modal()
			combat = model
			battle_timer = 0.65
			toast_text = ""
			_refresh()
		elif back_to_rewards.is_valid():
			back_to_rewards.call()
		else:
			_close_modal()
			_refresh())
	editor.cancelled.connect(back_to_rewards if back_to_rewards.is_valid() else _close_modal)

func _show_chess_view() -> void:
	chess_view = ChessView.new()
	ui.add_child(chess_view)
	chess_view.setup(combat, _story_texture(_story_scene_at(combat.position)))
	chess_view.acted.connect(func():
		sound.play("click")
		battle_timer = 0.20 if chess_view.is_attack_playing() else 0.55)
	chess_view.attack_impact.connect(sound.play)
	chess_view.retreat_requested.connect(func():
		_confirm("撤退？", "队伍返回出发地，旅人会受伤。", func():
			if combat != null and combat.retreat():
				_finish_battle()))
	chess_view.menu_requested.connect(_to_menu)

func _finish_battle() -> void:
	if combat == null or combat.outcome == "":
		return
	var victory = combat.outcome == "victory"
	combat = null
	selected_cell = run.actor(selected_id).position
	if victory:
		sound.play("victory")
		selected_id = "hero"
		_refresh()
		_shop_dialog()
		return
	_close_modal()
	_refresh()
	if run.data.status == "failed":
		_ending_story()
	else:
		_show_relic_intro()

func _victory_items(result: Dictionary) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	if not result.relic.is_empty():
		items.append({"kind": "relic", "id": result.relic, "count": 1,
			"status": "再次获得遗器" if result.get("relic_duplicate", false) else "发现遗器"})
	if result.get("coins", 0) > 0:
		items.append({"kind": "coins", "id": "lamp_coin", "count": result.coins})
	return items

func _leave_battle_shop() -> void:
	var previous: Dictionary = run.data.duplicate(true)
	_remove_reward_intros(_victory_items(run.data.pending_victory))
	run.close_battle_shop()
	run.data.erase("pending_victory")
	var saved: Dictionary = run.save_game()
	if not saved.ok:
		run.data = previous
		_shop_dialog(saved.message)
		return
	_close_modal()
	_refresh()
	if run.data.status == "won":
		_ending_story()
	else:
		_show_arrival()

func _victory_dialog() -> void:
	var result: Dictionary = run.data.pending_victory
	var box = _modal("战斗胜利", 730, 590)
	box.get_parent().name = "VictoryScreen"
	ui.hide()
	var content = _scroll_content(box)
	_text(content, "击倒主战者 · " + str(result.opponent) if result.has("opponent") else "已击败 %d 名敌人" % int(result.enemies), 19, muted)
	var items := _victory_items(result)
	if items.is_empty():
		_text(content, "这场没有战利品。", 17, muted)
	else:
		var rewards := RewardItems.new()
		rewards.custom_minimum_size.y = 305
		content.add_child(rewards)
		rewards.setup(_reward_entries(items))
	content.add_child(HSeparator.new())
	_text(content, "参战队员", 20, gold)
	for id in result.members:
		var actor = run.actor(id)
		var recovered = " · 倒下后已恢复至 1 HP" if id in result.revived else ""
		_text(content, "%s · HP %d/%d%s" % [actor.name, actor.hp, actor.hp_max, recovered], 16)
	_button(box, "返回商店", _shop_dialog).grab_focus()

func _process(delta: float) -> void:
	if combat == null or modal_layer.get_child_count() > 0:
		return
	if is_instance_valid(chess_view) and chess_view.is_attack_playing():
		return
	battle_timer -= delta
	if battle_timer > 0:
		return
	if not combat.outcome.is_empty():
		_finish_battle()
	elif combat.reveal_pending:
		_final_battle_page(0)
	elif combat.turn == Chess.ENEMY:
		combat.enemy_turn(true)
		chess_view.present_action()
		battle_timer = 0.15 if chess_view.is_attack_playing() else 0.8 if combat.enemy_action_resolved else 0.25

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
			if not river_revealed:
				_final_battle_page(index + 1)
			else:
				_resume_final_battle(), {}, Color.WHITE, 0, {}, Callable(), _resume_final_battle)

func _resume_final_battle() -> void:
	combat.awaken_death_power()
	_close_modal()
	_refresh()

func _talk(id: String) -> void:
	if not run.actor(id).get("joined", false):
		_notice("可在战后商店招募伙伴。")
		return
	var intro = narrative.encounter_intro(selected_id, id)
	if not intro.ok:
		_notice(intro.message)
		return
	if not character_codex_state.is_empty():
		_close_character_codex()
	_begin_dialogue(id)

func _begin_dialogue(id: String) -> void:
	if not run.actor(id).get("joined", false):
		_notice("可在战后商店招募伙伴。")
		return
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
	while not remaining.is_empty():
		var end = _story_fitted_end(remaining, label)
		if end < remaining.length():
			var sentence_ends = _story_sentence_ends(remaining, end)
			if not sentence_ends.is_empty():
				end = _story_balanced_end(remaining, sentence_ends, label)
			else:
				# A sentence taller than the page can still break at a clause or wrapped line.
				for index in range(end - 1, 0, -1):
					if remaining[index] in "；;，,、：:\n":
						end = index + 1
						break
			while end < remaining.length() and remaining[end] in "\n\r \t":
				end += 1
		pages.append(remaining.left(end))
		remaining = remaining.substr(end)
	return pages if not pages.is_empty() else PackedStringArray([""])

func _story_fitted_end(text: String, label: Label) -> int:
	var paragraph = TextParagraph.new()
	paragraph.width = label.size.x
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	paragraph.add_string(text, label.get_theme_font("font"), label.get_theme_font_size("font_size"))
	var spacing = label.get_theme_constant("line_spacing")
	var height = 0.0
	var end = 0
	for line in paragraph.get_line_count():
		var line_height = paragraph.get_line_size(line).y + (spacing if line > 0 else 0)
		if line > 0 and height + line_height > label.size.y:
			break
		height += line_height
		end = paragraph.get_line_range(line).y
	return clampi(end, mini(1, text.length()), text.length())

func _story_sentence_ends(text: String, fitted_end: int) -> PackedInt32Array:
	var ends = PackedInt32Array()
	var marks = "。！？!?｡"
	var closing = "」』”’）】》〉〕］)]}\"'"
	var suffix = marks + closing
	var index = 0
	while index < fitted_end:
		var mark = text[index]
		var period = mark == "." and (index + 1 == text.length() or text[index + 1] in closing + " \t\n\r")
		index += 1
		if mark not in marks and not period:
			continue
		while index < text.length() and text[index] in suffix:
			index += 1
		if index <= fitted_end:
			ends.append(index)
	return ends

func _story_balanced_end(text: String, sentence_ends: PackedInt32Array, label: Label) -> int:
	var end = sentence_ends[-1]
	var tail = text.substr(end).strip_edges()
	if _story_fitted_end(tail, label) < tail.length():
		return end
	# When two pages suffice, choose the closest sentence ending to the midpoint that fits both.
	var difference = absi(text.length() - 2 * end)
	for index in range(sentence_ends.size() - 2, -1, -1):
		var candidate = sentence_ends[index]
		var candidate_difference = absi(text.length() - 2 * candidate)
		if candidate_difference >= difference:
			break
		tail = text.substr(candidate).strip_edges()
		if _story_fitted_end(tail, label) == tail.length():
			end = candidate
			difference = candidate_difference
	return end

func _show_story(title: String, speaker: String, body: String, scene: String,
		portraits: Array, options: Array, on_choice: Callable, actions: Dictionary, tint: Color = Color.WHITE,
		page_index: int = 0, history_entry: Dictionary = {}, on_last_page: Callable = Callable(),
		on_skip: Callable = Callable()) -> void:
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
		# Keep the portrait's lower edge within the dialogue shade.
		_story_region(slot, center - portrait_width * 0.5, portrait_top, center + portrait_width * 0.5, 0.88)
		var actor_image = TextureRect.new()
		actor_image.name = "StoryActor%d" % i
		actor_image.texture = portraits[i]
		actor_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		actor_image.stretch_mode = TextureRect.STRETCH_SCALE
		actor_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var portrait_material := ShaderMaterial.new()
		portrait_material.shader = StoryPortrait
		actor_image.material = portrait_material
		actor_image.resized.connect(func():
			portrait_material.set_shader_parameter("portrait_height", actor_image.size.y))
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
	_story_icon_button(header, STORY_HISTORY_ICON, "历史对话", _show_story_history.bind(overlay)).name = "StoryHistoryButton"
	for label in actions:
		if label == "返回主菜单":
			_story_icon_button(header, STORY_MAIN_MENU_ICON, label, actions[label]).name = "StoryMainMenu"
			continue
		var button = _button(header, label, actions[label])
		if label in ["结束交谈", "返回角色图鉴"]:
			button.name = "StoryCancel"
	var turn_page = func(index: int):
		_show_story(title, speaker, body, scene, portraits, options, on_choice, actions, tint, index, history_entry, on_last_page, on_skip)
	var has_more_pages = page_index < pages.size() - 1
	if has_more_pages or options.is_empty():
		var skip = on_skip
		if not skip.is_valid():
			skip = turn_page.bind(pages.size() - 1)
			if options.is_empty():
				skip = func():
					if has_more_pages and on_last_page.is_valid():
						on_last_page.call()
					on_choice.call("")
		_story_icon_button(header, STORY_SKIP_ICON, "跳过当前剧情", skip).name = "StorySkip"
	var navigation = HBoxContainer.new()
	navigation.name = "StoryNavigation"
	navigation.mouse_filter = Control.MOUSE_FILTER_PASS
	navigation.alignment = BoxContainer.ALIGNMENT_END
	navigation.add_theme_constant_override("separation", 12)
	overlay.add_child(navigation)
	_story_region(navigation, 0.64, 0.90, 0.95, 0.955)
	if page_index > 0:
		_button(navigation, "上一页", turn_page.bind(page_index - 1))
	if has_more_pages or options.is_empty():
		var advance = func():
			if has_more_pages:
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

func _story_icon_button(header: HBoxContainer, icon: Texture2D, label: String, callback: Callable) -> Button:
	var button = _button(header, "", callback)
	button.icon = icon
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", 24)
	button.custom_minimum_size.x = 48
	button.tooltip_text = label
	button.accessibility_name = label
	return button

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
	if id == "villager_elf" and pose == "concerned":
		return preload("res://assets/portraits/villager_elf_water.png")
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
		_show_story(d.title, speaker, text, scene, portraits, d.options, _story_choice,
			{"结束交谈": _close_modal}, Color.WHITE, 0, {}, on_read)

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
	var result = narrative.choose(selected_id, dialogue_subject, option_id)
	if not result.ok:
		_notice(result.message, _render_dialogue)
		return
	if option_id in ["personal_a", "personal_b"]:
		run.save_game()
	var response: String = result.get("response", "")
	if response.is_empty() and _show_relic_intro(_render_dialogue):
		return
	if result.get("close", false):
		_close_modal()
		_refresh()
	elif result.get("quest", false):
		_personal_quest()
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
	var body: String = Relics.current_effect(intro.id) if effect_page else definition.story
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
			_show_opening(Screen.MENU))
	else:
		run.save_game()
		_show_opening(Screen.MENU)

func _guide() -> void:
	_notice("点相邻格预览，再点一次确认。伙伴跟随旅人一起移动，每走五格自动进入第二天。\n\n战斗胜利后会直接打开商店。抵达补给或寻宝地点会显示获得的物品。灯铢由全队共享。\n\n在「卡组」里选满 12 张牌。对战开局抽 3 张，之后每回合抽 1 张，只能走子、部署或用牌一次。攻击先扣护甲，击倒才占格。击倒对方主战者获胜。")

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
	_text(box, "按住左键拖动地图 · WASD 平移 · 滚轮缩放\n伙伴跟随旅人移动。\n对战时点棋子或手牌，再选高亮的格子。", 18, muted)
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
	_text(content, "维洛丹 · 试玩\n原创世界观、角色与肖像；原创怪物、适配及合成音效。肖像由内置图像生成工具制作。\n\n人形模型、动作与自然地景：Kay Lousberg，CC0。\n狼基础模型：crownjoshua，CC0；本项目修复绑定并制作动作。\n字体：Noto Sans SC，SIL Open Font License。\n引擎：Godot " + Engine.get_version_info().string + "\n完整来源、许可与适配说明随试玩包附带。", 18)
	_text(content, Engine.get_license_text(), 14, muted)
	_button(box, "返回设置", _settings_dialog)

func _smoke_capture() -> void:
	get_viewport().get_texture().get_image().save_png("user://smoke.png")
	print("SMOKE_FRAME=", ProjectSettings.globalize_path("user://smoke.png"))
	if "--smoke-exit" in OS.get_cmdline_user_args():
		get_tree().quit()
