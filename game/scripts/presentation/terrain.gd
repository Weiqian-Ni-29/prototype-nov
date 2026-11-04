class_name TerrainArt
extends RefCounted
const Doll = preload("res://scripts/presentation/doll.gd")
const Catalog = preload("res://scripts/domain/catalog.gd")
static var ground_materials: Dictionary = {}

static var nature_scenes: Dictionary = {}
static var nature_bounds: Dictionary = {}
static var land_meshes: Dictionary = {}
static var nature_materials: Dictionary = {}

static func tile(parent: Node3D, definition: Dictionary, revealed: bool, visual_seed: int) -> Node3D:
	var root = Node3D.new()
	parent.add_child(root)
	var terrain = str(definition.terrain)
	var color = Color(str(Catalog.TERRAIN[terrain].color)) if revealed else Color("536c79")
	var height = float(definition.get("height", 0.0)) if revealed else 0.0
	# Chamfered tabletop edges and exposed soil give each cell a crafted, physical thickness.
	var base = Doll._cylinder(root,0.973,0.978,0.25+height,color.darkened(0.32),Vector3(0,-0.125+height*0.5,0),6)
	var rim = Doll._cylinder(root,0.975,0.975,0.035,color.darkened(0.17),Vector3(0,-0.025+height,0),6)
	var top = MeshInstance3D.new()
	root.add_child(top)
	top.mesh = _land_mesh(visual_seed%7)
	top.position.y = height
	if not revealed:
		var fog_material = Doll.material(color)
		fog_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		top.material_override = fog_material
		return root
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
		"scorched":
			_prop(props,"Tree_Bare_1_A",Vector3(-0.34,0,-0.28),0.78,turn)
			_prop(props,"Rock_1_A",Vector3(0.4,0,-0.28),0.31,turn)
			for i in range(3): Doll._cylinder(props,0.035,0.065,0.24,Color("4b4c42"),Vector3(-0.4+i*0.31,0.12,0.25),7)
	if definition.get("camp", false):
		var tent = Doll._cone(props,0.34,0.42,Color("d7bd8c"),Vector3(0,0.21,0.15))
		tent.scale.z = 0.8
	if definition.get("site", "")!="": landmark(props,str(definition.site))
	elif definition.get("quantity",0)>0 and definition.get("enemies",[]).is_empty():
		var crate = Doll._box(props,Vector3(0.24,0.18,0.2),Color("aa8054"),Vector3(0.42,0.12,0.24))
		for i in [-1,1]: Doll._box(props,Vector3(0.26,0.025,0.215),Color("d6ba7c"),Vector3(0.42,0.12+i*0.055,0.24))
	if definition.get("burning",false): fire(props)
	elif definition.get("wet_until",0)>definition.get("current_day",1):
		_pool(props,Vector3(0,0.012,0.1),Vector3(0.74,1,0.45),Color("739caa"))
	return root

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

static func _prop(parent: Node3D, name: String, point: Vector3, size: float, turn: float, stretch: Vector3 = Vector3.ONE) -> void:
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
	material.set_shader_parameter("biome",["plains","forest","mountain","ruins","desert","swamp","scorched"].find(terrain))
	ground_materials[terrain] = material
	return material
