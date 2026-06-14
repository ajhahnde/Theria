class_name BotController
extends RefCounted
## Produces an InputCommand for a bot-controlled entity from the world state.
##
## v0.1 skeleton behaviour: walk toward the nearest enemy and stop on contact.
## Deterministic — a pure function of the state — so a bot match replays
## identically and feeds the same simulation core as a human would.

## Stop advancing once within this many world units of the target.
const STOP_RANGE := 60.0


func decide(state: SimState, bot_id: int) -> InputCommand:
	var command := InputCommand.new()
	var bot := state.get_entity(bot_id)
	if bot == null:
		return command
	var target := _nearest_enemy(state, bot)
	if target == null:
		return command
	var offset := target.position - bot.position
	if offset.length() > STOP_RANGE:
		command.move_dir = offset.normalized()
	return command


func _nearest_enemy(state: SimState, bot: SimEntity) -> SimEntity:
	var nearest: SimEntity = null
	var nearest_dist := INF
	for id in state.entities:
		var other: SimEntity = state.entities[id]
		if other.team == bot.team:
			continue
		var dist := bot.position.distance_to(other.position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = other
	return nearest
