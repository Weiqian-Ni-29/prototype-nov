extends SceneTree
const Main = preload("res://scenes/main.tscn")
const Hex = preload("res://scripts/domain/hex_map.gd")
var checks = 0
var failures = 0

func _initialize() -> void:
	call_deferred("execute")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func has_label(parent: Node, text: String) -> bool:
	return parent.find_children("*", "Label", true, false).any(func(label): return text in label.text)

func expect_stamina(game: Node, remaining: int) -> void:
	var tracks = game.ui.find_children("CrewStamina", "HBoxContainer", true, false)
	expect(tracks.size() == 1 and tracks[0].get_child_count() == 5, "Five segments appear once for the whole party")
	if tracks.size() != 1:
		return
	for index in tracks[0].get_child_count():
		var style: StyleBoxFlat = tracks[0].get_child(index).get_theme_stylebox("panel")
		expect(style.bg_color == Color("91c970" if index < remaining else "47604c"),
			"Stamina segment %d reflects %d remaining steps" % [index + 1, remaining])

func wait_for_arrival(game: Node) -> void:
	var deadline = Time.get_ticks_msec() + 5000
	while game.map_traveling and Time.get_ticks_msec() < deadline:
		await process_frame
	expect(not game.map_traveling, "Travel animation completes")

func execute() -> void:
	var game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game.sound.set_volume(0.0, false)
	game.run.save_path = "user://test-hero-marker.json"
	game._start_new()
	game.set_process(false)
	var run = game.run
	var origin: String = run.actor("hero").position
	var next: String = Hex.neighbors(origin, run.data.tiles).filter(func(cell): return Hex.is_land(run.data.tiles, cell))[0]
	run.data.tiles[next].enemies.clear()
	var colors = {"hero": "17161e", "ember": "773831", "tide": "24536e", "wind_runner": "376452"}
	for id in ["ember", "tide", "wind_runner"]:
		run.actor(id).position = origin
		expect(run.join_companion(id).ok, "Recruit companion " + id)
	# Treat recruitment reward stories as already read for this map-only check.
	run.data.relic_intros.clear()
	run.actor("hero").hp = 60
	run.actor("hero").mp = 17
	run.actor("hero").energy = 61
	game._refresh()
	for id in colors:
		var member = game.ui.find_child("CrewMember_" + id, true, false)
		expect(member is Button, "Roster row exists for " + id)
		if member == null:
			continue
		var portrait: Panel = member.find_child("Portrait", true, false)
		expect(portrait.get_theme_stylebox("panel").bg_color == Color(colors[id])
			and portrait.get_child_count() == 1 and portrait.get_child(0).texture != null,
			"Portrait uses the correct element color and character art for " + id)
		expect(has_label(member, run.actor(id).name), "Character name appears in their portrait row")
		var bars = member.find_children("*", "ProgressBar", true, false)
		var actor = run.actor(id)
		expect(bars.size() == 3 and bars[0].value == actor.hp and bars[0].max_value == actor.hp_max
			and bars[1].value == actor.mp and bars[1].max_value == actor.mp_max and bars[2].value == actor.energy,
			"Personal bars match the actor's health, magic and charge")
	var ember_card: Button = game.ui.find_child("CrewMember_ember", true, false)
	ember_card.pressed.emit()
	expect(game.selected_id == "ember", "Clicking a portrait row selects its character")
	expect(game.view.dolls.keys() == ["hero"], "Only the traveler is drawn on the map")
	expect_stamina(game, 5)
	game._select_cell(next)
	expect(game.move_preview.visible and run.remaining_steps() == 5 and run.actor("hero").position == origin,
		"Selecting a destination only previews the move")
	game._select_cell(next)
	expect(run.actor("hero").position == next and run.actor("ember").position == next
		and game.selected_id == "hero" and run.remaining_steps() == 4, "The traveler leads both characters and spends one step")
	expect_stamina(game, 4)
	await wait_for_arrival(game)
	expect(game.day_transition.get_child_count() == 0, "An ordinary step has no day notice")
	game._close_modal()
	run.data.steps_today = run.STEPS_PER_DAY - 1
	game._refresh()
	expect_stamina(game, 1)
	game._select_cell(origin)
	game._select_cell(origin)
	expect(run.data.day == 2 and has_label(game.ui, "第 1 天") and game.day_transition.get_child_count() == 0,
		"The final step commits the new day while the old date stays visible until arrival")
	expect_stamina(game, 1)
	await wait_for_arrival(game)
	expect(has_label(game.ui, "第 2 天"), "Arrival updates the date")
	expect_stamina(game, 5)
	expect(game.day_transition.has_node("MapNotice") and has_label(game.day_transition, "精力已恢复"),
		"Arrival shows the full map notice")
	await create_timer(1.6).timeout
	expect(game.day_transition.get_child_count() == 0, "The notice dismisses itself")
	game._cell_actions()
	for button in game.modal_layer.find_children("*", "Button", true, false):
		expect(button.text not in ["拆分小队", "结束一天"] and not button.text.begins_with("治疗队友"), "Removed actions stay absent")
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(run.save_path + suffix)
	game.free()
	print("HERO MAP UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
