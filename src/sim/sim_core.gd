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

## Tower combat tuning. A tower out-ranges and chips a unit that wanders into it,
## but takes many shots to kill — pressure, not an instant wall.
const TOWER_HP := 1000
const TOWER_DAMAGE := 50
const TOWER_RANGE := 500.0
const TOWER_COOLDOWN_TICKS := 60

## The nexus is a destructible structure with no attack of its own.
const NEXUS_HP := 2000

var state: SimState = SimState.new()
var _next_id: int = 1


## Creates a mobile entity, registers it in the world, and returns its id.
## `hp` of 0 (the default) leaves the entity outside the combat system — it
## cannot be targeted, damaged, or killed.
func add_entity(team: int, position: Vector2, move_speed: float, hp: int = 0) -> int:
	var entity := SimEntity.new(_next_id, team, position, move_speed)
	entity.max_hp = hp
	entity.hp = hp
	return _register(entity)


## Creates a static structure (a tower or nexus) and returns its id.
func add_structure(
	team: int,
	position: Vector2,
	hp: int,
	attack_damage: int,
	attack_range: float,
	attack_cooldown_ticks: int,
	is_nexus: bool = false,
) -> int:
	var entity := SimEntity.new(_next_id, team, position, 0.0)
	entity.max_hp = hp
	entity.hp = hp
	entity.attack_damage = attack_damage
	entity.attack_range = attack_range
	entity.attack_cooldown_ticks = attack_cooldown_ticks
	entity.is_structure = true
	entity.is_nexus = is_nexus
	return _register(entity)


## Populates the arena's structures from the map: each team's lane towers plus
## its destructible nexus. Both teams' structures mirror through the origin, so
## the match starts mirror-fair.
func spawn_structures() -> void:
	for team in MapData.NEXUS_POSITIONS.size():
		for slot in MapData.tower_positions(team):
			add_structure(team, slot, TOWER_HP, TOWER_DAMAGE, TOWER_RANGE, TOWER_COOLDOWN_TICKS)
		add_structure(team, MapData.nexus_for_team(team), NEXUS_HP, 0, 0.0, 0, true)


## Advances the world by exactly one tick: movement, then combat, then deaths.
## `inputs` maps an entity id to its InputCommand; an entity with no command
## holds still. Pure: the result is a function of the prior state and `inputs`
## only. Once a nexus has fallen the match is over and the step is a no-op.
func step(inputs: Dictionary) -> void:
	if state.is_match_over():
		return
	_step_movement(inputs)
	_step_combat()
	_resolve_deaths()
	state.tick += 1


func _register(entity: SimEntity) -> int:
	var id := _next_id
	_next_id += 1
	state.add_entity(entity)
	return id


func _step_movement(inputs: Dictionary) -> void:
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


## Every attacker ticks its cooldown down; when it hits 0 and an enemy is in
## range, it strikes the nearest one and the cooldown resets. Damage is applied
## to the shared entity in deterministic insertion order, so two attackers can
## both land on a target this tick and it dies once, in `_resolve_deaths`.
func _step_combat() -> void:
	for id in state.entities:
		var attacker: SimEntity = state.entities[id]
		if attacker.attack_damage <= 0:
			continue
		if attacker.cooldown > 0:
			attacker.cooldown -= 1
		if attacker.cooldown > 0:
			continue
		var target := _nearest_enemy_in_range(attacker)
		if target == null:
			continue
		target.hp -= attacker.attack_damage
		attacker.cooldown = attacker.attack_cooldown_ticks


func _nearest_enemy_in_range(attacker: SimEntity) -> SimEntity:
	var nearest: SimEntity = null
	var nearest_dist := INF
	for id in state.entities:
		var other: SimEntity = state.entities[id]
		if other.team == attacker.team:
			continue
		if other.max_hp <= 0:
			continue
		var dist := attacker.position.distance_to(other.position)
		if dist <= attacker.attack_range and dist < nearest_dist:
			nearest_dist = dist
			nearest = other
	return nearest


func _resolve_deaths() -> void:
	var dead: Array[int] = []
	for id in state.entities:
		var entity: SimEntity = state.entities[id]
		if entity.max_hp > 0 and entity.hp <= 0:
			dead.append(id)
	for id in dead:
		var entity: SimEntity = state.entities[id]
		if entity.is_nexus and not state.is_match_over():
			state.winner = 1 - entity.team
		state.entities.erase(id)
