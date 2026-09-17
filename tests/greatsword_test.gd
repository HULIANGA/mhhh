extends SceneTree
## Verify the M4.3 model budget, authored sockets, and visible blade coverage.

const GREATSWORD := preload("res://assets/models/greatsword.glb")
const EXPECTED_BLADE_LENGTH := 1.52
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var sword := GREATSWORD.instantiate()
	root.add_child(sword)
	var socket := _find_named(sword, "WeaponSocket") as Node3D
	var blade_base := _find_named(sword, "BladeBase") as Node3D
	var blade_tip := _find_named(sword, "BladeTip") as Node3D
	var blade_core := _find_named(sword, "BladeCore") as MeshInstance3D
	_expect(socket != null, "Greatsword exposes its authored WeaponSocket")
	_expect(blade_base != null and blade_tip != null, "Greatsword exposes BladeBase and BladeTip")
	_expect(blade_core != null, "Greatsword contains a visible BladeCore mesh")
	if socket and blade_base and blade_tip:
		var base_local := socket.to_local(blade_base.global_position)
		var tip_local := socket.to_local(blade_tip.global_position)
		_expect(absf(base_local.x) < 0.001 and absf(base_local.z) < 0.001, "BladeBase sits on the blade center line")
		_expect(absf(tip_local.x) < 0.001 and absf(tip_local.z) < 0.001, "BladeTip sits on the blade center line")
		_expect(is_equal_approx(base_local.y, 0.30) and is_equal_approx(tip_local.y, 1.82), "Blade sockets retain the authored 0.30 m to 1.82 m coverage")
		_expect(absf(base_local.distance_to(tip_local) - EXPECTED_BLADE_LENGTH) < 0.001, "Blade hit segment is 1.52 m long")
	if socket and blade_core:
		var bounds := blade_core.get_aabb()
		var lowest := INF
		var highest := -INF
		for corner_index in range(8):
			var corner := blade_core.to_global(bounds.get_endpoint(corner_index))
			var in_socket := socket.to_local(corner)
			lowest = minf(lowest, in_socket.y)
			highest = maxf(highest, in_socket.y)
		_expect(lowest <= 0.301 and highest >= 1.819, "Visible blade spans the complete gameplay hit segment")
	var triangles := _triangle_count(sword)
	_expect(triangles > 0 and triangles <= 3000, "Greatsword stays within the 3,000 triangle budget")
	print("GREATSWORD TESTS: %s (%d triangles)" % [("PASS" if failures == 0 else "%d FAILURES" % failures), triangles])
	sword.queue_free()
	quit(1 if failures else 0)

func _find_named(node: Node, target_name: StringName) -> Node:
	if node.name == target_name:
		return node
	for child: Node in node.get_children():
		var found := _find_named(child, target_name)
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
