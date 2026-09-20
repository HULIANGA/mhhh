class_name FieldMonster
extends CharacterBody3D

signal health_changed(current: int, maximum: int)
signal hit_received(damage: int, world_position: Vector3)
signal defeated
signal state_changed(state: StringName)
signal attack_phase_changed(attack_name: String, phase: StringName)

const STATE_IDLE: StringName = &"idle"
const STATE_CHASING: StringName = &"chasing"
const STATE_READY: StringName = &"ready"
const STATE_ATTACKING: StringName = &"attacking"
const STATE_DEAD: StringName = &"dead"
const PHASE_WINDUP: StringName = &"windup"
const PHASE_ACTIVE: StringName = &"active"
const PHASE_RECOVERY: StringName = &"recovery"
const PHASE_STUNNED: StringName = &"stunned"
const CHARGE_CRASH_RECOVERY: float = 2.2
const SWEEP_ATTACK: MonsterAttackData = preload("res://data/monster_sweep.tres")
const POUNCE_ATTACK: MonsterAttackData = preload("res://data/monster_pounce.tres")
const CHARGE_ATTACK: MonsterAttackData = preload("res://data/monster_charge.tres")

@export_range(1, 999) var max_health: int = 180
@export_range(0.1, 12.0) var move_speed: float = 3.6
@export_range(0.1, 40.0) var acceleration: float = 18.0
@export_range(0.1, 40.0) var turn_speed: float = 10.0
@export_range(1.0, 40.0) var detection_range: float = 24.0
@export_range(1.0, 6.0) var attack_range: float = 2.25
@export var target_path: NodePath = NodePath("../Player")
@export var arena_min := Vector2(-16.65, -13.65)
@export var arena_max := Vector2(16.65, 13.65)
@export var attacks_enabled: bool = true
@export var ai_enabled: bool = true
@export var decision_seed: int = 316031
@export_range(1, 4) var maximum_consecutive_attack: int = 2

var health: int = 180
var state: StringName = STATE_IDLE
var is_dead: bool = false
var distance_to_target: float = INF
var attack_phase: StringName = &"ready"
var attack_token: int = 0
var attack_cooldown_left: float = 0.0
var last_attack_id: StringName = &""
var consecutive_attack_count: int = 0
var _target: Hunter
var _spawn_transform: Transform3D
var _resolved_attacks: Dictionary = {}
var _flash_time: float = 0.0
var _attack_data: MonsterAttackData
var _attack_elapsed: float = 0.0
var _locked_attack_direction := Vector3.FORWARD
var _attack_resolved: bool = false
var _charge_crashed: bool = false
var _decision_rng := RandomNumberGenerator.new()
var _presentation: MonsterPresentation
var _left_horn_base: Node3D
var _left_horn_tip: Node3D
var _right_horn_base: Node3D
var _right_horn_tip: Node3D

func _ready() -> void:
	name = "FieldMonster"
	add_to_group("damageable")
	_spawn_transform = global_transform
	_target = get_node_or_null(target_path) as Hunter
	_presentation = $Presentation as MonsterPresentation
	_presentation.setup(attack_range)
	_left_horn_base = _presentation.left_horn_base
	_left_horn_tip = _presentation.left_horn_tip
	_right_horn_base = _presentation.right_horn_base
	_right_horn_tip = _presentation.right_horn_tip
	reset_monster()

func _physics_process(delta: float) -> void:
	_update_feedback(delta)
	if is_dead:
		velocity = Vector3.ZERO
		return
	if not ai_enabled:
		_stop(STATE_IDLE, delta)
		return
	attack_cooldown_left = maxf(attack_cooldown_left - delta, 0.0)
	if state == STATE_ATTACKING:
		_advance_attack(delta)
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
	if attacks_enabled and attack_cooldown_left <= 0.0:
		var selected_attack := _select_attack(distance_to_target)
		if selected_attack:
			_stop(STATE_READY, delta)
			_start_attack(selected_attack)
			return
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
	_attack_data = null
	_attack_elapsed = 0.0
	attack_phase = &"ready"
	attack_token = 0
	attack_cooldown_left = 0.0
	last_attack_id = &""
	consecutive_attack_count = 0
	_decision_rng.seed = decision_seed
	_attack_resolved = false
	_charge_crashed = false
	_presentation.reset_pose()
	_set_state(STATE_IDLE, true)
	health_changed.emit(health, max_health)

func set_target(target: Hunter) -> void:
	_target = target

func set_ai_enabled(enabled: bool) -> void:
	ai_enabled = enabled
	if enabled or is_dead:
		return
	velocity = Vector3.ZERO
	_attack_data = null
	_attack_elapsed = 0.0
	_attack_resolved = false
	_charge_crashed = false
	attack_phase = &"ready"
	_presentation.hide_attack_telegraphs()
	_presentation.reset_pose()
	_set_state(STATE_IDLE)

func _die() -> void:
	if is_dead:
		return
	is_dead = true
	velocity = Vector3.ZERO
	_attack_data = null
	attack_phase = &"ready"
	_set_state(STATE_DEAD)
	_presentation.play_defeated()
	_presentation.hide_attack_telegraphs()
	defeated.emit()

func _start_attack(data: MonsterAttackData) -> void:
	if last_attack_id == data.attack_id:
		consecutive_attack_count += 1
	else:
		last_attack_id = data.attack_id
		consecutive_attack_count = 1
	_attack_data = data
	_attack_elapsed = 0.0
	_attack_resolved = false
	_charge_crashed = false
	attack_token += 1
	velocity.x = 0.0
	velocity.z = 0.0
	_set_state(STATE_ATTACKING)
	_set_attack_phase(PHASE_WINDUP, true)
	_show_attack_telegraph()

func _advance_attack(delta: float) -> void:
	if not _attack_data:
		_finish_attack()
		return
	_attack_elapsed += delta
	var movement_start := global_position
	if _attack_elapsed < _attack_data.windup:
		if is_instance_valid(_target):
			var aim := _target.global_position - global_position
			aim.y = 0.0
			_face(aim, delta)
		_set_attack_phase(PHASE_WINDUP)
	elif _attack_elapsed < _attack_data.windup + _attack_data.active:
		if attack_phase != PHASE_ACTIVE:
			_locked_attack_direction = _forward()
			_set_attack_phase(PHASE_ACTIVE)
	elif not _charge_crashed:
		if attack_phase != PHASE_RECOVERY:
			if _is_motion_attack():
				velocity.x = 0.0
				velocity.z = 0.0
			_set_attack_phase(PHASE_RECOVERY)
	if attack_phase == PHASE_ACTIVE and _is_motion_attack():
		velocity.x = _locked_attack_direction.x * _attack_data.movement_speed
		velocity.z = _locked_attack_direction.z * _attack_data.movement_speed
	else:
		var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, acceleration * delta)
		velocity.x = horizontal.x
		velocity.z = horizontal.z
	_apply_gravity(delta)
	move_and_slide()
	_clamp_to_arena()
	var active_elapsed := _attack_elapsed - _attack_data.windup
	if attack_phase == PHASE_ACTIVE and active_elapsed >= _attack_data.hit_delay:
		if _is_motion_attack():
			_resolve_motion_hit(movement_start, global_position)
		else:
			_resolve_sweep_hit()
	if attack_phase == PHASE_ACTIVE and _attack_data.attack_id == &"charge":
		_handle_charge_collisions()
	_animate_attack()
	if _attack_elapsed >= _current_attack_duration():
		_finish_attack()

func _finish_attack() -> void:
	if _attack_data:
		var repeat_multiplier := 1.65 if consecutive_attack_count >= maximum_consecutive_attack else 1.0
		attack_cooldown_left = maxf(attack_cooldown_left, _attack_data.cooldown * repeat_multiplier)
	_attack_data = null
	_attack_elapsed = 0.0
	_attack_resolved = false
	_charge_crashed = false
	velocity.x = 0.0
	velocity.z = 0.0
	attack_phase = &"ready"
	if not is_dead:
		_presentation.reset_pose()
	_set_state(STATE_READY)

func _select_attack(distance: float) -> MonsterAttackData:
	var candidates := _attack_candidates(distance)
	if candidates.is_empty():
		return null
	if candidates.size() == 1:
		return candidates[0]
	if consecutive_attack_count >= maximum_consecutive_attack:
		var alternatives: Array[MonsterAttackData] = []
		for data in candidates:
			if data.attack_id != last_attack_id:
				alternatives.append(data)
		if not alternatives.is_empty():
			candidates = alternatives
	var total_weight := 0.0
	for data in candidates:
		total_weight += _selection_weight(data, distance)
	var roll := _decision_rng.randf() * total_weight
	for data in candidates:
		roll -= _selection_weight(data, distance)
		if roll <= 0.0:
			return data
	return candidates.back()

func _attack_candidates(distance: float) -> Array[MonsterAttackData]:
	var candidates: Array[MonsterAttackData] = []
	for data: MonsterAttackData in [SWEEP_ATTACK, POUNCE_ATTACK, CHARGE_ATTACK]:
		var in_primary_range := distance >= data.minimum_range and distance <= data.maximum_range
		var close_fallback := distance <= attack_range and data.close_weight_multiplier > 0.0
		if in_primary_range or close_fallback:
			candidates.append(data)
	return candidates

func _selection_weight(data: MonsterAttackData, distance: float) -> float:
	var weight := data.selection_weight
	if distance < data.minimum_range:
		weight *= data.close_weight_multiplier
	# The pounce/charge transition is distance-shaped rather than a flat coin
	# flip: pounce dominates its near edge, charge dominates its far edge.
	if distance >= CHARGE_ATTACK.minimum_range and distance <= POUNCE_ATTACK.maximum_range:
		var transition := inverse_lerp(CHARGE_ATTACK.minimum_range, POUNCE_ATTACK.maximum_range, distance)
		if data.attack_id == &"pounce":
			weight *= lerpf(1.45, 0.16, transition)
		elif data.attack_id == &"charge":
			weight *= lerpf(0.22, 1.75, transition)
	if data.attack_id == last_attack_id:
		weight *= 0.32
	return weight

func set_decision_seed(value: int) -> void:
	decision_seed = value
	_decision_rng.seed = decision_seed

func _set_attack_phase(next_phase: StringName, force_emit: bool = false) -> void:
	if attack_phase == next_phase and not force_emit:
		return
	attack_phase = next_phase
	if attack_phase != PHASE_WINDUP:
		_presentation.hide_attack_telegraphs()
	attack_phase_changed.emit(_attack_data.display_name, attack_phase)

func debug_attack_id() -> StringName:
	return _attack_data.attack_id if _attack_data else &"none"

func debug_animation_name() -> StringName:
	return _presentation.current_animation if _presentation else &"none"

func _resolve_sweep_hit() -> void:
	if _attack_resolved:
		return
	# Match the active hit volume to the rendered horns. As with the hunter's
	# blade, overlapping probes cover each segment from its root to its tip and
	# move with the animated model on every active physics tick.
	var sphere := SphereShape3D.new()
	sphere.radius = _attack_data.hit_radius
	for segment in [[_left_horn_base, _left_horn_tip], [_right_horn_base, _right_horn_tip]]:
		var horn_root: Vector3 = segment[0].global_position
		var horn_tip: Vector3 = segment[1].global_position
		for fraction: float in [0.18, 0.42, 0.68, 0.9, 1.0]:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = sphere
			query.transform = Transform3D(Basis.IDENTITY, horn_root.lerp(horn_tip, fraction))
			query.collision_mask = 2
			query.collide_with_areas = true
			query.collide_with_bodies = true
			query.exclude = [get_rid()]
			for result: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 8):
				var target: Object = result.get("collider")
				if not target or not target.has_method("receive_hit"):
					continue
				# Resolve the active attack even when the hunter is invulnerable. The
				# same sweep must not become a delayed hit after a successful dodge.
				_attack_resolved = true
				var hit_position: Vector3 = query.transform.origin
				target.receive_hit(attack_token, _attack_data.damage, hit_position)
				return

func _resolve_motion_hit(from_position: Vector3, to_position: Vector3) -> void:
	if _attack_resolved:
		return
	# Model-owned sockets keep moving hit paths aligned when the art is rescaled.
	var travelled := to_position - from_position
	for socket: Marker3D in _presentation.motion_probe_sockets():
		var path_end := socket.global_position
		var path_start := path_end - travelled
		for fraction: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
			if _probe_hunter(path_start.lerp(path_end, fraction), _attack_data.hit_radius):
				return

func _is_motion_attack() -> bool:
	return _attack_data and _attack_data.attack_id in [&"pounce", &"charge"]

func _handle_charge_collisions() -> void:
	for collision_index in get_slide_collision_count():
		var collision := get_slide_collision(collision_index)
		if absf(collision.get_normal().y) >= 0.7:
			continue
		var collider: Object = collision.get_collider()
		if collider and collider.has_method("break_from_charge"):
			collider.break_from_charge(collision.get_position())
			continue
		_crash_charge()
		return

func _crash_charge() -> void:
	_charge_crashed = true
	velocity.x = 0.0
	velocity.z = 0.0
	_attack_elapsed = _attack_data.windup + _attack_data.active
	_set_attack_phase(PHASE_STUNNED)

func _current_attack_duration() -> float:
	if _charge_crashed:
		return _attack_data.windup + _attack_data.active + CHARGE_CRASH_RECOVERY
	return _attack_data.duration()

func _probe_hunter(at: Vector3, radius: float) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, at)
	query.collision_mask = 2
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	for result: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 8):
		var target: Object = result.get("collider")
		if not target or not target.has_method("receive_hit"):
			continue
		_attack_resolved = true
		target.receive_hit(attack_token, _attack_data.damage, at)
		return true
	return false

func _forward() -> Vector3:
	return (-global_basis.z).normalized()

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
	_presentation.update_feedback(state, attack_phase, _flash_time)

func _animate_attack() -> void:
	_presentation.animate_attack(_attack_data, attack_phase, _attack_elapsed, CHARGE_CRASH_RECOVERY)

func _show_attack_telegraph() -> void:
	_presentation.show_attack_telegraph(_attack_data)

func _animate_walk(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	_presentation.animate_walk(delta, speed, move_speed, is_dead)
