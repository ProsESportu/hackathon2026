extends Node3D
## 6-DoF arcade flight for the player satellite.
## Reads exclusively from the InputBridge autoload — never from Input directly.
## Constants mirror the web prototype's tuning (see CLAUDE.md "Quick reference").

const ROT_ACCEL: float = 2.8
const ROT_DAMP_PER_SEC: float = 0.04        # fraction of angular velocity retained per second
const THRUST_ACCEL: float = 0.0008
const MAX_SPEED: float = 0.0025              # ~16 km/s in scene units
const VEL_DAMP_PER_SEC: float = 0.985        # light drag
const EARTH_COLLISION_FLOOR: float = 1.015   # scene radius
const START_ALT_SCENE: float = 1.11          # ~700 km altitude in scene units
const FRAME_REF_HZ: float = 60.0             # prototype thrust was per-frame at 60 Hz

# Tracked state
var ang_vel: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO

func _ready() -> void:
	# Only nudge to a default orbit if the scene placed us at origin.
	if global_position.length() < 0.001:
		global_position = Vector3(0.0, 0.0, START_ALT_SCENE)

func _process(delta: float) -> void:
	_apply_mouse_look()
	_apply_angular_velocity(delta)
	_apply_thrust(delta)
	_integrate_position(delta)
	_enforce_earth_floor()

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

	var accel_dir: Vector3 = fwd * InputBridge.thrust + right * InputBridge.strafe + up * InputBridge.lift
	# Match the prototype's per-frame-at-60Hz feel: a = THRUST_ACCEL * 60 per second.
	velocity += accel_dir * (THRUST_ACCEL * FRAME_REF_HZ) * delta

	var sp: float = velocity.length()
	if sp > MAX_SPEED:
		velocity *= MAX_SPEED / sp
	velocity *= pow(VEL_DAMP_PER_SEC, delta)

func _integrate_position(delta: float) -> void:
	global_position += velocity * delta

func _enforce_earth_floor() -> void:
	var r: float = global_position.length()
	if r < EARTH_COLLISION_FLOOR:
		global_position = global_position.normalized() * EARTH_COLLISION_FLOOR
		velocity = Vector3.ZERO
