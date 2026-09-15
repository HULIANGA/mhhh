class_name Hunter
extends CharacterBody3D

signal stamina_changed(current: float, maximum: float)
signal health_changed(current: int, maximum: int)
signal hit_received(damage: int, world_position: Vector3)
signal defeated
signal action_changed(action: String, phase: String)
signal attack_landed(damage: int, target_name: String, world_position: Vector3)
signal action_denied(reason: String)

const STATE_FREE: StringName = &"free"
const STATE_LIGHT: StringName = &"light_attack"
const STATE_CHARGING: StringName = &"charging"
const STATE_CHARGE_CANCEL: StringName = &"charge_cancel"
const STATE_CHARGE_RELEASE: StringName = &"charge_release"
const STATE_DODGING: StringName = &"dodging"
const STATE_DEFEATED: StringName = &"defeated"
const LIGHT_ACTION: CombatActionData = preload("res://data/light_1.tres")
const CHARGE_ACTIONS: Array[CombatActionData] = [
	preload("res://data/charge_1.tres"),
	preload("res://data/charge_2.tres"),
]
const DODGE_ACTION: CombatActionData = preload("res://data/dodge.tres")
# Blade-tip directions in hunter-local space. +X is the hunter's right,
# -Z is forward, and +Y is vertically above the grip.
const POSE_REST_FORWARD_UP := Vector3(0.0, 0.35, -0.94)
const POSE_RIGHT_HIGH := Vector3(0.62, 0.58, -0.53)
const POSE_LEFT_LOW := Vector3(-0.62, -0.48, -0.62)
const POSE_STRAIGHT_DOWN := Vector3(0.0, -0.58, -0.82)
const POSE_CHARGE_BACK := Vector3(0.0, 0.42, 0.91)
const CHARGE_STRIKE_APEX := 0.34
const CHARGE_CANCEL_DURATION := 0.22
const BLADE_TOP_RIGHT_TILT := deg_to_rad(10.0)
const BLADE_TOP_LEFT_TILT := deg_to_rad(-10.0)

@export_range(1.0, 12.0) var move_speed: float = 5.2
@export var acceleration: float = 32.0
@export var turn_speed: float = 16.0
@export var dodge_speed: float = 11.0
@export_range(1, 999) var max_health: int = 100
@export var max_stamina: float = 100.0
@export var stamina_regeneration: float = 24.0
@export var stamina_regeneration_delay: float = 0.7
@export var attack_hold_repeat_delay: float = 0.28

var travel_distance: float = 0.0
var input_frame := HunterInputFrame.new()
var health: int = 100
var stamina: float = 100.0
var action_state: StringName = STATE_FREE
var action_phase: StringName = &"ready"
var combo_step: int = 0
var charge_tier: int = 0
var is_invulnerable: bool = false
var is_defeated: bool = false
var last_attack_damage: int = 0
var _action_data: CombatActionData
var _action_elapsed: float = 0.0
var _charge_elapsed: float = 0.0
var _charge_stamina_spent: float = 0.0
var _charge_release_start_elapsed: float = 0.0
var _queued_attack: bool = false
var _queued_dodge: bool = false
var _attack_hold_elapsed: float = 0.0
var _auto_attack_active: bool = false
var _attack_repeat_blocked: bool = false
var _queued_charge: bool = false
var _attack_token: int = 0
var _hit_targets: Dictionary = {}
var _resolved_incoming_attacks: Dictionary = {}
var _dodge_direction := Vector3.ZERO
var _stamina_delay_left: float = 0.0
var _walk_time: float = 0.0
var _left_leg: MeshInstance3D
var _right_leg: MeshInstance3D
var _sword: Node3D
var _sword_rest_position := Vector3(0.48, 0.92, -0.26)
@onready var visuals: Node3D = $Visuals
@onready var input_source: HunterInputSource = $InputSource

func _ready() -> void:
	health = max_health
	stamina = max_stamina
	_build_placeholder()
	health_changed.emit(health, max_health)
	stamina_changed.emit(stamina, max_stamina)
	action_changed.emit("Ready", "Aim, then choose an action")

func _physics_process(delta: float) -> void:
	if is_defeated:
		velocity = Vector3.ZERO
		return
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
	# Charge is a hold action: remember a press made during another action, but
	# discard it if the button is released before that action fully completes.
	if action_state != STATE_FREE and action_state != STATE_CHARGING:
		if input_frame.charge.pressed:
			_queued_charge = true
		if input_frame.charge.released:
			_queued_charge = false
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
		var full_charge_time := CHARGE_ACTIONS[1].charge_threshold
		var next_elapsed := minf(_charge_elapsed + delta, full_charge_time)
		var target_stamina_spent := CHARGE_ACTIONS[0].stamina_cost * next_elapsed / full_charge_time
		if not _drain_charge_stamina(target_stamina_spent):
			_charge_elapsed = next_elapsed
			_release_charge()
			return
		_charge_elapsed = next_elapsed
		var new_tier := 0
		if _charge_elapsed >= CHARGE_ACTIONS[1].charge_threshold:
			new_tier = 2
		elif _charge_elapsed >= CHARGE_ACTIONS[0].charge_threshold:
			new_tier = 1
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
			_finish_or_start_queued_charge()
		return
	if action_state == STATE_CHARGE_CANCEL:
		if _action_elapsed >= CHARGE_CANCEL_DURATION:
			_finish_or_start_queued_charge()
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
		elif _queued_charge and input_frame.charge.held:
			_finish_or_start_queued_charge()
		elif action_state == STATE_LIGHT and _queued_attack:
			_start_light_attack()
		else:
			_finish_action()

func _move_hunter(delta: float) -> void:
	var axis := input_frame.movement.limit_length(1.0)
	var movement_scale := 1.0
	if action_state == STATE_CHARGING or action_state == STATE_CHARGE_CANCEL:
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
	if stamina + 0.001 < cost:
		action_denied.emit("Not enough stamina to charge")
		return false
	_queued_charge = false
	action_state = STATE_CHARGING
	action_phase = &"charging"
	charge_tier = 0
	combo_step = 0
	_charge_elapsed = 0.0
	_charge_stamina_spent = 0.0
	_action_data = null
	action_changed.emit("Charging", "Hold to reach tier I")
	return true

func _release_charge() -> void:
	if action_state != STATE_CHARGING:
		return
	if charge_tier == 0:
		_charge_release_start_elapsed = _charge_elapsed
		action_state = STATE_CHARGE_CANCEL
		action_phase = &"recovery"
		_action_elapsed = 0.0
		_action_data = null
		action_changed.emit("Charge cancelled", "Returning to ready")
		return
	var tier := charge_tier
	_charge_release_start_elapsed = _charge_elapsed
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
	_charge_stamina_spent = 0.0
	_charge_release_start_elapsed = 0.0
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
	_charge_stamina_spent = 0.0
	_charge_release_start_elapsed = 0.0
	_queued_attack = false
	_queued_dodge = false
	_queued_charge = false
	combo_step = 0
	charge_tier = 0
	is_invulnerable = false
	action_changed.emit("Ready", "Aim, then choose an action")

func _finish_or_start_queued_charge() -> void:
	var should_start_charge := _queued_charge and input_frame.charge.held
	_finish_action()
	if should_start_charge:
		_try_start_charge()

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

func receive_hit(attack_token: int, damage: int, hit_position: Vector3) -> bool:
	if damage <= 0 or _resolved_incoming_attacks.has(attack_token):
		return false
	# Record an attack even when dodged. The same active attack must not deal a
	# delayed hit after its overlap began during the invulnerability window.
	_resolved_incoming_attacks[attack_token] = true
	if is_invulnerable or is_defeated:
		return false
	var applied_damage := mini(damage, health)
	health = maxi(health - damage, 0)
	health_changed.emit(health, max_health)
	hit_received.emit(applied_damage, hit_position)
	if health <= 0:
		_enter_defeated_state()
	return true

func _enter_defeated_state() -> void:
	if is_defeated:
		return
	clear_input()
	_finish_action()
	is_defeated = true
	action_state = STATE_DEFEATED
	action_phase = &"down"
	velocity = Vector3.ZERO
	visuals.rotation.z = deg_to_rad(-72.0)
	action_changed.emit("Hunter down", "Press R to reset")
	defeated.emit()

func _spend_stamina(amount: float, failure_message: String) -> bool:
	if stamina + 0.001 < amount:
		action_denied.emit(failure_message)
		return false
	stamina -= amount
	_stamina_delay_left = stamina_regeneration_delay
	stamina_changed.emit(stamina, max_stamina)
	return true

func _drain_charge_stamina(target_total: float) -> bool:
	var requested := maxf(target_total - _charge_stamina_spent, 0.0)
	if requested <= 0.0:
		return true
	var drained := minf(requested, stamina)
	stamina -= drained
	_charge_stamina_spent += drained
	_stamina_delay_left = stamina_regeneration_delay
	stamina_changed.emit(stamina, max_stamina)
	return drained + 0.001 >= requested

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
	_queued_charge = false

func prepare_for_pause() -> void:
	clear_input()
	# A cleared held button is cancellation, never an implicit charge release.
	if action_state == STATE_CHARGING:
		_finish_action()

func reset() -> void:
	clear_input()
	_attack_repeat_blocked = false
	is_defeated = false
	position = Vector3(0.0, 0.05, 5.0)
	velocity = Vector3.ZERO
	travel_distance = 0.0
	visuals.rotation = Vector3.ZERO
	visuals.position = Vector3.ZERO
	health = max_health
	stamina = max_stamina
	_resolved_incoming_attacks.clear()
	_stamina_delay_left = 0.0
	_finish_action()
	health_changed.emit(health, max_health)
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
	_sword.quaternion = _sword_rest_pose()
	if action_state == STATE_CHARGING:
		_sword.quaternion = _charge_pose_at(_charge_elapsed)
	elif action_state == STATE_CHARGE_CANCEL:
		var cancel_progress := _smooth(_action_elapsed / CHARGE_CANCEL_DURATION)
		_sword.quaternion = _charge_cancel_pose(cancel_progress)
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
		POSE_RIGHT_HIGH,
		POSE_LEFT_LOW
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
	# Tier I attacks immediately from the released pose instead of finishing the
	# travel to the full-charge rear pose. Tier II already starts fully raised.
	if _action_elapsed < _action_data.windup:
		var windup_progress := _action_elapsed / maxf(_action_data.windup, 0.001)
		if charge_tier == 1:
			_sword.quaternion = _tier_one_windup_pose(_smooth(windup_progress))
		else:
			_sword.quaternion = _charge_pose_at(CHARGE_ACTIONS[1].charge_threshold)
	elif _action_elapsed < _action_data.windup + _action_data.active:
		var strike_progress := (_action_elapsed - _action_data.windup) / maxf(_action_data.active, 0.001)
		if charge_tier == 1:
			_sword.quaternion = _tier_one_downward_pose(_smooth(strike_progress))
		else:
			_sword.quaternion = _charged_strike_pose(_smooth(strike_progress))
	else:
		var recovery_progress := (_action_elapsed - _action_data.windup - _action_data.active) / maxf(_action_data.recovery, 0.001)
		var recovery_direction := POSE_STRAIGHT_DOWN.normalized().slerp(
			POSE_REST_FORWARD_UP.normalized(),
			_smooth(recovery_progress)
		)
		_sword.quaternion = _fore_aft_pose(recovery_direction)

func _charge_pose_at(elapsed: float) -> Quaternion:
	var tension := _charge_tension_at(elapsed)
	# Raise the tip in the vertical fore/aft plane while slowly rolling the blade
	# from its ready-state right lean to a 10-degree left lean.
	var blade_axis := POSE_REST_FORWARD_UP.normalized().slerp(POSE_CHARGE_BACK.normalized(), tension).normalized()
	var blade_tilt := lerpf(BLADE_TOP_RIGHT_TILT, BLADE_TOP_LEFT_TILT, tension)
	return _fore_aft_pose(blade_axis, blade_tilt)

func _charge_cancel_pose(progress: float) -> Quaternion:
	# Reverse the partial charging motion rather than snapping back to ready.
	var release_tension := _charge_tension_at(_charge_release_start_elapsed)
	var release_direction := POSE_REST_FORWARD_UP.normalized().slerp(
		POSE_CHARGE_BACK.normalized(),
		release_tension
	).normalized()
	var release_tilt := lerpf(BLADE_TOP_RIGHT_TILT, BLADE_TOP_LEFT_TILT, release_tension)
	var blade_direction := release_direction.slerp(POSE_REST_FORWARD_UP.normalized(), progress).normalized()
	var blade_tilt := lerpf(release_tilt, BLADE_TOP_RIGHT_TILT, progress)
	return _fore_aft_pose(blade_direction, blade_tilt)

func _tier_one_windup_pose(progress: float) -> Quaternion:
	# Move from the exact partial-charge direction straight toward the overhead
	# apex. This deliberately never visits the full-charge rear endpoint.
	var release_tension := _charge_tension_at(_charge_release_start_elapsed)
	var release_direction := POSE_REST_FORWARD_UP.normalized().slerp(
		POSE_CHARGE_BACK.normalized(),
		release_tension
	).normalized()
	var release_tilt := lerpf(BLADE_TOP_RIGHT_TILT, BLADE_TOP_LEFT_TILT, release_tension)
	var blade_direction := release_direction.slerp(Vector3.UP, progress).normalized()
	var blade_tilt := lerpf(release_tilt, BLADE_TOP_LEFT_TILT, progress)
	return _fore_aft_pose(blade_direction, blade_tilt)

func _tier_one_downward_pose(progress: float) -> Quaternion:
	var blade_direction := Vector3.UP.slerp(POSE_STRAIGHT_DOWN.normalized(), progress).normalized()
	var blade_tilt := lerpf(BLADE_TOP_LEFT_TILT, BLADE_TOP_RIGHT_TILT, progress)
	return _fore_aft_pose(blade_direction, blade_tilt)

func _charge_tension_at(elapsed: float) -> float:
	return _smooth(minf(elapsed / CHARGE_ACTIONS[1].charge_threshold, 1.0))

func _charged_strike_pose(progress: float) -> Quaternion:
	# The downward cleave reverses the charging roll, finishing with the blade's
	# upper direction leaning right again without changing the fore/aft path.
	var blade_direction := _charged_strike_direction(progress)
	var blade_tilt := lerpf(BLADE_TOP_LEFT_TILT, BLADE_TOP_RIGHT_TILT, progress)
	return _fore_aft_pose(blade_direction, blade_tilt)

func _charged_strike_direction(progress: float) -> Vector3:
	# The endpoints are nearly opposite. A direct shortest-arc slerp travels
	# underneath toward the hunter's back, so route explicitly over the head.
	var clamped := clampf(progress, 0.0, 1.0)
	if clamped < CHARGE_STRIKE_APEX:
		return POSE_CHARGE_BACK.normalized().slerp(
			Vector3.UP,
			clamped / CHARGE_STRIKE_APEX
		).normalized()
	return Vector3.UP.slerp(
		POSE_STRAIGHT_DOWN.normalized(),
		(clamped - CHARGE_STRIKE_APEX) / (1.0 - CHARGE_STRIKE_APEX)
	).normalized()

func _animate_sword_swing(windup_direction: Vector3, strike_direction: Vector3) -> void:
	if _action_elapsed < _action_data.windup:
		var windup_progress := _action_elapsed / maxf(_action_data.windup, 0.001)
		var blade_direction := POSE_REST_FORWARD_UP.normalized().slerp(
			windup_direction.normalized(),
			_smooth(windup_progress)
		)
		_sword.quaternion = _light_attack_pose(blade_direction)
	elif _action_elapsed < _action_data.windup + _action_data.active:
		var strike_progress := (_action_elapsed - _action_data.windup) / maxf(_action_data.active, 0.001)
		var blade_direction := windup_direction.normalized().slerp(
			strike_direction.normalized(),
			_smooth(strike_progress)
		)
		_sword.quaternion = _light_attack_pose(blade_direction)
	else:
		# Recovery is always rendered in full. Buffered/held input may choose the
		# next action, but it never skips the return-to-rest animation.
		var recovery_progress := (_action_elapsed - _action_data.windup - _action_data.active) / maxf(_action_data.recovery, 0.001)
		var blade_direction := strike_direction.normalized().slerp(
			POSE_REST_FORWARD_UP.normalized(),
			_smooth(recovery_progress)
		)
		_sword.quaternion = _light_attack_pose(blade_direction)

func _blade_direction_pose(direction: Vector3) -> Quaternion:
	# Preserve the original shortest-arc rotation used by attack and charge
	# animations. Rest orientation is handled separately so changing how the
	# sword is carried does not alter the established swing direction.
	return Quaternion(Vector3.UP, direction.normalized())

func _sword_rest_pose() -> Quaternion:
	return _fore_aft_pose(POSE_REST_FORWARD_UP)

func _fore_aft_pose(direction: Vector3, blade_top_tilt: float = BLADE_TOP_RIGHT_TILT) -> Quaternion:
	# Build pitch and roll independently so the tip remains in the centered
	# vertical plane even when the blade deliberately changes its lateral lean.
	var blade_axis := Vector3(0.0, direction.y, direction.z).normalized()
	var base_side := Vector3.RIGHT
	var base_edge := blade_axis.cross(base_side).normalized()
	# Local +X points toward the lower cutting edge, so shift it left to make
	# a positive blade_top_tilt lean the blade's upper direction to the right.
	var edge_axis := (base_edge * cos(blade_top_tilt) - base_side * sin(blade_top_tilt)).normalized()
	var side_axis := edge_axis.cross(blade_axis).normalized()
	return Basis(edge_axis, blade_axis, side_axis).get_rotation_quaternion()

func _light_attack_pose(direction: Vector3) -> Quaternion:
	# Bias the cutting edge down and slightly right for every sampled tip
	# direction. Rebuilding the frame avoids axial roll from quaternion slerp.
	var blade_axis := direction.normalized()
	var edge_hint := Vector3.DOWN * cos(BLADE_TOP_RIGHT_TILT) - Vector3.RIGHT * sin(BLADE_TOP_RIGHT_TILT)
	var edge_axis := (edge_hint - blade_axis * edge_hint.dot(blade_axis)).normalized()
	var side_axis := edge_axis.cross(blade_axis).normalized()
	return Basis(edge_axis, blade_axis, side_axis).get_rotation_quaternion()

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
	_sword.quaternion = _sword_rest_pose()
	var sword_model := Node3D.new()
	sword_model.name = "SwordModel"
	_sword.add_child(sword_model)
	# Local origin is the grip center. Guard and blade extend toward +Y.
	var grip := FieldGeometry.box(sword_model, Vector3(0.12, 0.42, 0.13), Vector3.ZERO, dark)
	grip.name = "Grip"
	# The blade width/cutting edge is local X, while the guard spans local Z.
	var guard := FieldGeometry.box(sword_model, Vector3(0.17, 0.11, 0.58), Vector3(0, 0.25, 0), gold)
	guard.name = "Guard"
	var blade := FieldGeometry.box(sword_model, Vector3(0.30, 1.55, 0.11), Vector3(0, 1.08, 0), steel)
	blade.name = "Blade"
	var cutting_edge := FieldGeometry.box(sword_model, Vector3(0.035, 1.52, 0.13), Vector3(0.165, 1.08, 0), FieldGeometry.material(Color("e7f2ec")))
	cutting_edge.name = "CuttingEdge"
	FieldGeometry.ring(self, 0.60, 0.035, Vector3(0, 0.04, 0), FieldGeometry.material(Color("86d6bc"), 0.4))
	var arrow := CylinderMesh.new()
	arrow.top_radius = 0.0
	arrow.bottom_radius = 0.17
	arrow.height = 0.35
	arrow.radial_segments = 3
	var marker := FieldGeometry.instance(visuals, arrow, Vector3(0, 0.09, -0.9), gold)
	marker.rotation.x = -PI / 2.0
