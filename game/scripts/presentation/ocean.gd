extends Node3D
## Deep water joins the shoreline mesh outside the navigable grid.
const Hex = preload("res://scripts/domain/hex_map.gd")
const Board = preload("res://scripts/presentation/board_surface.gd")
var sea_cells: Array[String] = []

func build(tiles: Dictionary) -> void:
	for child in get_children():
		child.free()
	sea_cells.clear()
	var radius = 0
	for id in tiles:
		radius = maxi(radius, Hex.distance(Hex.coord(id), Vector2i.ZERO))
	for q in range(-radius - 5, radius + 6):
		for r in range(-radius - 5, radius + 6):
			var coord = Vector2i(q, r)
			var id = Hex.key(coord)
			if Hex.distance(coord, Vector2i.ZERO) <= radius + 5 and not tiles.has(id):
				sea_cells.append(id)
	var distant = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(600, 600)
	distant.mesh = plane
	distant.position.y = Board.WATER_LEVEL - 0.03
	distant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material = ShaderMaterial.new()
	material.shader = Board.GROUND
	material.set_shader_parameter("deep_ocean", true)
	distant.material_override = material
	add_child(distant)
