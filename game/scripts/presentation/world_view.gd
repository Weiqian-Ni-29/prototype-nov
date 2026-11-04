class_name ExpeditionView
extends Node3D
const Hex = preload("res://scripts/domain/hex_map.gd")
const Terrain = preload("res://scripts/presentation/terrain.gd")
const Doll = preload("res://scripts/presentation/doll.gd")
const FontAsset = preload("res://assets/fonts/NotoSansSC.ttf")
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
var zoom_size = 15.0
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
	selection_ring = Doll._cylinder(self, 1.025, 1.025, 0.035, Color("e3c88b"), Vector3.ZERO, 6)
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
	_update_camera()

func reset() -> void:
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
	if ocean.sea_cells.is_empty(): ocean.build(current_tiles)
	ocean.visible = not battle_mode
	if not battle_mode: environment.background_color = Color("23577b")
	map_root.visible = not battle_mode
	actor_root.visible = not battle_mode
	selection_ring.visible = not battle_mode
	var terrain_changed = false
	for id in current_tiles:
		var revealed = run.data.explored.has(id)
		var t = current_tiles[id].duplicate(true)
		t.current_day = run.data.day
		var signature = JSON.stringify(t) if revealed else "fog"
		if tile_signatures.get(id, "") != signature:
			terrain_changed = true
			if tile_nodes.has(id):
				tile_nodes[id].free()
			var node = Terrain.tile(map_root, t, revealed, hash(str(run.data.seed) + id))
			node.position = Hex.world(id)
			if revealed:
				if t.site != "":
					_label(node, _site_name(t.site), Vector3(0, 1.35, 0), Color("eee0b8"))
				if not t.enemies.is_empty():
					_label(node, "⚔" if t.discovered_enemy else "…", Vector3(0, 0.8, 0.25), Color("e8aa86") if t.discovered_enemy else Color("b8b59e"))
			tile_nodes[id] = node
			tile_signatures[id] = signature
	if terrain_changed: _batch_map_geometry()
	var counts = {}
	var visible_counts = {}
	var actor_ids = run.data.actors.keys()
	actor_ids.sort_custom(func(a,b):
		if a==b: return false
		if a=="hero": return true
		if b=="hero": return false
		return str(a)<str(b))
	for id in actor_ids:
		var a = run.actor(id)
		if a.joined or (run.data.explored.has(a.position) and current_tiles[a.position].npc==id):
			visible_counts[a.position] = int(visible_counts.get(a.position,0))+1
	for id in actor_ids:
		var a = run.actor(id)
		var visible_actor = a.joined or (run.data.explored.has(a.position) and current_tiles[a.position].npc == id)
		if not visible_actor:
			if dolls.has(id):
				dolls[id].visible = false
			continue
		if not dolls.has(id):
			var doll = Doll.new()
			actor_root.add_child(doll)
			doll.configure(a)
			dolls[id] = doll
		var model = dolls[id]
		model.visible = true
		model.selected = id == selected_id
		model.set_down(a.hp <= 0)
		var count = int(counts.get(a.position, 0))
		counts[a.position] = count + 1
		var total = int(visible_counts[a.position])
		model.scale = Vector3.ONE*(0.32 if total>4 else 0.4 if total>1 else 0.45)
		var offset = Vector3(0,current_tiles[a.position].height+0.1,0)
		if total>1:
			var ring_count = total-1 if total==7 else total
			var index = count-1 if total==7 else count
			if index>=0:
				var angle = TAU*float(index)/ring_count
				offset += Vector3(cos(angle),0,sin(angle))*(0.52 if total>3 else 0.34)
		var point = Hex.world(a.position) + offset
		if model.has_meta("cell") and model.get_meta("cell") != a.position:
			model.move_to(point)
		elif not model.is_moving():
			model.position = point
		model.set_meta("cell", a.position)
	if selected_cell != "" and current_tiles.has(selected_cell):
		var height = current_tiles[selected_cell].height if run.data.explored.has(selected_cell) else 0.0
		selection_ring.position = Hex.world(selected_cell) + Vector3(0, height + 0.025, 0)
	light.light_color = Color("d0dce0") if run.data.weather == "rain" else Color("ffe5b2")
	light.light_energy = 0.48 if run.data.weather == "rain" else 0.68
	rain.emitting = run.data.weather == "rain"

func _batch_map_geometry() -> void:
	# Rebuild only after actual tile/fog changes. Particles, labels and actors stay independent.
	if is_instance_valid(map_batch): map_batch.free()
	map_batch = Node3D.new()
	map_root.add_child(map_batch)
	var groups = {}
	for tile in tile_nodes.values():
		for instance in tile.find_children("*","MeshInstance3D",true,false):
			if instance.skin!=null: continue
			for surface in range(instance.mesh.get_surface_count()):
				var material = instance.get_active_material(surface)
				var key = str(material.get_instance_id())
				if material is StandardMaterial3D:
					key = "%s:%s:%s:%s:%s" % [material.albedo_color.to_html(),material.shading_mode,material.metallic,material.roughness,material.albedo_texture.resource_path if material.albedo_texture else ""]
				if not groups.has(key):
					var tool = SurfaceTool.new()
					tool.begin(Mesh.PRIMITIVE_TRIANGLES)
					groups[key] = {"tool":tool,"material":material}
				groups[key].tool.append_from(instance.mesh,surface,map_root.global_transform.affine_inverse()*instance.global_transform)
			instance.visible = false
	for group in groups.values():
		var instance = MeshInstance3D.new()
		instance.mesh = group.tool.commit()
		instance.material_override = group.material
		map_batch.add_child(instance)

func focus_cell(id: String) -> void:
	focus_point = Hex.world(id)
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

func _unhandled_input(event: InputEvent) -> void:
	if battle_mode:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_size = maxf(8, zoom_size - 1.2)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_size = minf(30, zoom_size + 1.2)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var origin = camera.project_ray_origin(event.position)
			var normal = camera.project_ray_normal(event.position)
			var hit = Plane(Vector3.UP, 0.05).intersects_ray(origin, normal)
			if hit != null:
				var id = Hex.closest(hit, current_tiles)
				if id != "":
					cell_clicked.emit(id)

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
	if not battle_mode:
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
			focus_point += motion * delta * 8.0
			_update_camera()

func begin_battle(run: RefCounted, combat: RefCounted) -> void:
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
	var stage = Terrain.tile(battle_stage, tile, true, hash(position))
	stage.scale = Vector3(6.5, 1.0, 4.5)
	tile.ground_only = false
	# Backdrop is assembled from the actual biome; props never reveal neighboring cells.
	for i in range(5):
		var backdrop = Terrain.tile(battle_stage, tile, true, i + 31)
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
		model.selected = id == combat.current

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

static func _label(parent: Node3D, text: String, point: Vector3, color: Color) -> void:
	var label = Label3D.new()
	label.text = text
	var font = FontVariation.new()
	font.base_font = FontAsset
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600.0}
	label.font = font
	label.font_size = 40
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	label.outline_size = 7
	label.position = point
	parent.add_child(label)
