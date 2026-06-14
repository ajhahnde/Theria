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

## Creep tuning. A creep is a fragile melee unit — it dies in a few tower shots,
## but a wave pushing together trades, sieges, and (unopposed) fells a nexus.
const CREEP_HP := 100
const CREEP_DAMAGE := 20
const CREEP_RANGE := 150.0
const CREEP_COOLDOWN_TICKS := 30
const CREEP_SPEED := 180.0

## Wave cadence. Both teams spawn a wave per lane every interval, the first at
## tick 0. Creeps within a wave are strung along the lane so they file out of the
## base rather than stacking on one point.
const CREEP_WAVE_INTERVAL_TICKS := 600
const CREEP_PER_WAVE := 3
const CREEP_SPAWN_SPACING := 80.0

## How close (world units) a creep must come to its target waypoint before it
## switches to the next one — large enough to round a corner without stalling.
const WAYPOINT_ARRIVE_RADIUS := 40.0

## Hero tuning. A hero out-hits a creep and out-ranges one, so a player can clear
## a wave, pressure a tower, and duel the enemy hero — but a tower still out-ranges
## and out-hits a lone hero, so diving one undefended is punished.
const HERO_HP := 600
const HERO_DAMAGE := 60
const HERO_RANGE := 250.0
const HERO_COOLDOWN_TICKS := 36

var state: SimState = SimState.new()

## Whether `step` spawns creep waves on its own clock. On for live play and the
## integration tests; focused unit tests switch it off to stay isolated from the
## wave schedule and creep tuning.
var spawn_creeps: bool = true

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


## Creates a hero — a player- or bot-driven mobile unit that fights with the
## shared combat primitive (it auto-strikes the nearest enemy in range) — and
## returns its id. `move_speed` is set by the driver; combat is fixed tuning.
func add_hero(team: int, position: Vector2, move_speed: float) -> int:
	var entity := SimEntity.new(_next_id, team, position, move_speed)
	entity.max_hp = HERO_HP
	entity.hp = HERO_HP
	entity.attack_damage = HERO_DAMAGE
	entity.attack_range = HERO_RANGE
	entity.attack_cooldown_ticks = HERO_COOLDOWN_TICKS
	return _register(entity)


## Creates a lane creep at `position` and returns its id. The creep marches
## `lane` toward the enemy nexus and fights with the shared combat primitive.
func add_creep(team: int, lane: int, position: Vector2) -> int:
	var entity := SimEntity.new(_next_id, team, position, CREEP_SPEED)
	entity.max_hp = CREEP_HP
	entity.hp = CREEP_HP
	entity.attack_damage = CREEP_DAMAGE
	entity.attack_range = CREEP_RANGE
	entity.attack_cooldown_ticks = CREEP_COOLDOWN_TICKS
	entity.is_creep = true
	entity.lane = lane
	entity.waypoint_index = 1  # heading for the second waypoint; the first is the spawn nexus
	return _register(entity)


## Advances the world by exactly one tick: spawn waves, move the input-driven
## units, march the creeps, resolve combat, then deaths. `inputs` maps an entity
## id to its InputCommand; an entity with no command holds still. Pure: the
## result is a function of the prior state and `inputs` only (creep waves spawn
## off `state.tick`). Once a nexus has fallen the match is over and step no-ops.
func step(inputs: Dictionary) -> void:
	if state.is_match_over():
		return
	_step_spawning()
	_step_movement(inputs)
	_step_creeps()
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


## On a wave tick, spawns one creep wave per team per lane. Driven off
## `state.tick` so wave timing is part of the authoritative, replayable state.
func _step_spawning() -> void:
	if not spawn_creeps:
		return
	if state.tick % CREEP_WAVE_INTERVAL_TICKS != 0:
		return
	for team in MapData.NEXUS_POSITIONS.size():
		for lane in MapData.lane_count():
			_spawn_wave(team, lane)


## Spawns `CREEP_PER_WAVE` creeps for `team` on `lane`, strung forward along the
## first lane segment so they file out of the base instead of stacking. Because
## the lanes are point-symmetric, the two teams' waves mirror through the origin.
func _spawn_wave(team: int, lane: int) -> void:
	var path := MapData.lane_path(lane, team)
	var origin := path[0]
	var forward := Vector2.ZERO
	if path.size() > 1:
		forward = (path[1] - origin).normalized()
	for i in CREEP_PER_WAVE:
		add_creep(team, lane, origin + forward * (CREEP_SPAWN_SPACING * float(i + 1)))


## Marches every creep along its lane toward the enemy nexus. A creep holds
## position while any enemy is within its attack range (the combat step then
## strikes), otherwise it advances toward its current waypoint, switching to the
## next once it arrives. Movement is capped at the per-tick step so it never
## overshoots — deterministic and replayable like the rest of the core.
func _step_creeps() -> void:
	for id in state.entities:
		var creep: SimEntity = state.entities[id]
		if not creep.is_creep:
			continue
		if _nearest_enemy_in_range(creep) != null:
			continue
		var path := MapData.lane_path(creep.lane, creep.team)
		if creep.waypoint_index >= path.size():
			creep.waypoint_index = path.size() - 1
		var target := path[creep.waypoint_index]
		var to_target := target - creep.position
		var dist := to_target.length()
		var step_dist := creep.move_speed * TICK_DELTA
		if dist > 0.0:
			creep.position += to_target / dist * minf(step_dist, dist)
		if creep.position.distance_to(target) <= WAYPOINT_ARRIVE_RADIUS:
			if creep.waypoint_index < path.size() - 1:
				creep.waypoint_index += 1
		creep.position = MapData.clamp_to_bounds(creep.position)


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
