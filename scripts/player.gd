class_name Hunter
extends CharacterBody3D

@export_range(1.0, 12.0) var move_speed: float = 5.2
@export var acceleration: float = 32.0
@export var turn_speed: float = 16.0

var travel_distance: float = 0.0
var aim_point := Vector3.ZERO
var _walk_time: float = 0.0
var _left_leg: MeshInstance3D
var _right_leg: MeshInstance3D
@onready var visuals: Node3D = $Visuals

func _ready() -> void:
	_build_placeholder()

func _physics_process(delta: float) -> void:
	var axis := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# The camera has no yaw: screen right is +X, screen up is -Z.
	var desired := Vector3(axis.x, 0.0, axis.y) * move_speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(desired, acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not is_on_floor():
		velocity.y -= 22.0 * delta
	else:
		velocity.y = 0.0
	var previous := position
	move_and_slide()
	travel_distance += Vector2(position.x - previous.x, position.z - previous.z).length()
	_aim_at_mouse(delta)
	_animate_walk(delta)
	if position.y < -5.0:
		reset()

func _aim_at_mouse(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var ray := camera.project_ray_normal(mouse)
	var intersection: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, ray)
	if intersection == null:
		return
	aim_point = intersection
	var direction := aim_point - global_position
	direction.y = 0.0
	if direction.length_squared() > 0.04:
		var target_angle := atan2(-direction.x, -direction.z)
		visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, 1.0 - exp(-turn_speed * delta))

func reset() -> void:
	position = Vector3(0.0, 0.05, 5.0)
	velocity = Vector3.ZERO
	travel_distance = 0.0
	visuals.rotation = Vector3.ZERO

func _animate_walk(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	_walk_time += delta * speed * 2.8
	var swing := sin(_walk_time) * 0.38 * minf(speed / move_speed, 1.0)
	_left_leg.rotation.x = swing
	_right_leg.rotation.x = -swing
	visuals.position.y = absf(sin(_walk_time)) * 0.045 * minf(speed / move_speed, 1.0)

func _build_placeholder() -> void:
	var cloth := FieldGeometry.material(Color("78b9ab"))
	var dark := FieldGeometry.material(Color("253739"))
	var leather := FieldGeometry.material(Color("665645"))
	var steel := FieldGeometry.material(Color("bdd0c8"))
	var gold := FieldGeometry.material(Color("deb778"))
	_left_leg = FieldGeometry.box(visuals, Vector3(0.23, 0.56, 0.26), Vector3(-0.19, 0.30, 0), dark)
	_right_leg = FieldGeometry.box(visuals, Vector3(0.23, 0.56, 0.26), Vector3(0.19, 0.30, 0), dark)
	FieldGeometry.box(visuals, Vector3(0.66, 0.65, 0.4), Vector3(0, 0.90, 0), cloth)
	FieldGeometry.box(visuals, Vector3(0.70, 0.12, 0.43), Vector3(0, 0.67, 0), leather)
	FieldGeometry.box(visuals, Vector3(0.27, 0.48, 0.28), Vector3(-0.46, 0.91, 0), leather)
	FieldGeometry.box(visuals, Vector3(0.27, 0.48, 0.28), Vector3(0.46, 0.91, 0), leather)
	var head := SphereMesh.new()
	head.radius = 0.26
	head.height = 0.52
	head.radial_segments = 8
	head.rings = 4
	FieldGeometry.instance(visuals, head, Vector3(0, 1.48, 0), steel)
	FieldGeometry.box(visuals, Vector3(0.36, 0.08, 0.10), Vector3(0, 1.49, -0.23), dark)
	var sword := Node3D.new()
	visuals.add_child(sword)
	sword.position = Vector3(0.18, 0.95, 0.32)
	sword.rotation.z = -0.38
	FieldGeometry.box(sword, Vector3(0.30, 1.18, 0.11), Vector3(0, 0.30, 0), steel)
	FieldGeometry.box(sword, Vector3(0.52, 0.11, 0.17), Vector3(0, -0.31, 0), gold)
	FieldGeometry.box(sword, Vector3(0.11, 0.34, 0.12), Vector3(0, -0.52, 0), dark)
	FieldGeometry.ring(self, 0.60, 0.035, Vector3(0, 0.04, 0), FieldGeometry.material(Color("86d6bc"), 0.4))
	var arrow := CylinderMesh.new()
	arrow.top_radius = 0.0
	arrow.bottom_radius = 0.17
	arrow.height = 0.35
	arrow.radial_segments = 3
	var marker := FieldGeometry.instance(visuals, arrow, Vector3(0, 0.09, -0.9), gold)
	marker.rotation.x = -PI / 2.0
