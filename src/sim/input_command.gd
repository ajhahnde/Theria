class_name InputCommand
extends RefCounted
## A single tick of intent for one entity.
##
## The simulation consumes these. Nothing here touches rendering or the engine
## input system, so the same command type is produced by the local player, a
## bot, or — later — the network layer.

## Desired movement direction. Components are expected in [-1, 1]; the
## simulation clamps the magnitude to 1 so diagonal input is not faster.
var move_dir: Vector2 = Vector2.ZERO

## Ability cast intent for this tick. `ability_slot` is the bar slot to cast (0..3
## of the active form's kit), or -1 for no cast. `target_point` aims a skillshot or
## ground ability (a world position); `target_id` locks a unit-targeted one (an
## entity id). The fields the chosen ability does not use are ignored. Only
## `move_dir` is carried over the wire today; ability intent is consumed locally
## (v0.1 is local-only), so adding it here does not reshape the netcode protocol.
var ability_slot: int = -1
var target_point: Vector2 = Vector2.ZERO
var target_id: int = 0
