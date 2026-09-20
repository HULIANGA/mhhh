extends SceneTree
## Verify the M4.5 quadruped skeleton, authored actions, and in-place contract.

const MONSTER := preload("res://assets/models/monster.glb")
const REQUIRED_BONES := [
	"Root", "Pelvis", "Spine", "Shoulders", "Neck", "Head",
	"HornLBase", "HornLTip", "HornRBase", "HornRTip",
	"UpperForeleg.L", "LowerForeleg.L", "UpperForeleg.R", "LowerForeleg.R",
	"UpperHindleg.L", "LowerHindleg.L", "UpperHindleg.R", "LowerHindleg.R",
]
const REQUIRED_ANIMATIONS := [
	"idle", "run", "sweep", "pounce", "charge_windup", "charge_run",
	"charge_recovery", "crash_stunned", "hit", "defeated",
]

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var monster := MONSTER.instantiate()
	root.add_child(monster)
	var skeleton := _find_type(monster, Skeleton3D) as Skeleton3D
	var player := _find_type(monster, AnimationPlayer) as AnimationPlayer
	_expect(skeleton != null, "Monster GLB exposes a Skeleton3D")
	_expect(player != null, "Monster GLB exposes an AnimationPlayer")
	if skeleton:
		for bone_name: String in REQUIRED_BONES:
			_expect(skeleton.find_bone(bone_name) >= 0, "Monster skeleton exposes " + bone_name)
	if player:
		for animation_name: String in REQUIRED_ANIMATIONS:
			_expect(player.has_animation(animation_name), "Monster imports animation " + animation_name)
		for loop_name: String in ["idle", "run"]:
			if player.has_animation(loop_name):
				_expect(player.get_animation(loop_name).loop_mode != Animation.LOOP_NONE, loop_name + " keeps its loop contract")
		var model_transform: Transform3D = monster.transform
		for animation_name: String in REQUIRED_ANIMATIONS:
			if not player.has_animation(animation_name):
				continue
			var animation := player.get_animation(animation_name)
			for fraction: float in [0.0, 0.5, 1.0]:
				player.play(animation_name)
				player.seek(animation.length * fraction, true)
				_expect(monster.transform.is_equal_approx(model_transform), animation_name + " keeps world movement out of the imported model root")
		player.stop()
		if skeleton and player.has_animation("sweep"):
			var head_bone := skeleton.find_bone("Head")
			var left_tip_bone := skeleton.find_bone("HornLTip")
			var sweep := player.get_animation("sweep")
			player.play("sweep")
			player.seek(sweep.length * 7.0 / 24.0, true)
			var windup_direction := skeleton.get_bone_global_pose(left_tip_bone).origin - skeleton.get_bone_global_pose(head_bone).origin
			player.seek(sweep.length * 12.0 / 24.0, true)
			var strike_direction := skeleton.get_bone_global_pose(left_tip_bone).origin - skeleton.get_bone_global_pose(head_bone).origin
			_expect(windup_direction.angle_to(strike_direction) > 0.45, "Sweep moves the horn silhouette through a readable arc")
			player.stop()
	var triangles := _triangle_count(monster)
	_expect(triangles > 0 and triangles <= 15000, "Monster stays within the 15,000 triangle budget")
	print("MONSTER ASSET TESTS: %s (%d triangles)" % [("PASS" if failures == 0 else "%d FAILURES" % failures), triangles])
	monster.queue_free()
	quit(1 if failures else 0)


func _find_type(node: Node, type: Variant) -> Node:
	if is_instance_of(node, type):
		return node
	for child: Node in node.get_children():
		var found := _find_type(child, type)
		if found:
			return found
	return null


func _triangle_count(node: Node) -> int:
	var result := 0
	if node is MeshInstance3D and node.mesh:
		for surface in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			result += indices.size() / 3 if not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size() / 3
	for child: Node in node.get_children():
		result += _triangle_count(child)
	return result


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)
