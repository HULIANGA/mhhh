extends Node3D

const HUD = preload("res://scripts/hud.gd")
var hud: CanvasLayer
var started: bool = false
@onready var player: Hunter = $Player
@onready var arena: Node3D = $Arena
@onready var camera: Camera3D = $Camera3D
@onready var training_dummy: TrainingDummy = $Arena/TrainingDummy

func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Menu actions stay separate from gameplay input and work while paused.
	var bindings := {"pause": KEY_ESCAPE, "reset": KEY_R, "debug": KEY_F1}
	for action: String in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventKey.new()
			event.physical_keycode = bindings[action]
			InputMap.action_add_event(action, event)

func _ready() -> void:
	hud = HUD.new()
	add_child(hud)
	hud.continue_requested.connect(resume)
	hud.pause_requested.connect(pause)
	hud.reset_requested.connect(reset_exercise)
	player.health_changed.connect(hud.set_player_health)
	player.hit_received.connect(_on_player_hit)
	player.stamina_changed.connect(hud.set_stamina)
	player.action_changed.connect(hud.set_action)
	player.attack_landed.connect(_on_attack_landed)
	player.action_denied.connect(hud.show_denied)
	training_dummy.health_changed.connect(hud.set_target_health)
	hud.set_player_health(player.health, player.max_health)
	hud.set_stamina(player.stamina, player.max_stamina)
	hud.set_target_health(training_dummy.health, training_dummy.max_health)
	hud.set_action("Ready", "Aim, then choose an action")
	get_tree().paused = true
	hud.show_menu(true)

func _physics_process(_delta: float) -> void:
	if get_tree().paused:
		return
	hud.debug_label.text = "%d FPS  /  %.1f m\nX %+.2f    Z %+.2f\n%s  /  %s\nF1  hide diagnostics" % [Engine.get_frames_per_second(), player.travel_distance, player.position.x, player.position.z, player.action_state, player.action_phase]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if get_tree().paused:
			resume()
		else:
			pause()
	elif event.is_action_pressed("reset") and started:
		reset_exercise()
	elif event.is_action_pressed("debug"):
		hud.debug_label.visible = not hud.debug_label.visible

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(hud) and started:
		pause()

func pause() -> void:
	get_tree().paused = true
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	player.prepare_for_pause()
	hud.show_menu(not started)

func resume() -> void:
	player.clear_input()
	started = true
	hud.hide_menu()
	get_tree().paused = false

func reset_exercise() -> void:
	player.reset()
	training_dummy.reset_target()
	camera.snap_to_target()
	resume()

func _on_attack_landed(damage: int, _target_name: String, _world_position: Vector3) -> void:
	hud.show_hit(damage)

func _on_player_hit(damage: int, _world_position: Vector3) -> void:
	hud.show_player_hit(damage)
