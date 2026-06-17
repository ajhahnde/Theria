class_name FogOverlay
extends RefCounted
## The fog-of-war sheet drawn over the playfield: a dark plane spanning the arena that dims
## everywhere the player's team cannot see, cleared in a circle around each of the team's sight
## sources. It is presentation only — which enemies are hidden, and which never reach a remote
## client at all, is decided authoritatively by Vision and the snapshot filter; this just tints
## the unseen ground so the fog reads. Built once with the scene (skipped on a headless run, which
## has no display) and fed the live reveal circles each tick by `main.gd`.
##
## The reveal set comes straight from Vision.sight_sources, the same circles the server's snapshot
## filter uses, so the lit ground matches exactly which units are sent — a unit appears the instant
## its position enters a lit circle.

const FOG_SHADER: Shader = preload("res://src/client/fog.gdshader")

## Must match the fog shader's MAX_SOURCES. A 3v3 team fields well under this — up to three heroes,
## a dozen lane creeps, and five structures, ~20 sources — so the cap only ever clips a pathological
## case, in which the surplus sources simply go undrawn (a touch more fog), never an error.
const MAX_SOURCES := 64

## The sheet's height above the ground: above MapView's flat lane/river/bridge decor so the field
## dims under it, but well below the 3D bodies (heroes, towers) so a unit standing in a lit circle
## rises in front of the fog rather than being tinted by it.
const FOG_Y := 10.0

var _material: ShaderMaterial


## Builds the fog plane under `parent` and returns the overlay holding its material. Call once,
## after the ground and map decor exist; the plane covers the whole arena at a fixed lift.
static func build(parent: Node3D) -> FogOverlay:
	var fog := FogOverlay.new()
	fog._material = ShaderMaterial.new()
	fog._material.shader = FOG_SHADER
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = MapData.BOUNDS.size
	mesh.mesh = plane
	var center := MapData.BOUNDS.get_center()
	mesh.position = Vector3(center.x, FOG_Y, center.y)
	mesh.material_override = fog._material
	# Span the whole map, so a reveal circle near the rim is never clipped by the camera frustum
	# culling the plane when the hero is across the arena.
	mesh.extra_cull_margin = MapData.BOUNDS.size.length()
	parent.add_child(mesh)
	return fog


## Applies fog of war to the drawn world for `team`: dims the ground that team cannot see (every
## mode) and hides the enemy bodies standing in that fog (`hide_fogged`, set only with local
## authority — a pure CLIENT already receives a snapshot filtered to its team, so every entity it
## holds is one it can see). `views` is the renderer's id->view pool. Friendlies are always visible,
## so the hide pass only ever drops enemies, layered over the renderer's own dead-hero hide.
func apply(state: SimState, team: int, views: Dictionary, hide_fogged: bool) -> void:
	if hide_fogged:
		var visible := Vision.visible_ids(state, team)
		for id in state.entities:
			if not visible.has(id):
				(views[id]["root"] as Node3D).visible = false
	update(Vision.sight_sources(state, team))


## Feeds this tick's reveal circles to the shader: each `{center: Vector2, radius: float}` from
## Vision.sight_sources, packed as (center.x, center.y, radius, 0) in world units. Capped at
## MAX_SOURCES; an empty set leaves the field clear (no vision data yet).
func update(sources: Array) -> void:
	var packed := PackedVector4Array()
	for source in sources:
		if packed.size() >= MAX_SOURCES:
			break
		var center: Vector2 = source["center"]
		packed.append(Vector4(center.x, center.y, source["radius"], 0.0))
	_material.set_shader_parameter("fog_sources", packed)
	_material.set_shader_parameter("source_count", packed.size())
