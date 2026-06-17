class_name JungleDecor
extends RefCounted
## The three-dimensional map objects laid over the flat field so the arena reads as a real
## place — the mountain wall ringing the bounds, the rolling hills, a central landmark marking
## the middle, the scattered jungle growth, and the props that dress each neutral camp. Built
## once when the scene is raised, on top of MapView's flat lane/river/bridge decor.
##
## Everything here is procedural low-poly: faceted cones, domes, blades, and boxes assembled
## into a few batched meshes, each vertex carrying its own colour (rock grey rising to a light
## cap, trunk wood, leaf green fading to a sun-tipped edge). One shared toon material
## (foliage.gdshader) bands them into the same low-poly light family as the units, so a fern
## and a hero read as one art direction. No imported art — the geometry is the asset.
##
## Placement reads straight from MapData (bounds, lanes, river, camps, towers, nexuses), the
## one geometry source the sim/bots/tests already share, so the decor cannot drift from the
## simulated map: it never lands on a lane, in the river, on a structure, or out of bounds, and
## the jungle thins toward the lanes the way a beaten travel corridor would.

const FOLIAGE_SHADER: Shader = preload("res://src/client/foliage.gdshader")

## The reflection across the x = z plane — the world-space form of MapData's (x, y) → (y, x) field
## mirror, swapping the X and Z axes. Applied to the side batch to build team 1's half from team
## 0's, so the decorated halves are exact reflections and neither team gets more cover.
const MIRROR := Transform3D(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3.ZERO)

## A fixed seed so the scatter is identical every launch — the map is a designed place, not a
## fresh roll each match, and a reproducible layout is reviewable.
const SCATTER_SEED := 0x7E51A9

## How far inside the bounds the scatter keeps, leaving the rim to the mountain wall.
const FIELD_INSET := 600.0

## Lane / river / camp / structure clearances: no object lands within these of the named
## feature, so the playfield stays legible and nothing clips a unit's path or a building.
const LANE_HALF := 115.0  # mirrors MapView.LANE_WIDTH * 0.5 (the drawn path half-width)
const RIVER_HALF := 165.0  # mirrors MapView.RIVER_WIDTH * 0.5
const LANE_PLANT_MIN := LANE_HALF + 40.0
const RIVER_PLANT_MIN := RIVER_HALF + 110.0
const CAMP_CLEAR := 250.0
const TOWER_CLEAR := 360.0
const NEXUS_CLEAR := 620.0
const SPAWN_CLEAR := 380.0

## Jungle density falloff: a plant is rejected near a lane and reaches full density only deep in
## the jungle, so the growth thins toward the travelled lanes.
const JUNGLE_FULL := 1050.0

## Jungle walls (LoL-style paths): a boulder is drawn on every blocker point MapData lays down —
## the lane-flanking walls (broken by the gank gaps) and the camp pockets — so the rocks you see
## are exactly the rocks that block. The layout, its offsets, gaps, and the y = x mirror all live in
## MapData (the shared collision source); this file only dresses each point. Each visual boulder is
## sized a little larger than its collision footprint (MapData.WALL_RADIUS) so the solid circle
## always sits within the rock a player sees.
const BLOCKER_ROCK_MIN := 120.0  # ≥ MapData.WALL_RADIUS + the jitter below, so the rock covers it
const BLOCKER_ROCK_MAX := 175.0
const BLOCKER_JITTER := 20.0

## The central landmark: a wide low mound at the map centre crowned by one grand tree and ringed
## with standing stones, so the middle of the symmetric map is unmistakable. Its footprint is
## kept clear of other scatter.
const CENTER_RADIUS := 460.0

# --- palette (baked into the meshes as per-vertex colour) ----------------------------------
const ROCK_LOW := Color(0.26, 0.30, 0.25)  # mossy base of a peak / boulder
const ROCK_HIGH := Color(0.49, 0.50, 0.52)  # bare upper rock
const ROCK_CAP := Color(0.74, 0.76, 0.79)  # light, weathered crown
const WOOD_LOW := Color(0.25, 0.17, 0.10)
const WOOD_HIGH := Color(0.34, 0.24, 0.15)
const LEAF_LOW := Color(0.12, 0.33, 0.15)
const LEAF_HIGH := Color(0.27, 0.53, 0.25)
const FROND_LOW := Color(0.18, 0.40, 0.18)
const FROND_TIP := Color(0.42, 0.60, 0.27)  # sun-caught leaf edge
const GRASS_LOW := Color(0.13, 0.30, 0.12)  # the ground shader's low green — hills read as turf
const GRASS_HIGH := Color(0.22, 0.45, 0.18)  # the ground shader's high green
const MUSH_STEM := Color(0.86, 0.84, 0.74)
const MUSH_CAP := Color(0.62, 0.26, 0.20)
const TOTEM_WOOD := Color(0.31, 0.20, 0.12)
const TOTEM_CARVE := Color(0.58, 0.43, 0.20)
const BANNER_CLOTH := Color(0.64, 0.21, 0.17)


## Builds every map object under `parent`, batched into a few meshes. Call once, after the ground
## plane and MapView decor exist. Returns the FADE material so the caller can feed it the hero's
## position each frame (the canopy fade); the solid material never fades.
##
## Two axes of batching. By mirror: `axis` batches hold the self-symmetric decor on the mirror
## line (central marker, midline ridge, on-axis camps), drawn once; `side` batches hold the random
## decor, generated only on team 0's half and drawn again through a reflection across the x = z
## plane (MapData's field mirror), so team 1's half is an exact reflection — neither team gets more
## cover. By material: `solid` decor (mountains, rocks, walls, hills, camps, low cover) never fades;
## only the tall `fade` canopy (palms and trees) dissolves over the player's hero so it stays seen.
static func build(parent: Node3D) -> ShaderMaterial:
	var rng := RandomNumberGenerator.new()
	rng.seed = SCATTER_SEED
	var solid_mat := _material()
	var fade_mat := _material()
	var solid_axis := _new_surface()
	var solid_side := _new_surface()
	var fade_axis := _new_surface()
	var fade_side := _new_surface()
	_build_wall(solid_side, fade_side, rng)
	_build_terrain(solid_axis, solid_side, fade_axis, rng)
	_build_blockers(solid_axis, rng)
	_build_plants(solid_side, fade_side, rng)
	_build_camps(solid_axis, solid_side, rng)
	_emit(parent, solid_mat, solid_axis, false)
	_emit(parent, solid_mat, solid_side, false)
	_emit(parent, solid_mat, solid_side, true)
	_emit(parent, fade_mat, fade_axis, false)
	_emit(parent, fade_mat, fade_side, false)
	_emit(parent, fade_mat, fade_side, true)
	return fade_mat


## Commits a SurfaceTool batch as a MeshInstance3D wearing the shared material — mirrored across
## the y = x axis when `mirror` is set, so one generated half yields both. Drops an empty batch.
static func _emit(parent: Node3D, material: Material, st: SurfaceTool, mirror: bool) -> void:
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = material
	if mirror:
		inst.transform = MIRROR
	parent.add_child(inst)


static func _material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = FOLIAGE_SHADER
	return mat


# === boundary wall =========================================================================

## The mountain wall: a ridge of overlapping faceted peaks ringing the bounds, two staggered
## rows deep for silhouette, with the occasional tree breaking the rock so the rim reads as a
## forested mountain edge rather than a clean rampart. Only team 0's half is built here (peaks on
## its side of the y = x axis); the caller's mirror reflects it onto team 1's rim.
static func _build_wall(st: SurfaceTool, fade: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var b := MapData.BOUNDS
	var corners := [
		[Vector2(b.position.x, b.position.y), Vector2(b.end.x, b.position.y)],
		[Vector2(b.end.x, b.position.y), Vector2(b.end.x, b.end.y)],
		[Vector2(b.end.x, b.end.y), Vector2(b.position.x, b.end.y)],
		[Vector2(b.position.x, b.end.y), Vector2(b.position.x, b.position.y)],
	]
	var spacing := 540.0
	for edge in corners:
		var a: Vector2 = edge[0]
		var c: Vector2 = edge[1]
		var length := a.distance_to(c)
		var dir := (c - a) / length
		var inward := Vector2(-dir.y, dir.x)
		if inward.dot(-a) < 0.0:  # point the inward normal toward the map centre
			inward = -inward
		var steps := int(length / spacing)
		for i in steps:
			var t := (float(i) + 0.5) / float(steps)
			var base := a + dir * (length * t)
			if base.y < base.x:  # team 1's half — left to the mirror
				continue
			# back row: tall peaks sitting on the rim, pushed a touch outward
			var back := base - inward * rng.randf_range(40.0, 160.0)
			_mountain(st, _w(back), rng.randf_range(560.0, 800.0), rng.randf_range(1000.0, 1650.0), rng)
			# front row: shorter peaks pulled inboard, with trees mixed in
			var front := base + inward * rng.randf_range(220.0, 460.0) + dir * rng.randf_range(-160.0, 160.0)
			if rng.randf() < 0.24:
				_tree(fade, _w(front), rng.randf_range(0.9, 1.3), rng)
			else:
				_mountain(st, _w(front), rng.randf_range(360.0, 560.0), rng.randf_range(540.0, 980.0), rng)


# === terrain: hills + central landmark =====================================================

## The rolling relief and the central marker. The central marker and the midline ridge sit on the
## mirror axis and go in the `axis` batch (drawn once); the scattered swells go in the `side`
## batch (team 0's half, mirrored by the caller). Swells are wide, very low grass mounds kept off
## lanes, river, camps, and structures so they never deform a path or lift a building.
static func _build_terrain(
	axis: SurfaceTool, side: SurfaceTool, fade_axis: SurfaceTool, rng: RandomNumberGenerator
) -> void:
	# central landmark: a low mound crowned by a grand tree and ringed with standing stones
	_dome(axis, _w(Vector2.ZERO), CENTER_RADIUS, 28.0, 3, 9, GRASS_LOW, GRASS_HIGH, 0.05, rng)
	_tree(fade_axis, Vector3(0.0, 24.0, 0.0), 1.9, rng)  # the grand central tree, on the mound
	var stones := 6
	for i in stones:
		var a := TAU * float(i) / float(stones)
		var p := Vector2(cos(a), sin(a)) * 300.0
		var top := _w(p) + Vector3(0.0, 18.0, 0.0)
		_rock(axis, top, rng.randf_range(70.0, 110.0), rng.randf_range(120.0, 200.0), rng)
	_build_midline_ridge(axis, rng)
	# scattered swells — sparse, very low mounds so the ground rolls a little without burying a
	# hero (the sim is flat, so a tall mound would swallow a unit standing on it) and without a
	# wide mound's body ever spilling onto a lane, the river, or a building.
	var step := 1500.0
	var span := MapData.BOUNDS.size.x * 0.5 - FIELD_INSET
	var x := -span
	while x <= span:
		var z := -span
		while z <= span:
			var p := Vector2(x, z) + Vector2(rng.randf_range(-380.0, 380.0), rng.randf_range(-380.0, 380.0))
			z += step
			if p.y < p.x:  # team 1's half — the mirror fills it
				continue
			var radius := rng.randf_range(440.0, 720.0)
			if _near_lane(p) < radius + LANE_HALF + 150.0:
				continue
			if _near_river(p) < radius + RIVER_HALF + 150.0:
				continue
			if _blocked(p, radius + 220.0, radius) or p.length() < CENTER_RADIUS + radius:
				continue
			_dome(side, _w(p), radius, rng.randf_range(8.0, 18.0), 3, 8, GRASS_LOW, GRASS_HIGH, 0.08, rng)
		x += step


## The midline marker: a long low ridge of overlapping mounds running the mirror axis (y = x),
## the line halfway between the two bases, so the middle of the symmetric map reads at a glance.
## Broken where it would cross a lane or the river — gaps at the crossings — so the ridge never
## blocks a travelled path or dams the water. A touch taller than the ambient swells so it reads
## as a deliberate landform, but still low enough not to swallow a unit crossing the quiet mid.
static func _build_midline_ridge(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var radius := 360.0
	var span := MapData.BOUNDS.size.x * 0.5 - FIELD_INSET
	var s := -span
	while s <= span:
		var p := Vector2(s, s)  # every point on the mirror axis is (s, s)
		s += 300.0
		if _near_lane(p) < radius + LANE_HALF + 90.0:
			continue
		if _near_river(p) < radius + RIVER_HALF + 90.0:
			continue
		if _blocked(p, radius + 160.0, radius):
			continue
		_dome(
			st, _w(p), radius * rng.randf_range(0.85, 1.05), rng.randf_range(24.0, 38.0),
			3, 8, GRASS_LOW, GRASS_HIGH, 0.10, rng
		)


# === scattered jungle growth ===============================================================

## The general jungle objects: a dense jittered grid of plants over the open ground, each kind
## picked at random — leafy bushes, tall shrubs, ferns, grass tufts, palms, mossy rocks, and
## mushroom clusters — so the field reads as thick jungle. Only team 0's half is grown; the
## caller's mirror reflects it. Density still follows distance from the nearest lane (sparser
## beside a travelled lane, thicker deep in the jungle) but never thins to bare ground.
static func _build_plants(st: SurfaceTool, fade: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var step := 360.0
	var span := MapData.BOUNDS.size.x * 0.5 - FIELD_INSET
	var x := -span
	while x <= span:
		var z := -span
		while z <= span:
			var p := Vector2(x, z) + Vector2(rng.randf_range(-160.0, 160.0), rng.randf_range(-160.0, 160.0))
			z += step
			if p.y < p.x:  # team 1's half — the mirror fills it
				continue
			var d_lane := _near_lane(p)
			if d_lane < LANE_PLANT_MIN or _near_river(p) < RIVER_PLANT_MIN:
				continue
			if _blocked(p, CAMP_CLEAR) or p.length() < CENTER_RADIUS:
				continue
			var density := 0.22 + 0.5 * smoothstep(LANE_PLANT_MIN, JUNGLE_FULL, d_lane)
			if rng.randf() > density:
				continue
			_plant(st, fade, p, rng)
		x += step


## Places one random jungle plant. The tall canopy (palms, broadleafs) goes in the `fade` batch so
## it dissolves over the hero; the low cover and the odd boulder stay solid in `st`.
static func _plant(
	st: SurfaceTool, fade: SurfaceTool, p: Vector2, rng: RandomNumberGenerator
) -> void:
	var roll := rng.randf()
	var foot := _w(p)
	if roll < 0.18:
		_grass(st, foot, rng)
	elif roll < 0.33:
		_fern(st, foot, rng)
	elif roll < 0.47:
		_bush(st, foot, rng.randf_range(70.0, 120.0), rng.randf_range(60.0, 110.0), rng)
	elif roll < 0.55:
		_shrub(st, foot, rng)
	elif roll < 0.83:
		_palm(fade, foot, rng)  # palms — the bulk of the jungle canopy
	elif roll < 0.90:
		_tree(fade, foot, rng.randf_range(0.8, 1.2), rng)  # a few broadleafs for variety
	elif roll < 0.96:
		_mushrooms(st, foot, rng)
	else:
		_rock(st, foot, rng.randf_range(60.0, 130.0), rng.randf_range(70.0, 160.0), rng)


# === neutral camps =========================================================================

## Dresses each jungle camp with a ring of boulders around a carved totem flying a small banner,
## so a neutral camp reads as a claimed place rather than a flat disc on the ground. A camp on the
## mirror axis is dressed once into the `axis` batch; a camp on team 0's side goes in the `side`
## batch (the mirror dresses its team 1 partner); a camp on team 1's side is left to the mirror.
static func _build_camps(axis: SurfaceTool, side: SurfaceTool, rng: RandomNumberGenerator) -> void:
	for camp in MapData.JUNGLE_CAMPS:
		if camp.y < camp.x - 1.0:  # team 1's side — the mirror fills it
			continue
		var st := axis if absf(camp.y - camp.x) < 1.0 else side
		var rocks := 5
		var rot := rng.randf() * TAU
		for i in rocks:
			var a := rot + TAU * float(i) / float(rocks)
			var p := camp + Vector2(cos(a), sin(a)) * rng.randf_range(150.0, 195.0)
			_rock(st, _w(p), rng.randf_range(55.0, 95.0), rng.randf_range(70.0, 140.0), rng)
		_totem(st, _w(camp), rng)


## A carved totem post: stacked wood blocks on a base, a bright carved cap, and a banner cloth
## hung from one side. Faces the totem at a random yaw so no two camps line up.
static func _totem(st: SurfaceTool, foot: Vector3, rng: RandomNumberGenerator) -> void:
	var yaw := rng.randf() * TAU
	var post_h := 210.0
	_box(st, foot + Vector3(0.0, post_h * 0.5, 0.0), Vector3(46.0, post_h, 46.0), yaw, TOTEM_WOOD)
	_box(st, foot + Vector3(0.0, post_h + 18.0, 0.0), Vector3(78.0, 36.0, 78.0), yaw, TOTEM_CARVE)
	# a cross-arm the banner hangs from
	_box(st, foot + Vector3(0.0, post_h * 0.62, 0.0), Vector3(120.0, 30.0, 30.0), yaw, TOTEM_WOOD)
	var banner := foot + Vector3(cos(yaw), 0.0, sin(yaw)) * 64.0 + Vector3(0.0, post_h * 0.40, 0.0)
	_box(st, banner, Vector3(8.0, 110.0, 64.0), yaw, BANNER_CLOTH)


# === jungle walls (LoL-style paths) ========================================================

## Draws a boulder on every blocker point MapData lays down — the lane-flanking walls (with their
## gank gaps) and the camp pockets, both halves already mirrored in the data. Drawn once onto the
## non-mirrored `axis` batch (the points carry their own y = x partners), so what renders matches
## the collision set one-for-one. Each rock is sized a little over MapData.WALL_RADIUS, with only a
## small jitter, so the solid circle always sits inside the boulder a player sees.
static func _build_blockers(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	for p in MapData.jungle_wall_points():
		var jitter := Vector2(
			rng.randf_range(-BLOCKER_JITTER, BLOCKER_JITTER),
			rng.randf_range(-BLOCKER_JITTER, BLOCKER_JITTER),
		)
		_rock(
			st,
			_w(p + jitter),
			rng.randf_range(BLOCKER_ROCK_MIN, BLOCKER_ROCK_MAX),
			rng.randf_range(160.0, 260.0),
			rng,
		)


# === plant builders ========================================================================

## A faceted mountain peak: a two-ring cone with the base radius and apex jittered into a craggy
## silhouette, mossy at the foot, bare rock up the flank, a light weathered crown.
static func _mountain(
	st: SurfaceTool, foot: Vector3, radius: float, height: float, rng: RandomNumberGenerator
) -> void:
	var seg := 8
	var yaw := rng.randf() * TAU
	var center := foot + Vector3(0.0, height * 0.4, 0.0)
	var skew := radius * 0.3
	var apex := foot + Vector3((rng.randf() - 0.5) * skew, height, (rng.randf() - 0.5) * skew)
	var low: Array = []
	var mid: Array = []
	for i in seg:
		var a := yaw + TAU * float(i) / float(seg)
		var rl := radius * rng.randf_range(0.82, 1.12)
		var rm := radius * rng.randf_range(0.45, 0.62)
		low.append(foot + Vector3(cos(a) * rl, 0.0, sin(a) * rl))
		mid.append(foot + Vector3(cos(a) * rm, height * rng.randf_range(0.45, 0.60), sin(a) * rm))
	for i in seg:
		var j := (i + 1) % seg
		_quad_out(st, low[i], low[j], mid[j], mid[i], center, ROCK_LOW, ROCK_LOW, ROCK_HIGH, ROCK_HIGH)
		_face_out(st, mid[i], mid[j], apex, center, ROCK_HIGH, ROCK_HIGH, ROCK_CAP)
		_face_out(st, foot, low[j], low[i], foot, ROCK_LOW, ROCK_LOW, ROCK_LOW)  # base skirt


## A low-poly tree: a tapered trunk and two stacked canopy cones, green fading to a sun-tipped
## crown, hue-jittered per tree so a stand does not look stamped.
static func _tree(st: SurfaceTool, foot: Vector3, scale: float, rng: RandomNumberGenerator) -> void:
	var trunk_h := 90.0 * scale
	var trunk_r := 20.0 * scale
	_cone(st, foot, trunk_r * 1.2, trunk_h, 6, rng.randf() * TAU, WOOD_LOW, WOOD_HIGH, false)
	var hue := rng.randf_range(-0.04, 0.04)
	var low := Color(LEAF_LOW.r, clampf(LEAF_LOW.g + hue, 0.0, 1.0), LEAF_LOW.b)
	var high := Color(LEAF_HIGH.r, clampf(LEAF_HIGH.g + hue, 0.0, 1.0), LEAF_HIGH.b)
	var c1 := foot + Vector3(0.0, trunk_h * 0.7, 0.0)
	_cone(st, c1, 150.0 * scale, 165.0 * scale, 7, rng.randf() * TAU, low, high, true)
	var c2 := c1 + Vector3(0.0, 110.0 * scale, 0.0)
	_cone(st, c2, 100.0 * scale, 150.0 * scale, 7, rng.randf() * TAU, low, high, true)


## A tall jungle shrub: a stack of two leafy domes, broader at the base.
static func _shrub(st: SurfaceTool, foot: Vector3, rng: RandomNumberGenerator) -> void:
	var r := rng.randf_range(95.0, 140.0)
	_dome(st, foot, r, r * 0.9, 3, 7, LEAF_LOW, LEAF_HIGH, 0.18, rng)
	var top := foot + Vector3(0.0, r * 0.55, 0.0)
	_dome(st, top, r * 0.66, r * 0.8, 2, 7, LEAF_LOW, LEAF_HIGH, 0.18, rng)


## A leafy bush: one jittered dome of foliage.
static func _bush(
	st: SurfaceTool, foot: Vector3, radius: float, height: float, rng: RandomNumberGenerator
) -> void:
	_dome(st, foot, radius, height, 2, 7, LEAF_LOW, LEAF_HIGH, 0.22, rng)


## A tropical fern: a low crown of broad blades fanning out and up from the base.
static func _fern(st: SurfaceTool, foot: Vector3, rng: RandomNumberGenerator) -> void:
	var fronds := 7
	var rot := rng.randf() * TAU
	for i in fronds:
		var a := rot + TAU * float(i) / float(fronds) + rng.randf_range(-0.18, 0.18)
		var dir := Vector2(cos(a), sin(a))
		var length := rng.randf_range(95.0, 150.0)
		_blade(st, foot, dir, length, length * 0.55, 36.0, FROND_LOW, FROND_TIP)


## A grass tuft: a few near-vertical thin blades clustered at the base.
static func _grass(st: SurfaceTool, foot: Vector3, rng: RandomNumberGenerator) -> void:
	var blades := 5
	for i in blades:
		var a := rng.randf() * TAU
		var dir := Vector2(cos(a), sin(a))
		var length := rng.randf_range(45.0, 85.0)
		_blade(st, foot, dir, length * 0.35, 14.0, length, GRASS_HIGH, FROND_TIP)


## A palm: a tall thin trunk and a crown of long fronds arcing down from the top.
static func _palm(st: SurfaceTool, foot: Vector3, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(300.0, 420.0)
	_cone(st, foot, 20.0, h, 6, rng.randf() * TAU, WOOD_LOW, WOOD_HIGH, false)
	var crown := foot + Vector3(0.0, h, 0.0)
	var fronds := 7
	var rot := rng.randf() * TAU
	for i in fronds:
		var a := rot + TAU * float(i) / float(fronds)
		var dir := Vector2(cos(a), sin(a))
		_blade(st, crown, dir, 180.0, 70.0, -50.0, FROND_LOW, FROND_TIP)


## A mossy boulder: a squat jittered dome of rock.
static func _rock(
	st: SurfaceTool, foot: Vector3, radius: float, height: float, rng: RandomNumberGenerator
) -> void:
	_dome(st, foot, radius, height, 2, 6, ROCK_LOW, ROCK_HIGH, 0.18, rng)


## A small mushroom cluster: a handful of pale stems under red-brown caps.
static func _mushrooms(st: SurfaceTool, foot: Vector3, rng: RandomNumberGenerator) -> void:
	var count := 3
	for i in count:
		var off := Vector3(rng.randf_range(-45.0, 45.0), 0.0, rng.randf_range(-45.0, 45.0))
		var stem := foot + off
		var h := rng.randf_range(28.0, 52.0)
		var r := rng.randf_range(9.0, 16.0)
		_cone(st, stem, r, h, 5, 0.0, MUSH_STEM, MUSH_STEM, false)
		_dome(st, stem + Vector3(0.0, h, 0.0), r * 2.4, r * 1.5, 2, 6, MUSH_CAP, MUSH_CAP, 0.05, rng)


# === geometry primitives ===================================================================

## A cone from `base` upward: `seg` side facets to the apex, plus a base skirt. `cap_tip` colours
## the apex with `c_high`; otherwise the whole cone runs base→tip in the two colours by height.
static func _cone(
	st: SurfaceTool, base: Vector3, radius: float, height: float, seg: int, yaw: float,
	c_low: Color, c_high: Color, _cap_tip: bool
) -> void:
	var apex := base + Vector3(0.0, height, 0.0)
	var center := base + Vector3(0.0, height * 0.5, 0.0)
	var ring: Array = []
	for i in seg:
		var a := yaw + TAU * float(i) / float(seg)
		ring.append(base + Vector3(cos(a) * radius, 0.0, sin(a) * radius))
	for i in seg:
		var j := (i + 1) % seg
		_face_out(st, ring[i], ring[j], apex, center, c_low, c_low, c_high)
		_face_out(st, base, ring[j], ring[i], base, c_low, c_low, c_low)


## A half-ellipsoid dome from `base`, `rings` high by `seg` around, the side radius optionally
## jittered for a craggy or leafy irregular surface. Colours run base→apex.
static func _dome(
	st: SurfaceTool, base: Vector3, radius: float, height: float, rings: int, seg: int,
	c_low: Color, c_high: Color, jitter: float, rng: RandomNumberGenerator
) -> void:
	var center := base + Vector3(0.0, height * 0.45, 0.0)
	var grid: Array = []
	for r_i in rings:
		var t := float(r_i) / float(rings)
		var ph := t * PI * 0.5
		var rr := cos(ph) * radius
		var yy := sin(ph) * height
		var row: Array = []
		for s in seg:
			var a := TAU * float(s) / float(seg)
			var jr := 1.0 + (rng.randf() - 0.5) * jitter if r_i > 0 else 1.0
			row.append(base + Vector3(cos(a) * rr * jr, yy, sin(a) * rr * jr))
		grid.append(row)
	var apex := base + Vector3(0.0, height, 0.0)
	for r_i in rings:
		var ca := c_low.lerp(c_high, float(r_i) / float(rings))
		var cb := c_low.lerp(c_high, float(r_i + 1) / float(rings))
		for s in seg:
			var s2 := (s + 1) % seg
			var lo: Array = grid[r_i]
			if r_i == rings - 1:
				_face_out(st, lo[s], lo[s2], apex, center, ca, ca, c_high)
			else:
				var hi: Array = grid[r_i + 1]
				_quad_out(st, lo[s], lo[s2], hi[s2], hi[s], center, ca, ca, cb, cb)


## A single tapered blade (frond / grass / leaf): a triangle from a base width to a tip lifted
## `lift` above the base and pushed `length` along `dir`. Two-sided via the shader's disabled
## cull, so it lights from either face.
static func _blade(
	st: SurfaceTool, base: Vector3, dir: Vector2, length: float, width: float, lift: float,
	c_low: Color, c_high: Color
) -> void:
	var tip := base + Vector3(dir.x * length, lift, dir.y * length)
	var side := Vector3(-dir.y, 0.0, dir.x) * (width * 0.5)
	_face(st, base - side, base + side, tip, c_low, c_low, c_high)


## An axis-aligned box rotated `yaw` about Y at `center`, flat-coloured. Built from its eight
## corners with outward-oriented faces, so winding never matters.
static func _box(st: SurfaceTool, center: Vector3, size: Vector3, yaw: float, col: Color) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var cs := cos(yaw)
	var sn := sin(yaw)
	var c: Array = []
	var signs := [-1.0, 1.0]
	for iy in 2:
		var sy: float = signs[iy]
		for ix in 2:
			var sx: float = signs[ix]
			for iz in 2:
				var sz: float = signs[iz]
				var lx := sx * hx
				var lz := sz * hz
				c.append(center + Vector3(lx * cs - lz * sn, sy * hy, lx * sn + lz * cs))
	# index = (sy>0)<<2 | (sx>0)<<1 | (sz>0)
	_quad_out(st, c[0], c[1], c[3], c[2], center, col, col, col, col)  # bottom
	_quad_out(st, c[4], c[5], c[7], c[6], center, col, col, col, col)  # top
	_quad_out(st, c[0], c[1], c[5], c[4], center, col, col, col, col)
	_quad_out(st, c[2], c[3], c[7], c[6], center, col, col, col, col)
	_quad_out(st, c[0], c[2], c[6], c[4], center, col, col, col, col)
	_quad_out(st, c[1], c[3], c[7], c[5], center, col, col, col, col)


# === surface plumbing ======================================================================

static func _new_surface() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## Emits a flat-shaded triangle with a single face normal and per-vertex colours. Used for thin
## two-sided blades where there is no meaningful "outward".
static func _face(
	st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color
) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 0.0001:
		return
	n = n.normalized()
	st.set_color(ca)
	st.set_normal(n)
	st.add_vertex(a)
	st.set_color(cb)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_color(cc)
	st.set_normal(n)
	st.add_vertex(c)


## Like `_face`, but flips the normal to point away from `pivot` (the object's centre), so a
## solid's facets are lit from outside regardless of vertex winding.
static func _face_out(
	st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, pivot: Vector3,
	ca: Color, cb: Color, cc: Color
) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 0.0001:
		return
	n = n.normalized()
	if n.dot((a + b + c) / 3.0 - pivot) < 0.0:
		n = -n
	st.set_color(ca)
	st.set_normal(n)
	st.add_vertex(a)
	st.set_color(cb)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_color(cc)
	st.set_normal(n)
	st.add_vertex(c)


## Two outward-facing triangles making a quad a→b→c→d.
static func _quad_out(
	st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, pivot: Vector3,
	ca: Color, cb: Color, cc: Color, cd: Color
) -> void:
	_face_out(st, a, b, c, pivot, ca, cb, cc)
	_face_out(st, a, c, d, pivot, ca, cc, cd)


# === placement helpers =====================================================================

## Lifts a field point to world space, on the ground (y = 0). The decor sits on the plane;
## MapView's flat strips ride a hair above it.
static func _w(p: Vector2) -> Vector3:
	return Vector3(p.x, 0.0, p.y)


## Distance from a field point to the nearest lane corridor centreline.
static func _near_lane(p: Vector2) -> float:
	var best := INF
	for lane in MapData.LANES:
		best = minf(best, _dist_to_polyline(p, lane))
	return best


## Distance from a field point to the river course.
static func _near_river(p: Vector2) -> float:
	return _dist_to_polyline(p, MapData.RIVER)


## Whether a field point falls inside the clearance of any structure or camp — a hard keep-out
## the scatter must skip. `camp_clear` lets hills hold farther off a camp than plants do; `pad`
## widens the tower/nexus/spawn clearances by an object's own radius, so a wide hill's body never
## reaches a building, not just its centre.
static func _blocked(p: Vector2, camp_clear: float, pad := 0.0) -> bool:
	for camp in MapData.JUNGLE_CAMPS:
		if p.distance_to(camp) < camp_clear:
			return true
	for slot in MapData.TOWER_SLOTS:
		if p.distance_to(slot) < TOWER_CLEAR + pad:
			return true
	for team in 2:
		if p.distance_to(MapData.nexus_for_team(team)) < NEXUS_CLEAR + pad:
			return true
		if p.distance_to(MapData.spawn_for_team(team)) < SPAWN_CLEAR + pad:
			return true
	return false


## Shortest distance from `p` to a polyline, the minimum over its segments.
static func _dist_to_polyline(p: Vector2, pts: Array) -> float:
	var best := INF
	for i in pts.size() - 1:
		var closest := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
		best = minf(best, p.distance_to(closest))
	return best
