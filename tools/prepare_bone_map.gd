extends SceneTree
## Same-author GLB rests are verified by prepare_character_assets.py before name mapping.
func _initialize() -> void:
	var map = BoneMap.new()
	map.profile = SkeletonProfileHumanoid.new()
	for name in ["Root","Hips","Spine","Chest","Head","LeftUpperArm","LeftLowerArm","LeftHand","RightUpperArm","RightLowerArm","RightHand","LeftUpperLeg","LeftLowerLeg","LeftFoot","LeftToes","RightUpperLeg","RightLowerLeg","RightFoot","RightToes"]:
		map.set_skeleton_bone_name(name,name)
	assert(ResourceSaver.save(map,"res://assets/characters/humanoid_bone_map.tres")==OK)
	print("Humanoid BoneMap saved; optional neck/shoulder/twist bones are not fabricated.")
	quit()
