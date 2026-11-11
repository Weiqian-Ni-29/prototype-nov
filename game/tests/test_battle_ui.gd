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

func check_marker_height() -> void:
	game._start_new()
	var run = game.run
	var position = run.data.start
	run.data.tiles[position].terrain = "swamp"
	run.data.tiles[position].enemies = ["lurker", "apothecary"]
	var battle = Combat.new()
	expect(battle.begin(run, {"position": position, "origin": position, "ambush": false, "movers": [], "npc": ""}, ["hero"]).ok,
		"Marker fixture uses the reported swamp encounter")
	battle.current = "hero"
	game.combat = battle
	game.selected_target = "enemy_0"
	game.battle_timer = 0
	var view = game.view
	view.begin_battle(run, battle)
	game._refresh()
	game._select_battle_target("enemy_1")
	await process_frame
	var doll = view.battle_dolls.enemy_1
	var targeting = view.battle_targeting
	var screen_up: Vector3 = view.camera.global_basis.y
	var first_height: float = screen_up.dot(targeting.arrow.global_position)
	var initial_top: float = targeting._silhouette_top(doll, screen_up)
	expect(targeting.arrow.no_depth_test and first_height - initial_top > 0.29,
		"Apothecary arrow clears the entire silhouette")
	if DisplayServer.get_name() != "headless":
		await create_timer(0.26).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://battle-target-marker-height.png")
	doll.body.scale *= 1.45
	view._update_battle_targets()
	var taller_top: float = targeting._silhouette_top(doll, screen_up)
	var taller_height: float = screen_up.dot(targeting.arrow.global_position)
	expect(taller_top > initial_top + 0.30 and taller_height > first_height + 0.30,
		"The same selected target updates its marker when its model grows")
	var skeleton: Skeleton3D = doll.skeleton
	var head = doll.bones.head
	var rest_position = skeleton.get_bone_pose_position(head)
	doll.rigged.animator.pause()
	skeleton.set_bone_pose_position(head, rest_position + Vector3.UP * 0.8)
	skeleton.force_update_all_bone_transforms()
	view._update_battle_targets()
	expect(screen_up.dot(targeting.arrow.global_position) > taller_height + 0.10,
		"Changing a bone pose updates the selected marker independently of model scale")
	game.view.end_battle()

func check_victory_relic_text() -> void:
	game._start_new()
	var run = game.run
	var relic_name: String = load("res://scripts/domain/relic_catalog.gd").DATA.opening_flint.name
	for duplicate in [false, true]:
		run.data.pending_victory = {"enemies": 1, "salve_receiver": "", "relic": "opening_flint",
			"relic_duplicate": duplicate, "coins": 0, "members": ["hero"], "revived": []}
		var before = run.data.duplicate(true)
		game._victory_dialog()
		await process_frame
		var labels = game.modal_layer.find_children("*", "Label", true, false)
		var expected = "再次获得遗器" if duplicate else "发现遗器"
		expect(labels.any(func(label): return label.text == relic_name)
			and labels.any(func(label): return label.text == expected), "Victory distinguishes new and repeated relics in plain language")
		expect(not labels.any(func(label): return "副本" in label.text), "Victory does not describe a repeated relic as a copy")
		expect(run.data == before, "Reading the victory reward does not grant it again")
		game._close_modal()

func check_shield_badges(battle: RefCounted) -> void:
	await process_frame
	var hero = battle.unit("hero")
	var previous_hp = hero.hp
	var status: Control = game.ui.find_child("BattleStatus_hero", true, false)
	var original_rect = status.get_global_rect()
	expect(game.ui.find_child("ShieldBadge_hero", true, false) == null, "An unshielded fighter has no badge")
	battle.items.shield_gain(battle, "hero", 60)
	game._refresh()
	await process_frame
	var badge: TextureRect = game.ui.find_child("ShieldBadge_hero", true, false)
	expect(badge != null and badge.get_node("Amount").text == "60", "Gaining shield displays its remaining amount")
	battle.items.shield_gain(battle, "hero", 190)
	game._refresh()
	await process_frame
	badge = game.ui.find_child("ShieldBadge_hero", true, false)
	if badge != null:
		var amount: Label = badge.get_node("Amount")
		var tide_badge: TextureRect = game.ui.find_child("ShieldBadge_tide", true, false)
		status = game.ui.find_child("BattleStatus_hero", true, false)
		expect(amount.text == "250" and amount.get_minimum_size().x <= badge.size.x, "Stacked three-digit shield fits inside the badge")
		expect(tide_badge != null and tide_badge.size == badge.size
			and is_equal_approx(badge.get_global_rect().end.x, status.get_global_rect().end.x)
			and is_equal_approx(badge.get_global_rect().end.x, tide_badge.get_global_rect().end.x)
			and status.get_global_rect() == original_rect,
			"Shield badges keep a fixed size and sit at the right end of each status row")
	else:
		expect(false, "Stacking shield keeps the badge visible")
	battle._hurt("hero", 7)
	game._refresh()
	badge = game.ui.find_child("ShieldBadge_hero", true, false)
	expect(badge != null and badge.get_node("Amount").text == "243", "Absorbed damage updates the badge")
	battle._hurt("hero", 243)
	game._refresh()
	await process_frame
	status = game.ui.find_child("BattleStatus_hero", true, false)
	expect(game.ui.find_child("ShieldBadge_hero", true, false) == null and hero.hp == previous_hp,
		"Depleted shield absorbs its last damage and removes the badge")
	expect(status.get_global_rect() == original_rect, "Hiding the badge preserves the status row position and height")

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
	var tide = run.actor("tide")
	tide.hp = 71
	tide.mp = 42
	tide.energy = 63
	tide.shield = 15
	game.view.begin_battle(run, b)
	game._refresh()
	expect(b.current == "hero", "Fixture begins on protagonist normal action")
	expect(not game.ui.find_children("*", "Label", true, false).any(func(label): return label.text == "旅途记录"),
		"The battle HUD has no travel log banner")
	var party_cards = game.ui.find_children("BattleMember_*", "PanelContainer", true, false)
	expect(party_cards.size() == 4, "Four active fighters have status cards")
	var tide_card = game.ui.find_child("BattleMember_tide", true, false)
	expect(tide_card != null, "Battle sidebar contains the water companion")
	if tide_card != null:
		var meters = tide_card.find_children("*", "ProgressBar", true, false)
		expect(meters.size() == 3 and meters[0].value == tide.hp and meters[0].max_value == tide.hp_max
			and meters[1].value == tide.mp and meters[1].max_value == tide.mp_max
			and meters[2].value == tide.energy and meters[2].max_value == Catalog.ENERGY_MAX,
			"Battle status bars show the fighter's HP, MP and charge")
		expect(meters.map(func(bar): return bar.get_parent().get_child(1).text) == [
			"%d/%d" % [tide.hp, tide.hp_max], "%d/%d" % [tide.mp, tide.mp_max],
			"%d/%d" % [tide.energy, Catalog.ENERGY_MAX],
		], "Battle bars show exact current and maximum values")
		var colors = ["e16562", "65a6e6", "eea353"]
		for i in mini(meters.size(), colors.size()):
			expect(meters[i].get_theme_stylebox("fill").bg_color == Color(colors[i]), "Status bar uses the shared color")
		var portrait = tide_card.find_child("Portrait", true, false)
		expect(portrait != null and portrait.get_theme_stylebox("panel").bg_color == Color("24536e"),
			"Battle portraits use the same element background as the exploration sidebar")
		var badge = tide_card.find_child("ShieldBadge_tide", true, false)
		expect(badge != null and badge.get_node("Amount").text == "15", "Shield amount appears inside the fighter's badge")
	await check_shield_badges(b)
	var uncharged = find_button(game.ui, "终结技 · 落石")
	expect(uncharged != null and uncharged.disabled, "Ultimate button is disabled before charge is full")
	var cards = game.ui.find_children("EnemyCard_*", "PanelContainer", true, false)
	var card_contents_match = cards.all(func(card):
		return (card.find_children("*", "Button", true, false).size() == 1
			and card.find_children("*", "Label", true, false).size() == 1
			and card.find_children("*", "ProgressBar", true, false).size() == 1))
	expect(cards.size() == 3 and card_contents_match, "Each enemy card groups name, status, role and HP bar")
	await press("棘背兽 2号")
	expect(game.selected_target == "enemy_2" and find_button(game.ui, "◆ 棘背兽 2号") != null
		and find_button(game.ui, "棘背兽 1号") != null, "Same-name enemies can be distinguished and selected")
	for command in ["普攻", "重压", "防守", "道具", "换人", "自动战斗", "撤退", "终结技 · 落石"]:
		var button = find_button(game.ui, command)
		expect(button != null and not button.tooltip_text.is_empty(), "Command has hover help: " + command)
	var auto = find_button(game.ui, "自动战斗")
	var items = find_button(game.ui, "道具")
	var guard = find_button(game.ui, "防守")
	var enemy_card = game.ui.find_child("EnemyCard_enemy_2", true, false) as Control
	expect(auto.text == "自动战斗" and auto.toggle_mode and not auto.button_pressed,
		"Automatic battle uses a fixed label and starts unhighlighted")
	expect(auto.get_parent() == items.get_parent() and auto.position.y == items.position.y
		and auto.get_global_rect().position.x > root.get_visible_rect().get_center().x
		and items.get_global_rect().end.x < enemy_card.get_global_rect().position.x
		and items.get_global_rect().end.y < guard.get_global_rect().position.y,
		"Automatic battle and items share the upper-right row beside the enemy lineup")
	expect(find_button(game.ui, "自动保林") == null and find_button(game.ui, "自动可点火") == null,
		"Battle has no separate ignition policy button")
	var skill = find_button(game.ui, "重压")
	expect(skill != null and "8 MP" in skill.tooltip_text and "敌方单体" in skill.tooltip_text
		and "预计基础伤害" in skill.tooltip_text, "Skill hover help explains cost, target and damage preview")
	var hero = run.actor("hero")
	var original_mp = hero.mp
	hero.mp = 0
	await press("重压")
	var action_panel = find_button(game.ui, "普攻").get_parent().get_parent()
	expect(action_panel.find_children("*", "Label", true, false).any(func(label): return "魔力不足" in label.text),
		"Invalid commands report the error inside the action panel")
	hero.mp = original_mp
	await finish_presentation()
	# Full energy is a deliberate UI fixture. Charging itself is verified by domain checks.
	run.actor("hero").energy = 100
	game._refresh()
	var next_time = b.next_time.hero
	await press("终结技 · 落石")
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
	var steps = run.remaining_steps()
	await press("洛恩")
	expect("lorne" in b.active and "hero" not in b.active and run.remaining_steps() == steps, "Reserve UI swaps companion without spending movement")
	expect(b.active.size() == 4, "Swap never exceeds four active fighters")
	await press("自动战斗")
	expect(b.auto_mode and find_button(game.ui, "自动战斗").button_pressed,
		"Automatic mode stays highlighted after the battle UI refreshes")
	await press("自动战斗")
	expect(not b.auto_mode and not find_button(game.ui, "自动战斗").button_pressed,
		"Turning off automatic mode clears the highlight")
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
	await check_marker_height()
	await check_victory_relic_text()
	await create_timer(0.25).timeout
	game.queue_free()
	await create_timer(0.05).timeout
	print("BATTLE UI: %d checks, failed=%s (ultimate, item, reserve, auto toggle, retreat, checkpoint)" % [checks, failed])
	quit(1 if failed else 0)
