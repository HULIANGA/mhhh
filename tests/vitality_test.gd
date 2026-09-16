extends SceneTree
## Verify the player's M3.1 health, hit deduplication, dodge immunity, defeat, and reset contract.

class TestInputSource extends HunterInputSource:
	var frame := HunterInputFrame.new()
	func sample(_viewport: Viewport, _position: Vector3) -> HunterInputFrame:
		return frame
	func clear() -> void:
		frame = HunterInputFrame.new()

var failures: int = 0
var defeat_events: int = 0
var game: Node3D
var hunter: Hunter
var source: TestInputSource

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	hunter = game.get_node("Player")
	game.monster.attacks_enabled = false
	source = TestInputSource.new()
	hunter.add_child(source)
	hunter.input_source = source
	hunter.defeated.connect(_on_hunter_defeated)
	game.resume()
	await _frames(3)

	_expect(hunter.health == hunter.max_health, "Hunter starts at maximum health")
	_expect(game.hud.player_health_bar.value == hunter.max_health, "HUD starts with the hunter's current health")
	_expect(hunter.receive_hit(7001, 25, hunter.global_position), "A new incoming attack is accepted")
	_expect(hunter.health == 75 and game.hud.player_health_bar.value == 75, "Accepted damage updates hunter health and HUD")
	_expect(not hunter.receive_hit(7001, 25, hunter.global_position) and hunter.health == 75, "One incoming attack token cannot damage the hunter twice")

	game.reset_exercise()
	await _frames(2)
	source.frame.dodge.pressed = true
	source.frame.dodge.held = true
	await _frames(1)
	source.frame = HunterInputFrame.new()
	_expect(hunter.is_invulnerable, "Dodge enters its invulnerability window before incoming damage")
	_expect(not hunter.receive_hit(7002, 40, hunter.global_position) and hunter.health == hunter.max_health, "Dodge invulnerability rejects incoming damage")
	await _frames(18)
	_expect(hunter.is_invulnerable, "Extended dodge invulnerability remains active after movement begins recovering")
	await _frames(3)
	_expect(not hunter.is_invulnerable, "Dodge eventually leaves its extended invulnerability window")
	_expect(not hunter.receive_hit(7002, 40, hunter.global_position) and hunter.health == hunter.max_health, "An attack dodged during invulnerability cannot hit later with the same token")
	_expect(hunter.receive_hit(7003, 20, hunter.global_position) and hunter.health == 80, "A different attack can hit after invulnerability ends")

	var defeats_before := defeat_events
	_expect(hunter.receive_hit(7004, 999, hunter.global_position), "Lethal damage is accepted once")
	_expect(hunter.health == 0 and hunter.is_defeated and hunter.action_state == Hunter.STATE_DEFEATED, "Lethal damage puts the hunter into the defeated state")
	_expect(defeat_events == defeats_before + 1, "Defeat emits exactly once for the lethal hit")
	var defeated_position := hunter.position
	source.frame.movement = Vector2.RIGHT
	await _frames(5)
	_expect(hunter.position.is_equal_approx(defeated_position), "A defeated hunter cannot keep moving")
	_expect(not hunter.receive_hit(7005, 10, hunter.global_position) and defeat_events == defeats_before + 1, "Further attacks do not repeat defeat settlement")

	game.reset_exercise()
	await _frames(2)
	_expect(hunter.health == hunter.max_health and not hunter.is_defeated and hunter.action_state == Hunter.STATE_FREE, "Reset restores hunter health and control")
	_expect(game.hud.player_health_bar.value == hunter.max_health, "Reset restores the HUD health display")
	_expect(hunter.receive_hit(7001, 1, hunter.global_position), "Reset clears resolved incoming attack tokens")

	if failures == 0:
		print("VITALITY TESTS: PASS")
	else:
		printerr("VITALITY TESTS: %d FAILURE(S)" % failures)
	quit(failures)

func _on_hunter_defeated() -> void:
	defeat_events += 1

func _frames(count: int) -> void:
	for frame_index in range(count):
		await physics_frame

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		failures += 1
		printerr("FAIL: %s" % message)
