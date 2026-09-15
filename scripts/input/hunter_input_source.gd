class_name HunterInputSource
extends Node
## Replace the player's InputSource with a subclass to add another device.
## Device selection, dead zones and touch identifiers belong in adapters.

func sample(_viewport: Viewport, _actor_position: Vector3) -> HunterInputFrame:
	return HunterInputFrame.new()

## Clear held actions / pending edges on pause, restart or device change.
## Clearing is cancellation, not a release that should trigger a charge attack.
func clear() -> void:
	pass
