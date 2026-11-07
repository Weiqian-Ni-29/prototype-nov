extends SceneTree
## UI state fixtures exercise real buttons; legal full journeys live in test_journey.gd.
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/domain/battle.gd")
const Catalog = preload("res://scripts/domain/catalog.gd")
var game: Node
var checks = 0
var failed = false

func _initialize() -> void:
	call_deferred("execute")

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failed = true
		printerr("FAIL: ", label)

func find_button(parent: Node, prefix: String) -> Button:
	for node in parent.get_children():
		if node is Button and str(node.text).begins_with(prefix):
			return node
		var found = find_button(node, prefix)
		if found:
			return found
	return null

func press(prefix: String) -> void:
	var parent = game.modal_layer if game.modal_layer.get_child_count() > 0 else game.ui
	var button = find_button(parent, prefix)
	expect(button != null and not button.disabled, "Enabled battle UI command " + prefix)
	if button and not button.disabled:
		button.pressed.emit()
	await process_frame

func finish_presentation() -> void:
	var started = Time.get_ticks_msec()
	while game.view.is_animating() and Time.get_ticks_msec()-started<10000:
		await process_frame
	expect(not game.view.is_animating(),"Visual event queue completed before the next normal command")
	game.battle_timer = 0
	game._refresh()

func click_at(point: Vector2) -> void:
	for pressed in [true, false]:
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		root.push_input(event, true)

func check_battle_targeting() -> void:
	game.chosen_profession = "guardian"
	game._start_new()
	var run = game.run
	var position = run.data.start
	run.data.tiles[position].terrain = "forest"
	run.data.tiles[position].enemies = ["spider", "swarm"]
	var battle = Combat.new()
	expect(battle.begin(run, {"position": position, "origin": position, "ambush": false, "movers": [], "npc": ""}, ["hero"]).ok,
		"Target selection fixture begins")
	battle.current = "hero"
	game.combat = battle
	game.selected_target = "enemy_0"
	game.battle_timer = 0
	var view = game.view
	view.begin_battle(run, battle)
	game._refresh()
	await process_frame
	var swarm = view.battle_dolls.enemy_1
	var spider = view.battle_dolls.enemy_0
	var point: Vector2 = view.camera.unproject_position(swarm.body.global_position + Vector3.UP * 0.54)
	var motion = InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	await process_frame
	var targeting = view.battle_targeting
	expect(targeting.hovered_id == "enemy_1" and targeting.preview.visible and game.selected_target == "enemy_0", "Hover previews the battlefield target without changing selection")
	var old_spider: Vector3 = spider.global_position
	spider.global_position = swarm.global_position + view.camera.project_ray_normal(point) * 1.25
	expect(view._battle_enemy_at(point) == "enemy_1", "Overlapping enemy volumes favor the one closer to the camera")
	spider.global_position = old_spider
	var unchanged = JSON.stringify(battle.enemies)
	click_at(point)
	expect(game.selected_target == "enemy_1" and targeting.selected_id == "enemy_1" and targeting.selected.visible
		and find_button(game.ui, "◆ 巢鸣蜂群") != null and JSON.stringify(battle.enemies) == unchanged,
		"Clicking the enemy model selects it, synchronizes the card and does not attack")
	var card = game.ui.find_child("EnemyCard_enemy_0", true, false)
	await process_frame
	var label = card.find_children("*", "Label", true, false)[0]
	click_at(label.get_global_rect().get_center())
	expect(game.selected_target == "enemy_0" and targeting.selected_id == "enemy_0", "Clicking the card description selects the same battlefield target")
	click_at(root.get_visible_rect().size * Vector2(0.50, 0.25))
	expect(game.selected_target == "enemy_0", "Clicking empty space keeps the current target")
	game._item_dialog("hero")
	click_at(point)
	expect(game.selected_target == "enemy_0", "A modal blocks battlefield selection")
	game._close_modal()
	var base_point: Vector2 = view.camera.unproject_position(swarm.global_position + Vector3.UP * 0.035)
	click_at(base_point)
	expect(game.selected_target == "enemy_1", "Clicking the enemy's base also selects it")
	if DisplayServer.get_name() != "headless":
		await create_timer(0.26).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://battle-target-selection.png")
	var spider_hp = battle.enemies.enemy_0.hp
	var swarm_hp = battle.enemies.enemy_1.hp
	await press("普攻")
	expect(battle.enemies.enemy_0.hp == spider_hp and battle.enemies.enemy_1.hp < swarm_hp,
		"Single-target attacks damage the selected enemy")
	battle.enemies.enemy_1.hp = 0
	game._after_combat_step()
	expect(game.selected_target == "enemy_0" and targeting.selected_id == "enemy_0", "Defeated targets automatically pass selection to a surviving enemy")
	game.view.end_battle()
	expect(not targeting.selected.visible and not targeting.preview.visible, "Leaving battle clears the markers")

func execute() -> void:
	game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game.run.save_path = "user://test-battle-ui.json"
	game._start_new()
	game.set_process(false)
	var run = game.run
	var p = run.data.start
	for id in Catalog.COMPANIONS:
		run.actor(id).position = p
		run.join_companion(id)
	run.data.tiles[p].enemies = ["lamp_boss", "boar", "boar"]
	var b = Combat.new()
	expect(b.begin(run, {"position": p, "origin": p, "ambush": false, "movers": [], "npc": ""}, ["hero", "cen", "eve", "tide"]).ok, "Battle UI fixture begins")
	game.combat = b
	game.battle_timer = 0
	game.view.begin_battle(run, b)
	game._refresh()
	expect(b.current == "hero", "Fixture begins on protagonist normal action")
	var cards = game.ui.find_children("EnemyCard_*", "PanelContainer", true, false)
	var card_contents_match = cards.all(func(card):
		return (card.find_children("*", "Button", true, false).size() == 1
			and card.find_children("*", "Label", true, false).size() == 1
			and card.find_children("*", "ProgressBar", true, false).size() == 1))
	expect(cards.size() == 3 and card_contents_match, "Each enemy card groups name, status, role and HP bar")
	await press("棘背兽 2号")
	expect(game.selected_target == "enemy_2" and find_button(game.ui, "◆ 棘背兽 2号") != null
		and find_button(game.ui, "棘背兽 1号") != null, "Same-name enemies can be distinguished and selected")
	for command in ["普攻", "巡路连射", "防守", "道具", "换人", "自动 OFF", "自动保林", "撤退", "0% · 归途号令"]:
		var button = find_button(game.ui, command)
		expect(button != null and not button.tooltip_text.is_empty(), "Command has hover help: " + command)
	var skill = find_button(game.ui, "巡路连射")
	expect(skill != null and "8 MP" in skill.tooltip_text and "敌方单体" in skill.tooltip_text
		and "预计基础伤害" in skill.tooltip_text, "Skill hover help explains cost, target and damage preview")
	# Full energy is a deliberate UI fixture. Charging itself is verified by domain checks.
	run.actor("hero").energy = 100
	game._refresh()
	var next_time = b.next_time.hero
	await press("100% · 归途号令")
	expect(run.actor("hero").energy == 0 and b.next_time.hero == next_time, "Ultimate button spends personal energy and preserves normal action")
	await finish_presentation()
	game.battle_timer = 0
	game._refresh()
	var original_item_count = run.actor("hero").inventory.salve
	run.actor("hero").hp = 20
	await press("道具")
	await press("疗伤药")
	expect(run.actor("hero").inventory.salve == original_item_count - 1 and b.current == "hero", "Battle item button consumes item without consuming action")
	await press("用完了，返回")
	await finish_presentation()
	game.battle_timer = 0
	game._refresh()
	await press("换人")
	var lorne_ap = run.actor("lorne").ap
	await press("洛恩")
	expect("lorne" in b.active and "hero" not in b.active and run.actor("lorne").ap == lorne_ap - 2, "Reserve UI swaps same-cell character and charges once")
	expect(b.active.size() == 4, "Swap never exceeds four active fighters")
	await press("自动 OFF")
	expect(b.auto_mode, "Automatic mode button changes decisions only")
	await press("自动保林")
	expect(b.allow_auto_ignite, "Automatic environment policy is explicit and controllable")
	await press("撤退")
	await press("确认")
	expect(game.combat == null and run.data.status == "exploring", "Retreat UI returns to map")
	expect(not run.data.tiles[p].enemies.is_empty(), "Retreat does not erase enemy")
	expect(run.data.rewards.is_empty(), "Retreat never pays victory reward")
	# Saving during a battle is rejected; the original stable checkpoint remains reloadable.
	var restored = load("res://scripts/domain/expedition.gd").new()
	restored.save_path = run.save_path
	expect(restored.load_game().ok and restored.data.pending_battle.is_empty(), "Retreat state is a stable checkpoint")
	await check_battle_targeting()
	await create_timer(0.25).timeout
	game.queue_free()
	await create_timer(0.05).timeout
	print("BATTLE UI: %d checks, failed=%s (ultimate, item, reserve, auto policy, retreat, checkpoint)" % [checks, failed])
	quit(1 if failed else 0)
