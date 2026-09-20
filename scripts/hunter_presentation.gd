class_name HunterPresentation
extends Node3D
## Replaceable hunter art boundary. Gameplay talks to states and stable sockets only.

const GREATSWORD_SCENE := preload("res://assets/models/greatsword.glb")
const HUNTER_SCENE := preload("res://assets/models/hunter.glb")

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
var hunter_model: Node3D
var weapon_model: Node3D
var weapon_attachment: BoneAttachment3D
var weapon_socket: Node3D
var blade_base: Node3D
var blade_tip: Node3D
var current_animation: StringName = &"idle"
var current_state: StringName = &"free"
var current_phase: StringName = &"ready"
var hit_feedback_time: float = 0.0

var _skeleton: Skeleton3D
var _animation_player: AnimationPlayer
var _feedback_materials: Array[StandardMaterial3D] = []
var _feedback_base_colors: Array[Color] = []
var _hit_recoil_direction := Vector3.ZERO
var _weapon_rest_position := Vector3.ZERO

func _ready() -> void:
	_build_model()

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
	var _unused_delta := delta
	var amount := minf(speed / maximum_speed, 1.0)
	if current_state != &"free" or hit_feedback_time > 0.0:
		return
	if amount > 0.05:
		_play_loop(&"run", lerpf(0.75, 1.35, amount))
	else:
		_play_loop(&"idle", 1.0)

func animate_action(
	state: StringName,
	phase: StringName,
	elapsed: float,
	charge_elapsed: float,
	charge_release_start: float,
	charge_tier: int,
	action_data: CombatActionData,
	charge_ready_time: float,
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
		pass
	if hit_feedback_time <= 0.0:
		_animate_model_action(state, elapsed, charge_elapsed, charge_tier, action_data, charge_ready_time, full_charge_time, charge_cancel_duration, dodge_duration)

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
	if not defeated:
		_sample_animation(&"hit", elapsed / HIT_FEEDBACK_DURATION)
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
	_sample_animation(&"defeated", 1.0)

func reset_pose() -> void:
	current_state = &"free"
	current_phase = &"ready"
	hit_feedback_time = 0.0
	_hit_recoil_direction = Vector3.ZERO
	_restore_feedback_materials()
	visuals.rotation = Vector3.ZERO
	visuals.position = Vector3.ZERO
	weapon_socket.position = _weapon_rest_position
	weapon_socket.quaternion = _sword_rest_pose()
	_sample_animation(&"idle", 0.0)

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

func _build_model() -> void:
	if visuals:
		return
	visuals = Node3D.new()
	visuals.name = "Visuals"
	add_child(visuals)
	hunter_model = HUNTER_SCENE.instantiate() as Node3D
	hunter_model.name = "HunterModel"
	visuals.add_child(hunter_model)
	_skeleton = _find_type(hunter_model, Skeleton3D) as Skeleton3D
	_animation_player = _find_type(hunter_model, AnimationPlayer) as AnimationPlayer
	assert(_skeleton != null and _animation_player != null, "Hunter asset must expose a Skeleton3D and AnimationPlayer")
	assert(_skeleton.find_bone("WeaponSocket") >= 0, "Hunter skeleton must expose its right-hand WeaponSocket bone")
	_collect_feedback_materials(hunter_model)
	var gold := FieldGeometry.material(Color("deb778"))
	weapon_attachment = BoneAttachment3D.new()
	weapon_attachment.name = "RightHandWeaponAttachment"
	weapon_attachment.bone_name = "WeaponSocket"
	_skeleton.add_child(weapon_attachment)
	weapon_model = GREATSWORD_SCENE.instantiate() as Node3D
	weapon_model.name = "Greatsword"
	weapon_attachment.add_child(weapon_model)
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
	_sample_animation(&"idle", 0.0)

func _animate_model_action(
	state: StringName,
	elapsed: float,
	charge_elapsed: float,
	charge_tier: int,
	action_data: CombatActionData,
	charge_ready_time: float,
	full_charge_time: float,
	charge_cancel_duration: float,
	dodge_duration: float
) -> void:
	if state == &"free":
		return
	if state == &"charging":
		if charge_tier >= 1:
			_play_loop(&"charge_hold", 1.0)
		else:
			_sample_animation(&"charge_enter", charge_elapsed / maxf(charge_ready_time, 0.001))
	elif state == &"charge_cancel":
		_sample_animation(&"charge_cancel", elapsed / maxf(charge_cancel_duration, 0.001))
	elif state == &"light_attack" and action_data:
		_sample_animation(&"light_attack", elapsed / maxf(action_data.duration(), 0.001))
	elif state == &"charge_release" and action_data:
		_sample_animation(&"charge_release_2" if charge_tier >= 2 else &"charge_release_1", elapsed / maxf(action_data.duration(), 0.001))
	elif state == &"dodging":
		_sample_animation(&"dodge", elapsed / maxf(dodge_duration, 0.001))

func _play_loop(animation_name: StringName, speed: float) -> void:
	if not _animation_player or not _animation_player.has_animation(animation_name):
		return
	if current_animation != animation_name or not _animation_player.is_playing():
		_animation_player.play(animation_name)
	current_animation = animation_name
	_animation_player.speed_scale = speed

func _sample_animation(animation_name: StringName, progress: float) -> void:
	if not _animation_player or not _animation_player.has_animation(animation_name):
		return
	var animation := _animation_player.get_animation(animation_name)
	_animation_player.speed_scale = 0.0
	_animation_player.play(animation_name)
	_animation_player.seek(animation.length * clampf(progress, 0.0, 1.0), true)
	current_animation = animation_name

func _collect_feedback_materials(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		for surface_index in range(node.mesh.get_surface_count()):
			var source: Material = node.get_active_material(surface_index)
			if source is StandardMaterial3D:
				var instance_material := source.duplicate() as StandardMaterial3D
				node.set_surface_override_material(surface_index, instance_material)
				_feedback_materials.append(instance_material)
				_feedback_base_colors.append(instance_material.albedo_color)
	for child: Node in node.get_children():
		_collect_feedback_materials(child)

func _find_type(node: Node, type: Variant) -> Node:
	if is_instance_of(node, type):
		return node
	for child: Node in node.get_children():
		var found := _find_type(child, type)
		if found:
			return found
	return null

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
