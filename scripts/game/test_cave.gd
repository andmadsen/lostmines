extends Node3D
## Test scene: one cave passage with torchlight, four heroes and a few goblins.
## Proves camera, lighting, party control, real-time-with-pause combat,
## visible equipment and live data reloading.

const LAYOUT: Array[String] = [
	"######################",
	"#########...T#########",
	"#######..........#####",
	"######............####",
	"#####T.............###",
	"#####..............T##",
	"######.............###",
	"#######..........#####",
	"#########......#######",
	"##########....########",
	"##########T...########",
	"##########....########",
	"#########......#######",
	"########........######",
	"#######.........T#####",
	"#######..........#####",
	"#######T.........#####",
	"#########.....########",
	"##########...#########",
	"######################",
]
const HERO_IDS: Array[String] = ["aurelia", "pip", "keldrin", "shirvani"]
const HERO_START: Array[Vector2i] = [Vector2i(11, 14), Vector2i(10, 15), Vector2i(12, 15), Vector2i(11, 16)]
const GOBLINS: Array[Vector2i] = [Vector2i(11, 3), Vector2i(8, 4), Vector2i(14, 5)]

var cave: CaveBuilder
var rig: CameraRig
var hud: Hud
var units: Array[Unit] = []
var party: Array[Unit] = []
var selection: Array[Unit] = []
var paused := false
var astar := AStarGrid2D.new()

var _drag_start := Vector2.ZERO
var _dragging := false
var _drag_active := false
var _hover: Unit = null
var _sighted := false
var _arrows: Array[Dictionary] = []


func _ready() -> void:
	_setup_environment()
	cave = CaveBuilder.new()
	add_child(cave)
	cave.build(LAYOUT)
	_setup_astar()

	rig = CameraRig.new()
	add_child(rig)
	rig.bounds = Rect2(0, 0, cave.w * CaveBuilder.TILE, cave.h * CaveBuilder.TILE)

	for i in HERO_IDS.size():
		var u := _spawn_unit(cave.cell_center(HERO_START[i]))
		u.setup_hero(HERO_IDS[i])
		u.rotation.y = 0.0
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(0.3, 2.3, 0)
		lamp.light_color = Color(1.0, 0.88, 0.75)
		lamp.light_energy = 0.35
		lamp.omni_range = 4.0   # faint fill light; the real light comes from held torches
		u.add_child(lamp)
		party.append(u)
	for c in GOBLINS:
		var g := _spawn_unit(cave.cell_center(c))
		g.setup_monster("goblin")
		g.rotation.y = PI

	hud = Hud.new()
	hud.game = self
	add_child(hud)
	hud.build_portraits(party)
	DataDB.data_changed.connect(_on_data_changed)

	selection = party.duplicate()
	for u in party:
		u.set_selected(true)
	rig.focus(party[0].global_position + Vector3(0, 0, -3))

	log_line("[i]The passage reeks of smoke and wet fur. Somewhere ahead, something laughs in a high, nasty voice.[/i]")
	log_line("[color=#9fd3ff]Press H for controls. Space pauses the game.[/color]")


func _spawn_unit(pos: Vector3) -> Unit:
	var u := Unit.new()
	u.game = self
	add_child(u)
	u.global_position = pos
	units.append(u)
	return u


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.4, 0.55)
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.15
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.0
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.02
	env.volumetric_fog_albedo = Color(0.85, 0.8, 0.75)
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _setup_astar() -> void:
	astar.region = Rect2i(0, 0, cave.w, cave.h)
	astar.cell_size = Vector2(CaveBuilder.TILE, CaveBuilder.TILE)
	astar.offset = Vector2(CaveBuilder.TILE / 2.0, CaveBuilder.TILE / 2.0)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in cave.h:
		for x in cave.w:
			astar.set_point_solid(Vector2i(x, y), not cave.is_floor(x, y))


# ---------------- per-frame ----------------
func _process(delta: float) -> void:
	if not paused:
		for u in units:
			u.tick(delta)
		_separate()
		_update_arrows(delta)
	hud.refresh()


func _separate() -> void:
	for i in units.size():
		var a := units[i]
		if a.down:
			continue
		for j in range(i + 1, units.size()):
			var b := units[j]
			if b.down:
				continue
			var d := Vector2(b.global_position.x - a.global_position.x, b.global_position.z - a.global_position.z)
			var l := d.length()
			if l < 0.8 and l > 0.001:
				var push := (0.8 - l) / 2.0
				var n := d / l
				_try_nudge(a, -n * push)
				_try_nudge(b, n * push)


func _try_nudge(u: Unit, v: Vector2) -> void:
	var p := u.global_position + Vector3(v.x, 0, v.y)
	var c := cave.world_to_cell(p)
	if cave.is_floor(c.x, c.y):
		u.global_position = p


# ---------------- input ----------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_active = false
				_drag_start = mb.position
			elif _dragging:
				_dragging = false
				if _drag_active:
					_box_select(_drag_start, mb.position, mb.shift_pressed)
				else:
					_click(mb.position, mb.shift_pressed)
				_drag_active = false
				hud.set_drag(false)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging and mm.position.distance_to(_drag_start) > 8.0:
			_drag_active = true
			hud.set_drag(true, _drag_start, mm.position)
		_update_hover(mm.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		match k.keycode:
			KEY_SPACE:
				toggle_pause()
			KEY_H:
				hud.help_panel.visible = not hud.help_panel.visible
			KEY_F:
				if selection.size() > 0:
					rig.focus(selection[0].global_position)
			KEY_X:
				cmd_stop()
			KEY_C:
				cmd_heal()
			KEY_F5:
				get_tree().reload_current_scene()
			KEY_A:
				if k.ctrl_pressed:
					_select_list(party.filter(func(u): return not u.down))
			KEY_1, KEY_2, KEY_3, KEY_4:
				var i := int(k.keycode - KEY_1)
				if i < party.size():
					select_unit(party[i], k.shift_pressed)


func _click(pos: Vector2, shift: bool) -> void:
	var u := _unit_at(pos)
	if u:
		if u.faction == "party":
			select_unit(u, shift)
		else:
			for s in selection:
				s.order_attack(u)
		return
	var p = _ground_at(pos)
	if p == null:
		return
	_move_selection(p)


func _move_selection(dest: Vector3) -> void:
	var movers := selection.filter(func(u): return not u.down)
	if movers.is_empty():
		return
	var centre := Vector3.ZERO
	for u in movers:
		centre += u.global_position
	centre /= movers.size()
	var dir := Vector2(dest.x - centre.x, dest.z - centre.z)
	var ang := atan2(dir.x, dir.y) if dir.length() > 0.1 else 0.0
	var offsets := [Vector2(0, 0), Vector2(-1.1, -1.1), Vector2(1.1, -1.1), Vector2(0, -2.2), Vector2(-1.1, -3.3), Vector2(1.1, -3.3)]
	for i in movers.size():
		var o: Vector2 = offsets[i % offsets.size()] if movers.size() > 1 else Vector2.ZERO
		var r := o.rotated(-ang)
		var t := dest + Vector3(r.x, 0, r.y)
		var c := cave.world_to_cell(t)
		if not cave.is_floor(c.x, c.y):
			t = dest
		movers[i].order_move(t)
	_click_marker(dest)


func _box_select(a: Vector2, b: Vector2, shift: bool) -> void:
	var r := Rect2(a, Vector2.ZERO).expand(b)
	var picked: Array[Unit] = []
	for u in party:
		if u.down:
			continue
		var sp := rig.camera.unproject_position(u.global_position + Vector3(0, 0.9, 0))
		if r.has_point(sp):
			picked.append(u)
	if picked.is_empty():
		return
	if shift:
		for u in picked:
			if not selection.has(u):
				selection.append(u)
		_select_list(selection.duplicate())
	else:
		_select_list(picked)


func select_unit(u: Unit, add := false) -> void:
	if u.down:
		return
	if add:
		if selection.has(u):
			selection.erase(u)
		else:
			selection.append(u)
		_select_list(selection.duplicate())
	else:
		_select_list([u])


func _select_list(list: Array) -> void:
	for u in party:
		u.set_selected(false)
	selection.clear()
	for u in list:
		selection.append(u)
		u.set_selected(true)


func _unit_at(pos: Vector2) -> Unit:
	var best: Unit = null
	var bd := 34.0
	for u in units:
		if u.down:
			continue
		var wp := u.global_position + Vector3(0, 0.9, 0)
		if rig.camera.is_position_behind(wp):
			continue
		var d := rig.camera.unproject_position(wp).distance_to(pos)
		if d < bd:
			bd = d
			best = u
	return best


func _ground_at(pos: Vector2):
	var from := rig.camera.project_ray_origin(pos)
	var dir := rig.camera.project_ray_normal(pos)
	return Plane(Vector3.UP, 0.0).intersects_ray(from, dir)


func _update_hover(pos: Vector2) -> void:
	var u := _unit_at(pos)
	if u != _hover:
		if _hover and _hover.faction == "enemy" and not _hover.down:
			_hover.set_selected(false)
		_hover = u
		if u and u.faction == "enemy":
			u.ring.visible = true
	if u:
		var state := "Unhurt"
		var f := float(u.hp) / float(u.max_hp)
		if f < 1.0: state = "Wounded"
		if f < 0.5: state = "Badly wounded"
		if f < 0.2: state = "Near death"
		var txt := u.display_name + "\n" + ("HP %d/%d · AC %d" % [u.hp, u.max_hp, u.ac()] if u.faction == "party" else state)
		hud.show_tooltip(txt, pos)
	else:
		hud.show_tooltip("", pos)


# ---------------- commands ----------------
func toggle_pause() -> void:
	paused = not paused
	hud.set_pause_reason("")


func cmd_stop() -> void:
	for u in selection:
		u.stop()


## Cycles an equipment slot through matching items in the hero's inventory.
func cmd_cycle(slot: String, types: Array) -> void:
	if selection.size() != 1:
		return
	var u := selection[0]
	var options: Array = []
	for id in u.inventory:
		if types.has(str(DataDB.item(str(id)).get("type", ""))):
			options.append(id)
	if options.is_empty():
		log_line("%s has nothing else to swap to." % name_tag(u))
		return
	var next_id: String = options[0]
	u.inventory.erase(next_id)
	var cur := str(u.equipment.get(slot, ""))
	if cur != "":
		u.inventory.append(cur)
	u.equipment[slot] = next_id
	# a two-handed weapon needs the off hand free
	if slot == "main_hand" and bool(DataDB.item(next_id).get("two_handed", false)):
		var off := str(u.equipment.get("off_hand", ""))
		if off != "":
			u.inventory.append(off)
			u.equipment["off_hand"] = ""
			log_line("%s puts away the %s to use both hands." % [name_tag(u), DataDB.item(off).get("name", off)])
	u.visual.apply_equipment(u.equipment)
	log_line("%s equips the %s." % [name_tag(u), DataDB.item(next_id).get("name", next_id)])


## Toggles an item type in a slot: takes it off if worn, otherwise puts the
## first one from the inventory on (swapping out whatever was there).
func cmd_toggle(slot: String, type: String) -> void:
	if selection.size() != 1:
		return
	var u := selection[0]
	if slot == "off_hand" and bool(DataDB.item(str(u.equipment.get("main_hand", ""))).get("two_handed", false)):
		if str(u.equipment.get("off_hand", "")) == "":
			log_line("%s needs both hands for the %s." % [name_tag(u), DataDB.item(str(u.equipment.get("main_hand", ""))).get("name", "weapon")])
			return
	var cur := str(u.equipment.get(slot, ""))
	if cur != "" and str(DataDB.item(cur).get("type", "")) == type:
		u.inventory.append(cur)
		u.equipment[slot] = ""
		log_line("%s puts away the %s." % [name_tag(u), DataDB.item(cur).get("name", cur)])
	else:
		var found := ""
		for id in u.inventory:
			if str(DataDB.item(str(id)).get("type", "")) == type:
				found = str(id)
				break
		if found == "":
			log_line("%s has no %s." % [name_tag(u), type])
			return
		u.inventory.erase(found)
		if cur != "":
			u.inventory.append(cur)
		u.equipment[slot] = found
		log_line("%s takes out the %s." % [name_tag(u), DataDB.item(found).get("name", found)])
	u.visual.apply_equipment(u.equipment)


# ---------------- services used by units ----------------
func find_path(from: Vector3, to: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var a := cave.world_to_cell(from)
	var b := cave.world_to_cell(to)
	var exact := cave.is_floor(b.x, b.y)
	if not exact:
		b = _nearest_floor(b)
	if not cave.is_floor(a.x, a.y):
		a = _nearest_floor(a)
	var pts := astar.get_point_path(a, b, true)
	for i in range(1, pts.size()):
		out.append(Vector3(pts[i].x, 0, pts[i].y))
	if exact:
		if out.is_empty():
			out.append(Vector3(to.x, 0, to.z))
		else:
			out[out.size() - 1] = Vector3(to.x, 0, to.z)
	return out


func _nearest_floor(c: Vector2i) -> Vector2i:
	for r in range(1, 6):
		for y in range(c.y - r, c.y + r + 1):
			for x in range(c.x - r, c.x + r + 1):
				if cave.is_floor(x, y):
					return Vector2i(x, y)
	return c


## The party member who most needs healing (unconscious first), or null.
func most_wounded(near: Unit) -> Unit:
	var best: Unit = null
	var bs := 2.0
	for u in party:
		if u.hp >= u.max_hp:
			continue
		var score := float(u.hp) / float(u.max_hp) - (1.0 if u.down else 0.0) + near.global_position.distance_to(u.global_position) * 0.005
		if score < bs:
			bs = score
			best = u
	return best


## Selected healer casts Cure Wounds on whoever needs it most.
func cmd_heal() -> void:
	for u in selection:
		if u.knows_spell("cure_wounds"):
			var t := most_wounded(u)
			if t == null:
				log_line("Nobody needs healing right now.")
			else:
				u.order_heal(t)
			return
	log_line("Select Keldrin (or another healer) to cast Cure Wounds.")


## Soft golden light rising around a healed creature.
func heal_glow(p: Vector3, col: Color) -> void:
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 0.0
	light.omni_range = 4.0
	add_child(light)
	light.global_position = p + Vector3(0, 1.2, 0)
	var ring_mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.45
	tm.outer_radius = 0.55
	ring_mi.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(col, 0.8)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 3.0
	ring_mi.material_override = m
	add_child(ring_mi)
	ring_mi.global_position = p + Vector3(0, 0.1, 0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(light, "light_energy", 4.0, 0.25)
	tw.tween_property(ring_mi, "position:y", ring_mi.position.y + 1.8, 1.0)
	tw.tween_property(m, "albedo_color:a", 0.0, 1.0)
	tw.chain().tween_property(light, "light_energy", 0.0, 0.4)
	tw.chain().tween_callback(func():
		light.queue_free()
		ring_mi.queue_free())


## True if a living hostile creature stands right next to u.
func enemy_adjacent(u: Unit) -> bool:
	for o in units:
		if o.faction != u.faction and not o.down and (o.ai_state == "combat" or not o.is_monster) and o.global_position.distance_to(u.global_position) < 2.3:
			return true
	return false


## Fires an arrow from shooter to target. on_hit runs when it arrives
## (it logs the hit or miss and applies damage). Flight respects pause.
func shoot_arrow(shooter: Unit, target: Unit, delay: float, hit: bool, on_hit: Callable, look: Dictionary = {}) -> void:
	_arrows.append({"shooter": shooter, "target": target, "delay": delay, "hit": hit, "cb": on_hit, "node": null, "t": 0.0, "look": look})


func _update_arrows(delta: float) -> void:
	for i in range(_arrows.size() - 1, -1, -1):
		var a: Dictionary = _arrows[i]
		if a["node"] == null:
			a["delay"] = float(a["delay"]) - delta
			if float(a["delay"]) > 0.0:
				continue
			var sh: Unit = a["shooter"]
			var tg: Unit = a["target"]
			if not is_instance_valid(sh) or not is_instance_valid(tg):
				_arrows.remove_at(i)
				continue
			var s := float(DataDB.heroes.get(sh.data_id, {}).get("look", {}).get("scale", 1.0)) if not sh.is_monster else 0.8
			var start := sh.global_position + Vector3(0, 1.35 * s, 0) + (tg.global_position - sh.global_position).normalized() * 0.4
			var end := tg.global_position + Vector3(0, 1.0, 0)
			if not bool(a["hit"]):
				var side := (end - start).cross(Vector3.UP).normalized() * randf_range(-0.9, 0.9)
				end += side + (end - start).normalized() * 2.5 + Vector3(0, randf_range(-0.6, 0.3), 0)
			a["start"] = start
			a["end"] = end
			var look: Dictionary = a["look"]
			a["dur"] = maxf(0.08, start.distance_to(end) / float(look.get("speed", 32.0)))
			var node := _make_arrow() if str(look.get("kind", "arrow")) == "arrow" else _make_bolt(look)
			add_child(node)
			node.global_position = start
			a["node"] = node
		var n: Node3D = a["node"]
		a["t"] = float(a["t"]) + delta
		var k := clampf(float(a["t"]) / float(a["dur"]), 0.0, 1.0)
		var st: Vector3 = a["start"]
		var en: Vector3 = a["end"]
		var pos := st.lerp(en, k) + Vector3(0, sin(k * PI) * st.distance_to(en) * 0.04, 0)
		if pos.distance_to(n.global_position) > 0.001:
			n.look_at_from_position(n.global_position, pos, Vector3.UP)
		n.global_position = pos
		if k >= 1.0:
			if str((a["look"] as Dictionary).get("kind", "arrow")) != "arrow":
				_burst(n.global_position, Color.html(str((a["look"] as Dictionary).get("color", "#ff8a2a"))))
				n.visible = false
			(a["cb"] as Callable).call()
			_arrows.remove_at(i)
			var tw := create_tween()
			tw.tween_interval(1.5)
			tw.tween_callback(n.queue_free)


## A glowing mote of magic (e.g. Fire Bolt) that lights up the cave as it flies.
func _make_bolt(look: Dictionary) -> Node3D:
	var col := Color.html(str(look.get("color", "#ff8a2a")))
	var size := float(look.get("size", 0.12))
	var root := Node3D.new()
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = size
	sm.height = size * 2.0
	core.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col.lightened(0.5)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 6.0
	core.material_override = m
	root.add_child(core)
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 3.0
	light.omni_range = 5.0
	root.add_child(light)
	var trail := CaveBuilder.make_flame()
	trail.scale = Vector3.ONE * 0.6
	root.add_child(trail)
	return root


## Short flash of light and sparks where a spell lands.
func _burst(p: Vector3, col: Color) -> void:
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 6.0
	light.omni_range = 6.0
	add_child(light)
	light.global_position = p
	var fl := CaveBuilder.make_flame()
	fl.scale = Vector3.ONE * 1.6
	add_child(fl)
	fl.global_position = p
	var tw := create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.5)
	tw.tween_callback(light.queue_free)
	tw.tween_callback(fl.queue_free)


func _make_arrow() -> Node3D:
	var root := Node3D.new()
	var shaft := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.008
	c.bottom_radius = 0.008
	c.height = 0.7
	shaft.mesh = c
	shaft.rotation = Vector3(-PI / 2, 0, 0)
	shaft.position = Vector3(0, 0, 0.0)
	shaft.material_override = UnitVisual.mat("#8a6a42", 0.0, 0.7)
	root.add_child(shaft)
	var head := MeshInstance3D.new()
	var hc := CylinderMesh.new()
	hc.top_radius = 0.0
	hc.bottom_radius = 0.02
	hc.height = 0.07
	head.mesh = hc
	head.rotation = Vector3(-PI / 2, 0, 0)
	head.position = Vector3(0, 0, -0.38)
	head.material_override = UnitVisual.mat("#c0c4c8", 0.8, 0.3)
	root.add_child(head)
	for k in 2:
		var f := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.05, 0.12)
		f.mesh = q
		f.rotation = Vector3(0, PI / 2 * k, 0)
		f.position = Vector3(0, 0, 0.3)
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(0.85, 0.85, 0.8)
		fm.cull_mode = BaseMaterial3D.CULL_DISABLED
		f.material_override = fm
		root.add_child(f)
	return root


## True if an alerted, living enemy is within 15 m.
func fight_near(p: Vector3) -> bool:
	for u in units:
		if u.is_monster and not u.down and u.ai_state == "combat" and u.global_position.distance_to(p) < 15.0:
			return true
	return false


func line_of_sight(a: Vector3, b: Vector3) -> bool:
	var p := cave.world_to_cell(a)
	var q := cave.world_to_cell(b)
	var dx := absi(q.x - p.x)
	var dy := -absi(q.y - p.y)
	var sx := 1 if p.x < q.x else -1
	var sy := 1 if p.y < q.y else -1
	var err := dx + dy
	var x := p.x
	var y := p.y
	while true:
		if not cave.is_floor(x, y):
			return false
		if x == q.x and y == q.y:
			return true
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy
	return true


func on_enemy_alerted(enemy: Unit, _by: Unit) -> void:
	log_line("%s spots the party!" % name_tag(enemy))
	for u in units:
		if u.is_monster and u.ai_state == "idle" and u.global_position.distance_to(enemy.global_position) < 10.0:
			u.alert(enemy)
	if not _sighted:
		_sighted = true
		paused = true
		hud.set_pause_reason("Enemy sighted!")


func name_tag(u: Unit) -> String:
	var col := "#8fe08f" if u.faction == "party" else "#ff8f7f"
	return "[color=%s]%s[/color]" % [col, u.display_name]


func log_line(bb: String) -> void:
	if hud:
		hud.log_line(bb)
	print_rich(bb)


func float_text(at: Vector3, text: String, color: Color, size := 1.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = int(64 * size)
	l.outline_size = 14
	l.pixel_size = 0.008
	l.modulate = color
	l.position = at
	add_child(l)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", at.y + 1.3, 1.2)
	tw.tween_property(l, "modulate:a", 0.0, 1.2).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)


func sfx_hit(_at: Vector3) -> void:
	pass  # sound comes later


func _click_marker(at: Vector3) -> void:
	var m := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.3
	t.outer_radius = 0.36
	m.mesh = t
	m.scale = Vector3(1, 0.05, 1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.4, 1, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material_override = mat
	m.position = at + Vector3(0, 0.05, 0)
	add_child(m)
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tw.tween_callback(m.queue_free)


func _on_data_changed() -> void:
	for u in units:
		u.refresh_from_data()
	hud.build_portraits(party)
	log_line("[color=#d9c58a][i]Data files changed — reloaded.[/i][/color]")
