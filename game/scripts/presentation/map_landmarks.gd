extends RefCounted
## Low-poly props are built in tile units and cached as one vertex-colored mesh per variant.
const Doll = preload("res://scripts/presentation/doll.gd")
const Catalog = preload("res://scripts/domain/catalog.gd")
const WOOD = Color("795139")
const PLANK = Color("a87649")
const BRASS = Color("d2a14e")
const IRON = Color("49443b")
const CLOTH = Color("9b4338")
const STONE = {
	"plains": Color("a8a28b"), "forest": Color("858773"), "mountain": Color("989681"),
	"ruins": Color("b9a689"), "desert": Color("c98e58"), "swamp": Color("777e67"),
}
const WALL = {
	"plains": Color("dfc49b"), "forest": Color("947453"), "mountain": Color("a5a18c"),
	"ruins": Color("c3ae90"), "desert": Color("d1a06b"), "swamp": Color("b4a07d"),
}
const ROOF = {
	"plains": Color("bf8f48"), "forest": Color("667143"), "mountain": Color("81553e"),
	"ruins": Color("b17448"), "desert": Color("bb8657"), "swamp": Color("847149"),
}
static var meshes: Dictionary = {}
var tool := SurfaceTool.new()

static func offset(kind: String) -> Vector3:
	return Vector3(0.0, 0.0, -0.40 if kind == "village" else -0.29)

static func decoration(kind: String, terrain: String, claimed: bool) -> MeshInstance3D:
	var key := [kind, "" if kind == "elite" else terrain, claimed]
	if not meshes.has(key):
		var builder = new()
		builder.tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		match kind:
			"village": builder._village(terrain)
			"supply": builder._supply(terrain, claimed)
			"cache": builder._cache(terrain, claimed)
			"elite": builder._banner()
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.vertex_color_is_srgb = true
		material.roughness = 0.95
		builder.tool.set_material(material)
		meshes[key] = builder.tool.commit()
	var model := MeshInstance3D.new()
	model.mesh = meshes[key]
	model.name = {"village": "Village", "cache": "Chest", "supply": "Supplies", "elite": "EliteBanner"}[kind]
	return model

static func enemy(type: String, elite: bool) -> Doll:
	var definition: Dictionary = Catalog.ENEMIES[type].duplicate()
	definition.type = type
	var model := Doll.new()
	model.name = "Enemy"
	model.configure(definition)
	model.ring.hide()
	model.ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.set_process(false)
	# The battle scene owns the full animation. Use the same rig and colors in a posed map miniature.
	model.rigged.animator.advance(0.0)
	model.rigged.animator.pause()
	model.rotation.y = 0.83
	var scale_factor := 0.29 if elite else 0.25
	if type in ["boar", "lurker", "swarm"]:
		scale_factor *= 1.28
	model.scale = Vector3.ONE * scale_factor
	model.set_meta("enemy_type", type)
	return model

static func bounds(model: Node3D) -> AABB:
	var box := AABB()
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.visible and mesh.name != "Foundation":
			var pose := model.global_transform.affine_inverse() * mesh.global_transform
			var part := pose * mesh.get_aabb()
			box = part if not box.has_volume() else box.merge(part)
	return box

func _village(terrain: String) -> void:
	var wall: Color = WALL[terrain]
	var roof: Color = ROOF[terrain]
	var stone: Color = STONE[terrain]
	var raised := 0.16 if terrain == "swamp" else 0.0
	if raised > 0.0:
		_box(Vector3(1.13, 0.068, 0.65), PLANK, Vector3(0, 0.17, 0.03))
		for x in [-0.48, -0.15, 0.18, 0.49]:
			for z in [-0.24, 0.26]:
				_box(Vector3(0.058, 0.38, 0.056), WOOD, Vector3(x, 0.005, z))
		for step in range(3):
			_box(Vector3(0.27, 0.045, 0.08), PLANK, Vector3(-0.14, 0.16 - step * 0.055, 0.36 + step * 0.06))
	_house(Vector3(-0.24, raised, 0.0), Vector3(0.51, 0.36, 0.39), wall, roof, stone, terrain)
	_house(Vector3(0.33, raised, -0.07), Vector3(0.33, 0.27, 0.30), wall.darkened(0.06), roof, stone, terrain)
	match terrain:
		"plains":
			_box(Vector3(0.31, 0.034, 0.21), WOOD, Vector3(0.33, 0.018, 0.24))
			for x in [0.23, 0.33, 0.43]:
				for z in [0.19, 0.29]:
					_round(0.038, 0.055, 0.055, Color("677a3f"), Vector3(x, 0.061, z), 5)
		"forest":
			for i in range(3):
				var log := Vector3(-0.44 + i * 0.062, 0.04, 0.27)
				_round(0.034, 0.034, 0.16, WOOD, log, 7, Basis(Vector3.RIGHT, PI / 2.0))
				_round(0.022, 0.022, 0.003, PLANK, log + Vector3.BACK * 0.081, 7, Basis(Vector3.RIGHT, PI / 2.0))
		"mountain", "ruins":
			for i in range(3):
				_box(Vector3(0.15, 0.07, 0.074), stone, Vector3(0.24 + i * 0.15, 0.038, 0.22))
			if terrain == "ruins":
				_awning(Vector3(-0.25, 0.0, 0.24), 0.31, 0.26, 0.23, Color("b58867"))
		"desert":
			_awning(Vector3(-0.24, 0.0, 0.26), 0.43, 0.34, 0.25, Color("d9ba7d"), true)
			_jar(Vector3(0.46, 0.0, 0.21), 0.074, 0.19, Color("b77751"))

func _house(at: Vector3, size: Vector3, wall: Color, roof: Color, stone: Color, terrain: String) -> void:
	var front := size.z * 0.5
	_box(Vector3(size.x + 0.035, 0.14, size.z + 0.04), stone, at + Vector3.DOWN * 0.025)
	_box(size, wall, at + Vector3.UP * (size.y * 0.5 + 0.025))
	if terrain in ["mountain", "ruins"]:
		for row in range(2):
			for column in range(3):
				var brick := Vector3((column - 1) * size.x * 0.28, 0.072 + row * 0.078, front + 0.004)
				_box(Vector3(size.x * 0.25, 0.057, 0.012), stone.lightened((row + column) % 3 * 0.055), at + brick)
	for x in [-size.x * 0.46, size.x * 0.46]:
		_box(Vector3(0.033, size.y, 0.026), WOOD, at + Vector3(x, size.y / 2.0 + 0.025, front))
	_box(Vector3(0.114, 0.203, 0.026), WOOD, at + Vector3(-0.035, 0.12, front))
	_box(Vector3(0.033, 0.029, 0.035), BRASS, at + Vector3(-0.007, 0.12, front + 0.011))
	var window := at + Vector3(size.x * 0.27, 0.222, front)
	_box(Vector3(0.086, 0.084, 0.023), WOOD, window)
	_box(Vector3(0.063, 0.059, 0.006), Color("e5b673"), window + Vector3.BACK * 0.015)
	_box(Vector3(0.012, 0.065, 0.009), WOOD, window + Vector3.BACK * 0.02)
	var side_window := at + Vector3(size.x * 0.5, 0.22, 0)
	_box(Vector3(0.027, 0.092, 0.12), WOOD, side_window)
	_box(Vector3(0.005, 0.064, 0.086), Color("e5b673"), side_window + Vector3.RIGHT * 0.016)
	var eaves := at + Vector3.UP * (size.y + 0.025)
	if terrain == "desert":
		_box(Vector3(size.x + 0.065, 0.075, size.z + 0.07), roof, eaves)
		for x in [-size.x * 0.42, 0.0, size.x * 0.42]:
			_box(Vector3(0.043, 0.05, 0.054), WOOD, eaves + Vector3(x, -0.037, front + 0.027))
		return
	var half := size.x / 2.0 + 0.042
	var rise := size.x * 0.36
	_prism(PackedVector2Array([Vector2(-half, 0), Vector2(half, 0), Vector2(0, rise)]), size.z + 0.09, eaves, roof)
	for side in [-1, 1]:
		var tilt := Basis(Vector3.BACK, -side * atan2(rise, half))
		_box(Vector3(Vector2(half, rise).length() + 0.012, 0.037, size.z + 0.106), roof.lightened(0.045),
			eaves + Vector3(side * half * 0.5, rise * 0.5, 0), tilt)
		for i in range(1, 4):
			var fraction := i / 4.0
			_box(Vector3(0.016, 0.012, size.z + 0.108), roof.darkened(0.14),
				eaves + Vector3(side * half * fraction, rise * (1.0 - fraction) + 0.019, 0), tilt)
	_box(Vector3(0.046, 0.041, size.z + 0.11), roof.darkened(0.12), eaves + Vector3.UP * (rise + 0.012))
	if size.x > 0.4:
		var chimney := eaves + Vector3(-half * 0.52, rise * 0.78, -0.085)
		_box(Vector3(0.09, 0.22, 0.09), stone.darkened(0.13), chimney)
		_box(Vector3(0.114, 0.029, 0.114), stone, chimney + Vector3.UP * 0.107)
		_box(Vector3(0.064, 0.013, 0.064), IRON, chimney + Vector3.UP * 0.126)

func _supply(terrain: String, claimed: bool) -> void:
	var stone: Color = STONE[terrain]
	if terrain == "swamp":
		_box(Vector3(0.86, 0.09, 0.59), PLANK, Vector3(0, 0.09, 0))
		for x in [-0.36, 0.36]:
			for z in [-0.21, 0.21]:
				_box(Vector3(0.074, 0.34, 0.071), WOOD, Vector3(x, 0.0, z))
		_awning(Vector3(0.0, 0.13, 0.0), 0.86, 0.51, 0.62, ROOF[terrain])
		_jar(Vector3(-0.18, 0.13, 0.04), 0.153, 0.26, PLANK)
		_box(Vector3(0.10, 0.042, 0.072), BRASS, Vector3(-0.18, 0.23, 0.18))
		_crate(Vector3(0.22, 0.13, 0.13), claimed)
		return
	var well := Vector3(-0.14, 0, -0.04)
	_ring(well, 0.235, stone, 1 if terrain == "forest" else 2)
	_round(0.184, 0.184, 0.025, Color("477d7b"), well + Vector3.UP * 0.067)
	if terrain == "forest":
		_awning(well + Vector3.FORWARD * 0.052, 0.58, 0.47, 0.47, ROOF[terrain])
		_box(Vector3(0.147, 0.07, 0.067), stone, well + Vector3(0, 0.148, -0.16))
		_box(Vector3(0.09, 0.024, 0.087), Color("73bdb0"), well + Vector3(0, 0.134, -0.12))
	elif terrain == "ruins":
		_round(0.23, 0.23, 0.049, PLANK, well + Vector3.UP * 0.205, 10)
		_box(Vector3(0.113, 0.038, 0.042), IRON, well + Vector3.UP * 0.242)
	else:
		for side in [-1, 1]:
			_box(Vector3(0.06, 0.40, 0.065), WOOD, well + Vector3(side * 0.214, 0.23, 0.015))
		var spindle := Basis(Vector3.FORWARD, PI / 2.0)
		_round(0.032, 0.032, 0.51, PLANK, well + Vector3(0, 0.38, 0.016), 8, spindle)
		for i in range(4):
			_round(0.042, 0.042, 0.011, Color("c4a276"), well + Vector3(i * 0.013 - 0.02, 0.38, 0.017), 8, spindle)
		_round(0.011, 0.011, 0.24, Color("c4a276"), well + Vector3(0.02, 0.25, 0.047), 6)
	_crate(Vector3(0.21, 0.0, 0.14), claimed)
	if terrain == "desert":
		_jar(Vector3(0.35, 0.0, -0.12), 0.079, 0.20, Color("b87c52"))
	elif not claimed:
		_round(0.054, 0.091, 0.16, Color("bfa77d"), Vector3(0.30, 0.08, -0.09), 7)
		_round(0.045, 0.031, 0.043, Color("d0b895"), Vector3(0.30, 0.171, -0.09), 7)

func _cache(terrain: String, claimed: bool) -> void:
	var stone: Color = STONE[terrain]
	match terrain:
		"forest":
			_round(0.13, 0.20, 0.33, WOOD, Vector3(0.23, 0.14, -0.15), 7)
			_round(0.118, 0.118, 0.008, PLANK, Vector3(0.23, 0.308, -0.15), 7)
			for side in [-1, 1]:
				_box(Vector3(0.23, 0.08, 0.067), WOOD, Vector3(0.23 + side * 0.12, 0.047, -0.15), Basis(Vector3.UP, side * 0.5))
		"mountain", "ruins":
			_arch(Vector3(0.0, 0.0, -0.25), stone)
		"desert":
			for side in [-1, 1]:
				_box(Vector3(0.16, 0.36, 0.20), stone, Vector3(side * 0.24, 0.16, -0.25))
			_box(Vector3(0.64, 0.12, 0.22), stone.lightened(0.1), Vector3(0.0, 0.36, -0.25))
		"swamp":
			var turn := Basis(Vector3.UP, -0.4)
			for side in [-1, 1]:
				_box(Vector3(0.055, 0.18, 0.46), WOOD, Vector3(0.28 + side * 0.085, 0.072, -0.16), turn)
			_box(Vector3(0.20, 0.08, 0.45), PLANK, Vector3(0.28, 0.028, -0.16), turn)
		_:
			_prism(PackedVector2Array([Vector2(-0.082, 0), Vector2(0.082, 0), Vector2(0.082, 0.29),
				Vector2(0, 0.365), Vector2(-0.082, 0.29)]), 0.095, Vector3(0.29, 0.0, -0.14), stone)
	_chest(Vector3(-0.09, 0.02, 0.10), claimed)

func _chest(at: Vector3, open: bool) -> void:
	_box(Vector3(0.52, 0.055, 0.34), WOOD, at + Vector3.UP * 0.014)
	for side in [-1, 1]:
		_box(Vector3(0.51, 0.168, 0.042), PLANK, at + Vector3(0, 0.105, side * 0.15))
		_box(Vector3(0.042, 0.168, 0.30), WOOD, at + Vector3(side * 0.238, 0.105, 0))
		_box(Vector3(0.041, 0.175, 0.024), BRASS, at + Vector3(side * 0.17, 0.108, 0.174))
	for y in [0.065, 0.12]:
		_box(Vector3(0.50, 0.008, 0.004), WOOD, at + Vector3(0, y, 0.171))
	_box(Vector3(0.089, 0.095, 0.027), BRASS, at + Vector3(0, 0.162, 0.175))
	_box(Vector3(0.017, 0.037, 0.009), IRON, at + Vector3(0, 0.157, 0.192))
	var profile := PackedVector2Array()
	for i in range(9):
		var angle := float(i) * PI / 8.0
		profile.append(Vector2(cos(angle) * 0.176, sin(angle) * 0.116 + 0.016))
	var hinge := at + Vector3(0, 0.20, -0.16)
	var swing := Basis(Vector3.RIGHT, -1.54 if open else 0.0)
	var lid := hinge + swing * Vector3.BACK * 0.16
	var cross_section := swing * Basis(Vector3.UP, PI / 2.0)
	_prism(profile, 0.51, lid, WOOD.darkened(0.11) if open else WOOD, cross_section)
	var bands := PackedVector2Array()
	for point in profile:
		bands.append(point * 1.024)
	for side in [-1, 1]:
		_prism(bands, 0.04, lid + Vector3.RIGHT * (side * 0.17), BRASS, cross_section)

func _banner() -> void:
	var at := Vector3(0.35, 0, -0.025)
	_round(0.012, 0.019, 0.77, WOOD, at + Vector3.UP * 0.35, 7)
	_round(0.004, 0.032, 0.086, BRASS, at + Vector3.UP * 0.763, 6)
	_box(Vector3(0.38, 0.029, 0.03), WOOD, at + Vector3(-0.125, 0.66, 0.0))
	_prism(PackedVector2Array([Vector2(-0.29, -0.23), Vector2(-0.04, -0.26),
		Vector2(-0.04, 0), Vector2(-0.29, 0)]), 0.018, at + Vector3(0, 0.647, 0.008), CLOTH)
	_box(Vector3(0.066, 0.066, 0.023), BRASS, at + Vector3(-0.165, 0.541, 0.012), Basis(Vector3.BACK, PI / 4.0))

func _crate(at: Vector3, open: bool) -> void:
	_box(Vector3(0.22, 0.037, 0.20), WOOD, at + Vector3.UP * 0.018)
	for side in [-1, 1]:
		_box(Vector3(0.22, 0.15, 0.032), PLANK, at + Vector3(0, 0.086, side * 0.09))
		_box(Vector3(0.032, 0.15, 0.18), WOOD, at + Vector3(side * 0.10, 0.086, 0))
	_box(Vector3(0.16, 0.02, 0.012), WOOD, at + Vector3(0, 0.085, 0.109), Basis(Vector3.BACK, 0.62))
	if not open:
		_box(Vector3(0.23, 0.028, 0.21), PLANK.lightened(0.12), at + Vector3.UP * 0.163)

func _jar(at: Vector3, radius: float, height: float, color: Color) -> void:
	_round(radius, radius * 0.69, height * 0.57, color, at + Vector3.UP * (height * 0.28))
	_round(radius * 0.66, radius, height * 0.30, color, at + Vector3.UP * (height * 0.71))
	_round(radius * 0.71, radius * 0.71, height * 0.15, color.darkened(0.23), at + Vector3.UP * (height * 0.93))
	_round(radius * 0.48, radius * 0.48, 0.006, IRON, at + Vector3.UP * height * 1.01)

func _awning(at: Vector3, width: float, height: float, depth: float, roof: Color, striped: bool = false) -> void:
	for x in [-width * 0.42, width * 0.42]:
		for z in [-depth * 0.34, depth * 0.34]:
			_box(Vector3(0.046, height, 0.05), WOOD, at + Vector3(x, height * 0.48, z))
	var tilt := Basis(Vector3.RIGHT, 0.23)
	for i in range(5):
		var color := CLOTH if striped and i % 2 == 0 else roof.lightened(float(i % 3) * 0.035)
		_box(Vector3(width / 5.0 + 0.003, 0.043, depth), color,
			at + Vector3(width * (i - 2) / 5.0, height, 0), tilt)

func _ring(at: Vector3, radius: float, stone: Color, rows: int) -> void:
	for row in range(rows):
		for i in range(10):
			var angle := TAU * (i + row * 0.5) / 10.0
			var center := at + Vector3(sin(angle) * radius, 0.045 + row * 0.081, cos(angle) * radius)
			_box(Vector3(0.148, 0.091, 0.098), stone.lightened(float((row + i) % 3) * 0.055), center, Basis(Vector3.UP, angle))

func _arch(at: Vector3, stone: Color) -> void:
	for side in [-1, 1]:
		for row in range(2):
			_box(Vector3(0.138, 0.158, 0.19), stone.darkened(row * 0.065), at + Vector3(side * 0.25, 0.07 + row * 0.146, 0))
	for i in range(7):
		var angle := PI * i / 6.0
		_box(Vector3(0.139, 0.135, 0.19), stone.lightened((i % 3) * 0.05),
			at + Vector3(cos(angle) * 0.25, 0.29 + sin(angle) * 0.24, 0), Basis(Vector3.BACK, angle))

func _box(size: Vector3, color: Color, at: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	var part := BoxMesh.new()
	part.size = size
	_append(part, color, Transform3D(basis, at))

func _round(top: float, base: float, height: float, color: Color, at: Vector3, sides: int = 10, basis: Basis = Basis.IDENTITY) -> void:
	var part := CylinderMesh.new()
	part.top_radius = top
	part.bottom_radius = base
	part.height = height
	part.radial_segments = sides
	part.rings = 0
	_append(part, color, Transform3D(basis, at))

func _append(part: PrimitiveMesh, color: Color, pose: Transform3D) -> void:
	var arrays := part.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for index in arrays[Mesh.ARRAY_INDEX]:
		_vertex(pose * vertices[index], pose.basis * normals[index], color)

func _prism(profile: PackedVector2Array, depth: float, at: Vector3, color: Color, basis: Basis = Basis.IDENTITY) -> void:
	var pose := Transform3D(basis, at)
	for i in range(1, profile.size() - 1):
		_face(profile[0], profile[i], profile[i + 1], depth / 2.0, pose, color)
		_face(profile[0], profile[i + 1], profile[i], -depth / 2.0, pose, color)
	for i in range(profile.size()):
		var a := profile[i]
		var b := profile[(i + 1) % profile.size()]
		var near_a := Vector3(a.x, a.y, depth * 0.5)
		var near_b := Vector3(b.x, b.y, depth * 0.5)
		var far_a := near_a - Vector3.BACK * depth
		var far_b := near_b - Vector3.BACK * depth
		_triangle(near_a, far_b, far_a, pose, color)
		_triangle(near_a, near_b, far_b, pose, color)

func _face(a: Vector2, b: Vector2, c: Vector2, depth: float, pose: Transform3D, color: Color) -> void:
	_triangle(Vector3(a.x, a.y, depth), Vector3(c.x, c.y, depth), Vector3(b.x, b.y, depth), pose, color)

func _triangle(a: Vector3, b: Vector3, c: Vector3, pose: Transform3D, color: Color) -> void:
	var normal := pose.basis * (c - a).cross(b - a).normalized()
	for point in [a, b, c]:
		_vertex(pose * point, normal, color)

func _vertex(point: Vector3, normal: Vector3, color: Color) -> void:
	tool.set_color(color)
	tool.set_normal(normal)
	tool.add_vertex(point)
