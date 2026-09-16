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
	_expect(hunter_presentation.blade_base.is_inside_tree(), "Blade sockets are attached to the presentation model")
	_expect(monster_presentation.left_horn_tip.is_inside_tree(), "Horn sockets are attached to the presentation model")
	var blade_length := hunter_presentation.blade_base.global_position.distance_to(hunter_presentation.blade_tip.global_position)
	var left_horn_length := monster_presentation.left_horn_base.global_position.distance_to(monster_presentation.left_horn_tip.global_position)
	_expect(blade_length > 1.4 and left_horn_length > 0.6, "Placeholder sockets describe the visible weapon and horn paths")
	print("PRESENTATION TESTS: %s" % ("PASS" if failures == 0 else "%d FAILURES" % failures))
	game.queue_free()
	quit(1 if failures else 0)

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)
