extends CanvasLayer

signal continue_requested
signal pause_requested
signal reset_requested

const INK := Color("edf0df")
const MUTED := Color("a6bcb4")
const ACCENT := Color("dfbd7c")
const DANGER := Color("e48670")
var overlay: ColorRect
var title: Label
var description: Label
var start_button: Button
var objective: Label
var target_health: Label
var action_label: Label
var player_health_bar: ProgressBar
var player_health_value: Label
var stamina_bar: ProgressBar
var stamina_value: Label
var feedback: Label
var debug_label: Label
var _root: Control
var _feedback_time: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var top := _margin(_root, Vector2(28, 24), Vector2(520, 132))
	var heading := VBoxContainer.new()
	top.add_child(heading)
	_label(heading, "M H H H   /   F I E L D N O T E S", 14, ACCENT)
	_label(heading, "The proving ground", 30, INK)
	_label(heading, "03   /   SURVIVAL STUDY", 13, MUTED)
	var pause_button := _button("Pause  /  Esc", func(): pause_requested.emit())
	_root.add_child(pause_button)
	pause_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pause_button.offset_left = -180
	pause_button.offset_top = 28
	pause_button.offset_right = -30
	pause_button.offset_bottom = 70
	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", _panel(Color(0.045, 0.09, 0.1, 0.92)))
	_root.add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bottom.offset_left = 28
	bottom.offset_top = -226
	bottom.offset_right = 590
	bottom.offset_bottom = -28
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 7)
	bottom.add_child(content)
	target_health = _label(content, "FIELD BEAST    /    180 HP", 12, ACCENT)
	objective = _label(content, "Read the warning. Evade sweep, pounce, or charge.", 19, INK)
	action_label = _label(content, "READY    /    AIM, THEN CHOOSE AN ACTION", 12, MUTED)
	var health_row := HBoxContainer.new()
	health_row.add_theme_constant_override("separation", 12)
	content.add_child(health_row)
	player_health_bar = ProgressBar.new()
	player_health_bar.custom_minimum_size = Vector2(380, 18)
	player_health_bar.show_percentage = false
	player_health_bar.max_value = 100
	player_health_bar.value = 100
	player_health_bar.add_theme_stylebox_override("background", _panel(Color("2d2020")))
	player_health_bar.add_theme_stylebox_override("fill", _panel(Color("bd675b")))
	health_row.add_child(player_health_bar)
	player_health_value = _label(health_row, "HP  100 / 100", 12, INK)
	var stamina_row := HBoxContainer.new()
	stamina_row.add_theme_constant_override("separation", 12)
	content.add_child(stamina_row)
	stamina_bar = ProgressBar.new()
	stamina_bar.custom_minimum_size = Vector2(380, 18)
	stamina_bar.show_percentage = false
	stamina_bar.max_value = 100
	stamina_bar.value = 100
	stamina_bar.add_theme_stylebox_override("background", _panel(Color("172b2c")))
	stamina_bar.add_theme_stylebox_override("fill", _panel(Color("7eb898")))
	stamina_row.add_child(stamina_bar)
	stamina_value = _label(stamina_row, "100 / 100", 12, INK)
	_label(content, "LMB  click / hold attack    RMB  hold / release    SPACE  dodge    R  reset", 12, MUTED)
	feedback = Label.new()
	_root.add_child(feedback)
	feedback.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	feedback.offset_left = -260
	feedback.offset_top = 118
	feedback.offset_right = 260
	feedback.offset_bottom = 162
	feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback.add_theme_font_size_override("font_size", 23)
	feedback.add_theme_color_override("font_color", ACCENT)
	feedback.visible = false
	debug_label = Label.new()
	_root.add_child(debug_label)
	debug_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	debug_label.offset_left = -345
	debug_label.offset_top = -126
	debug_label.offset_right = -35
	debug_label.offset_bottom = -30
	debug_label.add_theme_color_override("font_color", INK)
	debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	debug_label.visible = false
	_build_overlay()

func _process(delta: float) -> void:
	if _feedback_time <= 0.0:
		return
	_feedback_time -= delta
	feedback.modulate.a = clampf(_feedback_time * 1.8, 0.0, 1.0)
	if _feedback_time <= 0.0:
		feedback.hide()

func _build_overlay() -> void:
	overlay = ColorRect.new()
	overlay.color = Color(0.025, 0.055, 0.06, 0.84)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 0)
	box.add_theme_constant_override("separation", 17)
	center.add_child(box)
	_label(box, "F I E L D N O T E S     /     0 0 2", 14, ACCENT)
	title = _label(box, "A heavy blade rewards\ndeliberate hands.", 42, INK)
	description = _label(box, "Practice on the post. Every swing has windup, impact, and recovery.\nWatch your stamina; an empty hunter cannot charge or roll.", 16, MUTED)
	_label(box, "LMB   Click / hold attack       RMB   Hold / release charge\nSPACE   Dodge       WASD   Move       MOUSE   Turn", 14, INK)
	start_button = _button("Begin blade study", func(): continue_requested.emit())
	start_button.custom_minimum_size = Vector2(0, 54)
	box.add_child(start_button)
	var reset_button := _button("Restart exercise", func(): reset_requested.emit())
	box.add_child(reset_button)
	_label(box, "PROTOTYPE  M3.5    /    Charge study", 12, MUTED)

func show_menu(first_time: bool) -> void:
	overlay.show()
	title.text = "A heavy blade rewards\ndeliberate hands." if first_time else "Take a breath."
	description.text = "Amber warns of an attack. Sweep up close, evade a pounce at medium range, or bait a long charge.\nA charge breaks wood; stone and walls knock the beast down for a long punish." if first_time else "The field is paused. Your action is frozen in place.\nResume when you are ready to commit."
	start_button.text = "Begin blade study" if first_time else "Return to the field"
	start_button.grab_focus()

func hide_menu() -> void:
	overlay.hide()
	start_button.release_focus()

func set_stamina(current: float, maximum: float) -> void:
	stamina_bar.max_value = maximum
	stamina_bar.value = current
	stamina_value.text = "%d / %d" % [roundi(current), roundi(maximum)]

func set_player_health(current: int, maximum: int) -> void:
	player_health_bar.max_value = maximum
	player_health_bar.value = current
	player_health_value.text = "HP  %d / %d" % [current, maximum]

func set_target_health(current: int, maximum: int) -> void:
	target_health.text = "FIELD BEAST    /    %d OF %d HP" % [current, maximum]
	objective.text = "Beast down. Press R to reset the pursuit." if current <= 0 else "Read the warning. Evade sweep, pounce, or charge."

func set_action(action: String, phase: String) -> void:
	action_label.text = "%s    /    %s" % [action.to_upper(), phase.to_upper()]

func show_hit(damage: int) -> void:
	_show_feedback("HIT  /  %d" % damage, ACCENT)

func show_player_hit(damage: int) -> void:
	_show_feedback("HURT  /  -%d HP" % damage, DANGER)

func show_denied(reason: String) -> void:
	_show_feedback(reason.to_upper(), DANGER)

func _show_feedback(message: String, color: Color) -> void:
	feedback.text = message
	feedback.add_theme_color_override("font_color", color)
	feedback.modulate.a = 1.0
	feedback.show()
	_feedback_time = 1.15

func _label(parent: Node, text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(text_value: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_stylebox_override("normal", _panel(Color("274440")))
	button.add_theme_stylebox_override("hover", _panel(Color("3c6054")))
	button.add_theme_stylebox_override("pressed", _panel(Color("466d5c")))
	button.add_theme_stylebox_override("focus", _panel(Color(0, 0, 0, 0), ACCENT))
	button.pressed.connect(action)
	return button

func _panel(color: Color, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _margin(parent: Node, from: Vector2, to: Vector2) -> MarginContainer:
	var container := MarginContainer.new()
	container.position = from
	container.size = to - from
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(container)
	return container
