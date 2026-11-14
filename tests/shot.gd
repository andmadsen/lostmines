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
		var a: Unit = scene.party[0]
		if frame == 5:
			scene.rig.focus(a.global_position)
			scene.rig._target_distance = 5.5
			scene.rig.distance = 5.5
			scene.rig.pitch = deg_to_rad(-25.0)
			scene.rig.yaw = PI + 0.5
			scene.paused = false
		if frame == 50:
			_save("model_idle")
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
