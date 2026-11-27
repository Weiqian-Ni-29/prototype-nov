extends Control

const Journey = preload("res://scripts/domain/journey.gd")
const STAKE_COLORS = [Color("a9c7a7"), Color("e3c58e"), Color("efab94")]

func setup(game: Node) -> void:
	name = "JourneyScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var run: RefCounted = game.run
	var journey: Dictionary = run.data.journey
	var step := int(journey.step)
	var passage := Journey.encounter(run.data)
	var entry := Journey.current(run.data)
	var hero: Dictionary = run.actor("hero")
	var finished: bool = run.data.status != "exploring"
	var archived: bool = finished and journey.history.is_empty()

	var illustration := TextureRect.new()
	illustration.texture = game._story_texture("cover" if archived else passage.scene)
	illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	illustration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	illustration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(illustration)
	illustration.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.28, 0.54, 1.0])
	gradient.colors = PackedColorArray([Color("101c19b0"), Color("101c1912"), Color("101c1933"), Color("101c19ed")])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_to = Vector2(0, 1)
	shade.texture = texture
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var layout := VBoxContainer.new()
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layout)
	game._story_region(layout, 0.04, 0.045, 0.96, 0.95)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 16)
	layout.add_child(top)
	var status := _panel(game, top, Color("142820ed"))
	var progress_text := "远征记录" if archived else "第 %d / %d 段" % [step + 1, Journey.STOPS]
	var progress: Label = _line(game, status, progress_text, 21, game.gold)
	progress.name = "JourneyProgress"
	progress.autowrap_mode = TextServer.AUTOWRAP_OFF
	var resources: Label = _line(game, status, "生命 %d / %d     灯铢 %d" % [hero.hp, hero.hp_max, run.data.lamp_coins], 16, game.ink)
	resources.name = "JourneyResources"
	resources.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_spacer(false).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var navigation := HBoxContainer.new()
	navigation.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	navigation.add_theme_constant_override("separation", 8)
	top.add_child(navigation)
	if not finished:
		game._button(navigation, "卡组", game._deck_dialog)
		game._button(navigation, "背包", game._inventory_dialog.bind("hero"))
	game._button(navigation, "角色", game._show_character_codex)
	game._button(navigation, "旅途记录", game._journey_history)
	game._button(navigation, "设置", game._settings_dialog)
	game._button(navigation, "主菜单", game._to_menu)

	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(gap)
	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", 22)
	layout.add_child(bottom)
	if archived:
		bottom.add_spacer(false).mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		var story := _panel(game, bottom, Color("162922ed"))
		story.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		story.get_parent().size_flags_stretch_ratio = 1.3
		_line(game, story, passage.title, 40, game.gold)
		_line(game, story, passage.text, 20, game.ink)

	var actions := _panel(game, bottom, Color("172b24f5"))
	actions.name = "JourneyActions"
	actions.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if finished:
		_line(game, actions, "战争结束" if run.data.status == "won" else "远征终止", 28, game.gold)
		var text: String = game.narrative.main_ending().title if run.data.status == "won" else run.data.flags.get("failure_reason", "远征失败。")
		_line(game, actions, text, 18, game.ink)
		if entry.get("settled", false):
			_line(game, actions, settlement(entry), 16, game.gold)
		game._button(actions, "查看结局", game._ending_story)
	elif entry.is_empty():
		_line(game, actions, "选一条路", 24, game.gold)
		for index in passage.choices.size():
			var choice: Dictionary = passage.choices[index]
			var stake: int = choice.stakes
			var button: Button = game._button(actions, "%s    ·    %s" % [choice.label, Journey.STAKES[stake]],
				game._choose_journey.bind(step, index))
			button.name = "JourneyChoice%d" % index
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.custom_minimum_size.y = 46
			button.add_theme_color_override("font_color", STAKE_COLORS[stake])
			button.add_theme_color_override("font_hover_color", STAKE_COLORS[stake].lightened(0.2))
	else:
		_line(game, actions, Journey.LABELS[entry.kind], 28, game.gold)
		_line(game, actions, passage.choices[int(entry.choice)].label, 16, game.muted)
		if entry.settled:
			_line(game, actions, entry.text, 19, game.ink)
			_line(game, actions, settlement(entry), 16, game.gold)
			game._button(actions, "继续前进", game._advance_journey.bind(step)).name = "JourneyAdvance"
		elif entry.kind == "shop":
			_line(game, actions, "商贩打开货箱。", 19, game.ink)
			game._button(actions, "进入商店", game._shop_dialog).name = "JourneyEnter"
		else:
			_line(game, actions, "卡德兰拔刀。" if entry.kind == "boss" else "前路被拦住了。", 19, game.ink)
			game._button(actions, "准备战斗", game._deck_dialog.bind(true)).name = "JourneyEnter"

static func settlement(entry: Dictionary) -> String:
	var changes := PackedStringArray()
	if int(entry.hp_change) != 0:
		changes.append("生命 %+d" % int(entry.hp_change))
	if int(entry.coins_change) != 0:
		changes.append("灯铢 %+d" % int(entry.coins_change))
	return "  ·  ".join(changes) if not changes.is_empty() else "生命和灯铢无变化"

func _panel(game: Node, parent: Container, color: Color) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame: StyleBoxFlat = game._style(color, Color("827653"), 9)
	frame.set_content_margin_all(21)
	panel.add_theme_stylebox_override("panel", frame)
	parent.add_child(panel)
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 10)
	panel.add_child(content)
	return content

func _line(game: Node, parent: Container, text: String, size: int, color: Color) -> Label:
	var label: Label = game._text(parent, text, size, color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
