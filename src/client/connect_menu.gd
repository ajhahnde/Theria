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
## The player chose a single-machine practice match.
signal practice_requested

## The address used when the player leaves the field blank. The driver injects its
## own default so the menu and the `--join` flag resolve to one value.
var default_address := "127.0.0.1"

var _address_field: LineEdit


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)

	var title := Label.new()
	title.text = "Ashmere"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var practice_button := Button.new()
	practice_button.text = "Practice (single machine)"
	practice_button.pressed.connect(_on_practice_pressed)
	box.add_child(practice_button)

	var host_button := Button.new()
	host_button.text = "Host a match"
	host_button.pressed.connect(_on_host_pressed)
	box.add_child(host_button)

	var join_row := HBoxContainer.new()
	box.add_child(join_row)

	_address_field = LineEdit.new()
	_address_field.placeholder_text = default_address
	_address_field.custom_minimum_size = Vector2(220, 0)
	join_row.add_child(_address_field)

	var join_button := Button.new()
	join_button.text = "Join"
	join_button.pressed.connect(_on_join_pressed)
	join_row.add_child(join_button)


func _on_practice_pressed() -> void:
	practice_requested.emit()


func _on_host_pressed() -> void:
	host_requested.emit()


## Resolves the typed address — falling back to `default_address` when blank — and
## emits `join_requested`. Trimmed so stray whitespace is not taken as a host name.
func _on_join_pressed() -> void:
	var address := _address_field.text.strip_edges()
	if address.is_empty():
		address = default_address
	join_requested.emit(address)
