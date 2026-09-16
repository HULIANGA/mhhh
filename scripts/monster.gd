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
const SWEEP_ATTACK: MonsterAttackData = preload("res://data/monster_sweep.tres")
const POUNCE_ATTACK: MonsterAttackData = preload("res://data/monster_pounce.tres")

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

var health: int = 180
var state: StringName = STATE_IDLE
var is_dead: bool = false
var distance_to_target: float = INF
var attack_phase: StringName = &"ready"
var attack_token: int = 0
var _target: Hunter
var _spawn_transform: Transform3D
var _resolved_attacks: Dictionary = {}
var _flash_time: float = 0.0
var _walk_time: float = 0.0
var _attack_data: MonsterAttackData
var _attack_elapsed: float = 0.0
var _locked_attack_direction := Vector3.FORWARD
var _attack_resolved: bool = false
var _body_material: StandardMaterial3D
var _visuals: Node3D
var _health_label: Label3D
var _left_foreleg: Node3D
var _right_foreleg: Node3D
var _left_hindleg: Node3D
var _right_hindleg: Node3D
var _left_horn: MeshInstance3D
var _right_horn: MeshInstance3D

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
	if attacks_enabled and distance_to_target >= POUNCE_ATTACK.minimum_range and distance_to_target <= POUNCE_ATTACK.maximum_range:
		_stop(STATE_READY, delta)
		_start_attack(POUNCE_ATTACK)
		return
	if distance_to_target <= attack_range:
		_stop(STATE_READY, delta)
		if attacks_enabled:
			_start_attack(SWEEP_ATTACK)
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
	_attack_data = null
	_attack_elapsed = 0.0
	attack_phase = &"ready"
	attack_token = 0
	_attack_resolved = false
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
	_attack_data = null
	attack_phase = &"ready"
	_set_state(STATE_DEAD)
	if _visuals:
		_visuals.rotation.z = deg_to_rad(78.0)
	_update_label()
	defeated.emit()

func _start_attack(data: MonsterAttackData) -> void:
	_attack_data = data
	_attack_elapsed = 0.0
	_attack_resolved = false
	attack_token += 1
	velocity.x = 0.0
	velocity.z = 0.0
	_set_state(STATE_ATTACKING)
	_set_attack_phase(PHASE_WINDUP, true)

func _advance_attack(delta: float) -> void:
	if not _attack_data:
		_finish_attack()
		return
	_attack_elapsed += delta
	var should_resolve_hit := false
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
		should_resolve_hit = true
	else:
		if attack_phase != PHASE_RECOVERY and _attack_data.attack_id == &"pounce":
			velocity.x = 0.0
			velocity.z = 0.0
		_set_attack_phase(PHASE_RECOVERY)
	if attack_phase == PHASE_ACTIVE and _attack_data.attack_id == &"pounce":
		velocity.x = _locked_attack_direction.x * _attack_data.movement_speed
		velocity.z = _locked_attack_direction.z * _attack_data.movement_speed
	else:
		var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, acceleration * delta)
		velocity.x = horizontal.x
		velocity.z = horizontal.z
	_apply_gravity(delta)
	move_and_slide()
	_clamp_to_arena()
	_animate_attack()
	var active_elapsed := _attack_elapsed - _attack_data.windup
	if should_resolve_hit and active_elapsed >= _attack_data.hit_delay:
		if _attack_data.attack_id == &"pounce":
			_resolve_pounce_hit(movement_start, global_position)
		else:
			_resolve_sweep_hit()
	if _attack_elapsed >= _attack_data.duration():
		_finish_attack()

func _finish_attack() -> void:
	_attack_data = null
	_attack_elapsed = 0.0
	_attack_resolved = false
	velocity.x = 0.0
	velocity.z = 0.0
	attack_phase = &"ready"
	if _visuals and not is_dead:
		_visuals.rotation = Vector3.ZERO
	_set_state(STATE_READY)
	_update_label()

func _set_attack_phase(next_phase: StringName, force_emit: bool = false) -> void:
	if attack_phase == next_phase and not force_emit:
		return
	attack_phase = next_phase
	attack_phase_changed.emit(_attack_data.display_name, attack_phase)
	_update_label()

func _resolve_sweep_hit() -> void:
	if _attack_resolved:
		return
	# Match the active hit volume to the rendered horns. As with the hunter's
	# blade, overlapping probes cover each segment from its root to its tip and
	# move with the animated model on every active physics tick.
	var sphere := SphereShape3D.new()
	sphere.radius = _attack_data.hit_radius
	for horn: MeshInstance3D in [_left_horn, _right_horn]:
		var horn_root := horn.to_global(Vector3(0.0, 0.0, 0.32))
		var horn_tip := horn.to_global(Vector3(0.0, 0.0, -0.42))
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

func _resolve_pounce_hit(from_position: Vector3, to_position: Vector3) -> void:
	if _attack_resolved:
		return
	# Sweep a physical sphere along both the body center and the leading head
	# path so a fast pounce cannot tunnel through the hunter between ticks.
	var front_offset := _locked_attack_direction * 1.05 + Vector3.UP * 0.95
	var center_offset := Vector3.UP * 0.85
	for offset: Vector3 in [front_offset, center_offset]:
		var path_start := from_position + offset
		var path_end := to_position + offset
		for fraction: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
			if _probe_hunter(path_start.lerp(path_end, fraction), _attack_data.hit_radius):
				return

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
	if _body_material:
		var phase_color := Color("75635a")
		if state == STATE_ATTACKING:
			if attack_phase == PHASE_WINDUP:
				phase_color = Color("d19a58")
			elif attack_phase == PHASE_ACTIVE:
				phase_color = Color("d9574f")
			else:
				phase_color = Color("617b78")
		_body_material.albedo_color = Color("ef8e74") if _flash_time > 0.0 else phase_color

func _animate_attack() -> void:
	if not _visuals or not _attack_data:
		return
	if _attack_data.attack_id == &"pounce":
		_animate_pounce()
		return
	if attack_phase == PHASE_WINDUP:
		var progress := clampf(_attack_elapsed / _attack_data.windup, 0.0, 1.0)
		_visuals.rotation.y = lerpf(0.0, -0.48, _smooth(progress))
		_visuals.rotation.x = lerpf(0.0, 0.16, _smooth(progress))
	elif attack_phase == PHASE_ACTIVE:
		var progress := clampf((_attack_elapsed - _attack_data.windup) / _attack_data.active, 0.0, 1.0)
		_visuals.rotation.y = lerpf(-0.48, 0.78, _smooth(progress))
		_visuals.rotation.x = lerpf(0.16, -0.1, _smooth(progress))
	else:
		var progress := clampf((_attack_elapsed - _attack_data.windup - _attack_data.active) / _attack_data.recovery, 0.0, 1.0)
		_visuals.rotation.y = lerpf(0.78, 0.0, _smooth(progress))
		_visuals.rotation.x = lerpf(-0.1, 0.0, _smooth(progress))

func _animate_pounce() -> void:
	if attack_phase == PHASE_WINDUP:
		var progress := clampf(_attack_elapsed / _attack_data.windup, 0.0, 1.0)
		_visuals.rotation.x = lerpf(0.0, 0.34, _smooth(progress))
		_visuals.position.y = lerpf(0.0, -0.16, _smooth(progress))
	elif attack_phase == PHASE_ACTIVE:
		var progress := clampf((_attack_elapsed - _attack_data.windup) / _attack_data.active, 0.0, 1.0)
		_visuals.rotation.x = lerpf(0.34, -0.24, _smooth(progress))
		_visuals.position.y = lerpf(-0.16, 0.0, _smooth(progress)) + sin(progress * PI) * 0.34
	else:
		var progress := clampf((_attack_elapsed - _attack_data.windup - _attack_data.active) / _attack_data.recovery, 0.0, 1.0)
		_visuals.rotation.x = lerpf(-0.24, 0.0, _smooth(progress))
		_visuals.position.y = lerpf(0.0, 0.0, progress)

func _smooth(value: float) -> float:
	var clamped := clampf(value, 0.0, 1.0)
	return clamped * clamped * (3.0 - 2.0 * clamped)

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
	if health <= 0:
		_health_label.text = "FIELD BEAST\nDOWN — R TO RESET"
	elif state == STATE_ATTACKING and _attack_data:
		_health_label.text = "FIELD BEAST  /  %d / %d\n%s — %s" % [health, max_health, _attack_data.display_name.to_upper(), String(attack_phase).to_upper()]
	else:
		_health_label.text = "FIELD BEAST\n%d / %d" % [health, max_health]

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
	_left_horn = FieldGeometry.box(_visuals, Vector3(0.22, 0.22, 0.72), Vector3(-0.42, 1.38, -1.88), horn)
	_right_horn = FieldGeometry.box(_visuals, Vector3(0.22, 0.22, 0.72), Vector3(0.42, 1.38, -1.88), horn)
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
