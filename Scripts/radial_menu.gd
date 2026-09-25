extends Node2D

@export var ring_radius: float = 126.0
@export var deadzone_radius: float = 40.0
@export var item_radius: float = 150.0
@export var label_font_size: int = 18

var _center := Vector2.ZERO
var _actions: Array[Dictionary] = []
var _selected_index := -1
var _font: Font = null

func _ready() -> void:
	visible = false
	set_process(false)

func set_menu_font(font: Font) -> void:
	_font = font
	queue_redraw()

func open_menu(center: Vector2, actions: Array[Dictionary]) -> void:
	_center = center
	_actions = actions.duplicate(true)
	_selected_index = -1
	visible = true
	queue_redraw()

func update_pointer(pointer_position: Vector2) -> void:
	if not visible or _actions.is_empty():
		return
	var delta := pointer_position - _center
	if delta.length() < deadzone_radius:
		_selected_index = -1
		queue_redraw()
		return
	var direction := delta.normalized()
	var best_dot := -2.0
	var best_index := -1
	for i in range(_actions.size()):
		var angle := -PI * 0.5 + TAU * float(i) / float(_actions.size())
		var slot_dir := Vector2(cos(angle), sin(angle))
		var score := direction.dot(slot_dir)
		if score > best_dot:
			best_dot = score
			best_index = i
	if best_index >= 0 and bool(_actions[best_index].get("enabled", true)):
		_selected_index = best_index
	else:
		_selected_index = -1
	queue_redraw()

func finish(pointer_position: Vector2) -> String:
	update_pointer(pointer_position)
	var action_id := ""
	if _selected_index >= 0 and _selected_index < _actions.size():
		action_id = str(_actions[_selected_index].get("id", ""))
	hide_menu()
	return action_id

func hide_menu() -> void:
	visible = false
	_selected_index = -1
	_actions.clear()
	queue_redraw()

func _draw() -> void:
	if not visible or _actions.is_empty():
		return

	# Subtle dark hub and guide ring. The menu remains mostly transparent so the
	# world stays visually dominant while the player drags toward an action.
	draw_circle(_center, deadzone_radius - 5.0, Color(0.01, 0.025, 0.04, 0.82))
	draw_arc(_center, ring_radius, 0.0, TAU, 96, Color(0.24, 0.47, 0.60, 0.40), 2.0, true)
	draw_arc(_center, deadzone_radius, 0.0, TAU, 64, Color(0.35, 0.62, 0.72, 0.55), 2.0, true)

	for i in range(_actions.size()):
		var action := _actions[i]
		var enabled := bool(action.get("enabled", true))
		var angle := -PI * 0.5 + TAU * float(i) / float(_actions.size())
		var direction := Vector2(cos(angle), sin(angle))
		var marker_pos := _center + direction * ring_radius
		var selected := i == _selected_index
		var marker_color := Color(0.28, 0.55, 0.66, 0.86) if enabled else Color(0.18, 0.22, 0.24, 0.60)
		if selected:
			marker_color = Color(0.76, 0.91, 0.96, 1.0)
			draw_line(_center + direction * deadzone_radius, marker_pos, Color(0.53, 0.82, 0.92, 0.62), 2.0, true)
		draw_circle(marker_pos, 11.0 if selected else 8.0, marker_color)

		var label := str(action.get("label", ""))
		var label_pos := _center + direction * item_radius
		_draw_label(label, label_pos, selected, enabled)

	if _font != null:
		var cancel := "RELEASE CENTER TO CANCEL"
		var cancel_size := _font.get_string_size(cancel, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18)
		draw_string(_font, _center + Vector2(-cancel_size.x * 0.5, 6.0), cancel, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color(0.45, 0.60, 0.66, 0.86))

func _draw_label(text: String, position: Vector2, selected: bool, enabled: bool) -> void:
	if _font == null:
		return
	var size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, label_font_size)
	var rect := Rect2(position - Vector2(size.x * 0.5 + 8.0, label_font_size * 0.68), Vector2(size.x + 16.0, label_font_size + 10.0))
	var bg := Color(0.015, 0.04, 0.06, 0.90 if selected else 0.74)
	var fg := Color(0.82, 0.93, 0.97, 1.0) if selected else Color(0.55, 0.72, 0.78, 0.95)
	if not enabled:
		bg = Color(0.03, 0.04, 0.05, 0.62)
		fg = Color(0.30, 0.34, 0.36, 0.76)
	draw_rect(rect, bg, true)
	draw_rect(rect, Color(fg.r, fg.g, fg.b, 0.30), false, 1.0)
	draw_string(_font, Vector2(position.x - size.x * 0.5, position.y + label_font_size * 0.32), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, label_font_size, fg)
