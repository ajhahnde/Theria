class_name MatchChat
extends Control
## The in-match chat box, bottom-left: a short scrollback of recent lines over an input
## field, with an all / team scope toggle, in the genre-standard corner. Pure presentation
## on the shared `UiTheme` palette, like the other code-built overlays.
##
## First pass is local only: a sent line is echoed straight into this client's own log and
## announced on `message_sent` — it does not yet travel to other players. Real all/team
## delivery is a v0.2 networking slice (the chat wire rides the same session as the snapshot
## stream); `message_sent` already carries the scope so that slice subscribes here without a
## rework. The input also gates the game keys: while the player is typing, `is_typing` is true
## and the driver suppresses ability casts, so a "q" in a message never fires Q.

## Fired when the player sends a line — `scope` is Scope.ALL/Scope.TEAM, `text` the message.
## The hook a later networking slice connects to deliver the line to the other clients.
signal message_sent(scope: int, text: String)

enum Scope { ALL, TEAM }

## How many lines the scrollback keeps; older lines drop off the top.
const MAX_LINES := 8
const WIDTH := 380.0
const MARGIN := 18.0
## Clears the input above the bottom HUD cluster so the two do not stack on the same row.
const BOTTOM_OFFSET := 150.0
const FONT_SIZE := 15

const ALL_COLOR := Color(0.88, 0.89, 0.90)
const TEAM_COLOR := Color(0.45, 0.78, 0.62)

var _scope: int = Scope.ALL
var _typing: bool = false
var _log: VBoxContainer
var _input: LineEdit
var _scope_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_left = MARGIN
	offset_bottom = -BOTTOM_OFFSET
	custom_minimum_size = Vector2(WIDTH, 0.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _build() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.custom_minimum_size = Vector2(WIDTH, 0.0)
	add_child(column)
	_log = VBoxContainer.new()
	_log.add_theme_constant_override("separation", 2)
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_log)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)
	_scope_button = Button.new()
	_scope_button.theme = UiTheme.make()
	_scope_button.custom_minimum_size = Vector2(72.0, 0.0)
	_scope_button.pressed.connect(toggle_scope)
	row.add_child(_scope_button)
	_input = LineEdit.new()
	_input.theme = UiTheme.make()
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.max_length = 120
	_input.visible = false
	_input.text_submitted.connect(_on_submitted)
	row.add_child(_input)
	_refresh_scope_button()


# --- State ------------------------------------------------------------------


## Whether the player is currently typing a message — read by the driver to suppress ability
## casts so the letters of a message never fire the QWER bar.
func is_typing() -> bool:
	return _typing


## Opens the input for typing and focuses it, so the next keystrokes land in the message rather
## than the game. Idempotent — opening while already open just keeps the caret.
func open() -> void:
	_typing = true
	_input.visible = true
	_input.grab_focus()


## Closes the input, drops focus, and clears any half-typed text, handing the keyboard back to
## the game. Called on send and on cancel.
func close() -> void:
	_typing = false
	_input.visible = false
	_input.text = ""
	_input.release_focus()


## Flips the send scope between all-chat and team-chat, updating the toggle label. The next
## sent line carries the new scope.
func toggle_scope() -> void:
	_scope = Scope.TEAM if _scope == Scope.ALL else Scope.ALL
	_refresh_scope_button()


# --- Input ------------------------------------------------------------------


## Opens chat on Enter when not already typing, and cancels on Escape while typing. Submitting
## a line is the LineEdit's own `text_submitted` (also Enter), so an open input never re-opens.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if _typing:
		if event.keycode == KEY_ESCAPE:
			close()
			accept_event()
	elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		open()
		accept_event()


## A submitted line: echo it into this client's own log and announce it, then close the input.
## A blank line just closes (the genre's "open, change your mind, hit enter" gesture).
func _on_submitted(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed != "":
		append_line("You", trimmed, _scope)
		message_sent.emit(_scope, trimmed)
	close()


# --- Log --------------------------------------------------------------------


## Appends a chat line to the scrollback, tagged by scope and tinted to match, trimming the
## oldest past the cap. Public so the later networking slice can drop remote players' lines in
## through the same path the local echo uses.
func append_line(speaker: String, text: String, scope: int) -> void:
	var label := Label.new()
	label.text = "[%s] %s: %s" % [_scope_tag(scope), speaker, text]
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", _scope_color(scope))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(WIDTH, 0.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.add_child(label)
	while _log.get_child_count() > MAX_LINES:
		var oldest := _log.get_child(0)
		_log.remove_child(oldest)
		oldest.queue_free()


func _refresh_scope_button() -> void:
	_scope_button.text = _scope_tag(_scope)
	_scope_button.add_theme_color_override("font_color", _scope_color(_scope))


func _scope_tag(scope: int) -> String:
	return "TEAM" if scope == Scope.TEAM else "ALL"


func _scope_color(scope: int) -> Color:
	return TEAM_COLOR if scope == Scope.TEAM else ALL_COLOR
