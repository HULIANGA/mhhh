class_name KeyboardMouseInput
extends HunterInputSource

const MOVE_ACTIONS := [&"move_left", &"move_right", &"move_up", &"move_down"]
const BUTTON_ACTIONS := [&"attack", &"charge", &"dodge"]
var _discard_edges: bool = true

func _enter_tree() -> void:
	var keys := {&"move_left": KEY_A, &"move_right": KEY_D, &"move_up": KEY_W, &"move_down": KEY_S, &"dodge": KEY_SPACE}
	for action: StringName in keys:
		var event := InputEventKey.new()
		event.physical_keycode = keys[action]
		_register(action, event)
	for action: StringName in [&"attack", &"charge"]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT if action == &"attack" else MOUSE_BUTTON_RIGHT
		_register(action, event)

func sample(viewport: Viewport, actor_position: Vector3) -> HunterInputFrame:
	var frame := HunterInputFrame.new()
	frame.movement = Input.get_vector(MOVE_ACTIONS[0], MOVE_ACTIONS[1], MOVE_ACTIONS[2], MOVE_ACTIONS[3])
	frame.aim_direction = _mouse_direction(viewport, actor_position)
	# Do not turn a UI click or pause cancellation into a gameplay button edge.
	if _discard_edges:
		_discard_edges = false
		return frame
	_read_button(&"attack", frame.attack)
	_read_button(&"charge", frame.charge)
	_read_button(&"dodge", frame.dodge)
	return frame

func clear() -> void:
	for action: StringName in MOVE_ACTIONS + BUTTON_ACTIONS:
		Input.action_release(action)
	_discard_edges = true

func _mouse_direction(viewport: Viewport, actor_position: Vector3) -> Vector3:
	var camera := viewport.get_camera_3d()
	if not camera:
		return Vector3.ZERO
	var mouse := viewport.get_mouse_position()
	var intersection: Variant = Plane(Vector3.UP, 0.0).intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
	if intersection == null:
		return Vector3.ZERO
	var direction: Vector3 = intersection - actor_position
	direction.y = 0.0
	return direction.normalized() if direction.length_squared() > 0.04 else Vector3.ZERO

func _read_button(action: StringName, state: HunterInputFrame.ButtonState) -> void:
	state.pressed = Input.is_action_just_pressed(action)
	state.held = Input.is_action_pressed(action)
	state.released = Input.is_action_just_released(action)

func _register(action: StringName, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
		InputMap.action_add_event(action, event)
