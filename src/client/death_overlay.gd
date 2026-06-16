class_name DeathOverlay
extends Control
## The full-screen death screen shown while the player's own hero is down, counting it
## back to respawn. Pure presentation: each tick the driver hands it the hero's remaining
## respawn ticks and it renders the dim and the countdown, or hides when the hero is alive.
## It owns no simulation and never decides when the hero is dead — `main.gd` reads that off
## the hero's `respawn_ticks` (sim-side in LOCAL/HOST, straight from the snapshot on a CLIENT)
## and drives this, exactly as the connect menu stays a pure entry point over the `_start_*`
## paths. A headless run never builds it (no display to draw to).

## A dim wash over the live world rather than an opaque cover: the match plays on behind the
## death screen — squadmates fight, the timer ticks — so the player watches it while waiting.
const DIM_COLOR := Color(0.0, 0.0, 0.0, 0.6)
const TITLE_TEXT := "YOU DIED"
const TITLE_COLOR := Color(0.85, 0.24, 0.22)
const TITLE_FONT_SIZE := 96
const TIMER_COLOR := Color(0.92, 0.93, 0.96)
const TIMER_FONT_SIZE := 52

var _timer_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The hero is down but the world plays on under the dim — never eat a click, so panning or
	# any other still-live input passes straight through to the game below.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = DIM_COLOR
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 28)
	center.add_child(box)

	var title := Label.new()
	title.text = TITLE_TEXT
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	box.add_child(title)

	_timer_label = Label.new()
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", TIMER_FONT_SIZE)
	_timer_label.add_theme_color_override("font_color", TIMER_COLOR)
	box.add_child(_timer_label)

	hide()


## Shows the death screen with the respawn countdown, or hides it when the hero is alive
## (0 ticks). The remaining ticks are rounded up to whole seconds so the timer counts the way
## a player reads it — "3… 2… 1…" — and reaches 0 on the tick the hero actually respawns.
func set_respawn(remaining_ticks: int, tick_rate: int) -> void:
	if remaining_ticks <= 0:
		hide()
		return
	var seconds := ceili(float(remaining_ticks) / float(tick_rate))
	_timer_label.text = "Respawning in %d" % seconds
	show()
