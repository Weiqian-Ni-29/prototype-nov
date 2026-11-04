extends Node3D
## Decorative ocean has no entries in the navigable map and reveals no land contents.
const Hex = preload("res://scripts/domain/hex_map.gd")
const WATER = preload("res://scripts/presentation/ocean.gdshader")
var sea_cells: Array[String] = []

func build(tiles: Dictionary) -> void:
	for child in get_children(): child.free()
	sea_cells.clear()
	var radius = 0
	for id in tiles: radius = maxi(radius,Hex.distance(Hex.coord(id),Vector2i.ZERO))
	var mesh = _hex_mesh()
	var positions: Array[Vector3] = []
	var depths: Array[float] = []
	for q in range(-radius-5,radius+6):
		for r in range(-radius-5,radius+6):
			var coord = Vector2i(q,r)
			var distance = Hex.distance(coord,Vector2i.ZERO)
			var id = Hex.key(coord)
			if distance>radius+5 or tiles.has(id): continue
			sea_cells.append(id)
			positions.append(Hex.world(id)+Vector3(0,-0.16,0))
			depths.append(clampf(float(distance-radius-1)/3.5,0.0,1.0))
	var batch = MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_custom_data = true
	batch.mesh = mesh
	batch.instance_count = positions.size()
	for i in range(positions.size()):
		batch.set_instance_transform(i,Transform3D(Basis.IDENTITY,positions[i]))
		batch.set_instance_custom_data(i,Color(depths[i],0,0,1))
	var instance = MultiMeshInstance3D.new()
	instance.multimesh = batch
	var material = ShaderMaterial.new()
	material.shader = WATER
	instance.material_override = material
	add_child(instance)
	var distant = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(600,600)
	distant.mesh = plane
	distant.position.y = -0.18
	var far_material = ShaderMaterial.new()
	far_material.shader = WATER
	far_material.set_shader_parameter("far_water",true)
	distant.material_override = far_material
	add_child(distant)
	# Only edges of the island carry short, broken foam strokes.
	var foam = SurfaceTool.new()
	foam.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments = 0
	for id in tiles:
		var p = Hex.coord(id)
		for direction in Hex.DIRECTIONS:
			if tiles.has(Hex.key(p+direction)): continue
			var center = Hex.world(id)
			var normal = (Hex.world(Hex.key(p+direction))-center).normalized()
			var tangent = Vector3(-normal.z,0,normal.x)
			for j in range(2):
				var c = center+normal*1.025+tangent*(-0.24+j*0.46)
				c.y = -0.145
				var a = c-tangent*0.17
				var b = c+tangent*0.17
				var d = normal*0.023
				for v in [a-d,b-d,b+d,a-d,b+d,a+d]: foam.add_vertex(v)
				segments += 1
	if segments>0:
		var strokes = MeshInstance3D.new()
		strokes.mesh = foam.commit()
		var mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = Color("91cbd0")
		strokes.material_override = mat
		add_child(strokes)

func _hex_mesh() -> ArrayMesh:
	var tool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(6):
		var a = PI/6.0+TAU*i/6.0
		var b = PI/6.0+TAU*(i+1)/6.0
		for v in [Vector3.ZERO,Vector3(cos(b),0,sin(b))*0.997,Vector3(cos(a),0,sin(a))*0.997]:
			tool.set_normal(Vector3.UP)
			tool.set_uv(Vector2(0 if v==Vector3.ZERO else 1,0))
			tool.add_vertex(v)
	return tool.commit()
