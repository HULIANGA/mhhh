extends SceneTree
## Verify the M3.2 monster's pursuit, health, death, arena bounds, and reset contract.

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
var defeat_events: int = 0

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
	monster.defeated.connect(func(): defeat_events += 1)
	game.resume()
	await _frames(3)

	_expect(monster.health == monster.max_health and monster.state == FieldMonster.STATE_CHASING, "Monster detects the hunter and starts pursuing")
	var starting_distance := monster.global_position.distance_to(hunter.global_position)
	await _frames(150)
	var pursued_distance := monster.global_position.distance_to(hunter.global_position)
	_expect(pursued_distance < starting_distance - 4.0, "Monster closes distance with direct physical movement")
	await _frames(120)
	_expect(monster.state == FieldMonster.STATE_READY and pursued_distance >= 0.0, "Monster stops when it reaches attack range")
	_expect(monster.global_position.distance_to(hunter.global_position) <= monster.attack_range + 0.18, "Monster holds just outside its configured attack distance")
	_expect(hunter.health == hunter.max_health, "Monster body contact never damages the hunter")

	monster.position = Vector3(monster.arena_max.x + 4.0, 0.05, monster.arena_max.y + 4.0)
	await _frames(2)
	_expect(monster.position.x <= monster.arena_max.x + 0.001 and monster.position.z <= monster.arena_max.y + 0.001, "Monster remains inside the arena bounds")
	_expect(monster.receive_hit(8001, 10, monster.position) and not monster.receive_hit(8001, 10, monster.position) and monster.health == monster.max_health - 10, "One player attack token can damage the monster only once")

	game.reset_exercise()
	monster.move_speed = 0.0
	monster.max_health = Hunter.LIGHT_ACTION.damage
	monster.reset_monster()
	hunter.position = monster.position + Vector3(0, 0, 2.2)
	hunter.visuals.rotation = Vector3.ZERO
	hunter.velocity = Vector3.ZERO
	await _frames(4)
	await _tap_attack()
	await _frames(40)
	_expect(monster.health == 0 and monster.is_dead and monster.state == FieldMonster.STATE_DEAD, "A real sword hit can kill the monster")
	_expect(defeat_events == 1, "Monster defeat is emitted exactly once")
	var death_position := monster.position
	hunter.position += Vector3(5, 0, 0)
	await _frames(30)
	_expect(monster.position.is_equal_approx(death_position) and monster.velocity.is_zero_approx(), "Dead monster stops movement and decisions")
	_expect(not monster.receive_hit(9001, 10, monster.position) and defeat_events == 1, "Dead monster rejects further hits without repeating defeat")

	monster.max_health = 180
	game.reset_exercise()
	_expect(monster.position.distance_to(Vector3(7, 0.05, -5)) < 0.001, "Reset restores the monster's initial position")
	await _frames(2)
	_expect(monster.health == monster.max_health and not monster.is_dead and monster.state != FieldMonster.STATE_DEAD, "Reset restores monster health and decisions")
	_expect(monster.receive_hit(9001, 10, monster.position), "Reset clears the monster's resolved attack tokens")

	print("MONSTER TESTS: %s" % ("PASS" if failures == 0 else "%d FAILURES" % failures))
	paused = false
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

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
