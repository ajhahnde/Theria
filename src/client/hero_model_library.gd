class_name HeroModelLibrary
extends RefCounted
## The placeholder 3D models the heroes wear, and the logic that drops one onto the
## field at a consistent size and team colour. Each hero kit maps to a low-poly animal
## glTF standing in for the species the shapeshifter takes. The models come from mixed
## sources at wildly different authored scales and facings, so this module normalises
## every one to a single on-field size and washes it with its team colour — the asset
## handling kept out of the match presenter, which only asks for a model by kit.

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

## The opacity of the team-colour wash overlaid on a model, strong enough to read blue
## or red at a glance while the species texture still shows through underneath. Kept light
## so an already-dark mesh (the spider) is tinted, not drowned to near-black.
const TEAM_TINT_ALPHA := 0.25

## The heavier wash a structure or creep takes — a prop has no species identity of its own
## to protect, so it leans harder into the team colour than a hero does, reading blue/red
## at a glance from across the lane.
const PROP_TINT_ALPHA := 0.4

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


## Instances `kit_id`'s model under `parent`, size-normalised and washed with
## `team_tint`, and returns it. `parent` must already be in the tree so the model's mesh
## transforms resolve for the bounds measurement. Call only when `has_model(kit_id)`.
static func add_to(parent: Node3D, kit_id: String, team_tint: Color) -> Node3D:
	var packed := load(HERO_MODELS[kit_id]) as PackedScene
	var model := packed.instantiate() as Node3D
	parent.add_child(model)
	_normalize(model, HERO_MODEL_SIZE)
	_tint(model, team_tint, TEAM_TINT_ALPHA)
	return model


## Instances a field prop's model (`prop` is a `PROP_MODELS` key — `creep`/`tower`/`nexus`)
## under `parent`, normalised to that prop's size and washed with the heavier prop tint, and
## returns it. Mirrors `add_to` for the non-hero field: a creep or a structure stands on the
## ground at a consistent size instead of a debug capsule or box. `parent` must be in the
## tree for the bounds measurement.
static func add_prop(parent: Node3D, prop: String, team_tint: Color) -> Node3D:
	var def: Dictionary = PROP_MODELS[prop]
	var packed := load(def["path"]) as PackedScene
	var model := packed.instantiate() as Node3D
	parent.add_child(model)
	_normalize(model, def["size"])
	_tint(model, team_tint, PROP_TINT_ALPHA)
	return model


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


## Lays a translucent `color` overlay (at opacity `alpha`) over every mesh in `model`,
## tinting it toward its team without replacing the model's own material, so the underlying
## texture stays visible. A hero takes a light wash to keep its species; a prop a heavier one.
static func _tint(model: Node3D, color: Color, alpha: float) -> void:
	var wash := color
	wash.a = alpha
	var overlay := StandardMaterial3D.new()
	overlay.albedo_color = wash
	overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for mi in _meshes(model):
		mi.material_overlay = overlay


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
