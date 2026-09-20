extends SceneTree
## Verify the M4.6 monster HUD, responsive placement, diagnostics, and restart flow.

var failures: int = 0
var game: Node3D
var monster: FieldMonster

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	monster = game.get_node("FieldMonster")
	var hud = game.hud
	_expect(not hud.monster_health_panel.visible, "Monster health stays hidden before the hunt starts")
	game.resume()
	await process_frame
	_expect(hud.monster_health_panel.visible, "Starting the hunt reveals the top monster health component")
	_expect(hud.monster_health_value.text == "180 / 180" and is_equal_approx(hud.monster_health_bar.value, 180.0), "Top monster health begins at the full current and maximum value")
	monster.receive_hit(4601, 37, monster.global_position)
	_expect(hud.monster_health_value.text == "143 / 180" and is_equal_approx(hud.monster_health_bar.value, 143.0), "Damage updates the top monster health immediately")
	_expect(not _contains_label_3d(monster._presentation), "Monster presentation contains no overhead Label3D")
	monster._flash_time = 0.0
	monster._start_attack(FieldMonster.CHARGE_ATTACK)
	await physics_frame
	await physics_frame
	_expect(monster.debug_attack_id() == &"charge" and monster.debug_animation_name() == &"charge_windup", "Monster exposes attack and animation diagnostics without world text (%s / %s)" % [monster.debug_attack_id(), monster.debug_animation_name()])
	game._physics_process(0.0)
	_expect(hud.debug_label.text.contains("BEAST  attacking / charge / windup") and hud.debug_label.text.contains("ANIM  charge_windup"), "F1 diagnostics include monster state, attack ID, phase, and animation (%s)" % hud.debug_label.text.replace("\n", " | "))
	monster.receive_hit(4602, monster.health, monster.global_position)
	await process_frame
	_expect(game.battle_state == game.BATTLE_WON and is_equal_approx(hud.monster_health_bar.value, 0.0) and hud.monster_health_value.text == "0 / 180", "Settlement freezes the final monster health value")
	game.reset_exercise()
	await physics_frame
	_expect(hud.monster_health_panel.visible and hud.monster_health_value.text == "180 / 180" and is_equal_approx(hud.monster_health_bar.value, 180.0), "Restart restores and shows full monster health")

	var viewport_size := Vector2(1280, 720)
	var panel_center: float = float(hud.monster_health_panel.position.x + hud.monster_health_panel.size.x * 0.5)
	_expect(absf(panel_center - viewport_size.x * 0.5) < 1.0, "At 1280 by 720 the monster health component is centered")
	_expect(hud.monster_health_panel.position.y + hud.monster_health_panel.size.y < hud.feedback.position.y, "Monster health does not overlap centered hit feedback")
	_expect(hud.monster_health_panel.position.x + hud.monster_health_panel.size.x < 1280.0 - 230.0, "Monster health leaves the top-right controls unobstructed")

	print("HUD TESTS: %s" % ("PASS" if failures == 0 else "%d FAILURES" % failures))
	paused = false
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func _contains_label_3d(node: Node) -> bool:
	if node is Label3D:
		return true
	for child: Node in node.get_children():
		if _contains_label_3d(child):
			return true
	return false

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		failures += 1
		printerr("FAIL: %s" % message)
