class_name UiTheme
extends RefCounted
## The client's shared look: one palette and one `Theme` factory the menu screens build
## on, so the boot/update screen and the title screen read as one product rather than two
## code-built panels that drifted apart. Authored in code (not a `.tres`), matching the way
## the rest of the client builds its scenes in code — so the Godot editor, which rewrites
## `project.godot`, is never needed to touch the UI.
##
## The palette is a dark jungle base with a single warm savanna-amber accent — Theria's
## two biomes in two roles: the world is the deep green/charcoal ground the controls sit on,
## the accent is the one colour that marks focus and the active control. Keeping the accent to
## one hue is what makes a code-built UI read as designed rather than busy.

const BG := Color(0.07, 0.09, 0.08)  # the deep jungle backdrop behind everything
const PANEL := Color(0.12, 0.14, 0.15)  # the card the controls sit on
const PANEL_BORDER := Color(0.20, 0.23, 0.22)
const BUTTON := Color(0.16, 0.19, 0.20)
const BUTTON_HOVER := Color(0.22, 0.26, 0.26)
const BUTTON_PRESSED := Color(0.10, 0.12, 0.13)
const FIELD := Color(0.09, 0.11, 0.11)
const ACCENT := Color(0.95, 0.69, 0.26)  # savanna amber — focus, the active edge
const TEXT := Color(0.92, 0.93, 0.94)
const TEXT_MUTED := Color(0.58, 0.62, 0.62)  # the footer build/status line

const BASE_FONT_SIZE := 26
const CORNER := 10
const BUTTON_PAD := 16.0

## The wordmark logo, the title screens' header in place of a text title. Loaded by path
## so a caller need not know it is an imported SVG texture.
const WORDMARK_PATH := "res://wordmark.svg"

## Engine-meta key the boot screen writes its update outcome to and the title screen reads
## for its footer. Engine meta outlives a `change_scene_to_file`, so the one word the boot
## learned ("up to date" / "updated" / "offline") survives the hand-off to the menu without
## a file write or a shared autoload.
const STATUS_META := "theria_update_status"


## A fully configured Theme every menu control inherits: button states, the framed panel,
## the address field, the dropdown, and the base font size. Built fresh per caller so a
## screen may tweak its own copy without bleeding into the other.
static func make() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = BASE_FONT_SIZE

	theme.set_stylebox("normal", "Button", _button_style(BUTTON, false))
	theme.set_stylebox("hover", "Button", _button_style(BUTTON_HOVER, false))
	theme.set_stylebox("pressed", "Button", _button_style(BUTTON_PRESSED, false))
	theme.set_stylebox("focus", "Button", _button_style(BUTTON_HOVER, true))
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", ACCENT)

	# OptionButton draws as a Button but keeps its own theme type, so it needs the same
	# styleboxes or it falls back to the flat default and looks unthemed next to the buttons.
	theme.set_stylebox("normal", "OptionButton", _button_style(BUTTON, false))
	theme.set_stylebox("hover", "OptionButton", _button_style(BUTTON_HOVER, false))
	theme.set_stylebox("pressed", "OptionButton", _button_style(BUTTON_PRESSED, false))
	theme.set_stylebox("focus", "OptionButton", _button_style(BUTTON_HOVER, true))
	theme.set_color("font_color", "OptionButton", TEXT)

	theme.set_stylebox("normal", "LineEdit", _field_style())
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", TEXT_MUTED)
	theme.set_color("caret_color", "LineEdit", ACCENT)

	theme.set_stylebox("panel", "PanelContainer", card_style())
	return theme


## The framed card the menu controls sit on: a solid dark panel with rounded corners, a
## faint border, and generous inner padding. Public so a screen can reuse the exact card.
static func card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.set_corner_radius_all(CORNER + 4)
	style.set_border_width_all(1)
	style.border_color = PANEL_BORDER
	style.set_content_margin_all(48.0)
	return style


## A button face in `color`. With `focused`, an amber edge marks the keyboard-focused
## control so the menu is navigable without a mouse.
static func _button_style(color: Color, focused: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(CORNER)
	style.set_content_margin_all(BUTTON_PAD)
	if focused:
		style.set_border_width_all(2)
		style.border_color = ACCENT
	return style


## The address field's face: a recessed dark slot with rounded corners, distinct from the
## raised buttons so it reads as an input rather than another button.
static func _field_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = FIELD
	style.set_corner_radius_all(CORNER)
	style.set_border_width_all(1)
	style.border_color = PANEL_BORDER
	style.set_content_margin_all(12.0)
	return style


## The wordmark texture, or null if it is somehow missing (a caller falls back to a text
## title), so a screen never crashes for a stripped asset.
static func wordmark() -> Texture2D:
	if not ResourceLoader.exists(WORDMARK_PATH):
		return null
	return load(WORDMARK_PATH) as Texture2D
