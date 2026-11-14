class_name Unit
extends Node3D
## A hero or monster: stats from DataDB, orders (move / attack), D&D attacks,
## simple AI. The level (game) provides pathfinding, line of sight and the log.

signal died(unit: Unit)

var game: Node  ## the level script (test_cave.gd)
var data_id := ""
var display_name := ""
var faction := "party"   ## "party" or "enemy"
var is_monster := false
var abilities: Dictionary = {}
var max_hp := 10
var hp := 10
var base_ac := 10        ## monsters: fixed AC from data
var speed := 3.0         ## metres per second
var sight := 10.0
var xp_value := 0
var equipment: Dictionary = {}
var inventory: Array = []
var monster_attack: Dictionary = {}

var cooldown := 0.0
var path: Array[Vector3] = []
var order := ""          ## "", "move", "attack"
var target: Unit = null
var ai_state := "idle"   ## monsters: idle -> combat
var down := false        ## 0 HP
var selected := false

var visual: UnitVisual
var ring: MeshInstance3D
var _repath := 0.0
var _facing := 0.0
var _calm := 0.0          ## seconds since the last fight nearby


func setup_hero(id: String) -> void:
	var d: Dictionary = DataDB.heroes.get(id, {})
	data_id = id
	faction = "party"
	display_name = str(d.get("name", id))
	_apply_hero_data(d, true)
	_build_visual(d.get("look", {}))
	visual.apply_equipment(equipment)


func setup_monster(id: String) -> void:
	var d: Dictionary = DataDB.monsters.get(id, {})
	data_id = id
	faction = "enemy"
	is_monster = true
	display_name = str(d.get("name", id))
	abilities = d.get("abilities", {})
	max_hp = maxi(1, Rules.roll(str(d.get("hp", "7"))))
	hp = max_hp
	base_ac = int(d.get("ac", 12))
	speed = float(d.get("speed", 3.4))
	sight = float(d.get("sight", 10))
	xp_value = int(d.get("xp", 0))
	equipment = d.get("equipment", {}).duplicate()
	var atks: Array = d.get("attacks", [])
	monster_attack = atks[0] if atks.size() > 0 else {"name": "Claw", "to_hit": 2, "damage": "1d4", "reach": 1.5}
	var lk: Dictionary = d.get("look", {})
	_build_visual(lk)
	visual.apply_equipment(equipment, str(lk.get("armor_color", "")))


func _apply_hero_data(d: Dictionary, first: bool) -> void:
	abilities = d.get("abilities", {})
	var new_max := int(d.get("hp", 10))
	if first:
		max_hp = new_max
		hp = new_max
		equipment = d.get("equipment", {}).duplicate()
		inventory = d.get("inventory", []).duplicate()
	else:
		var lost := max_hp - hp
		max_hp = new_max
		hp = clampi(max_hp - lost, 0, max_hp)


## Called when the JSON files change while the game runs.
func refresh_from_data() -> void:
	if is_monster:
		var d: Dictionary = DataDB.monsters.get(data_id, {})
		abilities = d.get("abilities", abilities)
		base_ac = int(d.get("ac", base_ac))
		speed = float(d.get("speed", speed))
		var atks: Array = d.get("attacks", [])
		if atks.size() > 0:
			monster_attack = atks[0]
		visual.build(d.get("look", {}))
		visual.apply_equipment(equipment, str(d.get("look", {}).get("armor_color", "")))
	else:
		var d: Dictionary = DataDB.heroes.get(data_id, {})
		_apply_hero_data(d, false)
		visual.build(d.get("look", {}))
		visual.apply_equipment(equipment)
	if down:
		visual.knock_down()


func _build_visual(lk: Dictionary) -> void:
	if visual == null:
		visual = UnitVisual.new()
		add_child(visual)
		ring = MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.42
		t.outer_radius = 0.48
		t.rings = 32
		ring.mesh = t
		ring.scale = Vector3(1, 0.05, 1)
		ring.position.y = 0.04
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.3, 1.0, 0.3)
		ring.material_override = m
		add_child(ring)
	visual.build(lk)
	visual.move_speed = speed
	set_selected(selected)


func set_selected(v: bool) -> void:
	selected = v
	if ring == null:
		return
	var m := ring.material_override as StandardMaterial3D
	if faction == "party":
		ring.visible = not down
		m.albedo_color = Color(0.35, 1.0, 0.35) if v else Color(0.15, 0.45, 0.15)
	else:
		ring.visible = ai_state == "combat" and not down
		m.albedo_color = Color(0.9, 0.15, 0.1)


# ---------------- derived stats ----------------
func ab(key: String) -> int:
	return int(abilities.get(key, 10))


func ac() -> int:
	if is_monster:
		return base_ac
	var armor := DataDB.item(str(equipment.get("armor", "")))
	var base := int(armor.get("ac", 10))
	var cap := int(armor.get("dex_cap", 99))
	var total := base + mini(Rules.mod(ab("dex")), cap)
	var shield := DataDB.item(str(equipment.get("off_hand", "")))
	if str(shield.get("type", "")) == "shield":
		total += int(shield.get("ac", 2))
	return total


## Returns {name, to_hit, damage, reach}.
func attack_profile() -> Dictionary:
	if is_monster:
		return monster_attack
	var w := DataDB.item(str(equipment.get("main_hand", "")))
	if w.is_empty():
		var m := Rules.mod(ab("str"))
		return {"name": "Fist", "to_hit": Rules.PROFICIENCY + m, "damage": str(maxi(1, 1 + m)), "reach": 1.5}
	var stat := str(w.get("ability", "str"))
	var m2 := Rules.mod(ab("str"))
	if stat == "dex":
		m2 = Rules.mod(ab("dex"))
	elif stat == "finesse":
		m2 = maxi(Rules.mod(ab("str")), Rules.mod(ab("dex")))
	var dmg := str(w.get("damage", "1d4"))
	if m2 != 0:
		dmg += Rules.signed(m2)
	return {"name": str(w.get("name", "Weapon")), "to_hit": Rules.PROFICIENCY + m2, "damage": dmg, "reach": float(w.get("reach", 1.6))}


func alive() -> bool:
	return not down


# ---------------- orders ----------------
func order_move(dest: Vector3) -> void:
	if down:
		return
	order = "move"
	target = null
	path = game.find_path(global_position, dest)


func order_attack(t: Unit) -> void:
	if down or t == null or t.down:
		return
	order = "attack"
	target = t
	path.clear()
	_repath = 0.0


func stop() -> void:
	order = ""
	target = null
	path.clear()


# ---------------- update ----------------
func tick(delta: float) -> void:
	if down:
		visual.walk_amount = 0.0
		return
	cooldown -= delta
	var moving := false
	if is_monster:
		_monster_ai()
	elif order == "" and path.is_empty():
		_party_ai()

	if order == "attack":
		if target == null or target.down:
			stop()
		else:
			var prof := attack_profile()
			var reach := float(prof.get("reach", 1.6)) + 0.35
			var dist := _flat(global_position).distance_to(_flat(target.global_position))
			if dist <= reach:
				path.clear()
				_face(target.global_position)
				if cooldown <= 0.0:
					_attack(target, prof)
					cooldown = Rules.ROUND * 0.5
			else:
				_repath -= delta
				if _repath <= 0.0 or path.is_empty():
					path = game.find_path(global_position, target.global_position)
					_repath = 0.5
				moving = _follow_path(delta)
	elif not path.is_empty():
		moving = _follow_path(delta)
		if path.is_empty() and order == "move":
			order = ""
	visual.walk_amount = lerpf(visual.walk_amount, 1.0 if moving else 0.0, 0.25)
	# weapon in hand during fights, on the back a few seconds after
	if order == "attack" or game.fight_near(global_position):
		_calm = 0.0
		visual.set_armed(true)
	else:
		_calm += delta
		if _calm > 3.0:
			visual.set_armed(false)


func _follow_path(delta: float) -> bool:
	if path.is_empty():
		return false
	var wp := path[0]
	var pos := global_position
	var to := _flat(wp) - _flat(pos)
	var step := speed * delta
	if to.length() <= step:
		global_position = Vector3(wp.x, 0, wp.z)
		path.remove_at(0)
	else:
		var dir := to.normalized()
		global_position += Vector3(dir.x, 0, dir.y) * step
		_face(pos + Vector3(dir.x, 0, dir.y))
	return true


func _face(p: Vector3) -> void:
	var d := _flat(p) - _flat(global_position)
	if d.length() < 0.01:
		return
	var want := atan2(-d.x, -d.y)
	rotation.y = lerp_angle(rotation.y, want, 0.35)


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


# ---------------- combat ----------------
func _attack(t: Unit, prof: Dictionary) -> void:
	visual.swing()
	var r := Rules.d(20)
	var to_hit := int(prof.get("to_hit", 0))
	var total := r + to_hit
	var crit := r == 20
	var hit := r != 1 and (crit or total >= t.ac())
	var who: String = game.name_tag(self)
	var tgt: String = game.name_tag(t)
	var roll_txt := "%d%s = %d" % [r, Rules.signed(to_hit), total]
	if hit:
		var dmg := Rules.roll(str(prof.get("damage", "1d4")), crit)
		game.log_line("%s → %s: %s %s vs AC %d — [color=#ffd35a]%s[/color] (%d)" % [who, tgt, prof.get("name", ""), roll_txt, t.ac(), "CRITICAL HIT" if crit else "Hit", dmg])
		game.sfx_hit(t.global_position)
		t.take_damage(dmg, self, crit)
	else:
		game.log_line("%s → %s: %s %s vs AC %d — [color=#9a9a9a]Miss[/color]" % [who, tgt, prof.get("name", ""), roll_txt, t.ac()])
		game.float_text(t.global_position + Vector3(0, 2.0, 0), "Miss", Color(0.75, 0.75, 0.75))
	if t.is_monster and t.ai_state == "idle":
		t.alert(self)


func take_damage(dmg: int, src: Unit, crit := false) -> void:
	if down:
		return
	hp -= dmg
	game.float_text(global_position + Vector3(0, 2.0, 0), str(dmg), Color(1, 0.85, 0.2) if crit else Color(1, 0.3, 0.25), 1.4 if crit else 1.0)
	if hp <= 0:
		hp = 0
		down = true
		stop()
		ring.visible = false
		if is_monster:
			visual.die()
			game.log_line("%s dies. [color=#ffe07a]+%d XP[/color]" % [game.name_tag(self), xp_value])
		else:
			visual.knock_down()
			game.log_line("%s falls unconscious!" % game.name_tag(self))
		died.emit(self)
	elif is_monster and ai_state == "idle":
		alert(src)


# ---------------- AI ----------------
func _party_ai() -> void:
	if cooldown > 0.3:
		return
	var best: Unit = null
	var bd := 9.0
	for u in game.units:
		if u.faction != "enemy" or u.down or u.ai_state != "combat":
			continue
		var dd := global_position.distance_to(u.global_position)
		if dd < bd and game.line_of_sight(global_position, u.global_position):
			bd = dd
			best = u
	if best:
		order_attack(best)


func _monster_ai() -> void:
	if ai_state == "idle":
		for u in game.units:
			if u.faction == "party" and not u.down and global_position.distance_to(u.global_position) <= sight and game.line_of_sight(global_position, u.global_position):
				alert(u)
				break
		return
	if order != "attack" or target == null or target.down:
		var best: Unit = null
		var bd := 999.0
		for u in game.units:
			if u.faction == "party" and not u.down:
				var dd := global_position.distance_to(u.global_position)
				if dd < bd:
					bd = dd
					best = u
		if best:
			order_attack(best)
		else:
			stop()


func alert(by: Unit) -> void:
	if ai_state != "idle":
		return
	ai_state = "combat"
	set_selected(false)
	cooldown = randf() * 2.0
	game.on_enemy_alerted(self, by)
