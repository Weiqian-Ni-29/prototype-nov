class_name ExpeditionView
extends Node3D
const Hex = preload("res://scripts/domain/hex_map.gd")
const Terrain = preload("res://scripts/presentation/terrain.gd")
const Doll = preload("res://scripts/presentation/doll.gd")
const FontAsset = preload("res://assets/fonts/NotoSansSC.ttf")
const Catalog = preload("res://scripts/domain/catalog.gd")
const Board = preload("res://scripts/presentation/board_surface.gd")
const Landmarks = preload("res://scripts/presentation/map_landmarks.gd")
const Nodes = preload("res://scripts/domain/map_nodes.gd")
const OCCLUSION = preload("res://scripts/presentation/board_occlusion.gdshader")
const GROUND_FADE = preload("res://scripts/presentation/board_ground_fade.gdshader")
const NATURE_PALETTE = preload("res://scripts/presentation/nature_palette.gdshader")
const MAP_PLANE = Plane(Vector3.UP, 0.05)
const DRAG_THRESHOLD = 8.0
const DEFAULT_MAP_ZOOM = 5.5
const MIN_MAP_ZOOM = 3.8
const MAX_MAP_ZOOM = 38.0
const MAP_ZOOM_STEP = 1.14
const OCCLUSION_ZOOM = 9.0
const FOG_REVEAL_SECONDS = 0.7
const FOG_REVEAL_PRIORITY = 2
signal cell_clicked(id: String)
var hero_marker = preload("res://scripts/presentation/squad_markers.gd").new()
var camera: Camera3D
var light: DirectionalLight3D
var map_root: Node3D
var actor_root: Node3D
var landmark_root: Node3D
var landmarks: Dictionary = {}
var revealing_cells: Dictionary = {}
var tile_nodes: Dictionary = {}
var dolls: Dictionary = {}
var tile_signatures: Dictionary = {}
var current_tiles: Dictionary = {}
var focus_point = Vector3.ZERO
var map_follow_actor: Node3D
var map_follow_offset = Vector3.ZERO
var map_min = Vector3.ZERO
var map_max = Vector3.ZERO
var zoom_size: float = DEFAULT_MAP_ZOOM
var map_pointer_down = false
var map_dragging = false
var map_pointer_position = Vector2.ZERO
var selection_ring: MeshInstance3D
var rain: CPUParticles3D
var ocean: Node3D
var map_batch: Node3D
var canopy_batch: Node3D
var canopy_individual = false
var chunk_occluders: Dictionary
var board_surface = Board.new()
var board_mesh: Node3D
var board_fog: Node3D
var board_fringe: Node3D
var fog_reveals: Node3D
var board_ground_material: ShaderMaterial
var board_fog_material: ShaderMaterial
var board_fringe_material: ShaderMaterial
var board_stamp: Dictionary
var outline_cell = ""
var map_occluders: Array[MeshInstance3D] = []
var fading_occluders: Dictionary

func _ready() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("23577b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e2ddbe")
	environment.ambient_light_energy = 0.42
	var world_environment = WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -35, 0)
	light.light_color = Color("ffe5b2")
	light.light_energy = 0.68
	light.shadow_enabled = true
	add_child(light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = zoom_size
	camera.far = 150
	camera.current = true
	add_child(camera)
	map_root = Node3D.new()
	actor_root = Node3D.new()
	landmark_root = Node3D.new()
	landmark_root.name = "MapLandmarks"
	add_child(map_root)
	add_child(actor_root)
	add_child(landmark_root)
	var marker_canvas = CanvasLayer.new()
	marker_canvas.layer = 1
	add_child(marker_canvas)
	marker_canvas.add_child(hero_marker)
	ocean = preload("res://scripts/presentation/ocean.gd").new()
	add_child(ocean)
	selection_ring = MeshInstance3D.new()
	var outline_material = Doll.material(Color("f0d9a0"))
	outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	selection_ring.material_override = outline_material
	selection_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(selection_ring)
	rain = CPUParticles3D.new()
	rain.amount = 120
	rain.lifetime = 1.4
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(14, 0.2, 13)
	rain.direction = Vector3(0.12, -1.0, 0)
	rain.initial_velocity_min = 8.0
	rain.initial_velocity_max = 11.0
	rain.gravity = Vector3(0, -5, 0)
	var raindrop = BoxMesh.new()
	raindrop.size = Vector3(0.014, 0.42, 0.014)
	raindrop.material = Doll.material(Color("aac8c5"))
	rain.mesh = raindrop
	rain.emitting = false
	add_child(rain)
	visibility_changed.connect(func():
		hero_marker.visible = is_visible_in_tree())
	_update_camera()

func reset() -> void:
	_cancel_map_pointer()
	hero_marker.hide()
	map_follow_actor = null
	zoom_size = DEFAULT_MAP_ZOOM
	for root in [map_root, actor_root, landmark_root]:
		for child in root.get_children():
			child.free()
	tile_nodes.clear()
	landmarks.clear()
	revealing_cells.clear()
	map_batch = null
	canopy_batch = null
	board_mesh = null
	board_fog = null
	board_fringe = null
	fog_reveals = null
	board_stamp.clear()
	outline_cell = ""
	map_occluders.clear()
	chunk_occluders.clear()
	fading_occluders.clear()
	tile_signatures.clear()
	dolls.clear()

func refresh(run: RefCounted, _selected_id: String, selected_cell: String) -> void:
	current_tiles = run.data.tiles
	if tile_nodes.is_empty() and not current_tiles.is_empty():
		board_surface.prepare(current_tiles, int(run.data.seed))
		map_min = Hex.world(current_tiles.keys()[0])
		map_max = map_min
		for id in current_tiles:
			var point = Hex.world(id)
			map_min = map_min.min(point)
			map_max = map_max.max(point)
	if ocean.sea_cells.is_empty(): ocean.build(current_tiles)
	var visible_layout: Dictionary = {}
	var pending_sight: Array = run.relic_intro().get("new_sight", [])
	for id in run.data.explored:
		if id not in pending_sight:
			var tile: Dictionary = current_tiles[id]
			var node: Dictionary = run.node_at(id)
			var clearing: bool = tile.site == "start" or node.get("kind") in ["cache", "supply", "battle", "elite"]
			visible_layout[id] = [tile.terrain, tile.height, clearing]
	var relief_changed = visible_layout != board_stamp
	if relief_changed:
		if not is_instance_valid(board_mesh):
			board_mesh = Node3D.new()
			map_root.add_child(board_mesh)
			board_fog = Node3D.new()
			map_root.add_child(board_fog)
			board_fringe = Node3D.new()
			map_root.add_child(board_fringe)
			fog_reveals = Node3D.new()
			map_root.add_child(fog_reveals)
			board_ground_material = ShaderMaterial.new()
			board_ground_material.shader = Board.GROUND
			board_fog_material = ShaderMaterial.new()
			board_fog_material.shader = Board.FOG
			board_fringe_material = ShaderMaterial.new()
			board_fringe_material.shader = Board.FRINGE
			board_fringe_material.render_priority = 1
		var patches = board_surface.rebuild(visible_layout, board_stamp)
		for chunk in patches:
			_update_surface_chunk(board_mesh, chunk, patches[chunk][0], board_ground_material)
			_update_surface_chunk(board_fog, chunk, patches[chunk][1], board_fog_material)
			_update_surface_chunk(board_fringe, chunk, patches[chunk][2], board_fringe_material)
		if not board_stamp.is_empty():
			var reveal = board_surface.reveal_meshes(visible_layout, board_stamp)
			if reveal[0] != null:
				var new_cells := visible_layout.keys().filter(func(id): return not board_stamp.has(id))
				_animate_fog_reveal(reveal[0], reveal[1], new_cells)
		board_stamp = visible_layout
	var dirty_details = {}
	for id in visible_layout:
		var t: Dictionary = current_tiles[id]
		var landmark := _landmark_state(run, id, t)
		_refresh_landmark(id, landmark, relief_changed)
		var visited: bool = run.has_visited(id)
		var borders: Array = []
		for next in Hex.neighbors(id, current_tiles):
			borders.append(visible_layout.get(next, []))
		var name_on_map = run.location_name(id) if visited or (id == run.data.boss and run.boss_known()) else ""
		var has_landmark := not landmark.is_empty()
		var signature = JSON.stringify([visible_layout[id], borders, name_on_map, has_landmark])
		if tile_signatures.get(id, "") != signature:
			dirty_details[Board.chunk_for(id)] = true
			if tile_nodes.has(id):
				tile_nodes[id].free()
			var visual_seed = hash(str(run.data.seed) + id)
			var node = Node3D.new()
			map_root.add_child(node)
			node.position = Hex.world(id)
			Terrain.board_details(node, t, id, visual_seed, board_surface, has_landmark)
			if not name_on_map.is_empty():
				var height = board_surface.height_at(node.position)
				_label_location(node, name_on_map, height)
			tile_nodes[id] = node
			tile_signatures[id] = signature
	for id in landmarks.keys():
		if not visible_layout.has(id):
			_refresh_landmark(id, [])
	if not dirty_details.is_empty():
		_batch_map_geometry(dirty_details)
	var hero = run.actor("hero")
	if not dolls.has("hero"):
		var doll = Doll.new()
		actor_root.add_child(doll)
		doll.configure(hero)
		doll.map_height_source = board_surface
		dolls["hero"] = doll
	var model = dolls["hero"]
	model.selected = true
	model.set_down(hero.hp <= 0)
	model.scale = Vector3.ONE * 0.24
	var point = Hex.world(hero.position)
	point.y = board_surface.height_at(point) + 0.025
	if model.has_meta("cell") and model.get_meta("cell") != hero.position:
		model.move_to(point)
	elif not model.is_moving():
		model.position = point
	model.set_meta("cell", hero.position)
	if relief_changed or outline_cell != selected_cell:
		outline_cell = selected_cell
		selection_ring.mesh = board_surface.outline(selected_cell, visible_layout.has(selected_cell)) if current_tiles.has(selected_cell) else null
	light.light_color = Color("d0dce0") if run.data.weather == "rain" else Color("ffe5b2")
	light.light_energy = 0.48 if run.data.weather == "rain" else 0.68
	rain.emitting = run.data.weather == "rain"

func _chunk_name(chunk: Vector2i) -> String:
	return "Chunk_%d_%d" % [chunk.x, chunk.y]

func _landmark_state(run: RefCounted, id: String, tile: Dictionary) -> Array:
	if tile.terrain == "lake":
		return []
	if not tile.enemies.is_empty():
		if (tile.hidden or id == run.data.boss) and not run.knows_encounter(id):
			return []
		var elite: bool = run.node_at(id).get("kind") == "elite" or Nodes.is_elite(tile.enemies) or "war_god" in tile.enemies
		var leader: String = "war_god" if "war_god" in tile.enemies else tile.enemies[0]
		return ["enemy", leader, elite]
	if tile.site == "start":
		return ["village", tile.base_terrain, false]
	var node: Dictionary = run.node_at(id)
	if node.get("kind") in ["supply", "cache"]:
		return [node.kind, tile.base_terrain, not node.result.is_empty()]
	if tile.quantity > 0:
		return ["supply", tile.base_terrain, false]
	if run.relic_sites.has(id) and node.get("kind") not in ["battle", "elite"]:
		return ["cache", tile.base_terrain, run.data.relic_claims.has("site:" + id)]
	return []

func _refresh_landmark(id: String, state: Array, relief_changed: bool = false) -> void:
	var model: Node3D = landmarks.get(id)
	if model != null and model.get_meta("state") != state:
		model.free()
		landmarks.erase(id)
		model = null
	if state.is_empty():
		return
	if model != null and not relief_changed:
		return
	if model == null:
		model = Node3D.new()
		model.set_meta("state", state)
		landmark_root.add_child(model)
		if state[0] == "enemy":
			var enemy := Landmarks.enemy(state[1], state[2])
			model.add_child(enemy)
			var bounds := Landmarks.bounds(enemy)
			enemy.position.y = -bounds.position.y * enemy.scale.y + 0.02
			if state[2]:
				model.add_child(Landmarks.decoration("elite", "mountain", false))
		else:
			model.add_child(Landmarks.decoration(state[0], state[1], state[2]))
		model.set_meta("bounds", Landmarks.bounds(model))
		landmarks[id] = model
	var point := Hex.world(id) + Landmarks.offset(state[0])
	point.y = board_surface.height_at(point)
	if state[0] == "enemy" and model.has_node("EliteBanner"):
		var banner := model.get_node("EliteBanner") as MeshInstance3D
		banner.position.y = board_surface.height_at(point + Vector3(0.35, 0.0, -0.025)) - point.y
		model.set_meta("bounds", Landmarks.bounds(model))
	if state[0] != "enemy":
		var footprint: AABB = model.get_child(0).get_aabb()
		var top := point.y
		var bottom := point.y
		for x in [footprint.position.x * 0.8, footprint.end.x * 0.8]:
			for z in [footprint.position.z * 0.8, footprint.end.z * 0.8]:
				var height := board_surface.height_at(point + Vector3(x, 0.0, z))
				top = maxf(top, height)
				bottom = minf(bottom, height)
		point.y = top
		if top - bottom > 0.07 and current_tiles[id].base_terrain != "swamp":
			_seat_landmark(model, footprint, top - bottom, current_tiles[id].base_terrain)
		elif model.has_node("Foundation"):
			model.get_node("Foundation").free()
	model.position = point
	model.visible = not revealing_cells.has(id)

func _seat_landmark(model: Node3D, footprint: AABB, depth: float, terrain: String) -> void:
	var base := model.get_node_or_null("Foundation") as MeshInstance3D
	if base == null:
		base = MeshInstance3D.new()
		base.name = "Foundation"
		base.material_override = Doll.material(Landmarks.STONE[terrain].darkened(0.13))
		base.mesh = CylinderMesh.new()
		model.add_child(base)
	var mesh := base.mesh as CylinderMesh
	mesh.radial_segments = 8
	mesh.height = depth + 0.06
	mesh.top_radius = 0.47
	mesh.bottom_radius = 0.44
	base.position = Vector3(footprint.get_center().x, 0.005 - mesh.height / 2.0, footprint.get_center().z)
	base.scale = Vector3(footprint.size.x, 1.0, footprint.size.z)

func _animate_fog_reveal(mesh: ArrayMesh, old_edge_mesh: ArrayMesh, cells: Array) -> void:
	var material := ShaderMaterial.new()
	material.shader = Board.REVEAL
	material.set_shader_parameter("progress", 0.0)
	material.render_priority = FOG_REVEAL_PRIORITY
	var veil := MeshInstance3D.new()
	veil.mesh = mesh
	veil.material_override = material
	veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fog_reveals.add_child(veil)
	for id in cells:
		revealing_cells[id] = veil
	var old_edge_material: ShaderMaterial
	if old_edge_mesh != null:
		old_edge_material = board_fringe_material.duplicate()
		var old_edge := MeshInstance3D.new()
		old_edge.mesh = old_edge_mesh
		old_edge.material_override = old_edge_material
		old_edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		veil.add_child(old_edge)
	var dissolve = veil.create_tween()
	dissolve.tween_method(func(progress: float):
		material.set_shader_parameter("progress", progress)
		if old_edge_material != null:
			old_edge_material.set_shader_parameter("progress", progress), 0.0, 1.0, FOG_REVEAL_SECONDS)
	dissolve.tween_callback(func():
		for id in cells:
			if revealing_cells.get(id) == veil:
				revealing_cells.erase(id)
				if landmarks.has(id):
					landmarks[id].show())
	dissolve.tween_callback(veil.queue_free)

func _update_surface_chunk(parent: Node3D, chunk: Vector2i, mesh: ArrayMesh, material: ShaderMaterial) -> void:
	var name = _chunk_name(chunk)
	var instance = parent.get_node_or_null(name) as MeshInstance3D
	if mesh == null:
		if instance != null:
			instance.free()
		return
	if instance == null:
		instance = MeshInstance3D.new()
		instance.name = name
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.material_override = material
		parent.add_child(instance)
	instance.mesh = mesh

func _batch_map_geometry(dirty: Dictionary) -> void:
	if not is_instance_valid(map_batch):
		map_batch = Node3D.new()
		map_root.add_child(map_batch)
		canopy_batch = Node3D.new()
		map_batch.add_child(canopy_batch)
	for chunk in dirty:
		_batch_detail_chunk(chunk)
	map_occluders.clear()
	for instances in chunk_occluders.values():
		map_occluders.append_array(instances)
	for instance in fading_occluders.keys():
		if not is_instance_valid(instance):
			fading_occluders.erase(instance)
	_sync_canopy_lod(true)

func _new_detail_chunk(parent: Node3D, chunk: Vector2i) -> Node3D:
	var name = _chunk_name(chunk)
	var old = parent.get_node_or_null(name)
	if old != null:
		old.free()
	var replacement = Node3D.new()
	replacement.name = name
	parent.add_child(replacement)
	return replacement

func _batch_detail_chunk(chunk: Vector2i) -> void:
	var detail_root = _new_detail_chunk(map_batch, chunk)
	var canopy_root = _new_detail_chunk(canopy_batch, chunk)
	var groups = {}
	var repeated = {}
	var world_to_map = map_root.global_transform.affine_inverse()
	var occluders: Array[MeshInstance3D] = []
	for id in board_surface.chunks[chunk]:
		var tile = tile_nodes.get(id)
		if tile == null:
			continue
		for instance in tile.find_children("*","MeshInstance3D",true,false):
			if instance.skin!=null: continue
			var occluder = instance.has_meta("board_occluder")
			if occluder:
				occluders.append(instance)
			for surface in range(instance.mesh.get_surface_count()):
				var material = instance.get_active_material(surface)
				if fading_occluders.has(instance):
					var original = fading_occluders[instance].originals[surface]
					material = instance.material_override if instance.material_override else original
					if material == null:
						material = instance.mesh.surface_get_material(surface)
				if instance.mesh.get_surface_count() == 1 and material is ShaderMaterial and material.shader == NATURE_PALETTE:
					var key = [instance.mesh.get_instance_id(), material.get_instance_id(), occluder]
					if not repeated.has(key):
						repeated[key] = {"mesh": instance.mesh, "material": material, "occluder": occluder, "poses": []}
					repeated[key].poses.append(world_to_map * instance.global_transform)
					continue
				var key = str(material.get_instance_id())
				if material is StandardMaterial3D:
					key = "%s:%s:%s:%s:%s" % [material.albedo_color.to_html(),material.shading_mode,material.metallic,material.roughness,material.albedo_texture.resource_path if material.albedo_texture else ""]
				if occluder:
					key += ":occluder"
				if not groups.has(key):
					var tool = SurfaceTool.new()
					tool.begin(Mesh.PRIMITIVE_TRIANGLES)
					groups[key] = {"tool":tool,"material":material,"occluder":occluder}
				groups[key].tool.append_from(instance.mesh,surface,world_to_map * instance.global_transform)
			instance.visible = false
	for group in groups.values():
		var instance = MeshInstance3D.new()
		instance.mesh = group.tool.commit()
		instance.material_override = group.material
		var parent = canopy_root if group.occluder else detail_root
		parent.add_child(instance)
	for group in repeated.values():
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = group.mesh
		batch.instance_count = group.poses.size()
		for i in batch.instance_count:
			batch.set_instance_transform(i, group.poses[i])
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = batch
		instance.material_override = group.material
		var parent = canopy_root if group.occluder else detail_root
		parent.add_child(instance)
	chunk_occluders[chunk] = occluders

func _sync_canopy_lod(force: bool = false) -> void:
	if not is_instance_valid(canopy_batch):
		return
	var close_view = zoom_size <= OCCLUSION_ZOOM
	if not force and close_view == canopy_individual:
		return
	canopy_individual = close_view
	canopy_batch.visible = not close_view
	for instance in map_occluders:
		instance.visible = close_view

func focus_cell(id: String) -> void:
	_cancel_map_pointer()
	map_follow_actor = null
	focus_point = Hex.world(id)
	_update_camera()

func follow_map_movement(id: String) -> void:
	var actor = dolls.get(id)
	if actor == null or actor == map_follow_actor:
		return
	map_follow_actor = actor
	map_follow_offset = focus_point - _map_actor_ground(actor)

func is_map_moving() -> bool:
	var hero = dolls.get("hero")
	return is_instance_valid(hero) and hero.is_moving()

func _map_actor_ground(actor: Node3D) -> Vector3:
	return Vector3(actor.position.x, 0.0, actor.position.z)

func _update_map_follow() -> void:
	if not is_instance_valid(map_follow_actor):
		return
	var next = (_map_actor_ground(map_follow_actor) + map_follow_offset).clamp(map_min, map_max)
	if not focus_point.is_equal_approx(next):
		focus_point = next
		_update_camera()
	if not map_follow_actor.is_moving():
		map_follow_actor = null

func _pan_map(offset: Vector3) -> void:
	focus_point = (focus_point + offset).clamp(map_min, map_max)
	_update_camera()

func _update_camera() -> void:
	if camera == null:
		return
	camera.position = focus_point + Vector3(0, 18, 17)
	camera.look_at(focus_point)
	camera.size = zoom_size
	camera.h_offset = 0.3
	_sync_canopy_lod()

func set_world_input_enabled(enabled: bool) -> void:
	set_process_unhandled_input(enabled)
	if not enabled:
		_cancel_map_pointer()

func _cancel_map_pointer() -> void:
	map_pointer_down = false
	map_dragging = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_cancel_map_pointer()

func _map_point(screen_position: Vector2) -> Variant:
	return MAP_PLANE.intersects_ray(camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))

func _zoom_map(screen_position: Vector2, factor: float) -> void:
	var next_zoom = clampf(zoom_size * factor, MIN_MAP_ZOOM, MAX_MAP_ZOOM)
	if is_equal_approx(zoom_size, next_zoom):
		return
	var before = _map_point(screen_position)
	zoom_size = next_zoom
	_update_camera()
	var after = _map_point(screen_position)
	if before != null and after != null:
		_pan_map(before - after)
		if is_instance_valid(map_follow_actor):
			map_follow_offset = focus_point - _map_actor_ground(map_follow_actor)

func _drag_map_to(screen_position: Vector2) -> void:
	if not map_dragging and map_pointer_position.distance_to(screen_position) < DRAG_THRESHOLD:
		return
	map_dragging = true
	map_follow_actor = null
	var from = _map_point(map_pointer_position)
	var to = _map_point(screen_position)
	if from != null and to != null:
		_pan_map(from - to)
	map_pointer_position = screen_position

func _input(event: InputEvent) -> void:
	# Capture a gesture started on the board, even when it ends over the HUD.
	if not map_pointer_down:
		return
	if event is InputEventMouseMotion:
		_drag_map_to(event.position)
		if map_dragging:
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_drag_map_to(event.position)
		var click = not map_dragging
		_cancel_map_pointer()
		if is_instance_valid(map_follow_actor):
			map_follow_offset = focus_point - _map_actor_ground(map_follow_actor)
		get_viewport().set_input_as_handled()
		if click:
			var origin := camera.project_ray_origin(map_pointer_position)
			var direction := camera.project_ray_normal(map_pointer_position)
			var ground := board_surface.pick_hit(origin, direction)
			var id := _pick_landmark(origin, direction, ground[1])
			if id.is_empty():
				id = ground[0]
			if id != "":
				cell_clicked.emit(id)

func _pick_landmark(origin: Vector3, direction: Vector3, nearest: float) -> String:
	var cell := ""
	for id in landmarks:
		var model: Node3D = landmarks[id]
		if not model.is_visible_in_tree():
			continue
		var bounds: AABB = model.get_meta("bounds")
		var hit = (model.global_transform * bounds).intersects_ray(origin, direction)
		if hit == null:
			continue
		var distance := origin.distance_squared_to(hit)
		if distance < nearest:
			nearest = distance
			cell = id
	return cell

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			map_pointer_down = true
			map_pointer_position = event.position
		MOUSE_BUTTON_WHEEL_UP:
			_zoom_map(event.position, 1.0 / MAP_ZOOM_STEP)
		MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_map(event.position, MAP_ZOOM_STEP)
		_:
			return
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	rain.position = focus_point + Vector3(0, 10, 0)
	if is_processing_unhandled_input() and not map_pointer_down:
		var motion = Vector3.ZERO
		if Input.is_physical_key_pressed(KEY_A):
			motion.x -= 1
		if Input.is_physical_key_pressed(KEY_D):
			motion.x += 1
		if Input.is_physical_key_pressed(KEY_W):
			motion.z -= 1
		if Input.is_physical_key_pressed(KEY_S):
			motion.z += 1
		if motion != Vector3.ZERO:
			map_follow_actor = null
			_pan_map(motion * delta * 8.0)
	if not map_pointer_down:
		_update_map_follow()
	_update_occlusion(delta)
	hero_marker.update_position(camera, dolls.get("hero"), is_visible_in_tree())

func _update_occlusion(delta: float) -> void:
	var blocked: Dictionary = {}
	var sight = -camera.global_basis.z
	var mountain_targets := PackedVector3Array()
	var tree_targets := PackedVector3Array()
	var model = dolls.get("hero")
	if zoom_size <= OCCLUSION_ZOOM and is_instance_valid(model) and model.visible:
		var feet: Vector3 = model.global_position
		mountain_targets.append(feet)
		tree_targets.append(feet + Vector3.UP * 0.20)
		var landmark_range := zoom_size * 0.8
		for landmark in landmarks.values():
			if not landmark.visible or landmark.position.distance_squared_to(focus_point) > landmark_range * landmark_range:
				continue
			var bounds: AABB = landmark.get_meta("bounds")
			var center: Vector3 = landmark.global_position + bounds.get_center()
			tree_targets.append(center)
			if mountain_targets.size() < 32 and board_surface.profiles.get(Hex.cell_at(center), [""])[0] == "mountain":
				mountain_targets.append(Vector3(center.x, landmark.position.y + maxf(0.0, bounds.size.y * 0.35 - 0.18), center.z))
		var canopy_range := zoom_size + 2.0
		for instance in map_occluders:
			if instance.global_position.distance_squared_to(focus_point) > canopy_range * canopy_range:
				continue
			var bounds: AABB = (instance.global_transform * instance.get_aabb()).grow(0.025)
			var targets := PackedVector3Array()
			for target in tree_targets:
				var upper := target + Vector3.UP * 0.18
				if bounds.intersects_segment(target - sight * 3.0, target) != null \
						or bounds.intersects_segment(upper - sight * 3.0, upper) != null:
					targets.append(target)
					if targets.size() == 7:
						break
			if not targets.is_empty():
				blocked[instance] = targets
	if board_ground_material != null:
		var fade = 1.0 - smoothstep(7.75, OCCLUSION_ZOOM, zoom_size)
		var ground_shader = GROUND_FADE if fade > 0.0 and not mountain_targets.is_empty() else Board.GROUND
		if board_ground_material.shader != ground_shader:
			board_ground_material.shader = ground_shader
		if ground_shader == GROUND_FADE:
			board_ground_material.set_shader_parameter("mountain_target_count", mountain_targets.size())
			board_ground_material.set_shader_parameter("mountain_fade", fade)
			board_ground_material.set_shader_parameter("mountain_targets", mountain_targets)
			board_ground_material.set_shader_parameter("mountain_sight", sight)
	for instance in blocked:
		if not fading_occluders.has(instance):
			_begin_occlusion(instance)
	for instance in fading_occluders.keys():
		var effect: Dictionary = fading_occluders[instance]
		var obscures = blocked.has(instance)
		effect.amount = move_toward(effect.amount, 1.0 if obscures else 0.0, delta * 8.0)
		if obscures:
			effect.targets = blocked[instance]
		for material in effect.materials:
			material.set_shader_parameter("fade", effect.amount)
			material.set_shader_parameter("targets", effect.targets)
			material.set_shader_parameter("target_count", effect.targets.size())
			material.set_shader_parameter("sight", sight)
		if effect.amount == 0.0 and not obscures:
			_restore_occluder(instance, effect)
			fading_occluders.erase(instance)

func _restore_occluder(instance: MeshInstance3D, effect: Dictionary) -> void:
	for surface in range(effect.originals.size()):
		instance.set_surface_override_material(surface, effect.originals[surface])

func _begin_occlusion(instance: MeshInstance3D) -> void:
	var effect = {"originals": [], "materials": [], "amount": 0.0, "targets": PackedVector3Array()}
	for surface in range(instance.mesh.get_surface_count()):
		effect.originals.append(instance.get_surface_override_material(surface))
		var original = instance.get_active_material(surface)
		var material = ShaderMaterial.new()
		material.shader = OCCLUSION
		if original is ShaderMaterial:
			material.set_shader_parameter("textured", true)
			material.set_shader_parameter("atlas", original.get_shader_parameter("atlas"))
		elif original is StandardMaterial3D:
			material.set_shader_parameter("tint", original.albedo_color)
		effect.materials.append(material)
		instance.set_surface_override_material(surface, material)
	fading_occluders[instance] = effect

static func _label_location(parent: Node3D, text: String, height: float) -> void:
	var label = Label3D.new()
	label.name = "LocationName"
	label.text = text
	var font = FontVariation.new()
	font.base_font = FontAsset
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600.0}
	label.font = font
	label.font_size = 40
	label.pixel_size = minf(0.0032, 1.2 / font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	# Transparent terrain and fog can cover labels drawn earlier, even without depth testing.
	label.outline_render_priority = FOG_REVEAL_PRIORITY + 1
	label.render_priority = FOG_REVEAL_PRIORITY + 2
	label.modulate = Color("eee0b8")
	label.outline_size = 7
	label.position.y = height + 0.04
	parent.add_child(label)
