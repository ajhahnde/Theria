extends SceneTree
## Top-down map preview: renders the map straight overhead and saves it as a PNG, so the
## map can be reshaped by editing MapData coordinates and seeing the result without playing.
##
## Run it:
##   godot --path . -s tools/map_shot.gd
## then open the written file (printed at the end). Edit src/sim/map_data.gd, run again.

const IMG := 1200  # output is a square IMG x IMG png
const VIEW := 10080.0  # world units the camera frames (a touch past the 9600-wide bounds)
const OUT := "res://map_preview.png"

var _frames := 0


func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(IMG, IMG))
	var world := Node3D.new()
	get_root().add_child(world)

	# A flat overhead orthographic camera: x stays x, the sim's y reads as screen-down,
	# so the picture matches a top-down map drawn on paper.
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = VIEW
	cam.position = Vector3(0.0, 6000.0, 0.0)
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	cam.far = 20000.0
	world.add_child(cam)
	cam.make_current()

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	world.add_child(light)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = MapData.BOUNDS.size
	ground.mesh = plane
	ground.material_override = _mat(Color(0.12, 0.13, 0.15))
	world.add_child(ground)

	# A coordinate grid under everything: a faint line every 500 world units and a brighter
	# pair through the origin, so a spot in the picture maps back to the numbers in MapData.
	_grid(world)

	# The real map decor (lanes, river, camps) drawn by the same code the game uses,
	# plus a marker on each nexus so the bases read.
	MapView.build(world)
	for team in MapData.NEXUS_POSITIONS.size():
		var color := Color(0.30, 0.60, 1.0) if team == 0 else Color(1.0, 0.42, 0.38)
		_disc(world, MapData.nexus_for_team(team), 360.0, color)
		for tower in MapData.tower_positions(team):
			_disc(world, tower, 168.0, color.darkened(0.3))


## Waits a few frames so the scene is drawn, then grabs the framebuffer and saves it.
func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false
	var image := get_root().get_texture().get_image()
	image.save_png(OUT)
	print("map preview saved -> ", ProjectSettings.globalize_path(OUT))
	return true


## Draws the coordinate grid: a faint strip every 500 units along both axes, the origin pair
## brighter, plus a label at each axis end so the numbers are readable off the picture.
func _grid(parent: Node3D) -> void:
	for k in range(-4800, 4801, 1200):
		var major := k == 0
		var color := Color(0.55, 0.55, 0.62) if major else Color(0.22, 0.23, 0.27)
		var width := 29.0 if major else 10.0
		_strip(parent, Vector3(float(k), 1.0, 0.0), Vector3(width, 1.0, 9600.0), color)
		_strip(parent, Vector3(0.0, 1.0, float(k)), Vector3(9600.0, 1.0, width), color)
	_label(parent, Vector3(4440.0, 8.0, 216.0), "+x")
	_label(parent, Vector3(216.0, 8.0, 4440.0), "+y")


func _strip(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var strip := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	strip.mesh = box
	strip.material_override = _mat(color)
	strip.position = pos
	parent.add_child(strip)


func _label(parent: Node3D, pos: Vector3, text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 312
	label.position = pos
	label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	parent.add_child(label)


func _disc(parent: Node3D, pos: Vector2, radius: float, color: Color) -> void:
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 1.0
	disc.mesh = cyl
	disc.material_override = _mat(color)
	disc.position = Vector3(pos.x, 5.0, pos.y)
	parent.add_child(disc)


func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat
