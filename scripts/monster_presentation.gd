class_name MonsterPresentation
extends Node3D
## Replaceable monster art boundary and the sole owner of visual state.

const MONSTER_SCENE := preload("res://assets/models/monster.glb")

@export_range(0.5, 3.0, 0.05) var model_scale: float = 1.25

var visuals: Node3D
var monster_model: Node3D
var left_horn_base: Marker3D
var left_horn_tip: Marker3D
var right_horn_base: Marker3D
var right_horn_tip: Marker3D
var body_center: Marker3D
var head_front: Marker3D
var current_animation: StringName = &"idle"
var current_state: StringName = &"idle"
var current_phase: StringName = &"ready"

var _skeleton: Skeleton3D
var _animation_player: AnimationPlayer
var _feedback_materials: Array[StandardMaterial3D] = []
var _feedback_base_colors: Array[Color] = []
var _horn_materials: Array[StandardMaterial3D] = []
var _health_label: Label3D
var _pounce_telegraph: Node3D
var _charge_telegraph: MeshInstance3D
var _airborne := false
var _knocked_down := false
var _hit_feedback_time := 0.0


func setup(attack_range: float) -> void:
	if visuals:
		return
	_build_model(attack_range)


func update_feedback(state: StringName, phase: StringName, flash_time: float) -> void:
	current_state = state
	current_phase = phase
	_hit_feedback_time = flash_time
	for index in range(mini(_feedback_materials.size(), _feedback_base_colors.size())):
		_feedback_materials[index].albedo_color = Color("ef8e74") if flash_time > 0.0 else _feedback_base_colors[index]
	if flash_time > 0.0 and state != &"dead":
		_sample_animation(&"hit", 1.0 - flash_time / 0.18)


func animate_attack(data: MonsterAttackData, phase: StringName, elapsed: float, crash_recovery: float) -> void:
	if not data:
		return
	current_state = &"attacking"
	current_phase = phase
	if _hit_feedback_time > 0.0:
		return
	_airborne = false
	_knocked_down = false
	if data.attack_id == &"sweep":
		_sample_animation(&"sweep", elapsed / maxf(data.duration(), 0.001))
	elif data.attack_id == &"pounce":
		_sample_animation(&"pounce", elapsed / maxf(data.duration(), 0.001))
		var active_progress := (elapsed - data.windup) / maxf(data.active, 0.001)
		_airborne = phase == &"active" and active_progress > 0.08 and active_progress < 0.92
	elif data.attack_id == &"charge":
		_animate_charge(data, phase, elapsed, crash_recovery)


func animate_walk(_delta: float, speed: float, maximum_speed: float, dead: bool) -> void:
	if dead or current_state == &"attacking" or _hit_feedback_time > 0.0:
		return
	var amount := minf(speed / maximum_speed, 1.0)
	if amount > 0.05:
		_play_loop(&"run", lerpf(0.8, 1.45, amount))
	else:
		_play_loop(&"idle", 1.0)


func show_attack_telegraph(data: MonsterAttackData) -> void:
	hide_attack_telegraphs()
	if not data:
		return
	if data.attack_id == &"pounce":
		_pounce_telegraph.position.z = -data.movement_speed * data.active
		_pounce_telegraph.show()
	elif data.attack_id == &"charge":
		var length := data.movement_speed * data.active
		_charge_telegraph.scale.z = length
		_charge_telegraph.position.z = -length * 0.5
		_charge_telegraph.show()


func hide_attack_telegraphs() -> void:
	_pounce_telegraph.hide()
	_charge_telegraph.hide()


func update_status(health: int, maximum: int, state: StringName, data: MonsterAttackData, phase: StringName) -> void:
	if health <= 0:
		_health_label.text = "FIELD BEAST\nDOWN — R TO RESET"
	elif state == &"attacking" and data:
		_health_label.text = "FIELD BEAST  /  %d / %d\n%s — %s" % [health, maximum, data.display_name.to_upper(), String(phase).to_upper()]
	else:
		_health_label.text = "FIELD BEAST\n%d / %d" % [health, maximum]


func play_defeated() -> void:
	current_state = &"dead"
	current_phase = &"down"
	_airborne = false
	_knocked_down = true
	_hit_feedback_time = 0.0
	_set_horn_charge_glow(0.0)
	_sample_animation(&"defeated", 1.0)


func reset_pose() -> void:
	current_state = &"idle"
	current_phase = &"ready"
	_airborne = false
	_knocked_down = false
	_hit_feedback_time = 0.0
	visuals.rotation = Vector3.ZERO
	visuals.position = Vector3.ZERO
	_set_horn_charge_glow(0.0)
	hide_attack_telegraphs()
	_sample_animation(&"idle", 0.0)


func motion_probe_sockets() -> Array[Marker3D]:
	return [body_center, head_front]


func status_text() -> String:
	return _health_label.text


func pounce_telegraph_visible() -> bool:
	return _pounce_telegraph.visible


func charge_telegraph_visible() -> bool:
	return _charge_telegraph.visible


func charge_telegraph_length() -> float:
	return _charge_telegraph.scale.z


func is_airborne() -> bool:
	return _airborne


func is_knocked_down() -> bool:
	return _knocked_down


func horn_glowing() -> bool:
	return not _horn_materials.is_empty() and _horn_materials[0].emission_enabled


func _animate_charge(data: MonsterAttackData, phase: StringName, elapsed: float, crash_recovery: float) -> void:
	if phase == &"windup":
		var progress := elapsed / maxf(data.windup, 0.001)
		_sample_animation(&"charge_windup", progress)
		_set_horn_charge_glow(0.35 + clampf(progress, 0.0, 1.0) * 1.8)
	elif phase == &"active":
		_play_loop(&"charge_run", 1.5)
		_set_horn_charge_glow(2.4)
	elif phase == &"stunned":
		var progress := (elapsed - data.windup - data.active) / maxf(crash_recovery, 0.001)
		_sample_animation(&"crash_stunned", progress)
		_knocked_down = progress > 0.06 and progress < 0.92
		_set_horn_charge_glow(lerpf(1.2, 0.0, clampf(progress, 0.0, 1.0)))
	else:
		var progress := (elapsed - data.windup - data.active) / maxf(data.recovery, 0.001)
		_sample_animation(&"charge_recovery", progress)
		_set_horn_charge_glow(lerpf(2.4, 0.0, clampf(progress, 0.0, 1.0)))


func _set_horn_charge_glow(energy: float) -> void:
	for horn_material in _horn_materials:
		horn_material.emission_enabled = energy > 0.01
		horn_material.emission = Color("f0b75e")
		horn_material.emission_energy_multiplier = energy


func _build_model(attack_range: float) -> void:
	visuals = Node3D.new()
	visuals.name = "Visuals"
	visuals.scale = Vector3.ONE * model_scale
	add_child(visuals)
	monster_model = MONSTER_SCENE.instantiate() as Node3D
	monster_model.name = "FieldBeastModel"
	# Blender's authored forward axis imports toward +Z; gameplay faces -Z.
	monster_model.rotation.y = PI
	visuals.add_child(monster_model)
	_skeleton = _find_type(monster_model, Skeleton3D) as Skeleton3D
	_animation_player = _find_type(monster_model, AnimationPlayer) as AnimationPlayer
	assert(_skeleton != null and _animation_player != null, "Monster asset must expose a Skeleton3D and AnimationPlayer")
	_collect_feedback_materials(monster_model)
	left_horn_base = _bone_marker("HornLBase", Vector3.ZERO)
	left_horn_tip = _bone_marker("HornLTip", Vector3(0.0, 0.5, 0.0))
	right_horn_base = _bone_marker("HornRBase", Vector3.ZERO)
	right_horn_tip = _bone_marker("HornRTip", Vector3(0.0, 0.5, 0.0))
	body_center = _bone_marker("Spine", Vector3.ZERO)
	head_front = _bone_marker("Head", Vector3(0.0, 0.5, 0.0))
	FieldGeometry.ring(self, attack_range, 0.045, Vector3(0, 0.055, 0), FieldGeometry.material(Color("c98665"), 0.28))
	_build_attack_telegraphs()
	_health_label = Label3D.new()
	_health_label.position = Vector3(0, 2.75, 0)
	_health_label.font_size = 42
	_health_label.pixel_size = 0.008
	_health_label.modulate = Color("eadab5")
	_health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_health_label)
	_sample_animation(&"idle", 0.0)


func _bone_marker(bone_name: StringName, at: Vector3) -> Marker3D:
	assert(_skeleton.find_bone(bone_name) >= 0, "Monster skeleton is missing " + bone_name)
	var attachment := BoneAttachment3D.new()
	attachment.name = String(bone_name) + "Attachment"
	attachment.bone_name = bone_name
	_skeleton.add_child(attachment)
	var marker := Marker3D.new()
	marker.name = bone_name
	marker.position = at
	attachment.add_child(marker)
	return marker


func _build_attack_telegraphs() -> void:
	var pounce_material := FieldGeometry.material(Color("e5c268"), 0.55)
	pounce_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pounce_material.albedo_color.a = 0.52
	_pounce_telegraph = Node3D.new()
	_pounce_telegraph.name = "PounceLandingTelegraph"
	add_child(_pounce_telegraph)
	FieldGeometry.ring(_pounce_telegraph, 1.15, 0.11, Vector3(0, 0.02, 0), pounce_material)
	var charge_material := FieldGeometry.material(Color("e46f45"), 0.72)
	charge_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	charge_material.albedo_color.a = 0.42
	_charge_telegraph = FieldGeometry.box(self, Vector3(1.7, 0.025, 1.0), Vector3.ZERO, charge_material)
	_charge_telegraph.name = "ChargePathTelegraph"
	_charge_telegraph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hide_attack_telegraphs()


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
				if source.resource_name.contains("PaleHorn"):
					_horn_materials.append(instance_material)
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
