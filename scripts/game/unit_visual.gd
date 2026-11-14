class_name UnitVisual
extends Node3D
## Placeholder figure built from primitive shapes, with real equipment slots
## (main hand, off hand, head, armor). Later the primitives are swapped for
## rigged models; the slots and equipment logic stay the same.

var look: Dictionary = {}

var body: Node3D
var torso: MeshInstance3D
var head: MeshInstance3D
var hair: MeshInstance3D
var skirt: MeshInstance3D
var leg_l: Node3D
var leg_r: Node3D
var arm_l: Node3D
var arm_r: Node3D
var hand_l: Node3D
var hand_r: Node3D
var head_slot: Node3D
var extras: Node3D  ## armor shape parts (pauldrons etc.)

var walk_amount := 0.0
var _phase := 0.0
var _swing := 0.0
var _dead := false

static var _mat_cache: Dictionary = {}


func build(p_look: Dictionary) -> void:
	look = p_look
	for c in get_children():
		c.queue_free()
	var s := float(look.get("scale", 1.0))
	var w := float(look.get("width", 1.0))
	body = Node3D.new()
	body.scale = Vector3(s * w, s, s * w)
	add_child(body)

	var skin := mat(str(look.get("skin", "#d9a882")), 0.0, 0.6)
	var pants := mat("#2e2620", 0.0, 0.85)

	torso = _mesh(body, _capsule(0.25, 0.78), Vector3(0, 1.17, 0), mat("#777777"))
	torso.scale = Vector3(1.0, 1.0, 0.72)

	leg_l = _pivot(body, Vector3(-0.11, 0.84, 0))
	leg_r = _pivot(body, Vector3(0.11, 0.84, 0))
	_mesh(leg_l, _capsule(0.095, 0.84), Vector3(0, -0.41, 0), pants)
	_mesh(leg_r, _capsule(0.095, 0.84), Vector3(0, -0.41, 0), pants)

	arm_l = _pivot(body, Vector3(-0.32, 1.44, 0))
	arm_r = _pivot(body, Vector3(0.32, 1.44, 0))
	_mesh(arm_l, _capsule(0.075, 0.66), Vector3(0, -0.3, 0), skin)
	_mesh(arm_r, _capsule(0.075, 0.66), Vector3(0, -0.3, 0), skin)
	hand_l = _pivot(arm_l, Vector3(0, -0.62, 0))
	hand_r = _pivot(arm_r, Vector3(0, -0.62, 0))
	hand_r.rotation = Vector3(-PI / 2, 0, 0)   # weapons are built along +Y, this points them forward
	hand_l.rotation = Vector3(0, 0, 0)

	head = _mesh(body, _sphere(0.15), Vector3(0, 1.7, 0), skin)
	hair = _mesh(body, _sphere(0.158, true), Vector3(0, 1.73, 0.02), mat(str(look.get("hair", "#3a2a1a")), 0.0, 0.8))
	head_slot = _pivot(body, Vector3(0, 1.7, 0))

	skirt = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.24
	cyl.bottom_radius = 0.4
	cyl.height = 0.82
	skirt.mesh = cyl
	skirt.position = Vector3(0, 0.44, 0)
	skirt.visible = false
	body.add_child(skirt)

	extras = Node3D.new()
	body.add_child(extras)


## Applies equipment: a Dictionary slot -> item id, looked up in DataDB.
func apply_equipment(equipment: Dictionary, fallback_armor_color := "") -> void:
	_clear(hand_r)
	_clear(hand_l)
	_clear(head_slot)
	_clear(extras)
	var armor := DataDB.item(str(equipment.get("armor", "")))
	var av: Dictionary = armor.get("visual", {})
	var style := str(av.get("style", "none"))
	var col := str(av.get("color", fallback_armor_color if fallback_armor_color != "" else "#5a4a3a"))
	var armor_mat := armor_material(style, col, float(av.get("metallic", 0.0)), float(av.get("roughness", 0.8)))
	torso.material_override = armor_mat
	skirt.visible = style == "robe"
	skirt.material_override = armor_mat
	leg_l.visible = style != "robe"
	leg_r.visible = style != "robe"
	if style == "plate":
		for sx in [-1.0, 1.0]:
			var p := _mesh(extras, _sphere(0.15, true), Vector3(0.3 * sx, 1.45, 0), armor_mat)
			p.scale = Vector3(1.15, 0.9, 1.1)
		var gorget := _mesh(extras, _capsule(0.12, 0.24), Vector3(0, 1.55, 0), armor_mat)
		gorget.rotation = Vector3(0, 0, PI / 2)
	if style == "chain" or style == "plate" or style == "leather":
		var belt := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 0.22
		tor.outer_radius = 0.27
		belt.mesh = tor
		belt.scale = Vector3(1.0, 0.6, 0.75)
		belt.position = Vector3(0, 0.9, 0)
		belt.material_override = mat("#3a2414", 0.0, 0.6)
		extras.add_child(belt)

	var main := DataDB.item(str(equipment.get("main_hand", "")))
	if not main.is_empty():
		hand_r.add_child(weapon_mesh(main.get("visual", {})))
	var off := DataDB.item(str(equipment.get("off_hand", "")))
	if not off.is_empty():
		hand_l.add_child(shield_mesh(off.get("visual", {})))
	var helm := DataDB.item(str(equipment.get("head", "")))
	hair.visible = helm.is_empty()
	if not helm.is_empty():
		var hv: Dictionary = helm.get("visual", {})
		var hm := _mesh(head_slot, _sphere(0.175, true), Vector3(0, 0.02, 0), mat(str(hv.get("color", "#9aa2aa")), 0.9, 0.35))
		hm.scale = Vector3(1, 1.05, 1.05)
		var nose := MeshInstance3D.new()
		var nb := BoxMesh.new()
		nb.size = Vector3(0.03, 0.16, 0.03)
		nose.mesh = nb
		nose.position = Vector3(0, -0.04, -0.17)
		nose.material_override = hm.material_override
		head_slot.add_child(nose)


func weapon_mesh(v: Dictionary) -> Node3D:
	var root := Node3D.new()
	var kind := str(v.get("mesh", "sword"))
	var length := float(v.get("length", 0.8))
	var metal := mat(str(v.get("color", "#c8ccd2")), 0.9, 0.3)
	var wood := mat("#5a3a1e", 0.0, 0.7)
	match kind:
		"sword":
			var blade := _box(root, Vector3(0.05, length, 0.012), Vector3(0, length / 2 + 0.08, 0), metal)
			blade.name = "Blade"
			_box(root, Vector3(0.2, 0.03, 0.04), Vector3(0, 0.08, 0), mat("#8a6a2a", 0.7, 0.4))
			_box(root, Vector3(0.035, 0.16, 0.035), Vector3(0, 0.0, 0), wood)
		"axe":
			_box(root, Vector3(0.04, length, 0.04), Vector3(0, length / 2 - 0.1, 0), wood)
			_box(root, Vector3(0.24, 0.2, 0.02), Vector3(0.1, length - 0.18, 0), metal)
		"mace":
			_box(root, Vector3(0.04, length, 0.04), Vector3(0, length / 2 - 0.1, 0), wood)
			_mesh(root, _sphere(0.08), Vector3(0, length - 0.1, 0), metal)
		"staff":
			_box(root, Vector3(0.045, length, 0.045), Vector3(0, length / 2 - 0.5, 0), wood)
			var orb := _mesh(root, _sphere(0.06), Vector3(0, length - 0.48, 0), glow_mat(str(v.get("glow", "#a98bff"))))
			var l := OmniLight3D.new()
			l.light_color = Color(str(v.get("glow", "#a98bff")))
			l.light_energy = 0.6
			l.omni_range = 2.5
			orb.add_child(l)
	return root


func shield_mesh(v: Dictionary) -> Node3D:
	var root := Node3D.new()
	var face := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	var kite := str(v.get("mesh", "")) == "kite_shield"
	cyl.top_radius = 0.3
	cyl.bottom_radius = 0.3
	cyl.height = 0.04
	cyl.radial_segments = 24
	face.mesh = cyl
	face.material_override = mat(str(v.get("color", "#7a1e1e")), 0.6 if kite else 0.0, 0.4 if kite else 0.7)
	face.rotation = Vector3(0, 0, PI / 2)
	if kite:
		face.scale = Vector3(1.35, 1.0, 0.85)
	face.position = Vector3(-0.08, 0.05, -0.05)
	root.add_child(face)
	var boss := _mesh(root, _sphere(0.06), Vector3(-0.11, 0.05, -0.05), mat(str(v.get("rim", "#8a8f96")), 0.9, 0.3))
	boss.scale = Vector3(0.6, 1, 1)
	return root


# ---------------- animation ----------------
func _process(delta: float) -> void:
	if body == null or _dead:
		return
	_phase += delta * 9.0 * walk_amount
	var sw := sin(_phase) * 0.55 * walk_amount
	leg_l.rotation.x = sw
	leg_r.rotation.x = -sw
	arm_l.rotation.x = -sw * 0.6
	body.position.y = absf(sin(_phase)) * 0.04 * walk_amount
	if _swing > 0.0:
		_swing = maxf(0.0, _swing - delta)
		var t := 1.0 - _swing / 0.4
		arm_r.rotation.x = lerpf(-2.4, 0.5, ease(t, 0.4)) if t > 0.25 else lerpf(0.0, -2.4, t / 0.25)
	else:
		arm_r.rotation.x = lerpf(arm_r.rotation.x, sw * 0.6 - 0.25, 0.2)


func swing() -> void:
	_swing = 0.4


func die() -> void:
	_dead = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(body, "rotation:x", PI / 2, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(body, "position:y", 0.15, 0.5)


func knock_down() -> void:
	_dead = true
	var tw := create_tween()
	tw.tween_property(body, "rotation:x", PI / 2.2, 0.4)


# ---------------- helpers ----------------
static func mat(hex: String, metallic := 0.0, rough := 0.7) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f" % [hex, metallic, rough]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.metallic = metallic * 0.5   # caves have little to reflect; full metal reads as black
	m.roughness = maxf(rough, 0.35)
	_mat_cache[key] = m
	return m


static func glow_mat(hex: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.emission_enabled = true
	m.emission = Color(hex)
	m.emission_energy_multiplier = 4.0
	return m


static func armor_material(style: String, hex: String, metallic: float, rough: float) -> StandardMaterial3D:
	var key := "armor|%s|%s" % [style, hex]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.metallic = metallic * 0.5
	m.roughness = maxf(rough, 0.35)
	if style == "chain" or style == "leather":
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.frequency = 0.35 if style == "chain" else 0.08
		var tex := NoiseTexture2D.new()
		tex.width = 256
		tex.height = 256
		tex.seamless = true
		tex.as_normal_map = true
		tex.bump_strength = 6.0 if style == "chain" else 2.0
		tex.noise = n
		m.normal_enabled = true
		m.normal_texture = tex
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(4, 4, 4)
	_mat_cache[key] = m
	return m


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _mesh(parent: Node3D, m: Mesh, pos: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.material_override = material
	parent.add_child(mi)
	return mi


func _box(parent: Node3D, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mesh(parent, b, pos, material)


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	return c


func _sphere(r: float, hemi := false) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * (1.0 if hemi else 2.0)
	s.is_hemisphere = hemi
	return s


func _clear(n: Node) -> void:
	for c in n.get_children():
		c.queue_free()
