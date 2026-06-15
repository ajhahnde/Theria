class_name MoveMarker
extends Node3D
## The click-to-move destination marker (LoL-style): a flat ring laid on the ground at the
## point the player last right-clicked, shown while the hero walks toward it and hidden once
## it arrives. It pulses so the destination reads at a glance. Pure presentation — driven by
## the client's move target each tick, never by the simulation or the wire.

## Ring footprint and how far it floats above the ground (a hair, to dodge z-fighting with
## the ground plane), then the pulse rate and how far the radius breathes.
const RADIUS := 48.0
const THICKNESS := 8.0
const LIFT := 4.0
const COLOR := Color(0.45, 1.0, 0.65)
const PULSE_HZ := 2.0
const PULSE_AMOUNT := 0.16

var _ring: MeshInstance3D = null
var _phase := 0.0


func _ready() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = RADIUS - THICKNESS
	torus.outer_radius = RADIUS
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOR
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring.material_override = mat
	add_child(_ring)
	visible = false


## Shows the marker at a field point (a sim `Vector2`, placed on the ground). Idempotent —
## the pulse runs on its own clock, so re-pointing each tick just tracks the live target.
func point_at(field_point: Vector2) -> void:
	position = Vector3(field_point.x, LIFT, field_point.y)
	visible = true


## Hides the marker — the hero has arrived (or has no destination).
func clear() -> void:
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_phase += delta * PULSE_HZ * TAU
	var s := 1.0 + sin(_phase) * PULSE_AMOUNT
	_ring.scale = Vector3(s, 1.0, s)
