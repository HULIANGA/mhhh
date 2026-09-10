extends Camera3D

@export var follow_speed: float = 7.0
var _focus := Vector3(0, 0, 3)
@onready var target: Hunter = get_node("../Player")

func _ready() -> void:
	snap_to_target()

func _physics_process(delta: float) -> void:
	_focus = _focus.lerp(_target_focus(), 1.0 - exp(-follow_speed * delta))
	_update_transform()

func snap_to_target() -> void:
	_focus = _target_focus()
	_update_transform()

func _target_focus() -> Vector3:
	return Vector3(clampf(target.position.x, -5.0, 5.0), 0.0, clampf(target.position.z, -4.0, 4.0))

func _update_transform() -> void:
	position = _focus + Vector3(0, 18, 12.6)
	look_at(_focus)

