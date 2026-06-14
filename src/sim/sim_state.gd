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


func add_entity(entity: SimEntity) -> void:
	entities[entity.id] = entity


func get_entity(id: int) -> SimEntity:
	return entities.get(id, null)


func is_match_over() -> bool:
	return winner != -1
