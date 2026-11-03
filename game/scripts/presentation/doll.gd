class_name CharacterDoll
extends Node3D
## Original articulated tabletop miniatures. Both map and battle use this exact class.
var skeleton: Skeleton3D
var body: Node3D
var bones: Dictionary = {}
var definition: Dictionary = {}
var phase = 0.0
var action = "idle"
var action_time = 0.0
var down = false
var selected = false
var ring: MeshInstance3D
var is_wolf = false
var home_position = Vector3.ZERO

func configure(character: Dictionary) -> void:
	definition = character.duplicate(true)
	is_wolf = definition.get("id", "") == "grit" or definition.get("type", "") in ["boar", "lurker"]
	_build()

func _build() -> void:
	body = Node3D.new()
	add_child(body)
	skeleton = Skeleton3D.new()
	body.add_child(skeleton)
	var color = Color(str(definition.get("color", "a0b6a0")))
	var dark = color.darkened(0.42)
	var ivory = Color("eee0c6")
	var skin = Color("f1d3b4")
	ring = _cylinder(self, 0.5, 0.5, 0.055, Color("b99e65"), Vector3(0, 0.025, 0), 32)
	_cylinder(self, 0.45, 0.48, 0.05, Color("263d39"), Vector3(0, 0.06, 0), 32)
	if is_wolf:
		_bone("root", -1, Vector3(0, 0.65, 0))
		_bone("head", bones.root, Vector3(0, 0.1, 0.42))
		_bone("tail", bones.root, Vector3(0, 0.1, -0.49))
		for i in range(4):
			_bone("leg%d" % i, bones.root, Vector3(-0.22 if i % 2 == 0 else 0.22, -0.18, -0.28 if i < 2 else 0.28))
		var torso = _attachment("root")
		_sphere(torso, Vector3(0.36, 0.31, 0.65), color, Vector3.ZERO)
		var head = _attachment("head")
		_sphere(head, Vector3(0.29, 0.29, 0.3), color.lightened(0.1), Vector3(0, 0.08, 0.02))
		_sphere(head, Vector3(0.18, 0.12, 0.23), ivory, Vector3(0, -0.05, 0.26))
		_sphere(head, Vector3(0.07, 0.05, 0.05), Color("303c3b"), Vector3(0, -0.02, 0.47))
		for side in [-1, 1]:
			_cone(head, 0.105, 0.23, dark, Vector3(side * 0.18, 0.35, 0.01))
			_sphere(head, Vector3(0.042, 0.045, 0.025), Color("dfb563"), Vector3(side * 0.18, 0.13, 0.25))
		for i in range(4):
			_cylinder(_attachment("leg%d" % i), 0.075, 0.095, 0.38, dark, Vector3(0, -0.17, 0), 8)
		_cone(_attachment("tail"), 0.12, 0.6, color, Vector3(0, 0.15, -0.13)).rotation_degrees.x = -65
	else:
		_bone("root", -1, Vector3(0, 0.8, 0))
		_bone("head", bones.root, Vector3(0, 0.47, 0))
		_bone("arm_l", bones.root, Vector3(-0.29, 0.15, 0))
		_bone("arm_r", bones.root, Vector3(0.29, 0.15, 0))
		_bone("leg_l", bones.root, Vector3(-0.13, -0.22, 0))
		_bone("leg_r", bones.root, Vector3(0.13, -0.22, 0))
		var torso = _attachment("root")
		_cylinder(torso, 0.22, 0.32, 0.52, color, Vector3(0, -0.03, 0), 12)
		_cylinder(torso, 0.24, 0.25, 0.055, Color("c2a26d"), Vector3(0, -0.1, 0), 12)
		var cape = _cone(torso, 0.33, 0.65, dark, Vector3(0, -0.04, -0.12))
		cape.scale = Vector3(1, 1, 0.48)
		var head = _attachment("head")
		_sphere(head, Vector3(0.33, 0.36, 0.31), skin, Vector3(0, 0.05, 0))
		var hair = _hair_color()
		_sphere(head, Vector3(0.35, 0.27, 0.32), hair, Vector3(0, 0.22, -0.03))
		for i in range(5):
			var bang = _cone(head, 0.11, 0.24, hair, Vector3(-0.24 + i * 0.12, 0.23, 0.24))
			bang.rotation_degrees.z = 165 - i * 4
		for side in [-1, 1]:
			_sphere(head, Vector3(0.04, 0.061, 0.025), Color("33433d"), Vector3(side * 0.12, 0.04, 0.288))
			_sphere(head, Vector3(0.012, 0.017, 0.01), Color("fff5dc"), Vector3(side * 0.115, 0.055, 0.311))
		if definition.get("id", "") == "eve":
			for side in [-1, 1]:
				var ear = _cone(head, 0.08, 0.28, skin, Vector3(side * 0.36, 0.05, 0))
				ear.rotation_degrees.z = side * -80
			_sphere(head, Vector3(0.28, 0.38, 0.15), hair, Vector3(0, 0.03, -0.23))
		for side in ["l", "r"]:
			var arm = _attachment("arm_" + side)
			_cylinder(arm, 0.105, 0.09, 0.37, color, Vector3(0, -0.15, 0), 10)
			_sphere(arm, Vector3(0.095, 0.095, 0.095), skin, Vector3(0, -0.36, 0.01))
			var leg = _attachment("leg_" + side)
			_cylinder(leg, 0.09, 0.10, 0.36, Color("4d5149"), Vector3(0, -0.18, 0), 10)
			_sphere(leg, Vector3(0.115, 0.09, 0.16), dark, Vector3(0, -0.36, 0.04))
		var hand = _attachment("arm_r")
		if definition.get("skill", "") in ["ember", "torrent", "heal", "ignite", "wet"]:
			_cylinder(hand, 0.025, 0.035, 1.0, Color("6a5742"), Vector3(0.04, -0.1, 0.07), 8)
			_sphere(hand, Vector3(0.11, 0.14, 0.11), color.lightened(0.3), Vector3(0.04, 0.43, 0.07))
		else:
			var blade = _box(hand, Vector3(0.09, 0.6, 0.035), Color("d9d9c4"), Vector3(0, -0.05, 0.12))
			blade.rotation_degrees.x = -20
			_box(hand, Vector3(0.25, 0.045, 0.06), Color("c3a66d"), Vector3(0, -0.32, 0.02))
	for i in range(skeleton.get_bone_count()):
		skeleton.reset_bone_pose(i)

func _hair_color() -> Color:
	var colors = {"hero": "544c43", "cen": "553e30", "lorne": "b69b6f", "eve": "dedfcb", "ember": "783c32", "tide": "477a88"}
	return Color(colors.get(str(definition.get("id", "hero")), "5b5d52"))

func _bone(bone_name: String, parent: int, offset: Vector3) -> void:
	var index = skeleton.add_bone(bone_name)
	bones[bone_name] = index
	skeleton.set_bone_parent(index, parent)
	skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, offset))

func _attachment(bone_name: String) -> BoneAttachment3D:
	var attachment = BoneAttachment3D.new()
	attachment.bone_name = bone_name
	skeleton.add_child(attachment)
	return attachment

func play_action(kind: String) -> void:
	action = kind
	action_time = 0.0

func set_down(value: bool) -> void:
	down = value

func _process(delta: float) -> void:
	if skeleton == null:
		return
	phase += delta
	action_time += delta
	if action_time > 0.75 and action not in ["idle", "walk"]:
		action = "idle"
	var walk = sin(phase * 10.0) * 0.55 if action == "walk" else sin(phase * 2.0) * 0.025
	var attack = sin(clampf(action_time / 0.6, 0, 1) * PI) if action in ["attack", "cast", "ultimate", "hit", "heal"] else 0.0
	var lean = -attack * 0.28 if action == "attack" else attack * 0.12
	body.rotation.z = lerpf(body.rotation.z, 1.35 if down else 0.0, minf(1.0, delta * 9.0))
	body.position.y = sin(phase * 2.5) * 0.015 if not down else -0.4
	skeleton.set_bone_pose_rotation(bones.root, Quaternion(Vector3.RIGHT, lean))
	if is_wolf:
		for i in range(4):
			skeleton.set_bone_pose_rotation(bones["leg%d" % i], Quaternion(Vector3.RIGHT, walk * (-1 if i % 2 == 0 else 1)))
		skeleton.set_bone_pose_rotation(bones.head, Quaternion(Vector3.RIGHT, -attack * 0.45))
		skeleton.set_bone_pose_rotation(bones.tail, Quaternion(Vector3.FORWARD, sin(phase * 3) * 0.13))
	else:
		skeleton.set_bone_pose_rotation(bones.leg_l, Quaternion(Vector3.RIGHT, walk))
		skeleton.set_bone_pose_rotation(bones.leg_r, Quaternion(Vector3.RIGHT, -walk))
		skeleton.set_bone_pose_rotation(bones.arm_l, Quaternion(Vector3.RIGHT, -walk * 0.5 - (attack if action in ["cast", "ultimate", "heal"] else 0.0)))
		skeleton.set_bone_pose_rotation(bones.arm_r, Quaternion(Vector3.RIGHT, walk * 0.5 - attack * 1.5))
		skeleton.set_bone_pose_rotation(bones.head, Quaternion(Vector3.UP, sin(phase * 0.8) * 0.08))
	if ring:
		ring.material_override.albedo_color = Color("ffe2a0") if selected else Color("b99e65")

static func material(color: Color) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.92
	return m

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
