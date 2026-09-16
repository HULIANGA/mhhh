class_name MonsterPresentation
extends Node3D
## Replaceable monster art boundary and the sole owner of visual state.

@export_range(0.5, 3.0, 0.05) var model_scale: float = 1.25

var visuals: Node3D
var left_horn_base: Marker3D
var left_horn_tip: Marker3D
var right_horn_base: Marker3D
var right_horn_tip: Marker3D
var body_center: Marker3D
var head_front: Marker3D
var current_state: StringName = &"idle"
var current_phase: StringName = &"ready"

var _body_material: StandardMaterial3D
var _horn_material: StandardMaterial3D
var _left_foreleg: Node3D
var _right_foreleg: Node3D
var _left_hindleg: Node3D
var _right_hindleg: Node3D
var _health_label: Label3D
var _pounce_telegraph: Node3D
var _charge_telegraph: MeshInstance3D
var _walk_time: float = 0.0

func setup(attack_range: float) -> void:
	if visuals:
		return
	_build_placeholder(attack_range)

func update_feedback(state: StringName, phase: StringName, flash_time: float) -> void:
	current_state = state
	current_phase = phase
	var color := Color("75635a")
	if state == &"attacking":
		if phase == &"windup":
			color = Color("d19a58")
		elif phase == &"active":
			color = Color("d9574f")
		elif phase == &"stunned":
			color = Color("536b78")
		else:
			color = Color("617b78")
	_body_material.albedo_color = Color("ef8e74") if flash_time > 0.0 else color

func animate_attack(data: MonsterAttackData, phase: StringName, elapsed: float, crash_recovery: float) -> void:
	if not data:
		return
	current_state = &"attacking"
	current_phase = phase
	if data.attack_id == &"pounce":
		_animate_pounce(data, phase, elapsed)
	elif data.attack_id == &"charge":
		_animate_charge(data, phase, elapsed, crash_recovery)
	elif phase == &"windup":
		var progress := _smooth(elapsed / data.windup)
		visuals.rotation.y = lerpf(0.0, -0.48, progress)
		visuals.rotation.x = lerpf(0.0, 0.16, progress)
	elif phase == &"active":
		var progress := _smooth((elapsed - data.windup) / data.active)
		visuals.rotation.y = lerpf(-0.48, 0.78, progress)
		visuals.rotation.x = lerpf(0.16, -0.1, progress)
	else:
		var progress := _smooth((elapsed - data.windup - data.active) / data.recovery)
		visuals.rotation.y = lerpf(0.78, 0.0, progress)
		visuals.rotation.x = lerpf(-0.1, 0.0, progress)

func animate_walk(delta: float, speed: float, maximum_speed: float, dead: bool) -> void:
	if dead:
		return
	_walk_time += delta * speed * 3.1
	var amount := minf(speed / maximum_speed, 1.0)
	var swing := sin(_walk_time) * 0.38 * amount
	_left_foreleg.rotation.x = swing
	_right_hindleg.rotation.x = swing
	_right_foreleg.rotation.x = -swing
	_left_hindleg.rotation.x = -swing
	visuals.position.y = absf(sin(_walk_time * 2.0)) * 0.035 * amount

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
	visuals.rotation.z = deg_to_rad(78.0)

func reset_pose() -> void:
	current_state = &"idle"
	current_phase = &"ready"
	visuals.rotation = Vector3.ZERO
	visuals.position = Vector3.ZERO
	for leg: Node3D in [_left_foreleg, _right_foreleg, _left_hindleg, _right_hindleg]:
		leg.rotation = Vector3.ZERO
	_set_horn_charge_glow(0.0)
	hide_attack_telegraphs()

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
	return visuals.position.y > 0.3 * model_scale

func is_knocked_down() -> bool:
	return absf(visuals.rotation.z) > 0.8

func horn_glowing() -> bool:
	return _horn_material.emission_enabled

func _animate_pounce(data: MonsterAttackData, phase: StringName, elapsed: float) -> void:
	if phase == &"windup":
		var progress := _smooth(elapsed / data.windup)
		visuals.rotation.x = lerpf(0.0, 0.34, progress)
		visuals.position.y = lerpf(0.0, -0.16, progress)
		_left_foreleg.rotation.x = lerpf(0.0, 0.35, progress)
		_right_foreleg.rotation.x = lerpf(0.0, 0.35, progress)
		_left_hindleg.rotation.x = lerpf(0.0, -0.28, progress)
		_right_hindleg.rotation.x = lerpf(0.0, -0.28, progress)
	elif phase == &"active":
		var raw := clampf((elapsed - data.windup) / data.active, 0.0, 1.0)
		visuals.rotation.x = lerpf(0.34, -0.24, _smooth(raw))
		visuals.position.y = sin(raw * PI) * 0.68
		_left_foreleg.rotation.x = lerpf(0.35, -1.05, _smooth(minf(raw * 2.5, 1.0)))
		_right_foreleg.rotation.x = lerpf(0.35, -1.05, _smooth(minf(raw * 2.5, 1.0)))
	else:
		var progress := _smooth((elapsed - data.windup - data.active) / data.recovery)
		visuals.rotation.x = lerpf(-0.24, 0.0, progress)
		visuals.position.y = 0.0
		_left_foreleg.rotation.x = lerpf(-1.05, 0.0, progress)
		_right_foreleg.rotation.x = lerpf(-1.05, 0.0, progress)
		_left_hindleg.rotation.x = lerpf(-0.28, 0.0, progress)
		_right_hindleg.rotation.x = lerpf(-0.28, 0.0, progress)

func _animate_charge(data: MonsterAttackData, phase: StringName, elapsed: float, crash_recovery: float) -> void:
	if phase == &"windup":
		var progress := _smooth(elapsed / data.windup)
		visuals.rotation.x = lerpf(0.0, 0.46, progress)
		visuals.position.y = lerpf(0.0, -0.22, progress)
		visuals.position.z = lerpf(0.0, 0.34, _smooth(minf(progress / 0.72, 1.0)))
		var scrape := sin(progress * TAU * 2.0) * 0.5 * minf(progress * 3.0, 1.0)
		_left_foreleg.rotation.x = scrape
		_right_foreleg.rotation.x = -scrape * 0.35
		_set_horn_charge_glow(0.35 + progress * 1.8)
	elif phase == &"active":
		var progress := clampf((elapsed - data.windup) / data.active, 0.0, 1.0)
		visuals.rotation.x = lerpf(0.46, -0.34, minf(progress * 3.0, 1.0))
		visuals.position.y = lerpf(-0.22, 0.0, minf(progress * 3.0, 1.0))
		visuals.position.z = lerpf(0.34, 0.0, minf(progress * 4.0, 1.0))
		_left_foreleg.rotation.x = lerpf(_left_foreleg.rotation.x, -0.22, minf(progress * 4.0, 1.0))
		_right_foreleg.rotation.x = lerpf(_right_foreleg.rotation.x, -0.22, minf(progress * 4.0, 1.0))
		_set_horn_charge_glow(2.4)
	elif phase == &"stunned":
		var progress := clampf((elapsed - data.windup - data.active) / crash_recovery, 0.0, 1.0)
		var fall := _smooth(minf(progress / 0.12, 1.0))
		var rise := _smooth(clampf((progress - 0.78) / 0.22, 0.0, 1.0))
		visuals.rotation.x = lerpf(-0.34, 0.0, rise)
		visuals.rotation.z = lerpf(0.0, 1.28, fall) * (1.0 - rise)
		visuals.position.y = -0.18 * fall * (1.0 - rise)
		visuals.position.z = 0.0
		_set_horn_charge_glow(lerpf(1.2, 0.0, rise))
	else:
		var progress := _smooth((elapsed - data.windup - data.active) / data.recovery)
		visuals.rotation.x = lerpf(-0.34, 0.0, progress)
		visuals.position.y = 0.0
		visuals.position.z = 0.0
		_left_foreleg.rotation.x = lerpf(-0.22, 0.0, progress)
		_right_foreleg.rotation.x = lerpf(-0.22, 0.0, progress)
		_set_horn_charge_glow(lerpf(2.4, 0.0, progress))

func _set_horn_charge_glow(energy: float) -> void:
	_horn_material.emission_enabled = energy > 0.01
	_horn_material.emission = Color("f0b75e")
	_horn_material.emission_energy_multiplier = energy

func _build_placeholder(attack_range: float) -> void:
	visuals = Node3D.new()
	visuals.name = "Visuals"
	visuals.scale = Vector3.ONE * model_scale
	add_child(visuals)
	_body_material = FieldGeometry.material(Color("75635a"))
	var hide := FieldGeometry.material(Color("51463f"))
	_horn_material = FieldGeometry.material(Color("d7c99f"))
	var body := FieldGeometry.box(visuals, Vector3(1.55, 1.05, 2.25), Vector3(0, 1.05, 0), _body_material)
	FieldGeometry.box(visuals, Vector3(1.25, 0.92, 0.92), Vector3(0, 1.12, -1.32), hide)
	var left_horn := FieldGeometry.box(visuals, Vector3(0.22, 0.22, 0.72), Vector3(-0.42, 1.38, -1.88), _horn_material)
	var right_horn := FieldGeometry.box(visuals, Vector3(0.22, 0.22, 0.72), Vector3(0.42, 1.38, -1.88), _horn_material)
	_left_foreleg = _leg(Vector3(-0.52, 0.48, -0.66), hide)
	_right_foreleg = _leg(Vector3(0.52, 0.48, -0.66), hide)
	_left_hindleg = _leg(Vector3(-0.52, 0.48, 0.68), hide)
	_right_hindleg = _leg(Vector3(0.52, 0.48, 0.68), hide)
	left_horn_base = _marker(left_horn, "HornLBase", Vector3(0.0, 0.0, 0.32))
	left_horn_tip = _marker(left_horn, "HornLTip", Vector3(0.0, 0.0, -0.42))
	right_horn_base = _marker(right_horn, "HornRBase", Vector3(0.0, 0.0, 0.32))
	right_horn_tip = _marker(right_horn, "HornRTip", Vector3(0.0, 0.0, -0.42))
	body_center = _marker(body, "BodyCenter", Vector3.ZERO)
	head_front = _marker(visuals, "HeadFront", Vector3(0.0, 1.05, -1.75))
	var warning := FieldGeometry.material(Color("c98665"), 0.28)
	FieldGeometry.ring(self, attack_range, 0.045, Vector3(0, 0.055, 0), warning)
	_build_attack_telegraphs()
	_health_label = Label3D.new()
	_health_label.position = Vector3(0, 2.75, 0)
	_health_label.font_size = 42
	_health_label.pixel_size = 0.008
	_health_label.modulate = Color("eadab5")
	_health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_health_label)

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

func _leg(at: Vector3, material: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	visuals.add_child(pivot)
	FieldGeometry.box(pivot, Vector3(0.34, 0.9, 0.38), Vector3(0, -0.32, 0), material)
	return pivot

func _marker(parent: Node3D, marker_name: String, at: Vector3) -> Marker3D:
	var result := Marker3D.new()
	result.name = marker_name
	result.position = at
	parent.add_child(result)
	return result

func _smooth(value: float) -> float:
	var clamped := clampf(value, 0.0, 1.0)
	return clamped * clamped * (3.0 - 2.0 * clamped)
