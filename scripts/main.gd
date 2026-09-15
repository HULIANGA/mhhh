extends Node3D

const HUD = preload("res://scripts/hud.gd")
var hud: CanvasLayer
var visited: int = 0
var started: bool = false
@onready var player: Hunter = $Player
@onready var arena: Node3D = $Arena
@onready var camera: Camera3D = $Camera3D

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
	get_tree().paused = true
	hud.show_menu(true)

func _physics_process(_delta: float) -> void:
	if get_tree().paused:
		return
	if visited < arena.WAYPOINTS.size():
		var waypoint: Vector3 = arena.WAYPOINTS[visited]
		var distance := Vector2(player.position.x - waypoint.x, player.position.z - waypoint.z).length()
		if distance < 1.15:
			arena.beacons[visited].hide()
			visited += 1
			hud.set_progress(visited)
	hud.debug_label.text = "%d FPS  /  %.1f m\nX %+.2f    Z %+.2f\nF1  hide diagnostics" % [Engine.get_frames_per_second(), player.travel_distance, player.position.x, player.position.z]

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
	player.clear_input()
	hud.show_menu(not started)

func resume() -> void:
	player.clear_input()
	started = true
	hud.hide_menu()
	get_tree().paused = false

func reset_exercise() -> void:
	player.reset()
	camera.snap_to_target()
	visited = 0
	for beacon: Node3D in arena.beacons:
		beacon.show()
	hud.set_progress(visited)
	resume()
