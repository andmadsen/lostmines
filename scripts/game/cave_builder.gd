class_name CaveBuilder
extends Node3D
## Builds a cave from a text layout ('#' = rock, '.' = floor, 'T' = torch on
## the nearest wall). Walls are made of noise-displaced boulders; everything
## uses procedural textures until real Poly Haven textures are added.

const TILE := 2.0
const WALL_HEIGHT := 3.4

var layout: Array[String] = []
var w := 0
var h := 0
var torches: Array[Dictionary] = []   ## {light, base, seed}

var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()


func build(p_layout: Array[String]) -> void:
	layout = p_layout
	h = layout.size()
	w = layout[0].length()
	_rng.seed = 1337
	_noise.seed = 7
	_noise.frequency = 1.6
	_build_floor()
	_build_walls()
	_build_pebbles()
	for y in h:
		for x in w:
			if layout[y][x] == "T":
				_build_torch(Vector2i(x, y))


func is_floor(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= w or y >= h:
		return false
	return layout[y][x] != "#"


func cell_center(c: Vector2i) -> Vector3:
	return Vector3(c.x * TILE + TILE / 2.0, 0, c.y * TILE + TILE / 2.0)


func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.z / TILE))


# ---------------- floor ----------------
func _build_floor() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w * TILE + 20, h * TILE + 20)
	mi.mesh = pm
	mi.position = Vector3(w * TILE / 2.0, 0, h * TILE / 2.0)
	mi.material_override = ground_material()
	add_child(mi)


# ---------------- walls ----------------
func _build_walls() -> void:
	var variants: Array[ArrayMesh] = []
	for i in 6:
		variants.append(_rock_mesh(i))
	var transforms: Array = []
	for i in variants.size():
		transforms.append([])
	var mass: Array[Transform3D] = []
	for y in range(-2, h + 2):
		for x in range(-2, w + 2):
			if is_floor(x, y):
				continue
			var near := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if is_floor(x + dx, y + dy):
						near = true
			var c := cell_center(Vector2i(x, y))
			if near:
				for k in 3:
					var b := Basis()
					b = b.rotated(Vector3.UP, _rng.randf() * TAU)
					b = b.rotated(Vector3.RIGHT, _rng.randf_range(-0.25, 0.25))
					var sx := _rng.randf_range(1.2, 1.9)
					var sy := _rng.randf_range(WALL_HEIGHT * 0.55, WALL_HEIGHT * 1.0)
					b = b.scaled(Vector3(sx, sy, _rng.randf_range(1.2, 1.9)))
					var off := Vector3(_rng.randf_range(-0.7, 0.7), _rng.randf_range(-0.2, 0.6), _rng.randf_range(-0.7, 0.7))
					transforms[_rng.randi() % variants.size()].append(Transform3D(b, c + off))
			else:
				mass.append(Transform3D(Basis().scaled(Vector3(TILE, WALL_HEIGHT * 2.0, TILE)), c + Vector3(0, WALL_HEIGHT * 0.4, 0)))
	var rock := rock_material()
	for i in variants.size():
		var list: Array = transforms[i]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = variants[i]
		mm.instance_count = list.size()
		for j in list.size():
			mm.set_instance_transform(j, list[j])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = rock
		add_child(mmi)
	# solid rock mass behind the walls (seen from above as dark rock)
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mm2 := MultiMesh.new()
	mm2.transform_format = MultiMesh.TRANSFORM_3D
	mm2.mesh = box
	mm2.instance_count = mass.size()
	for j in mass.size():
		mm2.set_instance_transform(j, mass[j])
	var mmi2 := MultiMeshInstance3D.new()
	mmi2.multimesh = mm2
	mmi2.material_override = rock_material(true)
	add_child(mmi2)


## A boulder: a sphere whose vertices are pushed in and out by 3D noise.
func _rock_mesh(variant_seed: int) -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 18
	sm.rings = 10
	var arrays := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var n := FastNoiseLite.new()
	n.seed = variant_seed * 31 + 5
	n.frequency = 1.4
	n.fractal_octaves = 3
	for i in verts.size():
		var v := verts[i]
		var dist := 1.0 + n.get_noise_3dv(v * 1.0) * 0.55
		var flat := 1.0 if v.y > -0.1 else 0.6     # flatter bottom
		verts[i] = Vector3(v.x * dist, v.y * dist * flat, v.z * dist)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in idx:
		st.set_uv(uvs[i])
		st.add_vertex(verts[i])
	st.generate_normals()
	st.index()
	return st.commit()


func _build_pebbles() -> void:
	var list: Array[Transform3D] = []
	for y in h:
		for x in w:
			if not is_floor(x, y):
				continue
			var walls := 0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if not is_floor(x + d.x, y + d.y):
					walls += 1
			var count := 1 + walls * 3
			for k in count:
				var c := cell_center(Vector2i(x, y)) + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))
				var s := _rng.randf_range(0.06, 0.22) * (1.0 + walls * 0.4)
				var b := Basis().rotated(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * 0.6, s))
				list.append(Transform3D(b, c))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _rock_mesh(99)
	mm.instance_count = list.size()
	for j in list.size():
		mm.set_instance_transform(j, list[j])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = rock_material()
	add_child(mmi)


# ---------------- torches ----------------
func _build_torch(c: Vector2i) -> void:
	var dir := Vector2i.ZERO
	for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)]:
		if not is_floor(c.x + d.x, c.y + d.y):
			dir = d
			break
	var p := cell_center(c) + Vector3(dir.x, 0, dir.y) * (TILE * 0.42)
	var holder := Node3D.new()
	holder.position = p + Vector3(0, 1.9, 0)
	add_child(holder)
	var stick := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.03
	cyl.height = 0.45
	stick.mesh = cyl
	stick.rotation = Vector3(-dir.y * 0.5, 0, dir.x * 0.5)
	stick.material_override = UnitVisual.mat("#3a2414", 0.0, 0.8)
	holder.add_child(stick)
	var flame := make_flame()
	flame.position = Vector3(0, 0.3, 0)
	holder.add_child(flame)
	var light := OmniLight3D.new()
	light.position = Vector3(-dir.x * 0.35, 0.4, -dir.y * 0.35)
	light.light_color = Color(1.0, 0.62, 0.32)
	light.light_energy = 2.6
	light.omni_range = 9.0
	light.omni_attenuation = 1.3
	light.shadow_enabled = true
	light.light_volumetric_fog_energy = 1.5
	holder.add_child(light)
	torches.append({"light": light, "base": 2.6, "seed": _rng.randf() * 100.0})


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for tc in torches:
		var s: float = tc["seed"]
		var f := 0.85 + 0.1 * sin(t * 11.0 + s) + 0.07 * sin(t * 23.0 + s * 2.0) + 0.05 * sin(t * 4.0 + s)
		(tc["light"] as OmniLight3D).light_energy = float(tc["base"]) * f


## A small flame made of glowing particles (used by wall torches and hand torches).
static func make_flame() -> GPUParticles3D:
	var flame := GPUParticles3D.new()
	flame.amount = 28
	flame.lifetime = 0.6
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0, 0.6, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	var curve := CurveTexture.new()
	var cv := Curve.new()
	cv.add_point(Vector2(0, 1))
	cv.add_point(Vector2(1, 0))
	curve.curve = cv
	pm.scale_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.4, 1))
	grad.set_color(1, Color(0.9, 0.2, 0.05, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	flame.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.3)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fm.vertex_color_use_as_albedo = true
	fm.albedo_color = Color(1, 0.7, 0.3)
	q.material = fm
	flame.draw_pass_1 = q
	return flame


# ---------------- materials ----------------
const WALL_TEX := "res://assets/textures/cave_wall/textures/dark_rock_02_%s_1k.%s"
const FLOOR_TEX := "res://assets/textures/cave_floor/textures/rock_face_04_%s_1k.%s"


## A material from downloaded PBR textures (Poly Haven): colour, normal and
## roughness maps, projected in world space so any rock shape gets them
## without UVs. Returns null if the textures are not there.
static func _pbr_material(pattern: String, scale: float, tint: Color) -> StandardMaterial3D:
	var diff := pattern % ["diff", "jpg"]
	if not ResourceLoader.exists(diff):
		return null
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(diff)
	m.albedo_color = tint
	var nor := pattern % ["nor_gl", "png"]
	if ResourceLoader.exists(nor):
		m.normal_enabled = true
		m.normal_texture = load(nor)
		m.normal_scale = 1.3
	var rough := pattern % ["rough", "png"]
	if ResourceLoader.exists(rough):
		m.roughness_texture = load(rough)
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness = 1.0
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3(scale, scale, scale)
	return m


static func rock_material(dark := false) -> StandardMaterial3D:
	var pm := _pbr_material(WALL_TEX, 0.33, Color(0.55, 0.5, 0.45) if dark else Color(1.15, 1.08, 1.0))
	if pm:
		return pm
	var m := StandardMaterial3D.new()
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.frequency = 0.012
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = n
	var g := Gradient.new()
	g.set_color(0, Color(0.11, 0.1, 0.09) if not dark else Color(0.04, 0.035, 0.03))
	g.set_color(1, Color(0.42, 0.38, 0.33) if not dark else Color(0.1, 0.09, 0.08))
	tex.color_ramp = g
	m.albedo_texture = tex
	var ntex := NoiseTexture2D.new()
	ntex.width = 512
	ntex.height = 512
	ntex.seamless = true
	ntex.as_normal_map = true
	ntex.bump_strength = 12.0
	ntex.noise = n
	m.normal_enabled = true
	m.normal_texture = ntex
	m.normal_scale = 1.4
	m.roughness = 0.92
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.45, 0.45, 0.45)
	return m


static func ground_material() -> StandardMaterial3D:
	var pm := _pbr_material(FLOOR_TEX, 0.22, Color(0.95, 0.88, 0.8))
	if pm:
		return pm
	var m := StandardMaterial3D.new()
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.01
	n.fractal_octaves = 5
	var tex := NoiseTexture2D.new()
	tex.width = 1024
	tex.height = 1024
	tex.seamless = true
	tex.noise = n
	var g := Gradient.new()
	g.set_color(0, Color(0.09, 0.075, 0.06))
	g.add_point(0.55, Color(0.2, 0.16, 0.12))
	g.set_color(g.get_point_count() - 1, Color(0.3, 0.26, 0.2))
	tex.color_ramp = g
	m.albedo_texture = tex
	var n2 := FastNoiseLite.new()
	n2.noise_type = FastNoiseLite.TYPE_CELLULAR
	n2.frequency = 0.05
	var ntex := NoiseTexture2D.new()
	ntex.width = 512
	ntex.height = 512
	ntex.seamless = true
	ntex.as_normal_map = true
	ntex.bump_strength = 6.0
	ntex.noise = n2
	m.normal_enabled = true
	m.normal_texture = ntex
	m.roughness = 0.95
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.25, 0.25, 0.25)
	return m
