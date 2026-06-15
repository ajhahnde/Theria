class_name SimEntity
extends RefCounted
## A simulated actor — a mobile unit (hero, bot) or a static structure (tower,
## nexus) — inside the authoritative world state.
##
## Plain data plus its tuning — no engine, render, or input coupling. The combat
## fields are the shared primitive: a tower attacks with them now, and creeps and
## heroes reuse the same fields when those layers land.

var id: int = 0
var team: int = 0
var position: Vector2 = Vector2.ZERO
var move_speed: float = 0.0

## Health. An entity is damageable and killable only when `max_hp > 0`; pure
## movers (the v0.1 walking-skeleton entities) leave it at 0 and ignore combat.
var hp: int = 0
var max_hp: int = 0

## Attack tuning. An entity attacks only when `attack_damage > 0`: each time its
## `cooldown` reaches 0 it deals `attack_damage` to the nearest enemy within
## `attack_range`, then resets `cooldown` to `attack_cooldown_ticks`. Integer
## damage and a tick-counted cooldown keep combat deterministic.
var attack_damage: int = 0
var attack_range: float = 0.0
var attack_cooldown_ticks: int = 0
var cooldown: int = 0

## A structure is static (takes no movement input) and renders as a building.
## The nexus is the win anchor: destroying it ends the match for the other team.
var is_structure: bool = false
var is_nexus: bool = false

## A creep is an AI-driven mobile unit that marches a lane and fights on contact.
## It takes no player input: `lane` selects which corridor it walks and
## `waypoint_index` is the index of the lane waypoint it is currently heading
## for, advancing as it arrives until it reaches the enemy nexus.
var is_creep: bool = false
var lane: int = 0
var waypoint_index: int = 0

## A hero is the player/bot unit that, on top of the shared auto-attack, casts
## abilities. The ability layer is inert until `is_hero` is set and a kit equipped
## (see SimCore.equip_kit); a hero with no kit just auto-attacks like before.
var is_hero: bool = false

## The active shapeshifter form (AbilitySpec.FORM_HUMAN / FORM_ANIMAL). Only the
## abilities of the active form are castable; a TRANSFORM ability flips it.
var form: int = 0

## How a bot positions this hero (AbilityData.STANCE_*), set from the kit at equip.
## BRAWL (the default) closes to land a hit and shifts toward whichever form reaches;
## KITE holds the kit's ranged poke and keeps an enemy at arm's length. Ignored for a
## player-driven hero, which positions itself — a player hero just leaves it at BRAWL.
var stance: int = 0

## The current form's resource pool: `resource` spent to cast (gated against
## `resource_max`), refilled by one point every `resource_regen_ticks` ticks
## (0 = no regen), counted by `resource_regen_counter`. The two forms keep separate
## pools — `form_resource_max[form]` / `form_resource_regen[form]` hold each form's
## tuning, and a transform swaps the active values to the destination form's.
var resource: int = 0
var resource_max: int = 0
var resource_regen_ticks: int = 0
var resource_regen_counter: int = 0
var form_resource_max: PackedInt32Array = PackedInt32Array([0, 0])
var form_resource_regen: PackedInt32Array = PackedInt32Array([0, 0])

## Remaining cooldown in ticks per ability id (absent/0 = ready). Keyed by ability
## id rather than slot, so a cooldown set in one form is still ticking when the hero
## transforms back to it.
var ability_cooldowns: Dictionary = {}

## The hero's bar, by form: `kit[form][slot]` is the ability id in that slot, or
## absent for an empty slot. Set once when the kit is equipped; the catalog holds
## the immutable specs the ids resolve to.
var kit: Dictionary = {}

## Active status effects (venom DOT, web SLOW) left on this entity by abilities that
## struck it, keyed by status kind (AbilitySpec.STATUS_*) so there is one instance per
## kind — a re-application refreshes it. Each value holds `power`, `remaining` ticks,
## the DOT `interval`, and its `counter`. Empty for every entity carrying no status
## (towers, creeps, an unharmed hero), so the status layer is inert until something is
## laid on. SimCore.`_step_statuses` ages and ticks these; insertion order keeps the
## pass deterministic.
var statuses: Dictionary = {}


func _init(
	p_id: int = 0,
	p_team: int = 0,
	p_pos: Vector2 = Vector2.ZERO,
	p_speed: float = 0.0,
) -> void:
	id = p_id
	team = p_team
	position = p_pos
	move_speed = p_speed


## Returns a field-for-field copy of this entity. The client's snapshot
## interpolation uses it to build a render entity at an in-between position without
## mutating the buffered authoritative snapshots it derives from.
func clone() -> SimEntity:
	var copy := SimEntity.new(id, team, position, move_speed)
	copy.hp = hp
	copy.max_hp = max_hp
	copy.attack_damage = attack_damage
	copy.attack_range = attack_range
	copy.attack_cooldown_ticks = attack_cooldown_ticks
	copy.cooldown = cooldown
	copy.is_structure = is_structure
	copy.is_nexus = is_nexus
	copy.is_creep = is_creep
	copy.lane = lane
	copy.waypoint_index = waypoint_index
	copy.is_hero = is_hero
	copy.form = form
	copy.stance = stance
	copy.resource = resource
	copy.resource_max = resource_max
	copy.resource_regen_ticks = resource_regen_ticks
	copy.resource_regen_counter = resource_regen_counter
	copy.form_resource_max = form_resource_max.duplicate()
	copy.form_resource_regen = form_resource_regen.duplicate()
	copy.ability_cooldowns = ability_cooldowns.duplicate()
	copy.kit = kit.duplicate(true)
	copy.statuses = statuses.duplicate(true)
	return copy


## This entity's move speed after any active slow. A SLOW status scales the base speed
## by (100 - its percent); with none, the base speed is returned unchanged — so a
## status-free entity (every entity on the wire, every Solane unit) moves by exactly
## the same math as before. The authoritative movement step and the client's local
## prediction both read it, so a slowed hero is predicted identically.
func current_move_speed() -> float:
	var slow: Dictionary = statuses.get(AbilitySpec.STATUS_SLOW, {})
	if slow.is_empty():
		return move_speed
	var pct := clampi(slow["power"], 0, 100)
	return move_speed * float(100 - pct) / 100.0
