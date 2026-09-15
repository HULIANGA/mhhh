class_name CombatActionData
extends Resource
## Tunable timing and hit-volume data for one combat action.

@export var display_name: String = "Action"
@export_range(0.0, 2.0) var windup: float = 0.2
@export_range(0.01, 1.0) var active: float = 0.1
@export_range(0.0, 2.0) var recovery: float = 0.3
@export_range(0, 200) var damage: int = 10
@export_range(0.0, 100.0) var stamina_cost: float = 0.0
@export_range(0.1, 4.0) var hit_reach: float = 1.25
@export_range(0.1, 3.0) var hit_radius: float = 0.8
@export_range(0.0, 1.0) var movement_scale: float = 0.15
@export_range(0.0, 5.0) var charge_threshold: float = 0.0

func duration() -> float:
	return windup + active + recovery
