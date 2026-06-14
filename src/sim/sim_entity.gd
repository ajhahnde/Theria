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
	return copy
