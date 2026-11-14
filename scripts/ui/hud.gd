class_name Hud
extends CanvasLayer
## Baldur's Gate style interface in a gold-and-leather fantasy skin:
##  - right: living portraits of the party (their own 3D models),
##  - bottom: the chronicle (combat log), the action bar of the selected hero
##    (attack, spells, stop) and smaller gear / game buttons,
##  - pause banner, target hint, tooltips and the help scroll.

const GOLD := UiSkin.GOLD
const INK := UiSkin.INK
const PORTRAIT := Vector2i(140, 150)
const BAR_H := 186

var game: Node
var root: Control
var portraits: VBoxContainer
var log_label: RichTextLabel
var sel_label: Label
var stats_label: Label
var hint_label: Label
var pause_banner: Label
var tooltip: Label
var help_panel: PanelContainer
var drag_rect: Control
var action_row: HBoxContainer
var _portrait_rows: Array[Dictionary] = []
var _buttons: Dictionary = {}
var _action_key := ""
var _action_slots: Dictionary = {}
var sheet: CharacterSheet


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiSkin.theme()
	add_child(root)

	drag_rect = SelectionRect.new()
	drag_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	drag_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(drag_rect)

	_build_portrait_column()
	_build_bottom_bar()
	_build_overlays()


# ---------------- layout ----------------
func _build_portrait_column() -> void:
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", UiSkin.box("panel", 20, 10))
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.anchor_bottom = 1.0
	right.offset_left = -(PORTRAIT.x + 34)
	right.offset_bottom = -BAR_H + 6
	right.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(right)
	portraits = VBoxContainer.new()
	portraits.add_theme_constant_override("separation", 6)
	right.add_child(portraits)


func _build_bottom_bar() -> void:
	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", UiSkin.box("panel", 20, 14))
	bottom.anchor_top = 1.0
	bottom.anchor_right = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_top = -BAR_H
	bottom.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(bottom)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	bottom.add_child(hb)

	# --- the chronicle (log)
	var log_box := VBoxContainer.new()
	log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_box.size_flags_stretch_ratio = 1.15
	log_box.add_theme_constant_override("separation", 2)
	hb.add_child(log_box)
	log_box.add_child(UiSkin.title_label("Chronicle", 13, UiSkin.GOLD_DIM))
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.add_theme_font_override("normal_font", UiSkin.body_font())
	log_label.add_theme_font_size_override("normal_font_size", 16)
	log_label.add_theme_font_size_override("bold_font_size", 16)
	log_label.add_theme_font_size_override("italics_font_size", 16)
	log_label.add_theme_color_override("default_color", INK)
	log_label.add_theme_stylebox_override("normal", UiSkin.inset())
	log_box.add_child(log_label)

	# --- the selected hero and their actions
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 4)
	hb.add_child(mid)
	sel_label = UiSkin.title_label("", 17)
	mid.add_child(sel_label)
	stats_label = Label.new()
	stats_label.add_theme_color_override("font_color", UiSkin.INK_DIM)
	stats_label.add_theme_font_size_override("font_size", 15)
	mid.add_child(stats_label)
	var div := TextureRect.new()
	div.texture = UiSkin.tex("divider")
	div.stretch_mode = TextureRect.STRETCH_SCALE
	div.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	div.custom_minimum_size = Vector2(0, 10)
	mid.add_child(div)
	action_row = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	mid.add_child(action_row)
	hint_label = Label.new()
	hint_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	hint_label.add_theme_font_size_override("font_size", 15)
	mid.add_child(hint_label)

	# --- gear and game buttons
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	hb.add_child(side)
	side.add_child(UiSkin.title_label("Gear", 13, UiSkin.GOLD_DIM))
	var gear := HBoxContainer.new()
	gear.add_theme_constant_override("separation", 5)
	side.add_child(gear)
	_small(gear, "weapon", "swap", "Swap weapon\nCycle through the weapons in the pack.", func(): game.cmd_cycle("main_hand", ["weapon"]))
	_small(gear, "armor", "armor", "Change armor\nCycle through the armor in the pack.", func(): game.cmd_cycle("armor", ["armor"]))
	_small(gear, "shield", "shield", "Shield on / off", func(): game.cmd_toggle("off_hand", "shield"))
	_small(gear, "helm", "helm", "Helmet on / off", func(): game.cmd_toggle("head", "helmet"))
	_small(gear, "torch", "torch", "Torch on / off", func(): game.cmd_toggle("off_hand", "light"))
	side.add_child(UiSkin.title_label("Game", 13, UiSkin.GOLD_DIM))
	var sys := HBoxContainer.new()
	sys.add_theme_constant_override("separation", 5)
	side.add_child(sys)
	_small(sys, "record", "record", "Character record  [I]\nStats, equipment and biography.", func(): game.toggle_sheet())
	_small(sys, "pause", "pause", "Pause  [Space]\nGive orders while time stands still.", func(): game.toggle_pause())
	_small(sys, "help", "help", "Help  [H]", func(): help_panel.visible = not help_panel.visible)
	_small(sys, "reset", "restart", "Restart  [F5]", func(): game.get_tree().reload_current_scene())


func _build_overlays() -> void:
	pause_banner = UiSkin.title_label("PAUSED", 22, Color(1, 0.9, 0.8))
	pause_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_banner.anchor_left = 0.5
	pause_banner.anchor_right = 0.5
	pause_banner.offset_left = -230
	pause_banner.offset_right = 230 - PORTRAIT.x
	pause_banner.offset_top = 12
	var pb := UiSkin.box("panel", 20, 8)
	pause_banner.add_theme_stylebox_override("normal", pb)
	pause_banner.modulate = Color(1.0, 0.75, 0.7)
	pause_banner.visible = false
	root.add_child(pause_banner)

	tooltip = Label.new()
	tooltip.visible = false
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.add_theme_stylebox_override("normal", UiSkin.box("panel", 18, 10))
	tooltip.add_theme_font_size_override("font_size", 16)
	root.add_child(tooltip)

	help_panel = PanelContainer.new()
	help_panel.add_theme_stylebox_override("panel", UiSkin.box("panel", 20, 22))
	help_panel.anchor_left = 0.5
	help_panel.anchor_right = 0.5
	help_panel.anchor_top = 0.5
	help_panel.anchor_bottom = 0.5
	help_panel.offset_left = -330
	help_panel.offset_right = 330
	help_panel.offset_top = -260
	help_panel.offset_bottom = 120
	var ht := RichTextLabel.new()
	ht.bbcode_enabled = true
	ht.fit_content = true
	ht.add_theme_font_override("bold_font", UiSkin.title_font())
	ht.add_theme_font_size_override("normal_font_size", 17)
	ht.text = "[center][b][color=#dcb35c]Lost Mines — Test Cave[/color][/b][/center]\n\n" \
		+ "[color=#dcb35c]Left click[/color]  select a hero · move · attack an enemy\n" \
		+ "[color=#dcb35c]Drag[/color]  select several heroes   [color=#dcb35c]Shift[/color]  add to the selection\n" \
		+ "[color=#dcb35c]1–4 / Ctrl+A[/color]  select a hero / the whole party\n" \
		+ "[color=#dcb35c]Action bar[/color]  pick an attack or a spell, then click its target\n" \
		+ "[color=#dcb35c]Right click / Esc[/color]  cancel a target choice\n" \
		+ "[color=#dcb35c]Space[/color]  pause — give orders while time stands still\n" \
		+ "[color=#dcb35c]WASD / screen edge[/color]  move the camera · [color=#dcb35c]Q / E[/color] rotate · [color=#dcb35c]wheel[/color] zoom · [color=#dcb35c]F[/color] focus\n" \
		+ "[color=#dcb35c]I[/color] or right click a portrait: character record\n" \
		+ "[color=#dcb35c]X[/color] stop · [color=#dcb35c]C[/color] Cure Wounds · [color=#dcb35c]F5[/color] restart · [color=#dcb35c]H[/color] this help\n\n" \
		+ "[i]Edit data/*.json while the game runs — changes load within a second.[/i]"
	help_panel.add_child(ht)
	help_panel.visible = false
	root.add_child(help_panel)

	sheet = CharacterSheet.new()
	root.add_child(sheet)


func _small(parent: Control, key: String, icon_name: String, tip: String, cb: Callable) -> void:
	var b := UiSkin.slot(icon_name, 44, tip, cb)
	parent.add_child(b)
	_buttons[key] = b


# ---------------- portraits ----------------
func build_portraits(party: Array) -> void:
	for c in portraits.get_children():
		c.queue_free()
	_portrait_rows.clear()
	for u in party:
		portraits.add_child(_portrait_card(u))


func _portrait_card(u: Unit) -> Control:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 2)
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var pic := Control.new()
	pic.custom_minimum_size = Vector2(PORTRAIT)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(pic)
	var pv := PortraitView.new()
	var d: Dictionary = DataDB.heroes.get(u.data_id, {})
	pv.setup(d.get("look", {}), u.equipment, PORTRAIT - Vector2i(8, 8))
	pv.position = Vector2(4, 4)
	pic.add_child(pv)
	var frame := NinePatchRect.new()
	frame.texture = UiSkin.tex("frame")
	frame.set_patch_margin(SIDE_LEFT, 16)
	frame.set_patch_margin(SIDE_TOP, 16)
	frame.set_patch_margin(SIDE_RIGHT, 16)
	frame.set_patch_margin(SIDE_BOTTOM, 16)
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.add_child(frame)
	var name_lbl := UiSkin.title_label(u.display_name.split(" ")[0], 14, Color(1, 0.93, 0.75))
	name_lbl.position = Vector2(12, PORTRAIT.y - 30)
	pic.add_child(name_lbl)
	var cls := UiSkin.title_label(str(d.get("class", "")), 10, UiSkin.GOLD)
	cls.position = Vector2(12, 9)
	pic.add_child(cls)

	var bar := TextureProgressBar.new()
	bar.texture_under = UiSkin.tex("bar_bg")
	bar.texture_progress = UiSkin.tex("bar_green")
	bar.nine_patch_stretch = true
	bar.stretch_margin_left = 3
	bar.stretch_margin_right = 3
	bar.stretch_margin_top = 3
	bar.stretch_margin_bottom = 3
	bar.custom_minimum_size = Vector2(PORTRAIT.x, 18)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(bar)
	var hp := Label.new()
	hp.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp.add_theme_font_override("font", UiSkin.title_font())
	hp.add_theme_font_size_override("font_size", 11)
	hp.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	hp.add_theme_constant_override("outline_size", 4)
	bar.add_child(hp)

	var unit: Unit = u
	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			game.portrait_clicked(unit, ev.shift_pressed)
			if ev.double_click:
				game.rig.focus(unit.global_position)
		elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
			sheet.game = game
			sheet.open(unit)
	)
	card.tooltip_text = "%s\n%s %s\nRight click: character record" % [u.display_name, d.get("race", ""), d.get("class", "")]
	_portrait_rows.append({"unit": u, "frame": frame, "bar": bar, "hp": hp, "view": pv})
	return card


# ---------------- per frame ----------------
func refresh() -> void:
	for row in _portrait_rows:
		var u: Unit = row["unit"]
		var bar: TextureProgressBar = row["bar"]
		bar.max_value = u.max_hp
		bar.value = u.hp
		bar.texture_progress = UiSkin.tex("bar_green" if u.hp > u.max_hp / 3 else "bar_red")
		(row["hp"] as Label).text = "Unconscious" if u.down else "%d / %d" % [u.hp, u.max_hp]
		(row["frame"] as NinePatchRect).modulate = Color(1.35, 1.25, 0.9) if u.selected else Color(0.62, 0.56, 0.48)
		var pv: PortraitView = row["view"]
		pv.update_equipment(u.equipment)
		pv.modulate = Color(0.55, 0.3, 0.3) if u.down else Color(1, 1, 1)
	pause_banner.visible = game.paused
	_refresh_selection()


func _refresh_selection() -> void:
	var sel: Array = game.selection
	if sel.size() == 1:
		var u: Unit = sel[0]
		var d: Dictionary = DataDB.heroes.get(u.data_id, {})
		var a: Dictionary = u.attack_profile()
		var armor := str(DataDB.item(str(u.equipment.get("armor", ""))).get("name", "no armor"))
		sel_label.text = u.display_name
		stats_label.text = "%s %s · AC %d · %s %s (%s) · %s" % [d.get("race", ""), d.get("class", ""), u.ac(), a.get("name", ""), Rules.signed(int(a.get("to_hit", 0))), a.get("damage", ""), armor]
	elif sel.size() > 1:
		sel_label.text = "%d heroes" % sel.size()
		stats_label.text = "Orders go to the whole group."
	else:
		sel_label.text = "Nobody selected"
		stats_label.text = "Click a portrait or a hero."
	for k in ["weapon", "armor", "shield", "helm", "torch"]:
		UiSkin.set_slot_state(_buttons[k], false, sel.size() == 1)
	_buttons["pause"].add_theme_stylebox_override("normal", UiSkin.box("slot_active" if game.paused else "slot", 10, 0))
	_rebuild_actions(sel)
	var acts: Array = game.actions_for(sel)
	for a in acts:
		var b: Button = _action_slots.get(a["id"])
		if b == null:
			continue
		UiSkin.set_slot_state(b, bool(a.get("active", false)), bool(a.get("enabled", true)))
		(b.get_meta("badge") as Label).text = str(a.get("badge", ""))
	hint_label.text = game.target_hint()


## Rebuilds the action slots when the selection (or what it can do) changes.
func _rebuild_actions(sel: Array) -> void:
	var acts: Array = game.actions_for(sel)
	var key := ""
	for a in acts:
		key += "%s:%s:%s|" % [a["id"], a["icon"], a.get("tip", "")]
	if key == _action_key:
		return
	_action_key = key
	for c in action_row.get_children():
		c.queue_free()
	_action_slots.clear()
	for a in acts:
		var id: String = a["id"]
		var b := UiSkin.slot(str(a["icon"]), 60, str(a.get("tip", "")), func(): game.use_action(id))
		action_row.add_child(b)
		_action_slots[id] = b


func set_pause_reason(text: String) -> void:
	pause_banner.text = "PAUSED" + ("\n" + text if text != "" else "")


func show_tooltip(text: String, at: Vector2) -> void:
	tooltip.visible = text != ""
	tooltip.text = text
	tooltip.position = at + Vector2(18, 18)


func set_drag(active: bool, a := Vector2.ZERO, b := Vector2.ZERO) -> void:
	(drag_rect as SelectionRect).set_rect_points(active, a, b)


func log_line(bb: String) -> void:
	log_label.append_text(bb + "\n")
