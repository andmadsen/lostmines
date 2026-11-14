class_name CameraRig
extends Node3D
## Neverwinter Nights / Baldur's Gate style camera.
## WASD / arrows / screen edge: pan · Q/E or middle mouse drag: rotate ·
## mouse wheel: zoom · F: centre on selection.

var yaw := deg_to_rad(35.0)
var pitch := deg_to_rad(-52.0)
var distance := 13.0
var min_distance := 6.0
var max_distance := 30.0
var pan_speed := 14.0
var bounds := Rect2(0, 0, 100, 100)
var edge_pan := true

var camera: Camera3D
var _rotating := false
var _target_distance := 13.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	camera = Camera3D.new()
	camera.fov = 38.0
	camera.far = 200.0
	add_child(camera)
	_target_distance = distance
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_target_distance = clampf(_target_distance * 0.9, min_distance, max_distance)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_target_distance = clampf(_target_distance * 1.1, min_distance, max_distance)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_rotating = mb.pressed
	elif event is InputEventMouseMotion and _rotating:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * 0.006
		pitch = clampf(pitch - mm.relative.y * 0.004, deg_to_rad(-80.0), deg_to_rad(-30.0))


func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1
	if Input.is_key_pressed(KEY_Q):
		yaw += 1.6 * delta
	if Input.is_key_pressed(KEY_E):
		yaw -= 1.6 * delta
	if edge_pan and DisplayServer.window_is_focused():
		var vp := get_viewport()
		var mp := vp.get_mouse_position()
		var size := vp.get_visible_rect().size
		var e := 6.0
		if mp.x >= 0 and mp.y >= 0 and mp.x <= size.x and mp.y <= size.y:
			if mp.x < e: move.x -= 1
			if mp.x > size.x - e: move.x += 1
			if mp.y < e: move.y -= 1
			if mp.y > size.y - e: move.y += 1
	if move != Vector2.ZERO:
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		var speed := pan_speed * (distance / 16.0)
		position += (right * move.x + fwd * -move.y) * speed * delta
		position.x = clampf(position.x, bounds.position.x, bounds.end.x)
		position.z = clampf(position.z, bounds.position.y, bounds.end.y)
	distance = lerpf(distance, _target_distance, 0.15)
	_update_camera()


func focus(p: Vector3) -> void:
	position = Vector3(p.x, 0, p.z)


func _update_camera() -> void:
	if camera == null:
		return
	var offset := Vector3(0, 0, distance)
	offset = offset.rotated(Vector3.RIGHT, pitch)
	offset = offset.rotated(Vector3.UP, yaw)
	camera.position = offset
	camera.look_at(global_position + Vector3(0, 0.8, 0), Vector3.UP)
