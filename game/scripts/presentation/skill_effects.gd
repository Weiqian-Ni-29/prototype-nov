extends Node3D
## Original Compatibility-renderer effects using the nine documented Kenney CC0 textures.
const Shape = preload("res://scripts/presentation/doll.gd")
const FontAsset = preload("res://assets/fonts/NotoSansSC.ttf")
const SHIELD_SHADER = preload("res://scripts/presentation/shield.gdshader")
var materials: Dictionary = {}

func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

func flash(point: Vector3, texture_name: String, color: Color, size: float = 1.0) -> void:
	var sprite = Sprite3D.new()
	add_child(sprite)
	sprite.texture = load("res://assets/vfx/" + texture_name + ".png")
	sprite.pixel_size = size / 512.0
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.no_depth_test = false
	sprite.shaded = false
	sprite.modulate = color
	sprite.position = point
	var tween = sprite.create_tween().set_parallel(true)
	tween.tween_property(sprite,"scale",Vector3.ONE*1.3,0.3)
	tween.tween_property(sprite,"modulate:a",0.0,0.3)
	tween.chain().tween_callback(sprite.queue_free)

func ring(point: Vector3, color: Color, radius: float = 1.0, duration: float = 0.6) -> void:
	var mesh = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.94
	torus.outer_radius = 1.0
	torus.ring_segments = 24
	torus.rings = 5
	mesh.mesh = torus
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	mesh.material_override = material
	add_child(mesh)
	mesh.position = point
	mesh.scale = Vector3.ONE * 0.1
	var tween = mesh.create_tween().set_parallel(true)
	tween.tween_property(mesh,"scale",Vector3.ONE*radius,duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(material,"albedo_color:a",0.0,duration)
	tween.chain().tween_callback(mesh.queue_free)

func burst(point: Vector3, texture_name: String, color: Color, count: int = 14, duration: float = 0.6) -> void:
	var particles = CPUParticles3D.new()
	add_child(particles)
	particles.position = point
	particles.amount = count
	particles.lifetime = duration
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.direction = Vector3.UP
	particles.spread = 60
	particles.gravity = Vector3(0,-0.5,0)
	particles.initial_velocity_min = 0.4
	particles.initial_velocity_max = 1.7
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.1
	particles.color = color
	var quad = QuadMesh.new()
	quad.size = Vector2(0.22,0.22)
	var key = texture_name
	if not materials.has(key):
		var material = StandardMaterial3D.new()
		material.albedo_texture = load("res://assets/vfx/"+texture_name+".png")
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		material.vertex_color_use_as_albedo = true
		materials[key] = material
	quad.material = materials[key]
	particles.mesh = quad
	particles.emitting = true
	get_tree().create_timer(duration+0.25).timeout.connect(particles.queue_free)

func shield(point: Vector3, color: Color, size: float = 0.7) -> void:
	var bubble = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = size
	sphere.height = size*2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	bubble.mesh = sphere
	var material = ShaderMaterial.new()
	material.shader = SHIELD_SHADER
	material.set_shader_parameter("tint",color)
	bubble.material_override = material
	add_child(bubble)
	bubble.position = point
	var tween = bubble.create_tween()
	tween.tween_property(bubble,"scale",Vector3.ONE*1.12,0.22)
	tween.tween_property(bubble,"scale",Vector3.ONE*0.02,0.3)
	tween.tween_callback(bubble.queue_free)

func number(point: Vector3, text: String, color: Color) -> void:
	var label = Label3D.new()
	label.font = FontAsset
	label.font_size = 48
	label.outline_size = 9
	label.pixel_size = 0.006
	label.text = text
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = point
	add_child(label)
	var tween = label.create_tween().set_parallel(true)
	tween.tween_property(label,"position:y",point.y+0.6,0.8)
	tween.tween_property(label,"modulate:a",0.0,0.35).set_delay(0.45)
	tween.chain().tween_callback(label.queue_free)

const ELEMENT_COLORS = {
	"normal": Color("e6c98a"), "fire": Color("ef8749"), "water": Color("7fd3e2"),
	"ice": Color("b8e8ff"), "lightning": Color("d5b4ff"), "wind": Color("b1f5c5"), "earth": Color("dbad73"),
}

func projectile(start: Vector3, end: Vector3, kind: String, element: String, duration: float = 0.22) -> void:
	var root = Node3D.new()
	add_child(root)
	root.position = start
	var color = ELEMENT_COLORS.get(element, Color.WHITE)
	if kind in ["bow","crossbow"]:
		root.add_child(load("res://assets/characters/arrow_crossbow.gltf" if kind=="crossbow" else "res://assets/characters/arrow_bow.gltf").instantiate())
		root.look_at(end)
		root.scale = Vector3.ONE*0.9
	elif element=="fire":
		Shape._sphere(root,Vector3.ONE*0.21,color,Vector3.ZERO)
		burst(start,"flame_01",color,8,0.35)
	elif element=="water":
		var drop = Shape._sphere(root,Vector3(0.13,0.27,0.13),color,Vector3.ZERO)
		drop.rotation.z = -0.4
	elif element == "earth":
		var shard = Shape._box(root, Vector3(0.19, 0.29, 0.18), color, Vector3.ZERO)
		shard.rotation.z = 0.45
	else:
		Shape._sphere(root,Vector3.ONE*0.09,color,Vector3.ZERO)
		flash(start,"magic_01",color,0.6)
	var tween = root.create_tween()
	tween.tween_property(root,"position",end,duration).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(root.queue_free)

func ultimate_start(skill: String, actor: Vector3, targets: Array) -> void:
	match skill:
		"rally": ring(actor+Vector3.UP*0.15,Color("e9d498"),4.5,0.8)
		"dawn_strike": ring(actor+Vector3.UP*0.15,Color("ffe0a1"),2.5,0.5)
		"arrow_rain":
			for target in targets:
				for i in range(4):
					var offset = Vector3((i%2-0.5)*0.28,3.4+i*0.17,(i/2-0.5)*0.25)
					projectile(target+offset,target,"bow","normal",0.22)
		"warmth":
			ring(actor+Vector3.UP*0.1,Color("b9db99"),4.2,1.0)
			for target in targets: burst(target-Vector3.UP*0.5,"star_01",Color("c8e1a5"),18,1.0)
		"wolf_howl":
			for i in range(3): ring(actor+Vector3.UP*(0.2+i*0.25),Color("bdced9"),2.2+i*0.8,0.6+i*0.15)
		"sunfall":
			for target in targets:
				projectile(target+Vector3.UP*4.4,target,"magic","fire",0.22)
		"tide_shelter":
			for target in targets:
				ring(Vector3(target.x,0.18,target.z),Color("8bdae0"),0.9,0.8)
				burst(target-Vector3.UP*0.5,"circle_01",Color("93d3dd"),18,0.9)

		"frostfall":
			for target in targets:
				ring(target - Vector3.UP * 0.5, ELEMENT_COLORS.ice, 1.0, 0.6)
				burst(target, "star_01", ELEMENT_COLORS.ice, 16, 0.65)
		"thunderstorm":
			for target in targets:
				projectile(target + Vector3.UP * 3.8, target, "magic", "lightning")
				flash(target, "magic_01", ELEMENT_COLORS.lightning, 1.35)
		"tailwind":
			for target in targets:
				ring(target - Vector3.UP * 0.5, ELEMENT_COLORS.wind, 1.4, 0.65)
		"stonewall":
			for target in targets:
				ring(target - Vector3.UP * 0.5, ELEMENT_COLORS.earth, 1.25, 0.7)

func impact(event: Dictionary, result: Dictionary, point: Vector3) -> void:
	if result.get("damage",0)>0:
		number(point+Vector3.UP*0.7,"−%d" % result.damage,Color("f2d4b4"))
		var color = ELEMENT_COLORS.get(event.element, Color.WHITE)
		var sprite = {"normal": "slash_01", "fire": "fire_01", "lightning": "magic_01", "wind": "slash_01"}.get(event.element, "trace_01")
		flash(point, sprite, color, 0.8)
		burst(point, "star_01" if event.element == "ice" else "spark_01", color, 10, 0.4)
	if result.get("slow", 0) > 0:
		number(point + Vector3.UP, "减速 %d" % result.slow, ELEMENT_COLORS.ice)
	if result.get("haste", 0) > 0:
		number(point + Vector3.UP * 0.8, "提速", ELEMENT_COLORS.wind)
	if result.get("healing",0)>0:
		number(point+Vector3.UP*0.65,"治疗 +%d" % result.healing,Color("b4dc9f"))
		burst(point,"star_01",Color("b9df9d"),12)
	if result.get("shield_gain",0)>0:
		number(point+Vector3.UP*1.0,"护盾 +%d" % result.shield_gain,Color("a2d7df"))
		shield(point,Color("aad5dd"))
	if result.get("absorbed",0)>0:
		number(point+Vector3.UP*1.0,"吸收 %d" % result.absorbed,Color("a5d5df"))
		shield(point,Color("b0d6db"))
	if result.get("mp_gain",0)>0:
		number(point+Vector3.UP*0.8,"魔力 +%d" % result.mp_gain,Color("b9bded"))
