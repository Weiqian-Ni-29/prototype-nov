class_name TerrainArt
extends RefCounted
const Doll = preload("res://scripts/presentation/doll.gd")
const Catalog = preload("res://scripts/domain/catalog.gd")
const Hex = preload("res://scripts/domain/hex_map.gd")
static var ground_materials: Dictionary = {}

static var nature_scenes: Dictionary = {}
static var nature_bounds: Dictionary = {}
static var land_meshes: Dictionary = {}
static var nature_materials: Dictionary = {}

static func tile(parent: Node3D, definition: Dictionary, visual_seed: int) -> Node3D:
	var root = Node3D.new()
	parent.add_child(root)
	var terrain = str(definition.terrain)
	var color = Color(str(Catalog.TERRAIN[terrain].color))
	var height = float(definition.get("height", 0.0))
	# Chamfered tabletop edges and exposed soil give each cell a crafted, physical thickness.
	var base = Doll._cylinder(root,0.973,0.978,0.25+height,color.darkened(0.32),Vector3(0,-0.125+height*0.5,0),6)
	var rim = Doll._cylinder(root,0.975,0.975,0.035,color.darkened(0.17),Vector3(0,-0.025+height,0),6)
	var top = MeshInstance3D.new()
	root.add_child(top)
	top.mesh = _land_mesh(visual_seed%7)
	top.position.y = height
	top.material_override = _ground_material(terrain)
	if definition.get("ground_only", false): return root
	var props = Node3D.new()
	props.position.y = height+0.08
	root.add_child(props)
	var rng = RandomNumberGenerator.new()
	rng.seed = visual_seed
	var turn = rng.randf_range(-PI,PI)
	match terrain:
		"plains":
			_prop(props,"Grass_1_A",Vector3(-0.48,0,-0.3),0.38,turn)
			_prop(props,"Bush_1_B",Vector3(0.48,0,-0.38),0.37,turn)
			_prop(props,"Rock_1_F",Vector3(-0.46,0,0.32),0.22,turn)
			_flowers(props,rng,7)
		"forest":
			_prop(props,"Tree_1_A" if visual_seed%2==0 else "Tree_3_A",Vector3(-0.38,0,-0.27),1.12,turn)
			_prop(props,"Tree_2_B",Vector3(0.35,0,-0.42),0.95,turn+1.2)
			_prop(props,"Bush_2_C",Vector3(0.48,0,0.17),0.4,turn)
			_prop(props,"Grass_2_B",Vector3(-0.48,0,0.3),0.32,turn)
		"mountain":
			_prop(props,"Rock_3_B",Vector3(-0.18,0,-0.25),1.28,turn,Vector3(0.8,1.1,0.85))
			_prop(props,"Rock_2_C",Vector3(0.4,0,-0.24),0.7,turn+0.8)
			_prop(props,"Rock_1_A",Vector3(-0.44,0,0.35),0.32,turn)
			_prop(props,"Grass_1_A",Vector3(0.38,0,0.36),0.25,turn)
		"ruins":
			_ruins(props,rng)
			_prop(props,"Bush_1_B",Vector3(-0.5,0,0.31),0.34,turn)
		"desert":
			_dunes(props,rng)
			_prop(props,"Rock_1_F",Vector3(-0.47,0,-0.2),0.35,turn)
			_prop(props,"Grass_2_B",Vector3(0.45,0,0.3),0.22,turn)
		"swamp":
			_pool(props,Vector3(0.08,0.008,0.04),Vector3(0.65,1,0.47),Color("517f7f"))
			_prop(props,"Tree_Bare_1_A",Vector3(-0.44,0,-0.33),0.88,turn)
			_reeds(props,rng)
			for i in range(3):
				var lily = Doll._cylinder(props,0.08,0.08,0.012,Color("7caa79"),Vector3(0.05+i*0.13,0.035,-0.1+i*0.1),9)
	_tile_features(props, definition)
	return root

static func board_details(root: Node3D, tile: Dictionary, id: String, visual_seed: int, surface: RefCounted) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = visual_seed
	var terrain: String = tile.terrain
	var center = Hex.world(id)
	var neighbors = Hex.neighbors(id, surface.tiles)
	var same: Array[String] = []
	for next in neighbors:
		if surface.profiles.get(next, [""])[0] == terrain:
			same.append(next)
	match terrain:
		"plains":
			for i in range(9):
				var point = _board_position(rng, i, 9, 0.35, 0.77)
				var name = ["Grass_1_A", "Grass_2_B", "Bush_1_B", "Rock_1_F"][i % 4]
				_board_prop(root, surface, center, name, point, rng.randf_range(0.13, 0.32), rng.randf() * TAU)
			for next in neighbors:
				if surface.profiles.get(next, [""])[0] == "forest":
					var offset = (Hex.world(next) - center) * 0.36
					_board_prop(root, surface, center, "Tree_1_C", offset, rng.randf_range(0.37, 0.58), rng.randf() * TAU)
		"forest":
			var count = 5 + mini(3, same.size())
			for i in range(count):
				var point = _board_position(rng, i, count, 0.38, 0.75)
				var name = ["Tree_1_A", "Tree_2_B", "Tree_3_A", "Tree_1_C"][rng.randi_range(0, 3)]
				var size = rng.randf_range(0.55, 0.98)
				_board_prop(root, surface, center, name, point, size, rng.randf() * TAU)
			for i in range(4):
				_board_prop(root, surface, center, "Bush_2_C", _board_position(rng, i, 4, 0.38, 0.71), rng.randf_range(0.18, 0.32), rng.randf() * TAU)
		"mountain":
			var placed: Array[Vector3] = []
			for i in range(16):
				var point = _board_position(rng, i, 16, 0.28, 0.71)
				if placed.any(func(other: Vector3): return point.distance_squared_to(other) < 0.09):
					continue
				var name = "Rock_1_A" if i % 3 != 0 else "Rock_2_C"
				if _seat_mountain_rock(root, surface, center, name, point, rng.randf_range(0.14, 0.20), rng.randf() * TAU):
					placed.append(point)
					if placed.size() == 3:
						break
		"ruins":
			for next in same:
				var edge = (Hex.world(next) - center) * 0.5
				var edge_id = id + "/" + next if id < next else next + "/" + id
				if absf(edge.z) < 0.01 or hash(edge_id) % 4 == 0:
					_board_paving(root, surface, center, edge)
			var foundation = Node3D.new()
			root.add_child(foundation)
			var point = Vector3(rng.randf_range(-0.23, 0.23), 0.0, rng.randf_range(-0.38, -0.19))
			foundation.position = Vector3(point.x, surface.height_at(center + point), point.z)
			foundation.rotation.y = TAU / 6.0 * rng.randi_range(0, 2)
			foundation.scale = Vector3.ONE * rng.randf_range(0.67, 0.94)
			_ruins(foundation, rng)
			_register_occluders(foundation)
		"desert":
			for i in range(5):
				var point = _board_position(rng, i, 5, 0.40, 0.72)
				var name = "Rock_1_F" if i % 2 == 0 else "Grass_2_B"
				_board_prop(root, surface, center, name, point, rng.randf_range(0.13, 0.30), rng.randf() * TAU)
		"swamp", "lake":
			for i in range(10):
				var point = _board_position(rng, i, 10, 0.45, 0.85)
				var sample = surface.sample(center + point)
				if sample[3].y > 0.23:
					continue
				var reeds = Node3D.new()
				root.add_child(reeds)
				reeds.position = Vector3(point.x, sample[0].y, point.z)
				reeds.rotation.y = rng.randf() * TAU
				reeds.scale = Vector3.ONE * rng.randf_range(0.48, 0.75)
				_reeds(reeds, rng)
			if terrain == "swamp" and rng.randf() < 0.58:
				_board_prop(root, surface, center, "Tree_Bare_1_A", _board_position(rng, 0, 1, 0.4, 0.7), rng.randf_range(0.53, 0.83), rng.randf() * TAU)

static func _board_position(rng: RandomNumberGenerator, index: int, count: int, low: float, high: float) -> Vector3:
	var angle = TAU * (float(index) + rng.randf_range(-0.28, 0.28)) / count
	return Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(low, high)

static func _board_prop(root: Node3D, surface: RefCounted, center: Vector3, name: String,
		point: Vector3, size: float, turn: float) -> void:
	var sample = surface.sample(center + point)
	if sample[3].y > 0.045:
		return
	point.y = surface.height_at(center + point) - 0.035
	var prop = _prop(root, name, point, size, turn)
	if size >= 0.42:
		_register_occluders(prop)

static func _seat_mountain_rock(root: Node3D, surface: RefCounted, center: Vector3, name: String,
		point: Vector3, size: float, turn: float) -> bool:
	var anchor = center + point
	var height: float = surface.height_at(anchor)
	var radius = size * 0.75
	var east = Vector3.RIGHT * radius
	var south = Vector3.BACK * radius
	var gradient = Vector2(
		surface.height_at(anchor + east) - surface.height_at(anchor - east),
		surface.height_at(anchor + south) - surface.height_at(anchor - south)) / (2.0 * radius)
	if gradient.length_squared() > 1.25:
		return false
	var unevenness = 0.0
	for i in range(8):
		var offset = Vector2.from_angle(TAU * i / 8.0) * radius
		var foot: float = surface.height_at(anchor + Vector3(offset.x, 0.0, offset.y))
		if foot <= surface.WATER_LEVEL + 0.045:
			return false
		unevenness = maxf(unevenness, absf(foot - height - gradient.dot(offset)))
	if unevenness > size * 0.36:
		return false
	# Fit the base to the local slope, with a shallow overlap to hide the join.
	var normal = Vector3(-gradient.x, 1.0, -gradient.y).normalized()
	var tilt = Basis(Quaternion(Vector3.UP, normal))
	point.y = height - unevenness - size * 0.06
	var prop = _prop(root, name, point, size, turn, Vector3(1.0, 0.74, 1.0))
	prop.basis = tilt * prop.basis
	prop.position = point + tilt * (prop.position - point)
	return true

static func _register_occluders(root: Node3D) -> void:
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		if (mesh.transform * mesh.get_aabb()).size.y > 0.22:
			mesh.set_meta("board_occluder", true)

static func _board_paving(root: Node3D, surface: RefCounted, center: Vector3, edge: Vector3) -> void:
	var tool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var side = edge.cross(Vector3.UP).normalized() * 0.15
	for i in range(5):
		var near = edge * (i / 5.0)
		var far = edge * ((i + 1) / 5.0)
		for point in [near - side, far - side, far + side, near - side, far + side, near + side]:
			point.y = surface.height_at(center + point) + 0.028
			tool.add_vertex(point)
	tool.generate_normals()
	var paving = MeshInstance3D.new()
	paving.mesh = tool.commit()
	paving.material_override = Doll.material(Color("aaa690"))
	paving.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	root.add_child(paving)

static func _tile_features(props: Node3D, definition: Dictionary) -> void:
	if definition.get("burning", false):
		fire(props)
	if definition.get("wet", false):
		_pool(props,Vector3(0,0.012,0.1),Vector3(0.74,1,0.45),Color("739caa"))

static func _land_mesh(variant: int) -> ArrayMesh:
	if land_meshes.has(variant): return land_meshes[variant]
	var tool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertices: Array[Vector3] = []
	for i in range(6):
		var a = PI/6.0+TAU*i/6.0
		var b = PI/6.0+TAU*(i+1)/6.0
		var va = Vector3(cos(a),0,sin(a))
		var vb = Vector3(cos(b),0,sin(b))
		vertices.append_array([Vector3(0,0.075,0),vb*0.935+Vector3.UP*0.075,va*0.935+Vector3.UP*0.075])
		vertices.append_array([va*0.935+Vector3.UP*0.075,vb*0.935+Vector3.UP*0.075,vb*0.977+Vector3.UP*0.018,va*0.935+Vector3.UP*0.075,vb*0.977+Vector3.UP*0.018,va*0.977+Vector3.UP*0.018])
	for v in vertices:
		tool.set_uv(Vector2(v.x,v.z)*0.5+Vector2.ONE*0.5)
		tool.add_vertex(v)
	tool.generate_normals()
	var mesh = tool.commit()
	land_meshes[variant] = mesh
	return mesh

static func _prop(parent: Node3D, name: String, point: Vector3, size: float, turn: float, stretch: Vector3 = Vector3.ONE) -> Node3D:
	if nature_bounds.is_empty():
		nature_bounds = JSON.parse_string(FileAccess.get_file_as_string("res://assets/nature/bounds.json"))
	if not nature_scenes.has(name): nature_scenes[name] = load("res://assets/nature/"+name+"_Color1.gltf")
	var node = nature_scenes[name].instantiate()
	parent.add_child(node)
	_nature_palette(node)
	var bounds = nature_bounds[name]
	var low = Vector3(bounds.min[0],bounds.min[1],bounds.min[2])
	var high = Vector3(bounds.max[0],bounds.max[1],bounds.max[2])
	var dimensions = high-low
	var ratio = size/maxf(dimensions.x,maxf(dimensions.y,dimensions.z))
	node.scale = stretch*ratio
	node.rotation.y = turn
	node.position = point-Vector3.UP*low.y*ratio*stretch.y
	return node

static func _nature_palette(node: Node) -> void:
	if node is MeshInstance3D:
		for surface in range(node.mesh.get_surface_count()):
			var original = node.get_active_material(surface)
			if not original is StandardMaterial3D: continue
			var key = original.albedo_texture.resource_path
			if not nature_materials.has(key):
				var material = ShaderMaterial.new()
				material.shader = preload("res://scripts/presentation/nature_palette.gdshader")
				material.set_shader_parameter("atlas",original.albedo_texture)
				nature_materials[key] = material
			node.set_surface_override_material(surface,nature_materials[key])
	for child in node.get_children(): _nature_palette(child)

static func tree(parent: Node3D, point: Vector3, size: float, pine: bool = true) -> void:
	_prop(parent,"Tree_3_A" if pine else "Tree_1_C",point,size,0.3)

static func _pool(parent: Node3D, point: Vector3, size: Vector3, color: Color) -> void:
	var pool = Doll._cylinder(parent,1,1,0.012,color,point,32)
	pool.scale = size
	var material = pool.material_override
	material.roughness = 0.3
	material.metallic = 0.2

static func _flowers(parent: Node3D, rng: RandomNumberGenerator, count: int) -> void:
	# One shared mesh per patch avoids a draw call for every small blossom.
	var tool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(count):
		var center = Vector3(rng.randf_range(-0.65,0.65),0.018,rng.randf_range(0.23,0.46))
		for v in [Vector3(-0.024,0,0),Vector3(0.02,0,0.02),Vector3(0.01,0,-0.025)]: tool.add_vertex(center+v)
	tool.generate_normals()
	var patch = MeshInstance3D.new()
	patch.mesh = tool.commit()
	patch.material_override = Doll.material(Color("dfcf99"))
	parent.add_child(patch)

static func _ruins(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var variant = rng.randi_range(0,3)
	for i in range(5):
		var slab = Doll._box(parent,Vector3(0.22,0.022,0.19),Color("b5ae91"),Vector3((i%3-1)*0.25,0.015,(i/3)*0.24-0.1))
		slab.rotation.y = rng.randf_range(-0.12,0.12)
	for x in [-0.4,0.4]:
		Doll._box(parent,Vector3(0.27,0.08,0.27),Color("9b9d85"),Vector3(x,0.04,-0.4))
		var height = (0.62 if x<0 else 0.83) if variant==0 else rng.randf_range(0.12,0.47)
		Doll._cylinder(parent,0.095,0.12,height,Color("c8bea0"),Vector3(x,height*0.5+0.08,-0.4),8)
		for j in range(ceili(height/0.2)): Doll._cylinder(parent,0.113,0.113,0.035,Color("aba98d"),Vector3(x,0.13+j*0.2,-0.4),8)
		Doll._box(parent,Vector3(0.25,0.08,0.26),Color("d0c4a4"),Vector3(x,height+0.1,-0.4))
	var lintel = Doll._box(parent,Vector3(0.65,0.13,0.25),Color("aaa58b"),Vector3(0.18,0.93 if variant==0 else 0.09,-0.4 if variant==0 else 0.2))
	lintel.rotation.z = -0.09
	var rubble = Doll._box(parent,Vector3(0.19,0.13,0.22),Color("b6ad91"),Vector3(-0.5,0.08,0.16))
	rubble.rotation.y = 0.6

static func _dunes(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var tool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(3):
		for i in range(10):
			var x = -0.52+i*0.105
			var z = -0.38+j*0.25+sin(x*3+j)*0.07
			var a = Vector3(x,0.024,z)
			var b = Vector3(x+0.106,0.025,z+0.01)
			var c = Vector3(x+0.106,0.021,z+0.028)
			for v in [a,b,c]: tool.add_vertex(v)
	tool.generate_normals()
	var strokes = MeshInstance3D.new()
	strokes.mesh = tool.commit()
	strokes.material_override = Doll.material(Color("bfa16a"))
	parent.add_child(strokes)

static func _reeds(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var tool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(13):
		var p = Vector3(rng.randf_range(-0.1,0.55),0,rng.randf_range(-0.59,-0.36))
		var h = rng.randf_range(0.22,0.42)
		for v in [p-Vector3.RIGHT*0.012,p+Vector3(0.07,h,0),p+Vector3.RIGHT*0.012]: tool.add_vertex(v)
	tool.generate_normals()
	var reeds = MeshInstance3D.new()
	reeds.mesh = tool.commit()
	reeds.material_override = Doll.material(Color("a9ab70"))
	reeds.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	parent.add_child(reeds)

static func fire(parent: Node3D) -> void:
	var particles = CPUParticles3D.new()
	parent.add_child(particles)
	particles.position = Vector3(0,0.06,0)
	particles.amount = 14
	particles.lifetime = 0.85
	particles.preprocess = 0.85
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(0.46,0.01,0.25)
	particles.direction = Vector3.UP
	particles.spread = 12
	particles.gravity = Vector3.ZERO
	particles.initial_velocity_min = 0.3
	particles.initial_velocity_max = 0.6
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.2
	var ramp = Gradient.new()
	ramp.set_color(0,Color("ffe3a9"))
	ramp.set_color(1,Color(0.92,0.4,0.12,0.0))
	particles.color_ramp = ramp
	var quad = QuadMesh.new()
	quad.size = Vector2(0.27,0.56)
	var material = StandardMaterial3D.new()
	material.albedo_texture = preload("res://assets/vfx/flame_01.png")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	quad.material = material
	particles.mesh = quad
	particles.emitting = true

static func _ground_material(terrain: String) -> ShaderMaterial:
	if ground_materials.has(terrain): return ground_materials[terrain]
	var material = ShaderMaterial.new()
	material.shader = preload("res://scripts/presentation/terrain_surface.gdshader")
	material.set_shader_parameter("ground_color",Color(str(Catalog.TERRAIN[terrain].color)))
	material.set_shader_parameter("biome",["plains","forest","mountain","ruins","desert","swamp"].find(terrain))
	ground_materials[terrain] = material
	return material
