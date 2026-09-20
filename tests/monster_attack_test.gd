extends SceneTree
## Verify the M3.3 shared monster attack phases and first horn sweep.

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
var observed_phases: Array[StringName] = []

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
	monster.attack_phase_changed.connect(func(_attack_name: String, phase: StringName): observed_phases.append(phase))
	game.resume()

	_prepare_encounter(Vector3(0, 0.05, -2.2))
	await _until_phase(FieldMonster.PHASE_WINDUP)
	_expect(monster.state == FieldMonster.STATE_ATTACKING and monster.attack_phase == FieldMonster.PHASE_WINDUP, "Entering sweep range starts the shared windup phase")
	_expect(not _contains_label_3d(monster._presentation), "Normal play has no overhead monster status text")
	await _until_phase(FieldMonster.PHASE_ACTIVE)
	_expect(monster._presentation.current_animation == &"sweep", "Sweep silhouette remains the active-frame warning without phase text")
	_expect(hunter.health == hunter.max_health, "Visible active motion appears briefly before horn probes can deal damage")
	await _until_phase(FieldMonster.PHASE_RECOVERY)
	_expect(observed_phases == [FieldMonster.PHASE_WINDUP, FieldMonster.PHASE_ACTIVE, FieldMonster.PHASE_RECOVERY], "Sweep advances through windup, active, and recovery in order")
	_expect(hunter.health == hunter.max_health - FieldMonster.SWEEP_ATTACK.damage, "Sweep applies its configured damage exactly once across all active frames")
	_expect(hunter._presentation.has_active_hit_feedback(), "Accepted sweep enters the hunter hit presentation state")
	await _frames(18)
	_expect(hunter.health == hunter.max_health - FieldMonster.SWEEP_ATTACK.damage, "One sweep cannot damage the hunter repeatedly")

	_prepare_encounter(Vector3(0, 0.05, -2.2))
	await _until_phase(FieldMonster.PHASE_WINDUP)
	await _frames(16)
	hunter.position = Vector3(2.2, 0.05, 0)
	while monster._attack_elapsed < FieldMonster.SWEEP_ATTACK.windup - 0.07:
		await physics_frame
	var aimed_direction := monster._forward()
	hunter.position = monster.position - aimed_direction * 2.2
	hunter.position.y = 0.05
	var aimed_angle := atan2(-aimed_direction.x, -aimed_direction.z)
	while monster._attack_elapsed < FieldMonster.SWEEP_ATTACK.windup - 0.005:
		await physics_frame
		# Keep the already-captured aim while giving the teleported physics body
		# enough ticks to update its broadphase position for the probe assertion.
		monster.rotation.y = aimed_angle
	await _until_phase(FieldMonster.PHASE_ACTIVE)
	var locked_direction := monster._locked_attack_direction
	await _until_phase(FieldMonster.PHASE_RECOVERY)
	_expect(locked_direction.dot(aimed_direction) > 0.995 and monster._forward().dot(locked_direction) > 0.995, "Sweep locks its direction when windup ends and cannot track during active frames")
	_expect(hunter.health == hunter.max_health, "Leaving the animated horn path avoids damage")

	_prepare_encounter(Vector3(0, 0.05, -2.2))
	await _until_phase(FieldMonster.PHASE_ACTIVE)
	_expect(hunter.health == hunter.max_health, "Hunter is not hit on the first visible red frame")
	source.frame.dodge.pressed = true
	source.frame.dodge.held = true
	await _frames(1)
	source.frame = HunterInputFrame.new()
	_expect(hunter.is_invulnerable, "Dodge started on the red warning overlaps the delayed hit window")
	await _until_phase(FieldMonster.PHASE_RECOVERY)
	await _frames(14)
	_expect(hunter.health == hunter.max_health, "Dodge invulnerability fully avoids the sweep without a delayed hit")
	_expect(not hunter._presentation.has_active_hit_feedback(), "A successfully dodged sweep does not play the hunter hit reaction")

	var monster_health_before := monster.health
	hunter.position = monster.position + Vector3(0, 0, 2.2)
	hunter._presentation.set_facing_y(0.0)
	hunter.velocity = Vector3.ZERO
	await _tap_attack()
	await _frames(24)
	_expect(monster.health == monster_health_before - Hunter.LIGHT_ACTION.damage, "Recovery leaves a safe counterattack window for the hunter")

	print("MONSTER ATTACK TESTS: %s" % ("PASS" if failures == 0 else "%d FAILURES" % failures))
	paused = false
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func _prepare_encounter(hunter_position: Vector3) -> void:
	game.reset_exercise()
	observed_phases.clear()
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

func _contains_label_3d(node: Node) -> bool:
	if node is Label3D:
		return true
	for child: Node in node.get_children():
		if _contains_label_3d(child):
			return true
	return false
