extends SceneTree
## Verify the M3.5 extended charge, obstacle outcomes, locked path, and shared cooldown.

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

	_prepare_encounter(Vector3(4, 0.05, -5.0), Vector3(4, 0.05, 8.0))
	await _until_phase(FieldMonster.PHASE_WINDUP)
	await physics_frame
	_expect(monster._attack_data == FieldMonster.CHARGE_ATTACK, "Far range selects charge while medium and close ranges remain assigned to pounce and sweep")
	_expect(monster._presentation.current_animation == &"charge_windup", "Charge windup is communicated by its authored silhouette")
	await _frames(24)
	_expect(monster._presentation.charge_telegraph_visible() and monster._presentation.charge_telegraph_length() > 12.0 and not monster._presentation.pounce_telegraph_visible(), "Charge windup shows a long lane instead of a landing marker")
	_expect(monster._presentation.horn_glowing(), "Charge windup activates the presentation adapter's horn warning")
	var charge_start := monster.position
	await _until_phase(FieldMonster.PHASE_ACTIVE)
	var locked_direction := monster._locked_attack_direction
	await _until_phase(FieldMonster.PHASE_RECOVERY)
	var charge_displacement := monster.position - charge_start
	charge_displacement.y = 0.0
	_expect(charge_displacement.length() > 11.0 and charge_displacement.normalized().dot(locked_direction) > 0.995, "Charge travels farther along its locked direction")
	_expect(hunter.health == hunter.max_health - FieldMonster.CHARGE_ATTACK.damage, "Charge path probes apply the configured damage")
	await _frames(12)
	_expect(hunter.health == hunter.max_health - FieldMonster.CHARGE_ATTACK.damage, "One charge cannot damage the hunter repeatedly")

	_prepare_encounter(Vector3(4, 0.05, -5.0), Vector3(4, 0.05, 8.0))
	await _until_phase(FieldMonster.PHASE_ACTIVE)
	locked_direction = monster._locked_attack_direction
	charge_start = monster.position
	hunter.position = Vector3(6.0, 0.05, 0.0)
	await _until_phase(FieldMonster.PHASE_RECOVERY)
	charge_displacement = monster.position - charge_start
	charge_displacement.y = 0.0
	_expect(charge_displacement.normalized().dot(locked_direction) > 0.995, "Charge cannot turn to track the hunter after windup locks its direction")
	_expect(hunter.health == hunter.max_health, "Side-stepping the locked charge path avoids damage")

	_prepare_encounter(Vector3(4, 0.05, -12.8), Vector3(4, 0.05, -4.5))
	hunter.collision_layer = 0
	await _until_phase(FieldMonster.PHASE_ACTIVE)
	charge_start = monster.position
	await _until_phase(FieldMonster.PHASE_STUNNED)
	hunter.collision_layer = 2
	charge_displacement = monster.position - charge_start
	charge_displacement.y = 0.0
	_expect(monster.position.z >= monster.arena_min.y - 0.01 and charge_displacement.length() < FieldMonster.CHARGE_ATTACK.movement_speed * FieldMonster.CHARGE_ATTACK.active, "Arena boundary stops charge and triggers the stunned phase")
	await _frames(18)
	_expect(monster.attack_phase == FieldMonster.PHASE_STUNNED and monster._presentation.is_knocked_down(), "Crashing into an indestructible boundary leaves the monster visibly down")

	_prepare_encounter(Vector3(-3.0, 0.05, -10.0), Vector3(-3.0, 0.05, 6.0))
	hunter.collision_layer = 0
	await _until_phase(FieldMonster.PHASE_STUNNED)
	hunter.collision_layer = 2
	_expect(monster.position.z > -3.0 and monster.attack_phase == FieldMonster.PHASE_STUNNED, "Central indestructible monolith knocks the charging monster down")

	var obstacle: BreakableObstacle = game.arena.breakable_obstacles[0]
	var obstacle_position := obstacle.global_position
	_prepare_encounter(obstacle_position + Vector3(0, 0.05, -5.5), obstacle_position + Vector3(0, 0.05, 6.0))
	await _until_obstacle_broken(obstacle)
	_expect(obstacle.is_broken and monster.attack_phase == FieldMonster.PHASE_ACTIVE, "Charge destroys a breakable barricade without knocking the monster down")
	game.reset_exercise()
	await _frames(2)
	_expect(not obstacle.is_broken and obstacle.collision_layer == 1, "Reset rebuilds destroyed barricades")

	_prepare_encounter(Vector3(4, 0.05, -12.8), Vector3(4, 0.05, -4.5))
	hunter.collision_layer = 0
	await _until_phase(FieldMonster.PHASE_STUNNED)
	hunter.collision_layer = 2
	hunter.position = monster.position - monster._forward() * 2.1
	hunter.position.y = 0.05
	await _until_not_attacking()
	await _frames(3)
	_expect(monster.attack_cooldown_left > 0.0 and monster.state != FieldMonster.STATE_ATTACKING, "Shared cooldown prevents an immediate seamless follow-up attack")
	await _until_attacking()
	_expect(monster._attack_data == FieldMonster.SWEEP_ATTACK, "After cooldown, close range selects sweep")

	print("MONSTER CHARGE TESTS: %s" % ("PASS" if failures == 0 else "%d FAILURES" % failures))
	paused = false
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func _prepare_encounter(hunter_position: Vector3, monster_position: Vector3 = Vector3(0, 0.05, 0)) -> void:
	game.reset_exercise()
	source.frame = HunterInputFrame.new()
	monster.attacks_enabled = true
	monster.position = monster_position
	monster.rotation = Vector3.ZERO
	monster.velocity = Vector3.ZERO
	hunter.position = hunter_position
	hunter._presentation.set_facing_y(0.0)
	hunter.velocity = Vector3.ZERO

func _until_phase(expected: StringName, maximum_frames: int = 240) -> void:
	for frame_index in range(maximum_frames):
		await physics_frame
		if monster.attack_phase == expected:
			return
	_expect(false, "Monster reaches phase %s" % expected)

func _until_not_attacking(maximum_frames: int = 240) -> void:
	for frame_index in range(maximum_frames):
		await physics_frame
		if monster.state != FieldMonster.STATE_ATTACKING:
			return
	_expect(false, "Monster finishes its current attack")

func _until_attacking(maximum_frames: int = 240) -> void:
	for frame_index in range(maximum_frames):
		await physics_frame
		if monster.state == FieldMonster.STATE_ATTACKING:
			return
	_expect(false, "Monster starts an attack after cooldown")

func _until_obstacle_broken(obstacle: BreakableObstacle, maximum_frames: int = 240) -> void:
	for frame_index in range(maximum_frames):
		await physics_frame
		if obstacle.is_broken:
			return
	_expect(false, "Charge reaches and breaks the barricade")

func _frames(count: int) -> void:
	for frame_index in range(count):
		await physics_frame

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		failures += 1
		printerr("FAIL: %s" % message)
