class_name CharacterSheet
extends PanelContainer
## The character record (BG2 style): the hero turning slowly in full figure,
## abilities and combat numbers, worn equipment and the pack (click to put
## on / take off), and their biography. Opens with I, the scroll button or
## a right click on a portrait. The game pauses while it is open.

const NEXT_LEVEL := [0, 300, 900, 2700, 6500, 14000]

var game: Node
var unit: Unit
var _body: HBoxContainer
var _bio: RichTextLabel
var _title: Label
var _subtitle: Label
var _was_paused := false


func _ready() -> void:
	add_theme_stylebox_override("panel", UiSkin.box("panel", 20, 18))
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -560
	offset_right = 470
	offset_top = -400
	offset_bottom = 250
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	head.add_child(UiSkin.slot("prev", 36, "Previous hero", func(): _step(-1)))
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 0)
	head.add_child(names)
	_title = UiSkin.title_label("", 26, Color(1, 0.92, 0.7))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	names.add_child(_title)
	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_color_override("font_color", UiSkin.INK_DIM)
	names.add_child(_subtitle)
	head.add_child(UiSkin.slot("next", 36, "Next hero", func(): _step(1)))
	head.add_child(UiSkin.slot("close", 36, "Close  [I / Esc]", func(): close()))

	var div := TextureRect.new()
	div.texture = UiSkin.tex("divider")
	div.stretch_mode = TextureRect.STRETCH_SCALE
	div.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	div.custom_minimum_size = Vector2(0, 10)
	v.add_child(div)

	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", 22)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_body)

	v.add_child(UiSkin.title_label("Biography", 14, UiSkin.GOLD_DIM))
	_bio = RichTextLabel.new()
	_bio.bbcode_enabled = true
	_bio.custom_minimum_size = Vector2(0, 92)
	_bio.add_theme_stylebox_override("normal", UiSkin.inset())
	_bio.add_theme_font_size_override("normal_font_size", 17)
	_bio.add_theme_font_size_override("italics_font_size", 17)
	v.add_child(_bio)


func open(u: Unit) -> void:
	if not visible:
		_was_paused = game.paused
		game.paused = true
	unit = u
	visible = true
	rebuild()


func close() -> void:
	if not visible:
		return
	visible = false
	game.paused = _was_paused
	for c in _body.get_children():
		c.queue_free()


func _step(dir: int) -> void:
	var p: Array = game.party
	var i := (p.find(unit) + dir + p.size()) % p.size()
	unit = p[i]
	rebuild()


func rebuild() -> void:
	for c in _body.get_children():
		c.queue_free()
	var u := unit
	var d: Dictionary = DataDB.heroes.get(u.data_id, {})
	var lvl := int(d.get("level", 1))
	_title.text = u.display_name
	_subtitle.text = "Level %d %s %s  ·  %s  ·  %s" % [lvl, d.get("race", ""), d.get("class", ""), d.get("background", ""), d.get("alignment", "")]
	_bio.text = "[i]%s[/i]" % str(d.get("bio", "No one knows much about %s yet." % u.display_name))

	# --- column 1: the hero in full figure + experience
	var c1 := VBoxContainer.new()
	c1.add_theme_constant_override("separation", 6)
	_body.add_child(c1)
	var pic := Control.new()
	pic.custom_minimum_size = Vector2(250, 330)
	c1.add_child(pic)
	var pv := PortraitView.new()
	pv.setup(d.get("look", {}), u.equipment, Vector2i(242, 322), true)
	pv.position = Vector2(4, 4)
	pic.add_child(pv)
	var frame := NinePatchRect.new()
	frame.texture = UiSkin.tex("frame")
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		frame.set_patch_margin(side, 16)
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.add_child(frame)
	var nxt: int = NEXT_LEVEL[mini(lvl, NEXT_LEVEL.size() - 1)]
	c1.add_child(_bar("Experience  %d / %d" % [u.xp, nxt], float(u.xp) / float(maxi(1, nxt)), "bar_gold"))
	c1.add_child(_bar("Hit points  %d / %d" % [u.hp, u.max_hp], float(u.hp) / float(u.max_hp), "bar_green" if u.hp > u.max_hp / 3 else "bar_red"))

	# --- column 2: abilities and combat
	var c2 := VBoxContainer.new()
	c2.custom_minimum_size = Vector2(330, 0)
	c2.add_theme_constant_override("separation", 4)
	_body.add_child(c2)
	c2.add_child(UiSkin.title_label("Abilities", 15))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 0)
	c2.add_child(grid)
	var names := {"str": "Strength", "dex": "Dexterity", "con": "Constitution", "int": "Intelligence", "wis": "Wisdom", "cha": "Charisma"}
	for k in ["str", "dex", "con", "int", "wis", "cha"]:
		var n := Label.new()
		n.text = names[k]
		n.custom_minimum_size = Vector2(130, 0)
		grid.add_child(n)
		var sc := UiSkin.title_label(str(u.ab(k)), 18, Color(1, 0.93, 0.75))
		sc.custom_minimum_size = Vector2(34, 0)
		sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(sc)
		var md := Label.new()
		md.text = "(%s)" % Rules.signed(Rules.mod(u.ab(k)))
		md.add_theme_color_override("font_color", UiSkin.INK_DIM)
		grid.add_child(md)
	c2.add_child(_gap())
	c2.add_child(UiSkin.title_label("Combat", 15))
	var a: Dictionary = u.attack_profile()
	var rows := [
		["Armor Class", str(u.ac())],
		["Speed", "%.1f m/s" % u.speed],
		["Initiative", Rules.signed(Rules.mod(u.ab("dex")))],
		["Proficiency", Rules.signed(Rules.PROFICIENCY)],
		["Attack", "%s  %s  (%s)" % [a.get("name", ""), Rules.signed(int(a.get("to_hit", 0))), a.get("damage", "")]],
	]
	var spells: Array = d.get("spells", [])
	if d.has("cantrip"):
		rows.append(["Cantrip", str(DataDB.spells.get(str(d["cantrip"]), {}).get("name", d["cantrip"]))])
	if not spells.is_empty():
		var sn: Array = spells.map(func(s): return str(DataDB.spells.get(str(s), {}).get("name", s)))
		rows.append(["Spells", ", ".join(sn)])
		rows.append(["Spell slots", "%d / %d" % [u.spell_slots, int(d.get("spell_slots", 0))]])
	var cg := GridContainer.new()
	cg.columns = 2
	cg.add_theme_constant_override("h_separation", 14)
	c2.add_child(cg)
	for r in rows:
		var l := Label.new()
		l.text = r[0]
		l.add_theme_color_override("font_color", UiSkin.INK_DIM)
		cg.add_child(l)
		var val := Label.new()
		val.text = r[1]
		val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		val.custom_minimum_size = Vector2(190, 0)
		cg.add_child(val)

	# --- column 3: equipment and pack
	var c3 := VBoxContainer.new()
	c3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c3.add_theme_constant_override("separation", 4)
	_body.add_child(c3)
	c3.add_child(UiSkin.title_label("Equipment", 15))
	for s in [["main_hand", "Main hand"], ["off_hand", "Off hand"], ["armor", "Armor"], ["head", "Head"]]:
		c3.add_child(_equip_row(s[0], s[1]))
	c3.add_child(_gap())
	c3.add_child(UiSkin.title_label("Pack", 15))
	var pack := HFlowContainer.new()
	pack.add_theme_constant_override("h_separation", 6)
	pack.add_theme_constant_override("v_separation", 6)
	c3.add_child(pack)
	if u.inventory.is_empty():
		var e := Label.new()
		e.text = "Empty."
		e.add_theme_color_override("font_color", UiSkin.INK_DIM)
		pack.add_child(e)
	for id in u.inventory:
		var it := DataDB.item(str(id))
		var item_id := str(id)
		var b := UiSkin.slot(item_icon(it), 48, "%s\n%s\nClick to equip." % [it.get("name", id), item_stats(it)], func():
			game.equip_item(unit, item_id)
			rebuild())
		pack.add_child(b)


func _equip_row(slot: String, label: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var id := str(unit.equipment.get(slot, ""))
	var it := DataDB.item(id)
	var b := UiSkin.slot(item_icon(it) if id != "" else "empty", 48,
		("%s\n%s\nClick to take it off." % [it.get("name", id), item_stats(it)]) if id != "" else "%s: nothing" % label,
		func():
			if id != "":
				game.unequip(unit, slot)
				rebuild())
	if id == "":
		(b.get_meta("icon") as TextureRect).modulate = Color(1, 1, 1, 0.15)
	row.add_child(b)
	var txt := VBoxContainer.new()
	txt.add_theme_constant_override("separation", -2)
	row.add_child(txt)
	txt.add_child(UiSkin.title_label(label, 11, UiSkin.GOLD_DIM))
	var n := Label.new()
	n.text = str(it.get("name", "—")) if id != "" else "—"
	txt.add_child(n)
	if id != "":
		var st := Label.new()
		st.text = item_stats(it)
		st.add_theme_color_override("font_color", UiSkin.INK_DIM)
		st.add_theme_font_size_override("font_size", 14)
		txt.add_child(st)
	return row


func _bar(text: String, frac: float, fill: String) -> Control:
	var bar := TextureProgressBar.new()
	bar.texture_under = UiSkin.tex("bar_bg")
	bar.texture_progress = UiSkin.tex(fill)
	bar.nine_patch_stretch = true
	for m in ["stretch_margin_left", "stretch_margin_right", "stretch_margin_top", "stretch_margin_bottom"]:
		bar.set(m, 3)
	bar.custom_minimum_size = Vector2(250, 22)
	bar.max_value = 1000
	bar.value = clampf(frac, 0.0, 1.0) * 1000
	var l := Label.new()
	l.text = text
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 4)
	bar.add_child(l)
	return bar


func _gap() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 8)
	return c


static func item_icon(it: Dictionary) -> String:
	match str(it.get("type", "")):
		"weapon":
			return "shoot" if bool(it.get("ranged", false)) else "attack"
		"armor":
			return "armor"
		"shield":
			return "shield"
		"helmet":
			return "helm"
		"light":
			return "torch"
	return "empty"


## A short line of rules text for an item.
static func item_stats(it: Dictionary) -> String:
	match str(it.get("type", "")):
		"weapon":
			var parts: Array[String] = [str(it.get("damage", "1d4"))]
			var ab := str(it.get("ability", "str"))
			parts.append({"str": "Strength", "dex": "Dexterity", "finesse": "finesse"}.get(ab, ab))
			if bool(it.get("ranged", false)):
				parts.append("range %d m" % int(it.get("range", 24)))
			if bool(it.get("two_handed", false)):
				parts.append("two-handed")
			return " · ".join(parts)
		"armor":
			var cap := int(it.get("dex_cap", 99))
			return "AC %d + Dex%s" % [int(it.get("ac", 10)), "" if cap >= 99 else (" (max %d)" % cap if cap > 0 else " (none)")]
		"shield":
			return "+%d AC" % int(it.get("ac", 2))
		"helmet":
			return "Protects the head" if int(it.get("ac", 0)) == 0 else "+%d AC" % int(it.get("ac", 0))
		"light":
			return "Bright light, %d m" % int(it.get("visual", {}).get("range", 8))
	return ""
