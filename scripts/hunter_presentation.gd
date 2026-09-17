class_name HunterPresentation
extends Node3D
## Replaceable hunter art boundary. Gameplay talks to states and stable sockets only.

const GREATSWORD_SCENE := preload("res://assets/models/greatsword.glb")

const POSE_REST_FORWARD_UP := Vector3(0.0, 0.35, -0.94)
const POSE_RIGHT_HIGH := Vector3(0.62, 0.58, -0.53)
const POSE_LEFT_LOW := Vector3(-0.62, -0.48, -0.62)
const POSE_STRAIGHT_DOWN := Vector3(0.0, -0.58, -0.82)
const POSE_CHARGE_BACK := Vector3(0.0, 0.42, 0.91)
const CHARGE_STRIKE_APEX := 0.34
const HIT_FEEDBACK_DURATION := 0.24
const BLADE_TOP_RIGHT_TILT := deg_to_rad(10.0)
const BLADE_TOP_LEFT_TILT := deg_to_rad(-10.0)

var visuals: Node3D
var weapon_model: Node3D
var weapon_socket: Node3D
var blade_base: Node3D
var blade_tip: Node3D
var current_state: StringName = &"free"
var current_phase: StringName = &"ready"
var hit_feedback_time: float = 0.0

var _left_leg: Node3D
var _right_leg: Node3D
var _walk_time: float = 0.0
var _feedback_materials: Array[StandardMaterial3D] = []
var _feedback_base_colors: Array[Color] = []
var _hit_recoil_direction := Vector3.ZERO
var _weapon_rest_position := Vector3(0.48, 0.92, -0.26)

func _ready() -> void:
	_build_placeholder()

func forward() -> Vector3:
	return (-visuals.global_basis.z).normalized()

func face(direction: Vector3, turn_speed: float, delta: float) -> void:
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		var target_angle := atan2(-direction.x, -direction.z)
		visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, 1.0 - exp(-turn_speed * delta))

func set_facing_y(angle: float) -> void:
	visuals.rotation.y = angle

func facing_y() -> float:
	return visuals.rotation.y

func animate_walk(delta: float, speed: float, maximum_speed: float) -> void:
	_walk_time += delta * speed * 2.8
	var amount := minf(speed / maximum_speed, 1.0)
	var swing := sin(_walk_time) * 0.38 * amount
	_left_leg.rotation.x = swing
	_right_leg.rotation.x = -swing
	visuals.position.y = absf(sin(_walk_time)) * 0.045 * amount

func animate_action(
	state: StringName,
	phase: StringName,
	elapsed: float,
	charge_elapsed: float,
	charge_release_start: float,
	charge_tier: int,
	action_data: CombatActionData,
	full_charge_time: float,
	charge_cancel_duration: float,
	dodge_duration: float
) -> void:
	current_state = state
	current_phase = phase
	weapon_socket.position = _weapon_rest_position
	weapon_socket.quaternion = _sword_rest_pose()
	if state == &"charging":
		weapon_socket.quaternion = charge_pose_at(charge_elapsed, full_charge_time)
	elif state == &"charge_cancel":
		weapon_socket.quaternion = charge_cancel_pose(_smooth(elapsed / charge_cancel_duration), charge_release_start, full_charge_time)
	elif state == &"light_attack" and action_data:
		_animate_sword_swing(elapsed, action_data, POSE_RIGHT_HIGH, POSE_LEFT_LOW)
	elif state == &"charge_release" and action_data:
		_animate_charge_release(elapsed, action_data, charge_tier, charge_release_start, full_charge_time)
	elif state == &"dodging":
		visuals.rotation.x = sin(clampf(elapsed / dodge_duration, 0.0, 1.0) * PI) * -0.55
		return
	visuals.rotation.x = move_toward(visuals.rotation.x, 0.0, 0.18)

func start_hit_feedback(hunter_position: Vector3, hit_position: Vector3) -> void:
	hit_feedback_time = HIT_FEEDBACK_DURATION
	_hit_recoil_direction = hunter_position - hit_position
	_hit_recoil_direction.y = 0.0
	if _hit_recoil_direction.length_squared() <= 0.0001:
		_hit_recoil_direction = -forward()
	else:
		_hit_recoil_direction = _hit_recoil_direction.normalized()

func update_hit_feedback(delta: float, defeated: bool) -> void:
	if hit_feedback_time <= 0.0:
		return
	hit_feedback_time = maxf(hit_feedback_time - delta, 0.0)
	var elapsed := HIT_FEEDBACK_DURATION - hit_feedback_time
	var pulse := sin(clampf(elapsed / HIT_FEEDBACK_DURATION, 0.0, 1.0) * PI)
	for material in _feedback_materials:
		material.albedo_color = Color("f06f68").lerp(Color("fff0dc"), pulse * 0.35)
	if not defeated:
		visuals.position.x = _hit_recoil_direction.x * 0.16 * pulse
		visuals.position.z = _hit_recoil_direction.z * 0.16 * pulse
		visuals.rotation.z = sin(elapsed * 58.0) * 0.11 * pulse
	if hit_feedback_time <= 0.0:
		_restore_feedback_materials()
		if not defeated:
			visuals.position.x = 0.0
			visuals.position.z = 0.0
			visuals.rotation.z = 0.0

func play_defeated() -> void:
	current_state = &"defeated"
	current_phase = &"down"
	visuals.rotation.z = deg_to_rad(-72.0)

func reset_pose() -> void:
	current_state = &"free"
	current_phase = &"ready"
	hit_feedback_time = 0.0
	_hit_recoil_direction = Vector3.ZERO
	_restore_feedback_materials()
	visuals.rotation = Vector3.ZERO
	visuals.position = Vector3.ZERO
	_left_leg.rotation = Vector3.ZERO
	_right_leg.rotation = Vector3.ZERO
	weapon_socket.position = _weapon_rest_position
	weapon_socket.quaternion = _sword_rest_pose()

func has_active_hit_feedback() -> bool:
	return hit_feedback_time > 0.0

func rest_pose() -> Quaternion:
	return _sword_rest_pose()

func charge_pose_at(elapsed: float, full_charge_time: float) -> Quaternion:
	var tension := _smooth(minf(elapsed / full_charge_time, 1.0))
	var blade_axis := POSE_REST_FORWARD_UP.normalized().slerp(POSE_CHARGE_BACK.normalized(), tension).normalized()
	var blade_tilt := lerpf(BLADE_TOP_RIGHT_TILT, BLADE_TOP_LEFT_TILT, tension)
	return fore_aft_pose(blade_axis, blade_tilt)

func charge_cancel_pose(progress: float, release_elapsed: float, full_charge_time: float) -> Quaternion:
	var release_tension := _smooth(minf(release_elapsed / full_charge_time, 1.0))
	var release_direction := POSE_REST_FORWARD_UP.normalized().slerp(POSE_CHARGE_BACK.normalized(), release_tension).normalized()
	var release_tilt := lerpf(BLADE_TOP_RIGHT_TILT, BLADE_TOP_LEFT_TILT, release_tension)
	var blade_direction := release_direction.slerp(POSE_REST_FORWARD_UP.normalized(), progress).normalized()
	return fore_aft_pose(blade_direction, lerpf(release_tilt, BLADE_TOP_RIGHT_TILT, progress))

func charged_strike_pose(progress: float) -> Quaternion:
	var blade_direction := charged_strike_direction(progress)
	var blade_tilt := lerpf(BLADE_TOP_LEFT_TILT, BLADE_TOP_RIGHT_TILT, progress)
	return fore_aft_pose(blade_direction, blade_tilt)

func charged_strike_direction(progress: float) -> Vector3:
	var clamped := clampf(progress, 0.0, 1.0)
	if clamped < CHARGE_STRIKE_APEX:
		return POSE_CHARGE_BACK.normalized().slerp(Vector3.UP, clamped / CHARGE_STRIKE_APEX).normalized()
	return Vector3.UP.slerp(POSE_STRAIGHT_DOWN.normalized(), (clamped - CHARGE_STRIKE_APEX) / (1.0 - CHARGE_STRIKE_APEX)).normalized()

func fore_aft_pose(direction: Vector3, blade_top_tilt: float = BLADE_TOP_RIGHT_TILT) -> Quaternion:
	var blade_axis := Vector3(0.0, direction.y, direction.z).normalized()
	var base_side := Vector3.RIGHT
	var base_edge := blade_axis.cross(base_side).normalized()
	var edge_axis := (base_edge * cos(blade_top_tilt) - base_side * sin(blade_top_tilt)).normalized()
	var side_axis := edge_axis.cross(blade_axis).normalized()
	return Basis(edge_axis, blade_axis, side_axis).get_rotation_quaternion()

func _animate_charge_release(elapsed: float, action_data: CombatActionData, tier: int, release_elapsed: float, full_charge_time: float) -> void:
	if elapsed < action_data.windup:
		var progress := _smooth(elapsed / maxf(action_data.windup, 0.001))
		if tier == 1:
			var tension := _smooth(minf(release_elapsed / full_charge_time, 1.0))
			var start := POSE_REST_FORWARD_UP.normalized().slerp(POSE_CHARGE_BACK.normalized(), tension).normalized()
			var tilt := lerpf(BLADE_TOP_RIGHT_TILT, BLADE_TOP_LEFT_TILT, tension)
			weapon_socket.quaternion = fore_aft_pose(start.slerp(Vector3.UP, progress).normalized(), lerpf(tilt, BLADE_TOP_LEFT_TILT, progress))
		else:
			weapon_socket.quaternion = charge_pose_at(full_charge_time, full_charge_time)
	elif elapsed < action_data.windup + action_data.active:
		var progress := _smooth((elapsed - action_data.windup) / maxf(action_data.active, 0.001))
		if tier == 1:
			weapon_socket.quaternion = fore_aft_pose(Vector3.UP.slerp(POSE_STRAIGHT_DOWN.normalized(), progress).normalized(), lerpf(BLADE_TOP_LEFT_TILT, BLADE_TOP_RIGHT_TILT, progress))
		else:
			weapon_socket.quaternion = charged_strike_pose(progress)
	else:
		var progress := _smooth((elapsed - action_data.windup - action_data.active) / maxf(action_data.recovery, 0.001))
		weapon_socket.quaternion = fore_aft_pose(POSE_STRAIGHT_DOWN.normalized().slerp(POSE_REST_FORWARD_UP.normalized(), progress))

func _animate_sword_swing(elapsed: float, action_data: CombatActionData, windup_direction: Vector3, strike_direction: Vector3) -> void:
	var blade_direction: Vector3
	if elapsed < action_data.windup:
		blade_direction = POSE_REST_FORWARD_UP.normalized().slerp(windup_direction.normalized(), _smooth(elapsed / maxf(action_data.windup, 0.001)))
	elif elapsed < action_data.windup + action_data.active:
		blade_direction = windup_direction.normalized().slerp(strike_direction.normalized(), _smooth((elapsed - action_data.windup) / maxf(action_data.active, 0.001)))
	else:
		blade_direction = strike_direction.normalized().slerp(POSE_REST_FORWARD_UP.normalized(), _smooth((elapsed - action_data.windup - action_data.active) / maxf(action_data.recovery, 0.001)))
	weapon_socket.quaternion = _light_attack_pose(blade_direction)

func _sword_rest_pose() -> Quaternion:
	return fore_aft_pose(POSE_REST_FORWARD_UP)

func _light_attack_pose(direction: Vector3) -> Quaternion:
	var blade_axis := direction.normalized()
	var edge_hint := Vector3.DOWN * cos(BLADE_TOP_RIGHT_TILT) - Vector3.RIGHT * sin(BLADE_TOP_RIGHT_TILT)
	var edge_axis := (edge_hint - blade_axis * edge_hint.dot(blade_axis)).normalized()
	var side_axis := edge_axis.cross(blade_axis).normalized()
	return Basis(edge_axis, blade_axis, side_axis).get_rotation_quaternion()

func _restore_feedback_materials() -> void:
	for index in range(mini(_feedback_materials.size(), _feedback_base_colors.size())):
		_feedback_materials[index].albedo_color = _feedback_base_colors[index]

func _build_placeholder() -> void:
	if visuals:
		return
	visuals = Node3D.new()
	visuals.name = "Visuals"
	add_child(visuals)
	var cloth := FieldGeometry.material(Color("78b9ab"))
	var dark := FieldGeometry.material(Color("253739"))
	var leather := FieldGeometry.material(Color("665645"))
	var steel := FieldGeometry.material(Color("bdd0c8"))
	var gold := FieldGeometry.material(Color("deb778"))
	_feedback_materials = [cloth, dark, leather, steel]
	for material in _feedback_materials:
		_feedback_base_colors.append(material.albedo_color)
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
	weapon_model = GREATSWORD_SCENE.instantiate() as Node3D
	weapon_model.name = "Greatsword"
	visuals.add_child(weapon_model)
	weapon_socket = _find_named_node(weapon_model, "WeaponSocket") as Node3D
	blade_base = _find_named_node(weapon_model, "BladeBase") as Node3D
	blade_tip = _find_named_node(weapon_model, "BladeTip") as Node3D
	assert(weapon_socket != null and blade_base != null and blade_tip != null, "Greatsword asset must expose WeaponSocket, BladeBase, and BladeTip")
	weapon_socket.position = _weapon_rest_position
	weapon_socket.quaternion = _sword_rest_pose()
	FieldGeometry.ring(self, 0.60, 0.035, Vector3(0, 0.04, 0), FieldGeometry.material(Color("86d6bc"), 0.4))
	var arrow := CylinderMesh.new()
	arrow.top_radius = 0.0
	arrow.bottom_radius = 0.17
	arrow.height = 0.35
	arrow.radial_segments = 3
	var facing_marker := FieldGeometry.instance(visuals, arrow, Vector3(0, 0.09, -0.9), gold)
	facing_marker.rotation.x = -PI / 2.0

func _find_named_node(node: Node, target_name: StringName) -> Node:
	if node.name == target_name:
		return node
	for child: Node in node.get_children():
		var found := _find_named_node(child, target_name)
		if found:
			return found
	return null

func _smooth(value: float) -> float:
	var clamped := clampf(value, 0.0, 1.0)
	return clamped * clamped * (3.0 - 2.0 * clamped)
