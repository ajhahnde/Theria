class_name NetSim
extends RefCounted
## A client-side network-condition simulator for the snapshot stream.
##
## The listen-server's snapshots reach a client over the local machine or a clean
## LAN with almost no latency, jitter, or loss — so the smoothing that exists to
## ride out a bad connection (interpolation and its adaptive delay) is never
## actually exercised in a playtest. This shapes the received snapshot stream as if
## it had crossed a worse link: it holds each snapshot for a base `latency` plus a
## random `jitter`, and drops a `loss` fraction outright. The result is irregular
## arrival gaps and holes the rest of the netcode then has to absorb, so the
## adaptive interpolation delay can be *seen* growing and the interpolation can be
## seen covering dropped snapshots.
##
## It conditions opaque payloads (it never inspects the snapshot) and takes arrival
## and release times as plain milliseconds rather than reading a clock, so — like
## the simulation, protocol, and interpolation cores — it is pure and unit-tested
## headlessly. Its randomness is seeded, so a given seed yields the same drop and
## jitter pattern every run, which keeps the tests deterministic and a playtest
## reproducible.
##
## It lives on the client's snapshot intake only: it shapes nothing the server
## sends out and changes no wire bytes, so PROTOCOL_VERSION is unaffected. The
## whole stream — what interpolation buffers and what prediction reconciles against
## alike — passes through it, so a simulated bad link degrades the client honestly
## rather than only cosmetically.

## Base hold applied to every accepted snapshot, in milliseconds: its release time
## is at least this far past its arrival.
var _latency_ms: float

## Extra random hold on top of `_latency_ms`, in milliseconds: each snapshot is
## held an additional uniform `[0, _jitter_ms)`. This is what makes consecutive
## arrival gaps irregular, which is what the adaptive delay responds to.
var _jitter_ms: float

## Fraction of snapshots dropped on arrival, in `[0, 1]` — a dropped snapshot is
## never queued and never released, leaving a hole the interpolation must cover.
var _loss: float

## Seeded so the drop and jitter pattern is reproducible: deterministic for the
## tests and repeatable in a playtest.
var _rng := RandomNumberGenerator.new()

## Snapshots accepted but not yet due, each `{release: float, data: Variant}` where
## `release` is the arrival time plus the hold. Not kept sorted; `drain` orders the
## packets it releases.
var _pending: Array[Dictionary] = []


func _init(latency_ms: float, jitter_ms: float, loss: float, rng_seed: int) -> void:
	_latency_ms = maxf(0.0, latency_ms)
	_jitter_ms = maxf(0.0, jitter_ms)
	_loss = clampf(loss, 0.0, 1.0)
	_rng.seed = rng_seed


## Offers a freshly received snapshot, stamped with its arrival time in
## milliseconds. Returns false if the loss roll drops it (it is discarded), or true
## if it was queued to be released later at `arrival + latency + random jitter`.
func receive(data: Variant, recv_msec: float) -> bool:
	if _rng.randf() < _loss:
		return false
	var release := recv_msec + _latency_ms + _rng.randf() * _jitter_ms
	_pending.append({"release": release, "data": data})
	return true


## Releases every queued snapshot whose hold has elapsed by `now_msec`, oldest
## release first, and removes them from the queue. Each returned entry is
## `{release: float, data: Variant}`; the caller stamps the downstream buffer with
## `release` so the injected latency and jitter show up as real arrival timing.
## Jitter can reorder releases relative to arrival; the snapshot buffer downstream
## already drops a stale tick, so an overtaken snapshot is handled there.
func drain(now_msec: float) -> Array:
	var due: Array = []
	var kept: Array[Dictionary] = []
	for packet in _pending:
		if packet["release"] <= now_msec:
			due.append(packet)
		else:
			kept.append(packet)
	_pending = kept
	due.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["release"] < b["release"])
	return due


## Whether any snapshot is held back waiting for its release time.
func has_pending() -> bool:
	return not _pending.is_empty()
