extends Node3D

signal battle_settled(result: StringName)

const HUD = preload("res://scripts/hud.gd")
const BATTLE_WAITING: StringName = &"waiting"
const BATTLE_RUNNING: StringName = &"running"
const BATTLE_WON: StringName = &"won"
const BATTLE_LOST: StringName = &"lost"
var hud: CanvasLayer
var started: bool = false
var battle_state: StringName = BATTLE_WAITING
var settlement_count: int = 0
var monster_ai_enabled: bool = true
var _settlement_pending: bool = false
@onready var player: Hunter = $Player
@onready var arena: FieldArena = $Arena
@onready var camera: Camera3D = $Camera3D
@onready var training_dummy: TrainingDummy = $Arena/TrainingDummy
@onready var monster: FieldMonster = $FieldMonster

func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Menu actions stay separate from gameplay input and work while paused.
	var bindings := {"pause": KEY_ESCAPE, "reset": KEY_R, "debug": KEY_F1}
	for action: String in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventKey.new()
			# Web exports report non-positional menu keys through keycode.
			# physical_keycode remains appropriate for gameplay controls such as WASD.
			event.keycode = bindings[action]
			InputMap.action_add_event(action, event)

func _ready() -> void:
	hud = HUD.new()
	add_child(hud)
	hud.continue_requested.connect(resume)
	hud.pause_requested.connect(pause)
	hud.reset_requested.connect(reset_exercise)
	hud.monster_ai_requested.connect(set_monster_ai_enabled)
	player.health_changed.connect(hud.set_player_health)
	player.hit_received.connect(_on_player_hit)
	player.stamina_changed.connect(hud.set_stamina)
	player.action_changed.connect(hud.set_action)
	player.attack_landed.connect(_on_attack_landed)
	player.action_denied.connect(hud.show_denied)
	player.defeated.connect(_request_battle_settlement)
	monster.health_changed.connect(hud.set_target_health)
	monster.defeated.connect(_request_battle_settlement)
	monster.add_collision_exception_with(training_dummy)
	hud.set_player_health(player.health, player.max_health)
	hud.set_stamina(player.stamina, player.max_stamina)
	hud.set_target_health(monster.health, monster.max_health)
	hud.set_action("Ready", "Aim, then choose an action")
	set_monster_ai_enabled(monster_ai_enabled)
	get_tree().paused = true
	hud.show_menu(true)

func _physics_process(_delta: float) -> void:
	if get_tree().paused:
		return
	hud.debug_label.text = "%d FPS  /  %.1f m\nX %+.2f    Z %+.2f\nHUNTER  %s / %s\nBEAST  %s / %s / %s\nANIM  %s\nF1  hide diagnostics" % [Engine.get_frames_per_second(), player.travel_distance, player.position.x, player.position.z, player.action_state, player.action_phase, monster.state, monster.debug_attack_id(), monster.attack_phase, monster.debug_animation_name()]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if battle_state in [BATTLE_WON, BATTLE_LOST]:
			return
		if get_tree().paused:
			resume()
		else:
			pause()
	elif event.is_action_pressed("reset") and started:
		reset_exercise()
	elif event.is_action_pressed("debug"):
		hud.debug_label.visible = not hud.debug_label.visible

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(hud) and battle_state == BATTLE_RUNNING:
		pause()

func pause() -> void:
	get_tree().paused = true
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	player.prepare_for_pause()
	hud.show_menu(not started)

func resume() -> void:
	if battle_state in [BATTLE_WON, BATTLE_LOST]:
		return
	player.clear_input()
	started = true
	battle_state = BATTLE_RUNNING
	hud.hide_menu()
	hud.set_monster_health_visible(true)
	get_tree().paused = false

func reset_exercise() -> void:
	_settlement_pending = false
	battle_state = BATTLE_RUNNING
	player.reset()
	training_dummy.reset_target()
	arena.reset_obstacles()
	monster.reset_monster()
	monster.set_ai_enabled(monster_ai_enabled)
	camera.snap_to_target()
	hud.hide_battle_result()
	resume()

func set_monster_ai_enabled(enabled: bool) -> void:
	monster_ai_enabled = enabled
	monster.set_ai_enabled(enabled)
	if is_instance_valid(hud):
		hud.set_monster_ai_enabled(enabled)

func _request_battle_settlement() -> void:
	if battle_state != BATTLE_RUNNING or _settlement_pending:
		return
	_settlement_pending = true
	call_deferred("_settle_battle")

func _settle_battle() -> void:
	if battle_state != BATTLE_RUNNING:
		_settlement_pending = false
		return
	# Settlement is deferred until the current physics frame is complete. Player
	# defeat therefore wins the tie when both combatants receive lethal damage.
	if player.is_defeated:
		battle_state = BATTLE_LOST
	elif monster.is_dead:
		battle_state = BATTLE_WON
	else:
		_settlement_pending = false
		return
	_settlement_pending = false
	settlement_count += 1
	player.clear_input()
	player.velocity = Vector3.ZERO
	monster.velocity = Vector3.ZERO
	get_tree().paused = true
	hud.show_battle_result(battle_state == BATTLE_WON)
	battle_settled.emit(battle_state)

func _on_attack_landed(damage: int, _target_name: String, _world_position: Vector3) -> void:
	hud.show_hit(damage)

func _on_player_hit(damage: int, _world_position: Vector3) -> void:
	hud.show_player_hit(damage)
