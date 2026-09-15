class_name Hunter
extends CharacterBody3D

signal stamina_changed(current: float, maximum: float)
signal action_changed(action: String, phase: String)
signal attack_landed(damage: int, target_name: String, world_position: Vector3)
signal action_denied(reason: String)

const STATE_FREE: StringName = &"free"
const STATE_LIGHT: StringName = &"light_attack"
const STATE_CHARGING: StringName = &"charging"
const STATE_CHARGE_RELEASE: StringName = &"charge_release"
const STATE_DODGING: StringName = &"dodging"
const LIGHT_ACTION: CombatActionData = preload("res://data/light_1.tres")
const CHARGE_ACTIONS: Array[CombatActionData] = [
	preload("res://data/charge_1.tres"),
	preload("res://data/charge_2.tres"),
]
const DODGE_ACTION: CombatActionData = preload("res://data/dodge.tres")
# Blade-tip directions in hunter-local space. +X is the hunter's right,
# -Z is forward, and +Y is vertically above the grip.
const POSE_RIGHT_HIGH := Vector3(0.62, 0.58, -0.53)
const POSE_LEFT_LOW := Vector3(-0.62, -0.48, -0.62)
const POSE_STRAIGHT_DOWN := Vector3(0.0, -0.58, -0.82)
const POSE_CHARGE_BACK := Vector3(0.0, 0.42, 0.91)

@export_range(1.0, 12.0) var move_speed: float = 5.2
@export var acceleration: float = 32.0
@export var turn_speed: float = 16.0
@export var dodge_speed: float = 11.0
@export var max_stamina: float = 100.0
@export var stamina_regeneration: float = 24.0
@export var stamina_regeneration_delay: float = 0.7
@export var attack_hold_repeat_delay: float = 0.28

var travel_distance: float = 0.0
var input_frame := HunterInputFrame.new()
var stamina: float = 100.0
var action_state: StringName = STATE_FREE
var action_phase: StringName = &"ready"
var combo_step: int = 0
var charge_tier: int = 0
var is_invulnerable: bool = false
var last_attack_damage: int = 0
var _action_data: CombatActionData
var _action_elapsed: float = 0.0
var _charge_elapsed: float = 0.0
var _queued_attack: bool = false
var _queued_dodge: bool = false
var _attack_hold_elapsed: float = 0.0
var _auto_attack_active: bool = false
var _attack_repeat_blocked: bool = false
var _attack_token: int = 0
var _hit_targets: Dictionary = {}
var _dodge_direction := Vector3.ZERO
var _stamina_delay_left: float = 0.0
var _walk_time: float = 0.0
var _left_leg: MeshInstance3D
var _right_leg: MeshInstance3D
var _sword: Node3D
var _sword_rest_position := Vector3(0.48, 0.92, -0.26)
var _sword_rest_rotation := Vector3(0.12, 0.0, -0.62)
@onready var visuals: Node3D = $Visuals
@onready var input_source: HunterInputSource = $InputSource

func _ready() -> void:
	stamina = max_stamina
	_build_placeholder()
	stamina_changed.emit(stamina, max_stamina)
	action_changed.emit("Ready", "Aim, then choose an action")

func _physics_process(delta: float) -> void:
	input_frame = input_source.sample(get_viewport(), global_position)
	_update_attack_hold(delta)
	_regenerate_stamina(delta)
	_handle_action_input()
	_advance_action(delta)
	_move_hunter(delta)
	_animate_walk(delta)
	_animate_action()
	if (action_state == STATE_LIGHT or action_state == STATE_CHARGE_RELEASE) and action_phase == &"active":
		_resolve_attack_hit()
	if position.y < -5.0:
		reset()

func _handle_action_input() -> void:
	if action_state == STATE_FREE:
		if input_frame.dodge.pressed:
			_cancel_attack_repeat()
			_try_start_dodge()
		elif input_frame.charge.pressed:
			_try_start_charge()
		elif input_frame.attack.pressed or (_auto_attack_active and input_frame.attack.held):
			_start_light_attack()
	elif action_state == STATE_CHARGING:
		if input_frame.dodge.pressed:
			_try_start_dodge()
		elif input_frame.charge.released:
			_release_charge()
	elif action_state == STATE_LIGHT:
		if input_frame.dodge.pressed:
			_cancel_attack_repeat()
			_queued_attack = false
			_queued_dodge = true
		elif input_frame.attack.pressed or (_auto_attack_active and input_frame.attack.held):
			_queued_attack = true

func _advance_action(delta: float) -> void:
	if action_state == STATE_CHARGING:
		_charge_elapsed += delta
		var new_tier := 2 if _charge_elapsed >= CHARGE_ACTIONS[1].charge_threshold else 1
		if new_tier != charge_tier:
			charge_tier = new_tier
			action_changed.emit("Charge %s" % _roman(charge_tier), "Release to strike")
		if charge_tier == 2:
			_release_charge()
		return
	if action_state == STATE_FREE:
		return
	_action_elapsed += delta
	if action_state == STATE_DODGING:
		is_invulnerable = _action_elapsed <= DODGE_ACTION.active
		_set_phase(&"invulnerable" if is_invulnerable else &"recovery")
		if _action_elapsed >= DODGE_ACTION.duration():
			_finish_action()
		return
	if not _action_data:
		_finish_action()
		return
	if _action_elapsed < _action_data.windup:
		_set_phase(&"windup")
	elif _action_elapsed < _action_data.windup + _action_data.active:
		_set_phase(&"active")
	else:
		_set_phase(&"recovery")
	if _action_elapsed >= _action_data.duration():
		if action_state == STATE_LIGHT and _queued_dodge:
			_queued_dodge = false
			_queued_attack = false
			if not _try_start_dodge():
				_finish_action()
		elif action_state == STATE_LIGHT and _queued_attack:
			_start_light_attack()
		else:
			_finish_action()

func _move_hunter(delta: float) -> void:
	var axis := input_frame.movement.limit_length(1.0)
	var movement_scale := 1.0
	if action_state == STATE_CHARGING:
		movement_scale = 0.34
	elif action_state == STATE_LIGHT or action_state == STATE_CHARGE_RELEASE:
		movement_scale = _action_data.movement_scale if _action_data else 0.0
	var desired := Vector3(axis.x, 0.0, axis.y) * move_speed * movement_scale
	if action_state == STATE_DODGING:
		var roll_scale := 1.0 if _action_elapsed <= DODGE_ACTION.active else maxf(0.0, 1.0 - (_action_elapsed - DODGE_ACTION.active) / DODGE_ACTION.recovery)
		desired = _dodge_direction * dodge_speed * roll_scale
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
	if action_state == STATE_FREE or action_state == STATE_CHARGING:
		_apply_aim(input_frame.aim_direction, delta)

func _start_light_attack() -> void:
	combo_step = 1
	_start_attack(LIGHT_ACTION, STATE_LIGHT)

func _try_start_charge() -> bool:
	var cost := CHARGE_ACTIONS[0].stamina_cost
	if not _spend_stamina(cost, "Not enough stamina to charge"):
		return false
	action_state = STATE_CHARGING
	action_phase = &"charging"
	charge_tier = 1
	combo_step = 0
	_charge_elapsed = 0.0
	_action_data = null
	action_changed.emit("Charge I", "Hold for tier II · dodge to cancel")
	return true

func _release_charge() -> void:
	if action_state != STATE_CHARGING:
		return
	var tier := charge_tier
	_start_attack(CHARGE_ACTIONS[tier - 1], STATE_CHARGE_RELEASE)
	charge_tier = tier

func _try_start_dodge() -> bool:
	if not _spend_stamina(DODGE_ACTION.stamina_cost, "Not enough stamina to dodge"):
		return false
	if input_frame.attack.held or _auto_attack_active:
		_cancel_attack_repeat()
	var axis := input_frame.movement.limit_length(1.0)
	_dodge_direction = Vector3(axis.x, 0.0, axis.y).normalized()
	if _dodge_direction.is_zero_approx():
		_dodge_direction = _forward()
	action_state = STATE_DODGING
	action_phase = &"invulnerable"
	_action_data = DODGE_ACTION
	_action_elapsed = 0.0
	_charge_elapsed = 0.0
	charge_tier = 0
	combo_step = 0
	_queued_attack = false
	_queued_dodge = false
	is_invulnerable = true
	action_changed.emit(DODGE_ACTION.display_name, "Invulnerable")
	return true

func _start_attack(data: CombatActionData, state: StringName) -> void:
	action_state = state
	action_phase = &"windup"
	_action_data = data
	_action_elapsed = 0.0
	_queued_attack = false
	_queued_dodge = false
	_attack_token += 1
	_hit_targets.clear()
	last_attack_damage = data.damage
	is_invulnerable = false
	action_changed.emit(data.display_name, "Windup")

func _finish_action() -> void:
	action_state = STATE_FREE
	action_phase = &"ready"
	_action_data = null
	_action_elapsed = 0.0
	_charge_elapsed = 0.0
	_queued_attack = false
	_queued_dodge = false
	combo_step = 0
	charge_tier = 0
	is_invulnerable = false
	action_changed.emit("Ready", "Aim, then choose an action")

func _set_phase(next_phase: StringName) -> void:
	if next_phase == action_phase:
		return
	action_phase = next_phase
	var name_text := _action_data.display_name if _action_data else "Action"
	action_changed.emit(name_text, String(next_phase).capitalize())

func _resolve_attack_hit() -> void:
	# Match the active hit volume to the rendered blade instead of placing one
	# fixed sphere in front of the hunter. Multiple overlapping probes cover the
	# segment from just above the guard to the sword tip as it moves each tick.
	var grip_position := _sword.global_position
	var blade_length := minf(1.82, _action_data.hit_reach + 0.3)
	var blade_tip := _sword.to_global(Vector3(0.0, blade_length, 0.0))
	var sphere := SphereShape3D.new()
	sphere.radius = clampf(_action_data.hit_radius * 0.52, 0.38, 0.58)
	for fraction: float in [0.32, 0.55, 0.78, 1.0]:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = sphere
		query.transform = Transform3D(Basis.IDENTITY, grip_position.lerp(blade_tip, fraction))
		query.collision_mask = 4
		query.collide_with_areas = true
		query.collide_with_bodies = true
		query.exclude = [get_rid()]
		for result: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 16):
			var target: Object = result.get("collider")
			if not target or _hit_targets.has(target.get_instance_id()) or not target.has_method("receive_hit"):
				continue
			_hit_targets[target.get_instance_id()] = true
			var hit_position: Vector3 = target.global_position if target is Node3D else blade_tip
			if target.receive_hit(_attack_token, _action_data.damage, hit_position):
				attack_landed.emit(_action_data.damage, target.name, hit_position)

func _spend_stamina(amount: float, failure_message: String) -> bool:
	if stamina + 0.001 < amount:
		action_denied.emit(failure_message)
		return false
	stamina -= amount
	_stamina_delay_left = stamina_regeneration_delay
	stamina_changed.emit(stamina, max_stamina)
	return true

func _regenerate_stamina(delta: float) -> void:
	if _stamina_delay_left > 0.0:
		_stamina_delay_left = maxf(_stamina_delay_left - delta, 0.0)
		return
	if action_state != STATE_FREE or stamina >= max_stamina:
		return
	stamina = minf(stamina + stamina_regeneration * delta, max_stamina)
	stamina_changed.emit(stamina, max_stamina)

func _forward() -> Vector3:
	return (-visuals.global_basis.z).normalized()

func _apply_aim(direction: Vector3, delta: float) -> void:
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		var target_angle := atan2(-direction.x, -direction.z)
		visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, 1.0 - exp(-turn_speed * delta))

func clear_input() -> void:
	input_source.clear()
	input_frame = HunterInputFrame.new()
	_attack_hold_elapsed = 0.0
	_auto_attack_active = false

func prepare_for_pause() -> void:
	clear_input()
	# A cleared held button is cancellation, never an implicit charge release.
	if action_state == STATE_CHARGING:
		_finish_action()

func reset() -> void:
	clear_input()
	_attack_repeat_blocked = false
	position = Vector3(0.0, 0.05, 5.0)
	velocity = Vector3.ZERO
	travel_distance = 0.0
	visuals.rotation = Vector3.ZERO
	visuals.position = Vector3.ZERO
	stamina = max_stamina
	_stamina_delay_left = 0.0
	_finish_action()
	stamina_changed.emit(stamina, max_stamina)

func _animate_walk(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	_walk_time += delta * speed * 2.8
	var swing := sin(_walk_time) * 0.38 * minf(speed / move_speed, 1.0)
	_left_leg.rotation.x = swing
	_right_leg.rotation.x = -swing
	visuals.position.y = absf(sin(_walk_time)) * 0.045 * minf(speed / move_speed, 1.0)

func _animate_action() -> void:
	if not _sword:
		return
	# SwordGripPivot never moves during an attack: all blade motion rotates around
	# the hunter's hand at the center of the grip.
	_sword.position = _sword_rest_position
	_sword.quaternion = Quaternion.from_euler(_sword_rest_rotation)
	if action_state == STATE_CHARGING:
		var tension := minf(_charge_elapsed / CHARGE_ACTIONS[1].charge_threshold, 1.0)
		_set_sword_rotation(
			Quaternion.from_euler(_sword_rest_rotation),
			_blade_direction_pose(POSE_CHARGE_BACK),
			_smooth(tension)
		)
	elif action_state == STATE_LIGHT:
		_animate_light_swing()
	elif action_state == STATE_CHARGE_RELEASE:
		_animate_charge_release()
	elif action_state == STATE_DODGING:
		visuals.rotation.x = sin(clampf(_action_elapsed / DODGE_ACTION.duration(), 0.0, 1.0) * PI) * -0.55
		return
	visuals.rotation.x = move_toward(visuals.rotation.x, 0.0, 0.18)

func _animate_light_swing() -> void:
	# Keep one readable light attack until the shared timing is settled.
	_animate_sword_swing(
		_blade_direction_pose(POSE_RIGHT_HIGH),
		_blade_direction_pose(POSE_LEFT_LOW)
	)

func _update_attack_hold(delta: float) -> void:
	if input_frame.attack.pressed:
		_attack_hold_elapsed = 0.0
		_auto_attack_active = false
		_attack_repeat_blocked = false
	if not input_frame.attack.held:
		_attack_hold_elapsed = 0.0
		_auto_attack_active = false
		return
	if _attack_repeat_blocked:
		return
	_attack_hold_elapsed += delta
	if _attack_hold_elapsed >= attack_hold_repeat_delay:
		_auto_attack_active = true

func _cancel_attack_repeat() -> void:
	_attack_repeat_blocked = true
	_attack_hold_elapsed = 0.0
	_auto_attack_active = false

func _animate_charge_release() -> void:
	var held_pose := _blade_direction_pose(POSE_CHARGE_BACK)
	var strike_pose := _blade_direction_pose(POSE_STRAIGHT_DOWN)
	var rest_pose := Quaternion.from_euler(_sword_rest_rotation)
	# The charged blade is already behind the hunter. Hold that pose through the
	# release windup, then rotate only in the vertical fore/aft plane to cleave.
	if _action_elapsed < _action_data.windup:
		_sword.quaternion = held_pose
	elif _action_elapsed < _action_data.windup + _action_data.active:
		var strike_progress := (_action_elapsed - _action_data.windup) / maxf(_action_data.active, 0.001)
		_set_sword_rotation(held_pose, strike_pose, _smooth(strike_progress))
	else:
		var recovery_progress := (_action_elapsed - _action_data.windup - _action_data.active) / maxf(_action_data.recovery, 0.001)
		_set_sword_rotation(strike_pose, rest_pose, _smooth(recovery_progress))

func _animate_sword_swing(windup_pose: Quaternion, strike_pose: Quaternion) -> void:
	var rest_pose := Quaternion.from_euler(_sword_rest_rotation)
	if _action_elapsed < _action_data.windup:
		var windup_progress := _action_elapsed / maxf(_action_data.windup, 0.001)
		_set_sword_rotation(rest_pose, windup_pose, _smooth(windup_progress))
	elif _action_elapsed < _action_data.windup + _action_data.active:
		var strike_progress := (_action_elapsed - _action_data.windup) / maxf(_action_data.active, 0.001)
		_set_sword_rotation(windup_pose, strike_pose, _smooth(strike_progress))
	else:
		# Recovery is always rendered in full. Buffered/held input may choose the
		# next action, but it never skips the return-to-rest animation.
		var recovery_progress := (_action_elapsed - _action_data.windup - _action_data.active) / maxf(_action_data.recovery, 0.001)
		_set_sword_rotation(strike_pose, rest_pose, _smooth(recovery_progress))

func _blade_direction_pose(direction: Vector3) -> Quaternion:
	return Quaternion(Vector3.UP, direction.normalized())

func _set_sword_rotation(from: Quaternion, to: Quaternion, weight: float) -> void:
	_sword.quaternion = from.slerp(to, clampf(weight, 0.0, 1.0))

func _smooth(value: float) -> float:
	var clamped := clampf(value, 0.0, 1.0)
	return clamped * clamped * (3.0 - 2.0 * clamped)

func _roman(number: int) -> String:
	return "II" if number == 2 else "I"

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
	_sword = Node3D.new()
	_sword.name = "SwordGripPivot"
	visuals.add_child(_sword)
	_sword.position = _sword_rest_position
	_sword.rotation = _sword_rest_rotation
	var sword_model := Node3D.new()
	sword_model.name = "SwordModel"
	_sword.add_child(sword_model)
	# Local origin is the grip center. Guard and blade extend toward +Y.
	var grip := FieldGeometry.box(sword_model, Vector3(0.12, 0.42, 0.13), Vector3.ZERO, dark)
	grip.name = "Grip"
	var guard := FieldGeometry.box(sword_model, Vector3(0.58, 0.11, 0.17), Vector3(0, 0.25, 0), gold)
	guard.name = "Guard"
	var blade := FieldGeometry.box(sword_model, Vector3(0.30, 1.55, 0.11), Vector3(0, 1.08, 0), steel)
	blade.name = "Blade"
	FieldGeometry.ring(self, 0.60, 0.035, Vector3(0, 0.04, 0), FieldGeometry.material(Color("86d6bc"), 0.4))
	var arrow := CylinderMesh.new()
	arrow.top_radius = 0.0
	arrow.bottom_radius = 0.17
	arrow.height = 0.35
	arrow.radial_segments = 3
	var marker := FieldGeometry.instance(visuals, arrow, Vector3(0, 0.09, -0.9), gold)
	marker.rotation.x = -PI / 2.0
