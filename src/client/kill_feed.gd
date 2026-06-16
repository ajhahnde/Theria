class_name KillFeed
extends VBoxContainer
## The top-right kill feed: a short stack of recent takedown lines, newest on top, each
## fading out after a few seconds so the feed stays a glance, not a wall. Pure presentation —
## the driver decides a kill happened and calls `push`; this owns only the on-screen list and
## its expiry, like the other code-built client overlays, on the shared `UiTheme` palette.
##
## First pass shows the victim alone ("X was slain"), because the simulation records no killer
## today — `_resolve_deaths` only zeroes hp and starts the respawn timer. Attributing the kill
## ("X slew Y") is a later sim slice (record the dealer of the lethal blow, and carry it on the
## wire for a networked feed); the `push` signature already takes the full line so that slice is
## a driver change, not a rework here.

## How many lines stay on screen at once; older lines drop off the bottom as new ones arrive.
const MAX_ENTRIES := 5
## How long (seconds) a line lingers before it removes itself.
const LIFETIME := 6.0
const FONT_SIZE := 16
const MARGIN := 16.0
## Where the feed sits below the top-right settings button, so the two do not overlap.
const TOP_OFFSET := 70.0

## Which heroes were down last tick (id -> true), so `observe` fires one line on the
## alive -> down edge rather than every tick a hero stays dead.
var _down_last_tick: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_top = TOP_OFFSET
	offset_right = -MARGIN
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Adds a takedown line, newest at the top, trimming the oldest past the cap and scheduling
## the line to fade itself out after LIFETIME. `color` tints the line (the victim's team) so a
## glance reads which side fell. Safe before the node is in a tree — the timer is only armed
## once it is, so a headless or pre-ready caller just gets the label without an expiry.
func push(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	move_child(label, 0)
	while get_child_count() > MAX_ENTRIES:
		# remove_child drops the count synchronously (queue_free alone does not), so detach the
		# oldest first to bound the loop, then free the now-orphaned line.
		var oldest := get_child(get_child_count() - 1)
		remove_child(oldest)
		oldest.queue_free()
	_expire(label)


## Scans the state for heroes that went down this tick — the alive -> down edge against last
## tick's record — and posts one feed line each, tinted by the team's colour (`team_colors`
## indexed by team id). `ally_team` only picks the Ally/Enemy fallback name when a hero's kit is
## unknown (a pure CLIENT hero). First pass names the victim alone; the killer is unknown until
## the sim attributes the lethal blow. Owns the death-edge tracking so the driver just hands it
## the state each tick.
func observe(state: SimState, ally_team: int, team_colors: Array) -> void:
	var down_now: Dictionary = {}
	for id in state.entities:
		var entity: SimEntity = state.entities[id]
		if not entity.is_hero:
			continue
		var down := entity.is_dead()
		down_now[id] = down
		if down and not _down_last_tick.get(id, false):
			push("%s was slain" % _victim_name(entity, ally_team), team_colors[entity.team])
	_down_last_tick = down_now


## A downed hero's name for the feed: its kit, capitalised, or an Ally/Enemy fallback when the
## kit is unknown (not carried on the wire for a pure CLIENT hero).
func _victim_name(hero: SimEntity, ally_team: int) -> String:
	if hero.kit_id != "":
		return hero.kit_id.capitalize()
	return "Ally" if hero.team == ally_team else "Enemy"


## Arms a line to remove itself after LIFETIME. A scene-tree timer needs the node in a tree;
## outside one (a unit test that never adds the feed) the line simply persists, which is all a
## push assertion needs.
func _expire(label: Label) -> void:
	if not is_inside_tree():
		return
	var timer := get_tree().create_timer(LIFETIME)
	timer.timeout.connect(func() -> void: _remove(label))


func _remove(label: Label) -> void:
	if is_instance_valid(label):
		label.queue_free()
