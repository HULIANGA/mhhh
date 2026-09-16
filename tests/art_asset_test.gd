extends SceneTree

## Verify that Godot can import the committed M4.1 GLB contract fixture.

const FIXTURE := preload("res://assets/models/contract_fixture.glb")
const REQUIRED_NODES := [
	"ContractRig",
	"ContractMesh",
	"WeaponSocket",
	"BladeBase",
	"BladeTip",
	"HornLBase",
	"HornLTip",
	"HornRBase",
	"HornRTip",
]
var failures := 0


func _initialize() -> void:
	var fixture := FIXTURE.instantiate()
	root.add_child(fixture)
	for node_name: String in REQUIRED_NODES:
		_expect(_find_named(fixture, node_name) != null, "Imported GLB exposes " + node_name)
	_expect(_find_type(fixture, Skeleton3D) != null, "Imported GLB exposes a Skeleton3D")
	var player := _find_type(fixture, AnimationPlayer) as AnimationPlayer
	_expect(player != null, "Imported GLB exposes an AnimationPlayer")
	if player:
		print("Imported animations: ", player.get_animation_list())
		_expect(player.has_animation("idle"), "Godot imports the idle_loop source action as idle")
		if player.has_animation("idle"):
			_expect(player.get_animation("idle").loop_mode != Animation.LOOP_NONE, "Imported idle animation keeps its loop contract")
	print("ART ASSET TESTS: %s" % ("PASS" if failures == 0 else "%d FAILURES" % failures))
	fixture.queue_free()
	quit(1 if failures else 0)


func _find_named(node: Node, node_name: String) -> Node:
	if node.name == node_name:
		return node
	for child: Node in node.get_children():
		var found := _find_named(child, node_name)
		if found:
			return found
	return null


func _find_type(node: Node, type: Variant) -> Node:
	if is_instance_of(node, type):
		return node
	for child: Node in node.get_children():
		var found := _find_type(child, type)
		if found:
			return found
	return null


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)
