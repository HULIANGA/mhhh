class_name TrainingDummy
extends StaticBody3D

signal health_changed(current: int, maximum: int)
signal hit_received(damage: int, world_position: Vector3)

@export var max_health: int = 240
var health: int = 240
var hit_count: int = 0
var damage_received: int = 0
var _resolved_attacks: Dictionary = {}
var _flash_time: float = 0.0
var _body_material: StandardMaterial3D
var _health_label: Label3D
var _visuals: Node3D

func _ready() -> void:
	name = "TrainingDummy"
	collision_layer = 5 # World and damageable.
	collision_mask = 0
	add_to_group("damageable")
	_build_placeholder()
	reset_target()

func _process(delta: float) -> void:
	_flash_time = maxf(_flash_time - delta, 0.0)
	if _body_material:
		_body_material.albedo_color = Color("e6c27a") if _flash_time > 0.0 else Color("80674d")
	if _visuals:
		_visuals.rotation.z = sin(_flash_time * 42.0) * 0.045 if _flash_time > 0.0 else 0.0

func receive_hit(attack_token: int, damage: int, hit_position: Vector3) -> bool:
	if _resolved_attacks.has(attack_token):
		return false
	# A training post must remain usable indefinitely. Rebuild its durability on
	# the first new attack after it breaks; never turn one active window into two
	# hits because the attack token is still recorded below.
	if health <= 0:
		health = max_health
	_resolved_attacks[attack_token] = true
	health = maxi(health - damage, 0)
	hit_count += 1
	damage_received += damage
	_flash_time = 0.16
	_update_label()
	health_changed.emit(health, max_health)
	hit_received.emit(damage, hit_position)
	return true

func reset_target() -> void:
	health = max_health
	hit_count = 0
	damage_received = 0
	_resolved_attacks.clear()
	_flash_time = 0.0
	_update_label()
	health_changed.emit(health, max_health)

func _update_label() -> void:
	if _health_label:
		_health_label.text = "TRAINING POST\n%d / %d" % [health, max_health] if health > 0 else "TRAINING POST\nBROKEN — R TO RESET"

func _build_placeholder() -> void:
	_visuals = Node3D.new()
	_visuals.name = "Visuals"
	add_child(_visuals)
	_body_material = FieldGeometry.material(Color("80674d"))
	var iron := FieldGeometry.material(Color("455553"))
	var cloth := FieldGeometry.material(Color("b06758"))
	FieldGeometry.box(_visuals, Vector3(0.95, 1.7, 0.62), Vector3(0, 1.05, 0), _body_material)
	FieldGeometry.box(_visuals, Vector3(1.45, 0.16, 0.78), Vector3(0, 0.3, 0), iron)
	FieldGeometry.box(_visuals, Vector3(0.18, 1.25, 0.18), Vector3(-0.58, 1.02, 0), iron)
	FieldGeometry.box(_visuals, Vector3(0.18, 1.25, 0.18), Vector3(0.58, 1.02, 0), iron)
	FieldGeometry.box(_visuals, Vector3(1.02, 0.38, 0.68), Vector3(0, 1.25, -0.02), cloth)
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.05, 1.8, 0.72)
	var collision := CollisionShape3D.new()
	collision.position = Vector3(0, 1.05, 0)
	collision.shape = shape
	add_child(collision)
	_health_label = Label3D.new()
	_health_label.position = Vector3(0, 2.35, 0)
	_health_label.font_size = 42
	_health_label.pixel_size = 0.008
	_health_label.modulate = Color("eadab5")
	_health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_health_label)
	FieldGeometry.ring(self, 1.15, 0.045, Vector3(0, 0.055, 0), FieldGeometry.material(Color("c98665"), 0.45))
