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
	scene = load("res://scenes/test_cave.tscn").instantiate()
	add_child(scene)

func _process(_d: float) -> void:
	frame += 1
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
			if OS.get_environment("LM_SHEATHED") == "":
				k.visual.set_armed(true)
				k._calm = -999.0
			scene.rig.focus(k.global_position + Vector3(0, 0.6, 0))
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
	elif plan == "model":
		var a: Unit = scene.party[int(OS.get_environment("LM_HERO")) if OS.get_environment("LM_HERO") != "" else 0]
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
