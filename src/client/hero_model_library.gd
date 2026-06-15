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

## The world size a model's longest axis is scaled to, so every model reads at one size
## on the field regardless of the units it was authored in. Sized a touch above the
## capsule it replaces so the species is legible from the follow-camera.
const HERO_MODEL_SIZE := 260.0

## The opacity of the team-colour wash overlaid on a model, strong enough to read blue
## or red at a glance while the species texture still shows through underneath. Kept light
## so an already-dark mesh (the spider) is tinted, not drowned to near-black.
const TEAM_TINT_ALPHA := 0.25


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
	_normalize(model)
	_tint(model, team_tint)
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


## Scales `model` so its longest axis spans HERO_MODEL_SIZE, then offsets it so its
## footprint is centred on the parent origin and its base rests on the ground (y = 0).
## The models arrive at wildly different authored scales, so this is what makes every
## hero read at one size.
static func _normalize(model: Node3D) -> void:
	var aabb := _model_aabb(model)
	var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if longest <= 0.0:
		return
	var s := HERO_MODEL_SIZE / longest
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


## Lays a translucent `color` overlay over every mesh in `model`, tinting it toward its
## team without replacing the model's own material, so the species texture stays visible.
static func _tint(model: Node3D, color: Color) -> void:
	var wash := color
	wash.a = TEAM_TINT_ALPHA
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
