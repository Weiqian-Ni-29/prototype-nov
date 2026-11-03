extends Node
const Run = preload("res://scripts/domain/expedition.gd")
const Catalog = preload("res://scripts/domain/catalog.gd")
const Hex = preload("res://scripts/domain/hex_map.gd")
const Combat = preload("res://scripts/domain/battle.gd")
const Story = preload("res://scripts/domain/narrative.gd")
const World = preload("res://scripts/presentation/world_view.gd")
const FontAsset = preload("res://assets/fonts/NotoSansSC.ttf")
const Sound = preload("res://scripts/presentation/sound.gd")
var run = Run.new()
var view: Node3D
var ui: Control
var modal_layer: Control
var combat: RefCounted
var selected_id = "hero"
var selected_cell = ""
var moving_ids: Array = ["hero"]
var chosen_profession = "wayfarer"
var chosen_seed = "20261104"
var selected_target = "enemy_0"
var menu_visible = true
var battle_timer = 0.0
var toast_text = ""
var narrative: RefCounted
var dialogue_subject = ""
var dialogue_response = ""
var sound: Node
var gold = Color("dec38e")
var ink = Color("e8e4d1")
var muted = Color("a2b3a7")

func _ready() -> void:
	DisplayServer.window_set_title("归灯之野 · 白栎远征")
	sound = Sound.new()
	add_child(sound)
	view = World.new()
	add_child(view)
	view.cell_clicked.connect(_select_cell)
	var canvas = CanvasLayer.new()
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
	theme.set_stylebox("panel", "PopupMenu", _style(Color("233c36"), gold, 6))
	theme.set_stylebox("normal", "LineEdit", _style(Color("213831"), Color("647460"), 5))
	theme.set_stylebox("background", "ProgressBar", _bar_style(Color("152d2b")))
	theme.set_stylebox("fill", "ProgressBar", _bar_style(Color("92aa7a")))
	ui.theme = theme
	canvas.add_child(ui)
	modal_layer = Control.new()
	modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_layer.theme = theme
	canvas.add_child(modal_layer)
	run.new_run(20261104, "wayfarer")
	narrative = Story.new(run)
	selected_cell = run.data.start
	view.refresh(run, selected_id, selected_cell)
	view.focus_cell(selected_cell)
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
	if menu_visible:
		_menu(screen)
		return
	view.refresh(run, selected_id, selected_cell)
	_header(screen)
	if combat != null:
		_battle_ui(screen)
	elif run.data.status in ["extracted", "failed"]:
		_summary(screen)
	else:
		_crew_panel(screen)
		_tile_panel(screen)
	_footer(screen)

func _menu(screen: Vector2) -> void:
	if ResourceLoader.exists("res://assets/portraits/hero.png"):
		var illustration = TextureRect.new()
		illustration.texture = load("res://assets/portraits/hero.png")
		illustration.position = Vector2(screen.x * 0.43, 0)
		illustration.size = Vector2(screen.x * 0.57, screen.y)
		illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		illustration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		illustration.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ui.add_child(illustration)
	var box = _panel(ui, Rect2(70, 65, 570, minf(775, screen.y - 90)))
	_text(box, "RETURN TO THE LAMPS", 13, gold)
	_text(box, "归灯之野", 52, ink)
	_text(box, "第一章  ·  地图上没有的驿站", 21, gold)
	_text(box, "渡桥已塌，归途在迷雾之外。\n沿着旧灯路前进，决定与谁同行，又带什么回去。", 18, muted)
	_text(box, "选择职业", 18)
	for id in Catalog.PROFESSIONS:
		var p = Catalog.PROFESSIONS[id]
		var title = ("◆ " if id == chosen_profession else "◇ ") + p.name + "   HP %d · MP %d · AP %d" % [p.hp, p.mp, p.ap]
		_button(box, title + "\n" + p.description, _choose_profession.bind(id))
	var row = HBoxContainer.new()
	box.add_child(row)
	var seed_label = _text(row, "地图种子", 16, muted)
	seed_label.custom_minimum_size.x = 100
	seed_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var seed_edit = LineEdit.new()
	seed_edit.text = chosen_seed
	seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_edit.text_changed.connect(func(value: String): chosen_seed = value)
	row.add_child(seed_edit)
	_button(box, "开始远征  →", _start_new)
	_button(box, "继续上次远征", _continue_run, not FileAccess.file_exists(run.save_path))
	_button(box, "设置与操作指南", _settings_dialog)
	_text(box, "每位角色独立行动 · 无撤离期限\nWASD 平移地图，滚轮缩放，点击相邻地块前进。", 15, muted)
	var info = _panel(ui, Rect2(screen.x - 350, screen.y - 155, 315, 110), Color("19332fd9"))
	_text(info, "六边形上的一次冒险", 21, gold)
	_text(info, "手绘沙盘 · 3D 人偶 · 分支旅途", 15, muted)

func _choose_profession(id: String) -> void:
	chosen_profession = id
	_refresh()

func _start_new() -> void:
	var value = int(chosen_seed) if chosen_seed.is_valid_int() else hash(chosen_seed)
	run.new_run(value, chosen_profession)
	combat = null
	view.reset()
	selected_id = "hero"
	moving_ids = ["hero"]
	selected_cell = run.data.start
	menu_visible = false
	view.refresh(run, selected_id, selected_cell)
	view.focus_cell(selected_cell)
	run.save_game()
	_refresh()

func _continue_run() -> void:
	var result = run.load_game()
	if not result.ok:
		_notice(result.message)
		return
	combat = null
	view.reset()
	selected_id = "hero"
	moving_ids = ["hero"]
	selected_cell = run.actor("hero").position
	menu_visible = false
	view.refresh(run, selected_id, selected_cell)
	view.focus_cell(selected_cell)
	_refresh()
	if not run.data.pending_battle.is_empty():
		_formation_dialog()

func _header(screen: Vector2) -> void:
	var box = _panel(ui, Rect2(20, 17, screen.x - 40, 88))
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	_text(row, "归灯之野", 29, gold).custom_minimum_size.x = 190
	var weather = "细雨" if run.data.weather == "rain" else "晴朗"
	var forecast = "雨" if run.next_weather() == "rain" else "晴"
	_text(row, "第 %d 天  ·  %s\n明日%s · 探索 %d/217" % [run.data.day, weather, forecast, run.data.explored.size()], 16).custom_minimum_size.x = 250
	_text(row, "归航方向  " + _exit_direction() + "\n没有撤离期限，抵达后可等待同伴。", 16, muted).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(row, "设置/帮助", _settings_dialog)
	_button(row, "旅途手记", _journal)
	_button(row, "保存", func(): _run_action(run.save_game()), combat != null)
	_button(row, "主菜单", _to_menu)

func _exit_direction() -> String:
	if run.actor("hero").position == run.data.exit:
		return "已抵达"
	if run.data.explored.has(run.data.exit):
		return "已发现 · 见手记"
	var delta = Hex.coord(run.data.exit) - Hex.coord(run.data.start)
	return ("北" if delta.y < -2 else "南" if delta.y > 2 else "") + ("东" if delta.x + delta.y * 0.5 > 1 else "西" if delta.x + delta.y * 0.5 < -1 else "侧") + "一带"

func _crew_panel(screen: Vector2) -> void:
	var box = _panel(ui, Rect2(20, 120, 244, screen.y - 275))
	_text(box, "远征队", 24, gold)
	_text(box, "点击定位 · 勾选同格同行", 13, muted)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var roster = VBoxContainer.new()
	roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster.add_theme_constant_override("separation", 10)
	scroll.add_child(roster)
	for id in run.joined_ids():
		var a = run.actor(id)
		var row = HBoxContainer.new()
		roster.add_child(row)
		var toggle = CheckBox.new()
		toggle.button_pressed = id in moving_ids
		toggle.disabled = a.hp <= 0
		toggle.toggled.connect(_toggle_mover.bind(id))
		row.add_child(toggle)
		var text = ("◆ " if selected_id == id else "") + a.name + ("  重伤" if a.hp <= 0 else "")
		var button = _button(row, text, _select_actor.bind(id))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_text(roster, "HP %d/%d   MP %d/%d\nAP %d/%d  ·  充能 %d%%" % [a.hp, a.hp_max, a.mp, a.mp_max, a.ap, a.ap_max, a.energy], 13, muted)
		var bar = ProgressBar.new()
		bar.value = float(a.hp) / a.hp_max * 100
		bar.show_percentage = false
		bar.custom_minimum_size.y = 5
		roster.add_child(bar)
	_button(box, "个人背包与装备", _inventory_dialog.bind(selected_id))
	_button(box, "结束一天", _end_day_dialog)

func _tile_panel(screen: Vector2) -> void:
	var outer = _panel(ui, Rect2(screen.x - 342, 120, 322, screen.y - 275))
	var box = _scroll_content(outer)
	if selected_cell == "" or not run.data.explored.has(selected_cell):
		_text(box, "迷雾之中", 25, gold)
		_text(box, "移动揭开周围一圈。探索过的地块将永久点亮。", 17, muted)
		return
	var t = run.data.tiles[selected_cell]
	_text(box, World._site_name(t.site) if t.site != "" else Catalog.terrain_name(t.terrain), 25, gold)
	_text(box, "%s · 坐标 %s" % [Catalog.terrain_name(t.terrain), selected_cell], 14, muted)
	var states: Array[String] = []
	if t.burning:
		states.append("燃烧 · 剩余燃料 %d 天" % t.fuel)
	if t.wet_until > run.data.day:
		states.append("潮湿至第 %d 天" % t.wet_until)
	if not states.is_empty():
		_text(box, " / ".join(states), 16, gold)
	var here = run.actor(selected_id).position == selected_cell
	if not here:
		var preview = run.movement_preview(moving_ids, selected_cell)
		var costs: Array[String] = []
		if preview.ok:
			for id in preview.costs:
				costs.append(run.actor(id).name + " %d AP" % preview.costs[id])
		_text(box, "移动：" + " / ".join(costs) if preview.ok else preview.message, 15, muted)
		_button(box, "前往此格  →", _move_selected, not preview.ok)
	if not t.enemies.is_empty():
		if t.discovered_enemy:
			_text(box, "驻守敌人 · 强度固定", 18, Color("e4ab87"))
			_text(box, "首次上场另付每人 2 AP；同地最多四名在场，进入后开始遭遇。", 14, muted)
			for enemy in t.enemies:
				_text(box, Catalog.ENEMIES[enemy].name + " · " + Catalog.ENEMIES[enemy].role, 14, muted)
				if run.actor("grit").joined and run.actor("grit").hp > 0 and run.actor("grit").position == run.actor(selected_id).position and Hex.distance(Hex.coord(selected_cell), Hex.coord(run.actor(selected_id).position)) <= 1:
					var definition = Catalog.ENEMIES[enemy]
					_text(box, "砾牙辨识：HP %d · 攻击 %d · 速度 %d" % [definition.hp, definition.attack, definition.speed], 13, gold)
			if here:
				_button(box, "选择阵容并交战", _open_current_encounter)
		else:
			_text(box, "危险迹象", 18, Color("e4ab87"))
			_text(box, "泥水下有气泡，附近足迹忽然中断。" if t.terrain == "swamp" else "蛛丝挂在枝间，林下有新鲜脚印。", 16, muted)
	if t.npc != "" and run.actor(t.npc).position == selected_cell:
		var npc = run.actor(t.npc)
		_text(box, npc.name + " · " + npc.title, 18)
		if here:
			_button(box, "交谈 / 个人故事", _talk.bind(t.npc))
	elif t.site in ["inn", "home", "record", "exit", "water", "track", "forest"] and here:
		_button(box, "调查与交谈", _talk.bind(t.site))
	if here:
		for id in run.same_cell(selected_cell):
			if id != "hero" and id != t.npc:
				_button(box, "与 " + run.actor(id).name + " 交谈", _talk.bind(id))
	if t.quantity > 0:
		_text(box, "可采集：%s ×%d" % [Catalog.item_name(t.resource), t.quantity], 16, muted)
		if here:
			_button(box, "采集 · 1 AP", func(): _run_action(run.collect(selected_id)))
	if here:
		_button(box, "使用物资 / 同地救援", _item_dialog.bind(selected_id))
		if run.actor(selected_id).skill == "heal":
			_button(box, "治疗队友 · 1 AP / 12 MP", _healing_dialog)
		if run.actor(selected_id).skill == "ember":
			_button(box, "点燃林地 · 1 AP / 8 MP", func(): _run_action(run.environmental_skill(selected_id, "ignite")))
		if run.actor(selected_id).skill == "torrent":
			_button(box, "灭火 / 浸湿 · 1 AP / 8 MP", func(): _run_action(run.environmental_skill(selected_id, "wet")))
		_button(box, "休整 · 2 AP", func(): _run_action(run.rest(selected_id)))
		_button(box, "建营 · 2 AP / 2 木料", func(): _run_action(run.build_camp(selected_id)), t.camp)
		if selected_cell == run.data.exit and run.actor("hero").position == run.data.exit:
			_button(box, "确认撤离 / 继续等待", _extraction_dialog)

func _footer(screen: Vector2) -> void:
	var box = _panel(ui, Rect2(20, screen.y - 140, screen.x - 40, 122))
	_text(box, toast_text if toast_text != "" else "旅途记录", 15, gold)
	var lines: Array[String] = []
	for line in run.data.log.slice(maxi(0, run.data.log.size() - 3)):
		lines.append(str(line))
	_text(box, "\n".join(lines), 14, muted)

func _toggle_mover(value: bool, id: String) -> void:
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

func _select_actor(id: String) -> void:
	selected_id = id
	selected_cell = run.actor(id).position
	moving_ids = [id]
	view.focus_cell(selected_cell)
	_refresh()

func _select_cell(id: String) -> void:
	if menu_visible or combat != null or modal_layer.get_child_count() > 0:
		return
	selected_cell = id
	_refresh()

func _move_selected() -> void:
	var result = run.move(moving_ids, selected_cell)
	if result.ok and selected_id in moving_ids:
		view.focus_cell(selected_cell)
	_run_action(result)
	if result.ok and result.get("battle", false):
		_formation_dialog()

func _run_action(result: Dictionary) -> void:
	toast_text = "已完成。" if result.ok else str(result.get("message", "无法执行。"))
	if result.ok and run.data.status != "battle":
		run.save_game()
	_refresh()

func _modal(title: String, width: float = 650, height: float = 520) -> VBoxContainer:
	_clear(modal_layer)
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
			remaining.append("%s %d AP" % [run.actor(id).name, run.actor(id).ap])
	_confirm("结束这一天？", "尚余：" + " / ".join(remaining) + "\n\n全队进入次日，HP/MP 部分恢复、AP 回各自上限；重伤不会自行站起。火势按日结算。", func(): _run_action(run.end_day()))

func _extraction_dialog() -> void:
	var preview = run.extraction_preview()
	var message = "到站撤离：\n"
	for id in preview.present:
		message += run.actor(id).name + ("（重伤）" if run.actor(id).hp <= 0 else "") + "  "
	message += "\n\n异地未撤离：\n"
	for id in preview.absent:
		message += "%s · %s · %s\n" % [run.actor(id).name, run.actor(id).position, "重伤待援" if run.actor(id).hp <= 0 else "可行动"]
	message += "\n可取消并继续等人；确认后按当前处境记录尾声。"
	_confirm("确认归航名单", message, func(): _run_action(run.extract()))

func _inventory_dialog(id: String) -> void:
	var a = run.actor(id)
	var box = _modal(a.name + " · 背包与装备", 850, 670)
	_text(box, "攻击 %d · 防御 %d · 速度 %d\n战斗外免费换装；物品只在同格交接，不刷新资源。" % [run.stat(id, "attack"), run.stat(id, "defense"), run.stat(id, "speed")], 16, muted)
	var slots: Array[String] = []
	for slot in ["weapon", "armor", "accessory"]:
		var item = str(a.equipment.get(slot, ""))
		slots.append({"weapon": "武器", "armor": "防具", "accessory": "饰品"}[slot] + "：" + (Catalog.item_name(item) if item != "" else "空"))
	_text(box, "  ·  ".join(slots), 17, gold)
	_text(box, "专长：" + Catalog.passive_description(id), 16, muted)
	_text(box, "技能 · " + Catalog.SKILLS[a.skill].name + "\n" + Catalog.skill_description(a.skill), 16, muted)
	_text(box, "终结技 · " + Catalog.SKILLS[a.ultimate].name + "\n" + Catalog.skill_description(a.ultimate) + "；满能量额外释放，不占正常行动。", 16, muted)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for item in a.inventory:
		if a.inventory[item] <= 0:
			continue
		var row = HBoxContainer.new()
		list.add_child(row)
		_text(row, Story.DOCUMENTS.get(item, Catalog.item_name(item)) + " ×%d" % a.inventory[item], 16).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if Catalog.ITEMS.get(item, {}).has("slot"):
			_button(row, "卸下" if item in a.equipment.values() else "装备", func(): _run_action(run.equip(id, item)); _inventory_dialog(id))
		if run.same_cell(a.position).size() > 1:
			_button(row, "交接", _transfer_dialog.bind(id, item))
	_button(box, "关闭", _close_modal)

func _transfer_dialog(owner: String, item: String) -> void:
	var box = _modal("同地交接 · " + Story.DOCUMENTS.get(item, Catalog.item_name(item)), 650, 540)
	_text(box, "每次交接一件，不消耗行动点。已装备的物品需先卸下。", 17, muted)
	var content = _scroll_content(box)
	for other in run.same_cell(run.actor(owner).position):
		if other != owner:
			_button(content, "交给" + run.actor(other).name, func():
				var result = run.transfer(owner, other, item, 1)
				if result.ok:
					_run_action(result)
					_inventory_dialog(owner)
				else:
					_text(content, result.message, 16, gold))
	_button(box, "返回背包", _inventory_dialog.bind(owner))

func _item_dialog(user_id: String) -> void:
	var box = _modal("使用物资 · " + run.actor(user_id).name, 650, 460)
	_text(box, "地图使用不耗 AP；战斗中不占正常行动，可使用多件。", 16, muted)
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
	box.add_child(select)
	for item in ["salve", "ether"]:
		var quantity = int(run.actor(user_id).inventory.get(item, 0))
		_button(box, Catalog.item_name(item) + " ×%d" % quantity, func():
			var target = targets[select.selected]
			var result = combat.use_item(item, target) if combat != null else run.use_item(user_id, target, item)
			_run_action(result)
			_item_dialog(user_id), quantity <= 0 or targets.is_empty())
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
	run.data.pending_battle = {"position": selected_cell, "ambush": false, "origin": selected_cell, "movers": [], "npc": ""}
	_formation_dialog()

func _formation_dialog() -> void:
	var encounter = run.data.pending_battle
	var box = _modal("选择出战阵容 · 最多四人", 700, 620)
	_text(box, "每人本场首次上场支付 2 AP；同地候补可换入。" + ("\n伏击：行动点不足仍可出战，最多扣至 0。" if encounter.ambush else ""), 17, muted)
	var chosen: Array = []
	for id in run.same_cell(encounter.position, true):
		var eligible = encounter.ambush or run.actor(id).ap >= Catalog.BATTLE_AP
		var toggle = CheckBox.new()
		toggle.text = "%s · HP %d/%d · AP %d" % [run.actor(id).name, run.actor(id).hp, run.actor(id).hp_max, run.actor(id).ap]
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
		box.add_child(toggle)
	_button(box, "开始战斗", func():
		var battle = Combat.new()
		var result = battle.begin(run, encounter, chosen)
		if result.ok:
			_close_modal()
			combat = battle
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
	var left_outer = _panel(ui, Rect2(20, 120, 250, screen.y - 275))
	_text(left_outer, "出战角色", 24, gold)
	var left = _scroll_content(left_outer)
	left.add_theme_constant_override("separation", 4)
	for id in combat.active:
		var a = run.actor(id)
		_text(left, ("▶ " if combat.current == id else "") + a.name + (" · 盾%d" % a.shield if a.shield > 0 else ""), 19, ink if a.hp > 0 else muted)
		_text(left, "HP %d/%d · MP %d/%d" % [a.hp, a.hp_max, a.mp, a.mp_max], 14, muted)
		_hp_bar(left, a.hp, a.hp_max)
		_button(left, "%d%% · " % a.energy + Catalog.SKILLS[a.ultimate].name, _ultimate.bind(id), a.energy < 100 or a.hp <= 0)
	var right_outer = _panel(ui, Rect2(screen.x - 330, 120, 310, screen.y - 275))
	_text(right_outer, "敌方阵容", 24, gold)
	var right = _scroll_content(right_outer)
	right.add_theme_constant_override("separation", 4)
	for id in combat.enemies:
		var e = combat.enemies[id]
		_button(right, ("◆ " if selected_target == id else "") + e.name, func(): selected_target = id; _refresh(), e.hp <= 0)
		_text(right, "HP %d/%d · %s\n%s" % [e.hp, e.hp_max, "蓄力中！" if e.charged else "行动蓄积", e.role], 14, muted)
		_hp_bar(right, e.hp, e.hp_max, true)
	var timeline: Array[String] = []
	for entry in combat.timeline(6):
		timeline.append(combat.unit(entry.id).name)
	_text(right, "行动顺序\n" + " → ".join(timeline), 14, gold)
	var center = _panel(ui, Rect2(290, screen.y - 305, screen.x - 640, 155))
	var is_friendly = combat.current != "" and not combat.enemies.has(combat.current) and combat.outcome == "" and battle_timer <= 0
	_text(center, (combat.unit(combat.current).name + " 的行动") if combat.current != "" else "战斗结算", 20, gold)
	var commands = HBoxContainer.new()
	center.add_child(commands)
	_button(commands, "普攻", func(): _combat_action("attack"), not is_friendly)
	var skill_id = str(combat.unit(combat.current).get("skill", "attack")) if is_friendly else "attack"
	_button(commands, Catalog.SKILLS.get(skill_id, Catalog.SKILLS.attack).name, func(): _combat_action(skill_id), not is_friendly)
	_button(commands, "防守", func(): _combat_action("guard"), not is_friendly)
	_button(commands, "物资", func(): _item_dialog(combat.current), not is_friendly)
	_button(commands, "换人", _swap_dialog, not is_friendly or combat.reserves().is_empty())
	_button(commands, "自动 ON" if combat.auto_mode else "自动 OFF", func(): combat.auto_mode = not combat.auto_mode; _refresh())
	_button(commands, "自动可点火" if combat.allow_auto_ignite else "自动保林", func(): combat.allow_auto_ignite = not combat.allow_auto_ignite; _refresh())
	_button(commands, "撤退", func(): _confirm("撤退？", "已付 AP 不退还；本战出战者承受 10% 最大生命损伤，敌人恢复。", func(): _run_action(combat.retreat()); _finish_battle()))
	var terrain = run.data.tiles[combat.position]
	var context = "场地：" + Catalog.terrain_name(terrain.terrain) + (" · 燃烧" if terrain.burning else " · 潮湿" if terrain.wet_until > run.data.day else "")
	if is_friendly:
		context += "\n" + Catalog.skill_description(skill_id)
		if selected_target in combat.alive_enemies() and Catalog.SKILLS[skill_id].target == "enemy":
			context += " · 预计基础伤害 %d（护盾/防守等另计）" % combat.damage_preview(combat.current, selected_target, skill_id)
	_text(center, context, 12, muted)

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
	if not result.ok:
		toast_text = result.message
	_after_combat_step()

func _ultimate(id: String) -> void:
	var result = combat.request_ultimate(id, selected_target)
	if result.ok:
		if battle_timer > 0:
			toast_text = "终结技已排队，在当前动作结束后释放。"
			_refresh()
			return
		combat.resolve_queued()
	else:
		toast_text = result.message
	_after_combat_step()

func _swap_dialog() -> void:
	var box = _modal("换入同地候补", 600, 500)
	for id in combat.reserves():
		_button(box, run.actor(id).name + " · HP %d · AP %d" % [run.actor(id).hp, run.actor(id).ap], func(): _close_modal(); _run_action(combat.swap(id)); _after_combat_step())
	_button(box, "取消", _close_modal)

func _after_combat_step() -> void:
	var presentation_events = combat.events.duplicate(true)
	combat.events.clear()
	if not presentation_events.is_empty():
		sound.play("attack" if presentation_events[0].kind == "attack" else "cast")
	battle_timer = 0.85
	if not combat.alive_enemies().has(selected_target) and not combat.alive_enemies().is_empty():
		selected_target = combat.alive_enemies()[0]
	_refresh()
	view.animate_events(presentation_events)
	if combat.outcome != "":
		if combat.outcome == "victory":
			sound.play("victory")
		get_tree().create_timer(0.8).timeout.connect(_finish_battle)

func _finish_battle() -> void:
	if combat == null or combat.outcome == "":
		return
	combat = null
	view.end_battle()
	selected_cell = run.actor(selected_id).position
	_refresh()

func _process(delta: float) -> void:
	if combat == null or combat.outcome != "" or modal_layer.get_child_count() > 0:
		return
	var was_playing = battle_timer > 0
	battle_timer -= delta
	if battle_timer <= 0 and not combat.queue.is_empty():
		combat.resolve_queued()
		_after_combat_step()
		return
	if battle_timer <= 0 and (combat.enemies.has(combat.current) or combat.auto_mode):
		combat.step_auto()
		_after_combat_step()
	elif was_playing and battle_timer <= 0:
		_refresh()

func _talk(id: String) -> void:
	dialogue_subject = id
	dialogue_response = ""
	_render_dialogue()

func _render_dialogue() -> void:
	var d = narrative.dialogue(selected_id, dialogue_subject)
	if not d.ok:
		_notice(d.message)
		return
	var box = _modal(d.title, 900, 740)
	var columns = HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 20)
	box.add_child(columns)
	var portrait_path = "res://assets/portraits/" + dialogue_subject + ".png"
	if ResourceLoader.exists(portrait_path):
		var portrait = TextureRect.new()
		portrait.texture = load(portrait_path)
		portrait.custom_minimum_size = Vector2(245, 340)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		columns.add_child(portrait)
	var content = _scroll_content(columns)
	_text(content, d.text, 19)
	if dialogue_response != "":
		_text(content, dialogue_response, 18, gold)
	for option in d.options:
		var caption = str(option.text)
		if not option.enabled:
			caption += "\n" + str(option.reason)
		var button = _button(content, caption, _story_choice.bind(str(option.id)), not option.enabled)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(box, "结束交谈，继续远征", _close_modal)
	run.save_game()

func _story_choice(option_id: String) -> void:
	var result = narrative.choose(selected_id, dialogue_subject, option_id)
	if not result.ok:
		dialogue_response = result.message
		_render_dialogue()
		return
	if result.get("close", false):
		_close_modal()
		_refresh()
	elif result.get("battle", false):
		_formation_dialog()
	elif result.get("extract_requested", false):
		_extraction_dialog()
	elif result.has("rescue"):
		_item_dialog(selected_id)
	elif result.has("heal_dialog"):
		_healing_dialog()
	else:
		dialogue_response = str(result.get("response", "同行状态已更新。"))
		run.save_game()
		_refresh()
		_render_dialogue()

func _journal() -> void:
	var box = _modal("旅途手记 · 亲历、文书与同行", 920, 720)
	var content = _scroll_content(box)
	if run.data.explored.has(run.data.exit):
		_text(content, "已发现归航站：" + str(run.data.exit), 21, gold)
		_button(content, "在地图上定位归航站", func(): _close_modal(); selected_cell = run.data.exit; view.focus_cell(selected_cell); _refresh())
	_text(content, "地方故事", 23, gold)
	var flags = run.data.flags
	_text(content, "二十八年前的接应记录与仍有人居住的林边之间存在矛盾。材料可向陆衡、乔禾和旧调度柜核对；调查不是撤离前置条件。" if flags.get("investigated", false) else "渡桥坍塌，归航站在另一端。你可以沿方向归航，也可以探索沿途人物与仍在使用的旧灯路。", 18)
	for id in Catalog.COMPANIONS:
		if run.data.story[id].met:
			var s = run.data.story[id]
			_text(content, "%s · %s" % [run.actor(id).name, "已同行" if run.actor(id).joined else "暂缓" if s.relation == "later" else "本局未同行" if s.relation == "declined" else "已接触"], 20, gold)
			_text(content, Story.PERSONAL[id].get(str(s.result), ""), 16, muted)
	_text(content, "原件的实际去向", 23, gold)
	for item in Story.DOCUMENTS:
		var holders: Array[String] = []
		for id in run.joined_ids():
			if int(run.actor(id).inventory.get(item, 0)) > 0:
				holders.append(run.actor(id).name + "（" + str(run.actor(id).position) + "）")
		if run.data.submitted.has(item):
			holders.append("归航站已实际收件")
		if not holders.is_empty():
			_text(content, Story.DOCUMENTS[item] + "：" + " / ".join(holders), 16, muted)
	_text(content, "同地角色可当面交换亲历见闻；共享地图不传送物品。", 16, muted)
	_button(box, "合上手记", _close_modal)

func _summary(screen: Vector2) -> void:
	var box = _panel(ui, Rect2(300, 135, screen.x - 600, screen.y - 300))
	_text(box, "归航记录" if run.data.status == "extracted" else "远征终止", 36, gold)
	_text(box, "第 %d 天 · 探索 %d 格 · 战斗 %d 场" % [run.data.day, run.data.explored.size(), run.data.battles], 18)
	if run.data.status == "failed":
		_text(box, run.data.flags.get("failure_reason", "远征失败。"), 20, muted)
	else:
		var ending = narrative.main_ending()
		_text(box, ending.title, 25, gold)
		_text(box, ending.text, 18)
	var content = _scroll_content(box)
	for id in Catalog.COMPANIONS:
		var ending = narrative.character_ending(id)
		var condition = "未相遇" if not run.data.story[id].met and not run.actor(id).joined else "本局未同行" if not run.actor(id).joined else "已到站" if run.actor(id).position == run.data.exit else "异地重伤" if run.actor(id).hp <= 0 else "异地未撤离"
		_text(content, ending.name + " · " + condition, 20, gold)
		_text(content, ending.text, 17, muted)
	_button(box, "返回主菜单", _to_menu)

func _to_menu() -> void:
	if combat != null:
		_confirm("返回菜单？", "未完成战斗将保留同一个战前检查点与随机状态；继续时重新进入本场遭遇。", func(): combat = null; view.end_battle(); menu_visible = true; _refresh())
	else:
		run.save_game()
		menu_visible = true
		_refresh()

func _guide() -> void:
	_notice("点击角色定位，勾选同格角色可共同移动。点击相邻地块后，在详情面板确认前往。\n\nWASD 平移、滚轮缩放。每人 AP 独立；结束一天恢复个人 AP 以及部分 HP/MP。\n\n同地最多四人出战，候补换人占正常行动；终结技可插队。\n\n交谈与交任务免费，物品只能同格交接。抵达归航站后可等待，只有主动确认才结束。")

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
	_text(box, "WASD 平移地图 · 滚轮缩放\n点击角色定位，勾选同格成员同行。\n自动战斗默认保林，可在战斗中允许自动点火。", 18, muted)
	_button(box, "查看完整操作指南", _guide)
	_button(box, "制作与许可", _credits_dialog)
	if not menu_visible and combat == null and run.data.status == "exploring":
		_button(box, "放弃本次远征", func(): _confirm("结束本次远征？", "将按远征中断记录当前事实；已经交出的文书仍保留，不把异地角色写成成功归航。", func(): run.data.status = "failed"; run.data.flags.failure_reason = "你主动结束了本次远征。"; run.save_game(); _refresh()))
	_button(box, "返回", _close_modal)

func _credits_dialog() -> void:
	var box = _modal("制作与许可", 800, 650)
	var content = _scroll_content(box)
	_text(content, "《归灯之野》MVP 0.1.0\n原创世界观、角色、程序化立体模型、骨骼、材质与合成音效。肖像由内置图像生成工具制作。\n\n字体：Noto Sans SC，SIL Open Font License。\n引擎：Godot " + Engine.get_version_info().string + "\n许可全文与第三方声明随试玩包附带。", 18)
	_text(content, Engine.get_license_text(), 14, muted)
	_button(box, "返回设置", _settings_dialog)

func _smoke_capture() -> void:
	get_viewport().get_texture().get_image().save_png("user://smoke.png")
	print("SMOKE_FRAME=", ProjectSettings.globalize_path("user://smoke.png"))
	if "--smoke-exit" in OS.get_cmdline_user_args():
		get_tree().quit()
