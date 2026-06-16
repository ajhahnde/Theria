class_name CombatFx
extends RefCounted
## Draws the brief visuals for the combat the simulation resolved this tick: a floating damage
## number over any unit that lost hp, and the auto-attack that caused it — a bolt flying from a
## ranged attacker to its target, or a close-in impact flash for a melee one. The sim records
## each on `SimState.hit_events` / `attack_events`; the presenter drains them every tick and
## hands each entry here. Like MatchFx, every node fades and frees itself, so the field never
## piles up; nothing here touches the simulation, and a snapshot-fed CLIENT simply draws none.

const GROUND_FX_HEIGHT := 30.0
## Bolts and impacts read better lofted to roughly mid-body rather than on the floor.
const STRIKE_HEIGHT := 70.0

## Floating damage number — a billboarded label that drifts up as it fades out.
const NUMBER_FONT_SIZE := 96
const NUMBER_START_Y := 130.0
const NUMBER_RISE := 90.0
const NUMBER_LIFETIME := 0.7
const NUMBER_COLOR := Color(1.0, 0.86, 0.4)

## Ranged auto: a small bright bolt that flies from attacker to target. Flight time scales
## with the gap but is clamped so a point-blank shot still reads and a long one is not slow.
const BOLT_RADIUS := 13.0
const BOLT_SPEED := 1300.0
const BOLT_MIN_TIME := 0.05
const BOLT_MAX_TIME := 0.22
const BOLT_COLOR := Color(1.0, 0.9, 0.55)

## Melee auto: a quick ring of impact flashed on the struck target.
const IMPACT_RADIUS := 50.0
const IMPACT_THICKNESS := 12.0
const IMPACT_ALPHA := 0.85
const IMPACT_LIFETIME := 0.16
const IMPACT_COLOR := Color(1.0, 0.95, 0.85)


## Pops one floating damage number from a `SimState.hit_events` entry (`{position, amount}`).
static func number(parent: Node3D, hit: Dictionary) -> void:
	var label := Label3D.new()
	label.text = str(hit["amount"])
	label.font_size = NUMBER_FONT_SIZE
	label.outline_size = NUMBER_FONT_SIZE / 6
	label.modulate = NUMBER_COLOR
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	parent.add_child(label)
	var base := _world(hit["position"], NUMBER_START_Y)
	label.global_position = base
	var faded := NUMBER_COLOR
	faded.a = 0.0
	var risen := base + Vector3(0.0, NUMBER_RISE, 0.0)
	var tween := parent.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position", risen, NUMBER_LIFETIME)
	tween.tween_property(label, "modulate", faded, NUMBER_LIFETIME)
	tween.chain().tween_callback(label.queue_free)


## Draws one auto-attack from a `SimState.attack_events` entry (`{origin, target, ranged}`):
## a flying bolt for a ranged attacker, an impact flash for a melee one.
static func strike(parent: Node3D, attack: Dictionary) -> void:
	if attack["ranged"]:
		_bolt(parent, attack["origin"], attack["target"])
	else:
		_impact(parent, attack["target"])


## A bright bolt that flies from `a` to `b` (sim positions) at mid-body height, then frees
## itself on arrival — the visible shot of a ranged auto-attack.
static func _bolt(parent: Node3D, a: Vector2, b: Vector2) -> void:
	var from := _world(a, STRIKE_HEIGHT)
	var to := _world(b, STRIKE_HEIGHT)
	var bolt := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = BOLT_RADIUS
	sphere.height = BOLT_RADIUS * 2.0
	bolt.mesh = sphere
	bolt.material_override = _material(BOLT_COLOR, 1.0)
	parent.add_child(bolt)
	bolt.global_position = from
	var flight := clampf(from.distance_to(to) / BOLT_SPEED, BOLT_MIN_TIME, BOLT_MAX_TIME)
	var tween := parent.create_tween()
	tween.tween_property(bolt, "global_position", to, flight)
	tween.tween_callback(bolt.queue_free)


## A quick ring flashed on the target — the close-in hit of a melee auto-attack.
static func _impact(parent: Node3D, at: Vector2) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = IMPACT_RADIUS - IMPACT_THICKNESS
	torus.outer_radius = IMPACT_RADIUS
	ring.mesh = torus
	var mat := _material(IMPACT_COLOR, IMPACT_ALPHA)
	ring.material_override = mat
	parent.add_child(ring)
	ring.global_position = _world(at, GROUND_FX_HEIGHT)
	var faded := mat.albedo_color
	faded.a = 0.0
	var tween := parent.create_tween()
	tween.tween_property(mat, "albedo_color", faded, IMPACT_LIFETIME)
	tween.tween_callback(ring.queue_free)


## An unshaded, alpha-blended material in `color` at `alpha` — mirrors MatchFx so combat and
## cast flashes read as one visual language.
static func _material(color: Color, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var c := color
	c.a = alpha
	mat.albedo_color = c
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


## A sim ground position to a world point at height `y` — the same x/z mapping the presenter
## uses for entities.
static func _world(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)
