class_name BreakableObstacle
extends StaticBody3D
## A lightweight arena prop that a monster charge can destroy and reset.

var is_broken: bool = false
var _collision: CollisionShape3D
var _visuals: Node3D

func setup(dimensions: Vector3, material: Material) -> void:
	name = "BreakableBarricade"
	collision_layer = 1
	collision_mask = 0
	add_to_group("charge_breakable")
	_collision = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = dimensions
	_collision.shape = shape
	_collision.position.y = dimensions.y * 0.5
	add_child(_collision)
	_visuals = Node3D.new()
	_visuals.name = "Visuals"
	add_child(_visuals)
	FieldGeometry.box(_visuals, dimensions, Vector3(0, dimensions.y * 0.5, 0), material)
	var brace := FieldGeometry.material(Color("554536"))
	FieldGeometry.box(_visuals, Vector3(dimensions.x + 0.14, 0.16, dimensions.z + 0.08), Vector3(0, dimensions.y * 0.7, 0), brace)

func break_from_charge(_world_position: Vector3) -> void:
	if is_broken:
		return
	is_broken = true
	collision_layer = 0
	if _collision:
		_collision.set_deferred("disabled", true)
	if _visuals:
		_visuals.hide()

func reset_obstacle() -> void:
	is_broken = false
	collision_layer = 1
	if _collision:
		_collision.set_deferred("disabled", false)
	if _visuals:
		_visuals.show()
