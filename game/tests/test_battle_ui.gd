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
	run.data.tiles[p].enemies = ["lamp_boss"]
	var b = Combat.new()
	expect(b.begin(run, {"position": p, "origin": p, "ambush": false, "movers": [], "npc": ""}, ["hero", "cen", "eve", "tide"]).ok, "Battle UI fixture begins")
	game.combat = b
	game.battle_timer = 0
	game.view.begin_battle(run, b)
	game._refresh()
	expect(b.current == "hero", "Fixture begins on protagonist normal action")
	# Full energy is a deliberate UI fixture. Charging itself is verified by domain checks.
	run.actor("hero").energy = 100
	game._refresh()
	var next_time = b.next_time.hero
	await press("100% · 归途号令")
	expect(run.actor("hero").energy == 0 and b.next_time.hero == next_time, "Ultimate button spends personal energy and preserves normal action")
	game.battle_timer = 0
	game._refresh()
	var original_item_count = run.actor("hero").inventory.salve
	run.actor("hero").hp = 20
	await press("物资")
	await press("疗伤药")
	expect(run.actor("hero").inventory.salve == original_item_count - 1 and b.current == "hero", "Battle item button consumes item without consuming action")
	await press("用完了，返回")
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
	await create_timer(0.25).timeout
	game.queue_free()
	await create_timer(0.05).timeout
	print("BATTLE UI: %d checks, failed=%s (ultimate, item, reserve, auto policy, retreat, checkpoint)" % [checks, failed])
	quit(1 if failed else 0)
