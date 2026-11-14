extends RefCounted
## A shared, world-space height and pigment field. Unknown cells use a neutral apron.
const Hex = preload("res://scripts/domain/hex_map.gd")
const Catalog = preload("res://scripts/domain/catalog.gd")
const GROUND = preload("res://scripts/presentation/board_ground.gdshader")
const FOG = preload("res://scripts/presentation/exploration_fog.gdshader")
const FRINGE = preload("res://scripts/presentation/fog_fringe.gdshader")
const REVEAL = preload("res://scripts/presentation/fog_reveal.gdshader")
enum SurfaceLayer { GROUND, FOG, FRINGE, REVEAL }
const WATER_LEVEL = -0.12
const SUBDIVISIONS = 6
const CHUNK_SIZE = 3
const BLEND_RADIUS_SQUARED = 2.19
const LAND_LEVELS = {
	"plains": 0.22, "forest": 0.26, "mountain": 0.48, "ruins": 0.29,
	"desert": 0.29, "swamp": 0.072,
}
const UNKNOWN = ["unknown", 0.08, Color("788880")]
const SEA = ["sea", -0.83, Color("8e9f84")]
const LAKE = ["lake", -0.72, Color("9b9c72")]
var tiles: Dictionary
var profiles: Dictionary
var origins: Dictionary
var adjacent: Dictionary
var cached_samples: Dictionary
var sample_cells: Dictionary
var cached_normals: Dictionary
var triangles: Dictionary
var template: PackedVector3Array
var template_indices: PackedInt32Array
var template_edges: PackedByteArray
var chunks: Dictionary
var cell_surfaces: Dictionary
var seed_offset: Vector2
var noise := FastNoiseLite.new()

func prepare(board: Dictionary, seed_value: int) -> void:
	tiles = board
	noise.seed = seed_value & 0x7fffffff
	noise.frequency = 1.0
	noise.fractal_octaves = 2
	seed_offset = Vector2(seed_value & 255, (seed_value >> 8) & 255) * 0.017
	chunks.clear()
	cell_surfaces.clear()
	triangles.clear()
	cached_samples.clear()
	sample_cells.clear()
	origins.clear()
	adjacent.clear()
	var surface_cells = tiles.duplicate()
	for id in tiles:
		for next in _around(id):
			if not tiles.has(next):
				surface_cells[next] = true
	for id in surface_cells:
		var chunk = chunk_for(id)
		if not chunks.has(chunk):
			chunks[chunk] = []
		chunks[chunk].append(id)
	if not template.is_empty():
		return
	var lookup = {}
	for side in range(6):
		var a = corner(side) / SUBDIVISIONS
		var b = corner(side + 1) / SUBDIVISIONS
		for i in range(SUBDIVISIONS):
			for j in range(SUBDIVISIONS - i):
				var point = a * i + b * j
				_add_template_face(lookup, point, point + a, point + b)
				if i + j < SUBDIVISIONS - 1:
					_add_template_face(lookup, point + a, point + a + b, point + b)

func _add_template_face(lookup: Dictionary, a: Vector3, b: Vector3, c: Vector3) -> void:
	for point in [a, b, c]:
		var key = Vector2i(roundi(point.x * 10000), roundi(point.z * 10000))
		if not lookup.has(key):
			lookup[key] = template.size()
			template.append(point)
			var radius = maxf(absf(point.x) * 1.1547005, absf(point.z) + absf(point.x) * 0.5773503)
			template_edges.append(1 if radius > 0.999 else 0)
		template_indices.append(lookup[key])

static func chunk_for(id: String) -> Vector2i:
	var coord = Hex.coord(id)
	return Vector2i(floori(float(coord.x) / CHUNK_SIZE), floori(float(coord.y) / CHUNK_SIZE))

func rebuild(layout: Dictionary, previous: Dictionary) -> Dictionary:
	profiles.clear()
	cached_normals.clear()
	for id in layout:
		var terrain: String = layout[id][0]
		profiles[id] = LAKE if terrain == "lake" else [terrain,
			LAND_LEVELS[terrain] + clampf(float(layout[id][1]), 0.0, 0.10), Color(Catalog.TERRAIN[terrain].color),
			layout[id][2] if layout[id].size() > 2 else false]
	var dirty = {}
	var changed_centers: Array[Vector3] = []
	for id in layout:
		if layout[id] != previous.get(id, []):
			changed_centers.append(_origin(id))
			for affected in _around(id):
				dirty[affected] = true
	for id in previous:
		if not layout.has(id):
			changed_centers.append(_origin(id))
			for affected in _around(id):
				dirty[affected] = true
	_invalidate_samples(dirty, changed_centers)
	var updates = {}
	for chunk in chunks:
		var changed = false
		for id in chunks[chunk]:
			if dirty.has(id) or not cell_surfaces.has(id):
				cell_surfaces[id] = _build_cell(id)
				changed = true
		if changed:
			var cells: Array = chunks[chunk]
			updates[chunk] = [_build_chunk(cells, SurfaceLayer.GROUND), _build_chunk(cells, SurfaceLayer.FOG),
				_build_chunk(cells, SurfaceLayer.FRINGE)]
	return updates

func reveal_meshes(layout: Dictionary, previous: Dictionary) -> Array[ArrayMesh]:
	var revealed: Array = []
	var masks = {}
	for id in layout:
		if previous.has(id):
			continue
		revealed.append(id)
		var coord = Hex.coord(id)
		for side in Hex.DIRECTIONS.size():
			var neighbor = Hex.key(coord - Hex.DIRECTIONS[side])
			if previous.has(neighbor) and layout.has(neighbor):
				masks[neighbor] = masks.get(neighbor, 0) | (1 << side)
	return [_build_chunk(revealed, SurfaceLayer.REVEAL), _build_chunk(masks.keys(), SurfaceLayer.FRINGE, masks)]

func _invalidate_samples(dirty: Dictionary, changed_centers: Array[Vector3]) -> void:
	for id in dirty:
		if not sample_cells.has(id):
			continue
		var retained: Array[Vector2i] = []
		for key in sample_cells[id]:
			var point = Vector3(key.x * 0.0001, 0.0, key.y * 0.0001)
			var stale = false
			for center in changed_centers:
				if point.distance_squared_to(center) <= BLEND_RADIUS_SQUARED:
					stale = true
					break
			if stale:
				cached_samples.erase(key)
			else:
				retained.append(key)
		sample_cells[id] = retained

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
	var clearing := 0.0
	var cell = Hex.cell_at(point)
	for id in _around(cell):
		var distance_sq = _origin(id).distance_squared_to(point)
		var weight = maxf(0.0, 1.0 - distance_sq / BLEND_RADIUS_SQUARED)
		if weight == 0.0:
			continue
		weight *= weight
		var profile = profiles.get(id, UNKNOWN if tiles.has(id) else SEA)
		var terrain: String = profile[0]
		if profile.size() > 3 and profile[3]:
			clearing = maxf(clearing, 1.0 - smoothstep(0.42, 0.85, sqrt(distance_sq)))
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
	var ridge_signal = absf(noise.get_noise_2dv(Vector2(p.x * 0.8 + p.y * 0.44, p.y * 1.6)))
	var ridge = 1.0 - smoothstep(0.0, 0.70, ridge_signal)
	var dune = sin(p.dot(Vector2(1.35, 2.7)) + rolling * 3.3)
	height += (rolling * 0.10 + chips * 0.035) * (1.0 - (sea + lake + unknown) / total)
	# Leave a gentler patch inside each landmark hex while keeping continuous ridges along the edges.
	height += mountain * mountain * (0.30 + ridge * 0.74 + chips * 0.11) * (1.0 - 0.78 * clearing)
	height += sand * (0.065 + dune * 0.14)
	var channels = 1.0 - absf(noise.get_noise_2dv(Vector2(p.x * 0.43 + p.y * 0.30, p.y * 0.71)))
	height -= marsh * marsh * smoothstep(0.51, 0.97, channels) * 0.27 * (1.0 - 0.76 * clearing)
	var stone = clampf(mountain + ruins * 0.65, 0.0, 1.0)
	var tint = Color(pigment.x, pigment.y, pigment.z, lake / maxf(lake + sea, 0.0001))
	var result = [Vector3(point.x, maxf(WATER_LEVEL, height), point.z),
		tint, Vector2(sand, stone), Vector2(marsh, WATER_LEVEL - height), mountain]
	cached_samples[key] = result
	if not sample_cells.has(cell):
		sample_cells[cell] = []
	sample_cells[cell].append(key)
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

func _build_cell(id: String) -> Array:
	var center = _origin(id)
	var fog = tiles.has(id) and not profiles.has(id)
	var fog_edge = fog and _around(id).any(func(next): return not tiles.has(next) or profiles.has(next))
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var mountains := PackedFloat32Array()
	for offset in template:
		if fog:
			var point = center + offset
			if fog_edge:
				point = sample(point)[0]
			else:
				point.y = UNKNOWN[1]
			vertices.append(point)
			uv.append(Vector2(offset.x, offset.z) * 0.5 + Vector2.ONE * 0.5)
		else:
			var surface = sample(center + offset)
			var point: Vector3 = surface[0]
			vertices.append(point)
			colors.append(surface[1])
			uv.append(surface[2])
			uv2.append(surface[3])
			mountains.append(surface[4])
	if not fog:
		normals = _cell_normals(vertices)
	if profiles.has(id):
		var faces := PackedVector3Array()
		for index in template_indices:
			faces.append(vertices[index])
		triangles[id] = faces
	else:
		triangles.erase(id)
	return [fog, vertices, normals, colors, uv, uv2, mountains]

func _cell_normals(vertices: PackedVector3Array) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for face in range(0, template_indices.size(), 3):
		var a = template_indices[face]
		var b = template_indices[face + 1]
		var c = template_indices[face + 2]
		var normal = (vertices[c] - vertices[a]).cross(vertices[b] - vertices[a])
		normals[a] += normal
		normals[b] += normal
		normals[c] += normal
	for i in normals.size():
		# Shared edge normals come from the common height field, independently of the chunk.
		normals[i] = _normal_at(vertices[i]) if template_edges[i] != 0 else normals[i].normalized()
	return normals

func _normal_at(point: Vector3) -> Vector3:
	if not cached_normals.has(point):
		const STEP = 0.04
		var left: Vector3 = sample(point - Vector3.RIGHT * STEP)[0]
		var right: Vector3 = sample(point + Vector3.RIGHT * STEP)[0]
		var near: Vector3 = sample(point - Vector3.BACK * STEP)[0]
		var far: Vector3 = sample(point + Vector3.BACK * STEP)[0]
		cached_normals[point] = Vector3(left.y - right.y, STEP * 2.0, near.y - far.y).normalized()
	return cached_normals[point]

func _build_chunk(ids: Array, layer: SurfaceLayer, fringe_masks: Dictionary = {}) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var mountains := PackedFloat32Array()
	var indices := PackedInt32Array()
	for id in ids:
		var cell: Array = cell_surfaces[id]
		if cell[0] != (layer == SurfaceLayer.FOG):
			continue
		var mask = fringe_masks.get(id, 0)
		if layer == SurfaceLayer.FRINGE:
			if not profiles.has(id):
				continue
			if fringe_masks.is_empty():
				var coord = Hex.coord(id)
				for side in Hex.DIRECTIONS.size():
					var neighbor = Hex.key(coord + Hex.DIRECTIONS[side])
					if tiles.has(neighbor) and not profiles.has(neighbor):
						mask |= 1 << side
			if mask == 0:
				continue
		var base = vertices.size()
		vertices.append_array(cell[1])
		if layer == SurfaceLayer.FRINGE or layer == SurfaceLayer.REVEAL:
			# Cloud effects sample tile-local UVs and share the ground surface at the seam.
			for offset in template:
				uv.append(Vector2(offset.x, offset.z) * 0.5 + Vector2.ONE * 0.5)
				if layer == SurfaceLayer.FRINGE:
					uv2.append(Vector2(mask, 0))
		else:
			normals.append_array(cell[2])
			colors.append_array(cell[3])
			uv.append_array(cell[4])
			uv2.append_array(cell[5])
			if layer == SurfaceLayer.GROUND:
				mountains.append_array(cell[6])
		for index in template_indices:
			indices.append(base + index)
	if vertices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	if layer == SurfaceLayer.GROUND or layer == SurfaceLayer.FRINGE:
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
	if layer == SurfaceLayer.GROUND:
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_CUSTOM0] = mountains
	var mesh := ArrayMesh.new()
	var flags = (Mesh.ARRAY_CUSTOM_R_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) if layer == SurfaceLayer.GROUND else 0
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return mesh

func pick_hit(origin: Vector3, direction: Vector3) -> Array:
	var fog_hit = Plane(Vector3.UP, 0.16).intersects_ray(origin, direction)
	if fog_hit == null:
		return ["", INF]
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
	return [closest_id, nearest]

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
