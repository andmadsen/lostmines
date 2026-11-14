class_name UiSkin
## Shared look of the interface: fonts, gold-framed panels, action slots.
## The textures in res://ui/skin are drawn by tools/make_ui_skin.py.

const GOLD := Color(0.86, 0.7, 0.36)
const GOLD_DIM := Color(0.6, 0.48, 0.25)
const INK := Color(0.93, 0.88, 0.76)
const INK_DIM := Color(0.7, 0.64, 0.52)

static var _title: Font
static var _body: Font
static var _cache: Dictionary = {}


## Cinzel: carved Roman capitals for names, headings and buttons.
static func title_font() -> Font:
	if _title == null:
		_title = _variable("res://ui/fonts/Cinzel.ttf", 700)
	return _title


## EB Garamond: book type for the log, tooltips and descriptions.
static func body_font() -> Font:
	if _body == null:
		_body = _variable("res://ui/fonts/EBGaramond.ttf", 500)
	return _body


static func _variable(path: String, weight: int) -> Font:
	if not ResourceLoader.exists(path):
		return ThemeDB.fallback_font
	var fv := FontVariation.new()
	fv.base_font = load(path)
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return fv


static func tex(name: String) -> Texture2D:
	var p := "res://ui/skin/%s.png" % name
	if not _cache.has(p):
		_cache[p] = load(p) if ResourceLoader.exists(p) else null
	return _cache[p]


static func icon(name: String) -> Texture2D:
	var p := "res://ui/icons/%s.svg" % name
	if not _cache.has(p):
		_cache[p] = load(p) if ResourceLoader.exists(p) else null
	return _cache[p]


## A 9-patch stylebox from a skin texture.
static func box(name: String, margin := 18, content := 12) -> StyleBox:
	var t := tex(name)
	if t == null:
		var f := StyleBoxFlat.new()
		f.bg_color = Color(0.12, 0.09, 0.06, 0.95)
		f.border_color = GOLD_DIM
		f.set_border_width_all(2)
		f.set_content_margin_all(content)
		return f
	var sb := StyleBoxTexture.new()
	sb.texture = t
	sb.set_texture_margin_all(margin)
	sb.set_content_margin_all(content)
	return sb


## Sunken dark area inside a panel (the log, the hint line).
static func inset() -> StyleBoxFlat:
	var f := StyleBoxFlat.new()
	f.bg_color = Color(0.03, 0.02, 0.015, 0.75)
	f.border_color = Color(0.0, 0.0, 0.0, 0.8)
	f.border_width_top = 2
	f.border_width_left = 2
	f.border_width_bottom = 1
	f.border_width_right = 1
	f.set_corner_radius_all(3)
	f.content_margin_left = 10
	f.content_margin_right = 8
	f.content_margin_top = 6
	f.content_margin_bottom = 6
	return f


## The interface theme: fonts, colours and the tooltip panel.
static func theme() -> Theme:
	var th := Theme.new()
	th.default_font = body_font()
	th.default_font_size = 17
	th.set_color("font_color", "Label", INK)
	th.set_color("default_color", "RichTextLabel", INK)
	th.set_stylebox("panel", "TooltipPanel", box("panel", 18, 10))
	th.set_font("font", "TooltipLabel", body_font())
	th.set_font_size("font_size", "TooltipLabel", 16)
	th.set_color("font_color", "TooltipLabel", INK)
	return th


static func title_label(text: String, size := 16, color := GOLD) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", title_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A square action slot with an icon, a hover glow and an optional badge
## (e.g. spell slots left). Returns the Button; the badge is meta "badge".
static func slot(icon_name: String, size: int, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(size, size)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.add_theme_stylebox_override("normal", box("slot", 10, 0))
	b.add_theme_stylebox_override("hover", box("slot_hover", 10, 0))
	b.add_theme_stylebox_override("pressed", box("slot_active", 10, 0))
	b.add_theme_stylebox_override("disabled", box("slot", 10, 0))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var ic := TextureRect.new()
	ic.texture = icon(icon_name)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pad := int(size * 0.16)
	ic.offset_left = pad
	ic.offset_top = pad
	ic.offset_right = -pad
	ic.offset_bottom = -pad
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ic)
	b.set_meta("icon", ic)
	var badge := Label.new()
	badge.add_theme_font_override("font", title_font())
	badge.add_theme_font_size_override("font_size", 13)
	badge.add_theme_color_override("font_color", Color(1, 0.92, 0.6))
	badge.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	badge.add_theme_constant_override("outline_size", 5)
	badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	badge.offset_left = -22
	badge.offset_top = -22
	badge.offset_right = -5
	badge.offset_bottom = -2
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(badge)
	b.set_meta("badge", badge)
	b.pressed.connect(cb)
	return b


## Marks a slot as the active choice (glowing rim) or dims it when unusable.
static func set_slot_state(b: Button, active: bool, enabled: bool) -> void:
	b.add_theme_stylebox_override("normal", box("slot_active" if active else "slot", 10, 0))
	b.disabled = not enabled
	(b.get_meta("icon") as TextureRect).modulate = Color(1, 1, 1) if enabled else Color(0.45, 0.42, 0.38)
