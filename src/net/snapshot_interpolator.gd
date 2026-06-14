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
## Pure and engine-free — it takes arrival and render times as plain milliseconds
## rather than reading a clock, so the whole buffer/sample round trip is unit-tested
## headlessly, like the simulation and protocol cores.

## How many recent snapshots to retain. At the 60 Hz snapshot rate this spans
## ~200 ms, comfortably more than any sane interpolation delay needs to bracket.
const BUFFER_LIMIT := 12

## Buffered snapshots, oldest first, each `{time: float, state: SimState}` where
## `time` is the arrival time in milliseconds. Kept ascending in both arrival time
## and tick by `push`.
var _buffer: Array[Dictionary] = []


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


func has_data() -> bool:
	return not _buffer.is_empty()


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
