extends RefCounted
## A shared, world-space height and pigment field. Unknown cells use a neutral apron.
const Hex = preload("res://scripts/domain/hex_map.gd")
const Catalog = preload("res://scripts/domain/catalog.gd")
const GROUND = preload("res://scripts/presentation/board_ground.gdshader")
const FOG = preload("res://scripts/presentation/exploration_fog.gdshader")
const WATER_LEVEL = -0.12
const SUBDIVISIONS = 6
const LAND_LEVELS = {
	"plains": 0.22, "forest": 0.26, "mountain": 0.48, "ruins": 0.29,
	"desert": 0.29, "swamp": 0.072, "scorched": 0.26,
}
const UNKNOWN = ["unknown", 0.08, Color("788880")]
const SEA = ["sea", -0.83, Color("8e9f84")]
const LAKE = ["lake", -0.72, Color("9b9c72")]
var tiles: Dictionary
var profiles: Dictionary
var origins: Dictionary
var adjacent: Dictionary
var cached_samples: Dictionary
var triangles: Dictionary
var fog_mesh: ArrayMesh
var template: PackedVector3Array
var shore_cells: Array[String]
var seed_offset: Vector2
var noise := FastNoiseLite.new()

func prepare(board: Dictionary, seed_value: int) -> void:
	tiles = board
	noise.seed = seed_value & 0x7fffffff
	noise.frequency = 1.0
	noise.fractal_octaves = 2
	seed_offset = Vector2(seed_value & 255, (seed_value >> 8) & 255) * 0.017
	shore_cells.clear()
	origins.clear()
	adjacent.clear()
	var coast: Dictionary = {}
	for id in tiles:
		for next in _around(id):
			if not tiles.has(next):
				coast[next] = true
	shore_cells.assign(coast.keys())
	if not template.is_empty():
		return
	for side in range(6):
		var a = corner(side) / SUBDIVISIONS
		var b = corner(side + 1) / SUBDIVISIONS
		for i in range(SUBDIVISIONS):
			for j in range(SUBDIVISIONS - i):
				var point = a * i + b * j
				template.append_array(PackedVector3Array([point, point + a, point + b]))
				if i + j < SUBDIVISIONS - 1:
					template.append_array(PackedVector3Array([point + a, point + a + b, point + b]))

func rebuild(explored: Dictionary) -> ArrayMesh:
	profiles.clear()
	cached_samples.clear()
	triangles.clear()
	for id in explored:
		var terrain: String = tiles[id].terrain
		profiles[id] = LAKE if terrain == "lake" else [terrain,
			LAND_LEVELS[terrain] + clampf(float(tiles[id].height), 0.0, 0.10), Color(Catalog.TERRAIN[terrain].color)]
	var tool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for id in explored:
		_add_cell(tool, id, true)
	for id in shore_cells:
		_add_cell(tool, id, false)
	var clouds = SurfaceTool.new()
	clouds.begin(Mesh.PRIMITIVE_TRIANGLES)
	for id in tiles:
		if not explored.has(id):
			_add_fog(clouds, id)
	fog_mesh = null if explored.size() == tiles.size() else clouds.commit()
	tool.index()
	tool.generate_normals()
	return tool.commit()

static func corner(side: int) -> Vector3:
	var angle = PI / 6.0 + TAU * (side % 6) / 6.0
	return Vector3(cos(angle), 0.0, sin(angle))

func _around(id: String) -> Array[String]:
	if not adjacent.has(id):
		var result: Array[String] = [id]
		var coord = Hex.coord(id)
		for direction in Hex.DIRECTIONS:
			result.append(Hex.key(coord + direction))
		adjacent[id] = result
	return adjacent[id]

func _origin(id: String) -> Vector3:
	if not origins.has(id):
		origins[id] = Hex.world(id)
	return origins[id]

func sample(point: Vector3) -> Array:
	# Quantizing world positions makes both sides of every generated seam identical.
	var key = Vector2i(roundi(point.x * 10000), roundi(point.z * 10000))
	if cached_samples.has(key):
		return cached_samples[key]
	point = Vector3(key.x * 0.0001, 0.0, key.y * 0.0001)
	var height = 0.0
	var pigment = Vector3.ZERO
	var total = 0.0
	var mountain = 0.0
	var sand = 0.0
	var ruins = 0.0
	var marsh = 0.0
	var lake = 0.0
	var sea = 0.0
	var unknown = 0.0
	for id in _around(Hex.cell_at(point)):
		var distance_sq = _origin(id).distance_squared_to(point)
		var weight = maxf(0.0, 1.0 - distance_sq / 2.19)
		if weight == 0.0:
			continue
		weight *= weight
		var profile = profiles.get(id, UNKNOWN if tiles.has(id) else SEA)
		var terrain: String = profile[0]
		var color: Color = profile[2]
		total += weight
		height += float(profile[1]) * weight
		pigment += Vector3(color.r, color.g, color.b) * weight
		match terrain:
			"mountain": mountain += weight
			"desert": sand += weight
			"ruins": ruins += weight
			"swamp": marsh += weight
			"lake": lake += weight
			"sea": sea += weight
			"unknown": unknown += weight
	height /= total
	pigment /= total
	mountain /= total
	sand /= total
	marsh /= total
	ruins /= total
	var p = Vector2(point.x, point.z) + seed_offset
	var rolling = noise.get_noise_2dv(p * 0.68)
	var chips = noise.get_noise_2dv(p * 3.7)
	var ridge = pow(1.0 - absf(noise.get_noise_2dv(Vector2(p.x * 0.8 + p.y * 0.44, p.y * 1.6))), 3.0)
	var dune = sin(p.dot(Vector2(1.35, 2.7)) + rolling * 3.3)
	height += (rolling * 0.10 + chips * 0.035) * (1.0 - (sea + lake + unknown) / total)
	height += mountain * mountain * (0.36 + ridge * 0.91 + chips * 0.19)
	height += sand * (0.065 + dune * 0.14)
	var channels = 1.0 - absf(noise.get_noise_2dv(Vector2(p.x * 0.43 + p.y * 0.30, p.y * 0.71)))
	height -= marsh * marsh * smoothstep(0.51, 0.97, channels) * 0.27
	var stone = clampf(mountain + ruins * 0.65, 0.0, 1.0)
	var tint = Color(pigment.x, pigment.y, pigment.z, lake / maxf(lake + sea, 0.0001))
	var result = [Vector3(point.x, maxf(WATER_LEVEL, height), point.z),
		tint, Vector2(sand, stone), Vector2(marsh, WATER_LEVEL - height)]
	cached_samples[key] = result
	return result

func height_at(point: Vector3) -> float:
	var id = Hex.cell_at(point)
	if not profiles.has(id):
		return sample(point)[0].y
	var center = _origin(id)
	var local = point - center
	var angle = fposmod(atan2(local.z, local.x) - PI / 6.0, TAU)
	var side = floori(angle / (TAU / 6.0))
	var a = corner(side) / SUBDIVISIONS
	var b = corner(side + 1) / SUBDIVISIONS
	var area = a.x * b.z - a.z * b.x
	var u = maxf(0.0, (local.x * b.z - local.z * b.x) / area)
	var v = maxf(0.0, (a.x * local.z - a.z * local.x) / area)
	var limit = minf(1.0, (SUBDIVISIONS - 0.0001) / maxf(0.0001, u + v))
	u *= limit
	v *= limit
	var corner_point = center + a * floorf(u) + b * floorf(v)
	u = fposmod(u, 1.0)
	v = fposmod(v, 1.0)
	var a_height: float = sample(corner_point + a)[0].y
	var b_height: float = sample(corner_point + b)[0].y
	if u + v <= 1.0:
		return float(sample(corner_point)[0].y) * (1.0 - u - v) + a_height * u + b_height * v
	return float(sample(corner_point + a + b)[0].y) * (u + v - 1.0) + a_height * (1.0 - v) + b_height * (1.0 - u)

func _add_cell(tool: SurfaceTool, id: String, pickable: bool) -> void:
	var center = _origin(id)
	var vertices := PackedVector3Array()
	for offset in template:
		var surface = sample(center + offset)
		tool.set_color(surface[1])
		tool.set_uv(surface[2])
		tool.set_uv2(surface[3])
		tool.add_vertex(surface[0])
		if pickable:
			vertices.append(surface[0])
	if pickable:
		triangles[id] = vertices

func _add_fog(tool: SurfaceTool, id: String) -> void:
	var center = _origin(id)
	var touching_known = false
	for next in _around(id):
		if not tiles.has(next) or profiles.has(next):
			touching_known = true
			break
	for offset in template:
		var point = center + offset
		point.y = (float(sample(point)[0].y) if touching_known else float(UNKNOWN[1])) + 0.015
		tool.set_uv(Vector2(offset.x, offset.z) * 0.5 + Vector2.ONE * 0.5)
		tool.add_vertex(point)

func pick(origin: Vector3, direction: Vector3) -> String:
	var fog_hit = Plane(Vector3.UP, 0.16).intersects_ray(origin, direction)
	if fog_hit == null:
		return ""
	var fog_id = Hex.closest(fog_hit, tiles)
	var closest_id = fog_id if not profiles.has(fog_id) else ""
	var nearest = origin.distance_squared_to(fog_hit) if not closest_id.is_empty() else INF
	# Ray projection can cross a second cell on steep slopes.
	var candidates: Dictionary = {}
	for altitude in [WATER_LEVEL, 0.65, 1.4, 2.15]:
		var point = Plane(Vector3.UP, altitude).intersects_ray(origin, direction)
		if point == null:
			continue
		for id in _around(Hex.cell_at(point)):
			if triangles.has(id):
				candidates[id] = true
	for id in candidates:
		var vertices: PackedVector3Array = triangles[id]
		for index in range(0, vertices.size(), 3):
			var hit = Geometry3D.ray_intersects_triangle(origin, direction, vertices[index], vertices[index + 1], vertices[index + 2])
			if hit != null and origin.distance_squared_to(hit) < nearest:
				nearest = origin.distance_squared_to(hit)
				closest_id = id
	return closest_id

func outline(id: String, known: bool) -> ArrayMesh:
	var tool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center = _origin(id)
	for side in range(6):
		for step in range(SUBDIVISIONS):
			var first = corner(side).lerp(corner(side + 1), float(step) / SUBDIVISIONS)
			var second = corner(side).lerp(corner(side + 1), float(step + 1) / SUBDIVISIONS)
			for offset in [first * 0.956, first * 0.990, second * 0.990, first * 0.956, second * 0.990, second * 0.956]:
				var point = center + offset
				point.y = height_at(point) + (0.045 if known else 0.085)
				tool.add_vertex(point)
	tool.generate_normals()
	return tool.commit()
