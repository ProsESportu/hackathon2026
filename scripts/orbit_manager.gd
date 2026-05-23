extends Node
## Owns the player's "in space vs in Earth orbit" state machine.
## Each frame:
##  - mirrors Earth's world position onto EarthFrame (identity rotation, so the
##    player isn't dragged by Earth's spin animation when reparented under it),
##  - computes Earth's world velocity numerically (animation, not physics),
##  - checks player distance to Earth and triggers reparent + velocity correction
##    on state transitions with hysteresis to prevent boundary flicker.
##
## Signals are emitted for the HUD (Step 5) to consume; until the HUD exists
## we print transitions for verification.

signal orbit_entered
signal orbit_exit_warning
signal orbit_exited
signal proximity_alert_started
signal proximity_alert_cleared

const ORBIT_ENTER_RADIUS: float = 0.80
const ORBIT_EXIT_RADIUS:  float = 0.95
const ORBIT_WARN_RADIUS:  float = 0.88
const PROXIMITY_WARN_RADIUS:  float = 0.61   # ~0.10 above Earth surface
const PROXIMITY_CLEAR_RADIUS: float = 0.64   # hysteresis band (0.03 wide)

const EARTH_PATH:       NodePath = ^"../Słońce/ziemia axis/Ziemia"
const EARTH_FRAME_PATH: NodePath = ^"../EarthFrame"
const PLAYER_PATH:      NodePath = ^"../PlayerSat"

enum State { IN_SPACE, IN_ORBIT }

var state: State = State.IN_SPACE
var warned_this_orbit: bool = false
var _proximity_active: bool = false

var earth: Node3D
var earth_frame: Node3D
var player: Node3D
var original_player_parent: Node

var _earth_prev_pos: Vector3 = Vector3.ZERO
var earth_velocity_world: Vector3 = Vector3.ZERO


func _ready() -> void:
	earth = get_node(EARTH_PATH)
	earth_frame = get_node(EARTH_FRAME_PATH)
	player = get_node(PLAYER_PATH)
	original_player_parent = player.get_parent()
	_earth_prev_pos = earth.global_position
	earth_frame.global_position = earth.global_position


func _process(delta: float) -> void:
	# Track Earth in idle (same tick as AnimationPlayer) so the parented
	# player doesn't lag behind Earth visually.
	var earth_pos: Vector3 = earth.global_position
	if delta > 0.0:
		earth_velocity_world = (earth_pos - _earth_prev_pos) / delta
	_earth_prev_pos = earth_pos
	earth_frame.global_position = earth_pos

	var dist: float = player.global_position.distance_to(earth_pos)

	match state:
		State.IN_SPACE:
			if dist < ORBIT_ENTER_RADIUS:
				_enter_orbit()
		State.IN_ORBIT:
			if dist > ORBIT_EXIT_RADIUS:
				_exit_orbit()
			elif dist > ORBIT_WARN_RADIUS and not warned_this_orbit:
				warned_this_orbit = true
				print("[OrbitManager] WARNING: leaving orbit (dist=", "%.3f" % dist, ")")
				orbit_exit_warning.emit()
			elif dist < ORBIT_WARN_RADIUS and warned_this_orbit:
				# Dipped back in; allow warning to fire again next time.
				warned_this_orbit = false
			if dist < PROXIMITY_WARN_RADIUS and not _proximity_active:
				_proximity_active = true
				proximity_alert_started.emit()
			elif dist > PROXIMITY_CLEAR_RADIUS and _proximity_active:
				_proximity_active = false
				proximity_alert_cleared.emit()


func _enter_orbit() -> void:
	state = State.IN_ORBIT
	warned_this_orbit = false
	player.reparent(earth_frame, true)
	if player.has_method("on_orbit_entered"):
		player.on_orbit_entered(earth_velocity_world)
	print("[OrbitManager] ENTERED orbit (earth_vel=", earth_velocity_world, ")")
	orbit_entered.emit()


func _exit_orbit() -> void:
	state = State.IN_SPACE
	warned_this_orbit = false
	if _proximity_active:
		_proximity_active = false
		proximity_alert_cleared.emit()
	player.reparent(original_player_parent, true)
	if player.has_method("on_orbit_exited"):
		player.on_orbit_exited(earth_velocity_world)
	print("[OrbitManager] EXITED orbit (earth_vel=", earth_velocity_world, ")")
	orbit_exited.emit()
