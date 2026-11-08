class_name ExpeditionView
extends Node3D
const Hex = preload("res://scripts/domain/hex_map.gd")
const Terrain = preload("res://scripts/presentation/terrain.gd")
const Doll = preload("res://scripts/presentation/doll.gd")
const FontAsset = preload("res://assets/fonts/NotoSansSC.ttf")
const Catalog = preload("res://scripts/domain/catalog.gd")
const Board = preload("res://scripts/presentation/board_surface.gd")
const BattleTargeting = preload("res://scripts/presentation/battle_targeting.gd")
const OCCLUSION = preload("res://scripts/presentation/board_occlusion.gdshader")
const NATURE_PALETTE = preload("res://scripts/presentation/nature_palette.gdshader")
const MAP_PLANE = Plane(Vector3.UP, 0.05)
const DRAG_THRESHOLD = 8.0
const DEFAULT_MAP_ZOOM = 5.5
const MIN_MAP_ZOOM = 3.8
const MAX_MAP_ZOOM = 38.0
const MAP_ZOOM_STEP = 1.14
const OCCLUSION_ZOOM = 9.0
const FOG_REVEAL_SECONDS = 0.7
signal cell_clicked(id: String)
signal enemy_clicked(id: String)
signal squad_clicked(id: String)
var squad_markers = preload("res://scripts/presentation/squad_markers.gd").new()
var camera: Camera3D
var light: DirectionalLight3D
var map_root: Node3D
var actor_root: Node3D
var battle_root: Node3D
var tile_nodes: Dictionary = {}
var dolls: Dictionary = {}
var battle_dolls: Dictionary = {}
var tile_signatures: Dictionary = {}
var current_tiles: Dictionary = {}
var focus_point = Vector3.ZERO
var map_follow_actor: Node3D
var map_follow_offset = Vector3.ZERO
var map_min = Vector3.ZERO
var map_max = Vector3.ZERO
var zoom_size = DEFAULT_MAP_ZOOM
var map_pointer_down = false
var map_dragging = false
var map_pointer_position = Vector2.ZERO
var battle_mode = false
var battle_targeting = BattleTargeting.new()
var selection_ring: MeshInstance3D
var clock = 0.0
var rain: CPUParticles3D
var effects: Node3D
var presenter: Node
var battle_stage: Node3D
var battle_run: RefCounted
var battle_combat: RefCounted
var display_results: Dictionary = {}
var ocean: Node3D
var environment: Environment
var camera_impulse = 0.0
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
var map_actor = ""
var map_squad: Array = []
signal presentation_changed
signal sound_cue(kind: String)

func _ready() -> void:
	environment = Environment.new()
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
	battle_root = Node3D.new()
	add_child(map_root)
	add_child(actor_root)
	add_child(battle_root)
	add_child(battle_targeting)
	var marker_canvas = CanvasLayer.new()
	marker_canvas.layer = 1
	add_child(marker_canvas)
	marker_canvas.add_child(squad_markers)
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
	effects = preload("res://scripts/presentation/skill_effects.gd").new()
	add_child(effects)
	presenter = preload("res://scripts/presentation/battle_presenter.gd").new()
	add_child(presenter)
	presenter.view = self
	presenter.finished.connect(func(): presentation_changed.emit())
	presenter.feedback_changed.connect(func(): presentation_changed.emit())
	presenter.started.connect(func(): presentation_changed.emit())
	visibility_changed.connect(func():
		squad_markers.visible = is_visible_in_tree() and not battle_mode)
	_update_camera()

func reset() -> void:
	_cancel_map_pointer()
	squad_markers.groups.clear()
	squad_markers.markers.clear()
	squad_markers.queue_redraw()
	_clear_battle_target()
	map_follow_actor = null
	zoom_size = DEFAULT_MAP_ZOOM
	presenter.cancel()
	effects.clear()
	display_results.clear()
	battle_stage = null
	battle_run = null
	battle_combat = null
	for root in [map_root, actor_root, battle_root]:
		for child in root.get_children():
			child.free()
	tile_nodes.clear()
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
	map_squad.clear()
	tile_signatures.clear()
	dolls.clear()
	battle_dolls.clear()
	battle_mode = false
	battle_root.visible = false
	map_root.visible = true
	actor_root.visible = true
	selection_ring.visible = true
	ocean.visible = true
	camera_impulse = 0.0

func refresh(run: RefCounted, selected_id: String, selected_cell: String) -> void:
	current_tiles = run.data.tiles
	squad_markers.refresh(run, selected_id)
	if selected_id != map_actor:
		map_follow_actor = null
	map_actor = selected_id
	map_squad = run.squad_members(selected_id)
	if tile_nodes.is_empty() and not current_tiles.is_empty():
		board_surface.prepare(current_tiles, int(run.data.seed))
		map_min = Hex.world(current_tiles.keys()[0])
		map_max = map_min
		for id in current_tiles:
			var point = Hex.world(id)
			map_min = map_min.min(point)
			map_max = map_max.max(point)
	if ocean.sea_cells.is_empty(): ocean.build(current_tiles)
	ocean.visible = not battle_mode
	if not battle_mode: environment.background_color = Color("23577b")
	map_root.visible = not battle_mode
	actor_root.visible = not battle_mode
	selection_ring.visible = not battle_mode
	var visible_layout: Dictionary = {}
	var pending_sight: Array = run.relic_intro().get("new_sight", [])
	for id in run.data.explored:
		if id not in pending_sight:
			visible_layout[id] = [current_tiles[id].terrain, current_tiles[id].height]
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
		if not board_stamp.is_empty() and not battle_mode:
			var reveal = board_surface.reveal_meshes(visible_layout, board_stamp)
			if reveal[0] != null:
				_animate_fog_reveal(reveal[0], reveal[1])
		board_stamp = visible_layout
	var dirty_details = {}
	for id in visible_layout:
		var t: Dictionary = current_tiles[id]
		var visited: bool = run.has_visited(id)
		var borders: Array = []
		for next in Hex.neighbors(id, current_tiles):
			borders.append(visible_layout.get(next, []))
		var site: String = t.site if visited else ""
		var signature = JSON.stringify([visible_layout[id], borders, t.wet_until > run.data.day, site, t.burning])
		if tile_signatures.get(id, "") != signature:
			dirty_details[Board.chunk_for(id)] = true
			if tile_nodes.has(id):
				tile_nodes[id].free()
			var visual_seed = hash(str(run.data.seed) + id)
			var node = Node3D.new()
			map_root.add_child(node)
			node.position = Hex.world(id)
			var detail = t.duplicate()
			detail.current_day = run.data.day
			Terrain.board_details(node, detail, id, visual_seed, board_surface)
			if not site.is_empty():
				var height = board_surface.height_at(node.position)
				_label(node, _site_name(site), Vector3(0, height + 1.03, 0), Color("eee0b8"), 0.0041)
			tile_nodes[id] = node
			tile_signatures[id] = signature
	if not dirty_details.is_empty():
		_batch_map_geometry(dirty_details)
	var counts = {}
	var visible_counts = {}
	var visible_actor_ids: Array = []
	var actor_ids = run.data.actors.keys()
	actor_ids.sort_custom(func(a,b):
		if a==b: return false
		if a=="hero": return true
		if b=="hero": return false
		return str(a)<str(b))
	for id in actor_ids:
		var a = run.actor(id)
		var show_npc = run.has_visited(a.position) and current_tiles[a.position].npc == id
		if not a.joined and not show_npc:
			if dolls.has(id):
				dolls[id].visible = false
			continue
		visible_actor_ids.append(id)
		visible_counts[a.position] = int(visible_counts.get(a.position, 0)) + 1
	for id in visible_actor_ids:
		var a = run.actor(id)
		if not dolls.has(id):
			var doll = Doll.new()
			actor_root.add_child(doll)
			doll.configure(a)
			doll.map_height_source = board_surface
			dolls[id] = doll
		var model = dolls[id]
		model.visible = true
		model.selected = id == selected_id
		model.set_down(a.hp <= 0)
		var count = int(counts.get(a.position, 0))
		counts[a.position] = count + 1
		var total = int(visible_counts[a.position])
		model.scale = Vector3.ONE * (0.19 if total > 4 else 0.22 if total > 1 else 0.24)
		var offset = Vector3.ZERO
		if total>1:
			var ring_count = total-1 if total==7 else total
			var index = count-1 if total==7 else count
			if index>=0:
				var angle = TAU*float(index)/ring_count
				offset += Vector3(cos(angle),0,sin(angle))*(0.52 if total>3 else 0.34)
		var point = Hex.world(a.position) + offset
		point.y = board_surface.height_at(point) + 0.025
		if model.has_meta("cell") and model.get_meta("cell") != a.position:
			model.move_to(point)
		elif not model.is_moving():
			model.position = point
		model.set_meta("cell", a.position)
	if relief_changed or outline_cell != selected_cell:
		outline_cell = selected_cell
		selection_ring.mesh = board_surface.outline(selected_cell, visible_layout.has(selected_cell)) if current_tiles.has(selected_cell) else null
	light.light_color = Color("d0dce0") if run.data.weather == "rain" else Color("ffe5b2")
	light.light_energy = 0.48 if run.data.weather == "rain" else 0.68
	rain.emitting = run.data.weather == "rain"

func _chunk_name(chunk: Vector2i) -> String:
	return "Chunk_%d_%d" % [chunk.x, chunk.y]

func _animate_fog_reveal(mesh: ArrayMesh, old_edge_mesh: ArrayMesh) -> void:
	var material := ShaderMaterial.new()
	material.shader = Board.REVEAL
	material.set_shader_parameter("progress", 0.0)
	material.render_priority = 2
	var veil := MeshInstance3D.new()
	veil.mesh = mesh
	veil.material_override = material
	veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fog_reveals.add_child(veil)
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
	if battle_mode:
		camera.position = Vector3(7.5, 9, 12)
		camera.look_at(Vector3(0, 0.5, 0))
		camera.size = 13.0
		camera.h_offset = 1.4
	else:
		camera.position = focus_point + Vector3(0, 18, 17)
		camera.look_at(focus_point)
		camera.size = zoom_size
		camera.h_offset = 0.3
		_sync_canopy_lod()

func set_world_input_enabled(enabled: bool) -> void:
	set_process_unhandled_input(enabled)
	if not enabled:
		_cancel_map_pointer()
		battle_targeting.hovered_id = ""
		_update_battle_targets()

func _cancel_map_pointer() -> void:
	map_pointer_down = false
	map_dragging = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_cancel_map_pointer()
		battle_targeting.hovered_id = ""

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
	if battle_mode and event is InputEventMouseMotion:
		# HUD controls consume motion before the world can offer a preview again.
		battle_targeting.hovered_id = ""
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
			var squad = squad_markers.pick(map_pointer_position)
			if not squad.is_empty():
				squad_clicked.emit(squad)
				return
			var id = board_surface.pick(camera.project_ray_origin(map_pointer_position), camera.project_ray_normal(map_pointer_position))
			if id != "":
				cell_clicked.emit(id)

func _unhandled_input(event: InputEvent) -> void:
	if battle_mode:
		if battle_combat != null and battle_combat.outcome.is_empty():
			if event is InputEventMouseMotion:
				battle_targeting.hovered_id = _battle_enemy_at(event.position)
			elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				var enemy = _battle_enemy_at(event.position)
				if not enemy.is_empty():
					get_viewport().set_input_as_handled()
					enemy_clicked.emit(enemy)
		return
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
	clock += delta
	if camera_impulse>0.0:
		camera_impulse = maxf(0.0,camera_impulse-delta*0.7)
		camera.v_offset = sin(clock*72.0)*camera_impulse
	else: camera.v_offset = 0.0
	if rain:
		rain.position = (Vector3.ZERO if battle_mode else focus_point) + Vector3(0, 10, 0)
	for flame in get_tree().get_nodes_in_group("world_flames"):
		flame.scale.y = 0.9 + sin(clock * 5.0 + flame.get_instance_id() % 11) * 0.16
	if not battle_mode and is_processing_unhandled_input() and not map_pointer_down:
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
		else:
			_update_map_follow()
	if battle_mode:
		_update_battle_targets()
	else:
		_update_occlusion(delta)
	squad_markers.update_positions(camera, dolls, is_visible_in_tree() and not battle_mode)

func _battle_enemy_at(screen_position: Vector2) -> String:
	return battle_targeting.pick(camera, screen_position, battle_dolls, battle_combat.alive_enemies())

func set_battle_target(id: String) -> void:
	battle_targeting.select(id)
	_update_battle_targets()

func _update_battle_targets() -> void:
	var alive: Array[String] = []
	if battle_mode and battle_combat != null and battle_combat.outcome.is_empty():
		alive = battle_combat.alive_enemies()
	battle_targeting.update_markers(camera, battle_dolls, alive)

func _clear_battle_target() -> void:
	battle_targeting.hovered_id = ""
	battle_targeting.select("")
	var empty: Array[String] = []
	battle_targeting.update_markers(camera, battle_dolls, empty)

func _update_occlusion(delta: float) -> void:
	var blocked: Dictionary = {}
	var sight = -camera.global_basis.z
	if zoom_size <= OCCLUSION_ZOOM:
		for id in map_squad:
			var model = dolls.get(id)
			if not is_instance_valid(model) or not model.visible:
				continue
			var feet: Vector3 = model.global_position
			var target = feet + Vector3.UP * 0.20
			var head = feet + Vector3.UP * 0.38
			for instance in map_occluders:
				if instance.global_position.distance_squared_to(feet) > 9.0:
					continue
				var bounds: AABB = (instance.global_transform * instance.get_aabb()).grow(0.025)
				if bounds.intersects_segment(target - sight * 3.0, target) != null or bounds.intersects_segment(head - sight * 3.0, head) != null:
					var targets: PackedVector3Array = blocked.get(instance, PackedVector3Array())
					targets.append(target)
					blocked[instance] = targets
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

func begin_battle(run: RefCounted, combat: RefCounted) -> void:
	_cancel_map_pointer()
	_clear_battle_target()
	if is_instance_valid(map_follow_actor):
		focus_point = Hex.world(combat.position)
	map_follow_actor = null
	presenter.cancel()
	effects.clear()
	display_results.clear()
	battle_run = run
	battle_combat = combat
	battle_mode = true
	ocean.visible = false
	map_root.visible = false
	actor_root.visible = false
	selection_ring.visible = false
	for child in battle_root.get_children():
		child.free()
	battle_stage = null
	battle_dolls.clear()
	battle_root.visible = true
	_draw_battle_stage(run.data.tiles[combat.position],run.data.day,combat.position)
	_update_camera()
	refresh_battle(run, combat)

func _draw_battle_stage(definition: Dictionary, day: int, position: String) -> void:
	environment.background_color = {"plains":Color("526757"),"forest":Color("354b42"),"mountain":Color("657078"),"ruins":Color("64695b"),"desert":Color("9b8965"),"swamp":Color("405c60"),"scorched":Color("4f5652")}.get(str(definition.terrain),Color("526757"))
	if is_instance_valid(battle_stage): battle_stage.free()
	battle_stage = Node3D.new()
	battle_root.add_child(battle_stage)
	var tile = definition.duplicate(true)
	tile.current_day = day
	tile.height = 0.0
	tile.enemies = []
	tile.npc = ""
	tile.quantity = 0
	tile.ground_only = true
	var stage = Terrain.tile(battle_stage, tile, hash(position))
	stage.scale = Vector3(6.5, 1.0, 4.5)
	tile.ground_only = false
	# Backdrop is assembled from the actual biome; props never reveal neighboring cells.
	for i in range(5):
		var backdrop = Terrain.tile(battle_stage, tile, i + 31)
		backdrop.position = Vector3(-5 + i * 2.4, -0.2, -4.0)
		backdrop.scale = Vector3(1.4, 1.7, 1.4)
	if tile.burning:
		var fire_ring = Node3D.new()
		battle_stage.add_child(fire_ring)
		fire_ring.position = Vector3(0, 0.05, 2.8)
		Terrain.fire(fire_ring)
	battle_root.set_meta("environment_signature", _battle_signature(tile))

func refresh_battle(run: RefCounted, combat: RefCounted) -> void:
	var tile = run.data.tiles[combat.position].duplicate(true)
	tile.current_day = run.data.day
	if not is_animating() and battle_root.get_meta("environment_signature", "") != _battle_signature(tile):
		_draw_battle_stage(tile,run.data.day,combat.position)
	var ids = combat.active.duplicate()
	ids.append_array(combat.enemies.keys())
	if is_animating():
		for id in presenter.visible_ids:
			if battle_dolls.has(id) and id not in ids: ids.append(id)
	for id in battle_dolls:
		battle_dolls[id].visible = id in ids
	for index in range(ids.size()):
		var id = str(ids[index])
		var enemy = combat.enemies.has(id)
		var a = combat.unit(id)
		if not battle_dolls.has(id):
			var doll = Doll.new()
			battle_root.add_child(doll)
			doll.configure(a)
			doll.rotation.y = -PI / 2 if enemy else PI / 2
			doll.scale = Vector3.ONE * (1.15 if a.get("type", "") == "lamp_boss" else 0.9)
			battle_dolls[id] = doll
		var slot = combat.enemies.keys().find(id) if enemy else combat.active.find(id)
		var model = battle_dolls[id]
		if slot>=0: model.position = Vector3(2.1 if enemy else -2.5, 0.1, -1.6 + slot * 1.25)
		model.visible = true
		if not is_animating(): model.set_down(a.hp <= 0)
		if not is_animating() and a.get("charged",false) and model.rigged.role=="crossbow": model.play_action("aim")
		model.selected = id == presentation_actor(combat.current)

func animate_events(events: Array) -> void:
	if not is_animating():
		var initialized = {}
		for event in events:
			for result in event.get("results",[]):
				if not initialized.has(result.target):
					display_results[result.target] = {"hp_after":result.hp_before,"shield_after":result.shield_before}
					initialized[result.target] = true
	presenter.enqueue(events)

func is_animating() -> bool:
	return presenter!=null and presenter.playing

func display_hp(id: String, current: int) -> int:
	return int(display_results.get(id,{}).get("hp_after",current)) if is_animating() else current

func display_shield(id: String, current: int) -> int:
	return int(display_results.get(id,{}).get("shield_after",current)) if is_animating() else current

func presentation_actor(fallback: String) -> String:
	return str(presenter.active_event.get("actor",fallback)) if is_animating() else fallback

func presentation_title(fallback: String) -> String:
	if not is_animating(): return fallback
	var event = presenter.active_event
	if event.get("kind","")=="environment": return "火场伤害 · 结算中"
	var id = str(event.get("actor",""))
	if battle_combat==null or id=="": return "演出中"
	var skill = str(event.get("skill_id",""))
	var title = str(Catalog.SKILLS[skill].name) if Catalog.SKILLS.has(skill) else "防守" if event.get("kind","")=="guard" else "使用道具" if event.get("kind","")=="heal" else "行动"
	return str(battle_combat.unit(id).name)+" · "+title

func sync_battle_states() -> void:
	if not battle_mode or battle_combat==null: return
	refresh_battle(battle_run,battle_combat)
	for id in battle_dolls:
		battle_dolls[id].set_down(battle_combat.unit(id).hp<=0)
	var tile = battle_run.data.tiles[battle_combat.position].duplicate(true)
	tile.current_day = battle_run.data.day
	if battle_root.get_meta("environment_signature", "") != _battle_signature(tile):
		_draw_battle_stage(tile,battle_run.data.day,battle_combat.position)

func sync_event_environment(event: Dictionary) -> void:
	if not event.has("environment_after") or battle_run==null: return
	var tile = battle_run.data.tiles[battle_combat.position].duplicate(true)
	tile.merge(event.environment_after,true)
	tile.current_day = battle_run.data.day
	if battle_root.get_meta("environment_signature", "") != _battle_signature(tile):
		_draw_battle_stage(tile,battle_run.data.day,battle_combat.position)

func end_battle() -> void:
	presenter.cancel()
	_clear_battle_target()
	effects.clear()
	battle_run = null
	battle_combat = null
	battle_mode = false
	battle_root.visible = false
	map_root.visible = true
	actor_root.visible = true
	selection_ring.visible = true
	ocean.visible = true
	environment.background_color = Color("23577b")
	camera_impulse = 0.0
	camera.v_offset = 0.0
	_update_camera()

func impact_camera(strength: float) -> void:
	camera_impulse = maxf(camera_impulse,strength)

func _battle_signature(tile: Dictionary) -> String:
	return "%s:%s:%s" % [tile.terrain, tile.burning, int(tile.wet_until) > int(tile.current_day)]

static func _site_name(site: String) -> String:
	return {"start": "断桥废棚", "exit": "归航站", "inn": "白栎旧驿站", "home": "林边人家", "record": "旧调度柜", "sign": "山路旧牌", "forest": "林缘捕网", "herb": "药箱树荫", "track": "旧兽径营地", "clear": "清障营地", "water": "水文台"}.get(site, "路途")

static func _label(parent: Node3D, text: String, point: Vector3, color: Color, pixel_size: float = 0.006) -> void:
	var label = Label3D.new()
	label.text = text
	var font = FontVariation.new()
	font.base_font = FontAsset
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600.0}
	label.font = font
	label.font_size = 40
	label.pixel_size = pixel_size
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	label.outline_size = 7
	label.position = point
	parent.add_child(label)
