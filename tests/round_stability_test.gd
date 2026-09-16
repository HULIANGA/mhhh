extends SceneTree
## Stress M3 restarts across settled rounds and verify no combat state leaks.

const ROUND_COUNT := 10

var failures: int = 0
var game: Node3D
var hunter: Hunter
var monster: FieldMonster
var settled_results: Array[StringName] = []
var initial_node_count: int

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	hunter = game.get_node("Player")
	monster = game.get_node("FieldMonster")
	game.battle_settled.connect(func(result: StringName): settled_results.append(result))
	game.resume()
	await physics_frame
	initial_node_count = _count_nodes(game)

	for round_index in range(ROUND_COUNT):
		await _dirty_round_state(round_index)
		var expected_result: StringName
		if round_index % 2 == 0:
			expected_result = game.BATTLE_WON
			monster.receive_hit(8100 + round_index, monster.max_health, monster.global_position)
		else:
			expected_result = game.BATTLE_LOST
			hunter.receive_hit(8200 + round_index, hunter.max_health, hunter.global_position)
		await process_frame
		_expect(game.battle_state == expected_result and paused, "Round %d settles with the expected result" % (round_index + 1))
		_expect(settled_results.size() == round_index + 1 and game.settlement_count == round_index + 1, "Round %d settles exactly once" % (round_index + 1))

		game.reset_exercise()
		await physics_frame
		_expect(_round_is_clean(), "Restart %d restores combat, input, and obstacles" % (round_index + 1))
		_expect(_count_nodes(game) == initial_node_count, "Restart %d keeps the complete scene population stable" % (round_index + 1))

	_expect(settled_results.size() == ROUND_COUNT, "Ten alternating rounds complete without a missing or duplicate settlement")
	print("ROUND STABILITY TESTS: %s" % ("PASS" if failures == 0 else "%d FAILURES" % failures))
	paused = false
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func _dirty_round_state(round_index: int) -> void:
	var obstacle: BreakableObstacle = game.arena.breakable_obstacles[round_index % game.arena.breakable_obstacles.size()]
	obstacle.break_from_charge(obstacle.global_position)
	hunter.receive_hit(8000 + round_index, 1, monster.global_position)
	hunter.stamina = 1.0
	Input.action_press("move_right")
	Input.action_press("attack")
	await physics_frame
	monster._start_attack(monster.SWEEP_ATTACK)
	_expect(monster.state == monster.STATE_ATTACKING and monster.attack_token > 0, "Round %d creates active monster attack state before settlement" % (round_index + 1))

func _round_is_clean() -> bool:
	var obstacles_clean := true
	for obstacle: BreakableObstacle in game.arena.breakable_obstacles:
		obstacles_clean = obstacles_clean and not obstacle.is_broken and obstacle.collision_layer == 1
	return (
		game.battle_state == game.BATTLE_RUNNING
		and not paused
		and not game.hud.overlay.visible
		and hunter.health == hunter.max_health
		and is_equal_approx(hunter.stamina, hunter.max_stamina)
		and not hunter.is_defeated
		and hunter.action_state == hunter.STATE_FREE
		and hunter.action_phase == &"ready"
		and hunter.velocity.is_zero_approx()
		and hunter._resolved_incoming_attacks.is_empty()
		and hunter._hit_targets.is_empty()
		and not hunter._queued_attack
		and not hunter._queued_dodge
		and not hunter._queued_charge
		and not Input.is_action_pressed("move_right")
		and not Input.is_action_pressed("attack")
		and monster.health == monster.max_health
		and not monster.is_dead
		and monster.state == monster.STATE_IDLE
		and monster.attack_phase == &"ready"
		and monster.attack_token == 0
		and monster.attack_cooldown_left <= 0.0
		and monster.last_attack_id.is_empty()
		and monster.consecutive_attack_count == 0
		and monster._resolved_attacks.is_empty()
		and monster._attack_data == null
		and obstacles_clean
	)

func _count_nodes(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count_nodes(child)
	return total

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		failures += 1
		printerr("FAIL: %s" % message)
