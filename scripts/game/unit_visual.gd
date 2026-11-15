class_name UnitVisual
extends Node3D
## A unit's body. Either a rigged model (e.g. from Mixamo, set by "model" in
## the look data) with animations, or a placeholder built from primitive
## shapes. Both expose the same equipment slots (main hand, off hand, head),
## so weapons, shields, helmets and torches attach the same way.

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
var _cast_len := 0.0
var cast_release := 0.5
var held_light: OmniLight3D = null

# rigged model
var using_model := false
var model: Node3D
var anim_player: AnimationPlayer
var move_speed := 3.0
var _walk_ref_speed := 1.5
var _attack_len := 1.0
var back_slot: Node3D = null      ## where the main weapon rests when sheathed
var _main_weapon: Node3D = null
var _main_slot: Node3D = null      ## the hand the main weapon is held in
var hip_slot: Node3D = null       ## belt: where one-handed weapons hang when sheathed
var _sheath_slot: Node3D = null    ## back_slot or hip_slot for the current weapon
var _main_sheathes := true         ## false for bows: they stay in hand
var attack_speed := 1.4
var release_frac := 0.5            ## when in the attack animation an arrow leaves
var armed := true
var _flicker_seed := randf() * 100.0

static var _mat_cache: Dictionary = {}


func build(p_look: Dictionary) -> void:
	look = p_look
	for c in get_children():
		c.queue_free()
	using_model = false
	held_light = null
	_dead = false
	var model_path := str(look.get("model", ""))
	if model_path != "" and ResourceLoader.exists(model_path):
		if _has_skeleton(model_path):
			_build_model(model_path)
			return
		push_warning("Model %s has no skeleton (rig it in Mixamo and download 'With Skin'); using a placeholder." % model_path)
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


## Rigged model: instance it, add animations from the animation set, and put
## equipment slots on the hand and head bones.
func _build_model(path: String) -> void:
	using_model = true
	body = Node3D.new()
	body.scale = Vector3.ONE * float(look.get("scale", 1.0))
	add_child(body)
	model = (load(path) as PackedScene).instantiate()
	model.rotation.y = PI   # Mixamo models face +Z; units face -Z
	body.add_child(model)
	_apply_textures(model, look.get("textures", {}))
	_apply_tints(model, look.get("tints", {}))
	var skel: Skeleton3D = model.find_child("Skeleton3D", true, false)
	anim_player = model.find_child("AnimationPlayer", true, false)
	var set_id := str(look.get("animation_set", ""))
	var aset: Dictionary = DataDB.animation_sets.get(set_id, {})
	if set_id != "" and aset.is_empty():
		push_warning("Animation set '%s' not found in data/animations.json" % set_id)
	_walk_ref_speed = float(aset.get("walk_speed", 1.5)) * float(look.get("scale", 1.0))
	release_frac = float(aset.get("release", 0.5))
	attack_speed = float(aset.get("attack_speed", 1.4))
	cast_release = float(aset.get("cast_release", 0.5))
	if anim_player == null and skel:
		# glTF characters (e.g. built in MakeHuman) come without a player
		anim_player = AnimationPlayer.new()
		model.add_child(anim_player)
	if anim_player:
		var skel_path := str(anim_player.get_node(anim_player.root_node).get_path_to(skel)) if skel else "Skeleton3D"
		for key in ["idle", "walk", "attack", "death", "cast"]:
			var p := str(aset.get(key, ""))
			if p == "":
				continue
			if not ResourceLoader.exists(p):
				push_warning("Animation '%s' not found: %s (check data/animations.json, or restart if the file was just moved)" % [key, p])
				continue
			var src: Node = (load(p) as PackedScene).instantiate()
			var sap: AnimationPlayer = src.find_child("AnimationPlayer", true, false)
			if sap and sap.get_animation_list().size() > 0:
				var anim: Animation = sap.get_animation(sap.get_animation_list()[0]).duplicate()
				var src_skel: Skeleton3D = src.find_child("Skeleton3D", true, false)
				if skel and src_skel and Retarget.needed(src_skel, skel):
					anim = Retarget.convert(anim, src_skel, skel, skel_path, "%s|%s" % [path, p]).duplicate()
				elif skel_path != "Skeleton3D":
					for ti in anim.get_track_count():
						var tp := anim.track_get_path(ti)
						anim.track_set_path(ti, NodePath("%s:%s" % [skel_path, tp.get_concatenated_subnames()]))
				anim.loop_mode = Animation.LOOP_LINEAR if key in ["idle", "walk"] else Animation.LOOP_NONE
				if key == "attack":
					_attack_len = anim.length
				if key == "cast":
					_cast_len = anim.length
				var lib := AnimationLibrary.new()
				lib.add_animation(key, anim)
				if anim_player.has_animation_library(key):
					anim_player.remove_animation_library(key)
				anim_player.add_animation_library(key, lib)
			src.free()
		_play("idle", 0.0)
	var grip: Dictionary = aset.get("grip", {})
	hand_r = _bone_slot(skel, "mixamorig_RightHand", grip.get("right", {}))
	back_slot = _bone_slot(skel, "mixamorig_Spine2", grip.get("back", {"position": [0.0, 0.12, -0.17], "rotation": [0, 0, 200]}))
	hip_slot = _bone_slot(skel, "mixamorig_Hips", grip.get("hip", {"position": [-0.2, 0.02, 0.0], "rotation": [0, 0, -12]}))
	armed = false
	hand_l = _bone_slot(skel, "mixamorig_LeftHand", grip.get("left", {}))
	head_slot = _bone_slot(skel, "mixamorig_Head", grip.get("head", {}))
	extras = Node3D.new()
	body.add_child(extras)


static var _skel_cache: Dictionary = {}

static func _has_skeleton(path: String) -> bool:
	if not _skel_cache.has(path):
		var n: Node = (load(path) as PackedScene).instantiate()
		_skel_cache[path] = n.find_child("Skeleton3D", true, false) != null
		n.free()
	return _skel_cache[path]


## Puts separately downloaded textures (look.textures) on a model whose own
## materials were lost, e.g. after rigging it in Mixamo.
func _apply_textures(root: Node, tex: Dictionary) -> void:
	if tex.is_empty():
		return
	var m := StandardMaterial3D.new()
	var load_tex := func(key: String) -> Texture2D:
		var p := str(tex.get(key, ""))
		return load(p) as Texture2D if p != "" and ResourceLoader.exists(p) else null
	m.albedo_texture = load_tex.call("albedo")
	var nt: Texture2D = load_tex.call("normal")
	if nt:
		m.normal_enabled = true
		m.normal_texture = nt
	var rt: Texture2D = load_tex.call("roughness")
	if rt:
		m.roughness_texture = rt
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	var at: Texture2D = load_tex.call("ao")
	if at:
		m.ao_enabled = true
		m.ao_texture = at
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.metallic = float(tex.get("metallic", 0.0))
	var b := float(tex.get("brightness", 1.0))
	m.albedo_color = Color(b, b, b)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = m


## Characters built by tools/build_hero.py carry every outfit as its own
## mesh ("outfit_plate", "outfit_boots"...). Show the ones the equipment
## calls for: look.outfits_always, plus the worn armor's visual.outfits.
func _show_outfits(equipment: Dictionary) -> void:
	var meshes := model.find_children("outfit_*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return
	var on: Array = look.get("outfits_always", ["under_legs", "boots"]).duplicate()
	if str(equipment.get("armor", "")) == "":
		on.append("under_top")
	for slot in ["armor", "head", "off_hand"]:
		var it := DataDB.item(str(equipment.get(slot, "")))
		on.append_array(it.get("visual", {}).get("outfits", []))
	for m in meshes:
		(m as Node3D).visible = str(m.name).trim_prefix("outfit_") in on
	# skin under worn clothes is hidden (body_hide_boots+pants...)
	for m in model.find_children("body_hide_*", "MeshInstance3D", true, false):
		var hide := false
		for id in str(m.name).trim_prefix("body_hide_").split("+"):
			if id in on:
				hide = true
		(m as Node3D).visible = not hide


## Tints parts of a model by name, e.g. look.tints = {"hair": "#5a3a24"}.
func _apply_tints(root: Node, tints: Dictionary) -> void:
	for key in tints:
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			if not str(mi.name).to_lower().contains(str(key)):
				continue
			var m := mi as MeshInstance3D
			for si in m.mesh.get_surface_count():
				var src := m.get_active_material(si)
				if src is StandardMaterial3D:
					var c := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
					var t = tints[key]
					# a colour ("#5a3a24") tints; a number (1.8) brightens
					c.albedo_color = Color(float(t), float(t), float(t)) if (t is float or t is int) else Color.html(str(t))
					m.set_surface_override_material(si, c)


func _bone_slot(skel: Skeleton3D, bone: String, g: Dictionary) -> Node3D:
	var slot := Node3D.new()
	if skel == null or skel.find_bone(bone) < 0:
		body.add_child(slot)
		return slot
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	skel.add_child(ba)
	var p: Array = g.get("position", [0, 0, 0])
	var r: Array = g.get("rotation", [0, 0, 0])
	slot.position = Vector3(p[0], p[1], p[2])
	slot.rotation_degrees = Vector3(r[0], r[1], r[2])
	ba.add_child(slot)
	return slot


func _play(name_: String, blend := 0.2) -> void:
	if anim_player == null:
		return
	var full := "%s/%s" % [name_, name_]
	if anim_player.has_animation(full) and anim_player.current_animation != full:
		anim_player.play(full, blend)


## Applies equipment: a Dictionary slot -> item id, looked up in DataDB.
func apply_equipment(equipment: Dictionary, fallback_armor_color := "") -> void:
	_clear(hand_r)
	_clear(hand_l)
	_clear(head_slot)
	_clear(extras)
	if back_slot:
		_clear(back_slot)
	if hip_slot:
		_clear(hip_slot)
	_main_weapon = null
	held_light = null
	if using_model:
		_show_outfits(equipment)
		_attach_items(equipment)
		return
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

	_attach_items(equipment)


func _attach_items(equipment: Dictionary) -> void:
	var main := DataDB.item(str(equipment.get("main_hand", "")))
	if not main.is_empty():
		var mv: Dictionary = main.get("visual", {})
		_main_weapon = weapon_mesh(mv)
		_main_slot = hand_l if str(mv.get("hand", "right")) == "left" else hand_r
		var sh = mv.get("sheathe", true)
		_sheath_slot = hip_slot if str(sh) == "hip" else back_slot
		_main_sheathes = (str(sh) == "hip" or (sh is bool and sh)) and _sheath_slot != null
		if using_model and _main_sheathes and not armed:
			_sheath_slot.add_child(_main_weapon)
		else:
			_main_slot.add_child(_main_weapon)
	var off := DataDB.item(str(equipment.get("off_hand", "")))
	if not off.is_empty():
		if str(off.get("type", "")) == "light":
			hand_l.add_child(torch_mesh(off.get("visual", {})))
		else:
			hand_l.add_child(shield_mesh(off.get("visual", {})))
	var helm := DataDB.item(str(equipment.get("head", "")))
	if hair:
		hair.visible = helm.is_empty()
	if not helm.is_empty() and str(helm.get("visual", {}).get("model", "")) != "":
		head_slot.add_child(ModelFit.helmet(helm.get("visual", {})))
	elif not helm.is_empty():
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
	if str(v.get("model", "")) != "" and ResourceLoader.exists(str(v.get("model", ""))):
		return ModelFit.weapon(v)
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


## A torch held in the off hand: flame + a shadow-casting light that moves
## with the hero, so shadows swing as the party walks.
func torch_mesh(v: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.rotation = Vector3(-0.35, 0, 0)
	if using_model:
		root.rotation = Vector3(0, 0, -PI / 2 - 0.3)   # undo the forward grip so the torch points up
	var stick := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.035
	cyl.bottom_radius = 0.025
	cyl.height = 0.5
	stick.mesh = cyl
	stick.position = Vector3(0, 0.2, 0)
	stick.material_override = mat("#3a2414", 0.0, 0.8)
	root.add_child(stick)
	var flame := CaveBuilder.make_flame()
	flame.position = Vector3(0, 0.5, 0)
	root.add_child(flame)
	var l := OmniLight3D.new()
	l.position = Vector3(0, 0.6, 0)
	l.light_color = Color(str(v.get("light_color", "#ff9e52")))
	l.light_energy = float(v.get("light_energy", 2.0))
	l.omni_range = float(v.get("light_range", 10.0))
	l.omni_attenuation = 1.2
	l.shadow_enabled = true
	l.shadow_blur = 1.5
	l.light_size = 0.08
	l.light_volumetric_fog_energy = 1.2
	l.set_meta("base_energy", l.light_energy)
	root.add_child(l)
	held_light = l
	return root


func shield_mesh(v: Dictionary) -> Node3D:
	var root := Node3D.new()
	if str(v.get("model", "")) != "" and ResourceLoader.exists(str(v.get("model", ""))):
		root.add_child(ModelFit.shield(v))
		if using_model:
			root.rotation = Vector3(0, PI / 2, 0)
			root.position = Vector3(-0.12, 0.0, -0.02)
		return root
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
	if using_model:
		# stand the shield up against the back of the forearm
		root.rotation = Vector3(0, PI / 2, 0)
		root.position = Vector3(-0.12, 0.0, -0.02)
	return root


# ---------------- animation ----------------
func _process(delta: float) -> void:
	if body == null or _dead:
		return
	if using_model:
		_flicker()
		if _swing > 0.0:
			_swing -= delta
			if _swing <= 0.0:
				anim_player.speed_scale = 1.0
			return
		if walk_amount > 0.3:
			_play("walk")
			anim_player.speed_scale = clampf(move_speed / _walk_ref_speed, 0.5, 2.5)
		else:
			_play("idle")
			anim_player.speed_scale = 1.0
		return
	_phase += delta * 9.0 * walk_amount
	var sw := sin(_phase) * 0.55 * walk_amount
	leg_l.rotation.x = sw
	leg_r.rotation.x = -sw
	var now := Time.get_ticks_msec() / 1000.0
	if held_light != null and is_instance_valid(held_light):
		# torch held forward; it sways with each step so the shadows swing
		arm_l.rotation.x = -1.05 + sin(_phase * 0.5) * 0.12 * walk_amount + sin(now * 1.3 + _flicker_seed) * 0.03
		arm_l.rotation.z = -0.25
		_flicker()
	else:
		arm_l.rotation.x = -sw * 0.6
		arm_l.rotation.z = 0.0
	body.position.y = absf(sin(_phase)) * 0.04 * walk_amount
	if _swing > 0.0:
		_swing = maxf(0.0, _swing - delta)
		var t := 1.0 - _swing / 0.4
		arm_r.rotation.x = lerpf(-2.4, 0.5, ease(t, 0.4)) if t > 0.25 else lerpf(0.0, -2.4, t / 0.25)
	else:
		arm_r.rotation.x = lerpf(arm_r.rotation.x, sw * 0.6 - 0.25, 0.2)


func _flicker() -> void:
	if held_light == null or not is_instance_valid(held_light):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var base := float(held_light.get_meta("base_energy", 2.0))
	held_light.light_energy = base * (0.86 + 0.08 * sin(now * 12.0 + _flicker_seed) + 0.06 * sin(now * 27.0 + _flicker_seed * 2.0))


## Draws the main weapon (to the hand) or sheathes it (on the back).
func set_armed(v: bool) -> void:
	if not using_model or back_slot == null or v == armed:
		armed = v if not using_model else armed
		return
	if not _main_sheathes:
		armed = true
		return
	armed = v
	if _main_weapon and is_instance_valid(_main_weapon):
		_main_weapon.reparent(_main_slot if v else _sheath_slot, false)


## Seconds from the start of an attack until an arrow is released.
func release_time() -> float:
	if using_model:
		return _attack_len / attack_speed * release_frac
	return 0.15


func swing() -> void:
	set_armed(true)
	if using_model:
		if anim_player and anim_player.has_animation("attack/attack"):
			anim_player.play("attack/attack", 0.1)
			anim_player.seek(0.0, true)
			anim_player.speed_scale = attack_speed
			_swing = _attack_len / attack_speed
		return
	_swing = 0.4


## Plays the spellcasting animation; returns seconds until the spell takes effect.
func cast() -> float:
	if using_model and anim_player and anim_player.has_animation("cast/cast"):
		anim_player.play("cast/cast", 0.15)
		anim_player.seek(0.0, true)
		anim_player.speed_scale = 1.0
		_swing = _cast_len
		return _cast_len * cast_release
	swing()
	return 0.3


## Gets back up after being healed from 0 HP.
func revive() -> void:
	_dead = false
	if using_model:
		_swing = 0.0
		if anim_player:
			anim_player.speed_scale = 1.0
			anim_player.play("idle/idle", 0.4)
		return
	var tw := create_tween()
	tw.tween_property(body, "rotation:x", 0.0, 0.4)


func die() -> void:
	_dead = true
	if using_model:
		if anim_player:
			anim_player.speed_scale = 1.0
		_play("death", 0.15)
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(body, "rotation:x", PI / 2, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(body, "position:y", 0.15, 0.5)


func knock_down() -> void:
	if using_model:
		die()
		return
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
