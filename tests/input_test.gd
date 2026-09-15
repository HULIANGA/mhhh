extends SceneTree

class TestInputSource extends HunterInputSource:
	var frame := HunterInputFrame.new()
	var clear_count: int = 0
	func sample(_viewport: Viewport, _position: Vector3) -> HunterInputFrame:
		return frame
	func clear() -> void:
		clear_count += 1
		frame = HunterInputFrame.new()

var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var hunter: Hunter = game.get_node("Player")
	var keyboard: HunterInputSource = hunter.input_source
	# Exercise button transitions while gameplay is paused, so only this test samples.
	keyboard.clear()
	keyboard.sample(root, hunter.position)
	# Start on an established physics tick, after initial cancellation has expired.
	await _frames(2)
	Input.action_press("charge")
	await _frames(1)
	var frame := keyboard.sample(root, hunter.position)
	_expect(frame.charge.pressed and frame.charge.held and not frame.charge.released, "Charge exposes press and hold")
	await _frames(3)
	frame = keyboard.sample(root, hunter.position)
	_expect(frame.charge.held and not frame.charge.pressed, "Holding does not repeatedly press")
	Input.action_release("charge")
	await _frames(1)
	frame = keyboard.sample(root, hunter.position)
	_expect(frame.charge.released and not frame.charge.held, "Charge exposes release")
	Input.action_press("attack")
	Input.action_press("dodge")
	frame = keyboard.sample(root, hunter.position)
	_expect(frame.attack.held and frame.dodge.held and not frame.charge.held, "Gameplay actions remain independent")
	keyboard.clear()
	frame = keyboard.sample(root, hunter.position)
	_expect(not frame.attack.held and not frame.attack.released and not frame.dodge.released and not frame.charge.released, "Clear cancels input without generating a release action")
	await _frames(3)
	frame = keyboard.sample(root, hunter.position)
	_expect(not frame.charge.pressed and not frame.charge.held and not frame.charge.released, "No stale charge after cancellation")
	# No real gamepad: inject the same normalized intent a future adapter would supply.
	var source := TestInputSource.new()
	hunter.add_child(source)
	hunter.input_source = source
	game.resume()
	source.frame.movement = Vector2(0.5, 0)
	source.frame.aim_direction = Vector3.RIGHT
	await _frames(45)
	_expect(absf(hunter.velocity.x - hunter.move_speed * 0.5) < 0.01, "Analog magnitude controls movement speed")
	_expect(absf(angle_difference(hunter.visuals.rotation.y, -PI / 2.0)) < 0.01, "World aim works without a mouse")
	source.frame.movement = Vector2(4, 4)
	await _frames(20)
	_expect(absf(Vector2(hunter.velocity.x, hunter.velocity.z).length() - hunter.move_speed) < 0.01, "Oversized input cannot exceed maximum speed")
	var facing := hunter.visuals.rotation.y
	source.frame.aim_direction = Vector3.ZERO
	await _frames(10)
	_expect(is_equal_approx(hunter.visuals.rotation.y, facing), "Neutral aim retains the last facing")
	var before_clear := source.clear_count
	game.pause()
	_expect(source.clear_count == before_clear + 1 and source.frame.movement == Vector2.ZERO, "Pause clears an injected input source")
	game.resume()
	await _frames(4)
	_expect(hunter.velocity.is_zero_approx(), "Resume has no stale movement")
	source.frame.movement = Vector2.LEFT
	game.reset_exercise()
	_expect(source.frame.movement == Vector2.ZERO and hunter.input_frame.movement == Vector2.ZERO, "Restart clears source and consumed input")
	print("INPUT TESTS: %s" % ("PASS" if failures == 0 else "%d FAILURES" % failures))
	paused = false
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)
