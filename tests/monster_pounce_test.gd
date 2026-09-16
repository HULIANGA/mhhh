extends SceneTree
## Verify the M3.4 medium-range pounce selection, locked motion, path hit, dodge, and recovery.

class TestInputSource extends HunterInputSource:
	var frame := HunterInputFrame.new()
	func sample(_viewport: Viewport, _position: Vector3) -> HunterInputFrame:
		return frame
	func clear() -> void:
		frame = HunterInputFrame.new()

var failures: int = 0
var game: Node3D
var hunter: Hunter
var monster: FieldMonster
var source: TestInputSource

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	hunter = game.get_node("Player")
	monster = game.get_node("FieldMonster")
	source = TestInputSource.new()
	hunter.add_child(source)
	hunter.input_source = source
	game.resume()

	_prepare_encounter(Vector3(0, 0.05, -5.0))
	await _until_phase(FieldMonster.PHASE_WINDUP)
	_expect(monster._attack_data == FieldMonster.POUNCE_ATTACK, "Medium range selects the configured pounce instead of the close sweep")
	_expect(monster._presentation.status_text().contains("POUNCE") and monster._presentation.status_text().contains("WINDUP"), "Pounce windup has a readable phase warning")
	_expect(monster._presentation.pounce_telegraph_visible() and not monster._presentation.charge_telegraph_visible(), "Pounce windup shows a compact landing marker instead of a charge lane")
	var pounce_start := monster.position
	await _until_phase(FieldMonster.PHASE_ACTIVE)
	var locked_direction := monster._locked_attack_direction
	await _frames(8)
	_expect(monster._presentation.is_airborne(), "Pounce enters the presentation adapter's airborne state")
	await _until_phase(FieldMonster.PHASE_RECOVERY)
	var pounce_displacement := monster.position - pounce_start
	pounce_displacement.y = 0.0
	_expect(pounce_displacement.length() > 3.0 and pounce_displacement.normalized().dot(locked_direction) > 0.995, "Pounce travels quickly along its locked direction")
	_expect(hunter.health == hunter.max_health - FieldMonster.POUNCE_ATTACK.damage, "Pounce path probes apply the configured damage")
	await _frames(16)
	_expect(hunter.health == hunter.max_health - FieldMonster.POUNCE_ATTACK.damage, "One pounce cannot damage the hunter repeatedly")

	_prepare_encounter(Vector3(0, 0.05, -5.0))
	await _until_phase(FieldMonster.PHASE_ACTIVE)
	locked_direction = monster._locked_attack_direction
	pounce_start = monster.position
	hunter.position = Vector3(5.0, 0.05, 0.0)
	await _until_phase(FieldMonster.PHASE_RECOVERY)
	pounce_displacement = monster.position - pounce_start
	pounce_displacement.y = 0.0
	_expect(pounce_displacement.normalized().dot(locked_direction) > 0.995, "Pounce cannot turn to track the hunter after windup locks its direction")
	_expect(hunter.health == hunter.max_health, "Side-stepping the locked pounce path avoids damage")

	_prepare_encounter(Vector3(0, 0.05, -5.0))
	await _until_phase(FieldMonster.PHASE_ACTIVE)
	source.frame.movement = Vector2.RIGHT
	source.frame.dodge.pressed = true
	source.frame.dodge.held = true
	await _frames(1)
	source.frame = HunterInputFrame.new()
	await _until_phase(FieldMonster.PHASE_RECOVERY)
	_expect(hunter.health == hunter.max_health, "A lateral dodge avoids the fixed pounce path")

	var monster_health_before := monster.health
	hunter.position = monster.position + Vector3(0, 0.05, 2.2)
	hunter._presentation.set_facing_y(0.0)
	hunter.velocity = Vector3.ZERO
	while hunter.action_state != Hunter.STATE_FREE:
		await physics_frame
	await _frames(2)
	await _tap_attack()
	await _frames(24)
	_expect(monster.health == monster_health_before - Hunter.LIGHT_ACTION.damage, "Pounce landing recovery leaves a safe counterattack window")

	hunter.position = monster.position + Vector3(0, 0.05, 10.0)
	await _until_not_attacking()
	await _frames(2)
	_expect(monster.state == FieldMonster.STATE_CHASING, "Pounce recovery returns to pursuit when the hunter is far away")

	print("MONSTER POUNCE TESTS: %s" % ("PASS" if failures == 0 else "%d FAILURES" % failures))
	paused = false
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func _prepare_encounter(hunter_position: Vector3) -> void:
	game.reset_exercise()
	source.frame = HunterInputFrame.new()
	monster.attacks_enabled = true
	monster.position = Vector3(0, 0.05, 0)
	monster.rotation = Vector3.ZERO
	monster.velocity = Vector3.ZERO
	hunter.position = hunter_position
	hunter._presentation.set_facing_y(0.0)
	hunter.velocity = Vector3.ZERO

func _until_phase(expected: StringName, maximum_frames: int = 180) -> void:
	for frame_index in range(maximum_frames):
		await physics_frame
		if monster.attack_phase == expected:
			return
	_expect(false, "Monster reaches phase %s" % expected)

func _until_not_attacking(maximum_frames: int = 180) -> void:
	for frame_index in range(maximum_frames):
		await physics_frame
		if monster.state != FieldMonster.STATE_ATTACKING:
			return
	_expect(false, "Monster finishes its current attack")

func _tap_attack() -> void:
	source.frame.attack.pressed = true
	source.frame.attack.held = true
	await _frames(1)
	source.frame = HunterInputFrame.new()
	await _frames(1)

func _frames(count: int) -> void:
	for frame_index in range(count):
		await physics_frame

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		failures += 1
		printerr("FAIL: %s" % message)
