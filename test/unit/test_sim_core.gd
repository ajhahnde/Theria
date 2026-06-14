extends GutTest
## Deterministic checks on the authoritative simulation core. These run headless
## and stay free of any engine/render coupling — they exercise the exact step
## function the live client and (later) the netcode drive.


func test_constant_input_advances_position_deterministically() -> void:
	var sim := SimCore.new()
	var id := sim.add_entity(0, Vector2.ZERO, 300.0)
	var command := InputCommand.new()
	command.move_dir = Vector2.RIGHT
	var inputs := {id: command}
	for _i in SimCore.TICK_RATE:
		sim.step(inputs)
	var entity := sim.state.get_entity(id)
	# 60 ticks * (1/60 s) * 300 u/s = 300 units along +x.
	assert_almost_eq(entity.position.x, 300.0, 0.0001)
	assert_almost_eq(entity.position.y, 0.0, 0.0001)
	assert_eq(sim.state.tick, 60)


func test_identical_input_replays_identically() -> void:
	var a := _run_scripted(120)
	var b := _run_scripted(120)
	assert_eq(a, b, "the simulation must be a pure function of state + input")


func test_diagonal_input_is_not_faster() -> void:
	var sim := SimCore.new()
	var speed := 300.0
	var id := sim.add_entity(0, Vector2.ZERO, speed)
	var command := InputCommand.new()
	command.move_dir = Vector2.ONE  # length sqrt(2) -> must clamp to 1
	sim.step({id: command})
	var moved := sim.state.get_entity(id).position.length()
	assert_almost_eq(moved, speed * SimCore.TICK_DELTA, 0.0001)


func test_entity_without_command_holds_still() -> void:
	var sim := SimCore.new()
	var id := sim.add_entity(0, Vector2(10.0, -5.0), 300.0)
	sim.step({})
	assert_eq(sim.state.get_entity(id).position, Vector2(10.0, -5.0))


func _run_scripted(ticks: int) -> Vector2:
	var sim := SimCore.new()
	var id := sim.add_entity(0, Vector2.ZERO, 250.0)
	var command := InputCommand.new()
	for i in ticks:
		command.move_dir = Vector2(sin(float(i)), cos(float(i)))
		sim.step({id: command})
	return sim.state.get_entity(id).position
