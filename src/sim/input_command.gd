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
