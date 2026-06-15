class_name MatchFx
extends RefCounted
## Draws the brief visual for a cast the simulation resolved this tick, so an ability
## reads on screen instead of resolving invisibly. The sim records each cast on
## `SimState.fx_events` (origin, landing point, area radius, effect, target kind, status);
## the presenter drains that list every tick and hands each entry here. A skillshot or a
## unit cast flashes a beam from the caster to where it landed, a ground area flashes a
## disc at its true radius (so a zone like the Spider's stun nest reads its real size), and
## a self-cast pulses a ring on the caster. Every flash fades out and frees itself, so the
## field never accumulates nodes. Pure presentation — nothing here touches the simulation.

## How far above the ground the flashes sit, so they read over the lit plane rather than
## z-fighting it.
const FX_HEIGHT := 30.0

## Beam (skillshot / unit cast) — a thin bright bar from the caster to the landing point.
const BEAM_WIDTH := 16.0
const BEAM_ALPHA := 0.9
const BEAM_LIFETIME := 0.16

## Area (ground cast) — a translucent disc at the landing point, drawn at the ability's
## true radius so the zone's real footprint reads. Held a touch longer than a beam and
## kept see-through so what stands inside it stays visible.
const AREA_THICKNESS := 8.0
const AREA_ALPHA := 0.32
const AREA_LIFETIME := 0.45

## Pulse (self / heal / transform) — a ring on the caster that swells as it fades.
const PULSE_INNER := 60.0
const PULSE_OUTER := 78.0
const PULSE_ALPHA := 0.7
const PULSE_GROWTH := 2.1
const PULSE_LIFETIME := 0.3

## Flash colours. A status cast (stun / slow / poison) takes its status's colour — matching
## the floating status labels — so a control ability reads as control; otherwise the cast
## reads by effect: warm for damage, green for a heal, pale blue for a shapeshift.
const DAMAGE_COLOR := Color(1.0, 0.95, 0.82)
const HEAL_COLOR := Color(0.4, 1.0, 0.5)
const TRANSFORM_COLOR := Color(0.82, 0.85, 1.0)
const STUN_COLOR := Color(1.0, 0.9, 0.3)
const DOT_COLOR := Color(0.6, 1.0, 0.4)
const SLOW_COLOR := Color(0.55, 0.8, 1.0)


## Draws one cast's flash under `parent` (a node already in the tree, at the world origin),
## dispatched by its targeting kind. The event is one `SimState.fx_events` entry.
static func play(parent: Node3D, event: Dictionary) -> void:
	var color := _color(event)
	match event["kind"]:
		AbilitySpec.TARGET_SKILLSHOT, AbilitySpec.TARGET_UNIT:
			_beam(parent, event["origin"], event["point"], color)
		AbilitySpec.TARGET_GROUND:
			_disc(parent, event["point"], maxf(event["radius"], BEAM_WIDTH), color)
		_:
			_pulse(parent, event["origin"], color)


## A thin bar from `a` to `b` (sim positions) — the path of a skillshot or the line to a
## locked target. Centred on the midpoint and turned to face the landing point, so it spans
## exactly the cast's reach. A zero-length cast (caster on the point) draws nothing.
static func _beam(parent: Node3D, a: Vector2, b: Vector2, color: Color) -> void:
	var from := _world(a)
	var to := _world(b)
	var length := from.distance_to(to)
	if length <= 0.0:
		return
	var bar := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(BEAM_WIDTH, BEAM_WIDTH, length)
	bar.mesh = box
	var mat := _material(color, BEAM_ALPHA)
	bar.material_override = mat
	parent.add_child(bar)
	bar.global_position = from.lerp(to, 0.5)
	bar.look_at(to, Vector3.UP)
	_fade(parent, bar, mat, BEAM_LIFETIME)


## A flat translucent disc at `center`, drawn at `radius` — a ground area's real footprint.
static func _disc(parent: Node3D, center: Vector2, radius: float, color: Color) -> void:
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = AREA_THICKNESS
	disc.mesh = cyl
	var mat := _material(color, AREA_ALPHA)
	disc.material_override = mat
	parent.add_child(disc)
	disc.global_position = _world(center)
	_fade(parent, disc, mat, AREA_LIFETIME)


## A ring on the caster that swells outward as it fades — a self-cast (heal, shapeshift)
## has no reach to draw, so it marks the caster itself.
static func _pulse(parent: Node3D, at: Vector2, color: Color) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = PULSE_INNER
	torus.outer_radius = PULSE_OUTER
	ring.mesh = torus
	var mat := _material(color, PULSE_ALPHA)
	ring.material_override = mat
	parent.add_child(ring)
	ring.global_position = _world(at)
	var faded := mat.albedo_color
	faded.a = 0.0
	var tween := parent.create_tween()
	tween.set_parallel(true)
	tween.tween_property(mat, "albedo_color", faded, PULSE_LIFETIME)
	tween.tween_property(ring, "scale", Vector3.ONE * PULSE_GROWTH, PULSE_LIFETIME)
	tween.chain().tween_callback(ring.queue_free)


## Fades `node`'s flash to transparent over `lifetime`, then frees it — so a cast's mark
## lingers a beat and clears itself, and the field never piles up flash nodes.
static func _fade(parent: Node3D, node: Node3D, mat: StandardMaterial3D, lifetime: float) -> void:
	var faded := mat.albedo_color
	faded.a = 0.0
	var tween := parent.create_tween()
	tween.tween_property(mat, "albedo_color", faded, lifetime)
	tween.tween_callback(node.queue_free)


## The flash colour for a cast: its status's colour when it carries one, else its effect's.
static func _color(event: Dictionary) -> Color:
	match event["status"]:
		AbilitySpec.STATUS_STUN:
			return STUN_COLOR
		AbilitySpec.STATUS_DOT:
			return DOT_COLOR
		AbilitySpec.STATUS_SLOW:
			return SLOW_COLOR
	match event["effect"]:
		AbilitySpec.EFFECT_HEAL:
			return HEAL_COLOR
		AbilitySpec.EFFECT_TRANSFORM:
			return TRANSFORM_COLOR
	return DAMAGE_COLOR


## An unshaded, alpha-blended material in `color` at `alpha` — a flat flash that reads at a
## glance and tweens its own opacity down as it fades.
static func _material(color: Color, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var c := color
	c.a = alpha
	mat.albedo_color = c
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


## A sim ground position to a world point at the flash height — the same x/z mapping the
## presenter uses for entities, lifted clear of the ground plane.
static func _world(p: Vector2) -> Vector3:
	return Vector3(p.x, FX_HEIGHT, p.y)
