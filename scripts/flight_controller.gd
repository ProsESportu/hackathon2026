extends Node3D
## 6-DoF arcade flight for the player satellite.
## Reads exclusively from the InputBridge autoload — never from Input directly.
## Constants mirror the web prototype's tuning (see CLAUDE.md "Quick reference").

const ROT_ACCEL: float = 2.8
const ROT_DAMP_PER_SEC: float = 0.04        # fraction of angular velocity retained per second
const THRUST_ACCEL: float = 0.1
const MAX_SPEED: float = 5              # ~16 km/s in scene units
const IN_ORBIT_THRUST_ACCEL: float = 0.001   # gentler push while inside Earth's orbital bubble
const IN_ORBIT_MAX_SPEED: float = 0.09       # so the player can't blitz through orbit and crash
const VEL_DAMP_PER_SEC: float = 0.985        # light drag
const BRAKE_DAMP_PER_SEC: float = 0.02       # Space = active brake (~98%/s velocity loss)
const EARTH_COLLISION_FLOOR: float = 1.015   # scene radius (Sun, at origin)
const EARTH_RADIUS: float = 0.51             # orbiting Earth surface (sphere radius 0.5 + buffer)
const ORBIT_ENTRY_DROP_RADIUS: float = 0.655 # midpoint between EARTH_RADIUS (0.51) and OrbitManager.ORBIT_ENTER_RADIUS (0.80)
const START_ALT_SCENE: float = 1.11          # ~700 km altitude in scene units
const FRAME_REF_HZ: float = 60.0             # prototype thrust was per-frame at 60 Hz
const ORBIT_MANAGER_PATH: NodePath = ^"OrbitManager"
@onready var game_over_screen: Control = %GameOverScreen

# Tracked state
var ang_vel: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var in_orbit: bool = false
var _game_over: bool = false
var _start_global_transform: Transform3D
var _start_parent: Node

@onready var earth: Node3D = get_node_or_null("../Słońce/ziemia axis/Ziemia")

func _ready() -> void:
	# Only nudge to a default orbit if the scene placed us at origin.
	if global_position.length() < 0.001:
		global_position = Vector3(0.0, 0.0, START_ALT_SCENE)
	_start_global_transform = global_transform
	_start_parent = get_parent()

func _process(delta: float) -> void:
	if _game_over:
		return
	_apply_mouse_look()
	_apply_angular_velocity(delta)
	_apply_thrust(delta)
	_integrate_position(delta)
	
func _apply_mouse_look() -> void:
	# Mouse rotates the body directly — no inertia, snappy aim.
	var look := InputBridge.consume_look()
	if look == Vector2.ZERO:
		return
	# Yaw around global up keeps horizon stable; pitch around local right.
	rotate_y(look.x)
	rotate_object_local(Vector3.RIGHT, look.y)

func _apply_angular_velocity(delta: float) -> void:
	# Rate axes (gyro pad, EEG jitter) feed angular accel with damping.
	var f: float = clamp(InputBridge.focus, 0.0, 1.0)
	var jitter: float = (1.0 - f) * 0.4
	ang_vel.x += (InputBridge.pitch * ROT_ACCEL + (randf() - 0.5) * jitter) * delta
	ang_vel.y += (InputBridge.yaw   * ROT_ACCEL + (randf() - 0.5) * jitter) * delta
	ang_vel.z += (InputBridge.roll  * ROT_ACCEL) * delta

	ang_vel *= pow(ROT_DAMP_PER_SEC, delta)

	if ang_vel.length_squared() > 0.0:
		rotate_object_local(Vector3.RIGHT,   ang_vel.x * delta)
		rotate_object_local(Vector3.UP,      ang_vel.y * delta)
		rotate_object_local(Vector3.FORWARD, ang_vel.z * delta)

func _apply_thrust(delta: float) -> void:
	var basis := global_transform.basis
	var fwd: Vector3 = -basis.z   # camera-forward in Godot
	var right: Vector3 = basis.x
	var up: Vector3 = basis.y

	var thrust_accel: float = IN_ORBIT_THRUST_ACCEL if in_orbit else THRUST_ACCEL
	var max_speed: float = IN_ORBIT_MAX_SPEED if in_orbit else MAX_SPEED

	var accel_dir: Vector3 = fwd * InputBridge.thrust + right * InputBridge.strafe + up * InputBridge.lift
	# Match the prototype's per-frame-at-60Hz feel: a = THRUST_ACCEL * 60 per second.
	velocity += accel_dir * (thrust_accel * FRAME_REF_HZ) * delta

	var sp: float = velocity.length()
	if sp > max_speed:
		velocity *= max_speed / sp
	velocity *= pow(VEL_DAMP_PER_SEC, delta)

	if InputBridge.brake:
		velocity *= pow(BRAKE_DAMP_PER_SEC, delta)

func _integrate_position(delta: float) -> void:
	# Local-space integration: when reparented under EarthFrame the player
	# automatically drifts with Earth, and `velocity` is interpreted in the
	# parent's frame. Under the scene root (identity transform) this is
	# equivalent to integrating global_position.
	position += velocity * delta

func on_orbit_entered(_earth_world_velocity: Vector3) -> void:
	in_orbit = true
	velocity = Vector3.ZERO
	var dir: Vector3 = position.normalized() if position.length() > 0.001 else Vector3.BACK
	position = dir * ORBIT_ENTRY_DROP_RADIUS

func on_orbit_exited(earth_world_velocity: Vector3) -> void:
	# Convert Earth-frame velocity back to world-relative.
	velocity += earth_world_velocity
	in_orbit = false


func _get_orbit_manager() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null(ORBIT_MANAGER_PATH)


func _trigger_game_over() -> void:
	if _game_over:
		return
	_game_over = true
	velocity = Vector3.ZERO
	ang_vel = Vector3.ZERO
	if game_over_screen != null:
		game_over_screen.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func reset_to_start() -> void:
	var orbit_manager := _get_orbit_manager()
	if orbit_manager != null and orbit_manager.has_method("force_exit_orbit"):
		orbit_manager.force_exit_orbit()
	if _start_parent != null and get_parent() != _start_parent:
		reparent(_start_parent, true)
	global_transform = _start_global_transform
	velocity = Vector3.ZERO
	ang_vel = Vector3.ZERO
	in_orbit = false
	_game_over = false
	if game_over_screen != null:
		game_over_screen.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _on_area_3d_body_entered(body: Node3D) -> void:
	# Phantom signals can fire when the player reparents into/out of EarthFrame
	# (Area3D re-registers in the physics server and re-emits body_entered for
	# anything in range). Only count it as a crash if we're geometrically inside
	# the body's ~0.5-radius collision sphere.
	if body == null:
		return
	var d: float = global_position.distance_to(body.global_position)
	var parent_name: String = get_parent().name if get_parent() != null else "<none>"
	print("[FlightController] body_entered: ", body.name, " dist=", "%.3f" % d, " parent=", parent_name)
	if d > 0.55:
		print("[FlightController]   -> ignored (outside surface threshold)")
		return
	_trigger_game_over()


func _on_button_pressed() -> void:
	reset_to_start()

func _enforce_earth_floor() -> void:
	var r: float = global_position.length()
	if r < EARTH_COLLISION_FLOOR:
		global_position = global_position.normalized() * EARTH_COLLISION_FLOOR
		velocity = Vector3.ZERO

func _enforce_earth_solid() -> void:
	if earth == null:
		return
	var to_player: Vector3 = global_position - earth.global_position
	var d: float = to_player.length()
	if d < EARTH_RADIUS:
		var dir: Vector3 = to_player / d if d > 0.0001 else Vector3.UP
		global_position = earth.global_position + dir * EARTH_RADIUS
		velocity = Vector3.ZERO
