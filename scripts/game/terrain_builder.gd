class_name TerrainBuilder
extends Node3D
## Builds an outdoor map from data/maps/<id>.json: rolling ground, a road cut
## between banks, five ground textures blended by rules (road, verge, forest
## floor, rock on slopes), and trees, thickets, rocks, plants and props
## scattered or placed from the data. Provides what the level needs: walkable
## cells for path-finding, cells that block sight, and the ground height.

var tile := 1.0          ## path-finding cell, metres
var w := 0               ## cells across (x)
var h := 0               ## cells deep (z)
var size := Vector2.ZERO ## metres
var map: Dictionary = {}

var _heights := PackedFloat32Array()   # (w + 1) * (h + 1), one per metre corner
var _walk := PackedByteArray()         # w * h, 1 = walkable
var _sight := PackedByteArray()        # w * h, 1 = blocks sight
var _road := PackedVector2Array()
var _road_w := 4.0
var _noise := FastNoiseLite.new()
var _low := FastNoiseLite.new()
var _forest := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
var _scenes := {}


func build(map_id: String) -> void:
	var text := FileAccess.get_file_as_string("res://data/maps/%s.json" % map_id)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Map %s: missing or not valid JSON" % map_id)
		return
	map = parsed
	var sz: Array = map.get("size", [64, 96])
	size = Vector2(sz[0], sz[1])
	w = int(size.x / tile)
	h = int(size.y / tile)
	var hm: Dictionary = map.get("height", {})
	_noise.seed = int(hm.get("seed", 11))
	_noise.frequency = float(hm.get("frequency", 0.03))
	_noise.fractal_octaves = 4
	_low.seed = _noise.seed + 1
	_low.frequency = float(hm.get("frequency", 0.03)) * 0.35
	_forest.seed = _noise.seed + 2
	_forest.frequency = 0.06
	_rng.seed = _noise.seed
	var rd: Dictionary = map.get("road", {})
	for p in rd.get("points", []):
		_road.append(Vector2(p[0], p[1]))
	_road_w = float(rd.get("width", 4.0))
	_walk.resize(w * h)
	_walk.fill(1)
	_sight.resize(w * h)
	_sight.fill(0)
	_make_heights(hm)
	_make_ground()
	for rule in map.get("scatter", []):
		_scatter(rule)
	for p in map.get("props", []):
		_prop(p)
	print("terrain: %dx%d m, %d nodes" % [int(size.x), int(size.y), get_child_count()])


# ---------------- queries used by the level ----------------
func is_floor(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= w or y >= h:
		return false
	return _walk[y * w + x] == 1


func blocks_sight(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= w or y >= h:
		return true
	return _sight[y * w + x] == 1


func cell_center(c: Vector2i) -> Vector3:
	var x := c.x * tile + tile / 2.0
	var z := c.y * tile + tile / 2.0
	return Vector3(x, height_at(x, z), z)


func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / tile), floori(p.z / tile))


func height_at(x: float, z: float) -> float:
	x = clampf(x, 0.0, size.x - 0.001)
	z = clampf(z, 0.0, size.y - 0.001)
	var ix := int(x)
	var iz := int(z)
	var fx := x - ix
	var fz := z - iz
	var n := int(size.x) + 1
	var a := _heights[iz * n + ix]
	var b := _heights[iz * n + ix + 1]
	var c := _heights[(iz + 1) * n + ix]
	var d := _heights[(iz + 1) * n + ix + 1]
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)


## Distance from a point to the middle of the road (metres).
func road_distance(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := INF
	for i in _road.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, _road[i], _road[i + 1])
		best = minf(best, p.distance_to(q))
	return best


# ---------------- ground ----------------
func _make_heights(hm: Dictionary) -> void:
	var amp := float(hm.get("amplitude", 3.0))
	var bank := float(hm.get("bank_height", 1.0))
	var bank_w := float(hm.get("bank_width", 4.0))
	var n := int(size.x) + 1
	_heights.resize(n * (int(size.y) + 1))
	for z in int(size.y) + 1:
		for x in n:
			var far := _noise.get_noise_2d(x, z) * amp + bank
			var near := _low.get_noise_2d(x, z) * amp * 0.5
			var d := road_distance(x, z)
			var k := smoothstep(_road_w / 2.0, _road_w / 2.0 + bank_w, d)
			_heights[z * n + x] = lerpf(near, far, k)


func _forest_amount(x: float, z: float, d: float) -> float:
	return clampf(_forest.get_noise_2d(x, z) * 0.8 + (d - 7.0) / 8.0, 0.0, 1.0)


func _make_ground() -> void:
	var n := int(size.x) + 1
	var m := int(size.y) + 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edge := FastNoiseLite.new()
	edge.seed = _noise.seed + 5
	edge.frequency = 0.35
	for z in m:
		for x in n:
			var y := _heights[z * n + x]
			# slope from the neighbours
			var hx := _heights[z * n + mini(x + 1, n - 1)] - _heights[z * n + maxi(x - 1, 0)]
			var hz := _heights[mini(z + 1, m - 1) * n + x] - _heights[maxi(z - 1, 0) * n + x]
			var nrm := Vector3(-hx, 2.0, -hz).normalized()
			var d := road_distance(x, z) + edge.get_noise_2d(x, z) * 0.6
			var road := 1.0 - smoothstep(_road_w / 2.0 - 0.4, _road_w / 2.0 + 0.4, d)
			var verge := smoothstep(_road_w / 2.0 - 1.2, _road_w / 2.0, d) * (1.0 - smoothstep(_road_w / 2.0 + 0.3, _road_w / 2.0 + 1.6, d))
			var forest := _forest_amount(x, z, d) * (1.0 - road)
			var rock := smoothstep(0.35, 0.6, 1.0 - nrm.y) * (1.0 - road)
			# layers: R forest floor, G road, B muddy verge, A rock; base is grass
			var col := Color(forest * (1.0 - rock), road, verge * 0.85, rock)
			st.set_color(col)
			st.set_normal(nrm)
			st.set_uv(Vector2(x, z))
			st.add_vertex(Vector3(x, y, z))
	for z in m - 1:
		for x in n - 1:
			var i := z * n + x
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + n)
			st.add_index(i + 1)
			st.add_index(i + n + 1)
			st.add_index(i + n)
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.name = "Ground"
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/terrain.gdshader")
	var layers: Array = map.get("ground", [])
	var sc := Vector4(0.25, 0.25, 0.25, 0.25)
	for i in mini(layers.size(), 5):
		var g: Dictionary = layers[i]
		var id := str(g.get("texture", ""))
		var base := "res://assets/nature/textures/%s/%s" % [id, id]
		sm.set_shader_parameter("alb%d" % i, load(base + "_diff_2k.jpg"))
		sm.set_shader_parameter("nrm%d" % i, load(base + "_nor_gl_2k.jpg"))
		var s := 1.0 / float(g.get("tile_metres", 4.0))
		if i == 0:
			sm.set_shader_parameter("scale0", s)
		else:
			sc[i - 1] = s
	sm.set_shader_parameter("scales", sc)
	mi.material_override = sm
	add_child(mi)


# ---------------- scattering ----------------
func _scene(name_: String) -> PackedScene:
	if _scenes.has(name_):
		return _scenes[name_]
	var tries := ["res://assets/nature/split/%s.gltf" % name_,
		"res://assets/nature/models/%s/%s_1k.gltf" % [name_, name_],
		"res://assets/nature/models_sf/%s.glb" % name_]
	for p in tries:
		if ResourceLoader.exists(p):
			_scenes[name_] = load(p)
			return _scenes[name_]
	push_warning("Map model not found: " + name_)
	_scenes[name_] = null
	return null


func _mark(x: float, z: float, r: float, walk: bool, sight: bool) -> void:
	for cz in range(floori((z - r) / tile), floori((z + r) / tile) + 1):
		for cx in range(floori((x - r) / tile), floori((x + r) / tile) + 1):
			if cx < 0 or cz < 0 or cx >= w or cz >= h:
				continue
			var c := Vector2((cx + 0.5) * tile, (cz + 0.5) * tile)
			if c.distance_to(Vector2(x, z)) > r + tile * 0.5:
				continue
			if not walk:
				_walk[cz * w + cx] = 0
			if sight:
				_sight[cz * w + cx] = 1


func _free_at(x: float, z: float, r: float) -> bool:
	return is_floor(floori(x / tile), floori(z / tile)) and is_floor(floori((x + r) / tile), floori(z / tile)) \
		and is_floor(floori((x - r) / tile), floori(z / tile))


## One rule: {"models": [...], "density": per m2, "min_road": m, "max_road": m,
##  "forest": [min, max] amount, "scale": [a, b], "block": radius (not walkable),
##  "hide": radius (blocks sight), "multimesh": true for small plants, "spacing": m}
func _scatter(rule: Dictionary) -> void:
	var models: Array = rule.get("models", [])
	if models.is_empty():
		return
	var count := int(size.x * size.y * float(rule.get("density", 0.01)))
	var sc: Array = rule.get("scale", [1.0, 1.0])
	var forest: Array = rule.get("forest", [0.0, 1.0])
	var block := float(rule.get("block", 0.0))
	var hide := float(rule.get("hide", 0.0))
	var spacing := float(rule.get("spacing", 0.0))
	var margin := float(rule.get("margin", 0.0))
	var placed: Array[Transform3D] = []
	var by_model := {}
	for i in count * 4:
		if placed.size() >= count:
			break
		var x := _rng.randf_range(margin, size.x - margin)
		var z := _rng.randf_range(margin, size.y - margin)
		var d := road_distance(x, z)
		if d < float(rule.get("min_road", 0.0)) or d > float(rule.get("max_road", 1e9)):
			continue
		var f := _forest_amount(x, z, d)
		if f < float(forest[0]) or f > float(forest[1]):
			continue
		if (block > 0.0 or spacing > 0.0) and not _free_at(x, z, maxf(block, spacing)):
			continue
		var s := _rng.randf_range(float(sc[0]), float(sc[1]))
		var t := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, height_at(x, z) - 0.05, z))
		var model := str(models[_rng.randi() % models.size()])
		placed.append(t)
		by_model[model] = by_model.get(model, []) + [t]
		if block > 0.0 or hide > 0.0:
			_mark(x, z, maxf(block, hide), block <= 0.0, hide > 0.0)
	for model in by_model:
		var ps := _scene(model)
		if ps == null:
			continue
		if bool(rule.get("multimesh", false)):
			_multimesh(ps, by_model[model], model)
		else:
			for t in by_model[model]:
				var inst: Node3D = ps.instantiate()
				inst.transform = t
				add_child(inst)


## Many copies of a small plant as one MultiMesh per mesh in its scene.
func _multimesh(ps: PackedScene, ts: Array, model: String) -> void:
	var src: Node = ps.instantiate()
	for mi in src.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.name.to_lower().contains("lod") and not m.name.to_lower().contains("lod0"):
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = m.mesh
		mm.instance_count = ts.size()
		for i in ts.size():
			mm.set_instance_transform(i, ts[i] * _rel(m, src))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = "MM_" + model
		add_child(mmi)
	src.free()


func _rel(m: Node3D, root: Node) -> Transform3D:
	var t := m.transform
	var p := m.get_parent()
	while p != null and p != root:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


# ---------------- placed props ----------------
## {"model": "wagon_old", "at": [x, z], "turn": deg, "size": metres (longest side), "scale": f,
##  "block": radius, "hide": radius}
func _prop(p: Dictionary) -> void:
	var ps := _scene(str(p.get("model", "")))
	if ps == null:
		return
	var inst: Node3D = ps.instantiate()
	var at: Array = p.get("at", [0, 0])
	var x := float(at[0])
	var z := float(at[1])
	add_child(inst)
	var s := float(p.get("scale", 1.0))
	if p.has("size"):
		var ab := _aabb(inst)
		var longest := maxf(ab.size.x, ab.size.z)
		if longest > 0.0:
			s = float(p["size"]) / longest
	var ab2 := _aabb(inst)
	inst.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(p.get("turn", 0.0)))).scaled(Vector3.ONE * s), Vector3.ZERO)
	# stand it on the ground with its base centred on the spot
	var c := ab2.get_center() * s
	inst.position = Vector3(x, height_at(x, z) - ab2.position.y * s + float(p.get("lift", 0.0)), z) - Basis(Vector3.UP, deg_to_rad(float(p.get("turn", 0.0)))) * Vector3(c.x, 0, c.z)
	if float(p.get("block", 0.0)) > 0.0 or float(p.get("hide", 0.0)) > 0.0:
		_mark(x, z, maxf(float(p.get("block", 0.0)), float(p.get("hide", 0.0))), float(p.get("block", 0.0)) <= 0.0, float(p.get("hide", 0.0)) > 0.0)


func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var t := _rel(m, n)
		var ab := t * m.get_aabb()
		out = ab if first else out.merge(ab)
		first = false
	return out
