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
	_expect(paused, "The field waits for explicit start")
	game.resume()
	await _frames(12)
	_expect(hunter.is_on_floor(), "Player rests on the ground collision")
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
