class_name HeroModelLibrary
extends RefCounted
## The placeholder 3D models the heroes wear, and the logic that drops one onto the
## field at a consistent size, facing, and team colour under a stylised cel shader. Each
## hero kit maps to a low-poly animal glTF standing in for the species the shapeshifter
## takes. The models come from mixed sources at wildly different authored scales and
## facings, so this module normalises every one to a single on-field size, re-skins each
## surface with the shared toon shader (`cel.gdshader` — banded light, team colour mixed
## in), and leaves the match presenter to only ask for a model by kit.

## A hero kit's placeholder model, keyed by `kit_id`. A kit with no entry (an unknown
## kit, or a hero whose `kit_id` did not survive the wire on a pure CLIENT) has no model
## and the presenter falls back to a plain capsule body.
const HERO_MODELS := {
	"lion": "res://assets/models/heroes/lion.glb",
	"cheetah": "res://assets/models/heroes/cheetah.glb",
	"hyena": "res://assets/models/heroes/hyena.glb",
	"snake": "res://assets/models/heroes/snake.glb",
	"spider": "res://assets/models/heroes/spider.glb",
	"chameleon": "res://assets/models/heroes/chameleon.glb",
}

## The non-hero field props that now wear models too — lane creeps and the two structure
## kinds — keyed by a prop name the presenter passes (`creep`/`tower`/`nexus`). Each entry
## carries its glTF and the on-field size its longest axis is scaled to, so a creep reads
## small under the heroes while a tower stands imposing over them. Same low-poly source
## family (Quaternius / iPoly3D, all CC0) as the hero animals, credited in CREDITS.md.
const PROP_MODELS := {
	"creep": {"path": "res://assets/models/creeps/slime.glb", "size": 120.0},
	"tower": {"path": "res://assets/models/structures/tower.glb", "size": 460.0},
	"nexus": {"path": "res://assets/models/structures/nexus.glb", "size": 360.0},
}

## The world size a model's longest axis is scaled to, so every model reads at one size
## on the field regardless of the units it was authored in. Sized a touch above the
## capsule it replaces so the species is legible from the follow-camera.
const HERO_MODEL_SIZE := 260.0

## The shared cel shader every model is re-skinned with, so a stylised toon-banded look
## replaces the raw PBR import. Driven per surface in `_stylize`, which copies the source
## material's albedo into it and folds the team colour in.
const CEL_SHADER: Shader = preload("res://src/client/cel.gdshader")

## The soft drop-shadow blob laid under every unit so it sits on the ground rather than
## floating: a flat quad washed by this radial-fade shader, sized to the unit's own footprint
## and scaled out a touch, set a hair above the ground decor (SHADOW_Y) so a unit's shadow
## reads over a lane or the river too. A blob, not a shadow-map cast — it grounds thin
## low-poly legs cleanly without a stretched, noisy silhouette.
const SHADOW_SHADER: Shader = preload("res://src/client/shadow.gdshader")
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.5)
const SHADOW_SCALE := 1.7
const SHADOW_Y := 3.0

## How far a hero's albedo is mixed toward its team colour (0 keeps the species colour, 1
## replaces it), strong enough to read blue or red at a glance while the species texture
## still shows through. Kept light so an already-dark mesh (the spider) is tinted, not
## drowned to near-black.
const TEAM_TINT_STRENGTH := 0.25

## The heavier mix a structure or creep takes — a prop has no species identity of its own
## to protect, so it leans harder into the team colour than a hero does, reading blue/red
## at a glance from across the lane.
const PROP_TINT_STRENGTH := 0.4

## The yaw, in radians, that turns a kit's model to face its movement direction once the
## presenter has aimed its length axis down the move vector. The land animals are all
## authored with their body along Z but not all nose the same way, and the spider reads
## the same from every side — so this corrects the ones that come out tail-first. A kit
## with no entry needs no correction. Eyeball-calibrated against the windowed playtest.
const FORWARD_OFFSET := {}

## Per-tick world distance below which a hero counts as standing (it holds its heading and
## idles, rather than snapping to the jitter of a near-zero step), and the share of the
## remaining angle it turns through each 60 Hz tick — so it swings round to a new heading
## over a few ticks instead of popping.
const FACE_MOVE_EPS := 1.0
const FACE_TURN_RATE := 0.3


## The yaw correction for `kit_id`'s model, 0 when it already faces down its move vector.
static func forward_offset(kit_id: String) -> float:
	return FORWARD_OFFSET.get(kit_id, 0.0)


## The first AnimationPlayer inside `model`, or null when the model ships no clips (most
## of the placeholders are static meshes — only the spider is rigged). Lets the presenter
## drive an idle/walk loop where there is one and leave the rest as static bodies.
static func animator(model: Node3D) -> AnimationPlayer:
	for child in _descendants(model):
		if child is AnimationPlayer:
			return child as AnimationPlayer
	return null


## The name of `anim`'s clip whose name contains `want` (case-insensitive), or "" when
## none does — so the presenter can ask for "walk"/"idle" without knowing a model's
## armature-prefixed clip names (the spider's read `SpiderArmature|Spider_Walk` etc.).
static func clip_named(anim: AnimationPlayer, want: String) -> String:
	for name in anim.get_animation_list():
		if (name as String).to_lower().contains(want):
			return name
	return ""


## Primes `view` to turn and animate a model hero's `body`: stashes the running heading
## (`yaw`), the kit's forward correction (`yaw_offset`), and — for a rigged model — its
## AnimationPlayer (`anim`) with looped walk/idle clip names (`clip_walk`/`clip_idle`).
## The presenter then drives it each tick with `drive_facing`. The animal placeholders are
## mostly static meshes, so a model with no AnimationPlayer simply turns without a clip.
static func setup_facing(view: Dictionary, kit_id: String, body: Node3D) -> void:
	view["yaw"] = 0.0
	view["yaw_offset"] = forward_offset(kit_id)
	var anim := animator(body)
	if anim == null:
		return
	view["anim"] = anim
	view["clip_walk"] = clip_named(anim, "walk")
	view["clip_idle"] = clip_named(anim, "idle")
	_loop_clip(anim, view["clip_walk"])
	_loop_clip(anim, view["clip_idle"])


## Turns `body` toward this tick's `move` (its ground-plane step, world units) and drives
## its walk/idle clip, reading the facing state `setup_facing` stashed on `view`. A step
## longer than FACE_MOVE_EPS counts as moving: the heading eases toward the move vector
## (plus the kit's forward correction) by FACE_TURN_RATE of the remaining angle and the
## walk clip loops; otherwise the body holds its heading and idles. Rigless models turn,
## no clip.
static func drive_facing(view: Dictionary, body: Node3D, move: Vector2) -> void:
	var moving := move.length() > FACE_MOVE_EPS
	if moving:
		var target := atan2(move.x, move.y) + float(view["yaw_offset"])
		view["yaw"] = lerp_angle(view["yaw"], target, FACE_TURN_RATE)
		body.rotation.y = view["yaw"]
	if view.has("anim"):
		var clip: String = view["clip_walk"] if moving else view["clip_idle"]
		var anim := view["anim"] as AnimationPlayer
		if clip != "" and anim.current_animation != clip:
			anim.play(clip)


## Marks `clip` on `anim` as looping, so a walk or idle cycle repeats instead of playing
## once and freezing on its last frame (glTF imports clips non-looping). No-op for "".
static func _loop_clip(anim: AnimationPlayer, clip: String) -> void:
	if clip != "" and anim.has_animation(clip):
		anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR


## Whether `kit_id` has a placeholder model. Gate `add_to` on this — an unmodelled kit
## keeps the capsule body.
static func has_model(kit_id: String) -> bool:
	return HERO_MODELS.has(kit_id)


## Instances `kit_id`'s model under `parent`, size-normalised and re-skinned with the cel
## shader mixed toward `team_tint`, and returns it. `parent` must already be in the tree so
## the model's mesh transforms resolve for the bounds measurement. Call only when
## `has_model(kit_id)`.
static func add_to(parent: Node3D, kit_id: String, team_tint: Color) -> Node3D:
	var packed := load(HERO_MODELS[kit_id]) as PackedScene
	var model := packed.instantiate() as Node3D
	parent.add_child(model)
	_normalize(model, HERO_MODEL_SIZE)
	_stylize(model, team_tint, TEAM_TINT_STRENGTH)
	return model


## Instances a field prop's model (`prop` is a `PROP_MODELS` key — `creep`/`tower`/`nexus`)
## under `parent`, normalised to that prop's size and re-skinned with the cel shader at the
## heavier prop mix, and returns it. Mirrors `add_to` for the non-hero field: a creep or a
## structure stands on the ground at a consistent size instead of a debug capsule or box.
## `parent` must be in the tree for the bounds measurement.
static func add_prop(parent: Node3D, prop: String, team_tint: Color) -> Node3D:
	var def: Dictionary = PROP_MODELS[prop]
	var packed := load(def["path"]) as PackedScene
	var model := packed.instantiate() as Node3D
	parent.add_child(model)
	_normalize(model, def["size"])
	_stylize(model, team_tint, PROP_TINT_STRENGTH)
	return model


## Lays a soft drop-shadow blob under a unit, parented to its view `root`: a flat quad sized
## to `body`'s measured footprint (scaled out by SHADOW_SCALE), washed by the radial-fade
## shadow shader, set at SHADOW_Y above the ground. Grounds every unit — hero, creep, or
## structure — against the grass. No-op for a footprint that measures to nothing. `body` must
## already sit under `root` in the tree for its footprint to resolve.
static func add_shadow(root: Node3D, body: Node3D) -> void:
	var radius := footprint_radius(body)
	if radius <= 0.0:
		return
	var blob := MeshInstance3D.new()
	var quad := QuadMesh.new()
	var diameter := radius * 2.0 * SHADOW_SCALE
	quad.size = Vector2(diameter, diameter)
	blob.mesh = quad
	blob.rotation.x = -PI / 2.0  # lay the upright quad flat on the ground, facing up
	blob.position = Vector3(0.0, SHADOW_Y, 0.0)
	var mat := ShaderMaterial.new()
	mat.shader = SHADOW_SHADER
	mat.set_shader_parameter("shadow_color", SHADOW_COLOR)
	blob.material_override = mat
	root.add_child(blob)


## The horizontal half-extent of `body` about its parent origin — the furthest its merged
## mesh bounds reach on x or z, measured in the parent's space. Lets the presenter size a
## unit's drop-shadow blob to its actual footprint, so a wide tower and a slim chameleon each
## get a shadow that fits. `body` must be in the tree for its mesh transforms to resolve.
static func footprint_radius(body: Node3D) -> float:
	var parent := body.get_parent() as Node3D
	var inv := parent.global_transform.affine_inverse() if parent else Transform3D()
	var radius := 0.0
	for mi in _meshes(body):
		var box: AABB = inv * (mi.global_transform * mi.get_aabb())
		radius = maxf(radius, maxf(absf(box.position.x), absf(box.end.x)))
		radius = maxf(radius, maxf(absf(box.position.z), absf(box.end.z)))
	return radius


## The height of `body`'s top above its parent origin — the merged mesh bounds' max y,
## measured in the parent's space so a normalised model's own ground-standing offset is
## included. Lets the presenter float a hero's bars a fixed margin above whatever model
## (or capsule) it wears instead of a one-size height that detaches over a small one.
## `body` must be in the tree for its mesh transforms to resolve.
static func top_of(body: Node3D) -> float:
	var parent := body.get_parent() as Node3D
	var inv := parent.global_transform.affine_inverse() if parent else Transform3D()
	var top := 0.0
	for mi in _meshes(body):
		var box: AABB = inv * (mi.global_transform * mi.get_aabb())
		top = maxf(top, box.position.y + box.size.y)
	return top


## Scales `model` so its longest axis spans `size`, then offsets it so its footprint is
## centred on the parent origin and its base rests on the ground (y = 0). The models arrive
## at wildly different authored scales, so this is what makes every one read at its intended
## on-field size — a common size for the heroes, a per-prop size for creeps and structures.
static func _normalize(model: Node3D, size: float) -> void:
	var aabb := _model_aabb(model)
	var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if longest <= 0.0:
		return
	var s := size / longest
	model.scale = Vector3(s, s, s)
	var center := aabb.get_center()
	model.position = Vector3(-center.x * s, -aabb.position.y * s, -center.z * s)


## The merged bounds of every mesh under `model`, in the model's own local space so a
## later offset on the model does not skew it. The model must be in the tree for the
## mesh global transforms to resolve.
static func _model_aabb(model: Node3D) -> AABB:
	var inv := model.global_transform.affine_inverse()
	var out := AABB()
	var first := true
	for mi in _meshes(model):
		var local: AABB = inv * (mi.global_transform * mi.get_aabb())
		if first:
			out = local
			first = false
		else:
			out = out.merge(local)
	return out


## Re-skins every surface of `model` with the shared cel shader, mixed `strength` toward
## the team `color`. Each surface gets its own ShaderMaterial seeded from the source
## material's albedo (texture, base colour, and vertex-colour flag) so the model still
## reads as itself — only the lighting turns toon-banded and the team colour blends in. A
## hero takes a light mix to keep its species; a prop a heavier one.
static func _stylize(model: Node3D, color: Color, strength: float) -> void:
	for mi in _meshes(model):
		for surface in mi.mesh.get_surface_count():
			var src := mi.get_active_material(surface) as BaseMaterial3D
			var mat := ShaderMaterial.new()
			mat.shader = CEL_SHADER
			mat.set_shader_parameter("team_tint", color)
			mat.set_shader_parameter("tint_strength", strength)
			if src != null:
				mat.set_shader_parameter("albedo", src.albedo_color)
				mat.set_shader_parameter("use_vertex", 1.0 if src.vertex_color_use_as_albedo else 0.0)
				if src.albedo_texture != null:
					mat.set_shader_parameter("albedo_tex", src.albedo_texture)
			mi.set_surface_override_material(surface, mat)


## Every MeshInstance3D carrying a mesh in the subtree under `node`, gathered depth-first.
static func _meshes(node: Node, acc: Array[MeshInstance3D] = []) -> Array[MeshInstance3D]:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		acc.append(node as MeshInstance3D)
	for child in node.get_children():
		_meshes(child, acc)
	return acc


## Every node in the subtree under `node` (including `node`), gathered depth-first — the
## walk `animator` scans for the model's AnimationPlayer.
static func _descendants(node: Node, acc: Array[Node] = []) -> Array[Node]:
	acc.append(node)
	for child in node.get_children():
		_descendants(child, acc)
	return acc
