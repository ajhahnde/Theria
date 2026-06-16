class_name ConnectMenu
extends Control
## The in-game connect screen, shown on a windowed launch with no mode flag. It
## lets the player start a single-machine practice match, host a listen-server, or
## join one by address — the same three modes the command line selects with
## `--local`, `--host`, and `--join`, surfaced as UI so a player never needs flags.
##
## Pure presentation: it owns no networking and no simulation, only emitting a
## signal for the chosen mode. `main.gd` wires those signals to the existing
## `_start_*` paths, so the menu adds an entry point without touching authority or
## the wire. A headless run skips it — a menu cannot be driven without a display —
## and the command-line flags stay the automation path.

## The player chose to host a listen-server.
signal host_requested
## The player chose to join a server at `address` (already resolved to the default
## when the field was left blank).
signal join_requested(address: String)
## The player chose a single-machine practice match driving `hero` (a kit id) against
## bots of `difficulty` (a level name). The hero's tribe fields the player's team and the
## opposing tribe the bots, so the pick also chooses the match-up — the same roles
## `--hero` and `--bot-difficulty` fill on the command line.
signal practice_requested(hero: String, difficulty: String)

## Menu styling. An opaque backdrop covers the whole viewport so the debug map and its
## jungle camps — drawn behind the menu in world space — do not bleed through the otherwise
## transparent controls; the card sits on top as a framed panel drawn with the shared UiTheme,
## so the menu reads as one product with the boot screen rather than as floating text over the
## arena. The header is the Theria wordmark in place of a text title.
const CARD_MIN_WIDTH := 680.0
const WORDMARK_WIDTH := 520.0
const TITLE_FALLBACK_SIZE := 72
const FOOTER_FONT_SIZE := 18
const BUTTON_MIN_SIZE := Vector2(560, 76)
const ADDRESS_MIN_WIDTH := 380.0

## The bot difficulty choices, as `[label, level name]` pairs — the label shown in the
## picker, the level name carried as item metadata and emitted on Practice (the same
## names `--bot-difficulty` accepts). Self-contained so the menu stays pure presentation.
const DIFFICULTY_OPTIONS := [["Easy", "easy"], ["Normal", "normal"], ["Hard", "hard"]]

## The update-channel choices, as `[label, channel id]` pairs for the Settings picker. The
## ids mirror `UpdateManifest.CHANNEL_STABLE`/`CHANNEL_BETA`; `Settings` normalises whatever
## is selected, so a label change here can never write an unknown channel.
const CHANNEL_OPTIONS := [["Stable", "stable"], ["Beta (testing)", "beta"]]

## The address used when the player leaves the field blank. The driver injects its
## own default so the menu and the `--join` flag resolve to one value.
var default_address := "127.0.0.1"

## The hero the picker starts on (a kit id). The driver injects its own default — any
## `--hero` already parsed, else the default tribe's lead — so the menu reflects the
## command line. Empty selects the first hero in the list.
var default_hero := ""

## The bot difficulty the picker starts on (a level name). The driver injects its own
## default — any `--bot-difficulty` parsed, else "easy" — so the menu reflects the command
## line. An unknown name leaves the picker on its first option.
var default_difficulty := "easy"

var _address_field: LineEdit
## Picks the hero the player drives in a practice match. Populated from
## `AbilityData.TRIBE` so the roster cannot drift from the simulation's; each item
## carries its kit id as metadata.
var _hero_picker: OptionButton
## Picks the bot skill level for a practice match; each item carries its level name as
## metadata, emitted on the Practice choice.
var _difficulty_picker: OptionButton
## The Settings dialog, built on first open. Carries the update-channel toggle today;
## video/audio options join it as they land.
var _settings_dialog: AcceptDialog


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The shared theme styles every control — the wordmark header, the labels, the dropdowns,
	# the buttons, the address field — so the menu reads as one product with the boot screen.
	theme = UiTheme.make()

	# An opaque backdrop, behind everything, so the world drawn in screen space behind the
	# menu does not show through the transparent controls. Ignores the mouse so it never
	# eats a click meant for a button below it in the tree.
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = UiTheme.BG
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# A framed card so the controls read against a solid panel rather than the arena, drawn
	# with the shared card style so it matches the boot screen.
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.card_style())
	card.custom_minimum_size = Vector2(CARD_MIN_WIDTH, 0)
	center.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	card.add_child(box)

	box.add_child(_header())

	var pick_label := Label.new()
	pick_label.text = "Practice hero"
	box.add_child(pick_label)

	_hero_picker = OptionButton.new()
	_populate_heroes()
	box.add_child(_hero_picker)

	var difficulty_label := Label.new()
	difficulty_label.text = "Bot difficulty"
	box.add_child(difficulty_label)

	_difficulty_picker = OptionButton.new()
	_populate_difficulties()
	box.add_child(_difficulty_picker)

	var practice_button := Button.new()
	practice_button.text = "Practice (single machine)"
	practice_button.custom_minimum_size = BUTTON_MIN_SIZE
	practice_button.pressed.connect(_on_practice_pressed)
	box.add_child(practice_button)

	var host_button := Button.new()
	host_button.text = "Host a match"
	host_button.custom_minimum_size = BUTTON_MIN_SIZE
	host_button.pressed.connect(_on_host_pressed)
	box.add_child(host_button)

	var join_row := HBoxContainer.new()
	box.add_child(join_row)

	_address_field = LineEdit.new()
	_address_field.placeholder_text = default_address
	_address_field.custom_minimum_size = Vector2(ADDRESS_MIN_WIDTH, 0)
	_address_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_address_field)

	var join_button := Button.new()
	join_button.text = "Join"
	join_button.pressed.connect(_on_join_pressed)
	join_row.add_child(join_button)

	box.add_child(_footer())


## The card header: the Theria wordmark texture, falling back to a large text title if the
## asset is somehow missing, so the menu always names itself.
func _header() -> Control:
	var mark := UiTheme.wordmark()
	if mark == null:
		var title := Label.new()
		title.text = "Theria"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", TITLE_FALLBACK_SIZE)
		return title
	var logo := TextureRect.new()
	logo.texture = mark
	logo.custom_minimum_size = Vector2(WORDMARK_WIDTH, 0)
	logo.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return logo


## The card footer: a muted build line on the left (so a tester can report exactly which
## build they are on) and the Settings affordance on the right, under a divider.
func _footer() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 14)
	wrap.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	var build := Label.new()
	build.text = _build_id()
	build.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	build.add_theme_font_size_override("font_size", FOOTER_FONT_SIZE)
	build.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	build.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(build)
	var settings := Button.new()
	settings.text = "⚙ Settings"
	settings.pressed.connect(_open_settings)
	row.add_child(settings)
	wrap.add_child(row)
	return wrap


## The build line: the client version, the installed pck's short sha (or "seed" when running
## the bundled build), and the boot screen's update outcome when it left one. The footer is
## how a playtester names their build in a report, so it reads off the same sources the
## updater wrote.
func _build_id() -> String:
	var sha := UpdateManifest.local_sha()
	var build := sha.substr(0, 7) if not sha.is_empty() else "seed"
	var parts := PackedStringArray(["v%s" % UpdateManifest.client_version(), "build %s" % build])
	var status := str(Engine.get_meta(UiTheme.STATUS_META, ""))
	if not status.is_empty():
		parts.append(status)
	return " · ".join(parts)


## Opens the Settings dialog, building it on first use. Today it carries the update-channel
## toggle — Stable (tagged releases only) or Beta (every main build) — written straight to
## `user://settings.cfg` and applied on the next launch; video/audio options join it later.
func _open_settings() -> void:
	if _settings_dialog == null:
		_settings_dialog = _build_settings_dialog()
		add_child(_settings_dialog)
	_settings_dialog.popup_centered()


## Builds the Settings dialog: a labelled update-channel picker over a hint that the choice
## takes effect on the next launch. The picker starts on the saved channel (via `Settings`)
## and writes each new choice straight back, so closing the dialog needs no Save step. Themed
## with the shared UiTheme so the popup reads as the same product as the menu behind it.
func _build_settings_dialog() -> AcceptDialog:
	var dialog := AcceptDialog.new()
	dialog.title = "Settings"
	dialog.theme = UiTheme.make()

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)

	var label := Label.new()
	label.text = "Update channel"
	box.add_child(label)

	var picker := OptionButton.new()
	for option in CHANNEL_OPTIONS:
		picker.add_item(option[0])
		picker.set_item_metadata(picker.item_count - 1, option[1])
	var saved := Settings.update_channel()
	for i in picker.item_count:
		if picker.get_item_metadata(i) == saved:
			picker.select(i)
			break
	picker.item_selected.connect(_on_channel_selected.bind(picker))
	box.add_child(picker)

	var hint := Label.new()
	hint.text = "Stable: tagged releases only. Beta: every new build. Applies on next launch."
	hint.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	hint.add_theme_font_size_override("font_size", FOOTER_FONT_SIZE)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(ADDRESS_MIN_WIDTH, 0)
	box.add_child(hint)

	dialog.add_child(box)
	return dialog


## Persists the picked update channel. `Settings` normalises the id, so the metadata carried
## by the selected item is written verbatim; the boot scene reads it on the next launch.
func _on_channel_selected(index: int, picker: OptionButton) -> void:
	Settings.set_update_channel(picker.get_item_metadata(index))


## Fills the hero picker from the tribe rosters — one item per hero, labelled
## "Tribe — Hero", carrying its kit id as metadata — and selects `default_hero` (or the
## first hero when none was injected). Reading `AbilityData.TRIBE` keeps the menu's roster
## in lockstep with the simulation's: a new hero appears here the moment it joins a tribe.
func _populate_heroes() -> void:
	for tribe in AbilityData.TRIBE:
		for hero in AbilityData.TRIBE[tribe]:
			_hero_picker.add_item("%s — %s" % [tribe.capitalize(), (hero as String).capitalize()])
			_hero_picker.set_item_metadata(_hero_picker.item_count - 1, hero)
	if default_hero.is_empty():
		return
	for i in _hero_picker.item_count:
		if _hero_picker.get_item_metadata(i) == default_hero:
			_hero_picker.select(i)
			return


## The kit id of the selected hero, falling back to `default_hero` if nothing is
## selected (an empty roster — never the case while a tribe is defined).
func _selected_hero() -> String:
	if _hero_picker.selected < 0:
		return default_hero
	return _hero_picker.get_item_metadata(_hero_picker.selected)


## Fills the difficulty picker from `DIFFICULTY_OPTIONS` — one item per level, carrying
## its level name as metadata — and selects `default_difficulty` (or the first option
## when the injected name is unknown).
func _populate_difficulties() -> void:
	for option in DIFFICULTY_OPTIONS:
		_difficulty_picker.add_item(option[0])
		_difficulty_picker.set_item_metadata(_difficulty_picker.item_count - 1, option[1])
	for i in _difficulty_picker.item_count:
		if _difficulty_picker.get_item_metadata(i) == default_difficulty:
			_difficulty_picker.select(i)
			return


## The level name of the selected difficulty, falling back to `default_difficulty` if
## nothing is selected (never the case while options are defined).
func _selected_difficulty() -> String:
	if _difficulty_picker.selected < 0:
		return default_difficulty
	return _difficulty_picker.get_item_metadata(_difficulty_picker.selected)


func _on_practice_pressed() -> void:
	practice_requested.emit(_selected_hero(), _selected_difficulty())


func _on_host_pressed() -> void:
	host_requested.emit()


## Resolves the typed address — falling back to `default_address` when blank — and
## emits `join_requested`. Trimmed so stray whitespace is not taken as a host name.
func _on_join_pressed() -> void:
	var address := _address_field.text.strip_edges()
	if address.is_empty():
		address = default_address
	join_requested.emit(address)
