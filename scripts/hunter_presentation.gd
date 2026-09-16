class_name HunterPresentation
extends Node3D
## Presentation boundary for replaceable hunter art and gameplay sockets.

var visuals: Node3D
var weapon_socket: Node3D
var blade_base: Marker3D
var blade_tip: Marker3D

func bind_placeholder(root: Node3D, sword: Node3D) -> void:
	visuals = root
	weapon_socket = sword
	blade_base = _marker(sword, "BladeBase", Vector3(0.0, 0.30, 0.0))
	blade_tip = _marker(sword, "BladeTip", Vector3(0.0, 1.82, 0.0))

func _marker(parent: Node3D, marker_name: String, at: Vector3) -> Marker3D:
	var existing := parent.get_node_or_null(marker_name) as Marker3D
	if existing:
		return existing
	var result := Marker3D.new()
	result.name = marker_name
	result.position = at
	parent.add_child(result)
	return result
