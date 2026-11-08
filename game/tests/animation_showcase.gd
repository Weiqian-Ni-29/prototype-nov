extends SceneTree
## Reproducible presentation fixture, recorded with --write-movie; never a gameplay journey.
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/domain/battle.gd")
var game: Node
var label: Label
var variant = "after"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): variant = arg.trim_prefix("--label=")
	call_deferred("execute")

func snapshot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://animation-" + variant + "-" + name + ".png")

func execute() -> void:
	game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game.run.save_path = "user://animation-showcase.json"
	game._start_new()
	game.run.actor("hero").skill = "guard_all"
	game.set_process(false)
	var r = game.run
	var position = r.actor("hero").position
	for id in ["cen", "eve", "grit"]:
		r.actor(id).position = position
		r.join_companion(id)
	r.data.tiles[position].terrain = "forest"
	r.data.tiles[position].enemies = []
	game._refresh()
	label = Label.new()
	label.position = Vector2(310, 115)
	label.add_theme_font_size_override("font_size", 22)
	game.ui.add_child(label)
	label.text = "探索样板 · 近战 / 弓手 / 医者 / 巨狼"
	await create_timer(1.0).timeout
	await snapshot("map")
	for id in ["hero", "cen", "eve", "grit"]:
		game.view.dolls[id].play_action("walk")
	await create_timer(1.5).timeout
	r.data.tiles[position].enemies = ["boar", "archer", "spider", "swarm"]
	var b = Combat.new()
	b.begin(r, {"position":position, "origin":position, "movers":[], "npc":"", "ambush":false}, ["hero","cen","eve","grit"])
	game.combat = b
	game.view.begin_battle(r, b)
	game._refresh()
	label = Label.new()
	label.position = Vector2(310,115)
	label.add_theme_font_size_override("font_size", 22)
	game.ui.add_child(label)
	for kind in ["idle", "walk", "attack", "cast", "guard", "ultimate", "hit", "down", "recover"]:
		label.text = "四类实机样板 · " + kind
		for id in ["hero", "cen", "eve", "grit"]:
			var doll = game.view.battle_dolls[id]
			if kind == "down": doll.set_down(true)
			elif kind == "recover": doll.set_down(false)
			else: doll.play_action(kind)
		await create_timer(0.35).timeout
		if kind in ["idle", "attack", "cast", "down"]: await snapshot(kind)
		await create_timer(1.0).timeout
	print("SHOWCASE COMPLETE ", variant)
	game.queue_free()
	await create_timer(0.2).timeout
	quit()
