class_name MatchHud
extends Control
## The in-match heads-up display for the player's own hero: a bottom-centre cluster
## carrying the hero's name + active form, its HP and resource bars, and the QWER
## ability bar with live cooldowns. Pure presentation — each tick the driver hands it
## the player's hero entity and it reconciles every readout, or hides while the hero is
## absent or down (the death screen covers that). It owns no simulation and reads only
## the entity's fields (hp, resource, form, the equipped kit, and the per-ability
## cooldowns), exactly as `death_overlay` reads `respawn_ticks`. Built in code on the
## shared `UiTheme` palette — no `.tscn`, no editor pass — like the rest of the client.
##
## Layout is the MOBA-standard bottom bar: a portrait panel (name + form badge), the
## HP/resource bars, and a four-slot ability row, so a player coming from the genre reads
## it at a glance. The four cells map one-to-one to PlayerInput's QWER binds; a hero fills
## only three slots per form (the fourth is the other form's), so one cell shows empty —
## that gap is the shapeshifter's two-kits-in-one identity, kept visible on purpose.
##
## A settings button sits in the top-right corner. It is a placeholder: pressing it fires
## `settings_pressed`, which the driver is free to leave unhandled for now — the in-match
## settings menu itself is a later slice, this is only the entry point reserved in the layout.

## Fired when the player clicks the settings button. A placeholder hook — there is no
## settings menu yet; the driver may connect a stub until that slice lands.
signal settings_pressed

## The QWER bind letters, one per ability slot 0..3 — the on-cell label, matching the
## order of `PlayerInput.ABILITY_KEYS` so the cell a key fires is the cell it is drawn on.
const SLOT_KEYS: Array[String] = ["Q", "W", "E", "R"]

## Ability-cell geometry (pixels): a square cell, the gap between cells, and the bar/panel
## sizing. The HP and resource bars span the same width as the four-cell row so the cluster
## reads as one block.
const CELL := 60.0
const CELL_SEP := 10.0
const BAR_HEIGHT := 22.0
const BAR_SPACING := 6.0
const CLUSTER_SEP := 18.0
const BOTTOM_MARGIN := 22.0
## Settings button geometry: a small square pinned the corner margin in from the top-right.
const SETTINGS_SIZE := 44.0
const SETTINGS_MARGIN := 16.0

## Cell face colour by ability effect (AbilitySpec.EFFECT_*): a warm strike, a green
## restore, the amber transform — the one accent the rest of the UI already uses for focus.
const DAMAGE_COLOR := Color(0.74, 0.34, 0.26)
const HEAL_COLOR := Color(0.34, 0.58, 0.36)
const TRANSFORM_COLOR := Color(0.62, 0.46, 0.20)
const EMPTY_COLOR := Color(0.10, 0.12, 0.12)  # the slot the active form does not fill

## Cell border by cast state: amber when the ability is ready, a cool tint when it is only
## blocked on resource (a hint that it is the pool, not the timer, that gates it), muted
## otherwise (on cooldown, empty).
const READY_BORDER := Color(0.95, 0.69, 0.26)  # UiTheme.ACCENT
const NO_RESOURCE_BORDER := Color(0.35, 0.52, 0.78)
const MUTED_BORDER := Color(0.22, 0.25, 0.24)

## The dark wash drawn over the unready portion of a cell, draining as the cooldown ticks
## down so the cell brightens from the bottom up as it readies.
const COOLDOWN_WASH := Color(0.0, 0.0, 0.0, 0.62)

const HP_FILL := Color(0.40, 0.72, 0.40)
const RESOURCE_FILL := Color(0.35, 0.60, 0.95)
const BAR_BG := Color(0.05, 0.06, 0.06, 0.85)

const NAME_FONT_SIZE := 22
const FORM_FONT_SIZE := 15
const BAR_FONT_SIZE := 14
const KEY_FONT_SIZE := 15
const COOLDOWN_FONT_SIZE := 26
const ABILITY_NAME_FONT_SIZE := 11

## Source of the tick rate cooldowns are counted in, so a remaining-tick count renders as
## the whole seconds a player reads ("3… 2… 1…"), rounded up like the respawn timer.
const TICK_RATE := SimCore.TICK_RATE

var _settings_button: Button
## The bottom cluster's frame, kept so a test can assert it lays out to a real on-screen size.
var _frame: PanelContainer
var _name_label: Label
var _form_label: Label
## Each bar as `{root, fill, label, frac}`; `frac` is the last fill fraction, kept so a test
## can read the bound value without waiting on a container layout pass.
var _hp: Dictionary = {}
var _resource: Dictionary = {}
## The four ability cells, slot 0..3. Each is `{root, style, wash, key, cooldown, name, frac}`
## — the nodes `_update_cell` mutates plus the last cooldown fraction, again for tests.
var _cells: Array[Dictionary] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The match plays under the HUD: never eat a click, so click-to-move and casts on the
	# field below pass straight through the empty space around the cluster.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := _build_frame()
	var cluster := HBoxContainer.new()
	cluster.add_theme_constant_override("separation", CLUSTER_SEP)
	cluster.alignment = BoxContainer.ALIGNMENT_CENTER
	frame.add_child(cluster)
	cluster.add_child(_build_portrait())
	cluster.add_child(_build_center())
	_build_settings_button()


## The settings entry point: a gear button pinned top-right, on the shared menu theme so it
## reads as the same product. A placeholder — it only re-emits `settings_pressed`; the menu it
## will open is a later slice. Built last so it layers over the rest of the (empty) HUD canvas.
func _build_settings_button() -> void:
	_settings_button = Button.new()
	_settings_button.text = "⚙"
	_settings_button.theme = UiTheme.make()
	_settings_button.add_theme_font_size_override("font_size", 22)
	_settings_button.custom_minimum_size = Vector2(SETTINGS_SIZE, SETTINGS_SIZE)
	add_child(_settings_button)
	# Pin to the top-right corner with explicit offsets (a preset sets anchors but not offsets,
	# leaving a zero-size box at the corner): a fixed square the corner margin in from the edge.
	_settings_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_settings_button.offset_left = -SETTINGS_SIZE - SETTINGS_MARGIN
	_settings_button.offset_right = -SETTINGS_MARGIN
	_settings_button.offset_top = SETTINGS_MARGIN
	_settings_button.offset_bottom = SETTINGS_MARGIN + SETTINGS_SIZE
	_settings_button.pressed.connect(func() -> void: settings_pressed.emit())


# --- Build ------------------------------------------------------------------


## The bottom-centre panel the cluster sits in. Pinned by containers rather than by hand: a
## full-rect column bottom-aligns its one row, the row centres the frame, and the frame sizes
## to its content — so it hugs the bottom-centre of any window without the manual anchor math
## that collapses a Container to zero size. Framed on the shared palette like the menus.
func _build_frame() -> PanelContainer:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_bottom = -BOTTOM_MARGIN
	column.alignment = BoxContainer.ALIGNMENT_END
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
	_frame = PanelContainer.new()
	_frame.add_theme_stylebox_override("panel", _panel_style())
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_frame)
	return _frame


## The portrait column: the hero's name over a form badge. The badge names the active form
## — the human stance or, in beast form, the creature the hero shifts into — so the player
## always sees which kit the QWER bar currently casts.
func _build_portrait() -> Control:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.custom_minimum_size = Vector2(150.0, 0.0)
	_name_label = _label("", NAME_FONT_SIZE, UiTheme.TEXT)
	_form_label = _label("", FORM_FONT_SIZE, UiTheme.ACCENT)
	box.add_child(_name_label)
	box.add_child(_form_label)
	return box


## The centre column: the HP bar, the resource bar, then the four-cell ability row, stacked
## so the vital readouts sit directly over the keys that spend them.
func _build_center() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", BAR_SPACING)
	_hp = _make_bar(HP_FILL)
	_resource = _make_bar(RESOURCE_FILL)
	box.add_child(_hp["root"])
	box.add_child(_resource["root"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", CELL_SEP)
	for slot in SLOT_KEYS.size():
		var cell := _make_cell(SLOT_KEYS[slot])
		_cells.append(cell)
		row.add_child(cell["slot_box"])
	box.add_child(row)
	return box


## A value bar (HP, resource): a dark track, a coloured fill sized each tick by fraction,
## and a centred `current / max` readout. Returned as the node refs the per-tick update
## mutates; the fill is positioned by hand (not a container child) so its width is the value.
func _make_bar(fill_color: Color) -> Dictionary:
	var root := Control.new()
	root.custom_minimum_size = Vector2(0.0, BAR_HEIGHT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = BAR_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	var fill := ColorRect.new()
	fill.color = fill_color
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fill)
	var label := _label("", BAR_FONT_SIZE, UiTheme.TEXT)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(label)
	return {"root": root, "fill": fill, "label": label, "frac": 0.0}


## One ability cell: a framed square whose face colours by effect and whose border marks
## cast state, with the bind letter in the corner, a draining cooldown wash, the remaining
## seconds over it, and the ability's name beneath. Returned as the refs the update mutates.
func _make_cell(key: String) -> Dictionary:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(8)
	style.set_border_width_all(2)
	var cell := Panel.new()
	cell.custom_minimum_size = Vector2(CELL, CELL)
	cell.add_theme_stylebox_override("panel", style)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wash := ColorRect.new()
	wash.color = COOLDOWN_WASH
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(wash)
	var key_label := _label(key, KEY_FONT_SIZE, UiTheme.TEXT)
	key_label.position = Vector2(5.0, 2.0)
	cell.add_child(key_label)
	var cooldown := _label("", COOLDOWN_FONT_SIZE, UiTheme.TEXT)
	cooldown.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cooldown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cooldown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cell.add_child(cooldown)
	var name_label := _label("", ABILITY_NAME_FONT_SIZE, UiTheme.TEXT_MUTED)
	name_label.custom_minimum_size = Vector2(CELL, 0.0)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var slot_box := VBoxContainer.new()
	slot_box.add_theme_constant_override("separation", 3)
	slot_box.add_child(cell)
	slot_box.add_child(name_label)
	return {
		"slot_box": slot_box,
		"style": style,
		"wash": wash,
		"cooldown": cooldown,
		"name": name_label,
		"frac": 0.0,
	}


# --- Per-tick update --------------------------------------------------------


## Reconciles the HUD with the player's hero: hidden while the hero is absent (not yet
## spawned) or down (the death screen owns the screen then), otherwise every readout bound
## to the live entity. The single entry point the driver calls each tick.
func refresh(hero: SimEntity) -> void:
	if hero == null or hero.is_dead():
		hide()
		return
	show()
	_name_label.text = hero.kit_id.capitalize() if hero.kit_id != "" else "—"
	_form_label.text = _form_text(hero)
	_set_bar(_hp, hero.hp, hero.max_hp)
	_set_bar(_resource, hero.resource, hero.resource_max)
	var bar: Dictionary = hero.kit.get(hero.form, {})
	for slot in _cells.size():
		_update_cell(_cells[slot], hero, bar.get(slot, 0))


## The form badge: the human stance, or in beast form the creature the kit shifts into
## (the hero's own name), so the badge reads as the active kit rather than a generic word.
func _form_text(hero: SimEntity) -> String:
	if hero.form == AbilitySpec.FORM_ANIMAL:
		return hero.kit_id.capitalize().to_upper() if hero.kit_id != "" else "BEAST"
	return "HUMAN"


## Fills a bar to `current / max_value` and writes the readout. Stores the fraction so the
## value is inspectable without a layout pass; sizes the fill from the bar's laid-out width.
func _set_bar(bar: Dictionary, current: int, max_value: int) -> void:
	var frac := 0.0 if max_value <= 0 else clampf(float(current) / float(max_value), 0.0, 1.0)
	bar["frac"] = frac
	var root := bar["root"] as Control
	var fill := bar["fill"] as ColorRect
	fill.position = Vector2.ZERO
	fill.size = Vector2(root.size.x * frac, root.size.y)
	(bar["label"] as Label).text = "%d / %d" % [maxi(current, 0), maxi(max_value, 0)]


## Reconciles one cell with the ability the hero now carries in that slot. An empty slot
## (the other form's) reads as a dimmed blank; otherwise the face colours by effect, the
## border marks ready / blocked-on-resource / on-cooldown, the wash drains with the
## remaining cooldown, and the seconds and name are written. Reads only — no node is built.
func _update_cell(cell: Dictionary, hero: SimEntity, ability_id: int) -> void:
	var style := cell["style"] as StyleBoxFlat
	var wash := cell["wash"] as ColorRect
	if ability_id == 0:
		style.bg_color = EMPTY_COLOR
		style.border_color = MUTED_BORDER
		wash.visible = false
		cell["frac"] = 0.0
		(cell["cooldown"] as Label).text = ""
		(cell["name"] as Label).text = ""
		return
	var spec := AbilityData.spec(ability_id)
	var remaining: int = hero.ability_cooldowns.get(ability_id, 0)
	var total := maxi(spec.cooldown_ticks, 1)
	var on_cooldown := remaining > 0
	var affordable := hero.resource >= spec.cost
	var ready := not on_cooldown and affordable and not hero.is_stunned()
	var face := _effect_color(spec.effect)
	style.bg_color = face if ready else face.darkened(0.45)
	if ready:
		style.border_color = READY_BORDER
	elif not on_cooldown and not affordable:
		style.border_color = NO_RESOURCE_BORDER
	else:
		style.border_color = MUTED_BORDER
	var frac := float(remaining) / float(total)
	cell["frac"] = frac
	wash.visible = on_cooldown
	if on_cooldown:
		var w: float = (cell["slot_box"] as Control).size.x
		var width := w if w > 0.0 else CELL
		wash.position = Vector2.ZERO
		wash.size = Vector2(width, CELL * frac)
	var seconds := str(ceili(float(remaining) / float(TICK_RATE)))
	(cell["cooldown"] as Label).text = seconds if on_cooldown else ""
	(cell["name"] as Label).text = spec.name


# --- Helpers ----------------------------------------------------------------


func _effect_color(effect: int) -> Color:
	match effect:
		AbilitySpec.EFFECT_HEAL:
			return HEAL_COLOR
		AbilitySpec.EFFECT_TRANSFORM:
			return TRANSFORM_COLOR
		_:
			return DAMAGE_COLOR


## A configured label — the one place font size and colour are set, so every readout shares
## the build and only its text and placement vary.
func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## The HUD frame's face: the shared panel colour with a faint border and tight inner
## padding — the menu card's look, trimmed to a strip that frames the cluster.
func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.PANEL
	style.set_corner_radius_all(UiTheme.CORNER)
	style.set_border_width_all(1)
	style.border_color = UiTheme.PANEL_BORDER
	style.set_content_margin_all(14.0)
	return style
