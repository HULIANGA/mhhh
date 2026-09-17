extends SceneTree
## Verify the M4.4 hunter skeleton, normalized actions, and root-motion contract.

const HUNTER := preload("res://assets/models/hunter.glb")
const REQUIRED_BONES := [
	"Root", "Pelvis", "Spine", "Chest", "Neck", "Head",
	"UpperArm.L", "Forearm.L", "Hand.L",
	"UpperArm.R", "Forearm.R", "Hand.R", "WeaponSocket",
	"Thigh.L", "Shin.L", "Foot.L", "Thigh.R", "Shin.R", "Foot.R",
]
const REQUIRED_ANIMATIONS := [
	"idle", "run", "light_attack", "charge_enter", "charge_hold",
	"charge_release_1", "charge_release_2", "charge_cancel", "dodge", "hit", "defeated",
]

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var hunter := HUNTER.instantiate()
	root.add_child(hunter)
	var skeleton := _find_type(hunter, Skeleton3D) as Skeleton3D
	var player := _find_type(hunter, AnimationPlayer) as AnimationPlayer
	_expect(skeleton != null, "Hunter GLB exposes a Skeleton3D")
	_expect(player != null, "Hunter GLB exposes an AnimationPlayer")
	if skeleton:
		for bone_name: String in REQUIRED_BONES:
			_expect(skeleton.find_bone(bone_name) >= 0, "Hunter skeleton exposes " + bone_name)
	if player:
		for animation_name: String in REQUIRED_ANIMATIONS:
			_expect(player.has_animation(animation_name), "Hunter imports animation " + animation_name)
		for loop_name: String in ["idle", "run"]:
			if player.has_animation(loop_name):
				_expect(player.get_animation(loop_name).loop_mode != Animation.LOOP_NONE, loop_name + " keeps its loop contract")
		var model_transform: Transform3D = hunter.transform
		for animation_name: String in REQUIRED_ANIMATIONS:
			if not player.has_animation(animation_name):
				continue
			var animation := player.get_animation(animation_name)
			for fraction: float in [0.0, 0.5, 1.0]:
				player.play(animation_name)
				player.seek(animation.length * fraction, true)
				_expect(hunter.transform.is_equal_approx(model_transform), animation_name + " keeps the imported model root in place")
		player.stop()
		if skeleton and player.has_animation("light_attack"):
			var weapon_bone := skeleton.find_bone("WeaponSocket")
			var attack := player.get_animation("light_attack")
			player.play("light_attack")
			player.seek(0.0, true)
			var ready_grip := skeleton.get_bone_global_pose(weapon_bone).origin
			player.seek(attack.length * 7.0 / 24.0, true)
			var raised_grip := skeleton.get_bone_global_pose(weapon_bone).origin
			_expect(raised_grip.y > ready_grip.y + 0.2, "Light attack raises the weapon hand during windup")
			_expect(raised_grip.z < ready_grip.z - 0.1, "Light attack raises the weapon in front instead of behind the hunter")
			player.stop()
	var triangles := _triangle_count(hunter)
	_expect(triangles > 0 and triangles <= 15000, "Hunter stays within the 15,000 triangle budget")
	print("HUNTER ASSET TESTS: %s (%d triangles)" % [("PASS" if failures == 0 else "%d FAILURES" % failures), triangles])
	hunter.queue_free()
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
