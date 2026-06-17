class_name ErrorOverlay
extends Control
## The full-screen error screen, shown when a match fails in a way that would otherwise grey the
## screen or quit without a word — a host that cannot open its port, a join that reaches no server,
## a refused or dropped connection. It names the failure, shows its code (so a bug report can quote
## it), and offers the player a way out: back to the connect menu, or quit. Pure presentation — it
## owns no networking; `main.gd` shows it on a failure and acts on its two signals.
##
## Unlike the death screen (a dim the live world plays on behind), this is an OPAQUE cover: the
## match behind it is broken or gone, so nothing should show through or take a click meant for the
## buttons. A headless run never builds it — there is no screen, and a failed smoke just exits.

## The player chose the connect menu — the driver tears the failed match down and reopens it.
signal menu_requested
## The player chose to quit the game.
signal quit_requested

const TITLE_COLOR := Color(0.90, 0.40, 0.32)  # a warm alarm red, distinct from the amber accent
const TITLE_FONT_SIZE := 56
const CODE_FONT_SIZE := 28
const DETAIL_FONT_SIZE := 22
const DETAIL_MAX_WIDTH := 760.0

var _title: Label
var _code: Label
var _detail: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The shared theme styles the two buttons so the error screen reads as one product with the menu.
	theme = UiTheme.make()

	# An opaque cover, so the broken match behind it neither shows through nor takes a click — STOP
	# (not IGNORE, the way the death dim passes clicks) so the dead world below never catches one.
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = UiTheme.BG
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 22)
	center.add_child(box)

	_title = _line(TITLE_FONT_SIZE, TITLE_COLOR)
	box.add_child(_title)

	_code = _line(CODE_FONT_SIZE, UiTheme.ACCENT)
	box.add_child(_code)

	_detail = _line(DETAIL_FONT_SIZE, UiTheme.TEXT_MUTED)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(DETAIL_MAX_WIDTH, 0.0)
	box.add_child(_detail)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	box.add_child(row)

	var menu_button := Button.new()
	menu_button.text = "Back to Menu"
	menu_button.pressed.connect(func() -> void: menu_requested.emit())
	row.add_child(menu_button)

	var quit_button := Button.new()
	quit_button.text = "Quit"
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	row.add_child(quit_button)

	hide()


## A centred label at `size` in `color` — the one label shape the screen reuses for its three lines.
func _line(size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


## Fills the screen for `code` — its headline and badge — and `detail` (the specific what/where),
## then raises it. The driver halts the failed match before calling this, so the screen sits still.
func show_error(code: int, detail: String) -> void:
	_title.text = ErrorCode.title(code)
	_code.text = "Error %s" % ErrorCode.label(code)
	_detail.text = detail
	show()
