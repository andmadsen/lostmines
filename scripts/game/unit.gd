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
var order := ""          ## "", "move", "attack", "heal"
var spell_slots := 0     ## level 1 spell slots left
var target: Unit = null
var ai_state := "idle"   ## monsters: idle -> combat
var down := false        ## 0 HP
var selected := false

var visual: UnitVisual
var ring: MeshInstance3D
var _repath := 0.0
var _facing := 0.0
var _heal_spell := ""
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
	speed = float(d.get("speed", 3.0))
	if first:
		spell_slots = int(d.get("spell_slots", 0))
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
	# casters with an attack cantrip use it instead of their weapon
	var cid := str(DataDB.heroes.get(data_id, {}).get("cantrip", ""))
	if cid != "" and DataDB.spells.has(cid):
		var sp: Dictionary = DataDB.spells[cid]
		var cm := Rules.mod(ab("int"))
		return {"name": str(sp.get("name", "Spell")), "to_hit": Rules.PROFICIENCY + cm, "damage": str(sp.get("damage", "1d10")),
			"reach": float(sp.get("range", 24.0)), "ranged": true, "projectile": sp.get("projectile", {})}
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
	var ranged := bool(w.get("ranged", false))
	var reach := float(w.get("range", 24.0)) if ranged else float(w.get("reach", 1.6))
	return {"name": str(w.get("name", "Weapon")), "to_hit": Rules.PROFICIENCY + m2, "damage": dmg, "reach": reach, "ranged": ranged}


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


func knows_spell(id: String) -> bool:
	return not is_monster and id in DataDB.heroes.get(data_id, {}).get("spells", [])


## Cast Cure Wounds (or another healing spell) on an ally: walk up, touch, heal.
func order_heal(t: Unit, spell_id := "cure_wounds") -> bool:
	if down or t == null or not knows_spell(spell_id):
		return false
	if spell_slots <= 0:
		game.log_line("%s has no spell slots left for %s." % [game.name_tag(self), DataDB.spells.get(spell_id, {}).get("name", spell_id)])
		return false
	order = "heal"
	target = t
	_heal_spell = spell_id
	path.clear()
	_repath = 0.0
	return true


func _do_heal(t: Unit, spell_id: String) -> void:
	var sp: Dictionary = DataDB.spells.get(spell_id, {})
	spell_slots -= 1
	var delay := visual.cast()
	cooldown = Rules.ROUND * 0.5
	var who: String = game.name_tag(self)
	var amount := maxi(1, Rules.roll(str(sp.get("heal", "1d8"))) + Rules.mod(ab(str(sp.get("ability", "wis")))))
	var col := Color.html(str(sp.get("color", "#ffe9a0")))
	var spell_name := str(sp.get("name", "Heal"))
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func():
		if not is_instance_valid(t):
			return
		t.receive_healing(amount)
		game.heal_glow(t.global_position, col)
		game.log_line("%s casts %s on %s: [color=#9fe89f]+%d HP[/color] (%d slot%s left)" % [who, spell_name, game.name_tag(t), amount, spell_slots, "" if spell_slots == 1 else "s"]))


func receive_healing(amount: int) -> void:
	var was_down := down
	hp = mini(max_hp, hp + amount)
	game.float_text(global_position + Vector3(0, 2.0, 0), "+%d" % amount, Color(0.5, 1.0, 0.5))
	if was_down and hp > 0:
		down = false
		visual.revive()
		set_selected(selected)
		game.log_line("%s gets back up!" % game.name_tag(self))


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

	if order == "heal":
		if target == null or target.hp >= target.max_hp:
			stop()
		else:
			var hr := float(DataDB.spells.get(_heal_spell, {}).get("range", 1.8)) + 0.35
			if _flat(global_position).distance_to(_flat(target.global_position)) <= hr:
				path.clear()
				_face(target.global_position)
				if cooldown <= 0.0:
					var t := target
					stop()
					_do_heal(t, _heal_spell)
			else:
				_repath -= delta
				if _repath <= 0.0 or path.is_empty():
					path = game.find_path(global_position, target.global_position)
					_repath = 0.5
				moving = _follow_path(delta)
	elif order == "attack":
		if target == null or target.down:
			stop()
		else:
			var prof := attack_profile()
			var ranged := bool(prof.get("ranged", false))
			var reach := float(prof.get("reach", 1.6)) + 0.35
			var dist := _flat(global_position).distance_to(_flat(target.global_position))
			if dist <= reach and (not ranged or game.line_of_sight(global_position, target.global_position)):
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
	var ranged := bool(prof.get("ranged", false))
	# D&D: a ranged attack with a hostile creature next to you has disadvantage
	var disadvantage: bool = ranged and game.enemy_adjacent(self)
	var r := Rules.d(20)
	var roll_txt := ""
	if disadvantage:
		var r2 := Rules.d(20)
		roll_txt = "[%d, %d] " % [r, r2]
		r = mini(r, r2)
	var to_hit := int(prof.get("to_hit", 0))
	var total := r + to_hit
	var crit := r == 20
	var hit := r != 1 and (crit or total >= t.ac())
	var who: String = game.name_tag(self)
	var tgt: String = game.name_tag(t)
	roll_txt += "%d%s = %d" % [r, Rules.signed(to_hit), total]
	var dis_txt := " [color=#ff9f9f](disadvantage: enemy adjacent)[/color]" if disadvantage else ""
	var dmg := Rules.roll(str(prof.get("damage", "1d4")), crit) if hit else 0
	var wname := str(prof.get("name", ""))
	var target_ac := t.ac()
	var resolve := func():
		if not is_instance_valid(t) or t.down:
			return
		if hit:
			game.log_line("%s → %s: %s %s vs AC %d%s — [color=#ffd35a]%s[/color] (%d)" % [who, tgt, wname, roll_txt, target_ac, dis_txt, "CRITICAL HIT" if crit else "Hit", dmg])
			game.sfx_hit(t.global_position)
			t.take_damage(dmg, self, crit)
		else:
			game.log_line("%s → %s: %s %s vs AC %d%s — [color=#9a9a9a]Miss[/color]" % [who, tgt, wname, roll_txt, target_ac, dis_txt])
			game.float_text(t.global_position + Vector3(0, 2.0, 0), "Miss", Color(0.75, 0.75, 0.75))
	if ranged:
		game.shoot_arrow(self, t, visual.release_time(), hit, resolve, prof.get("projectile", {}))
	else:
		resolve.call()
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
	# healers look after the party first: anyone down, or below a third of their HP
	if spell_slots > 0 and knows_spell("cure_wounds"):
		var hurt: Unit = game.most_wounded(self)
		if hurt and (hurt.down or hurt.hp * 3 < hurt.max_hp):
			order_heal(hurt)
			return
	var best: Unit = null
	var prof := attack_profile()
	var bd := 24.0 if bool(prof.get("ranged", false)) else 9.0
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
