class_name SimState
extends RefCounted
## The full authoritative world state at one tick.
##
## A pure data container: the simulation reads and advances it, nothing else.

## Monotonic simulation tick counter (starts at 0).
var tick: int = 0

## Entities keyed by their integer id. Insertion order is stable, which keeps
## iteration over the world deterministic.
var entities: Dictionary = {}

## The team that has won, or -1 while the match is ongoing. Set when a team's
## nexus is destroyed; once set, the simulation freezes (`step` no-ops).
var winner: int = -1

## Presentation-only record of the casts resolved this tick — one entry per cast, each
## carrying its origin, landing point, area radius, effect, target kind, and status, for
## the renderer to flash a skillshot line or an area zone. Cleared at the top of every
## `step` (so it never carries a stale cast) and never serialized onto the wire, so it
## stays a pure LOCAL/HOST render hint: a snapshot-fed CLIENT simply draws no cast FX,
## exactly as it shows no statuses. Read by the presenter, ignored by the simulation.
var fx_events: Array = []

## Presentation-only record of the damage dealt this tick — one entry per hp loss (an
## auto-attack, an ability hit, a venom tick), each `{position, amount}`, for the renderer to
## pop a floating damage number over the struck unit. Same lifecycle as `fx_events`: cleared
## at the top of every `step` and never serialized, so it stays a LOCAL/HOST render hint.
var hit_events: Array = []

## Presentation-only record of the auto-attacks that landed this tick — one entry per strike,
## each `{origin, target, ranged}`, so the renderer flies a projectile from a ranged attacker
## or flashes a close-in impact for a melee one. Same lifecycle as `fx_events`.
var attack_events: Array = []


func add_entity(entity: SimEntity) -> void:
	entities[entity.id] = entity


func get_entity(id: int) -> SimEntity:
	return entities.get(id, null)


func is_match_over() -> bool:
	return winner != -1
