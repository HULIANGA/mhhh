extends SceneTree
## Exercise the real scene, input actions, and physics bodies, not duplicate formulas.

var failures: int = 0
var game: Node3D
var hunter: Hunter

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	hunter = game.get_node("Player")
	game.monster.attacks_enabled = false
	_expect(paused, "The field waits for explicit start")
	var waiting_monster_position: Vector3 = game.monster.global_position
	await _frames(60)
	_expect(game.monster.global_position.is_equal_approx(waiting_monster_position), "Monster stays at spawn while the start menu is open")
	_expect(game.monster.state == FieldMonster.STATE_IDLE, "Monster AI stays idle before the exercise starts")
	game.resume()
	await _frames(12)
	_expect(hunter.is_on_floor(), "Player rests on the ground collision")
	game.monster._start_attack(FieldMonster.CHARGE_ATTACK)
	await _frames(1)
	game.hud.monster_ai_button.pressed.emit()
	var stopped_monster_position: Vector3 = game.monster.global_position
	await _frames(60)
	_expect(not game.monster_ai_enabled and not game.monster.ai_enabled, "Monster AI button disables the field beast")
	_expect(game.monster.global_position.is_equal_approx(stopped_monster_position) and game.monster.velocity.is_zero_approx(), "Disabled monster AI stops movement")
	_expect(game.monster.state == FieldMonster.STATE_IDLE and game.monster._attack_data == null and game.monster.attack_phase == &"ready", "Disabling monster AI cancels an active attack")
	_expect(game.hud.monster_ai_button.text.contains("Enable"), "Monster AI button clearly offers to resume AI")
	_expect(game.hud.monster_ai_button.focus_mode == Control.FOCUS_NONE, "Monster AI button cannot capture the dodge key after a mouse click")
	game.hud.monster_ai_button.pressed.emit()
	var resumed_monster_position: Vector3 = game.monster.global_position
	await _frames(30)
	_expect(game.monster_ai_enabled and game.monster.ai_enabled and game.monster.global_position.distance_to(resumed_monster_position) > 0.5, "Re-enabled monster AI resumes pursuit")
	_expect(game.hud.monster_ai_button.text.contains("Stop"), "Monster AI button reflects the active state")
	var straight := await _walk(["move_right"], 120)
	var diagonal := await _walk(["move_right", "move_up"], 120)
	print("Measured distance: straight=%.3f m, diagonal=%.3f m" % [straight, diagonal])
	_expect(straight > 9.5 and straight < 10.7, "Movement travels the configured distance")
	_expect(absf(straight - diagonal) < 0.12, "Diagonal movement is not faster")
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		game.reset_exercise()
		Input.action_press(action)
		await _frames(360)
		Input.action_release(action)
		_expect(absf(hunter.position.x) < 16.8 and absf(hunter.position.z) < 13.8, "World boundary blocks " + action)
	game.reset_exercise()
	Input.action_press("move_right")
	await _frames(20)
	game.pause()
	var paused_position := hunter.position
	await _frames(30)
	_expect(hunter.position.is_equal_approx(paused_position), "Paused physics preserves player position")
	_expect(not Input.is_action_pressed("move_right"), "Pause clears held movement input")
	game.resume()
	await _frames(20)
	_expect(hunter.position.distance_to(paused_position) < 0.6, "Resume does not retain a stuck movement key")
	for i in range(10):
		game.reset_exercise()
		await _frames(2)
		_expect(hunter.travel_distance < 0.01 and game.training_dummy.health == game.training_dummy.max_health and game.monster.health == game.monster.max_health, "Reset restores the combat exercise #%d" % i)
		_expect(game.get_child_count() == 5, "Reset keeps the scene population stable #%d" % i)
	print("MOVEMENT TESTS: %s" % ("PASS" if failures == 0 else "%d FAILURES" % failures))
	paused = false
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func _walk(actions: Array, count: int) -> float:
	game.reset_exercise()
	await _frames(8)
	var initial := hunter.position
	for action: String in actions:
		Input.action_press(action)
	await _frames(count)
	for action: String in actions:
		Input.action_release(action)
	return Vector2(hunter.position.x - initial.x, hunter.position.z - initial.z).length()

func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)
