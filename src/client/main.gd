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
const HERO_HP := 600
const BOT_HP := 600
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
const TOWER_SIZE := Vector2(110.0, 110.0)
const NEXUS_SIZE := Vector2(200.0, 200.0)

## HP bar, drawn above any entity that carries health.
const HP_BAR_SIZE := Vector2(160.0, 26.0)
const HP_BAR_OFFSET := Vector2(-80.0, -150.0)
const HP_BAR_BG := Color(0.0, 0.0, 0.0, 0.6)
const HP_BAR_FG := Color(0.4, 0.85, 0.4)

var _sim := SimCore.new()
var _bot := BotController.new()
var _hero_id: int = 0
var _bot_id: int = 0


func _ready() -> void:
	_sim.spawn_structures()
	_hero_id = _sim.add_entity(HERO_TEAM, MapData.spawn_for_team(HERO_TEAM), HERO_SPEED, HERO_HP)
	_bot_id = _sim.add_entity(BOT_TEAM, MapData.spawn_for_team(BOT_TEAM), BOT_SPEED, BOT_HP)
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


## Draws the live world: towers and nexuses as squares, mobile units as circles,
## each with an HP bar. Structures and units share one entity list, so they all
## come straight from the authoritative state.
func _draw_entities() -> void:
	for id in _sim.state.entities:
		var entity: SimEntity = _sim.state.entities[id]
		if entity.is_structure:
			var size := NEXUS_SIZE if entity.is_nexus else TOWER_SIZE
			draw_rect(Rect2(entity.position - size * 0.5, size), _team_color(entity.team), true)
		else:
			draw_circle(entity.position, ENTITY_RADIUS, _team_color(entity.team))
		_draw_hp_bar(entity)


func _draw_hp_bar(entity: SimEntity) -> void:
	if entity.max_hp <= 0:
		return
	var frac := clampf(float(entity.hp) / float(entity.max_hp), 0.0, 1.0)
	var top_left := entity.position + HP_BAR_OFFSET
	draw_rect(Rect2(top_left, HP_BAR_SIZE), HP_BAR_BG, true)
	draw_rect(Rect2(top_left, Vector2(HP_BAR_SIZE.x * frac, HP_BAR_SIZE.y)), HP_BAR_FG, true)


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
