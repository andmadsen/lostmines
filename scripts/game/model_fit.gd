class_name ModelFit
## Fits a downloaded weapon model to the hand automatically, whatever size
## and angle it was saved in:
##  - finds the weapon's long axis (principal component of its vertices),
##  - finds the pommel end (the guard is the widest part, near the pommel),
##  - puts the middle of the grip at the origin, blade along +Y, wide side
##    along X, and scales it to the length given in the data.


## Returns a Node3D holding the model, ready to add to a hand slot.
## v: the item's "visual" data ("model", "length", optional "flip",
## "grip" (0..1 along the handle, default auto), "rotation" [x,y,z] degrees).
static func weapon(v: Dictionary) -> Node3D:
	var path := str(v.get("model", ""))
	var holder := Node3D.new()
	if path == "" or not ResourceLoader.exists(path):
		return holder
	var model: Node3D = (load(path) as PackedScene).instantiate()
	holder.add_child(model)
	var verts := _collect(model)
	if verts.size() < 4:
		return holder
	# --- principal axes
	var c := Vector3.ZERO
	for p in verts:
		c += p
	c /= verts.size()
	var cov := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	for p in verts:
		var d := p - c
		for i in 3:
			for j in 3:
				cov[i][j] += d[i] * d[j]
	var a := _eigen(cov, Vector3(1, 0.3, 0.1))
	var cov2 := _deflate(cov, a)
	var b := _eigen(cov2, Vector3(0.1, 1, 0.3))
	b = (b - a * a.dot(b)).normalized()
	var n := a.cross(b).normalized()
	# --- profile along the long axis
	var tmin := INF
	var tmax := -INF
	for p in verts:
		var t := (p - c).dot(a)
		tmin = minf(tmin, t)
		tmax = maxf(tmax, t)
	var length := tmax - tmin
	const BINS := 24
	var width := []
	width.resize(BINS)
	width.fill(0.0)
	for p in verts:
		var d := p - c
		var t := d.dot(a)
		var k := clampi(int((t - tmin) / length * BINS), 0, BINS - 1)
		width[k] = maxf(width[k], absf(d.dot(b)))
	var guard := 0
	for k in BINS:
		if width[k] > width[guard]:
			guard = k
	var pommel_low := guard < BINS / 2
	if bool(v.get("flip", false)):
		pommel_low = not pommel_low
	if not pommel_low:
		a = -a
		n = -n
		var tmp := tmin
		tmin = -tmax
		tmax = -tmp
		guard = BINS - 1 - guard
	# grip: halfway between the pommel and the guard (or a fraction from data)
	var guard_t := tmin + (guard + 0.5) / BINS * length
	var grip_frac := float(v.get("grip", -1.0))
	var grip_t := (tmin + guard_t) * 0.5 if grip_frac < 0.0 else tmin + grip_frac * length
	var grip := c + a * grip_t
	# --- transform: blade along +Y, wide side along X, grip at origin
	var s := float(v.get("length", 1.0)) / length
	var r := Basis(b, a, n).transposed()
	var basis := Basis(r.x * s, r.y * s, r.z * s)
	model.transform = Transform3D(basis, -(basis * grip))
	var rot: Array = v.get("rotation", [0, 0, 0])
	holder.rotation_degrees = Vector3(rot[0], rot[1], rot[2])
	return holder


static func _collect(root: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var xf := Transform3D()
		var node: Node = m
		while node != root and node is Node3D:
			xf = (node as Node3D).transform * xf
			node = node.get_parent()
		for si in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(si)
			for p in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				out.append(xf * p)
	return out


static func _eigen(m: Array, start: Vector3) -> Vector3:
	var v := start.normalized()
	for it in 60:
		var w := Vector3(
			m[0][0] * v.x + m[0][1] * v.y + m[0][2] * v.z,
			m[1][0] * v.x + m[1][1] * v.y + m[1][2] * v.z,
			m[2][0] * v.x + m[2][1] * v.y + m[2][2] * v.z)
		if w.length() < 1e-12:
			break
		v = w.normalized()
	return v


static func _deflate(m: Array, a: Vector3) -> Array:
	var lam := 0.0
	var av := Vector3(
		m[0][0] * a.x + m[0][1] * a.y + m[0][2] * a.z,
		m[1][0] * a.x + m[1][1] * a.y + m[1][2] * a.z,
		m[2][0] * a.x + m[2][1] * a.y + m[2][2] * a.z)
	lam = a.dot(av)
	var out := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	for i in 3:
		for j in 3:
			out[i][j] = m[i][j] - lam * a[i] * a[j]
	return out
