extends GutTest
## The N3 remote-entity interpolation invariants, exercised without any networking.
##
## SnapshotInterpolator buffers authoritative snapshots stamped with their arrival
## time and renders remote entities a delay in the past, interpolating between the
## two snapshots that bracket the render time. These tests pin the buffer and the
## sampling math: the linear blend at the midpoint, the no-extrapolation clamps at
## both ends, spawn/death handling, duplicate-tick rejection, and the buffer cap —
## all pure, so the round trip is checked headlessly like the protocol and sim cores.


func test_an_empty_buffer_samples_to_null() -> void:
	var interp := SnapshotInterpolator.new()
	assert_false(interp.has_data(), "a fresh interpolator holds nothing")
	assert_null(interp.sample(0.0), "with no snapshots there is nothing to render")


func test_a_lone_snapshot_is_returned_as_is() -> void:
	var interp := SnapshotInterpolator.new()
	interp.push(_state(1, {7: Vector2(100.0, 200.0)}), 0.0)
	# With only one snapshot there is no pair to blend, so any render time yields it.
	var sampled := interp.sample(-50.0)
	assert_eq(sampled.get_entity(7).position, Vector2(100.0, 200.0))


func test_midpoint_render_time_lerps_position_halfway() -> void:
	var interp := SnapshotInterpolator.new()
	interp.push(_state(1, {7: Vector2(0.0, 0.0)}), 0.0)
	interp.push(_state(2, {7: Vector2(100.0, 40.0)}), 100.0)
	# Render exactly between the two arrival times -> alpha 0.5 -> the midpoint.
	var sampled := interp.sample(50.0)
	assert_eq(sampled.get_entity(7).position, Vector2(50.0, 20.0))


func test_a_render_time_before_the_oldest_clamps_to_it() -> void:
	var interp := SnapshotInterpolator.new()
	interp.push(_state(1, {7: Vector2(0.0, 0.0)}), 100.0)
	interp.push(_state(2, {7: Vector2(100.0, 0.0)}), 200.0)
	# Earlier than anything buffered: clamp to the oldest, never extrapolate backwards.
	var sampled := interp.sample(0.0)
	assert_eq(sampled.get_entity(7).position, Vector2(0.0, 0.0))


func test_a_render_time_past_the_newest_clamps_to_it() -> void:
	var interp := SnapshotInterpolator.new()
	interp.push(_state(1, {7: Vector2(0.0, 0.0)}), 0.0)
	interp.push(_state(2, {7: Vector2(100.0, 0.0)}), 100.0)
	# Later than anything buffered: clamp to the newest. Remote entities are never
	# extrapolated ahead — guessing their future only snaps back when truth arrives.
	var sampled := interp.sample(500.0)
	assert_eq(sampled.get_entity(7).position, Vector2(100.0, 0.0))


func test_a_repeated_or_stale_tick_is_ignored() -> void:
	var interp := SnapshotInterpolator.new()
	interp.push(_state(2, {7: Vector2(0.0, 0.0)}), 0.0)
	interp.push(_state(2, {7: Vector2(999.0, 0.0)}), 100.0)  # same tick -> dropped
	interp.push(_state(1, {7: Vector2(888.0, 0.0)}), 200.0)  # older tick -> dropped
	# Only the first snapshot was kept, so sampling still returns its position.
	assert_eq(interp.sample(150.0).get_entity(7).position, Vector2(0.0, 0.0))


func test_an_entity_that_spawned_after_appears_at_its_own_position() -> void:
	var interp := SnapshotInterpolator.new()
	interp.push(_state(1, {7: Vector2(0.0, 0.0)}), 0.0)
	interp.push(_state(2, {7: Vector2(10.0, 0.0), 9: Vector2(60.0, 0.0)}), 100.0)
	# Entity 9 exists only in the newer snapshot -> nothing to lerp from, so it
	# renders at its newer position rather than being blended toward the origin.
	var sampled := interp.sample(50.0)
	assert_not_null(sampled.get_entity(9), "the newly spawned entity is present")
	assert_eq(sampled.get_entity(9).position, Vector2(60.0, 0.0))


func test_an_entity_that_died_before_the_newer_snapshot_is_dropped() -> void:
	var interp := SnapshotInterpolator.new()
	interp.push(_state(1, {7: Vector2(0.0, 0.0), 9: Vector2(60.0, 0.0)}), 0.0)
	interp.push(_state(2, {7: Vector2(10.0, 0.0)}), 100.0)
	# Entity 9 is gone in the newer snapshot, so the render (targeting the newer
	# one) omits it — a dead unit disappears, it does not linger interpolating.
	var sampled := interp.sample(50.0)
	assert_null(sampled.get_entity(9), "the entity absent from the newer snapshot is dropped")


func test_non_position_fields_come_from_the_newer_snapshot() -> void:
	var interp := SnapshotInterpolator.new()
	var older := _state(1, {7: Vector2(0.0, 0.0)})
	older.get_entity(7).hp = 100
	var newer := _state(2, {7: Vector2(100.0, 0.0)})
	newer.get_entity(7).hp = 40
	interp.push(older, 0.0)
	interp.push(newer, 100.0)
	# Position blends, but hp (and every other field) is the fresher truth, not a blend.
	var sampled := interp.sample(50.0)
	assert_eq(sampled.get_entity(7).position, Vector2(50.0, 0.0), "position is blended")
	assert_eq(sampled.get_entity(7).hp, 40, "hp is taken whole from the newer snapshot")


func test_the_buffer_is_capped_to_its_limit() -> void:
	var interp := SnapshotInterpolator.new()
	var count := SnapshotInterpolator.BUFFER_LIMIT + 5
	for tick in range(1, count + 1):
		interp.push(_state(tick, {7: Vector2(float(tick), 0.0)}), float(tick))
	# The oldest snapshots are evicted, so a render time before the surviving window
	# clamps to the oldest retained snapshot, not the long-discarded tick 1.
	var oldest_kept := float(count - SnapshotInterpolator.BUFFER_LIMIT + 1)
	assert_eq(interp.sample(0.0).get_entity(7).position, Vector2(oldest_kept, 0.0))


# --- adaptive render delay --------------------------------------------------


func test_delay_floors_at_min_on_even_arrivals() -> void:
	var interp := SnapshotInterpolator.new()
	# Snapshots arriving evenly at the 60 Hz interval carry almost no jitter, so the
	# delay sits on its floor rather than buffering latency it does not need.
	_push_arrivals(interp, _repeat(16.0, 10))
	assert_almost_eq(interp.target_delay_ms(), SnapshotInterpolator.MIN_DELAY_MS, 0.001)


func test_delay_attacks_to_cover_a_large_gap() -> void:
	var interp := SnapshotInterpolator.new()
	# A single late snapshot opens a 200 ms gap; the delay snaps up at once to cover
	# it (worst gap + margin), so the next late packet is already absorbed.
	_push_arrivals(interp, [16.0, 16.0, 16.0, 200.0])
	var expected := 200.0 + SnapshotInterpolator.GAP_MARGIN_MS
	assert_almost_eq(interp.target_delay_ms(), expected, 0.001)


func test_delay_caps_at_max() -> void:
	var interp := SnapshotInterpolator.new()
	# A pathological gap must not buy unbounded latency — the delay clamps to the cap.
	_push_arrivals(interp, [16.0, 16.0, 1000.0])
	assert_almost_eq(interp.target_delay_ms(), SnapshotInterpolator.MAX_DELAY_MS, 0.001)


func test_delay_releases_slowly_after_jitter_subsides() -> void:
	var interp := SnapshotInterpolator.new()
	# A 200 ms gap drives the delay to its peak; once even arrivals resume the gap
	# leaves the recent window and the delay eases back down — gradually, not snapping
	# to the floor (which would warp remote-unit motion), but well below the peak.
	var peak := 200.0 + SnapshotInterpolator.GAP_MARGIN_MS  # the delay right after the gap
	var intervals := [16.0, 16.0, 200.0]
	intervals.append_array(_repeat(16.0, 20))
	_push_arrivals(interp, intervals)
	assert_lt(interp.target_delay_ms(), peak, "the delay relaxes once jitter subsides")
	assert_gt(
		interp.target_delay_ms(),
		SnapshotInterpolator.MIN_DELAY_MS,
		"but eases down slowly rather than snapping to the floor",
	)


# --- helpers ----------------------------------------------------------------


## Pushes a stream of snapshots whose inter-arrival times are `intervals`
## (milliseconds). The first arrives at time 0; time and tick advance per interval.
func _push_arrivals(interp: SnapshotInterpolator, intervals: Array) -> void:
	var time := 0.0
	var tick := 1
	interp.push(_state(tick, {7: Vector2(float(tick), 0.0)}), time)
	for dt: float in intervals:
		time += dt
		tick += 1
		interp.push(_state(tick, {7: Vector2(float(tick), 0.0)}), time)


## An array of `value` repeated `count` times.
func _repeat(value: float, count: int) -> Array:
	var out: Array = []
	for _i in count:
		out.append(value)
	return out


## A snapshot at `tick` whose entities are the given `id -> position` pairs.
func _state(tick: int, positions: Dictionary) -> SimState:
	var state := SimState.new()
	state.tick = tick
	for id in positions:
		state.add_entity(SimEntity.new(id, 1, positions[id], 0.0))
	return state
