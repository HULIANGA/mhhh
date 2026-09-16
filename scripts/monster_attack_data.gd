class_name MonsterAttackData
extends Resource
## Tunable timing and hit-volume data shared by monster attacks.

@export var display_name: String = "Monster attack"
@export var attack_id: StringName = &"attack"
@export_range(0.0, 3.0) var windup: float = 0.6
@export_range(0.01, 1.5) var active: float = 0.2
@export_range(0.0, 3.0) var recovery: float = 0.8
@export_range(0, 200) var damage: int = 20
@export_range(0.1, 2.0) var hit_radius: float = 0.42
@export_range(0.0, 1.0) var hit_delay: float = 0.0
@export_range(0.0, 20.0) var movement_speed: float = 0.0
@export_range(0.0, 20.0) var minimum_range: float = 0.0
@export_range(0.1, 30.0) var maximum_range: float = 3.0

func duration() -> float:
	return windup + active + recovery
