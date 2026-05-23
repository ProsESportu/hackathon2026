extends Node3D
## Spawns a constellation of satellites that follow Earth (via EarthFrame),
## reveals/hides them on orbit entry/exit, slowly revolves them, and emits
## proximity signals so the HUD can show a "Press X to play" prompt.

signal satellite_in_range(satellite: Node3D)
signal satellite_out_of_range
signal minigame_requested(satellite: Node3D)

const SUN_PATH:           NodePath = ^"../../Słońce"
const PLAYER_PATH:        NodePath = ^"../../PlayerSat"
const ORBIT_MANAGER_PATH: NodePath = ^"../../OrbitManager"

const SATELLITE_SCENE: PackedScene = preload("res://scenes/satelite.tscn")

const SAT_COUNT: int = 12
const SAT_ORBIT_RADIUS: float = 0.72   # between PROXIMITY_WARN (0.61) and ORBIT_ENTER (0.80)
const REVOLUTION_RAD_PER_SEC: float = 0.05

const INTERACT_ENTER_RADIUS: float = 0.08
const INTERACT_EXIT_RADIUS:  float = 0.11  # hysteresis band

enum State { IN_SPACE, IN_ORBIT }

var state: State = State.IN_SPACE
var _satellites: Array[Node3D] = []
var _current_target: Node3D = null

var sun: Node3D
var player: Node3D


func _ready() -> void:
	sun = get_node(SUN_PATH)
	player = get_node(PLAYER_PATH)

	var orbit_manager: Node = get_node(ORBIT_MANAGER_PATH)
	orbit_manager.orbit_entered.connect(_on_orbit_entered)
	orbit_manager.orbit_exited.connect(_on_orbit_exited)

	InputBridge.interact_pressed.connect(_on_interact_pressed)

	_spawn_satellites()


func _process(delta: float) -> void:
	rotate_y(REVOLUTION_RAD_PER_SEC * delta)
	if state == State.IN_ORBIT:
		_update_proximity()


# --- Spawning ----------------------------------------------------------------

# Fibonacci-sphere distribution: uniform spread, no pole clustering.
func _spawn_satellites() -> void:
	var golden_angle: float = PI * (3.0 - sqrt(5.0))
	for i in range(SAT_COUNT):
		var y: float = 1.0 - (float(i) / float(SAT_COUNT - 1)) * 2.0
		var radius_at_y: float = sqrt(max(0.0, 1.0 - y * y))
		var theta: float = golden_angle * float(i)
		var pos: Vector3 = Vector3(
			cos(theta) * radius_at_y,
			y,
			sin(theta) * radius_at_y
		) * SAT_ORBIT_RADIUS

		var sat: Node3D = SATELLITE_SCENE.instantiate()
		sat.set_sun(sun)
		sat.visible = false
		sat.position = pos
		add_child(sat)
		_satellites.append(sat)


# --- Orbit state handlers ----------------------------------------------------

func _on_orbit_entered() -> void:
	state = State.IN_ORBIT
	for sat in _satellites:
		sat.visible = true


func _on_orbit_exited() -> void:
	state = State.IN_SPACE
	for sat in _satellites:
		sat.visible = false
	if _current_target != null:
		_current_target = null
		satellite_out_of_range.emit()


# --- Proximity ---------------------------------------------------------------

func _update_proximity() -> void:
	var player_pos: Vector3 = player.global_position
	var nearest: Node3D = null
	var nearest_dist: float = INF
	for sat in _satellites:
		var d: float = player_pos.distance_to(sat.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = sat

	if _current_target == null:
		if nearest_dist < INTERACT_ENTER_RADIUS:
			_current_target = nearest
			satellite_in_range.emit(nearest)
	else:
		# Stay locked on _current_target until the player drifts past its exit radius.
		var target_dist: float = player_pos.distance_to(_current_target.global_position)
		if target_dist > INTERACT_EXIT_RADIUS:
			_current_target = null
			satellite_out_of_range.emit()
			# Allow a different satellite to grab focus immediately if the player
			# happens to already be inside another one's enter radius.
			if nearest != null and nearest_dist < INTERACT_ENTER_RADIUS:
				_current_target = nearest
				satellite_in_range.emit(nearest)


# --- Interaction -------------------------------------------------------------

func _on_interact_pressed() -> void:
	if state != State.IN_ORBIT or _current_target == null:
		return
	print("[SatelliteSpawner] minigame requested for ", _current_target.name)
	minigame_requested.emit(_current_target)
