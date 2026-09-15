extends CanvasLayer

signal continue_requested
signal pause_requested
signal reset_requested

const INK := Color("edf0df")
const MUTED := Color("a6bcb4")
const ACCENT := Color("dfbd7c")
var overlay: ColorRect
var title: Label
var description: Label
var start_button: Button
var objective: Label
var progress: Label
var debug_label: Label
var _root: Control

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var top := _margin(_root, Vector2(28, 24), Vector2(450, 124))
	var heading := VBoxContainer.new()
	top.add_child(heading)
	_label(heading, "M H H H   /   F I E L D N O T E S", 14, ACCENT)
	_label(heading, "The proving ground", 30, INK)
	_label(heading, "01   /   MOVEMENT STUDY", 13, MUTED)
	var pause_button := _button("Pause  /  Esc", func(): pause_requested.emit())
	_root.add_child(pause_button)
	pause_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pause_button.offset_left = -180
	pause_button.offset_top = 28
	pause_button.offset_right = -30
	pause_button.offset_bottom = 70
	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", _panel(Color(0.045, 0.09, 0.1, 0.9)))
	_root.add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bottom.offset_left = 28
	bottom.offset_top = -142
	bottom.offset_right = 518
	bottom.offset_bottom = -28
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	bottom.add_child(content)
	progress = _label(content, "FIELD EXERCISE    /    0 OF 3", 12, ACCENT)
	objective = _label(content, "Walk to the amber marker 01", 20, INK)
	_label(content, "W A S D  move     /     Mouse  turn     /     R  reset", 13, MUTED)
	debug_label = Label.new()
	_root.add_child(debug_label)
	debug_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	debug_label.offset_left = -315
	debug_label.offset_top = -110
	debug_label.offset_right = -35
	debug_label.offset_bottom = -30
	debug_label.add_theme_color_override("font_color", INK)
	debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	debug_label.visible = false
	_build_overlay()

func _build_overlay() -> void:
	overlay = ColorRect.new()
	overlay.color = Color(0.025, 0.055, 0.06, 0.82)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(500, 0)
	box.add_theme_constant_override("separation", 19)
	center.add_child(box)
	_label(box, "F I E L D N O T E S     /     0 0 1", 14, ACCENT)
	title = _label(box, "Every hunt starts\nwith a first step.", 44, INK)
	description = _label(box, "Explore the proving ground. Find the three amber markers.\nLearn to move and turn before drawing your blade.", 17, MUTED)
	_label(box, "W A S D   Move       MOUSE   Turn\nESC   Pause       R   Reset       F1   Diagnostics", 15, INK)
	start_button = _button("Enter the field", func(): continue_requested.emit())
	start_button.custom_minimum_size = Vector2(0, 54)
	box.add_child(start_button)
	var reset_button := _button("Restart exercise", func(): reset_requested.emit())
	box.add_child(reset_button)
	_label(box, "PROTOTYPE  M1    /    Movement only · combat comes next", 12, MUTED)

func show_menu(first_time: bool) -> void:
	overlay.show()
	title.text = "Every hunt starts\nwith a first step." if first_time else "Take a breath."
	description.text = "Explore the proving ground. Find the three amber markers.\nLearn to move and turn before drawing your blade." if first_time else "The field is paused. Resume when you are ready.\nYour position and exercise progress are preserved."
	start_button.text = "Enter the field" if first_time else "Return to the field"
	start_button.grab_focus()

func hide_menu() -> void:
	overlay.hide()
	start_button.release_focus()

func set_progress(count: int) -> void:
	progress.text = "FIELD EXERCISE    /    %d OF 3" % count
	objective.text = "Walk to the amber marker 0%d" % (count + 1) if count < 3 else "Route complete. Make this ground your own."

func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
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
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style

func _margin(parent: Node, from: Vector2, to: Vector2) -> MarginContainer:
	var container := MarginContainer.new()
	container.position = from
	container.size = to - from
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(container)
	return container
