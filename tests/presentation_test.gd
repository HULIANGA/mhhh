extends SceneTree
## Verify the M4.2 presentation boundaries and stable gameplay sockets.

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var hunter: Hunter = game.get_node("Player")
	var monster: FieldMonster = game.get_node("FieldMonster")
	var hunter_presentation := hunter.get_node("Presentation") as HunterPresentation
	var monster_presentation := monster.get_node("Presentation") as MonsterPresentation
	_expect(hunter_presentation != null, "Hunter owns an independent presentation adapter")
	_expect(monster_presentation != null, "Monster owns an independent presentation adapter")
	_expect(hunter_presentation.blade_base != null and hunter_presentation.blade_tip != null, "Hunter exposes blade sockets")
	_expect(monster_presentation.left_horn_base != null and monster_presentation.left_horn_tip != null, "Monster exposes left horn sockets")
	_expect(monster_presentation.right_horn_base != null and monster_presentation.right_horn_tip != null, "Monster exposes right horn sockets")
	_expect(monster_presentation.body_center != null and monster_presentation.head_front != null, "Monster exposes model-sized motion probe sockets")
	_expect(hunter_presentation.blade_base.is_inside_tree(), "Blade sockets are attached to the presentation model")
	_expect(hunter_presentation.weapon_model != null and hunter_presentation.weapon_model.scene_file_path.ends_with("greatsword.glb"), "Hunter uses the authored greatsword GLB")
	_expect(hunter_presentation.weapon_attachment != null and hunter_presentation.weapon_attachment.bone_name == "WeaponSocket", "Greatsword is attached to the right-hand WeaponSocket bone")
	_expect(hunter_presentation.weapon_model.get_parent() == hunter_presentation.weapon_attachment, "Greatsword follows the skeleton bone attachment")
	_expect(hunter_presentation.hunter_model != null and hunter_presentation.hunter_model.scene_file_path.ends_with("hunter.glb"), "Hunter uses the authored armored hunter GLB")
	_expect(_find_type(hunter_presentation.hunter_model, Skeleton3D) != null, "Hunter presentation retains the imported humanoid skeleton")
	_expect(_find_type(hunter_presentation.hunter_model, AnimationPlayer) != null, "Hunter presentation retains the imported action library")
	_expect(hunter_presentation.current_animation == &"idle", "Hunter presentation initializes in its authored idle pose")
	_expect(hunter_presentation.weapon_model.find_child("PlaceholderSword", true, false) == null, "Programmatic placeholder sword is no longer present")
	_expect(hunter_presentation.visuals.find_child("ChestArmor", true, false) != null and hunter_presentation.visuals.find_child("HairCap", true, false) != null, "Authored armor and silver hair replace the programmatic body")
	_expect(monster_presentation.left_horn_tip.is_inside_tree(), "Horn sockets are attached to the presentation model")
	var blade_length := hunter_presentation.blade_base.global_position.distance_to(hunter_presentation.blade_tip.global_position)
	var left_horn_length := monster_presentation.left_horn_base.global_position.distance_to(monster_presentation.left_horn_tip.global_position)
	_expect(is_equal_approx(blade_length, 1.52) and left_horn_length > 0.6, "Authored sockets describe the visible weapon and horn paths")
	_expect(monster_presentation.model_scale > 1.0, "Monster presentation owns its larger visual scale")
	hunter_presentation.animate_walk(0.016, hunter.move_speed, hunter.move_speed)
	_expect(hunter_presentation.current_animation == &"run", "Movement speed selects the authored run loop")
	hunter_presentation.animate_action(&"light_attack", &"active", 0.25, 0.0, 0.0, 0, Hunter.LIGHT_ACTION, Hunter.CHARGE_ACTIONS[0].charge_threshold, Hunter.CHARGE_ACTIONS[1].charge_threshold, Hunter.CHARGE_CANCEL_DURATION, Hunter.DODGE_ACTION.duration())
	_expect(hunter_presentation.current_animation == &"light_attack", "Light attack logic samples the matching authored action")
	hunter_presentation.animate_action(&"charging", &"windup", 0.0, 0.15, 0.0, 0, null, Hunter.CHARGE_ACTIONS[0].charge_threshold, Hunter.CHARGE_ACTIONS[1].charge_threshold, Hunter.CHARGE_CANCEL_DURATION, Hunter.DODGE_ACTION.duration())
	_expect(hunter_presentation.current_animation == &"charge_enter", "Early charge samples the authored entry action")
	var threshold := Hunter.CHARGE_ACTIONS[0].charge_threshold
	hunter_presentation.animate_action(&"charging", &"windup", 0.0, threshold - 0.001, 0.0, 0, null, threshold, Hunter.CHARGE_ACTIONS[1].charge_threshold, Hunter.CHARGE_CANCEL_DURATION, Hunter.DODGE_ACTION.duration())
	var blade_before_threshold := (hunter_presentation.blade_tip.global_position - hunter_presentation.blade_base.global_position).normalized()
	var tip_before_threshold := hunter_presentation.blade_tip.global_position
	hunter_presentation.animate_action(&"charging", &"windup", 0.0, threshold, 0.0, 1, null, threshold, Hunter.CHARGE_ACTIONS[1].charge_threshold, Hunter.CHARGE_CANCEL_DURATION, Hunter.DODGE_ACTION.duration())
	_expect(hunter_presentation.current_animation == &"charge_hold", "Charge tier I selects the authored hold action")
	var blade_at_threshold := (hunter_presentation.blade_tip.global_position - hunter_presentation.blade_base.global_position).normalized()
	var tip_at_threshold := hunter_presentation.blade_tip.global_position
	_expect(blade_before_threshold.angle_to(blade_at_threshold) < 0.08 and tip_before_threshold.distance_to(tip_at_threshold) < 0.08, "Charge entry transitions to its hold pose without teleporting the sword")
	hunter_presentation.animate_action(&"charge_release", &"active", 0.2, 0.0, Hunter.CHARGE_ACTIONS[1].charge_threshold, 2, Hunter.CHARGE_ACTIONS[1], threshold, Hunter.CHARGE_ACTIONS[1].charge_threshold, Hunter.CHARGE_CANCEL_DURATION, Hunter.DODGE_ACTION.duration())
	_expect(hunter_presentation.current_animation == &"charge_release_2", "Full charge selects the tier-II release action")
	hunter_presentation.animate_action(&"dodging", &"invulnerable", 0.1, 0.0, 0.0, 0, Hunter.DODGE_ACTION, threshold, Hunter.CHARGE_ACTIONS[1].charge_threshold, Hunter.CHARGE_CANCEL_DURATION, Hunter.DODGE_ACTION.duration())
	_expect(hunter_presentation.current_animation == &"dodge", "Dodge logic samples the authored in-place roll")
	hunter_presentation.start_hit_feedback(Vector3.ZERO, Vector3.FORWARD)
	hunter_presentation.update_hit_feedback(0.05, false)
	_expect(hunter_presentation.current_animation == &"hit", "Accepted damage selects the authored hit reaction")
	hunter_presentation.play_defeated()
	_expect(hunter_presentation.current_animation == &"defeated", "Defeat selects and holds the authored down pose")
	hunter_presentation.reset_pose()
	_expect(hunter_presentation.current_animation == &"idle" and not hunter_presentation.has_active_hit_feedback(), "Reset clears animation residue and restores idle")
	_expect(hunter_presentation.get_scene_file_path().ends_with("hunter_presentation.tscn"), "Hunter presentation is an independently replaceable subscene")
	_expect(monster_presentation.get_scene_file_path().ends_with("monster_presentation.tscn"), "Monster presentation is an independently replaceable subscene")
	print("PRESENTATION TESTS: %s" % ("PASS" if failures == 0 else "%d FAILURES" % failures))
	game.queue_free()
	quit(1 if failures else 0)

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func _find_type(node: Node, type: Variant) -> Node:
	if is_instance_of(node, type):
		return node
	for child: Node in node.get_children():
		var found := _find_type(child, type)
		if found:
			return found
	return null
