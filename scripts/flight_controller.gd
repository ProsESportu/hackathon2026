extends Node3D

## 6-DoF arcade flight for the player satellite.
## Reads exclusively from the InputBridge autoload — never from Input directly.
## Constants mirror the web prototype's tuning (see CLAUDE.md "Quick reference").

const ROT_ACCEL: float = 2.8
const ROT_DAMP_PER_SEC: float = 0.04        # fraction of angular velocity retained per second
const THRUST_ACCEL: float = 0.1
const MAX_SPEED: float = 25              # ~16 km/s in scene units
const IN_ORBIT_THRUST_ACCEL: float = 0.01   # gentler push while inside Earth's orbital bubble
const IN_ORBIT_MAX_SPEED: float = 0.9       # so the player can't blitz through orbit and crash
const VEL_DAMP_PER_SEC: float = 0.985        # light drag
const BRAKE_DAMP_PER_SEC: float = 0.02       # Space = active brake (~98%/s velocity loss)
const EARTH_COLLISION_FLOOR: float = 1.015   # scene radius (Sun, at origin)
const EARTH_RADIUS: float = 0.51             # orbiting Earth surface (sphere radius 0.5 + buffer)
const ORBIT_ENTRY_DROP_RADIUS: float = 0.655 # midpoint between EARTH_RADIUS (0.51) and OrbitManager.ORBIT_ENTER_RADIUS (0.80)
const START_ALT_SCENE: float = 1.11          # ~700 km altitude in scene units
const FRAME_REF_HZ: float = 60.0             # prototype thrust was per-frame at 60 Hz
@onready var game_over_screen: Control = %GameOverScreen
const PI_IP: String = "192.168.0.128"
const PI_PORT: int = 5004

var _peer: PacketPeerUDP
# Tracked state
var ang_vel: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var in_orbit: bool = false
var target_id:int=0

@onready var earth: Node3D = get_node_or_null("../Słońce/ziemia axis/Ziemia")
@onready var satellite_spawner: Node3D = $"../EarthFrame/SatelliteSpawner"

func _ready() -> void:
	_peer = PacketPeerUDP.new()
	# Bind is mandatory in Godot 4 to open the local socket
	var err := _peer.bind(0)  
	if err != OK:
		push_error("[distance] bind failed: %d" % err)
		return
	
	# Set target destination
	_peer.set_dest_address(PI_IP, PI_PORT)
	print("[distance] ready, will send to %s:%d" % [PI_IP, PI_PORT])
	#connect game over button to function
	%"Game again btn".connect("pressed",_on_button_pressed)
	# Only nudge to a default orbit if the scene placed us at origin.
	if global_position.length() < 0.001:
		global_position = Vector3(0.0, 0.0, START_ALT_SCENE)

func _process(delta: float) -> void:
	_apply_mouse_look()
	_apply_angular_velocity(delta)
	_apply_thrust(delta)
	_integrate_position(delta)
	var sattelite:Node3D=satellite_spawner.get_satellites()[target_id]
	
	# Check for transmission errors
	var disatnce_vector=sattelite.global_position.distance_to(global_position)
	var distance=(global_transform.origin.direction_to(sattelite.global_transform.origin).normalized().dot(rotation.normalized())*100)
	var payload: PackedByteArray = ("%f,%f" % [distance,disatnce_vector]).to_utf8_buffer()
	var err := _peer.put_packet(payload)
	if err == OK:
		print("[distance] sent distamce %s to %s:%d" % [payload.get_string_from_utf8(), PI_IP, PI_PORT])
	else:
		push_error("[distance] failed to send dsitcance packet: %d" % err)
	
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

func zero_velocity() -> void:
	velocity = Vector3.ZERO


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
		#return
	velocity=Vector3.ZERO
	game_over_screen.visible=true
	#GlobalData.can_move = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _on_button_pressed() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	print("reswtart")
	get_tree().reload_current_scene()

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
