extends Node2D
## Thin presentation + input driver for the v0.1 walking skeleton.
##
## It owns a SimCore and advances it one tick per physics frame (physics is
## pinned to the simulation's 60 Hz in project.godot). All authority lives in
## the simulation; this layer only samples local input, asks the bot for its
## command, and draws the resulting state. Swapping this for a networked driver
## later does not touch the simulation.

const HERO_SPEED := 320.0
const BOT_SPEED := 300.0
const HERO_TEAM := 0
const BOT_TEAM := 1
const MARKER_SIZE := Vector2(28.0, 28.0)
const HERO_COLOR := Color(0.36, 0.66, 1.0)
const BOT_COLOR := Color(1.0, 0.42, 0.38)

var _sim := SimCore.new()
var _bot := BotController.new()
var _hero_id: int = 0
var _bot_id: int = 0
var _markers: Dictionary = {}


func _ready() -> void:
	_hero_id = _sim.add_entity(HERO_TEAM, MapData.spawn_for_team(HERO_TEAM), HERO_SPEED)
	_bot_id = _sim.add_entity(BOT_TEAM, MapData.spawn_for_team(BOT_TEAM), BOT_SPEED)
	_markers[_hero_id] = _make_marker(HERO_COLOR)
	_markers[_bot_id] = _make_marker(BOT_COLOR)
	_sync_markers()


func _physics_process(_delta: float) -> void:
	var inputs := {
		_hero_id: _sample_player_input(),
		_bot_id: _bot.decide(_sim.state, _bot_id),
	}
	_sim.step(inputs)
	_sync_markers()


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


func _make_marker(color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.size = MARKER_SIZE
	add_child(rect)
	return rect


func _sync_markers() -> void:
	for id in _markers:
		var entity: SimEntity = _sim.state.get_entity(id)
		var marker: ColorRect = _markers[id]
		marker.position = entity.position - MARKER_SIZE * 0.5
