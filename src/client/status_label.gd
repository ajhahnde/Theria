class_name StatusLabel
extends RefCounted
## Writes a hero's active crowd-control statuses onto its floating `Label3D` — `STUNNED` /
## `POISONED` / `SLOWED`, coloured by the highest-priority one, and hidden when there are
## none. Statuses live only in the authoritative sim (LOCAL/HOST), so a pure CLIENT shows
## none until they cross the wire; the label simply stays hidden there. Pure presentation,
## lifted out of `main.gd` so that file stays under the line cap.


## Refreshes `label` from `entity`'s live statuses (see the class doc for the contract).
static func refresh(label: Label3D, entity: SimEntity) -> void:
	if entity.statuses.is_empty():
		label.visible = false
		return
	var names: Array[String] = []
	for kind in [AbilitySpec.STATUS_STUN, AbilitySpec.STATUS_DOT, AbilitySpec.STATUS_SLOW]:
		if entity.statuses.has(kind):
			names.append(_name_of(kind))
			if names.size() == 1:
				label.modulate = _color_of(kind)
	label.visible = true
	label.text = "\n".join(names)


static func _name_of(kind: int) -> String:
	match kind:
		AbilitySpec.STATUS_STUN:
			return "STUNNED"
		AbilitySpec.STATUS_DOT:
			return "POISONED"
		AbilitySpec.STATUS_SLOW:
			return "SLOWED"
	return ""


static func _color_of(kind: int) -> Color:
	match kind:
		AbilitySpec.STATUS_STUN:
			return Color(1.0, 0.9, 0.3)
		AbilitySpec.STATUS_DOT:
			return Color(0.6, 1.0, 0.4)
		AbilitySpec.STATUS_SLOW:
			return Color(0.55, 0.8, 1.0)
	return Color.WHITE
