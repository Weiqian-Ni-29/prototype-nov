extends SceneTree
## Export the installed engine's own notices, avoiding stale copied license lists.
func _initialize() -> void:
	var folder = "res://assets/licenses"
	DirAccess.make_dir_recursive_absolute(folder)
	var engine_file = FileAccess.open(folder + "/GODOT-LICENSE.txt", FileAccess.WRITE)
	engine_file.store_string(Engine.get_license_text())
	engine_file.close()
	var third_party = FileAccess.open(folder + "/GODOT-THIRD-PARTY.txt", FileAccess.WRITE)
	third_party.store_string("Godot " + Engine.get_version_info().string + "\n\n")
	for component in Engine.get_copyright_info():
		third_party.store_string(component.name + "\n")
		for part in component.parts:
			third_party.store_string(JSON.stringify(part, "  ") + "\n")
	for license_name in Engine.get_license_info():
		third_party.store_string("\n===== " + license_name + " =====\n" + Engine.get_license_info()[license_name] + "\n")
	third_party.close()
	var normalized = FileAccess.get_file_as_string(folder + "/GODOT-THIRD-PARTY.txt").strip_edges(false, true) + "\n"
	third_party = FileAccess.open(folder + "/GODOT-THIRD-PARTY.txt", FileAccess.WRITE)
	third_party.store_string(normalized)
	third_party.close()
	print("Engine notices exported from ", Engine.get_version_info().string)
	quit()
