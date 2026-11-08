extends SceneTree
const ExpeditionModel = preload("res://scripts/domain/expedition.gd")
const Hex = preload("res://scripts/domain/hex_map.gd")
var checks = 0
var failures = 0
func _initialize():
	call_deferred("execute")
func expect(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func execute():
	var run = ExpeditionModel.new()
	run.new_run(41, "wayfarer")
	var start = run.actor("hero").position
	for id in ["lorne", "grit", "ember"]:
		run.actor(id).position = start
		expect(run.join_companion(id).ok, "recruit companion")
	expect(run.squad_groups().size() == 1, "recruitment joins same-cell squad")
	var original = run.actor("hero").squad_id
	expect(not run.split_squad([]).ok, "empty split rejected")
	expect(not run.split_squad(["hero", "hero"]).ok, "duplicate split rejected")
	expect(not run.split_squad(run.joined_ids()).ok, "whole squad split rejected")
	expect(run.split_squad(["lorne", "grit"]).ok, "multi-member split")
	var split = run.actor("lorne").squad_id
	expect(original != split, "new identity")
	expect(run.squad_members("hero") == ["hero", "ember"], "remaining squad preserved")
	expect(run.squad_groups().size() == 2 and run.squad_groups().size() == 2, "refresh preserves co-located splits")
	expect(not run.split_squad(["hero", "lorne"]).ok, "cross-squad split rejected")
	var path = "user://test_squads.json"
	expect(run.save_game(path).ok, "save splits")
	var loaded = ExpeditionModel.new()
	expect(loaded.load_game(path).ok, "load splits")
	expect(loaded.squad_groups().size() == 2 and loaded.actor("lorne").squad_id == split, "persisted identities and colors")
	var destination = ""
	for cell in Hex.neighbors(start, run.data.tiles):
		if Hex.is_land(run.data.tiles, cell):
			destination = cell
			break
	run.data.tiles[start].enemies = []
	run.data.tiles[destination].enemies = []
	for id in run.joined_ids(): run.actor(id).ap = run.actor(id).ap_max
	expect(run.move(["lorne", "grit"], destination).ok, "move split squad")
	expect(run.actor("lorne").squad_id == split and run.actor("hero").squad_id == original, "moving entire squad preserves colors")
	expect(run.move(["lorne", "grit"], start).ok, "return to occupied cell")
	expect(run.squad_groups().size() == 1 and run.actor("lorne").squad_id == original, "arrival merges into resident identity")
	expect(run.move(["ember"], destination).ok, "subset move")
	expect(run.squad_groups().size() == 2 and run.actor("ember").squad_id != original, "subset detaches new identity")
	# Returning to a cell with several intentionally separated squads merges all.
	expect(run.split_squad(["grit"]).ok, "split resident squad while another travels")
	for id in run.joined_ids(): run.actor(id).ap = run.actor(id).ap_max
	expect(run.move(["ember"], start).ok and run.squad_groups().size() == 1, "arrival merges multiple resident squads")
	for id in run.joined_ids(): run.actor(id).ap = run.actor(id).ap_max
	run.move(["ember"], destination)
	run.data.pending_battle = {"position": start}
	expect(not run.split_squad(["grit"]).ok, "pending battle blocks splitting")
	run.data.pending_battle = {}
	# Legacy v2 files had no squad extension: migrate by current occupied cell.
	var legacy = run.data.duplicate(true)
	legacy.erase("squad_colors")
	legacy.erase("next_squad_id")
	for id in legacy.actors: legacy.actors[id].erase("squad_id")
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	expect(loaded.load_game(path).ok and loaded.squad_groups().size() == 2, "legacy migration groups by cell")
	# External relocations (e.g. retreat) split spatially, never auto-merge.
	loaded.actor("grit").position = destination
	expect(loaded.squad_groups().size() == 3, "external relocation reconciles identity")
	loaded.actor("grit").position = start
	expect(loaded.squad_groups().size() == 3, "co-location does not erase explicit identities")
	var invalid = run.data.duplicate(true)
	invalid.squad_colors[original] = -1
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(invalid))
	file.close()
	expect(not loaded.load_game(path).ok, "malformed squad save rejected")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".bak")
	print("SQUADS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
