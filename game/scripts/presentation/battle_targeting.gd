extends Node3D
## World-space selection markers and forgiving hit volumes for the battle dolls.
const FontAsset = preload("res://assets/fonts/NotoSansSC.ttf")
const BASE_BOUNDS = AABB(Vector3(-0.56, -0.05, -0.56), Vector3(1.12, 0.16, 1.12))
const ARROW_CLEARANCE = 0.34
const BODY_SIZES = {
	"humanoid": Vector3(1.05, 1.85, 1.05),
	"quadruped": Vector3(1.08, 1.13, 1.85),
	"spider": Vector3(1.47, 0.84, 1.45),
	"swarm": Vector3(1.42, 1.10, 1.28),
}

var selected_id = ""
var hovered_id = ""
var selected: Node3D
var preview: Node3D
var selected_ring: Node3D
var arrow: Label3D
var pulse: Tween

func _ready() -> void:
	selected = Node3D.new()
	selected.name = "SelectedEnemy"
	add_child(selected)
	selected_ring = Node3D.new()
	selected.add_child(selected_ring)
	_ring(selected_ring, 0.53, 0.66, Color("42351f"), 0.0)
	_ring(selected_ring, 0.55, 0.63, Color("ffd367"), 0.012)
	arrow = Label3D.new()
	arrow.text = "▼"
	arrow.font = FontAsset
	arrow.font_size = 42
	arrow.pixel_size = 0.008
	arrow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	arrow.no_depth_test = true
	arrow.modulate = Color("ffd367")
	arrow.outline_modulate = Color("42351f")
	arrow.outline_size = 9
	selected.add_child(arrow)
	preview = Node3D.new()
	preview.name = "HoveredEnemy"
	add_child(preview)
	_ring(preview, 0.55, 0.61, Color(1.0, 0.85, 0.53, 0.55), 0.01)
	selected.hide()
	preview.hide()

func _ring(parent: Node3D, inside: float, outside: float, color: Color, height: float) -> void:
	var ring_mesh = TorusMesh.new()
	ring_mesh.inner_radius = inside
	ring_mesh.outer_radius = outside
	ring_mesh.rings = 48
	ring_mesh.ring_segments = 12
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var ring = MeshInstance3D.new()
	ring.mesh = ring_mesh
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.y = height
	ring.scale.y = 0.35
	parent.add_child(ring)

func select(id: String) -> void:
	if selected_id == id:
		return
	selected_id = id
	if pulse != null:
		pulse.kill()
	selected_ring.scale = Vector3.ONE
	if not id.is_empty():
		selected_ring.scale = Vector3(1.16, 1.0, 1.16)
		pulse = create_tween()
		pulse.tween_property(selected_ring, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func update_markers(camera: Camera3D, dolls: Dictionary, alive: Array[String]) -> void:
	_place_marker(selected, dolls.get(selected_id) if selected_id in alive else null)
	_place_marker(preview, dolls.get(hovered_id) if hovered_id in alive and hovered_id != selected_id else null)
	if selected.visible:
		var doll = dolls[selected_id]
		var screen_up = camera.global_basis.y
		var origin: Vector3 = doll.body.global_position
		var top = _silhouette_top(doll, screen_up)
		# Move along camera-up so the entire billboard sits above the projected model.
		arrow.global_position = origin + screen_up * (top - screen_up.dot(origin) + ARROW_CLEARANCE * doll.scale.x)

func _silhouette_top(doll: Node3D, screen_up: Vector3) -> float:
	if not doll.has_meta("target_silhouette"):
		var pieces: Array = []
		for mesh in doll.body.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh == null or not mesh.is_visible_in_tree():
				continue
			if mesh.skin == null:
				pieces.append([mesh, -1, mesh.get_aabb()])
			else:
				var bounds = _bone_bounds(mesh, doll.skeleton)
				for bone in bounds:
					pieces.append([mesh, bone, bounds[bone]])
		doll.set_meta("target_silhouette", pieces)
	var top: float = screen_up.dot(doll.body.global_position)
	var skeleton: Skeleton3D = doll.skeleton
	for piece in doll.get_meta("target_silhouette"):
		var mesh: MeshInstance3D = piece[0]
		if not mesh.is_visible_in_tree():
			continue
		var bone: int = piece[1]
		var box: AABB = piece[2]
		var pose = mesh.global_transform if bone == -1 else skeleton.global_transform * skeleton.get_bone_global_pose(bone)
		var extent = (pose.basis.transposed() * screen_up).abs().dot(box.size * 0.5)
		top = maxf(top, screen_up.dot(pose * box.get_center()) + extent)
	return top

func _bone_bounds(mesh: MeshInstance3D, skeleton: Skeleton3D) -> Dictionary:
	# Cache a box per contributing bone in bind space. A weighted vertex is contained
	# by the envelope of those boxes after the current bone poses are applied.
	var bounds = {}
	var skin = mesh.skin
	var bone_ids: Array[int] = []
	var bind_poses: Array[Transform3D] = []
	for bind in skin.get_bind_count():
		var name = skin.get_bind_name(bind)
		bone_ids.append(skeleton.find_bone(name) if name != &"" else skin.get_bind_bone(bind))
		bind_poses.append(skin.get_bind_pose(bind))
	for surface in mesh.mesh.get_surface_count():
		var arrays = mesh.mesh.surface_get_arrays(surface)
		var vertices = arrays[Mesh.ARRAY_VERTEX]
		var joints = arrays[Mesh.ARRAY_BONES]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		if joints == null or weights == null or vertices.is_empty():
			continue
		var stride = floori(float(joints.size()) / vertices.size())
		for i in vertices.size():
			for j in stride:
				var index = i * stride + j
				if weights[index] <= 0.0:
					continue
				var bind = joints[index]
				var bone = bone_ids[bind]
				if bone < 0:
					continue
				var point: Vector3 = bind_poses[bind] * vertices[i]
				var box: AABB = bounds.get(bone, AABB(point, Vector3.ZERO))
				bounds[bone] = box.expand(point)
	return bounds

func _place_marker(marker: Node3D, doll: Node3D) -> void:
	marker.visible = is_instance_valid(doll) and doll.is_visible_in_tree()
	if marker.visible:
		var body_position: Vector3 = doll.body.global_position
		marker.global_position = Vector3(body_position.x, doll.global_position.y + 0.044, body_position.z)
		marker.scale = Vector3.ONE * doll.scale.x

func pick(camera: Camera3D, screen_position: Vector2, dolls: Dictionary, alive: Array[String]) -> String:
	var origin = camera.project_ray_origin(screen_position)
	var direction = camera.project_ray_normal(screen_position)
	var nearest = INF
	var picked = ""
	for id in alive:
		var doll = dolls.get(id)
		if not is_instance_valid(doll) or not doll.is_visible_in_tree():
			continue
		var size: Vector3 = BODY_SIZES[doll.family]
		var body_bounds = AABB(Vector3(-size.x * 0.5, 0.0, -size.z * 0.5), size)
		var distance = minf(_hit_distance(body_bounds, doll.body.global_transform, origin, direction),
			_hit_distance(BASE_BOUNDS, doll.global_transform, origin, direction))
		if distance < nearest:
			nearest = distance
			picked = id
	return picked

func _hit_distance(bounds: AABB, pose: Transform3D, origin: Vector3, direction: Vector3) -> float:
	var inverse = pose.affine_inverse()
	var hit = bounds.intersects_ray(inverse * origin, inverse.basis * direction)
	return origin.distance_squared_to(pose * hit) if hit != null else INF
