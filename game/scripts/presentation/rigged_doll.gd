extends Node3D
## AnimationPlayer owns the skeleton exclusively. Display offsets never change domain positions.
const HumanoidMap = preload("res://assets/characters/humanoid_bone_map.tres")
var skeleton: Skeleton3D
var animator: AnimationPlayer
var definition: Dictionary
var body: Node3D
var bones: Dictionary = {}
var down = false
var action = "idle"
var role = "melee"
var asset_name = "knight"
var locomotion = "idle"
var holding_down = false
var held_weapon: Node3D
var weapon_bone = ""
var contact_sample: Dictionary = {}
var bow_release_pending = false
var bow_release_clip = "attack_bow"

func configure(character: Dictionary) -> void:
	definition = character.duplicate(true)
	var id = str(definition.get("id", ""))
	var skill = str(definition.get("skill", ""))
	var type = str(definition.get("type",""))
	if type.begins_with("npc:"): id = type.trim_prefix("npc:")
	role = "wolf" if id == "grit" else "beast" if type in ["boar","lurker"] else "spider" if type in ["spider","hunter_elite"] else "swarm" if type=="swarm" else "crossbow" if type=="archer" else "bow" if id in ["cen", "lorne"] or skill == "trail_shot" else "magic" if skill in ["ember", "torrent", "heal", "ignite", "wet"] else "melee"
	asset_name = {"melee":"knight", "bow":"ranger", "crossbow":"rogue_hooded","magic":"mage", "wolf":"wolf","beast":type,"spider":"spider","swarm":"swarm"}[role]
	if id=="lorne": asset_name = "rogue"
	if type=="archer": asset_name = "rogue_hooded"
	if type=="apothecary": asset_name = "rogue"
	if type in ["furnace","canal","furnace_elite","lamp_boss"]: asset_name = "knight"
	if type=="lamp_boss": asset_name="barbarian"
	body = Node3D.new()
	add_child(body)
	var scene = load("res://assets/characters/" + asset_name + ".glb").instantiate()
	body.add_child(scene)
	skeleton = _find_skeleton(scene)
	animator = _find_animator(scene)
	assert(skeleton != null and animator != null, "Rigged asset requires an actual skeleton and animation player")
	animator.animation_finished.connect(_animation_finished)
	for alias in {"root":"Root", "head":"Head", "arm_r":"RightUpperArm", "arm_l":"LeftUpperArm", "leg_l":"LeftUpperLeg", "leg_r":"RightUpperLeg"}:
		var bone_name = {"root":"Root", "head":"Head", "arm_r":"RightUpperArm", "arm_l":"LeftUpperArm", "leg_l":"LeftUpperLeg", "leg_r":"RightUpperLeg"}[alias]
		if role in ["melee","bow","crossbow","magic"]: bone_name = HumanoidMap.get_skeleton_bone_name(bone_name)
		bones[alias] = skeleton.find_bone(bone_name)
	if role in ["melee","bow","crossbow","magic"]:
		_customize(scene)
		if type not in ["furnace","canal","furnace_elite","lamp_boss"]:
			_weapon("bow_withString" if role == "bow" else "crossbow_2handed" if role=="crossbow" else "staff" if role == "magic" else "sword_1handed", "LeftHandSocket" if role == "bow" else "RightHandSocket")
		if skill == "guard_all": _weapon("shield_round", "LeftHandSocket")
		if id == "eve":
			var ears = BoneAttachment3D.new()
			ears.bone_name = "Head"
			skeleton.add_child(ears)
			for side in [-1,1]:
				var ear = load("res://scripts/presentation/doll.gd")._cone(ears,0.075,0.3,Color("e9c2a2"),Vector3(side*0.32,0.07,0))
				ear.rotation.z = side * -1.15
		_identity_details(id,type)
	else:
		_customize_creature(scene)
		if id=="grit": body.scale = Vector3.ONE*1.18
		if type=="hunter_elite": body.scale = Vector3.ONE*1.2
	for clip in animator.get_animation_list():
		animator.get_animation(clip).loop_mode = Animation.LOOP_LINEAR if str(clip) in ["idle", "walk", "run", "channel","crossbow_aim"] else Animation.LOOP_NONE
	play_action("idle")
	if int(definition.get("hp",1))<=0:
		down = true
		holding_down = true
		action = "down"
		animator.play("down",0.0)
		animator.seek(animator.get_animation("down").length,true)
		animator.pause()

func _customize_creature(node: Node) -> void:
	if node is MeshInstance3D:
		for surface in range(node.mesh.get_surface_count()):
			var original = node.get_active_material(surface)
			if original is StandardMaterial3D and ("shell" in original.resource_name or "fur" in original.resource_name):
				var material = original.duplicate()
				material.albedo_color = Color(str(definition.get("color","a0b6a0"))).srgb_to_linear()
				node.set_surface_override_material(surface,material)
	for child in node.get_children(): _customize_creature(child)

func _identity_details(id: String, type: String) -> void:
	var shape = load("res://scripts/presentation/doll.gd")
	if id=="lorne" or type=="apothecary":
		var chest = BoneAttachment3D.new()
		chest.bone_name = "Chest"
		skeleton.add_child(chest)
		shape._box(chest,Vector3(0.34,0.3,0.14),Color("8a6e47"),Vector3(0,-0.1,-0.25))
		shape._box(chest,Vector3(0.08,0.08,0.02),Color("c6af78"),Vector3(0,-0.08,-0.33))
	if type in ["furnace","canal","furnace_elite","lamp_boss"]:
		var head = BoneAttachment3D.new()
		head.bone_name = "Head"
		skeleton.add_child(head)
		var color = Color(str(definition.color))
		shape._box(head,Vector3(0.55,0.5,0.54),color.darkened(0.5),Vector3(0,0.1,0.01))
		var slit = shape._box(head,Vector3(0.4,0.055,0.03),color.lightened(0.5),Vector3(0,0.13,0.3))
		slit.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var chest = BoneAttachment3D.new()
		chest.bone_name = "Chest"
		skeleton.add_child(chest)
		var core = shape._sphere(chest,Vector3(0.15,0.17,0.09),color.lightened(0.4),Vector3(0,0.1,0.25))
		core.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if type=="canal":
			for side in [-1,1]: shape._cylinder(chest,0.1,0.1,0.55,color,Vector3(side*0.28,0.15,-0.27),8)
		else:
			shape._cylinder(chest,0.14,0.18,0.4,color.darkened(0.25),Vector3(0,0.3,-0.25),8)
		if type in ["furnace_elite","lamp_boss"]:
			body.scale = Vector3.ONE*(1.15 if type=="furnace_elite" else 1.25)
			for i in range(5): shape._cone(head,0.07,0.25,Color("d3c797"),Vector3(-0.26+i*0.13,0.48,0))

func _customize(node: Node) -> void:
	if node is MeshInstance3D:
		var id = str(definition.get("id", ""))
		var type = str(definition.get("type",""))
		if type.begins_with("npc:"): id = type.trim_prefix("npc:")
		if type in ["furnace","canal","furnace_elite","lamp_boss"] and ("Head" in node.name or "Helmet" in node.name or "Cape" in node.name or "Hat" in node.name): node.visible = false
		if "Mage_Hat" in node.name and id in ["eve", "ember", "tide", "hero"]: node.visible = false
		if true:
			for surface in range(node.mesh.get_surface_count()):
				var original = node.get_active_material(surface)
				if original is StandardMaterial3D:
					var material = ShaderMaterial.new()
					material.shader = preload("res://scripts/presentation/character_palette.gdshader")
					material.set_shader_parameter("atlas", original.albedo_texture)
					material.set_shader_parameter("clothing", Color(str(definition.get("color", "a0b6a0"))))
					material.set_shader_parameter("hair",Color({"hero":"544c43","cen":"553e30","lorne":"b69b6f","eve":"dedfcb","ember":"783c32","tide":"405665"}.get(id,"756b59")))
					material.set_shader_parameter("head_part", "Head" in node.name)
					material.set_shader_parameter("construct", type in ["furnace","canal","furnace_elite","lamp_boss"])
					node.set_surface_override_material(surface, material)
	for child in node.get_children(): _customize(child)

func _weapon(asset: String, bone: String) -> void:
	var attachment = BoneAttachment3D.new()
	attachment.bone_name = bone
	skeleton.add_child(attachment)
	var prop = load("res://assets/characters/" + asset + ".gltf").instantiate()
	attachment.add_child(prop)
	_customize(prop)
	if asset.begins_with("sword"):
		held_weapon = prop
		weapon_bone = bone

func weapon_tip_global() -> Vector3:
	if held_weapon == null:
		var name = "Head0" if role=="swarm" else "Head"
		var index = skeleton.find_bone(name)
		if index<0: return global_position + global_basis.z * 0.8 + Vector3.UP
		skeleton.force_update_all_bone_transforms()
		return skeleton.global_transform*skeleton.get_bone_global_pose(index)*Vector3(0,0.32 if role=="wolf" else 0.35 if role in ["beast","spider"] else 0.15,0)
	var meshes = held_weapon.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty(): return global_position
	var mesh = meshes[0]
	var bounds = mesh.get_aabb()
	var tip = bounds.get_center()
	tip.y = bounds.end.y
	var relative = held_weapon.to_local(mesh.to_global(tip))
	var bone = skeleton.find_bone(weapon_bone)
	skeleton.force_update_all_bone_transforms()
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone) * held_weapon.transform * relative

func emission_point_global() -> Vector3:
	var name = "LeftHandSocket" if role=="bow" else "RightHandSocket"
	var bone = skeleton.find_bone(name)
	if bone<0: return global_position+Vector3.UP
	skeleton.force_update_all_bone_transforms()
	return skeleton.global_transform*skeleton.get_bone_global_pose(bone)*Vector3(0,0.6 if role=="magic" else 0,0)

func sample_melee_contact(clip: String = "attack_melee", ceiling: float = 2.0) -> Dictionary:
	var key = clip+":"+str(snappedf(ceiling,0.1))
	if contact_sample.has(key): return contact_sample[key]
	var length = animator.get_animation(clip).length
	animator.play(clip, 0)
	var best_tip = Vector3.ZERO
	var best_time = length * 0.5
	var best_score = -INF
	for i in range(4,22):
		var time = length * float(i) / 24.0
		animator.seek(time, true)
		var tip = body.to_local(weapon_tip_global())
		var world_tip = body.to_global(tip)
		var score = tip.z - maxf(0,world_tip.y-ceiling)*3.0 - maxf(0,0.25-world_tip.y)*3.0
		if score>best_score:
			best_score = score
			best_tip = tip
			best_time = time
	contact_sample[key] = {"tip":best_tip, "time":best_time, "length":length, "clip":clip}
	play_action("idle")
	return contact_sample[key]

func play_action(kind: String, duration: float = -1.0) -> void:
	if animator == null: return
	action = kind
	bow_release_pending = false
	var clip = kind
	match kind:
		"attack": clip = "bow_draw" if role == "bow" else "crossbow_shoot" if role=="crossbow" else "cast" if role == "magic" else "attack_melee"
		"cast": clip = "bow_draw" if role == "bow" else "crossbow_aim" if role=="crossbow" else "cast"
		"aim": clip = "crossbow_aim"
		"ultimate": clip = "attack_heavy" if role == "melee" else "bow_draw_up" if role=="bow" else "support"
		"heal": clip = "support"
		"recover":
			var was_down = animator.current_animation=="down"
			var previous_time = animator.current_animation_position
			holding_down = false
			animator.play_backwards("down", 0.1)
			if was_down: animator.seek(previous_time,true)
			return
	if not animator.has_animation(clip):
		push_error("Missing required animation %s for %s" % [clip, asset_name])
		return
	if kind in ["idle", "walk", "run"]: locomotion = kind
	holding_down = false
	var rate = animator.get_animation(clip).length / duration if duration > 0 else 1.0
	if role=="bow" and clip in ["bow_draw","bow_draw_up"]:
		bow_release_pending = true
		bow_release_clip = "bow_release_up" if clip=="bow_draw_up" else "attack_bow"
		rate = animator.get_animation(clip).length / 0.3
	animator.play(clip, 0.1, rate)

func set_down(value: bool) -> void:
	if down == value: return
	down = value
	if value:
		if action in ["idle", "walk", "run"]: play_action("down")
	else:
		if holding_down or animator.current_animation=="down": play_action("recover")

func _animation_finished(clip: StringName) -> void:
	if str(clip) in ["bow_draw","bow_draw_up"] and bow_release_pending:
		bow_release_pending = false
		animator.play(bow_release_clip,0.04,animator.get_animation(bow_release_clip).length/0.2)
		return
	if str(clip) == "down" and down:
		holding_down = true
		animator.pause()
		return
	if down: play_action("down")
	else: play_action(locomotion)

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	for child in node.get_children():
		var found = _find_skeleton(child)
		if found != null: return found
	return null

func _find_animator(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer: return node
	for child in node.get_children():
		var found = _find_animator(child)
		if found != null: return found
	return null
