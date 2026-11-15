extends Node
## Test harness: loads the test scene, optionally runs a scripted scenario,
## saves screenshots to user:// (or LM_OUT), then quits. Not part of the game.

var scene: Node
var frame := 0
var out := ""
var plan := ""

func _ready() -> void:
	out = OS.get_environment("LM_OUT")
	plan = OS.get_environment("LM_PLAN")
	scene = load("res://scenes/%s.tscn" % (OS.get_environment("LM_SCENE") if OS.get_environment("LM_SCENE") != "" else "test_cave")).instantiate()
	add_child(scene)

func _process(_d: float) -> void:
	frame += 1
	# LM_SWAP=<hero index>:<model path>: try a model on a hero (all plans)
	if frame == 2 and OS.get_environment("LM_SWAP") != "":
		var sw := OS.get_environment("LM_SWAP").split(":", true, 1)
		var hu: Unit = scene.party[int(sw[0])]
		var lk: Dictionary = DataDB.heroes[hu.data_id]["look"].duplicate()
		lk["model"] = sw[1]
		lk["scale"] = float(OS.get_environment("LM_SCALE")) if OS.get_environment("LM_SCALE") != "" else 1.0
		if OS.get_environment("LM_TINT") != "":
			lk["tints"] = {"hair": OS.get_environment("LM_TINT")}
		if OS.get_environment("LM_ARMOR") != "":
			hu.equipment["armor"] = OS.get_environment("LM_ARMOR")
		hu.visual.build(lk)
		hu.visual.apply_equipment(hu.equipment)
	if plan == "fight":
		if frame == 30:
			scene.rig.focus(Vector3(23, 0, 16))
			for u in scene.party:
				u.order_move(Vector3(22 + randf(), 0, 14 + randf()))
		if frame > 30 and scene.paused:
			scene.paused = false
		if frame == 520:
			_save("fight")
		if frame == 900:
			_save("fight2")
			print(scene.hud.log_label.get_parsed_text())
			get_tree().quit()
	elif plan == "bowshot":
		var p: Unit = scene.party[int(OS.get_environment("LM_HERO")) if OS.get_environment("LM_HERO") != "" else 1]
		if frame == 5:
			p.global_position = Vector3(23, 0, 20)
			p.rotation.y = 0.0
			scene.rig.focus(Vector3(23.5, 0, 18.5))
			scene.rig._target_distance = 4.0
			scene.rig.distance = 4.0
			scene.rig.pitch = deg_to_rad(-15.0)
			scene.rig.yaw = deg_to_rad(60.0)
			scene.rig.focus(Vector3(23, 0.8, 19.5))
			scene.paused = false
		if frame > 5 and scene.paused: scene.paused = false
		if frame == 45:
			_save("bow_idle")
			p.order_attack(scene.units[4])
		if frame == 62:
			_save("bow_draw")
			var ap: AnimationPlayer = p.visual.anim_player
			print("anim ", ap.current_animation, " pos ", ap.current_animation_position, " len ", ap.current_animation_length, " rot ", p.rotation_degrees.y, " target dir ", rad_to_deg(atan2(scene.units[4].global_position.x-23, scene.units[4].global_position.z-20)), " list ", ap.get_animation_list())
		if frame == 76:
			_save("bow_arrow")
			print(scene.hud.log_label.get_parsed_text())
			get_tree().quit()
	elif plan == "gearclose":
		var k: Unit = scene.party[int(OS.get_environment("LM_HERO")) if OS.get_environment("LM_HERO") != "" else 2]
		if frame == 5:
			if OS.get_environment("LM_EQUIP") != "":
				for kv in OS.get_environment("LM_EQUIP").split(","):
					var p2 := kv.split(":")
					k.equipment[p2[0]] = p2[1]
				k.visual.apply_equipment(k.equipment)
			if OS.get_environment("LM_SHEATHED") == "":
				k.visual.set_armed(true)
				k._calm = -999.0
			scene.rig.focus(k.global_position + Vector3(0, float(OS.get_environment("LM_FOCUSY")) if OS.get_environment("LM_FOCUSY") != "" else 0.6, 0))
			scene.rig.position.y = (float(OS.get_environment("LM_FOCUSY")) if OS.get_environment("LM_FOCUSY") != "" else 0.6) - 0.8
			var dist := float(OS.get_environment("LM_DIST")) if OS.get_environment("LM_DIST") != "" else 2.6
			scene.rig._target_distance = dist
			scene.rig.distance = dist
			scene.rig.pitch = deg_to_rad(float(OS.get_environment("LM_PITCH")) if OS.get_environment("LM_PITCH") != "" else -10.0)
			scene.paused = false
		if frame > 5 and scene.paused: scene.paused = false
		var yaws := [0.0, PI / 2, PI, -PI / 2]
		for i in 4:
			if frame == 10 + i * 6:
				scene.rig.yaw = k.rotation.y + yaws[i]
			if frame == 14 + i * 6:
				_save("gear_%d" % i)
		if frame == 40:
			var vv: UnitVisual = k.visual
			var inv := k.global_transform.affine_inverse()
			print("hipdebug hip ", inv * vv.hip_slot.global_position, " back ", inv * vv.back_slot.global_position, " hand_r ", inv * vv.hand_r.global_position)
			print("hip basis x ", (inv.basis * vv.hip_slot.global_basis.x).normalized(), " y ", (inv.basis * vv.hip_slot.global_basis.y).normalized(), " z ", (inv.basis * vv.hip_slot.global_basis.z).normalized(), " children ", vv.hip_slot.get_child_count(), " scale ", vv.hip_slot.global_basis.get_scale())
			for mi in vv.hip_slot.find_children("*", "MeshInstance3D", true, false):
				var ab: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
				print("mesh ", mi.name, " center ", inv * ab.get_center(), " size ", ab.size, " visible ", (mi as MeshInstance3D).is_visible_in_tree())
			get_tree().quit()
	elif plan == "goblin":
		var g: Unit = scene.units[4]
		var a: Unit = scene.party[0]
		if frame == 5:
			g.ai_state = "idle"
			g.sight = 0.0
			a.global_position = g.global_position + Vector3(8, 0, 0)
			g.visual.set_armed(true)
			scene.rig.focus(g.global_position + Vector3(0, 0.5, 0))
			scene.rig._target_distance = 3.0
			scene.rig.distance = 3.0
			scene.rig.pitch = deg_to_rad(-22.0)
			scene.rig.yaw = deg_to_rad(float(OS.get_environment("LM_YAW")) if OS.get_environment("LM_YAW") != "" else 200.0)
			scene.paused = false
		if frame > 5 and scene.paused: scene.paused = false
		if frame == 30:
			_save("gob_idle")
			var skel: Skeleton3D = g.visual.model.find_child("Skeleton3D", true, false) if g.visual.model else null
			if skel:
				var head := skel.find_bone("mixamorig_HeadTop_End")
				print("goblin height ", (skel.global_transform * skel.get_bone_global_pose(head)).origin.y - g.global_position.y, " rot ", g.rotation_degrees.y)
			g.visual.swing()
		if frame == 45:
			_save("gob_attack")
		if frame == 60:
			_save("gob_attack2")
			get_tree().quit()
	elif plan == "sheet":
		if frame == 5:
			scene.paused = false
			scene.party[2].take_damage(4, null)
			scene.party[2].xp = 50
			scene.select_unit(scene.party[2])
			scene.toggle_sheet()
		if frame == 40:
			_save("sheet_keldrin")
			scene.hud.sheet._step(-2)
		if frame == 60:
			_save("sheet_aurelia")
			scene.equip_item(scene.party[0], "wooden_shield")
			scene.hud.sheet.rebuild()
			print("aurelia main ", scene.party[0].equipment)
		if frame == 80:
			_save("sheet_aurelia2")
			get_tree().quit()
	elif plan == "uilogic":
		if frame == 5:
			Engine.max_fps = 60
			scene.paused = false
			var w: Unit = scene.party[3]
			scene.select_unit(w)
			print("actions ", scene.actions_for(scene.selection).map(func(a): return a["id"]))
			scene.use_action("attack")
			print("mode ", w.attack_mode, " profile ", w.attack_profile()["name"], " hint ", scene.target_hint())
			scene._target_clicked(scene.units[4])
			print("order ", w.order, " targeting ", scene.targeting)
			scene.use_action("cantrip")
			print("mode ", w.attack_mode, " profile ", w.attack_profile()["name"])
			scene.cancel_targeting()
			scene.party[0].take_damage(30, null)
			scene.select_unit(scene.party[2])
			scene.use_action("cure_wounds")
			scene.portrait_clicked(scene.party[0], false)
			print("keldrin order ", scene.party[2].order, " target ", scene.party[2].target.display_name)
		if frame == 5 + 60 * 5:
			print("aurelia down ", scene.party[0].down, " hp ", scene.party[0].hp)
			get_tree().quit()
	elif plan == "ui":
		if frame == 5:
			scene.paused = false
			scene.party[1].take_damage(5, null)
			scene.select_unit(scene.party[2])
		if frame == 60:
			scene.use_action("cure_wounds")
		if frame == 70:
			_save("ui_cleric")
			scene.cancel_targeting()
			scene.select_unit(scene.party[3])
		if frame == 85:
			_save("ui_wizard")
			print(scene.hud.log_label.get_parsed_text())
			get_tree().quit()
	elif plan == "helms":
		# close-ups of one item at a time on Aurelia: LM_ITEMS=slot:id,slot:id...
		var list := OS.get_environment("LM_ITEMS").split(",")
		var idx := int((frame - 10) / 12)
		var u: Unit = scene.party[int(OS.get_environment("LM_HERO")) if OS.get_environment("LM_HERO") != "" else 0]
		if frame >= 10 and (frame - 10) % 12 == 0 and idx < list.size():
			scene.paused = false
			var kv := list[idx].split(":")
			u.equipment[kv[0]] = kv[1]
			u.visual.apply_equipment(u.equipment)
			u.visual.set_armed(true)
			u._calm = -999.0
			var s := float(DataDB.heroes[u.data_id]["look"].get("scale", 1.0))
			var close := kv[0] == "head"
			scene.rig.focus(u.global_position)
			scene.rig.position.y = (1.55 if close else 1.0) * s - 0.8
			scene.rig._target_distance = (1.1 if close else 2.6) * s + 0.4
			scene.rig.distance = scene.rig._target_distance
			scene.rig.pitch = deg_to_rad(-6.0)
			scene.rig.yaw = u.rotation.y + PI + float(OS.get_environment("LM_YAWOFF") if OS.get_environment("LM_YAWOFF") != "" else "0.6")
		if frame >= 10 and (frame - 10) % 12 == 10 and idx < list.size():
			_save("it_%d" % idx)
		if frame == 10 + 12 * list.size():
			get_tree().quit()
	elif plan == "hidetest":
		var u: Unit = scene.party[0]
		var ms: Array = u.visual.model.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m.visible)
		if frame == 20:
			scene.paused = false
			scene.rig.focus(u.global_position)
			scene.rig.position.y = 0.1
			scene.rig._target_distance = 2.4
			scene.rig.distance = 2.4
			scene.rig.pitch = deg_to_rad(-35.0)
			scene.rig.yaw = u.rotation.y + float(OS.get_environment("LM_YAW2") if OS.get_environment("LM_YAW2") != "" else "3.0")
			for o in scene.party:
				if o != u: o.visible = false
			if OS.get_environment("LM_NOSHADOW") != "":
				for g in u.visual.back_slot.find_children("*", "GeometryInstance3D", true, false):
					g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for e in scene.units:
				if e.is_monster: e.visible = false
			set_meta("ms", ms)
			print("meshes ", ms.map(func(m): return m.name))
		var all: Array = get_meta("ms", [])
		var i := int((frame - 30) / 6)
		if frame >= 30 and (frame - 30) % 6 == 0 and i <= all.size():
			for k in all.size():
				all[k].visible = k != i - 1
		if frame >= 30 and (frame - 30) % 6 == 4 and i <= all.size():
			_save("hide_%d" % i)
		if frame == 30 + 6 * (all.size() + 1) and frame > 30:
			get_tree().quit()
	elif plan == "slots":
		if frame == 30:
			var u: Unit = scene.party[0]
			print("equip ", u.equipment)
			for slot in [u.visual.hand_r, u.visual.hand_l, u.visual.hip_slot, u.visual.back_slot, u.visual.head_slot, u.visual.extras]:
				if slot:
					print("slot ", slot.name, " -> ", slot.get_children().map(func(c): return str(c.name) + "(" + str(c.find_children("*", "MeshInstance3D", true, false).size()) + ")"))
			for m in u.find_children("*", "GeometryInstance3D", true, false):
				if m.is_visible_in_tree() and not u.visual.model.is_ancestor_of(m):
					print("visible mesh ", m.name, " ", m.get_class(), " path ", u.get_path_to(m))
			get_tree().quit()
	elif plan == "styles":
		var u: Unit = scene.party[int(OS.get_environment("LM_HERO")) if OS.get_environment("LM_HERO") != "" else 0]
		var combos := OS.get_environment("LM_COMBOS").split(";")
		var idx := int((frame - 10) / 70)
		var ph := (frame - 10) % 70
		if frame >= 10 and idx < combos.size():
			if ph == 0:
				scene.paused = false
				for o in scene.units:
					if o != u: o.visible = false
				for kv in combos[idx].split(","):
					var p2 := kv.split(":")
					u.equipment[p2[0]] = p2[1]
				u.visual.apply_equipment(u.equipment)
				u._calm = -999.0
				u.visual.set_armed(true)
				var s := float(DataDB.heroes[u.data_id]["look"].get("scale", 1.0))
				scene.rig.focus(u.global_position)
				scene.rig.position.y = 0.95 * s - 0.8
				scene.rig._target_distance = 3.2 * s + 0.4
				scene.rig.distance = scene.rig._target_distance
				scene.rig.pitch = deg_to_rad(-8.0)
				scene.rig.yaw = u.rotation.y + PI + 0.9
			if ph == 20:
				_save("st_%d_idle" % idx)
				u.visual.swing()
				var ap: AnimationPlayer = u.visual.anim_player
				var an := ap.get_animation(ap.current_animation)
				for ti in an.get_track_count():
					if an.track_get_type(ti) == Animation.TYPE_POSITION_3D:
						print("postrack ", an.track_get_path(ti), " k0 ", an.track_get_key_value(ti, 0), " kmid ", an.track_get_key_value(ti, an.track_get_key_count(ti) / 2))
			for k in 3:
				if ph == 30 + k * 12:
					_save("st_%d_a%d" % [idx, k])
		if frame == 10 + 70 * combos.size():
			get_tree().quit()
	elif plan == "gallery":
		var combos := [
			[0, {"main_hand": "longsword", "off_hand": "heater_shield", "head": "great_helm"}],
			[0, {"main_hand": "zweihander", "off_hand": "", "head": "winged_helm"}],
			[0, {"main_hand": "battleaxe", "off_hand": "kite_shield", "head": "barbuta"}],
			[2, {"main_hand": "warhammer", "off_hand": "lion_shield", "head": "kettle_hat"}],
			[2, {"main_hand": "mace", "off_hand": "wooden_shield", "head": "iron_helm"}],
			[1, {"main_hand": "light_crossbow", "off_hand": "", "head": ""}],
			[3, {"main_hand": "quarterstaff", "off_hand": "", "head": ""}],
			[1, {"main_hand": "dagger", "off_hand": "", "head": ""}],
		]
		var idx := int((frame - 10) / 14)
		if frame >= 10 and (frame - 10) % 14 == 0 and idx < combos.size():
			scene.paused = false
			var c: Array = combos[idx]
			var u: Unit = scene.party[c[0]]
			for k in c[1]:
				u.equipment[k] = c[1][k]
			u.visual.apply_equipment(u.equipment)
			u.visual.set_armed(true)
			u._calm = -999.0
			var s := float(DataDB.heroes[u.data_id]["look"].get("scale", 1.0))
			scene.rig.focus(u.global_position + Vector3(0, 1.0 * s, 0))
			scene.rig._target_distance = 2.6 * s + 0.6
			scene.rig.distance = 2.6 * s + 0.6
			scene.rig.pitch = deg_to_rad(-10.0)
			scene.rig.yaw = u.rotation.y + PI + 0.5
		if frame >= 10 and (frame - 10) % 14 == 12 and idx < combos.size():
			_save("gal_%d" % idx)
		if frame == 10 + 14 * combos.size():
			get_tree().quit()
	elif plan == "heights":
		if frame == 20:
			for u in scene.party:
				var hv: UnitVisual = u.visual
				var skel: Skeleton3D = hv.model.find_child("Skeleton3D", true, false)
				var head := skel.find_bone("mixamorig_HeadTop_End")
				var ht: float = (skel.global_transform * skel.get_bone_global_pose(head)).origin.y - u.global_position.y if head >= 0 else -1.0
				print("height ", u.data_id, " ", ht, " scale ", hv.body.scale.x)
			get_tree().quit()
	elif plan == "healshot":
		var k: Unit = scene.party[2]
		var a: Unit = scene.party[0]
		if frame == 5:
			a.global_position = k.global_position + Vector3(1.2, 0, -0.6)
			a.take_damage(10, null)
			scene.rig.focus(k.global_position + Vector3(0.6, 0.6, -0.3))
			scene.rig._target_distance = 4.5
			scene.rig.distance = 4.5
			scene.rig.pitch = deg_to_rad(-18.0)
			scene.rig.yaw = PI + 0.9
			scene.paused = false
		if frame > 5 and scene.paused: scene.paused = false
		if frame == 20:
			k.order_heal(a)
		if frame == 50:
			_save("heal_cast")
		if frame == 70:
			_save("heal_glow")
			get_tree().quit()
	elif plan == "heal":
		var k: Unit = scene.party[2]
		var a: Unit = scene.party[0]
		if frame == 5:
			Engine.max_fps = 60
			print("keldrin slots ", k.spell_slots, " spells ", DataDB.heroes["keldrin"].get("spells"))
			a.take_damage(30, null)
			print("aurelia down: ", a.down, " hp ", a.hp)
		if frame > 5 and scene.paused: scene.paused = false
		if frame == 5 + 60 * 6:
			print("aurelia down: ", a.down, " hp ", a.hp, "/", a.max_hp, " keldrin slots ", k.spell_slots)
			scene.select_unit(k, false)
			scene.cmd_heal()
		if frame == 5 + 60 * 12:
			print(scene.hud.log_label.get_parsed_text())
			print("aurelia hp ", a.hp, " keldrin slots ", k.spell_slots)
			get_tree().quit()
	elif plan == "bowlogic":
		var p: Unit = scene.party[1]
		if frame == 5:
			Engine.max_fps = 60
			print("pip weapon: ", p.attack_profile(), " speed ", p.speed, " shirvani off: ", scene.party[3].equipment.get("off_hand"))
			p.global_position = Vector3(23, 0, 20)
			var g: Unit = scene.units[4]
			print("distance to goblin: ", p.global_position.distance_to(g.global_position), " LOS ", scene.line_of_sight(p.global_position, g.global_position))
			p.order_attack(g)
		if frame > 5 and scene.paused: scene.paused = false
		if frame == 5 + 60 * 10:
			print(scene.hud.log_label.get_parsed_text())
			print("pip pos ", p.global_position, " arrows in flight ", scene._arrows.size())
			get_tree().quit()
	elif plan == "draw":
		var a: Unit = scene.party[0]
		if frame == 5:
			Engine.max_fps = 60
			scene.paused = false
			print("frame 5 armed: ", a.visual.armed)
			var g: Unit = scene.units[4]
			a.order_attack(g)
		if frame == 15:
			print("ordered attack -> armed: ", a.visual.armed)
			a.stop()
			for u in scene.units:
				if u.is_monster: u.down = true
		if frame == 15 + 60 * 4:
			print("4 s after fight -> armed: ", a.visual.armed)
			get_tree().quit()
		if frame > 5 and scene.paused: scene.paused = false
	elif plan == "anims":
		if frame == 10:
			var ap: AnimationPlayer = scene.party[0].visual.anim_player
			print("animation libraries: ", ap.get_animation_library_list(), " playing: ", ap.current_animation)
			get_tree().quit()
	elif plan == "sword":
		if frame == 20:
			var a: Unit = scene.party[0]
			var aabb := AABB(); var first := true
			for m in a.visual.hand_r.find_children("*", "MeshInstance3D", true, false):
				var bb: AABB = m.global_transform * m.get_aabb()
				aabb = bb if first else aabb.merge(bb); first = false
			print("sword world aabb ", aabb.size, " hand at ", a.visual.hand_r.global_position, " unit at ", a.global_position)
			get_tree().quit()
	elif plan == "walkseq":
		var a: Unit = scene.party[int(OS.get_environment("LM_HERO")) if OS.get_environment("LM_HERO") != "" else 0]
		if frame == 2 and OS.get_environment("LM_MODEL") != "":
			var lk: Dictionary = DataDB.heroes[a.data_id]["look"].duplicate()
			lk["model"] = OS.get_environment("LM_MODEL")
			lk["scale"] = 1.0
			a.visual.build(lk)
			a.visual.apply_equipment(a.equipment)
		if frame == 5:
			scene.paused = false
			scene.rig._target_distance = 3.2
			scene.rig.distance = 3.2
			scene.rig.pitch = deg_to_rad(-8.0)
			a.order_move(a.global_position + Vector3(-12, 0, 0))
		if frame > 5:
			scene.rig.focus(a.global_position + Vector3(0, float(OS.get_environment("LM_FOCUSY")) if OS.get_environment("LM_FOCUSY") != "" else 0.9, 0))
			scene.rig.yaw = PI * 0.0
		for i in 4:
			if frame == 40 + i * 6:
				_save("walk_%d" % i)
		if frame == 66:
			get_tree().quit()
	elif plan == "lineup":
		# the party side by side, facing the camera (heights, silhouettes)
		if frame == 3:
			for i in scene.party.size():
				var u: Unit = scene.party[i]
				u.global_position = Vector3(21.8 + i * 1.0, 0, 30)
				u.rotation.y = 0.0
				u.order_move(u.global_position)
			scene.rig.focus(Vector3(23.3, 0.8, 30))
			scene.rig._target_distance = 6.5
			scene.rig.distance = 6.5
			scene.rig.pitch = deg_to_rad(-6.0)
			scene.rig.yaw = PI
			scene.paused = false
		if frame > 3 and scene.paused: scene.paused = false
		if frame == 40:
			_save("lineup")
			get_tree().quit()
	elif plan == "view":
		# a still from anywhere: LM_FOCUS="x,z", LM_DIST, LM_PITCH, LM_YAW (degrees)
		if frame == 3:
			var f := OS.get_environment("LM_FOCUS").split(",") if OS.get_environment("LM_FOCUS") != "" else PackedStringArray()
			if f.size() == 2:
				var fx := float(f[0])
				var fz := float(f[1])
				scene.rig.focus(Vector3(fx, scene.ground_y(Vector3(fx, 0, fz)), fz))
			var dist := float(OS.get_environment("LM_DIST")) if OS.get_environment("LM_DIST") != "" else 14.0
			scene.rig._target_distance = dist
			scene.rig.distance = dist
			scene.rig.pitch = deg_to_rad(float(OS.get_environment("LM_PITCH")) if OS.get_environment("LM_PITCH") != "" else -40.0)
			scene.rig.yaw = deg_to_rad(float(OS.get_environment("LM_YAW")) if OS.get_environment("LM_YAW") != "" else 0.0)
		if frame == 40:
			_save(OS.get_environment("LM_NAME") if OS.get_environment("LM_NAME") != "" else "view")
			get_tree().quit()
	elif plan == "ambush":
		# the party walks up the road; prints what happens (run headless for speed)
		if frame == 5:
			scene.paused = false
			for u in scene.party:
				u.order_move(Vector3(u.global_position.x, 0, 38 + (u.global_position.z - 80)))
		if frame > 5 and scene.paused: scene.paused = false
		if frame % 300 == 0:
			var line := "t=%d" % frame
			for u in scene.units:
				line += " %s(%.0f,%.0f,y%.1f hp%d %s)" % [u.data_id.substr(0, 3), u.global_position.x, u.global_position.z, u.global_position.y, u.hp, u.ai_state if u.is_monster else u.order]
			print(line)
		if frame == 3600:
			print(scene.hud.log_label.get_parsed_text())
			get_tree().quit()
	elif plan == "outfits":
		# prints which outfit meshes a hero shows
		if frame == 10:
			var hu: Unit = scene.party[int(OS.get_environment("LM_HERO")) if OS.get_environment("LM_HERO") != "" else 0]
			for m in hu.visual.model.find_children("*", "MeshInstance3D", true, false):
				print("MESH ", m.name, " visible=", (m as Node3D).is_visible_in_tree())
			get_tree().quit()
	elif plan == "rootcheck":
		# prints how far the hips move in every animation of every set
		if frame == 5:
			var hero := OS.get_environment("LM_HERO")
			for hu in scene.party:
				if hero != "" and hu.data_id != hero:
					continue
				var v = hu.visual
				var sk: Skeleton3D = v._skel
				var hb := sk.find_bone("mixamorig_Hips")
				if hb < 0:
					hb = sk.find_bone("mixamorig:Hips")
				for sid in DataDB.animation_sets.keys():
					v._set_id = ""
					v._load_set(sid)
					var ap: AnimationPlayer = v.anim_player
					for an in ap.get_animation_list():
						var a: Animation = ap.get_animation(an)
						ap.play(an, 0.0)
						var first := Vector3.ZERO
						var mx := 0.0
						var my := -9.0
						var steps := 30
						var lows := 0.0
						var feet := [sk.find_bone("mixamorig_LeftToeBase"), sk.find_bone("mixamorig_RightToeBase"), sk.find_bone("mixamorig_LeftFoot"), sk.find_bone("mixamorig_RightFoot")]
						for i in steps + 1:
							ap.seek(a.length * i / steps, true)
							var hp: Vector3 = sk.get_bone_global_pose(hb).origin
							var wp: Vector3 = sk.global_transform * hp - hu.global_position
							if i == 0:
								first = wp
							mx = maxf(mx, Vector2(wp.x - first.x, wp.z - first.z).length())
							my = maxf(my, wp.y)
							var lo := 9.0
							for fb in feet:
								lo = minf(lo, (sk.global_transform * sk.get_bone_global_pose(fb).origin).y - hu.global_position.y)
							lows += lo / (steps + 1)
						if OS.get_environment("LM_FEET") != "" and (an.begins_with("idle") or an.begins_with("walk")):
							print("FEET %s %s %s %.3f" % [hu.data_id, sid, an, lows])
						var ky := -9.0
						for ti in a.get_track_count():
							if a.track_get_type(ti) == Animation.TYPE_POSITION_3D:
								for k in a.track_get_key_count(ti):
									ky = maxf(ky, a.track_get_key_value(ti, k).y)
						if mx > 0.25 or my > 1.6:
							print("KEYMAX ", ky, " skel=", sk.global_transform.basis.get_scale(), " unit=", hu.global_position)
							print("ROOT %s %s %s xz=%.2f maxy=%.2f" % [hu.data_id, sid, an, mx, my])
			get_tree().quit()
	elif plan == "model":
		var a: Unit = scene.party[int(OS.get_environment("LM_HERO")) if OS.get_environment("LM_HERO") != "" else 0]
		if frame == 2 and OS.get_environment("LM_MODEL") != "":
			var lk: Dictionary = DataDB.heroes[a.data_id]["look"].duplicate()
			lk["model"] = OS.get_environment("LM_MODEL")
			lk["scale"] = 1.0
			a.visual.build(lk)
			a.visual.apply_equipment(a.equipment)
		if frame == 5:
			scene.rig.focus(a.global_position)
			scene.rig._target_distance = 5.5
			scene.rig.distance = 5.5
			scene.rig.pitch = deg_to_rad(-25.0)
			scene.rig.yaw = PI + 0.5
			scene.paused = false
		if frame == 50:
			_save("model_idle")
			print("armed at idle: ", a.visual.armed)
			a.order_move(a.global_position + Vector3(-2, 0, 3))
		if frame > 50 and frame < 75:
			scene.rig.focus(a.global_position)
		if frame == 68:
			_save("model_walk")
		if frame == 90:
			a.visual.swing()
		if frame == 104:
			_save("model_attack")
			get_tree().quit()
	elif plan == "shadow":
		if frame == 5:
			scene.rig.focus(Vector3(23, 0, 24))
			scene.rig._target_distance = 11.0
			scene.rig.distance = 11.0
			scene.paused = false
			for u in scene.party:
				u.ai_state = "idle"
		if frame == 60:
			_save("shadow1")
			scene.party[1].order_move(Vector3(19, 0, 22))
		if frame == 160:
			_save("shadow2")
			get_tree().quit()
	elif plan == "gear":
		if frame == 5:
			var t: Unit = scene.party[0]
			scene.select_unit(t)
			scene.cmd_cycle("armor", ["armor"])
			scene.cmd_cycle("armor", ["armor"])
			scene.cmd_cycle("main_hand", ["weapon"])
			scene.cmd_toggle("head", "helmet")
			scene.rig.focus(t.global_position + Vector3(0, 0, -0.5))
			scene.rig._target_distance = 6.5
			scene.rig.distance = 6.5
		if frame == 70:
			_save("gear")
			get_tree().quit()
	elif plan == "twohand":
		if frame == 10:
			var t: Unit = scene.party[0]
			scene.select_unit(t)
			print("start: ", t.equipment, " AC ", t.ac(), " atk ", t.attack_profile())
			scene.cmd_toggle("off_hand", "shield")
			scene.cmd_cycle("main_hand", ["weapon"])
			scene.cmd_toggle("off_hand", "shield")
			print("one-hand + shield: ", t.equipment, " AC ", t.ac())
			scene.cmd_cycle("main_hand", ["weapon"])
			scene.cmd_cycle("main_hand", ["weapon"])
			print("back to greatsword: ", t.equipment, " AC ", t.ac(), " inv ", t.inventory)
			print(scene.hud.log_label.get_parsed_text())
			get_tree().quit()
	elif plan == "equip":
		if frame == 10:
			var t: Unit = scene.party[0]
			scene.select_unit(t)
			print("AC before: ", t.ac())
			scene.cmd_cycle("armor", ["armor"])
			print("AC after armor swap: ", t.ac(), " ", t.equipment)
			scene.cmd_cycle("armor", ["armor"])
			scene.cmd_cycle("main_hand", ["weapon"])
			scene.cmd_toggle("head", "helmet")
			scene.cmd_toggle("off_hand", "shield")
			scene.cmd_toggle("off_hand", "shield")
			print("final: ", t.equipment, " AC ", t.ac(), " atk ", t.attack_profile())
			# live data reload: change goblin AC on disk
			var f := FileAccess.open("res://data/monsters.json", FileAccess.READ)
			var txt := f.get_as_text(); f.close()
			var w := FileAccess.open("res://data/monsters.json", FileAccess.WRITE)
			w.store_string(txt.replace('"ac": 15', '"ac": 17')); w.close()
		if frame == 200:
			print("goblin AC after reload: ", scene.units[4].ac())
			var f2 := FileAccess.open("res://data/monsters.json", FileAccess.READ)
			var txt2 := f2.get_as_text(); f2.close()
			var w2 := FileAccess.open("res://data/monsters.json", FileAccess.WRITE)
			w2.store_string(txt2.replace('"ac": 17', '"ac": 15')); w2.close()
		if frame == 320:
			print(scene.hud.log_label.get_parsed_text())
			get_tree().quit()
	else:
		if frame == 60:
			_save("start")
			get_tree().quit()

func _save(n: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(out + "/" + n + ".png")
	print("saved ", n)
