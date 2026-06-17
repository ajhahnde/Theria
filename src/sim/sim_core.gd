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

## A hero's body radius for collision — how far its centre is kept from an obstacle's surface. One
## shared value for v1: the mobile non-creep units (heroes) collide as they move; lane creeps march
## uncollided so a wave is never jammed on its own forward tower, and structures never move. Read by
## `apply_movement` here and by the nav grid, so a routed path and the resolve agree.
const UNIT_RADIUS := 40.0

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
const CREEP_SPEED := 210.0

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

## How long a slain hero stays down before respawning at its spawn point, full health. A flat
## timer for now (8 s at the tick rate) — short enough that a death is a setback, not a sit-out;
## scaling it with match time is a later tuning pass. A dead hero is kept in the world (not
## erased like a creep) so its id, and this countdown, persist for the client's death screen.
const HERO_RESPAWN_TICKS := 8 * TICK_RATE

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


## Populates the arena's structures from the map — each team's four towers (two ringing the
## nexus, two forward down the lanes) plus its destructible nexus. Both teams' structures mirror
## across the map's y = x axis, so the match starts mirror-fair.
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
	entity.is_hero = true  # a hero from birth, so death downs-and-respawns it even before a kit
	entity.max_hp = HERO_HP
	entity.hp = HERO_HP
	entity.spawn_position = position  # where it returns after a death
	entity.attack_damage = HERO_DAMAGE
	entity.attack_range = HERO_RANGE
	entity.attack_cooldown_ticks = HERO_COOLDOWN_TICKS
	return _register(entity)


## Turns an already-spawned hero into an ability caster by equipping a kit from the
## catalog. The hero starts in human form with that form's resource pool full; the
## animal pool waits for the first transform. Kept separate from `add_hero` so a
## bare walking-skeleton hero — and the netcode that spawns one — is unchanged until
## a kit is equipped. A no-op for an unknown hero id or kit.
func equip_kit(hero_id: int, kit_id: String) -> void:
	var hero := state.get_entity(hero_id)
	if hero == null:
		return
	var kit_def := AbilityData.kit(kit_id)
	if kit_def.is_empty():
		return
	var res: Dictionary = kit_def["resource"]
	hero.is_hero = true
	hero.form = AbilitySpec.FORM_HUMAN
	hero.stance = kit_def.get("stance", AbilityData.STANCE_BRAWL)
	hero.kit_id = kit_id
	hero.kit = (kit_def["abilities"] as Dictionary).duplicate(true)
	hero.form_resource_max = PackedInt32Array(
		[res[AbilitySpec.FORM_HUMAN]["max"], res[AbilitySpec.FORM_ANIMAL]["max"]]
	)
	hero.form_resource_regen = PackedInt32Array(
		[res[AbilitySpec.FORM_HUMAN]["regen_ticks"], res[AbilitySpec.FORM_ANIMAL]["regen_ticks"]]
	)
	hero.resource_max = hero.form_resource_max[AbilitySpec.FORM_HUMAN]
	hero.resource_regen_ticks = hero.form_resource_regen[AbilitySpec.FORM_HUMAN]
	hero.resource = hero.resource_max
	hero.resource_regen_counter = 0
	hero.ability_cooldowns = {}


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


## Advances the world by exactly one tick: spawn waves, revive the dead, move the
## input-driven units, march the creeps, resolve combat, then deaths. `inputs` maps an
## entity id to its InputCommand; an entity with no command holds still. Pure: the
## result is a function of the prior state and `inputs` only (creep waves spawn
## off `state.tick`). Once a nexus has fallen the match is over and step no-ops.
func step(inputs: Dictionary) -> void:
	state.fx_events.clear()  # this tick's cast FX only — cleared even on a no-op tick
	state.hit_events.clear()  # this tick's damage numbers
	state.attack_events.clear()  # this tick's auto-attack strikes
	if state.is_match_over():
		return
	_step_spawning()
	_step_respawns()
	_step_movement(inputs)
	_step_creeps()
	_step_statuses()
	_step_abilities(inputs)
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
		apply_movement(entity, inputs.get(id, null))


## Advances one entity by a single tick of movement intent: the pure movement
## sub-step, with the diagonal-speed clamp and the bounds clamp. A `null` command
## holds the entity still. The authoritative `_step_movement` runs it over every
## entity; the client's prediction/replay runs it over its own hero alone — so the
## server and a predicting client move a unit by byte-identical math, which is what
## lets client-side reconciliation land exactly on the authoritative position.
static func apply_movement(entity: SimEntity, command: InputCommand) -> void:
	if entity.is_dead():
		return  # a downed hero holds where it fell — server and the client's prediction alike
	var move_dir := Vector2.ZERO
	if command != null:
		move_dir = command.move_dir
	if move_dir.length() > 1.0:
		move_dir = move_dir.normalized()
	var from := entity.position
	entity.position += move_dir * entity.current_move_speed() * TICK_DELTA
	entity.position = MapData.clamp_to_bounds(entity.position)
	# Resolve a moving unit out of the solid obstacles, keeping the tangential slide along them. The
	# gate is the same "mobile, non-creep" predicate the client identifies its hero by (main.gd
	# `_local_hero`), so the decoded snapshot the client predicts on — which carries no is_hero flag —
	# runs byte-identical math to the server and reconciliation lands exactly. Lane creeps march
	# uncollided (so a wave never jams on its own forward tower) and a still unit is never shoved off
	# its spot — collision resolves movement, not placement.
	if move_dir != Vector2.ZERO and not entity.is_structure and not entity.is_creep:
		entity.position = MapData.slide(from, entity.position, UNIT_RADIUS)


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
## each lane is its own reflection across the y = x axis, the two teams' waves
## mirror across that axis.
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
		if creep.is_stunned():
			continue  # a stunned creep holds its ground — no march this tick
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


## Ages every active status by one tick and applies a venom DOT's bite. For each
## entity carrying a status: a DOT advances its interval counter and, on each interval,
## subtracts its damage; every status counts its duration down and is dropped when it
## expires. A SLOW and a STUN do nothing here — the movement, cast, and combat steps read
## the live status off the entity each tick — they only age out. Runs before the cast step
## (upkeep first, like resource
## regen) so a status applied this tick begins aging next tick, and before
## `_resolve_deaths` so a lethal DOT, an auto-attack, and an ability all reconcile in
## the one death pass. Pure and insertion-ordered over entities and each entity's
## statuses, so it replays identically.
func _step_statuses() -> void:
	for id in state.entities:
		var entity: SimEntity = state.entities[id]
		if entity.statuses.is_empty():
			continue
		var expired: Array[int] = []
		for kind in entity.statuses:
			var s: Dictionary = entity.statuses[kind]
			if kind == AbilitySpec.STATUS_DOT:
				s["counter"] += 1
				if s["counter"] >= s["interval"]:
					s["counter"] = 0
					entity.hp -= s["power"]
					_record_damage(entity, s["power"])
			s["remaining"] -= 1
			if s["remaining"] <= 0:
				expired.append(kind)
		for kind in expired:
			entity.statuses.erase(kind)


## Advances the ability layer one tick. First every hero's passive upkeep —
## resource regen and cooldown decay — which runs regardless of input so pools refill
## and cooldowns elapse while idle. Then any casts requested this tick: a cast is
## gated through AbilityExecutor.can_cast (form, resource, cooldown) and, on success,
## applied and its cost booked. Runs before `_step_combat` so an ability and an
## auto-attack that both finish a unit this tick are reconciled in one death pass.
## Pure and insertion-ordered like the rest of the step.
func _step_abilities(inputs: Dictionary) -> void:
	for id in state.entities:
		var hero: SimEntity = state.entities[id]
		if not hero.is_hero or hero.is_dead():
			continue  # a dead hero neither regens nor decays cooldowns until it respawns
		_regen_resource(hero)
		_tick_cooldowns(hero)
	for id in inputs:
		var command: InputCommand = inputs[id]
		if command == null or command.ability_slot < 0:
			continue
		var hero: SimEntity = state.get_entity(id)
		if hero != null and hero.is_hero and not hero.is_dead():
			_try_cast(hero, command)


## Restores one resource point once `resource_regen_ticks` ticks have elapsed,
## capped at the form's max. Integer regen on a tick interval keeps the pool
## deterministic; a form with no regen (or a full pool) is left alone.
func _regen_resource(hero: SimEntity) -> void:
	if hero.resource_regen_ticks <= 0 or hero.resource >= hero.resource_max:
		return
	hero.resource_regen_counter += 1
	if hero.resource_regen_counter >= hero.resource_regen_ticks:
		hero.resource_regen_counter = 0
		hero.resource = mini(hero.resource + 1, hero.resource_max)


## Ticks every live ability cooldown down by one. Keyed by ability id, so a cooldown
## set in one form keeps elapsing while the hero is in the other.
func _tick_cooldowns(hero: SimEntity) -> void:
	for ability_id in hero.ability_cooldowns:
		var remaining: int = hero.ability_cooldowns[ability_id]
		if remaining > 0:
			hero.ability_cooldowns[ability_id] = remaining - 1


## Resolves the requested slot to an ability of the hero's active form and casts it
## if it is castable. An empty slot, an off-form slot, or a failed gate is a no-op.
func _try_cast(hero: SimEntity, command: InputCommand) -> void:
	var slots: Dictionary = hero.kit.get(hero.form, {})
	var ability_id: int = slots.get(command.ability_slot, 0)
	if ability_id == 0 or not AbilityData.has_ability(ability_id):
		return
	var spec := AbilityData.spec(ability_id)
	if AbilityExecutor.can_cast(hero, spec):
		AbilityExecutor.execute(state, hero, spec, command)


## Every attacker ticks its cooldown down; when it hits 0 and an enemy is in
## range, it strikes the nearest one and the cooldown resets. Damage is applied
## to the shared entity in deterministic insertion order, so two attackers can
## both land on a target this tick and it dies once, in `_resolve_deaths`.
func _step_combat() -> void:
	for id in state.entities:
		var attacker: SimEntity = state.entities[id]
		if attacker.attack_damage <= 0:
			continue
		if attacker.is_dead():
			continue  # a downed hero stops fighting until it respawns
		if attacker.is_stunned():
			continue  # a locked unit neither strikes nor ticks its cooldown down
		if attacker.cooldown > 0:
			attacker.cooldown -= 1
		if attacker.cooldown > 0:
			continue
		var target := _nearest_enemy_in_range(attacker)
		if target == null:
			continue
		target.hp -= attacker.attack_damage
		attacker.cooldown = attacker.attack_cooldown_ticks
		_record_attack_fx(attacker, target)


## Records an auto-attack for the renderer: a strike from `attacker` to `target`, flagged
## ranged (the renderer flies a projectile) or melee (a close-in impact), plus the damage
## number over the target. A structure or a kiting hero fires; everything else — creeps and
## brawler heroes — hits melee.
func _record_attack_fx(attacker: SimEntity, target: SimEntity) -> void:
	var ranged := (
		attacker.is_structure
		or (attacker.is_hero and attacker.stance == AbilityData.STANCE_KITE)
	)
	state.attack_events.append(
		{"origin": attacker.position, "target": target.position, "ranged": ranged}
	)
	_record_damage(target, attacker.attack_damage)


## Notes `amount` of damage on a struck entity for the floating-number renderer. A pure
## presentation hint — like `fx_events`, it never feeds the sim or crosses the wire.
func _record_damage(entity: SimEntity, amount: int) -> void:
	state.hit_events.append({"position": entity.position, "amount": amount})


func _nearest_enemy_in_range(attacker: SimEntity) -> SimEntity:
	var nearest: SimEntity = null
	var nearest_dist := INF
	for id in state.entities:
		var other: SimEntity = state.entities[id]
		if other.team == attacker.team:
			continue
		if other.max_hp <= 0 or other.is_dead():
			continue  # non-combat entities and downed heroes are not valid targets
		var dist := attacker.position.distance_to(other.position)
		if dist <= attacker.attack_range and dist < nearest_dist:
			nearest_dist = dist
			nearest = other
	return nearest


## Reconciles every unit brought to 0 hp this tick. A creep or a structure is erased (a
## felled nexus first deciding the match); a hero is kept in the world but downed —
## marked dead and put on the respawn clock — so its id, position, and countdown persist
## for the client's death screen and `_step_respawns` can revive it in place. A hero
## already counting down is skipped, so it is downed once, not re-killed every tick.
func _resolve_deaths() -> void:
	var dead: Array[int] = []
	for id in state.entities:
		var entity: SimEntity = state.entities[id]
		if entity.max_hp > 0 and entity.hp <= 0 and not entity.is_dead():
			dead.append(id)
	for id in dead:
		var entity: SimEntity = state.entities[id]
		if entity.is_hero:
			_down_hero(entity)
			continue
		if entity.is_nexus and not state.is_match_over():
			state.winner = 1 - entity.team
		state.entities.erase(id)


## Puts a slain hero on the respawn clock instead of erasing it: hp pinned to 0, the
## respawn timer started, and any lingering statuses and auto-attack cooldown cleared so
## nothing carries over the death. `is_dead` now reads true, which makes every acting and
## targeting step skip it until `_step_respawns` revives it.
func _down_hero(hero: SimEntity) -> void:
	hero.hp = 0
	hero.respawn_ticks = HERO_RESPAWN_TICKS
	hero.statuses.clear()
	hero.cooldown = 0


## Counts every downed hero's respawn timer down by one tick and revives the hero the tick
## it elapses. Runs near the top of the step so a hero that comes back this tick is alive for
## the rest of it. Pure and insertion-ordered like every other step.
func _step_respawns() -> void:
	for id in state.entities:
		var hero: SimEntity = state.entities[id]
		if not hero.is_dead():
			continue
		hero.respawn_ticks -= 1
		if hero.respawn_ticks <= 0:
			_respawn_hero(hero)


## Revives a hero at its spawn point with a full health bar, back in human form with a full
## resource pool and every cooldown cleared — a clean slate, as if freshly seated. `respawn_ticks`
## lands at 0, so `is_dead` reads false and the hero acts again from this tick. A hero with no kit
## (the bare walking skeleton) has empty resource tuning, so the pool simply stays 0.
func _respawn_hero(hero: SimEntity) -> void:
	hero.respawn_ticks = 0
	hero.position = hero.spawn_position
	hero.hp = hero.max_hp
	hero.cooldown = 0
	hero.statuses.clear()
	hero.ability_cooldowns.clear()
	hero.form = AbilitySpec.FORM_HUMAN
	hero.resource_max = hero.form_resource_max[AbilitySpec.FORM_HUMAN]
	hero.resource_regen_ticks = hero.form_resource_regen[AbilitySpec.FORM_HUMAN]
	hero.resource = hero.resource_max
	hero.resource_regen_counter = 0
