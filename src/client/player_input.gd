class_name PlayerInput
extends RefCounted
## Samples the local player's intent into an `InputCommand` each tick and owns the order state
## behind it: right-click to move, right-click an enemy to attack it, and Q·W·E·R to cast aimed
## at the cursor. Engine input and the camera ground-ray live here; given the world the player
## acts on it returns the same per-tick `move_dir` + ability intent the simulation consumes, so
## the presenter just hands over context and takes back a command. Pure presentation-side —
## authority stays in the sim. Lifted out of `main.gd` to keep that file under the line cap.

## Ability bar keys, one per slot (0..3) — QWER, the MOBA-standard bind. Movement is
## click-to-move (right mouse), so the letter row is free. A held key recasts as soon as the
## slot's cooldown and resource allow (quick-cast).
const ABILITY_KEYS: Array[Key] = [KEY_Q, KEY_W, KEY_E, KEY_R]

## How close (world units) a right-click must land to an enemy's body to read as "attack this
## one" rather than "walk here" — its footprint plus a little slop.
const ENEMY_PICK_RADIUS := 90.0

## The standing click-to-move destination (a sim point); `has_move_target` gates it. Read by
## the presenter to draw the destination marker.
var move_target: Vector2 = Vector2.ZERO
var has_move_target: bool = false
## Right-clicking an enemy sets this to its id: the hero closes on it and the combat step
## strikes it (LoL-style attack-on-click). 0 means the last order was a plain ground move.
var attack_target_id: int = 0

var _camera: Camera3D = null


func _init(camera: Camera3D) -> void:
	_camera = camera


## This tick's command. `state` is the world the player acts on and `hero` their own hero (null
## before one spawns); `team` is their team. `cast_abilities` is true only with a local
## authoritative sim (LOCAL/HOST) — a pure CLIENT casts nothing yet, as the wire carries
## movement alone.
func sample(state: SimState, hero: SimEntity, team: int, cast_abilities: bool) -> InputCommand:
	var command := InputCommand.new()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_issue_order(state, team, _mouse_world_point())
	command.move_dir = _move_dir(hero, state)
	if cast_abilities:
		_sample_ability(command, state, team)
	return command


## Resolves a right-click into an order: clicking on an enemy attacks it (the hero closes to
## attack range, then the combat step strikes it), clicking open ground walks there. One button
## both moves and engages — lighter than LoL's separate attack-move key.
func _issue_order(state: SimState, team: int, point: Vector2) -> void:
	var enemy := _enemy_under(state, team, point)
	if enemy != 0:
		attack_target_id = enemy
		has_move_target = false
	else:
		attack_target_id = 0
		move_target = point
		has_move_target = true


## This tick's movement direction: closing on the attack target when one is set, else the
## click-to-move toward the standing ground target, else still.
func _move_dir(hero: SimEntity, state: SimState) -> Vector2:
	if attack_target_id != 0:
		return _chase_dir(hero, state)
	if not has_move_target or hero == null:
		return Vector2.ZERO
	# Unit vector toward the target while far; within a single tick's reach, a sub-unit vector
	# that lands the hero exactly on it (apply_movement scales a move_dir under length 1 down),
	# so it stops on the point rather than overshooting. Then the target is cleared.
	var to_target := move_target - hero.position
	var step := hero.current_move_speed() * SimCore.TICK_DELTA
	if step <= 0.0 or to_target.length() <= step:
		has_move_target = false
		return to_target / step if step > 0.0 else Vector2.ZERO
	return to_target.normalized()


## Movement toward the attack target: close until the hero is inside its own attack range —
## then hold, and the combat step auto-strikes it as the nearest enemy — and drop the order
## once the target dies or leaves the world.
func _chase_dir(hero: SimEntity, state: SimState) -> Vector2:
	var target := _target_enemy(state)
	if hero == null or target == null:
		attack_target_id = 0
		return Vector2.ZERO
	var to_target := target.position - hero.position
	var reach := hero.attack_range if hero.attack_range > 0.0 else SimCore.HERO_RANGE
	if to_target.length() <= reach:
		return Vector2.ZERO
	return to_target.normalized()


## The id of an enemy under `point` (within a click's slop of its body), or 0 for open ground —
## what tells an attack order from a move order. Uses the same nearest-enemy pick the sim does.
func _enemy_under(state: SimState, team: int, point: Vector2) -> int:
	if state == null:
		return 0
	var id := AbilityExecutor.pick_unit_target(state, team, point)
	var enemy := state.get_entity(id)
	if enemy != null and enemy.position.distance_to(point) <= ENEMY_PICK_RADIUS:
		return id
	return 0


## The live attack-target enemy, or null once it is dead or gone.
func _target_enemy(state: SimState) -> SimEntity:
	var enemy := state.get_entity(attack_target_id) if state != null else null
	return enemy if enemy != null and enemy.hp > 0 else null


## Layers ability-cast intent onto the command. The pressed slot keys the cast; the cursor is
## the aim point a skillshot or ground ability uses, and the enemy nearest it is the lock a
## unit-targeted one uses — the sim reads whichever the cast ability needs.
func _sample_ability(command: InputCommand, state: SimState, team: int) -> void:
	var slot := _pressed_ability_slot()
	if slot < 0 or state == null:
		return
	var aim := _mouse_world_point()
	command.ability_slot = slot
	command.target_point = aim
	command.target_id = AbilityExecutor.pick_unit_target(state, team, aim)


## The bar slot of the first held ability key (0..3), or -1 if none is down.
func _pressed_ability_slot() -> int:
	for slot in ABILITY_KEYS.size():
		if Input.is_physical_key_pressed(ABILITY_KEYS[slot]):
			return slot
	return -1


## The point on the 2D field under the mouse: a ray from the camera through the cursor,
## intersected with the ground plane (y = 0), returned in sim space — the move/attack click
## point and the cast aim.
func _mouse_world_point() -> Vector2:
	if _camera == null:
		return Vector2.ZERO
	var mouse := _camera.get_viewport().get_mouse_position()
	var origin := _camera.project_ray_origin(mouse)
	var dir := _camera.project_ray_normal(mouse)
	if absf(dir.y) < 0.0001:
		return Vector2(origin.x, origin.z)
	var hit := origin + dir * (-origin.y / dir.y)
	return Vector2(hit.x, hit.z)
