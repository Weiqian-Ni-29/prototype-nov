class_name CharacterDoll
extends Node3D
## Shared skinned actor for exploration and battle. AnimationPlayer owns every bone.
var skeleton: Skeleton3D
var body: Node3D
var bones: Dictionary = {}
var definition: Dictionary = {}
var selected = false
var down = false
var ring: MeshInstance3D
var is_wolf = false
var family = "humanoid"
var rigged: Node3D
var action = "idle"
var move_tween: Tween
var movement_queue: Array[Vector3] = []
var movement_target = Vector3.INF
var map_height_source: RefCounted

func configure(character: Dictionary) -> void:
	definition = character.duplicate(true)
	var type = str(definition.get("type",""))
	family = "spider" if type in ["spider","hunter_elite"] else "swarm" if type=="swarm" else "quadruped" if definition.get("id","")=="grit" or type in ["boar","lurker"] else "humanoid"
	is_wolf = family=="quadruped"
	rigged = preload("res://scripts/presentation/rigged_doll.gd").new()
	add_child(rigged)
	rigged.configure(definition)
	skeleton = rigged.skeleton
	bones = rigged.bones
	body = rigged.body
	ring = _cylinder(self,0.5,0.5,0.035,Color("b99e65"),Vector3(0,0.02,0),32)

func play_action(kind: String, duration: float = -1.0) -> void:
	action = kind
	rigged.play_action(kind,duration)

func set_down(value: bool) -> void:
	if value and is_moving():
		var endpoint = movement_queue[-1] if not movement_queue.is_empty() else movement_target
		move_tween.kill()
		movement_queue.clear()
		position = endpoint
		movement_target = Vector3.INF
		rigged.animator.speed_scale = 1.0
	down = value
	rigged.set_down(value)

func is_moving() -> bool:
	return move_tween!=null and move_tween.is_valid() and move_tween.is_running()

func move_to(point: Vector3) -> void:
	if point.is_equal_approx(movement_target) or (not movement_queue.is_empty() and movement_queue[-1].is_equal_approx(point)): return
	movement_queue.append(point)
	if not is_moving(): _next_movement()

func _next_movement() -> void:
	if movement_queue.is_empty():
		movement_target = Vector3.INF
		if not down: play_action("idle")
		return
	var point = movement_queue.pop_front()
	movement_target = point
	var direction = point-position
	var distance = Vector2(direction.x,direction.z).length()
	if distance>0.02: rotation.y = atan2(direction.x,direction.z)
	var duration = clampf(distance/2.1,0.12,0.95)/(1.0+0.25*movement_queue.size())
	play_action("run" if distance>0.7 else "walk")
	var stride = 0.85 if family=="quadruped" else 0.42 if family=="spider" else 1.4
	var length = rigged.animator.current_animation_length
	rigged.animator.speed_scale = maxf(0.3,distance/maxf(0.01,duration*stride*scale.x))*length
	move_tween = create_tween()
	if map_height_source != null:
		move_tween.tween_method(_map_step, position, point, duration).set_trans(Tween.TRANS_LINEAR)
	else:
		move_tween.tween_property(self,"position",point,duration).set_trans(Tween.TRANS_LINEAR)
	move_tween.tween_callback(func(): rigged.animator.speed_scale=1.0; _next_movement())

func _map_step(point: Vector3) -> void:
	point.y = map_height_source.height_at(point) + 0.025
	position = point

func _process(_delta: float) -> void:
	if ring: ring.material_override.albedo_color = Color("ffe2a0") if selected else Color("b99e65")

static func material(color: Color) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.92
	return m

static func _bow(parent: Node3D) -> void:
	var points: Array[Vector3] = []
	for i in range(9):
		var angle = -PI / 2 + i * PI / 8
		points.append(Vector3(0.12 + cos(angle) * 0.2, -0.1 + sin(angle) * 0.48, 0.12))
	for i in range(8):
		var delta = points[i + 1] - points[i]
		var segment = _cylinder(parent, 0.022, 0.027, delta.length(), Color("917149"), (points[i] + points[i + 1]) * 0.5, 6)
		segment.quaternion = Quaternion(Vector3.UP, delta.normalized())
	_cylinder(parent, 0.006, 0.006, 0.96, Color("e5d9ae"), Vector3(0.12, -0.1, 0.12), 4)

static func _mesh(parent: Node3D, mesh: Mesh, color: Color, offset: Vector3) -> MeshInstance3D:
	var instance = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material(color)
	instance.position = offset
	parent.add_child(instance)
	return instance

static func _sphere(parent: Node3D, size: Vector3, color: Color, offset: Vector3) -> MeshInstance3D:
	var mesh = SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	var instance = _mesh(parent, mesh, color, offset)
	instance.scale = size
	return instance

static func _cylinder(parent: Node3D, top: float, bottom: float, height: float, color: Color, offset: Vector3, segments: int = 12) -> MeshInstance3D:
	var mesh = CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = segments
	return _mesh(parent, mesh, color, offset)

static func _cone(parent: Node3D, radius: float, height: float, color: Color, offset: Vector3) -> MeshInstance3D:
	return _cylinder(parent, 0.0, radius, height, color, offset, 9)

static func _box(parent: Node3D, size: Vector3, color: Color, offset: Vector3) -> MeshInstance3D:
	var mesh = BoxMesh.new()
	mesh.size = size
	return _mesh(parent, mesh, color, offset)
