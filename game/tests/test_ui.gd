extends SceneTree
const Main = preload("res://scenes/main.tscn")
const Hex = preload("res://scripts/domain/hex_map.gd")
var game: Node
var checks = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("execute")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)

func find_button(parent: Node, prefix: String) -> Button:
	for child in parent.get_children():
		if child is Button and str(child.text).begins_with(prefix):
			return child
		var found = find_button(child, prefix)
		if found != null:
			return found
	return null

func press(prefix: String) -> void:
	var button = find_button(game.modal_layer if game.modal_layer.get_child_count() > 0 else game.ui, prefix)
	expect(button != null, "UI button exists: " + prefix)
	if button != null:
		expect(not button.disabled, "UI button enabled: " + prefix)
		if not button.disabled:
			button.pressed.emit()
	await process_frame

func execute() -> void:
	game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game.run.save_path = "user://test-ui.json"
	await press("◇ 守灯卫")
	expect(game.chosen_profession == "guardian", "Profession selection updates")
	await press("开始远征")
	expect(game.run.actor("hero").hp_max == 145 and game.run.actor("hero").ap == 5, "Profession affects actual character")
	var path = Hex.path(game.run.data.tiles, game.run.actor("hero").position, game.run.actor("lorne").position)
	var cost = 0
	for destination in path.slice(1):
		cost += game.run.move_cost("hero", destination)
		game.view.cell_clicked.emit(destination)
		await process_frame
		await press("前往此格")
	expect(game.run.actor("hero").ap == 5 - cost, "Native UI movement pays exact AP")
	await press("交谈 / 个人故事")
	await press("邀请同行")
	expect(game.run.actor("lorne").joined and game.run.actor("lorne").ap == 10, "Native UI companion joins with individual AP")
	expect(game.run.actor("hero").ap == 5 - cost, "Native UI recruitment free")
	await press("接过原信")
	expect(game.run.actor("hero").inventory.get("Q-L", 0) == 1 and game.run.actor("lorne").inventory.get("Q-L", 0) == 0, "Native UI original letter transferred once")
	await press("结束交谈")
	await press("结束一天")
	await press("确认")
	expect(game.run.data.day == 2 and game.run.actor("hero").ap == 5 and game.run.actor("lorne").ap == 10, "Native UI daily settlement")
	await press("主菜单")
	await press("继续上次远征")
	expect(game.run.data.day == 2 and game.run.actor("lorne").joined, "Native UI continue restores state")
	await press("个人背包与装备")
	var salves = game.run.actor("hero").inventory.salve
	# Loaded JSON may order inventory differently; choose the visible item label, not row zero.
	var item_button: Button
	for label in game.modal_layer.find_children("*", "Label", true, false):
		if label.text.begins_with("疗伤药 ×"):
			item_button = find_button(label.get_parent(), "交接")
	expect(item_button != null and not item_button.disabled, "Salve handoff action exists")
	if item_button != null: item_button.pressed.emit()
	await process_frame
	expect(find_button(game.modal_layer, "交给洛恩") != null, "Same-cell inventory transfer exposed")
	await press("交给洛恩")
	expect(game.run.actor("hero").inventory.salve == salves - 1 and game.run.actor("lorne").inventory.salve == 2, "Native inventory handoff changes both real owners")
	await press("关闭")
	await press("旅途手记")
	expect(find_button(game.modal_layer, "合上手记") != null, "Journal opens")
	await press("合上手记")
	# Allow the last short audio cue to finish before testing scene teardown.
	await create_timer(0.25).timeout
	print("UI INTEGRATION: %d checks, %d failures (menu, movement, dialogue, recruitment, original item, day, continue, inventory, journal)" % [checks, failures.size()])
	game.queue_free()
	await create_timer(0.05).timeout
	quit(0 if failures.is_empty() else 1)
