extends SceneTree
## Exercise combat through the same per-tick input frame consumed by the real player.

class TestInputSource extends HunterInputSource:
	var frame := HunterInputFrame.new()
	func sample(_viewport: Viewport, _position: Vector3) -> HunterInputFrame:
		return frame
	func clear() -> void:
		frame = HunterInputFrame.new()

var failures: int = 0
var game: Node3D
var hunter: Hunter
var target: TrainingDummy
var source: TestInputSource

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	hunter = game.get_node("Player")
	game.monster.attacks_enabled = false
	target = game.get_node("Arena/TrainingDummy")
	source = TestInputSource.new()
	hunter.add_child(source)
	hunter.input_source = source
	game.resume()
	await _position_for_combat()

	var presentation := hunter.get_node("Presentation") as HunterPresentation
	var sword_pivot: Node3D = presentation.weapon_socket
	var grip_origin := sword_pivot.position
	_expect(presentation.blade_base != null and presentation.blade_tip != null, "Weapon animation uses the stable blade socket contract")
	var ready_blade_axis := sword_pivot.basis.y.normalized()
	_expect(ready_blade_axis.z < -0.9 and ready_blade_axis.y > 0.3, "Sword tip points forward and slightly upward while ready")
	_expect(sword_pivot.basis.x.normalized().dot(Vector3.DOWN) > 0.85 and sword_pivot.basis.x.normalized().x < -0.1, "Sword blade's upper direction leans slightly right while ready")
	var rear_charge_basis := Basis(presentation.fore_aft_pose(HunterPresentation.POSE_CHARGE_BACK))
	var rear_blade_axis := HunterPresentation.POSE_CHARGE_BACK.normalized()
	var rear_base_edge := rear_blade_axis.cross(Vector3.RIGHT).normalized()
	var expected_right_edge := (rear_base_edge * cos(HunterPresentation.BLADE_TOP_RIGHT_TILT) - Vector3.RIGHT * sin(HunterPresentation.BLADE_TOP_RIGHT_TILT)).normalized()
	_expect(rear_charge_basis.x.normalized().dot(expected_right_edge) > 0.999, "Fore-aft pose accepts the ready-state right tilt")
	var full_charge_basis := Basis(presentation.charge_pose_at(Hunter.CHARGE_ACTIONS[1].charge_threshold, Hunter.CHARGE_ACTIONS[1].charge_threshold))
	var expected_left_edge := (rear_base_edge * cos(HunterPresentation.BLADE_TOP_LEFT_TILT) - Vector3.RIGHT * sin(HunterPresentation.BLADE_TOP_LEFT_TILT)).normalized()
	_expect(full_charge_basis.x.normalized().dot(expected_left_edge) > 0.999, "Raising the charged sword finishes with its upper direction tilted left")
	var strike_start_basis := Basis(presentation.charged_strike_pose(0.0))
	var strike_finish_basis := Basis(presentation.charged_strike_pose(1.0))
	var finish_blade_axis := HunterPresentation.POSE_STRAIGHT_DOWN.normalized()
	var finish_base_edge := finish_blade_axis.cross(Vector3.RIGHT).normalized()
	var expected_finish_edge := (finish_base_edge * cos(HunterPresentation.BLADE_TOP_RIGHT_TILT) - Vector3.RIGHT * sin(HunterPresentation.BLADE_TOP_RIGHT_TILT)).normalized()
	_expect(strike_start_basis.x.normalized().dot(expected_left_edge) > 0.999 and strike_finish_basis.x.normalized().dot(expected_finish_edge) > 0.999, "Charged cleave rolls smoothly from a left tilt back to a right tilt")
	var rear_z := HunterPresentation.POSE_CHARGE_BACK.normalized().z
	var leaving_rear_z := presentation.charged_strike_direction(HunterPresentation.CHARGE_STRIKE_APEX * 0.5).z
	var apex_z := presentation.charged_strike_direction(HunterPresentation.CHARGE_STRIKE_APEX).z
	var forward_z := presentation.charged_strike_direction(0.65).z
	var finish_z := presentation.charged_strike_direction(1.0).z
	_expect(leaving_rear_z < rear_z and absf(apex_z) < 0.001 and forward_z < 0.0 and finish_z < -0.7, "Charged cleave travels from the rear over the head and finishes forward")
	await _tap("attack")
	var minimum_light_edge_alignment := 1.0
	for frame_index in range(10):
		await physics_frame
		var blade_axis := sword_pivot.basis.y.normalized()
		var edge_hint := Vector3.DOWN * cos(HunterPresentation.BLADE_TOP_RIGHT_TILT) - Vector3.RIGHT * sin(HunterPresentation.BLADE_TOP_RIGHT_TILT)
		var expected_edge := (edge_hint - blade_axis * edge_hint.dot(blade_axis)).normalized()
		minimum_light_edge_alignment = minf(minimum_light_edge_alignment, sword_pivot.basis.x.normalized().dot(expected_edge))
	_expect(minimum_light_edge_alignment > 0.999, "Light attack keeps a stable cutting-edge orientation without axial rotation")
	_expect(sword_pivot.position.is_equal_approx(grip_origin), "Attack rotation introduces no local offset from the right-hand weapon attachment")
	await _frames(35)
	_expect(target.hit_count == 1 and target.damage_received == 16, "One attack deals damage once across every active frame")
	_expect(hunter.action_state == Hunter.STATE_FREE, "Light attack returns to ready after recovery")

	game.reset_exercise()
	await _position_for_combat()
	await _tap("attack")
	await _frames(10)
	source.frame.charge.pressed = true
	source.frame.charge.held = true
	await _frames(1)
	_expect(hunter.action_state == Hunter.STATE_LIGHT, "Buffered charge does not interrupt the current attack")
	source.frame.charge.pressed = false
	var saw_buffered_charge := false
	for frame_index in range(60):
		await physics_frame
		saw_buffered_charge = saw_buffered_charge or hunter.action_state == Hunter.STATE_CHARGING
	_expect(saw_buffered_charge and target.hit_count == 1, "Held charge input starts only after the preceding attack fully completes")
	source.frame = HunterInputFrame.new()
	source.frame.charge.released = true
	await _frames(1)
	source.frame = HunterInputFrame.new()
	await _frames(20)

	game.reset_exercise()
	await _position_for_combat()
	await _tap("attack")
	await _frames(10)
	source.frame.charge.pressed = true
	source.frame.charge.held = true
	await _frames(1)
	source.frame = HunterInputFrame.new()
	source.frame.charge.released = true
	await _frames(1)
	source.frame = HunterInputFrame.new()
	await _frames(50)
	_expect(hunter.action_state == Hunter.STATE_FREE, "Releasing charge before the preceding action completes cancels the buffered input")

	game.reset_exercise()
	await _position_for_combat()
	await _tap("attack")
	await _frames(8)
	await _tap("attack")
	await _frames(30)
	await _tap("attack")
	await _frames(100)
	_expect(target.hit_count == 3, "Buffered presses execute exactly three complete light attacks")
	_expect(target.damage_received == 48, "Repeated light attacks use the single configured attack")
	_expect(hunter.action_state == Hunter.STATE_FREE and hunter.combo_step == 0, "Buffered light attacks stop after the requested count")

	game.reset_exercise()
	await _position_for_combat()
	sword_pivot = presentation.weapon_socket
	var previous_token := hunter._attack_token
	var previous_start_frame := -1
	var minimum_start_gap := 10000
	source.frame.attack.pressed = true
	source.frame.attack.held = true
	for frame_index in range(260):
		await physics_frame
		source.frame.attack.pressed = false
		if hunter._attack_token != previous_token:
			if previous_start_frame >= 0:
				minimum_start_gap = mini(minimum_start_gap, frame_index - previous_start_frame)
			previous_start_frame = frame_index
			previous_token = hunter._attack_token
	_expect(target.hit_count >= 5, "Holding attack automatically cycles through repeated light attacks")
	_expect(minimum_start_gap >= floori(Hunter.LIGHT_ACTION.duration() * 60.0) - 1, "Automatic repeat waits for the full attack and sheathing animation")
	source.frame = HunterInputFrame.new()
	await _frames(150)
	var hits_after_release := target.hit_count
	await _frames(90)
	_expect(hunter.action_state == Hunter.STATE_FREE and target.hit_count == hits_after_release, "Releasing held attack finishes the buffered animation and then stops")

	game.reset_exercise()
	await _position_for_combat()
	source.frame.attack.pressed = true
	source.frame.attack.held = true
	await _frames(30)
	source.frame.attack.pressed = false
	source.frame.dodge.pressed = true
	await _frames(1)
	source.frame.dodge.pressed = false
	var saw_dodge_after_attack := false
	for frame_index in range(100):
		await physics_frame
		saw_dodge_after_attack = saw_dodge_after_attack or hunter.action_state == Hunter.STATE_DODGING
	_expect(saw_dodge_after_attack, "Dodge pressed during held attack runs after the current full attack animation")
	var hits_after_dodge := target.hit_count
	await _frames(100)
	_expect(hunter.action_state == Hunter.STATE_FREE and target.hit_count == hits_after_dodge, "Dodge cancels held auto-repeat until a new press")
	source.frame = HunterInputFrame.new()
	await _frames(2)
	source.frame.attack.pressed = true
	source.frame.attack.held = true
	await _frames(40)
	_expect(target.hit_count > hits_after_dodge, "Pressing and holding again re-enables automatic light attacks")
	source.frame = HunterInputFrame.new()

	game.reset_exercise()
	await _position_for_combat()
	await _tap("attack")
	var stamina_before := hunter.stamina
	source.frame.charge.pressed = true
	source.frame.dodge.pressed = true
	await _frames(1)
	source.frame = HunterInputFrame.new()
	_expect(hunter.action_state == Hunter.STATE_LIGHT and is_equal_approx(hunter.stamina, stamina_before), "Attack windup is not interrupted immediately by dodge")
	await _frames(45)

	game.reset_exercise()
	await _position_for_combat()
	hunter.stamina = 23.0
	await _tap("dodge")
	_expect(hunter.action_state == Hunter.STATE_FREE, "Insufficient stamina blocks dodge startup")
	hunter.stamina = 29.0
	await _tap("charge")
	_expect(hunter.action_state == Hunter.STATE_FREE, "Insufficient stamina blocks charge startup")

	game.reset_exercise()
	await _position_for_combat()
	source.frame.movement = Vector2.RIGHT
	source.frame.dodge.pressed = true
	source.frame.dodge.held = true
	await _frames(1)
	source.frame = HunterInputFrame.new()
	_expect(hunter.action_state == Hunter.STATE_DODGING and hunter.is_invulnerable, "Dodge starts with an invulnerable window")
	_expect(absf(hunter.stamina - 76.0) < 0.1, "Dodge spends stamina once at startup")
	await _frames(18)
	_expect(hunter.action_state == Hunter.STATE_DODGING and hunter.is_invulnerable, "Extended invulnerability overlaps the beginning of dodge recovery")
	await _frames(4)
	_expect(hunter.action_state == Hunter.STATE_DODGING and not hunter.is_invulnerable, "Late dodge recovery is no longer invulnerable")
	await _frames(16)
	_expect(hunter.action_state == Hunter.STATE_FREE, "Dodge recovery returns to ready")

	game.reset_exercise()
	await _position_for_combat()
	source.frame.charge.pressed = true
	source.frame.charge.held = true
	await _frames(1)
	_expect(hunter.stamina < 100.0 and hunter.stamina > 99.0, "Charge begins with a small continuous stamina drain instead of spending 30 at startup")
	source.frame = HunterInputFrame.new()
	source.frame.charge.held = true
	await _frames(15)
	_expect(hunter.stamina < 96.0 and hunter.stamina > 92.0, "Holding charge drains stamina gradually over time")
	var early_release_pose := sword_pivot.quaternion
	var early_distance_to_ready := early_release_pose.angle_to(presentation.rest_pose())
	source.frame = HunterInputFrame.new()
	source.frame.charge.released = true
	await _frames(1)
	_expect(hunter.stamina > 90.0 and hunter.stamina < 99.0, "Early release only keeps the stamina drained while charging")
	_expect(hunter.action_state == Hunter.STATE_CHARGE_CANCEL and early_release_pose.angle_to(sword_pivot.quaternion) < 0.15, "Early release starts a continuous return from the current charge pose")
	source.frame = HunterInputFrame.new()
	await _frames(5)
	_expect(sword_pivot.quaternion.angle_to(presentation.rest_pose()) < early_distance_to_ready, "Cancelled charge animates progressively back toward ready")
	await _frames(70)
	_expect(hunter.action_state == Hunter.STATE_FREE and target.hit_count == 0, "Releasing before tier I returns to ready without attacking")

	game.reset_exercise()
	await _position_for_combat()
	source.frame.charge.pressed = true
	source.frame.charge.held = true
	await _frames(1)
	source.frame.charge.pressed = false
	var maximum_charge_lateral := 0.0
	for frame_index in range(35):
		await physics_frame
		maximum_charge_lateral = maxf(maximum_charge_lateral, absf(sword_pivot.basis.y.normalized().x))
	_expect(hunter.charge_tier == 1, "Holding past the first threshold reaches charge tier I")
	var pose_before_release := sword_pivot.quaternion
	var release_blade_z := sword_pivot.basis.y.normalized().z
	source.frame.charge.held = false
	source.frame.charge.released = true
	await _frames(1)
	_expect(pose_before_release.angle_to(sword_pivot.quaternion) < 0.15, "Tier-I release animation starts continuously from the current sword pose")
	source.frame = HunterInputFrame.new()
	var saw_forward_strike := false
	var maximum_tier_one_windup_z := release_blade_z
	for frame_index in range(70):
		await physics_frame
		var blade_axis := sword_pivot.basis.y.normalized()
		if hunter.action_state == Hunter.STATE_CHARGE_RELEASE and hunter.action_phase in [&"windup", &"active"]:
			maximum_charge_lateral = maxf(maximum_charge_lateral, absf(blade_axis.x))
		if hunter.action_state == Hunter.STATE_CHARGE_RELEASE and hunter.action_phase == &"windup":
			maximum_tier_one_windup_z = maxf(maximum_tier_one_windup_z, blade_axis.z)
		if hunter.action_state == Hunter.STATE_CHARGE_RELEASE and hunter.action_phase == &"active":
			saw_forward_strike = saw_forward_strike or blade_axis.z < -0.7
	_expect(maximum_tier_one_windup_z < 0.1, "Tier-I cleave moves directly from the released pose toward the overhead apex without visiting full charge")
	_expect(maximum_charge_lateral < 0.001, "Charge windup and active cleave stay in the straight fore-aft plane")
	_expect(saw_forward_strike, "Charged cleave strikes down toward the straight-ahead direction")
	_expect(target.hit_count == 1 and target.damage_received == 35, "Releasing after tier I performs the tier-I charged cleave")

	game.reset_exercise()
	await _position_for_combat()
	source.frame.charge.pressed = true
	source.frame.charge.held = true
	await _frames(1)
	source.frame.charge.pressed = false
	await _frames(90)
	_expect(absf(hunter.stamina - 70.0) < 0.1, "A full charge drains 30 stamina in total")
	source.frame = HunterInputFrame.new()
	await _frames(80)
	_expect(target.hit_count == 1 and target.damage_received == 60, "Full charge auto-releases the tier-II cleave")

	game.reset_exercise()
	await _position_for_combat()
	source.frame.charge.pressed = true
	source.frame.charge.held = true
	await _frames(1)
	source.frame = HunterInputFrame.new()
	source.frame.dodge.pressed = true
	await _frames(1)
	source.frame = HunterInputFrame.new()
	_expect(hunter.action_state == Hunter.STATE_DODGING, "Dodge cancels an unfinished charge")
	_expect(hunter.stamina < 76.0 and hunter.stamina > 75.0, "Charge cancellation keeps the partial drain and also pays the dodge cost")
	await _frames(60)
	_expect(target.hit_count == 0, "Cancelled charge never creates a hit")

	game.reset_exercise()
	await _position_for_combat()
	source.frame.charge.pressed = true
	source.frame.charge.held = true
	await _frames(1)
	game.pause()
	_expect(hunter.action_state == Hunter.STATE_FREE, "Pausing cancels held charge without releasing an attack")
	game.resume()
	await _frames(100)
	_expect(target.hit_count == 0, "Resume cannot create a stale charge release")

	target.reset_target()
	var every_hit_accepted := true
	for index in range(10):
		every_hit_accepted = target.receive_hit(1000 + index, 35, target.global_position) and every_hit_accepted
	_expect(every_hit_accepted and target.hit_count == 10, "Training post keeps accepting new attacks after durability reaches zero")
	_expect(target.damage_received == 350 and target.health == 135, "Broken training post rebuilds on the next attack and continues tracking damage")
	_expect(not target.receive_hit(1009, 35, target.global_position), "Rebuilt training post still rejects a duplicate attack token")

	print("COMBAT TESTS: %s" % ("PASS" if failures == 0 else "%d FAILURES" % failures))
	paused = false
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func _position_for_combat() -> void:
	hunter.position = Vector3(0, 0.05, 2.2)
	hunter.velocity = Vector3.ZERO
	hunter._presentation.set_facing_y(0.0)
	source.frame = HunterInputFrame.new()
	await _frames(4)

func _tap(button: String) -> void:
	var state: HunterInputFrame.ButtonState = source.frame.get(button)
	state.pressed = true
	state.held = true
	await _frames(1)
	source.frame = HunterInputFrame.new()
	await _frames(1)

func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)
