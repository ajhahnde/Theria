extends GutTest
## The N5 network-condition simulator, exercised without any networking.
##
## NetSim shapes the client's incoming snapshot stream — holding each snapshot a
## base latency plus random jitter, dropping a loss fraction — so the smoothing can
## be exercised under a worse link than the local machine provides. These tests pin
## its contract: identity pass-through, the latency hold, the seeded loss rate,
## the jitter band, release ordering, and that a not-yet-due snapshot stays queued.
## It conditions opaque payloads and takes plain millisecond times, so the whole
## round trip is checked headlessly like the protocol, sim, and interpolation cores.


func test_identity_releases_immediately() -> void:
	# No latency, jitter, or loss: a snapshot is due the instant it arrives.
	var sim := NetSim.new(0.0, 0.0, 0.0, 1)
	assert_true(sim.receive("a", 100.0), "an unconditioned snapshot is always accepted")
	var due := sim.drain(100.0)
	assert_eq(due.size(), 1, "the snapshot is released at its arrival time")
	assert_eq(due[0]["data"], "a")
	assert_eq(due[0]["release"], 100.0)
	assert_false(sim.has_pending(), "nothing is left queued")


func test_latency_holds_until_due() -> void:
	var sim := NetSim.new(50.0, 0.0, 0.0, 1)
	sim.receive("a", 100.0)
	assert_eq(sim.drain(149.0).size(), 0, "before arrival + latency the snapshot is held")
	assert_true(sim.has_pending(), "and stays queued")
	var due := sim.drain(150.0)
	assert_eq(due.size(), 1, "at arrival + latency it is released")
	assert_eq(due[0]["release"], 150.0)


func test_loss_drops_at_its_rate_and_drops_stay_gone() -> void:
	# Seeded, so the drop pattern is fixed: at 50% loss over 1000 arrivals the
	# delivered count sits near 500, and a dropped snapshot is never released later.
	var sim := NetSim.new(0.0, 0.0, 0.5, 12345)
	var accepted := 0
	for i in range(1000):
		if sim.receive(i, float(i)):
			accepted += 1
	assert_between(accepted, 440, 560, "roughly half the snapshots survive the loss roll")
	assert_eq(sim.drain(2000.0).size(), accepted, "only the accepted snapshots are ever released")


func test_jitter_spreads_release_within_the_band() -> void:
	# Every snapshot shares one arrival time, so their spread comes purely from jitter:
	# each is held the base latency plus a random [0, jitter), never outside that band.
	var sim := NetSim.new(100.0, 40.0, 0.0, 7)
	for i in range(50):
		sim.receive(i, 0.0)
	var due := sim.drain(1000.0)
	assert_eq(due.size(), 50, "no loss, so all are released once due")
	var lowest := INF
	var highest := -INF
	for packet in due:
		lowest = minf(lowest, packet["release"])
		highest = maxf(highest, packet["release"])
	assert_gte(lowest, 100.0, "never released before the base latency")
	assert_lt(highest, 140.0, "never held beyond latency + jitter")
	assert_gt(highest - lowest, 0.0, "jitter actually spreads the release times")


func test_drain_returns_due_in_release_order() -> void:
	# Released oldest-first regardless of the order they were offered, so the
	# downstream buffer sees them in arrival order.
	var sim := NetSim.new(0.0, 0.0, 0.0, 1)
	sim.receive("c", 30.0)
	sim.receive("a", 10.0)
	sim.receive("b", 20.0)
	var order: Array = []
	for packet in sim.drain(100.0):
		order.append(packet["data"])
	assert_eq(order, ["a", "b", "c"], "drained in ascending release time, not offer order")


func test_a_not_yet_due_snapshot_waits_for_a_later_drain() -> void:
	var sim := NetSim.new(0.0, 0.0, 0.0, 1)
	sim.receive("a", 10.0)
	sim.receive("b", 30.0)
	assert_eq(sim.drain(20.0).size(), 1, "only the snapshot already due is released")
	assert_eq(sim.drain(20.0).size(), 0, "the released one is not handed out twice")
	var later := sim.drain(40.0)
	assert_eq(later.size(), 1, "the held snapshot is released once its time comes")
	assert_eq(later[0]["data"], "b")
