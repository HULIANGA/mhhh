class_name FieldMonster
extends CharacterBody3D

signal health_changed(current: int, maximum: int)
signal hit_received(damage: int, world_position: Vector3)
signal defeated
signal state_changed(state: StringName)

const STATE_IDLE: StringName = &"idle"
const STATE_CHASING: StringName = &"chasing"
const STATE_READY: StringName = &"ready"
const STATE_DEAD: StringName = &"dead"

@export_range(1, 999) var max_health: int = 180
@export_range(0.1, 12.0) var move_speed: float = 3.6
@export_range(0.1, 40.0) var acceleration: float = 18.0
@export_range(0.1, 40.0) var turn_speed: float = 10.0
@export_range(1.0, 40.0) var detection_range: float = 24.0
@export_range(1.0, 6.0) var attack_range: float = 2.25
@export var target_path: NodePath = NodePath("../Player")
@export var arena_min := Vector2(-16.65, -13.65)
@export var arena_max := Vector2(16.65, 13.65)

var health: int = 180
var state: StringName = STATE_IDLE
var is_dead: bool = false
var distance_to_target: float = INF
var _target: Hunter
var _spawn_transform: Transform3D
var _resolved_attacks: Dictionary = {}
var _flash_time: float = 0.0
var _walk_time: float = 0.0
var _body_material: StandardMaterial3D
var _visuals: Node3D
var _health_label: Label3D
var _left_foreleg: Node3D
var _right_foreleg: Node3D
var _left_hindleg: Node3D
var _right_hindleg: Node3D

func _ready() -> void:
	name = "FieldMonster"
	add_to_group("damageable")
	_spawn_transform = global_transform
	_target = get_node_or_null(target_path) as Hunter
	_build_placeholder()
	reset_monster()

func _physics_process(delta: float) -> void:
	_update_feedback(delta)
	if is_dead:
		velocity = Vector3.ZERO
		return
	if not is_instance_valid(_target):
		_target = get_node_or_null(target_path) as Hunter
	if not is_instance_valid(_target) or _target.is_defeated:
		_stop(STATE_IDLE, delta)
		return
	var offset := _target.global_position - global_position
	offset.y = 0.0
	distance_to_target = offset.length()
	if distance_to_target > detection_range:
		_stop(STATE_IDLE, delta)
		return
	_face(offset, delta)
	if distance_to_target <= attack_range:
		_stop(STATE_READY, delta)
		return
	_set_state(STATE_CHASING)
	var desired := offset.normalized() * move_speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(desired, acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	_apply_gravity(delta)
	move_and_slide()
	_clamp_to_arena()
	_animate_walk(delta)

func receive_hit(attack_token: int, damage: int, hit_position: Vector3) -> bool:
	if damage <= 0 or is_dead or _resolved_attacks.has(attack_token):
		return false
	_resolved_attacks[attack_token] = true
	var applied_damage := mini(damage, health)
	health = maxi(health - damage, 0)
	_flash_time = 0.18
	_update_label()
	health_changed.emit(health, max_health)
	hit_received.emit(applied_damage, hit_position)
	if health <= 0:
		_die()
	return true

func reset_monster() -> void:
	global_transform = _spawn_transform
	velocity = Vector3.ZERO
	health = max_health
	is_dead = false
	distance_to_target = INF
	_resolved_attacks.clear()
	_flash_time = 0.0
	_walk_time = 0.0
	if _visuals:
		_visuals.rotation = Vector3.ZERO
		_visuals.position = Vector3.ZERO
	_set_state(STATE_IDLE, true)
	_update_label()
	health_changed.emit(health, max_health)

func set_target(target: Hunter) -> void:
	_target = target

func _die() -> void:
	if is_dead:
		return
	is_dead = true
	velocity = Vector3.ZERO
	_set_state(STATE_DEAD)
	if _visuals:
		_visuals.rotation.z = deg_to_rad(78.0)
	defeated.emit()

func _stop(next_state: StringName, delta: float) -> void:
	_set_state(next_state)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	_apply_gravity(delta)
	move_and_slide()
	_clamp_to_arena()
	_animate_walk(delta)

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 22.0 * delta
	else:
		velocity.y = 0.0

func _face(direction: Vector3, delta: float) -> void:
	if direction.length_squared() <= 0.0001:
		return
	var target_angle := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_angle, 1.0 - exp(-turn_speed * delta))

func _clamp_to_arena() -> void:
	position.x = clampf(position.x, arena_min.x, arena_max.x)
	position.z = clampf(position.z, arena_min.y, arena_max.y)

func _set_state(next_state: StringName, force_emit: bool = false) -> void:
	if state == next_state and not force_emit:
		return
	state = next_state
	state_changed.emit(state)

func _update_feedback(delta: float) -> void:
	_flash_time = maxf(_flash_time - delta, 0.0)
	if _body_material:
		_body_material.albedo_color = Color("ef8e74") if _flash_time > 0.0 else Color("75635a")

func _animate_walk(delta: float) -> void:
	if not _visuals or is_dead:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	_walk_time += delta * speed * 3.1
	var swing := sin(_walk_time) * 0.38 * minf(speed / move_speed, 1.0)
	_left_foreleg.rotation.x = swing
	_right_hindleg.rotation.x = swing
	_right_foreleg.rotation.x = -swing
	_left_hindleg.rotation.x = -swing
	_visuals.position.y = absf(sin(_walk_time * 2.0)) * 0.035 * minf(speed / move_speed, 1.0)

func _update_label() -> void:
	if not _health_label:
		return
	_health_label.text = "FIELD BEAST\n%d / %d" % [health, max_health] if health > 0 else "FIELD BEAST\nDOWN — R TO RESET"

func _build_placeholder() -> void:
	_visuals = Node3D.new()
	_visuals.name = "Visuals"
	add_child(_visuals)
	_body_material = FieldGeometry.material(Color("75635a"))
	var hide := FieldGeometry.material(Color("51463f"))
	var horn := FieldGeometry.material(Color("d7c99f"))
	var warning := FieldGeometry.material(Color("c98665"), 0.28)
	FieldGeometry.box(_visuals, Vector3(1.55, 1.05, 2.25), Vector3(0, 1.05, 0), _body_material)
	FieldGeometry.box(_visuals, Vector3(1.25, 0.92, 0.92), Vector3(0, 1.12, -1.32), hide)
	FieldGeometry.box(_visuals, Vector3(0.22, 0.22, 0.72), Vector3(-0.42, 1.38, -1.88), horn)
	FieldGeometry.box(_visuals, Vector3(0.22, 0.22, 0.72), Vector3(0.42, 1.38, -1.88), horn)
	_left_foreleg = _leg(Vector3(-0.52, 0.48, -0.66), hide)
	_right_foreleg = _leg(Vector3(0.52, 0.48, -0.66), hide)
	_left_hindleg = _leg(Vector3(-0.52, 0.48, 0.68), hide)
	_right_hindleg = _leg(Vector3(0.52, 0.48, 0.68), hide)
	FieldGeometry.ring(self, attack_range, 0.045, Vector3(0, 0.055, 0), warning)
	_health_label = Label3D.new()
	_health_label.position = Vector3(0, 2.2, 0)
	_health_label.font_size = 42
	_health_label.pixel_size = 0.008
	_health_label.modulate = Color("eadab5")
	_health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_health_label)

func _leg(at: Vector3, material: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	_visuals.add_child(pivot)
	FieldGeometry.box(pivot, Vector3(0.34, 0.9, 0.38), Vector3(0, -0.32, 0), material)
	return pivot
