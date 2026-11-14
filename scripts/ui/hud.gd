class_name Hud
extends CanvasLayer
## Baldur's Gate style interface: portraits on the right, combat log and
## action buttons at the bottom, pause banner, tooltip and help panel.

const GOLD := Color(0.79, 0.64, 0.29)
const INK := Color(0.91, 0.86, 0.75)
const CLASS_COLORS := {"Fighter": Color(0.55, 0.2, 0.18), "Rogue": Color(0.2, 0.33, 0.2), "Cleric": Color(0.55, 0.45, 0.22), "Wizard": Color(0.28, 0.22, 0.5)}

var game: Node
var root: Control
var portraits: VBoxContainer
var log_label: RichTextLabel
var sel_label: Label
var pause_banner: Label
var tooltip: Label
var help_panel: PanelContainer
var drag_rect: Control
var _portrait_rows: Array[Dictionary] = []
var _buttons: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	drag_rect = SelectionRect.new()
	drag_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	drag_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(drag_rect)

	# --- right: portraits ---
	var right := _panel()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.anchor_top = 0.0
	right.anchor_bottom = 1.0
	right.offset_left = -150
	right.offset_bottom = -190
	root.add_child(right)
	portraits = VBoxContainer.new()
	portraits.add_theme_constant_override("separation", 8)
	right.add_child(portraits)

	# --- bottom: log + actions ---
	var bottom := _panel()
	bottom.anchor_left = 0.0
	bottom.anchor_right = 1.0
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_top = -190
	root.add_child(bottom)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	bottom.add_child(hb)

	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.custom_minimum_size = Vector2(520, 160)
	log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_label.add_theme_color_override("default_color", INK)
	log_label.add_theme_font_size_override("normal_font_size", 15)
	log_label.add_theme_font_size_override("bold_font_size", 15)
	var log_bg := StyleBoxFlat.new()
	log_bg.bg_color = Color(0, 0, 0, 0.45)
	log_bg.content_margin_left = 8
	log_bg.content_margin_top = 4
	log_label.add_theme_stylebox_override("normal", log_bg)
	hb.add_child(log_label)

	var actions := VBoxContainer.new()
	actions.custom_minimum_size = Vector2(430, 0)
	hb.add_child(actions)
	sel_label = Label.new()
	sel_label.add_theme_color_override("font_color", GOLD)
	sel_label.add_theme_font_size_override("font_size", 16)
	actions.add_child(sel_label)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	actions.add_child(grid)
	_add_button(grid, "stop", "Stop  [X]", func(): game.cmd_stop())
	_add_button(grid, "weapon", "Swap weapon", func(): game.cmd_cycle("main_hand", ["weapon"]))
	_add_button(grid, "armor", "Change armor", func(): game.cmd_cycle("armor", ["armor"]))
	_add_button(grid, "shield", "Shield on/off", func(): game.cmd_toggle("off_hand", "shield"))
	_add_button(grid, "helm", "Helmet on/off", func(): game.cmd_toggle("head", "helmet"))
	_add_button(grid, "torch", "Torch on/off", func(): game.cmd_toggle("off_hand", "light"))
	_add_button(grid, "heal", "Cure Wounds  [C]", func(): game.cmd_heal())
	_add_button(grid, "pause", "Pause  [Space]", func(): game.toggle_pause())
	_add_button(grid, "help", "Help  [H]", func(): help_panel.visible = not help_panel.visible)
	_add_button(grid, "reset", "Restart  [F5]", func(): game.get_tree().reload_current_scene())

	# --- top: pause banner ---
	pause_banner = Label.new()
	pause_banner.text = "PAUSED"
	pause_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_banner.anchor_left = 0.5
	pause_banner.anchor_right = 0.5
	pause_banner.offset_left = -220
	pause_banner.offset_right = 220
	pause_banner.offset_top = 12
	pause_banner.add_theme_font_size_override("font_size", 22)
	pause_banner.add_theme_color_override("font_color", Color(1, 0.88, 0.88))
	var pb := StyleBoxFlat.new()
	pb.bg_color = Color(0.45, 0.02, 0.02, 0.8)
	pb.border_color = Color(1, 0.4, 0.4)
	pb.set_border_width_all(1)
	pb.content_margin_top = 4
	pb.content_margin_bottom = 4
	pause_banner.add_theme_stylebox_override("normal", pb)
	pause_banner.visible = false
	pause_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pause_banner)

	tooltip = Label.new()
	tooltip.visible = false
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tb := StyleBoxFlat.new()
	tb.bg_color = Color(0.04, 0.03, 0.02, 0.92)
	tb.border_color = GOLD * Color(1, 1, 1, 0.7)
	tb.set_border_width_all(1)
	tb.set_content_margin_all(6)
	tooltip.add_theme_stylebox_override("normal", tb)
	tooltip.add_theme_color_override("font_color", INK)
	root.add_child(tooltip)

	help_panel = _panel()
	help_panel.anchor_left = 0.5
	help_panel.anchor_right = 0.5
	help_panel.anchor_top = 0.5
	help_panel.anchor_bottom = 0.5
	help_panel.offset_left = -300
	help_panel.offset_right = 300
	help_panel.offset_top = -230
	help_panel.offset_bottom = 150
	var ht := RichTextLabel.new()
	ht.bbcode_enabled = true
	ht.fit_content = true
	ht.add_theme_color_override("default_color", INK)
	ht.text = "[b][color=#c9a24a]LOST MINES — TEST SCENE[/color][/b]\n\n" \
		+ "[color=#c9a24a]Left click[/color]  select hero · move · attack enemy\n" \
		+ "[color=#c9a24a]Drag[/color]  box-select heroes   [color=#c9a24a]Shift[/color]  add to selection\n" \
		+ "[color=#c9a24a]1–4 / Ctrl+A[/color]  select hero / whole party\n" \
		+ "[color=#c9a24a]Space[/color]  pause — give orders while paused\n" \
		+ "[color=#c9a24a]WASD / arrows / screen edge[/color]  move camera\n" \
		+ "[color=#c9a24a]Q / E or middle mouse[/color]  rotate camera · [color=#c9a24a]wheel[/color] zoom · [color=#c9a24a]F[/color] focus\n" \
		+ "[color=#c9a24a]X[/color] stop · [color=#c9a24a]F5[/color] restart · [color=#c9a24a]H[/color] this help\n\n" \
		+ "Use the equipment buttons to see gear change on the selected hero.\n" \
		+ "Edit [i]data/*.json[/i] while the game runs — changes load within a second."
	help_panel.add_child(ht)
	help_panel.visible = false
	root.add_child(help_panel)


func build_portraits(party: Array) -> void:
	for c in portraits.get_children():
		c.queue_free()
	_portrait_rows.clear()
	for u in party:
		var b := Button.new()
		b.custom_minimum_size = Vector2(132, 92)
		b.toggle_mode = false
		b.focus_mode = Control.FOCUS_NONE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.04, 0.03)
		sb.border_color = Color(0.3, 0.24, 0.15)
		sb.set_border_width_all(2)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		var face := ColorRect.new()
		var cls := str(DataDB.heroes.get(u.data_id, {}).get("class", ""))
		face.color = CLASS_COLORS.get(cls, Color(0.3, 0.3, 0.3))
		face.position = Vector2(4, 4)
		face.size = Vector2(124, 58)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(face)
		var initial := Label.new()
		initial.text = u.display_name.substr(0, 1)
		initial.add_theme_font_size_override("font_size", 34)
		initial.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
		initial.position = Vector2(52, 6)
		initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(initial)
		var name_lbl := Label.new()
		name_lbl.text = u.display_name.split(" ")[0]
		name_lbl.position = Vector2(8, 6)
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(name_lbl)
		var bar := ProgressBar.new()
		bar.position = Vector2(4, 66)
		bar.size = Vector2(124, 20)
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.25, 0.6, 0.25)
		bar.add_theme_stylebox_override("fill", fill)
		var bgs := StyleBoxFlat.new()
		bgs.bg_color = Color(0.3, 0.05, 0.05)
		bar.add_theme_stylebox_override("background", bgs)
		b.add_child(bar)
		var hp := Label.new()
		hp.position = Vector2(4, 66)
		hp.size = Vector2(124, 20)
		hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hp.add_theme_font_size_override("font_size", 12)
		hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(hp)
		var unit: Unit = u
		b.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				game.select_unit(unit, ev.shift_pressed)
				if ev.double_click:
					game.rig.focus(unit.global_position)
		)
		portraits.add_child(b)
		_portrait_rows.append({"unit": u, "box": sb, "bar": bar, "hp": hp, "fill": fill})


func refresh() -> void:
	for row in _portrait_rows:
		var u: Unit = row["unit"]
		var bar: ProgressBar = row["bar"]
		bar.max_value = u.max_hp
		bar.value = u.hp
		(row["hp"] as Label).text = "Unconscious" if u.down else "%d / %d" % [u.hp, u.max_hp]
		(row["box"] as StyleBoxFlat).border_color = Color(0.35, 1.0, 0.35) if u.selected else Color(0.3, 0.24, 0.15)
		(row["fill"] as StyleBoxFlat).bg_color = Color(0.25, 0.6, 0.25) if u.hp > u.max_hp / 3 else Color(0.75, 0.2, 0.15)
	pause_banner.visible = game.paused
	var sel: Array = game.selection
	if sel.size() == 1:
		var u: Unit = sel[0]
		var a: Dictionary = u.attack_profile()
		var armor := str(DataDB.item(str(u.equipment.get("armor", ""))).get("name", "No armor"))
		sel_label.text = "%s — AC %d · %s (%s, %s) · %s" % [u.display_name, u.ac(), a.get("name", ""), Rules.signed(int(a.get("to_hit", 0))), a.get("damage", ""), armor]
	elif sel.size() > 1:
		sel_label.text = "%d heroes selected" % sel.size()
	else:
		sel_label.text = "Nobody selected — click a portrait"
	for k in ["weapon", "armor", "shield", "helm", "torch"]:
		(_buttons[k] as Button).disabled = sel.size() != 1


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


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.075, 0.055, 0.95)
	sb.border_color = Color(0.54, 0.43, 0.23)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


func _add_button(parent: Control, key: String, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(138, 34)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	_buttons[key] = b
