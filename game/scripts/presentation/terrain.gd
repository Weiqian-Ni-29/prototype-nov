class_name TerrainArt
extends RefCounted
const Doll = preload("res://scripts/presentation/doll.gd")
const Catalog = preload("res://scripts/domain/catalog.gd")
static var ground_materials: Dictionary = {}

static func tile(parent: Node3D, definition: Dictionary, revealed: bool, visual_seed: int) -> Node3D:
	var root = Node3D.new()
	parent.add_child(root)
	var terrain = str(definition.terrain)
	var color = Color(str(Catalog.TERRAIN[terrain].color)) if revealed else Color("293f40")
	var height = float(definition.get("height", 0.0)) if revealed else 0.0
	var base = Doll._cylinder(root, 0.975, 0.975, 0.26 + height, color.darkened(0.3), Vector3(0, -0.12 + height * 0.5, 0), 6)
	var top = Doll._cylinder(root, 0.94, 0.975, 0.07, color, Vector3(0, 0.045 + height, 0), 6)
	if not revealed:
		var fog_material = Doll.material(Color("213a39"))
		fog_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		top.material_override = fog_material
		return root
	top.material_override = _ground_material(terrain)
	if definition.get("ground_only", false):
		return root
	var props = Node3D.new()
	props.position.y = height + 0.08
	root.add_child(props)
	var rng = RandomNumberGenerator.new()
	rng.seed = visual_seed
	# A few stylized strokes and fibers keep terrain from becoming featureless flat plastic.
	for i in range(4):
		var fleck = Doll._box(props, Vector3(rng.randf_range(0.12, 0.32), 0.008, 0.025), color.lightened(0.09), Vector3(rng.randf_range(-0.5, 0.5), 0.007, rng.randf_range(-0.5, 0.5)))
		fleck.rotation.y = rng.randf_range(-0.8, 0.8)
	match terrain:
		"forest":
			for i in range(3):
				tree(props, Vector3(rng.randf_range(-0.48, 0.48), 0, rng.randf_range(-0.5, 0.22)), rng.randf_range(0.65, 1.0), i % 2 == 0)
		"mountain":
			for i in range(2):
				var mountain = Doll._cone(props, 0.4, 0.8 + i * 0.35, Color("939990"), Vector3(-0.2 + i * 0.38, 0.4, -0.14))
				mountain.rotation.y = 0.5
				Doll._cone(props, 0.16, 0.28, Color("d8d9c5"), Vector3(-0.2 + i * 0.38, 0.8 + i * 0.17, -0.14))
		"ruins":
			for i in range(3):
				Doll._box(props, Vector3(0.2, 0.4 + i * 0.15, 0.23), Color("c0b59a"), Vector3(-0.35 + i * 0.3, 0.2, -0.33))
			Doll._box(props, Vector3(0.8, 0.12, 0.2), Color("b4ab94"), Vector3(0, 0.62, -0.33))
		"desert":
			Doll._sphere(props, Vector3(0.55, 0.15, 0.33), Color("d8c28a"), Vector3(0.12, 0.02, -0.2))
			Doll._sphere(props, Vector3(0.14, 0.22, 0.13), Color("968c68"), Vector3(-0.4, 0.17, 0.03))
		"swamp":
			var pool = Doll._cylinder(props, 0.51, 0.51, 0.015, Color("739d99"), Vector3(0, 0.02, 0), 24)
			pool.scale.z = 0.72
			for i in range(5):
				var reed = Doll._cylinder(props, 0.014, 0.018, 0.35, Color("aaa66c"), Vector3(-0.4 + i * 0.12, 0.17, -0.36), 5)
				reed.rotation.z = (i - 2) * 0.06
		"scorched":
			for i in range(3):
				Doll._cylinder(props, 0.045, 0.08, 0.3, Color("3f4640"), Vector3(-0.3 + i * 0.28, 0.14, -0.1), 7)
	if definition.get("camp", false):
		var tent = Doll._cone(props, 0.42, 0.5, Color("d7bd8c"), Vector3(0, 0.25, 0.15))
		tent.scale.z = 0.8
	if definition.get("site", "") != "":
		landmark(props, str(definition.site))
	elif definition.get("quantity", 0) > 0 and definition.get("enemies", []).is_empty():
		Doll._box(props, Vector3(0.25, 0.18, 0.2), Color("c7ab70"), Vector3(0.4, 0.12, 0.2))
	if definition.get("burning", false):
		fire(props)
	elif definition.get("wet_until", 0) > definition.get("current_day", 1):
		var wet = Doll._cylinder(props, 0.78, 0.78, 0.012, Color("8db3b4"), Vector3(0, 0.03, 0), 12)
		wet.scale.z = 0.7
	return root

static func tree(parent: Node3D, point: Vector3, size: float, pine: bool = true) -> void:
	var root = Node3D.new()
	parent.add_child(root)
	root.position = point
	root.scale = Vector3.ONE * size
	Doll._cylinder(root, 0.045, 0.065, 0.5, Color("705946"), Vector3(0, 0.24, 0), 7)
	if pine:
		Doll._cone(root, 0.35, 0.68, Color("39654e"), Vector3(0, 0.65, 0))
		Doll._cone(root, 0.27, 0.55, Color("527b5b"), Vector3(0, 0.9, 0))
	else:
		Doll._sphere(root, Vector3(0.38, 0.41, 0.33), Color("5c855b"), Vector3(0, 0.67, 0))
		Doll._sphere(root, Vector3(0.24, 0.27, 0.26), Color("7b995e"), Vector3(0.2, 0.8, 0.03))

static func landmark(parent: Node3D, site: String) -> void:
	var color = Color("d1b882")
	if site in ["inn", "home", "exit"]:
		Doll._box(parent, Vector3(0.5, 0.38, 0.38), Color("d5c5a3"), Vector3(0, 0.19, 0.1))
		var roof = Doll._cone(parent, 0.43, 0.26, Color("756450"), Vector3(0, 0.51, 0.1))
		roof.scale.z = 0.75
		if site == "exit":
			Doll._cylinder(parent, 0.06, 0.07, 1.15, Color("b4a070"), Vector3(0.4, 0.57, -0.2), 8)
			Doll._sphere(parent, Vector3(0.12, 0.16, 0.12), Color("f4d995"), Vector3(0.4, 1.16, -0.2))
	else:
		Doll._cylinder(parent, 0.035, 0.04, 0.65, Color("7c6951"), Vector3(0.2, 0.32, 0.1), 8)
		Doll._box(parent, Vector3(0.43, 0.18, 0.07), color, Vector3(0.2, 0.57, 0.1))

static func fire(parent: Node3D) -> void:
	for i in range(3):
		var flame = Doll._cone(parent, 0.17, 0.57 + i * 0.08, Color("e6a253"), Vector3(-0.35 + i * 0.32, 0.3, 0.1))
		flame.set_meta("flame", true)
		flame.add_to_group("world_flames")
		Doll._cone(parent, 0.095, 0.38, Color("f2d58a"), Vector3(-0.35 + i * 0.32, 0.25, 0.2))

static func _ground_material(terrain: String) -> StandardMaterial3D:
	if ground_materials.has(terrain):
		return ground_materials[terrain]
	var color = Color(str(Catalog.TERRAIN[terrain].color))
	var noise = FastNoiseLite.new()
	noise.seed = hash(terrain)
	noise.frequency = 0.055
	noise.fractal_octaves = 4
	var gradient = Gradient.new()
	gradient.set_color(0, color.darkened(0.16))
	gradient.set_color(1, color.lightened(0.10))
	var texture = NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.noise = noise
	texture.seamless = true
	texture.color_ramp = gradient
	var material = Doll.material(Color.WHITE)
	material.albedo_texture = texture
	ground_materials[terrain] = material
	return material
