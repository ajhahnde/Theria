class_name SimCore
extends RefCounted
## The server-authoritative simulation: a deterministic, side-effect-free,
## fixed-timestep step function.
##
## It owns its own clock (a constant tick delta) so the same core can be driven
## by the local game loop, a headless test, a bot, or — later — the network
## layer, and always advances identically for identical input. Keep it free of
## any rendering, engine-input, or global-state coupling.

const TICK_RATE := 60
const TICK_DELTA := 1.0 / TICK_RATE

var state: SimState = SimState.new()
var _next_id: int = 1


## Creates an entity, registers it in the world, and returns its id.
func add_entity(team: int, position: Vector2, move_speed: float) -> int:
	var id := _next_id
	_next_id += 1
	state.add_entity(SimEntity.new(id, team, position, move_speed))
	return id


## Advances the world by exactly one tick. `inputs` maps an entity id to its
## InputCommand; an entity with no command holds still. Pure: the result is a
## function of the prior state and `inputs` only.
func step(inputs: Dictionary) -> void:
	for id in state.entities:
		var entity: SimEntity = state.entities[id]
		var command: InputCommand = inputs.get(id, null)
		var move_dir := Vector2.ZERO
		if command != null:
			move_dir = command.move_dir
		if move_dir.length() > 1.0:
			move_dir = move_dir.normalized()
		entity.position += move_dir * entity.move_speed * TICK_DELTA
		entity.position = MapData.clamp_to_bounds(entity.position)
	state.tick += 1
