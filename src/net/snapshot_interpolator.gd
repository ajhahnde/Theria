class_name SnapshotInterpolator
extends RefCounted
## Client-side smoothing for remote entities.
##
## A client receives the authoritative world as a stream of snapshots that arrive
## with jitter and the occasional loss (snapshots travel unreliably). Drawing the
## newest one each frame makes remote units stutter and snap. This buffers the last
## few snapshots and renders remote entities a fixed delay in the *past*,
## interpolating between the two snapshots that bracket the render time — so a late
## or dropped snapshot is covered by the ones around it instead of stalling a unit.
##
## It never extrapolates: a render time past the newest snapshot clamps to it
## rather than guessing ahead. Remote entities carry no local input, so guessing
## their future would only snap back when the truth arrives — interpolation in the
## past is the right tool, and prediction is reserved for the client's own hero
## (which `main.gd` overlays on top of the interpolated world). Authority is never
## forked: every position here is derived from the server's snapshots alone.
##
## How far in the past to render is **adaptive** (`target_delay_ms`): it tracks the
## worst recent gap between snapshot arrivals, so a clean connection pays little
## latency while a jittery one buffers enough to ride out its hiccups. The delay
## snaps up to cover a new worst gap and eases back down slowly, and is clamped to a
## sane band, so it tracks the live connection without warping remote-unit motion.
##
## Pure and engine-free — it takes arrival and render times as plain milliseconds
## rather than reading a clock, so the whole buffer/sample round trip is unit-tested
## headlessly, like the simulation and protocol cores.

## How many recent snapshots to retain. At the 60 Hz snapshot rate this spans
## ~530 ms — comfortably more than MAX_DELAY_MS, so even at the largest adaptive
## delay the render time falls between two buffered snapshots rather than clamping
## to the oldest one.
const BUFFER_LIMIT := 32

## Adaptive render-delay bounds, in milliseconds. The delay tracks the observed
## snapshot jitter so a clean connection pays little latency while a jittery one
## buffers enough to ride out its worst gap. Floored so even a perfect line keeps a
## small cushion (≈3 snapshots), capped so a pathological connection never adds
## unbounded latency.
const MIN_DELAY_MS := 50.0
const MAX_DELAY_MS := 250.0

## Headroom added over the worst recent arrival gap — ≈2 snapshots at 60 Hz — so the
## render time stays behind the newest snapshot through one further late packet.
const GAP_MARGIN_MS := 33.0

## How many of the most recent arrival gaps the delay is sized against. A bad gap is
## remembered for this many snapshots and then forgotten, decoupling how long jitter
## influences the delay from how much history the buffer keeps for sampling.
const GAP_WINDOW := 8

## How fast the delay relaxes once jitter subsides. It snaps up at once to cover a
## new worst gap (fast attack) but eases down by this fraction per snapshot (slow
## release), so a single hiccup does not make the delay itself jitter and warp the
## apparent speed of remote units.
const DELAY_RELEASE := 0.05

## Buffered snapshots, oldest first, each `{time: float, state: SimState}` where
## `time` is the arrival time in milliseconds. Kept ascending in both arrival time
## and tick by `push`.
var _buffer: Array[Dictionary] = []

## The current adaptive render delay in milliseconds, updated as snapshots arrive.
var _delay_estimate_ms := MIN_DELAY_MS


## Records a freshly received snapshot, stamped with its arrival time in
## milliseconds. Snapshots whose tick is not newer than the latest buffered one are
## ignored, so feeding the most recent snapshot every frame is safe — each distinct
## snapshot is buffered exactly once, and a reordered or duplicate one is dropped.
func push(state: SimState, recv_msec: float) -> void:
	if state == null:
		return
	if not _buffer.is_empty() and state.tick <= _buffer[-1]["state"].tick:
		return
	_buffer.append({"time": recv_msec, "state": state})
	if _buffer.size() > BUFFER_LIMIT:
		_buffer.pop_front()
	_update_delay_estimate()


func has_data() -> bool:
	return not _buffer.is_empty()


## The render delay the client should currently apply: remote entities are drawn
## this many milliseconds in the past. It adapts to observed snapshot jitter
## (clamped to [MIN_DELAY_MS, MAX_DELAY_MS]) so the smoothing tracks the live
## connection instead of a fixed guess.
func target_delay_ms() -> float:
	return _delay_estimate_ms


## Resizes the adaptive delay to cover the worst arrival gap over the recent window,
## plus a margin, clamped to the delay band. Snaps up at once to cover a worse gap
## (so the next late packet is already absorbed) and eases down slowly otherwise (so
## the delay itself stays steady). A no-op until two snapshots give a first gap.
func _update_delay_estimate() -> void:
	if _buffer.size() < 2:
		return
	var target := clampf(_max_recent_gap() + GAP_MARGIN_MS, MIN_DELAY_MS, MAX_DELAY_MS)
	if target >= _delay_estimate_ms:
		_delay_estimate_ms = target
	else:
		_delay_estimate_ms += (target - _delay_estimate_ms) * DELAY_RELEASE


## The widest interval between consecutive arrivals over the last GAP_WINDOW gaps —
## the worst recent hiccup the delay must stay ahead of.
func _max_recent_gap() -> float:
	var widest := 0.0
	var start: int = maxi(1, _buffer.size() - GAP_WINDOW)
	for i in range(start, _buffer.size()):
		var gap: float = _buffer[i]["time"] - _buffer[i - 1]["time"]
		if gap > widest:
			widest = gap
	return widest


## The interpolated world at `render_msec`: the two buffered snapshots that bracket
## that time, with each entity present in both lerped between them. Returns null
## before any snapshot arrives, and the lone snapshot when only one is held. A
## render time outside the buffered span clamps to the nearest end — it never
## extrapolates past the newest snapshot.
func sample(render_msec: float) -> SimState:
	if _buffer.is_empty():
		return null
	if _buffer.size() == 1:
		return _buffer[0]["state"]
	if render_msec <= _buffer[0]["time"]:
		return _buffer[0]["state"]
	if render_msec >= _buffer[-1]["time"]:
		return _buffer[-1]["state"]
	var i := 0
	while i < _buffer.size() - 1 and _buffer[i + 1]["time"] <= render_msec:
		i += 1
	var before: Dictionary = _buffer[i]
	var after: Dictionary = _buffer[i + 1]
	var span: float = after["time"] - before["time"]
	var alpha := 0.0 if span <= 0.0 else clampf((render_msec - before["time"]) / span, 0.0, 1.0)
	return _interpolate(before["state"], after["state"], alpha)


## Builds a render state between two snapshots. The newer snapshot `after` is the
## target: iterating its entities makes a unit that has spawned appear and one that
## has died drop at the newer snapshot's moment. An entity also present in `before`
## has its position lerped; every other field, and any entity new in `after`, comes
## straight from `after` (the fresher truth). The buffered snapshots are never
## mutated — each render entity is a clone.
static func _interpolate(before: SimState, after: SimState, alpha: float) -> SimState:
	var out := SimState.new()
	out.tick = after.tick
	out.winner = after.winner
	for id in after.entities:
		var target: SimEntity = after.entities[id]
		var entity := target.clone()
		var prior: SimEntity = before.entities.get(id, null)
		if prior != null:
			entity.position = prior.position.lerp(target.position, alpha)
		out.add_entity(entity)
	return out
