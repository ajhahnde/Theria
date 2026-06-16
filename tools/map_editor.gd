extends SceneTree
## Live top-down map editor: place, drag, and delete the map geometry by clicking, build it
## symmetric across the TL-BR diagonal with one click per side, then write the result straight
## back into src/sim/map_data.gd. Built so the map can be designed by eye instead of by typing
## coordinates — the companion to tools/map_shot.gd (which is a still snapshot; this is live).
##
## Run it (window stays open, it is interactive):
##   godot --path . -s tools/map_editor.gd
##
## Controls
##   1..6         pick the layer: 1 River  2 Camps  3 Nexus  4 Towers  5 LaneT  6 LaneB
##   left-click   empty ground      -> add a point to the active layer (Nexus: drag only)
##                on a point         -> grab it; hold and move to drag
##                on a river segment -> insert a vertex there, splitting it
##   right-click  on a point         -> delete it (Nexus: ignored — always two bases)
##   S            symmetry-lock: edits mirror across the y=x axis automatically (default ON)
##   A            snap the hovered point exactly onto the y=x axis
##   Z            undo the last edit
##   G            grid snap (50)        H  mirror ghost (shown when symmetry-lock is off)
##   wheel        zoom    middle-drag  pan    R  reset the view
##   W            WRITE the layers back into map_data.gd (a .bak is saved first)
##   ESC          quit
##
## The map mirrors AXIALLY across the TL-BR diagonal (the bright line, sim y = x): a point
## (x, y) mirrors to (y, x), which swaps the two bases, so the map stays team-fair. With
## symmetry-lock on, every add/drag/delete keeps a point and its mirror partner in step (river
## vertices pair by order, end-to-end; camps/towers pair by position; an on-axis point is
## its own mirror). The two lanes (LaneT, LaneB) are polylines like the river; each is its own
## mirror across the axis. Lane endpoints are not pinned to the nexus — line them up by eye.

const VIEW := 10560.0  # default world units the orthographic camera frames (past the 9600 bounds)
const SNAP := 50.0  # grid step a placed/dragged point snaps to when snap is on
const GRAB := 312.0  # world-unit radius within which a click grabs an existing point
const INSERT_DIST := 288.0  # how close to a river segment a click must be to insert a vertex
const PAIR_EPS := 192.0  # how close a point must sit to another's mirror to count as its partner
const AXIS_EPS := 2.0  # |x - y| under which a point counts as sitting on the y=x axis
const ZOOM_MIN := 2160.0
const ZOOM_MAX := 17280.0
const ZOOM_STEP := 1.12
const UNDO_MAX := 120
const MAP_PATH := "res://src/sim/map_data.gd"

# The editable layers, in number-key order. `add` is false for layers with a fixed membership
# (the two bases) — those points can be dragged but not created or deleted. `const_name` is the
# MapData const the layer writes back to.
# `poly` layers are ordered polylines (river, lanes): drawn as a connected line, numbered, with
# click-on-segment insert, and — under symmetry-lock — self-mirrored end-to-end. The rest are
# point sets that pair by position. `add` is false for fixed-membership layers (the two bases).
const LAYERS := [
	{"key": "river", "label": "River", "const_name": "RIVER", "add": true, "poly": true,
		"color": Color(0.30, 0.55, 0.85)},
	{"key": "camps", "label": "Camps", "const_name": "JUNGLE_CAMPS", "add": true,
		"color": Color(0.40, 0.70, 0.45)},
	{"key": "nexus", "label": "Nexus", "const_name": "NEXUS_POSITIONS", "add": false,
		"color": Color(0.85, 0.50, 0.85)},
	{"key": "towers", "label": "Towers", "const_name": "TOWER_SLOTS", "add": true,
		"color": Color(0.80, 0.40, 0.40)},
	{"key": "lane_t", "label": "LaneT", "const_name": "LANE_TOP", "add": true, "poly": true,
		"color": Color(0.72, 0.62, 0.40)},
	{"key": "lane_b", "label": "LaneB", "const_name": "LANE_BOTTOM", "add": true, "poly": true,
		"color": Color(0.55, 0.62, 0.42)},
]

var _cam: Camera3D
var _world: Node3D
var _decor: Node3D  # everything redrawn each frame lives under here
var _hud: RichTextLabel

var _model := {}  # layer key -> Array[Vector2], the live geometry being edited
var _layer := 0  # index into LAYERS of the active layer
var _drag := -1  # index of the point being dragged in the active layer, or -1
var _snap_on := true
var _ghost_on := true
var _sym_on := true  # symmetry-lock: keep each point and its axial mirror in step
var _undo: Array = []  # stack of whole-model snapshots for Z

var _prev_keys := {}
var _was_left := false
var _was_right := false
var _was_mid := false
var _last_px := Vector2.ZERO


func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(1000, 1000))
	DisplayServer.window_set_title("Theria — map editor")
	_world = Node3D.new()
	get_root().add_child(_world)

	# Overhead orthographic camera: sim x reads as screen-x, sim y as screen-down, matching a
	# top-down map on paper and tools/map_shot.gd.
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = VIEW
	_cam.position = Vector3(0.0, 6000.0, 0.0)
	_cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_cam.far = 20000.0
	_world.add_child(_cam)
	_cam.make_current()

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_world.add_child(light)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = MapData.BOUNDS.size
	ground.mesh = plane
	ground.material_override = _mat(Color(0.12, 0.13, 0.15))
	_world.add_child(ground)

	_decor = Node3D.new()
	_world.add_child(_decor)

	var layer2d := CanvasLayer.new()
	get_root().add_child(layer2d)
	_hud = RichTextLabel.new()
	_hud.bbcode_enabled = true
	_hud.scroll_active = false
	_hud.autowrap_mode = TextServer.AUTOWRAP_OFF  # keep the layer tabs on one line
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE  # never eat clicks/wheel under the HUD
	_hud.position = Vector2(12.0, 8.0)
	_hud.size = Vector2(980.0, 140.0)
	_hud.add_theme_font_size_override("normal_font_size", 16)
	_hud.add_theme_font_size_override("bold_font_size", 16)
	layer2d.add_child(_hud)

	# A tiny node that catches discrete mouse-wheel events for zoom — the SceneTree script
	# itself does not receive input events, so this forwards them back to us.
	var wheel := WheelCatcher.new()
	wheel.editor = self
	get_root().add_child(wheel)

	_load_model()
	print("map editor — 1..5 layer | click add/drag/insert | right delete | S sym | Z undo | W write")


## Copies the MapData consts into the mutable in-memory model so editing never touches the
## stored geometry until W writes it back.
func _load_model() -> void:
	_model["river"] = _copy(MapData.RIVER)
	_model["camps"] = _copy(MapData.JUNGLE_CAMPS)
	_model["nexus"] = _copy(MapData.NEXUS_POSITIONS)
	_model["towers"] = _copy(MapData.TOWER_SLOTS)
	_model["lane_t"] = _copy(MapData.LANE_TOP)
	_model["lane_b"] = _copy(MapData.LANE_BOTTOM)


## True if `key` is an ordered polyline (river or a lane): drawn connected, numbered, with
## click-on-segment insert and end-to-end self-mirroring.
func _poly(key: String) -> bool:
	for layer in LAYERS:
		if layer["key"] == key:
			return layer.get("poly", false)
	return false


## True if `key`'s points pair by order rather than by position — the polylines (self-mirror,
## end to end) and the nexus pair (the two bases).
func _ordered(key: String) -> bool:
	return key == "nexus" or _poly(key)


func _copy(points: Array) -> Array:
	var out := []
	for p in points:
		out.append(p)
	return out


func _process(_delta: float) -> bool:
	_handle_keys()
	_handle_mouse()
	_handle_camera()
	_redraw()
	_update_hud()
	return false  # keep the editor running; the window close / ESC quits it


# --- input -------------------------------------------------------------------------------------

func _handle_keys() -> void:
	for i in LAYERS.size():
		if _tap(KEY_1 + i):
			_layer = i
			_drag = -1
	if _tap(KEY_G):
		_snap_on = not _snap_on
	if _tap(KEY_H):
		_ghost_on = not _ghost_on
	if _tap(KEY_S):
		_sym_on = not _sym_on
	if _tap(KEY_A):
		_axis_snap()
	if _tap(KEY_Z):
		_undo_last()
	if _tap(KEY_R):
		_cam.size = VIEW
		_cam.position = Vector3(0.0, 6000.0, 0.0)
	if _tap(KEY_W):
		_write_back()
	if _tap(KEY_ESCAPE):
		quit()


func _handle_mouse() -> void:
	var world := _cursor_world()
	var points: Array = _active_points()
	var key: String = _active_layer()["key"]

	var left := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if left and not _was_left:
		var hit := _nearest(points, world)
		if hit >= 0:
			_push_undo()
			_drag = hit
		elif _poly(key):
			_push_undo()
			var seg := _nearest_segment(points, world)
			if seg >= 0:
				_drag = _river_insert(points, seg, _place(world))
			else:
				_drag = _add(points, key, _place(world))
		elif _active_layer()["add"]:
			_push_undo()
			_drag = _add(points, key, _place(world))
	elif left and _drag >= 0:
		var newpos := _place(world)
		var partner := _partner(points, _drag, key) if _sym_on else -1
		points[_drag] = newpos
		if _sym_on and partner >= 0 and partner != _drag and not _on_axis(newpos):
			points[partner] = _mirror(newpos)
	elif not left:
		_drag = -1
	_was_left = left

	var right := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if right and not _was_right and _active_layer()["add"]:
		var hit := _nearest(points, world)
		if hit >= 0:
			_push_undo()
			_delete(points, key, hit)
			_drag = -1
	_was_right = right


## Mouse-wheel zoom and middle-button drag-to-pan. Both leave the camera looking straight down,
## so the cursor-to-world mapping stays correct.
func _handle_camera() -> void:
	var mid := Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
	var px := get_root().get_mouse_position()
	if mid and _was_mid:
		var per_px := _cam.size / float(get_root().size.y)
		var d := px - _last_px
		_cam.position.x -= d.x * per_px
		_cam.position.z -= d.y * per_px
	_last_px = px
	_was_mid = mid


func _zoom(dir: int) -> void:
	var f := ZOOM_STEP if dir > 0 else 1.0 / ZOOM_STEP
	_cam.size = clampf(_cam.size * f, ZOOM_MIN, ZOOM_MAX)


# --- editing model -----------------------------------------------------------------------------

## Adds a point to a layer. With symmetry-lock on, an off-axis point gets its mirror partner too:
## a river point is mirrored at the far end of the polyline (keeping the end-to-end pairing), a
## point-set point gets a mirrored twin. Returns the index of the user's own point.
func _add(points: Array, key: String, p: Vector2) -> int:
	if _poly(key):
		points.append(p)
		if _sym_on and not _on_axis(p):
			points.insert(0, _mirror(p))  # mirror at the opposite end keeps i <-> last-i
		return points.size() - 1
	points.append(p)
	var idx := points.size() - 1
	if _sym_on and not _on_axis(p):
		points.append(_mirror(p))
	return idx


## Inserts a vertex into the river polyline on segment `seg` (between seg and seg+1). With
## symmetry-lock on, the mirror vertex is inserted on the mirrored segment so the end-to-end
## pairing survives. Returns the index of the user's own new vertex.
func _river_insert(points: Array, seg: int, p: Vector2) -> int:
	if not _sym_on or _on_axis(p):
		points.insert(seg + 1, p)
		return seg + 1
	var mseg := points.size() - 2 - seg  # lower index of the mirrored segment
	var mp := _mirror(p)
	if seg <= mseg:
		points.insert(mseg + 1, mp)  # insert the higher index first so the lower stays valid
		points.insert(seg + 1, p)
		return seg + 1
	points.insert(seg + 1, p)
	points.insert(mseg + 1, mp)
	return seg + 2  # the mirror insert below seg+1 shifted our vertex up by one


## Deletes a point from a layer, taking its mirror partner with it when symmetry-lock is on.
func _delete(points: Array, key: String, i: int) -> void:
	if _ordered(key):
		var j := points.size() - 1 - i
		points.remove_at(i)
		if _sym_on and j != i:
			points.remove_at(j - 1 if j > i else j)
		return
	var m := _mirror(points[i])
	points.remove_at(i)
	if _sym_on:
		var p := _index_near(points, m, PAIR_EPS)
		if p >= 0:
			points.remove_at(p)


## Snaps the point under the cursor onto the y=x axis (its closest point on the line). Leaves any
## mirror partner alone — on-axis points are their own mirror, so a stray twin can be deleted by
## hand if symmetry-lock had made one.
func _axis_snap() -> void:
	var points := _active_points()
	var i := _nearest(points, _cursor_world())
	if i < 0:
		return
	_push_undo()
	var p: Vector2 = points[i]
	var c := (p.x + p.y) * 0.5
	points[i] = _place(Vector2(c, c))


## The index of `i`'s mirror partner in `points`, or -1. River and nexus pair by order (the
## point and its end-to-end opposite); the others pair by position (the point nearest `i`'s
## mirror). A point that is its own partner returns -1.
func _partner(points: Array, i: int, key: String) -> int:
	if _ordered(key):
		var j := points.size() - 1 - i
		return j if j != i else -1
	return _index_near_except(points, _mirror(points[i]), PAIR_EPS, i)


func _mirror(p: Vector2) -> Vector2:
	return Vector2(p.y, p.x)  # reflection across the line y = x


func _on_axis(p: Vector2) -> bool:
	return absf(p.x - p.y) < AXIS_EPS


func _push_undo() -> void:
	var snap := {}
	for k in _model:
		snap[k] = _model[k].duplicate()
	_undo.append(snap)
	if _undo.size() > UNDO_MAX:
		_undo.pop_front()


func _undo_last() -> void:
	if _undo.is_empty():
		return
	_model = _undo.pop_back()
	_drag = -1


# --- geometry queries --------------------------------------------------------------------------

## The cursor's position on the ground plane (y = 0), from the camera ray under the mouse.
func _cursor_world() -> Vector2:
	var m := get_root().get_mouse_position()
	var from := _cam.project_ray_origin(m)
	var dir := _cam.project_ray_normal(m)
	if absf(dir.y) < 0.00001:
		return Vector2.ZERO
	var t := -from.y / dir.y
	var p := from + dir * t
	return Vector2(p.x, p.z)


## A cursor position resolved to where a point should sit: snapped to the grid (if on) and
## clamped inside the playable bounds.
func _place(w: Vector2) -> Vector2:
	var p := w
	if _snap_on:
		p = Vector2(roundf(p.x / SNAP) * SNAP, roundf(p.y / SNAP) * SNAP)
	return MapData.clamp_to_bounds(p)


## Index of the point within `GRAB` reach of the cursor, nearest first, or -1.
func _nearest(points: Array, cursor: Vector2) -> int:
	return _index_near(points, cursor, GRAB)


func _index_near(points: Array, target: Vector2, radius: float) -> int:
	return _index_near_except(points, target, radius, -1)


func _index_near_except(points: Array, target: Vector2, radius: float, skip: int) -> int:
	var best := -1
	var best_d := radius
	for i in points.size():
		if i == skip:
			continue
		var d: float = points[i].distance_to(target)
		if d <= best_d:
			best_d = d
			best = i
	return best


## Index of the river segment (seg..seg+1) within `INSERT_DIST` of the cursor, nearest first, or
## -1 — where a click splits the polyline rather than extending it.
func _nearest_segment(points: Array, cursor: Vector2) -> int:
	var best := -1
	var best_d := INSERT_DIST
	for k in points.size() - 1:
		var d := _segment_distance(points[k], points[k + 1], cursor)
		if d <= best_d:
			best_d = d
			best = k
	return best


func _segment_distance(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	var t := 0.0 if len2 <= 0.0 else clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _active_layer() -> Dictionary:
	return LAYERS[_layer]


func _active_points() -> Array:
	return _model[_active_layer()["key"]]


# --- drawing -----------------------------------------------------------------------------------

## Clears and rebuilds every visual each frame: grid, axis, bounds, reference lanes, all layers'
## points, the active layer's draggable handles + indices, and the mirror ghosts. Cheap enough
## for a few dozen nodes; redrawing live keeps hover and drag responsive.
func _redraw() -> void:
	for c in _decor.get_children():
		c.free()

	_grid()
	_axis()
	_bounds()

	var cursor := _cursor_world()
	for i in LAYERS.size():
		var layer: Dictionary = LAYERS[i]
		var points: Array = _model[layer["key"]]
		var active: bool = i == _layer
		var poly: bool = layer.get("poly", false)
		if poly:
			_polyline(points, 72.0, layer["color"].darkened(0.2))
		var hover := _nearest(points, cursor) if active else -1
		for j in points.size():
			var radius := 180.0 if active else 108.0
			var color: Color = Color(1.0, 0.95, 0.4) if active and j == hover else layer["color"]
			_disc(points[j], radius, color, 6.0 if active else 3.0)
			if active and poly:
				_index(points[j], j)
		# The ghost previews the predicted mirror only when symmetry-lock is off — with it on the
		# mirror points are real, so a ghost would just double them.
		if active and _ghost_on and not _sym_on:
			for p in points:
				if not _on_axis(p):
					_disc(_mirror(p), 144.0, layer["color"], 4.0, 0.30)


## The coordinate grid: a faint line every 500 units, brighter through the origin — so a spot
## on screen maps back to MapData numbers.
func _grid() -> void:
	for k in range(-4800, 4801, 1200):
		var major := k == 0
		var color := Color(0.45, 0.45, 0.52) if major else Color(0.20, 0.21, 0.25)
		var w := 24.0 if major else 7.0
		_strip(Vector3(float(k), 1.0, 0.0), Vector3(w, 1.0, 9600.0), color)
		_strip(Vector3(0.0, 1.0, float(k)), Vector3(9600.0, 1.0, w), color)


## The mirror axis: the TL-BR diagonal (sim y = x), drawn bright so the symmetry reads.
func _axis() -> void:
	var diag := sqrt(2.0) * 9600.0
	var strip := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(24.0, 1.0, diag)
	strip.mesh = box
	strip.material_override = _mat(Color(0.85, 0.75, 0.35))
	strip.position = Vector3(0.0, 1.5, 0.0)
	strip.rotation.y = deg_to_rad(45.0)  # along (−2000,−2000)→(2000,2000)
	_decor.add_child(strip)


## The playable-bounds outline, so the map edges read.
func _bounds() -> void:
	var b := MapData.BOUNDS
	var color := Color(0.35, 0.35, 0.40)
	_strip(Vector3(b.position.x, 1.0, b.get_center().y), Vector3(20.0, 1.0, b.size.y), color)
	_strip(Vector3(b.end.x, 1.0, b.get_center().y), Vector3(20.0, 1.0, b.size.y), color)
	_strip(Vector3(b.get_center().x, 1.0, b.position.y), Vector3(b.size.x, 1.0, 20.0), color)
	_strip(Vector3(b.get_center().x, 1.0, b.end.y), Vector3(b.size.x, 1.0, 20.0), color)


## Draws a polyline as a ribbon of connected segments — the river course or a reference lane.
func _polyline(points: Array, width: float, color: Color) -> void:
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var delta := b - a
		var length := delta.length()
		if length <= 0.0:
			continue
		var strip := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(width, 1.0, length)
		strip.mesh = box
		strip.material_override = _mat(color)
		var mid := (a + b) * 0.5
		strip.position = Vector3(mid.x, 2.0, mid.y)
		strip.rotation.y = atan2(delta.x, delta.y)
		_decor.add_child(strip)


func _strip(pos: Vector3, size: Vector3, color: Color) -> void:
	var strip := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	strip.mesh = box
	strip.material_override = _mat(color)
	strip.position = pos
	_decor.add_child(strip)


func _disc(pos: Vector2, radius: float, color: Color, lift := 3.0, alpha := 1.0) -> void:
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 1.0
	disc.mesh = cyl
	disc.material_override = _mat(Color(color.r, color.g, color.b, alpha))
	disc.position = Vector3(pos.x, lift, pos.y)
	_decor.add_child(disc)


func _index(pos: Vector2, n: int) -> void:
	var label := Label3D.new()
	label.text = str(n)
	label.font_size = 216
	label.modulate = Color.WHITE
	label.position = Vector3(pos.x, 10.0, pos.y)
	label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_decor.add_child(label)


func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


## The on-screen overlay: the layer tabs (each in its own colour, the active one bold), a live
## coordinate readout of the cursor and the hovered point, the toggle states, and the controls.
func _update_hud() -> void:
	var tabs := PackedStringArray()
	for i in LAYERS.size():
		var layer: Dictionary = LAYERS[i]
		var hexc: String = layer["color"].to_html(false)
		var name := "%d %s(%d)" % [i + 1, layer["label"], _model[layer["key"]].size()]
		if i == _layer:
			tabs.append("[b][color=#%s]▸%s[/color][/b]" % [hexc, name])
		else:
			tabs.append("[color=#%s]%s[/color]" % [hexc, name])

	var points := _active_points()
	var cur := _place(_cursor_world())
	var read := "cursor (%d, %d)" % [int(cur.x), int(cur.y)]
	var hi := _nearest(points, _cursor_world())
	if hi >= 0:
		read += "    point[%d] (%d, %d)" % [hi, int(points[hi].x), int(points[hi].y)]

	var flags := "sym %s(S)  snap %s(G)  ghost %s(H)" % [
		_onoff(_sym_on), _onoff(_snap_on), _onoff(_ghost_on)
	]
	var ctl := "click add/drag | click line=insert | right-del | A axis | Z undo"
	var ctl2 := "wheel/middrag/R camera | W write | ESC quit"
	_hud.text = "  ".join(tabs) + "\n" + read + "\n" + flags + "\n" + ctl + "  |  " + ctl2


func _onoff(b: bool) -> String:
	return "ON" if b else "off"


# --- write-back --------------------------------------------------------------------------------

## Writes every layer back into the matching const in map_data.gd, after saving a .bak. Each
## const is rewritten body-only: the `## doc` block and the `const … = [` / `]` lines are kept,
## and the element lines between them are replaced with the live points. (Per-element inline
## comments inside an array are not preserved — re-add any once the shape is final.)
func _write_back() -> void:
	var f := FileAccess.open(MAP_PATH, FileAccess.READ)
	if f == null:
		push_error("map editor: cannot read %s" % MAP_PATH)
		return
	var src := f.get_as_text()
	f.close()

	var bak := FileAccess.open(MAP_PATH + ".bak", FileAccess.WRITE)
	bak.store_string(src)
	bak.close()

	for layer in LAYERS:
		src = _replace_const(src, layer["const_name"], _model[layer["key"]])

	var w := FileAccess.open(MAP_PATH, FileAccess.WRITE)
	w.store_string(src)
	w.close()
	print("map editor: wrote %s (backup: map_data.gd.bak)" % MAP_PATH)


## Replaces the element lines of `const <name>: Array[Vector2] = [ … ]` with `points`, keeping
## the declaration line, the closing `]`, and everything outside the array untouched.
func _replace_const(src: String, name: String, points: Array) -> String:
	var lines := src.split("\n")
	var start := -1
	for i in lines.size():
		if lines[i].strip_edges().begins_with("const " + name):
			start = i
			break
	if start == -1:
		push_warning("map editor: const %s not found — skipped" % name)
		return src
	var endi := -1
	for i in range(start + 1, lines.size()):
		if lines[i].strip_edges() == "]":
			endi = i
			break
	if endi == -1:
		push_warning("map editor: closing ] for %s not found — skipped" % name)
		return src

	var out := PackedStringArray()
	for i in start + 1:  # keep lines 0..start (the doc block + the `= [` line)
		out.append(lines[i])
	for p in points:
		out.append("\tVector2(%s, %s)," % [_num(p.x), _num(p.y)])
	for i in range(endi, lines.size()):  # keep the `]` and everything after
		out.append(lines[i])
	return "\n".join(out)


func _num(v: float) -> String:
	return "%.1f" % v


# --- input edge detection ----------------------------------------------------------------------

## True only on the frame `code` transitions from up to down — so a held key fires once.
func _tap(code: int) -> bool:
	var down := Input.is_physical_key_pressed(code)
	var was: bool = _prev_keys.get(code, false)
	_prev_keys[code] = down
	return down and not was


## Catches discrete mouse-wheel events (which have no held state to poll) and forwards them to
## the editor as zoom. The SceneTree script gets no input events itself; a node in the tree does.
class WheelCatcher:
	extends Node

	var editor

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				editor._zoom(-1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				editor._zoom(1)
