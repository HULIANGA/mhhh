class_name MonsterPresentation
extends Node3D
## Presentation boundary for replaceable monster art and gameplay sockets.

var visuals: Node3D
var left_horn_base: Marker3D
var left_horn_tip: Marker3D
var right_horn_base: Marker3D
var right_horn_tip: Marker3D

func bind_placeholder(root: Node3D, left_horn: Node3D, right_horn: Node3D) -> void:
	visuals = root
	left_horn_base = _marker(left_horn, "HornLBase", Vector3(0.0, 0.0, 0.32))
	left_horn_tip = _marker(left_horn, "HornLTip", Vector3(0.0, 0.0, -0.42))
	right_horn_base = _marker(right_horn, "HornRBase", Vector3(0.0, 0.0, 0.32))
	right_horn_tip = _marker(right_horn, "HornRTip", Vector3(0.0, 0.0, -0.42))

func _marker(parent: Node3D, marker_name: String, at: Vector3) -> Marker3D:
	var existing := parent.get_node_or_null(marker_name) as Marker3D
	if existing:
		return existing
	var result := Marker3D.new()
	result.name = marker_name
	result.position = at
	parent.add_child(result)
	return result
