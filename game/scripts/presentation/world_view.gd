class_name ExpeditionView
extends Node3D
const Hex = preload("res://scripts/domain/hex_map.gd")
const Terrain = preload("res://scripts/presentation/terrain.gd")
const Doll = preload("res://scripts/presentation/doll.gd")
const FontAsset = preload("res://assets/fonts/NotoSansSC.ttf")
const Catalog = preload("res://scripts/domain/catalog.gd")
const Board = preload("res://scripts/presentation/board_surface.gd")
const OCCLUSION = preload("res://scripts/presentation/board_occlusion.gdshader")
const MAP_PLANE = Plane(Vector3.UP, 0.05)
const DRAG_THRESHOLD = 8.0
const DEFAULT_MAP_ZOOM = 5.5
const MIN_MAP_ZOOM = 3.8
const MAX_MAP_ZOOM = 38.0
const MAP_ZOOM_STEP = 1.14
const OCCLUSION_ZOOM = 9.0
signal cell_clicked(id: String)
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
var map_min = Vector3.ZERO
var map_max = Vector3.ZERO
var zoom_size = DEFAULT_MAP_ZOOM
var map_pointer_down = false
var map_dragging = false
var map_pointer_position = Vector2.ZERO
var battle_mode = false
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
var board_surface = Board.new()
var board_mesh: MeshInstance3D
var board_fog: MeshInstance3D
var board_stamp: Dictionary
var outline_cell = ""
var map_occluders: Array[MeshInstance3D] = []
var fading_occluders: Dictionary
var map_actor = ""
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
	_update_camera()

func reset() -> void:
	_cancel_map_pointer()
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
	board_stamp.clear()
	outline_cell = ""
	map_occluders.clear()
	fading_occluders.clear()
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
	map_actor = selected_id
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
	for id in run.data.explored:
		visible_layout[id] = [current_tiles[id].terrain, current_tiles[id].height]
	var relief_changed = visible_layout != board_stamp
	if relief_changed:
		board_stamp = visible_layout
		if not is_instance_valid(board_mesh):
			board_mesh = MeshInstance3D.new()
			var ground = ShaderMaterial.new()
			ground.shader = Board.GROUND
			board_mesh.material_override = ground
			board_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			map_root.add_child(board_mesh)
			board_fog = MeshInstance3D.new()
			var clouds = ShaderMaterial.new()
			clouds.shader = Board.FOG
			board_fog.material_override = clouds
			board_fog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			map_root.add_child(board_fog)
		board_mesh.mesh = board_surface.rebuild(run.data.explored)
		board_fog.mesh = board_surface.fog_mesh
	var terrain_changed = false
	for id in run.data.explored:
		var t: Dictionary = current_tiles[id]
		var visited: bool = run.has_visited(id)
		var borders: Array = []
		for next in Hex.neighbors(id, current_tiles):
			borders.append(visible_layout.get(next, []))
		var signature = JSON.stringify([t, borders, t.wet_until > run.data.day, visited])
		if tile_signatures.get(id, "") != signature:
			terrain_changed = true
			if tile_nodes.has(id):
				tile_nodes[id].free()
			var visual_seed = hash(str(run.data.seed) + id)
			var node = Node3D.new()
			map_root.add_child(node)
			node.position = Hex.world(id)
			var detail = t.duplicate()
			detail.current_day = run.data.day
			if not visited:
				detail.site = ""
			Terrain.board_details(node, detail, id, visual_seed, board_surface)
			if detail.site != "":
				var height = board_surface.height_at(node.position)
				_label(node, _site_name(detail.site), Vector3(0, height + 1.03, 0), Color("eee0b8"), 0.0041)
			tile_nodes[id] = node
			tile_signatures[id] = signature
	if terrain_changed: _batch_map_geometry()
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
		selection_ring.mesh = board_surface.outline(selected_cell, run.data.explored.has(selected_cell)) if current_tiles.has(selected_cell) else null
	light.light_color = Color("d0dce0") if run.data.weather == "rain" else Color("ffe5b2")
	light.light_energy = 0.48 if run.data.weather == "rain" else 0.68
	rain.emitting = run.data.weather == "rain"

func _batch_map_geometry() -> void:
	# Rebuild only after actual tile/fog changes. Particles, labels and actors stay independent.
	if is_instance_valid(map_batch): map_batch.free()
	map_batch = Node3D.new()
	map_root.add_child(map_batch)
	canopy_batch = Node3D.new()
	map_batch.add_child(canopy_batch)
	var groups = {}
	map_occluders.clear()
	for instance in fading_occluders.keys():
		if is_instance_valid(instance):
			_restore_occluder(instance, fading_occluders[instance])
	fading_occluders.clear()
	for tile in tile_nodes.values():
		for instance in tile.find_children("*","MeshInstance3D",true,false):
			if instance.skin!=null: continue
			var occluder = instance.has_meta("board_occluder")
			if occluder:
				map_occluders.append(instance)
			for surface in range(instance.mesh.get_surface_count()):
				var material = instance.get_active_material(surface)
				var key = str(material.get_instance_id())
				if material is StandardMaterial3D:
					key = "%s:%s:%s:%s:%s" % [material.albedo_color.to_html(),material.shading_mode,material.metallic,material.roughness,material.albedo_texture.resource_path if material.albedo_texture else ""]
				if occluder:
					key += ":occluder"
				if not groups.has(key):
					var tool = SurfaceTool.new()
					tool.begin(Mesh.PRIMITIVE_TRIANGLES)
					groups[key] = {"tool":tool,"material":material,"occluder":occluder}
				groups[key].tool.append_from(instance.mesh,surface,map_root.global_transform.affine_inverse()*instance.global_transform)
			instance.visible = false
	for group in groups.values():
		var instance = MeshInstance3D.new()
		instance.mesh = group.tool.commit()
		instance.material_override = group.material
		var parent = canopy_batch if group.occluder else map_batch
		parent.add_child(instance)
	_sync_canopy_lod(true)

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
	focus_point = Hex.world(id)
	_update_camera()

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

func set_map_input_enabled(enabled: bool) -> void:
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

func _drag_map_to(screen_position: Vector2) -> void:
	if not map_dragging and map_pointer_position.distance_to(screen_position) < DRAG_THRESHOLD:
		return
	map_dragging = true
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
		get_viewport().set_input_as_handled()
		if click:
			var id = board_surface.pick(camera.project_ray_origin(map_pointer_position), camera.project_ray_normal(map_pointer_position))
			if id != "":
				cell_clicked.emit(id)

func _unhandled_input(event: InputEvent) -> void:
	if battle_mode or not (event is InputEventMouseButton and event.pressed):
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
			_pan_map(motion * delta * 8.0)
	if not battle_mode:
		_update_occlusion(delta)

func _update_occlusion(delta: float) -> void:
	var model = dolls.get(map_actor)
	var blocked: Dictionary = {}
	var target = Vector3.ZERO
	var sight = -camera.global_basis.z
	if zoom_size <= OCCLUSION_ZOOM and is_instance_valid(model) and model.visible:
		var feet: Vector3 = model.global_position
		target = feet + Vector3.UP * 0.20
		var head = feet + Vector3.UP * 0.38
		for instance in map_occluders:
			if instance.global_position.distance_squared_to(feet) > 9.0:
				continue
			var bounds: AABB = (instance.global_transform * instance.get_aabb()).grow(0.025)
			if bounds.intersects_segment(target - sight * 3.0, target) != null or bounds.intersects_segment(head - sight * 3.0, head) != null:
				blocked[instance] = true
				if not fading_occluders.has(instance):
					_begin_occlusion(instance)
	for instance in fading_occluders.keys():
		var effect: Dictionary = fading_occluders[instance]
		var obscures = blocked.has(instance)
		effect.amount = move_toward(effect.amount, 1.0 if obscures else 0.0, delta * 8.0)
		if obscures:
			effect.target = target
		for material in effect.materials:
			material.set_shader_parameter("fade", effect.amount)
			material.set_shader_parameter("target", effect.target)
			material.set_shader_parameter("sight", sight)
		if effect.amount == 0.0 and not obscures:
			_restore_occluder(instance, effect)
			fading_occluders.erase(instance)

func _restore_occluder(instance: MeshInstance3D, effect: Dictionary) -> void:
	for surface in range(effect.originals.size()):
		instance.set_surface_override_material(surface, effect.originals[surface])

func _begin_occlusion(instance: MeshInstance3D) -> void:
	var effect = {"originals": [], "materials": [], "amount": 0.0, "target": Vector3.ZERO}
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
	tile.site = ""
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
	var title = str(Catalog.SKILLS[skill].name) if Catalog.SKILLS.has(skill) else "防守" if event.get("kind","")=="guard" else "使用物资" if event.get("kind","")=="heal" else "行动"
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
