class_name PortraitView
extends SubViewportContainer
## A living portrait: the hero's own 3D model, in its own little world,
## lit like a painting and framed on the head. Shows the gear they wear.

var viewport: SubViewport
var visual: UnitVisual
var camera: Camera3D
var _equip_key := ""
var _frames := 0
var full_body := false   ## whole figure, slowly turning (character sheet)


func setup(look: Dictionary, equipment: Dictionary, size_px: Vector2i, whole := false) -> void:
	full_body = whole
	stretch = true
	custom_minimum_size = size_px
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = size_px
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.05, 0.035)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.3, 0.26)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	viewport.add_child(we)

	# warm key light from the front-left, cool rim light from behind
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.82, 0.6)
	key.light_energy = 1.5
	key.rotation_degrees = Vector3(-25, 155, 0)
	viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.55, 0.65, 1.0)
	rim.light_energy = 1.2
	rim.rotation_degrees = Vector3(-15, -20, 0)
	viewport.add_child(rim)
	if whole:
		rim.light_energy = 0.6
		key.light_energy = 1.8

	visual = UnitVisual.new()
	viewport.add_child(visual)
	visual.build(look)
	visual.apply_equipment(equipment)
	_equip_key = str(equipment)

	camera = Camera3D.new()
	camera.fov = 26.0
	viewport.add_child(camera)
	_frame_head()


## Re-dresses the portrait when the hero's equipment changes.
func update_equipment(equipment: Dictionary) -> void:
	var k := str(equipment)
	if k == _equip_key:
		return
	_equip_key = k
	visual.apply_equipment(equipment)


func _process(delta: float) -> void:
	if full_body and visual:
		visual.rotation.y += delta * 0.35
	# frame the head once the idle animation has settled the pose
	if _frames < 12 and is_inside_tree():
		_frames += 1
		_frame_head()


func _frame_head() -> void:
	if camera == null or not camera.is_inside_tree():
		return
	var s := float(visual.look.get("scale", 1.0))
	var head := Vector3(0, 1.55 * s, 0)
	var skel: Skeleton3D = visual.model.find_child("Skeleton3D", true, false) if visual.model else null
	if skel:
		var hb := skel.find_bone("mixamorig_Head")
		if hb >= 0:
			head = skel.global_transform * skel.get_bone_global_pose(hb).origin
			head.y += 0.07 * s
	if full_body:
		var mid := Vector3(0, head.y * 0.52, 0)
		var dist := head.y * 0.62 / tan(deg_to_rad(camera.fov * 0.5))
		camera.look_at_from_position(mid + Vector3(0, head.y * 0.08, -dist), mid, Vector3.UP)
		return
	# the unit faces -Z: look at the face from the front, slightly to its right
	var eye := head + Vector3(0.22, 0.03, -0.95) * s
	camera.look_at_from_position(eye, head + Vector3(0, -0.06 * s, 0), Vector3.UP)
