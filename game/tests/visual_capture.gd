extends SceneTree
## Presentation fixtures, deliberately separate from no-cheat end-to-end journeys.
const Main = preload("res://scenes/main.tscn")
const Catalog = preload("res://scripts/domain/catalog.gd")
const Combat = preload("res://scripts/domain/battle.gd")
var game: Node
var destination = "user://visual-checks"
var checks = 0
var failed = false

func _initialize() -> void:
	call_deferred("execute")

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failed = true
		printerr("FAIL VISUAL: ", label)

func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	expect(image != null and image.get_width() > 800, "Rendered image " + name)
	if image:
		var error = image.save_png(destination.path_join(name + ".png"))
		expect(error == OK, "Saved image " + name)

func execute() -> void:
	DirAccess.make_dir_recursive_absolute(destination)
	game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game.run.save_path = "user://visual-test-run.json"
	await create_timer(1.0).timeout
	await capture("01-menu")
	game._start_new()
	await create_timer(0.5).timeout
	await capture("02-exploration")
	# Inspect every biome through the exact same battle view used in the playable game.
	game.set_process(false)
	for biome in ["plains", "forest", "mountain", "ruins", "desert", "swamp", "scorched"]:
		game._start_new()
		var run = game.run
		var position = run.actor("hero").position
		run.data.tiles[position].terrain = biome
		run.data.tiles[position].site = ""
		run.data.tiles[position].burning = biome == "forest"
		run.data.tiles[position].wet_until = 3 if biome == "swamp" else 0
		run.data.weather = "rain" if biome == "swamp" else "sun"
		for id in Catalog.COMPANIONS:
			run.actor(id).position = position
			run.join_companion(id)
		run.data.tiles[position].enemies = ["spider", "furnace", "swarm", "canal"]
		var battle = Combat.new()
		var pending = {"position": position, "origin": position, "movers": [], "npc": "", "ambush": false}
		expect(battle.begin(run, pending, ["hero", "grit", "ember", "tide"]).ok, "Battle fixture begins " + biome)
		game.combat = battle
		game.battle_timer = 0
		game.view.begin_battle(run, battle)
		game._refresh()
		await create_timer(0.6).timeout
		expect(game.view.battle_dolls.size() == 8, "Four friends and four distinct foes rendered")
		expect(game.view.battle_dolls.grit.skeleton.get_bone_count() == 7, "Four-legged character has an actual rig")
		expect(game.view.battle_dolls.enemy_0.family == "spider" and game.view.battle_dolls.enemy_2.family == "swarm", "Enemy silhouettes match spider and swarm")
		await capture("battle-" + biome)
		if biome == "plains":
			battle.step_auto()
			game._refresh()
			await capture("battle-friendly-decision")
		var caster = game.view.battle_dolls.ember
		caster.play_action("cast")
		var before_pose = caster.skeleton.get_bone_pose_rotation(caster.bones.arm_r)
		await create_timer(0.22).timeout
		var after_pose = caster.skeleton.get_bone_pose_rotation(caster.bones.arm_r)
		expect(not before_pose.is_equal_approx(after_pose), "Skeletal cast motion changes pose over real frames")
		if biome == "forest":
			await capture("animation-cast-forest")
		game.combat = null
		game.view.end_battle()
	# Seven-person inventory and portrait dialogue layout use explicit presentation fixtures.
	game.run.data.status = "exploring"
	game.run.data.pending_battle = {}
	game._inventory_dialog("hero")
	await capture("inventory-seven-members")
	game._transfer_dialog("hero", "salve")
	await capture("transfer-seven-members")
	game._close_modal()
	game.run.data.tiles[game.run.actor("hero").position].enemies = []
	game._talk("lorne")
	await capture("dialogue-portrait")
	game._close_modal()
	# Instantiate every remaining enemy art family and verify its skeleton in the tree.
	for id in Catalog.ENEMIES:
		var definition = Catalog.ENEMIES[id].duplicate(true)
		definition.id = "visual_" + id
		definition.type = id
		var doll = load("res://scripts/presentation/doll.gd").new()
		game.view.add_child(doll)
		doll.configure(definition)
		expect(doll.skeleton.get_bone_count() >= 6, "Enemy has rig " + id)
		doll.queue_free()
	print("VISUAL FIXTURES: %d checks; failed=%s; captures=%s" % [checks, failed, ProjectSettings.globalize_path(destination)])
	quit(1 if failed else 0)
