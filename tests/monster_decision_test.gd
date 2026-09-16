extends SceneTree
## Verify M3.6 deterministic weighted choices, repeat limits, and combat pacing.

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

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	hunter = game.get_node("Player")
	monster = game.get_node("FieldMonster")
	var source := TestInputSource.new()
	hunter.add_child(source)
	hunter.input_source = source
	game.resume()

	_expect(monster._select_attack(2.2) == FieldMonster.SWEEP_ATTACK, "Close distance has an unambiguous sweep choice")
	_expect(monster._select_attack(5.0) == FieldMonster.POUNCE_ATTACK, "Medium distance has an unambiguous pounce choice")
	_expect(monster._select_attack(12.0) == FieldMonster.CHARGE_ATTACK, "Far distance has an unambiguous charge choice")
	_expect(_candidate_count(2.9) == 2 and _candidate_count(7.5) == 2, "Distance transitions expose weighted two-attack choices")

	monster.last_attack_id = &""
	monster.consecutive_attack_count = 0
	monster.set_decision_seed(1407)
	var first_sequence := _selection_sequence(7.5, 12)
	monster.set_decision_seed(1407)
	var repeated_sequence := _selection_sequence(7.5, 12)
	_expect(first_sequence == repeated_sequence, "The same decision seed reproduces the same weighted attack sequence")
	_expect(first_sequence.has(&"pounce") and first_sequence.has(&"charge"), "Weighted transition selection can produce both eligible attacks")

	monster.last_attack_id = &"pounce"
	monster.consecutive_attack_count = monster.maximum_consecutive_attack
	_expect(monster._select_attack(7.5) == FieldMonster.CHARGE_ATTACK, "Two consecutive pounces force the available charge alternative")
	monster.last_attack_id = &"charge"
	monster.consecutive_attack_count = monster.maximum_consecutive_attack
	_expect(monster._select_attack(7.5) == FieldMonster.POUNCE_ATTACK, "Two consecutive charges force the available pounce alternative")

	_prepare_close_encounter()
	monster.last_attack_id = &"sweep"
	monster.consecutive_attack_count = 1
	await _until_attacking()
	_expect(monster._attack_data == FieldMonster.SWEEP_ATTACK and monster.consecutive_attack_count == 2, "Actual attack startup records the consecutive choice")
	await _until_not_attacking()
	_expect(monster.attack_cooldown_left > FieldMonster.SWEEP_ATTACK.cooldown * 1.5, "Repeated attacks receive an extended cooldown")
	await _frames(24)
	_expect(monster.state != FieldMonster.STATE_ATTACKING, "Extended repeat cooldown leaves a reliable close-range counter window")
	await _until_attacking()
	_expect(monster._attack_data == FieldMonster.SWEEP_ATTACK, "Monster resumes attacking after the counter window instead of remaining inactive")

	game.reset_exercise()
	_expect(monster.last_attack_id == &"" and monster.consecutive_attack_count == 0, "Reset clears attack history and restarts the decision sequence")

	print("MONSTER DECISION TESTS: %s" % ("PASS" if failures == 0 else "%d FAILURES" % failures))
	paused = false
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func _candidate_count(distance: float) -> int:
	var count := 0
	for data: MonsterAttackData in [FieldMonster.SWEEP_ATTACK, FieldMonster.POUNCE_ATTACK, FieldMonster.CHARGE_ATTACK]:
		if distance >= data.minimum_range and distance <= data.maximum_range:
			count += 1
	return count

func _selection_sequence(distance: float, count: int) -> Array[StringName]:
	var result: Array[StringName] = []
	for index in range(count):
		result.append(monster._select_attack(distance).attack_id)
	return result

func _prepare_close_encounter() -> void:
	game.reset_exercise()
	monster.attacks_enabled = true
	monster.position = Vector3(5, 0.05, 4)
	monster.rotation = Vector3.ZERO
	monster.velocity = Vector3.ZERO
	hunter.position = Vector3(5, 0.05, 1.8)
	hunter.velocity = Vector3.ZERO

func _until_attacking(maximum_frames: int = 240) -> void:
	for frame_index in range(maximum_frames):
		await physics_frame
		if monster.state == FieldMonster.STATE_ATTACKING:
			return
	_expect(false, "Monster starts an attack within the pacing limit")

func _until_not_attacking(maximum_frames: int = 300) -> void:
	for frame_index in range(maximum_frames):
		await physics_frame
		if monster.state != FieldMonster.STATE_ATTACKING:
			return
	_expect(false, "Monster finishes its attack within the pacing limit")

func _frames(count: int) -> void:
	for frame_index in range(count):
		await physics_frame

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		failures += 1
		printerr("FAIL: %s" % message)
