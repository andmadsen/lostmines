class_name SelectionRect
extends Control
## Draws the green drag-selection box.

var _active := false
var _a := Vector2.ZERO
var _b := Vector2.ZERO


func set_rect_points(active: bool, a: Vector2, b: Vector2) -> void:
	_active = active
	_a = a
	_b = b
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	var r := Rect2(_a, Vector2.ZERO).expand(_b)
	draw_rect(r, Color(0.3, 1.0, 0.3, 0.08), true)
	draw_rect(r, Color(0.3, 1.0, 0.3, 0.9), false, 1.0)
