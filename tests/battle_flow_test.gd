extends SceneTree
## Verify M3.7 victory, defeat, tie precedence, frozen settlement, and restart.

var failures: int = 0
var game: Node3D
var hunter: Hunter
var monster: FieldMonster
var settled_results: Array[StringName] = []

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
	_expect(game.battle_state == game.BATTLE_RUNNING and not paused, "Starting the exercise enters the running battle state")

	monster.receive_hit(7101, monster.max_health, monster.global_position)
	await process_frame
	_expect(game.battle_state == game.BATTLE_WON and paused, "Monster defeat settles victory and freezes the scene")
	_expect(game.hud.overlay.visible and game.hud.title.text.contains("Hunt complete") and game.hud.objective.text.contains("VICTORY"), "Victory overlay shows the result and restart instruction")
	var frozen_hunter_position := hunter.position
	var frozen_monster_position := monster.position
	await _process_frames(4)
	_expect(hunter.position.is_equal_approx(frozen_hunter_position) and monster.position.is_equal_approx(frozen_monster_position), "Victory settlement freezes both combatants")
	_expect(settled_results == [game.BATTLE_WON] and game.settlement_count == 1, "Victory settles and emits exactly once")

	var reset_event := InputEventAction.new()
	reset_event.action = "reset"
	reset_event.pressed = true
	game._unhandled_input(reset_event)
	await process_frame
	_expect(game.battle_state == game.BATTLE_RUNNING and not paused and not game.hud.overlay.visible, "R restart returns to a running battle and hides the result")
	_expect(hunter.health == hunter.max_health and monster.health == monster.max_health and not hunter.is_defeated and not monster.is_dead, "Restart restores both combatants completely")

	hunter.receive_hit(7201, hunter.max_health, hunter.global_position)
	await process_frame
	_expect(game.battle_state == game.BATTLE_LOST and paused, "Hunter defeat settles loss and freezes the scene")
	_expect(game.hud.title.text.contains("fallen") and game.hud.objective.text.contains("DEFEAT"), "Defeat overlay shows the result and restart instruction")
	_expect(settled_results == [game.BATTLE_WON, game.BATTLE_LOST] and game.settlement_count == 2, "Defeat also settles and emits exactly once")

	game.reset_exercise()
	monster.receive_hit(7301, monster.max_health, monster.global_position)
	hunter.receive_hit(7302, hunter.max_health, hunter.global_position)
	await process_frame
	_expect(monster.is_dead and hunter.is_defeated, "Tie fixture applies both lethal hits in one settlement frame")
	_expect(game.battle_state == game.BATTLE_LOST and paused, "Simultaneous lethal damage deterministically resolves as player defeat")
	_expect(settled_results.back() == game.BATTLE_LOST and game.settlement_count == 3, "Tie settlement emits only the final loss result once")

	game.reset_exercise()
	_expect(game.battle_state == game.BATTLE_RUNNING and game.settlement_count == 3, "Restart clears the round without duplicating prior settlements")

	print("BATTLE FLOW TESTS: %s" % ("PASS" if failures == 0 else "%d FAILURES" % failures))
	paused = false
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func _process_frames(count: int) -> void:
	for frame_index in range(count):
		await process_frame

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		failures += 1
		printerr("FAIL: %s" % message)
