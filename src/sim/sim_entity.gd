class_name SimEntity
extends RefCounted
## A simulated actor (hero or bot) inside the authoritative world state.
##
## Plain data plus its tuning — no engine, render, or input coupling.

var id: int = 0
var team: int = 0
var position: Vector2 = Vector2.ZERO
var move_speed: float = 0.0


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
