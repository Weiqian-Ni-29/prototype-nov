extends Node3D
## World-space selection markers and forgiving hit volumes for the battle dolls.
const FontAsset = preload("res://assets/fonts/NotoSansSC.ttf")
const BASE_BOUNDS = AABB(Vector3(-0.56, -0.05, -0.56), Vector3(1.12, 0.16, 1.12))
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

func update_markers(dolls: Dictionary, alive: Array[String]) -> void:
	_place_marker(selected, dolls.get(selected_id) if selected_id in alive else null)
	_place_marker(preview, dolls.get(hovered_id) if hovered_id in alive and hovered_id != selected_id else null)
	if selected.visible:
		var doll = dolls[selected_id]
		var size: Vector3 = BODY_SIZES[doll.family]
		arrow.position.y = size.y * doll.body.scale.y + 0.28 \
			+ (doll.body.global_position.y - doll.global_position.y) / doll.scale.x

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
