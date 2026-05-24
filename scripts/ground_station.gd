extends Node

## Stalowa Wola ground station: detects when any satellite is overhead,
## drives a pulsing uplink beam on the Earth surface, and emits signals
## that Phase 2 (cosmic lottery) can consume for the x2 multiplier.

signal overhead_started
signal overhead_stopped

const SW_LAT_DEG: float = 50.5826
const SW_LON_DEG: float = 22.0533
# Earth mesh texture is rotationally offset from game-ECEF; tweak this if the
# marker lands in the wrong country.
const MESH_LON_OFFSET_DEG: float = 95.0
const EARTH_SURFACE_R: float = 0.515
const OVERHEAD_ANGLE_DEG: float = 15.0

const EARTH_PATH: NodePath  = ^"../Słońce/ziemia axis/Ziemia"
const EARTH_FRAME_PATH: NodePath = ^"../EarthFrame"
const SPAWNER_PATH: NodePath = ^"../EarthFrame/SatelliteSpawner"

var _sw_dir: Vector3
var _overhead_dot: float
var _is_overhead: bool = false

var _earth_frame: Node3D
var _satellite_spawner: Node
var _beam_mat: StandardMaterial3D
var _beam_tween: Tween


func _ready() -> void:
	var lat := deg_to_rad(SW_LAT_DEG)
	var lon := deg_to_rad(SW_LON_DEG - MESH_LON_OFFSET_DEG)
	_sw_dir = Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)).normalized()
	_overhead_dot = cos(deg_to_rad(OVERHEAD_ANGLE_DEG))

	_earth_frame = get_node(EARTH_FRAME_PATH)
	_satellite_spawner = get_node(SPAWNER_PATH)

	var ziemia: Node3D = get_node(EARTH_PATH)
	_build_marker(ziemia)
	_restart_beam_pulse(false)


func _build_marker(ziemia: Node3D) -> void:
	# Marker root: local +Y = surface normal (radially outward).
	var marker := Node3D.new()
	marker.name = "StalowaWolaMarker"

	var m_up := _sw_dir  # already normalized
	var ref := Vector3.RIGHT if abs(m_up.dot(Vector3.UP)) > 0.9 else Vector3.UP
	var m_fwd := m_up.cross(ref).normalized()
	var m_right := m_fwd.cross(m_up).normalized()
	marker.transform = Transform3D(Basis(m_right, m_up, -m_fwd), _sw_dir * EARTH_SURFACE_R)
	ziemia.add_child(marker)

	# Glowing dot
	var dot := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.005
	sphere.height = 0.010
	dot.mesh = sphere
	var dot_mat := StandardMaterial3D.new()
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_mat.albedo_color = Color.CYAN
	dot_mat.emission_enabled = true
	dot_mat.emission = Color.CYAN
	dot_mat.emission_energy_multiplier = 4.0
	dot.material_override = dot_mat
	marker.add_child(dot)

	# Uplink beam: CylinderMesh height along local +Y (= outward normal).
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0008
	cyl.bottom_radius = 0.0020
	cyl.height = 0.14
	beam.mesh = cyl
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.albedo_color = Color(0.0, 1.0, 1.0, 0.15)
	_beam_mat.emission_enabled = true
	_beam_mat.emission = Color.CYAN
	_beam_mat.emission_energy_multiplier = 1.5
	beam.material_override = _beam_mat
	beam.position = Vector3(0.0, 0.07, 0.0)
	marker.add_child(beam)

	# Billboard label
	var lbl := Label3D.new()
	lbl.text = "STALOWA WOLA"
	lbl.font_size = 48
	lbl.pixel_size = 0.0008
	lbl.modulate = Color.CYAN
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.double_sided = true
	lbl.position = Vector3(0.0, 0.026, 0.0)
	marker.add_child(lbl)


func _process(_delta: float) -> void:
	var any_overhead := false
	for sat in _satellite_spawner.get_satellites():
		if not sat.visible:
			continue
		var to_sat: Vector3 = (sat.global_position - _earth_frame.global_position).normalized()
		if to_sat.dot(_sw_dir) >= _overhead_dot:
			any_overhead = true
			break

	if any_overhead and not _is_overhead:
		_is_overhead = true
		overhead_started.emit()
		_restart_beam_pulse(true)
	elif not any_overhead and _is_overhead:
		_is_overhead = false
		overhead_stopped.emit()
		_restart_beam_pulse(false)


func _restart_beam_pulse(active: bool) -> void:
	if _beam_mat == null:
		return
	if _beam_tween != null and _beam_tween.is_valid():
		_beam_tween.kill()
	_beam_tween = create_tween().set_loops()
	if active:
		_beam_tween.tween_property(_beam_mat, "albedo_color:a", 0.85, 0.18)
		_beam_tween.tween_property(_beam_mat, "albedo_color:a", 0.30, 0.18)
	else:
		_beam_tween.tween_property(_beam_mat, "albedo_color:a", 0.35, 0.9)
		_beam_tween.tween_property(_beam_mat, "albedo_color:a", 0.05, 0.9)


func is_overhead() -> bool:
	return _is_overhead
