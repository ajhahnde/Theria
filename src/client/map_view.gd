class_name MapView
extends RefCounted
## The static map decor laid on the ground so the playfield reads — the lanes, the river,
## and the jungle camps — kept out of the match presenter so `main.gd` stays the driver and
## this stays the map painter.
##
## Every shape is read straight from MapData, the one geometry source the sim, the bots, and
## the tests already share, so the drawn map cannot drift from the simulated one. Pure
## presentation: flat coloured strips and discs lifted a hair above the ground to clear
## z-fighting, drawn once when the scene is built.

## The lift above the ground (y = 0) every flat decor piece sits at, so a painted strip does
## not z-fight the ground plane it lies on.
const DECOR_Y := 2.0

## Lanes: a sandy ribbon of this width tracing each lane corridor.
const LANE_WIDTH := 230.0
const LANE_COLOR := Color(0.40, 0.36, 0.25)

## River: a blue ribbon over the lanes, tracing the watercourse.
const RIVER_WIDTH := 210.0
const RIVER_COLOR := Color(0.17, 0.34, 0.52)

## Jungle camp: a flat disc marker on the ground.
const CAMP_RADIUS := 95.0
const CAMP_COLOR := Color(0.28, 0.40, 0.30)


## Paints the whole static map under `parent`: each lane as a sandy ribbon, the river as a
## blue ribbon over them, and a disc at every jungle camp. Drawn in that order so the river
## layers over the lanes. Call once, after the ground plane exists.
static func build(parent: Node3D) -> void:
	for lane in MapData.lane_count():
		_lay_ribbon(parent, MapData.lane_path(lane, 0), LANE_WIDTH, LANE_COLOR)
	_lay_ribbon(parent, MapData.river_polyline(), RIVER_WIDTH, RIVER_COLOR)
	for camp in MapData.JUNGLE_CAMPS:
		_mark_disc(parent, camp, CAMP_RADIUS, CAMP_COLOR)


## Lays a flat ribbon of `width` and `color` along a polyline's segments under `parent`, each
## a thin box set on the ground at the segment midpoint and yawed to its heading — so a lane
## or the river reads as a continuous painted strip rather than a row of disconnected marks.
static func _lay_ribbon(
	parent: Node3D, points: PackedVector2Array, width: float, color: Color
) -> void:
	var material := _flat_material(color)
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var delta := b - a
		var length := delta.length()
		if length <= 0.0:
			continue
		var strip := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(width, 1.0, length)
		strip.mesh = box
		strip.material_override = material
		var mid := (a + b) * 0.5
		strip.position = Vector3(mid.x, DECOR_Y, mid.y)
		strip.rotation.y = atan2(delta.x, delta.y)
		parent.add_child(strip)


## Marks a flat disc of `radius` and `color` on the ground at a field point — a jungle camp.
static func _mark_disc(parent: Node3D, pos: Vector2, radius: float, color: Color) -> void:
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 1.0
	disc.mesh = cyl
	disc.material_override = _flat_material(color)
	disc.position = Vector3(pos.x, DECOR_Y, pos.y)
	parent.add_child(disc)


static func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat
