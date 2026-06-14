extends Node2D
## Thin presentation + input driver for the v0.1 walking skeleton.
##
## It owns a SimCore and advances it one tick per physics frame (physics is
## pinned to the simulation's 60 Hz in project.godot). All authority lives in
## the simulation; this layer only samples local input, asks the bot for its
## command, and draws the resulting state — the static map geometry plus the
## live entities. Swapping this for a networked driver later does not touch the
## simulation.

const HERO_SPEED := 320.0
const BOT_SPEED := 300.0
const HERO_TEAM := 0
const BOT_TEAM := 1

const HERO_COLOR := Color(0.36, 0.66, 1.0)
const BOT_COLOR := Color(1.0, 0.42, 0.38)
const ENTITY_RADIUS := 44.0

## Map debug-draw styling. World-unit sizes, tuned to read at the camera's
## zoomed-out framing of the whole arena.
const FIELD_COLOR := Color(0.114, 0.125, 0.145)
const BOUNDS_COLOR := Color(0.3, 0.32, 0.36)
const BOUNDS_WIDTH := 8.0
const LANE_COLOR := Color(0.5, 0.5, 0.55, 0.7)
const LANE_WIDTH := 28.0
const CAMP_COLOR := Color(0.45, 0.7, 0.45)
const CAMP_RADIUS := 60.0
const NEXUS_SIZE := Vector2(140.0, 140.0)

var _sim := SimCore.new()
var _bot := BotController.new()
var _hero_id: int = 0
var _bot_id: int = 0


func _ready() -> void:
	_hero_id = _sim.add_entity(HERO_TEAM, MapData.spawn_for_team(HERO_TEAM), HERO_SPEED)
	_bot_id = _sim.add_entity(BOT_TEAM, MapData.spawn_for_team(BOT_TEAM), BOT_SPEED)
	queue_redraw()


func _physics_process(_delta: float) -> void:
	var inputs := {
		_hero_id: _sample_player_input(),
		_bot_id: _bot.decide(_sim.state, _bot_id),
	}
	_sim.step(inputs)
	queue_redraw()


func _draw() -> void:
	_draw_map()
	_draw_entities()


func _draw_map() -> void:
	draw_rect(MapData.BOUNDS, FIELD_COLOR, true)
	draw_rect(MapData.BOUNDS, BOUNDS_COLOR, false, BOUNDS_WIDTH)
	for lane in MapData.lane_count():
		draw_polyline(MapData.lane_path(lane, HERO_TEAM), LANE_COLOR, LANE_WIDTH)
	for camp in MapData.JUNGLE_CAMPS:
		draw_circle(camp, CAMP_RADIUS, CAMP_COLOR)
	for team in MapData.NEXUS_POSITIONS.size():
		var centre := MapData.nexus_for_team(team)
		var rect := Rect2(centre - NEXUS_SIZE * 0.5, NEXUS_SIZE)
		draw_rect(rect, _team_color(team), true)


func _draw_entities() -> void:
	for id in _sim.state.entities:
		var entity: SimEntity = _sim.state.entities[id]
		draw_circle(entity.position, ENTITY_RADIUS, _team_color(entity.team))


func _team_color(team: int) -> Color:
	return HERO_COLOR if team == HERO_TEAM else BOT_COLOR


func _sample_player_input() -> InputCommand:
	var command := InputCommand.new()
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	command.move_dir = dir
	return command
