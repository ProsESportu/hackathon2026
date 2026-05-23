extends Node
## InputBridge — the single input source for flight.
##
## Keyboard polls into rate axes each frame. Mouse-motion events accumulate
## into look deltas, consumed (and zeroed) by the flight controller each frame.
## External hardware (gyro pad, EEG) will write the same axes — never read
## from Input.is_*_pressed in flight_controller; read from here.

# ---- rate axes (-1..1) — what the flight controller integrates ----
var pitch: float = 0.0   # +1 = nose up   (gyro pad later; keyboard does not set this — mouse handles look)
var yaw: float = 0.0     # +1 = nose right (same)
var roll: float = 0.0    # +1 = roll right (Q/E)
var thrust: float = 0.0  # +1 = forward   (W/S)
var strafe: float = 0.0  # +1 = right     (A/D)
var lift: float = 0.0    # +1 = up        (Shift/Ctrl)
var brake: bool = false  # Space — actively damps linear velocity to a halt
var focus: float = 1.0   # 0..1 — EEG attention; multiplies scan speed, low focus adds reticle jitter


# ---- mouse-look (radians, accumulated per frame, consumed by flight controller) ----
var _look_dx: float = 0.0  # yaw delta (positive = look right)
var _look_dy: float = 0.0  # pitch delta (positive = look up)

@export var mouse_sensitivity: float = 0.0022  # rad per pixel
@export var invert_mouse_y: bool = false
@export var gamepad_look_speed: float = 2.5    # rad/sec at full right-stick deflection
@export var invert_gamepad_y: bool = false
@export var trigger_brake_threshold: float = 0.1

enum InputMode { LOCAL, UDP, AUTO }
@export_enum("Local", "UDP", "Auto") var input_mode: int = InputMode.AUTO

var server = UDPServer.new()
var _udp_has_input: bool = false
var _udp_look: Vector2 = Vector2.ZERO
var _udp_thrust: float = 0.0
var _udp_brake: bool = false

func _ready() -> void:
	# Capture mouse on startup so flight feels right immediately.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Make sure we still get input even if no other node grabs it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	server.listen(5000)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			# Mouse right -> yaw right (look right)
			_look_dx += -event.relative.x * mouse_sensitivity
			# Mouse up   -> pitch up
			var dy_sign := 1.0 if invert_mouse_y else -1.0
			_look_dy += dy_sign * event.relative.y * mouse_sensitivity
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			# Toggle capture so the user can alt-tab / use the editor.
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	var use_local := input_mode != InputMode.UDP
	var use_udp := input_mode != InputMode.LOCAL

	var local_roll: float = 0.0
	var local_strafe: float = 0.0
	var local_lift: float = 0.0
	var local_thrust: float = 0.0
	var local_brake: bool = false
	var local_look := Vector2.ZERO

	if use_local:
		# Poll keyboard into the rate axes. is_physical_key_pressed uses physical
		# layout so this still works on non-QWERTY layouts.
		local_roll = _axis(KEY_E, KEY_Q)        # E = roll right (+), Q = roll left (-)
		var key_thrust := _axis(KEY_W, KEY_S)
		local_strafe = _axis(KEY_D, KEY_A)
		local_lift = _axis(KEY_SHIFT, KEY_CTRL)
		var key_brake := Input.is_physical_key_pressed(KEY_SPACE)

		# Gamepad triggers: RT = forward thrust, LT = brake.
		var rt: float = Input.get_action_strength("r_trigger")
		var lt: float = Input.get_action_strength("l_trigger")
		local_thrust = clamp(key_thrust + rt, -1.0, 1.0)
		local_brake = key_brake or lt > trigger_brake_threshold

		# Gamepad right stick feeds the same look accumulator as the mouse.
		var look_x: float = Input.get_action_strength("right") - Input.get_action_strength("left")
		var look_y: float = Input.get_action_strength("up") - Input.get_action_strength("down")
		var gy_sign := -1.0 if invert_gamepad_y else 1.0
		local_look = Vector2(-look_x * gamepad_look_speed * delta, gy_sign * look_y * gamepad_look_speed * delta)

	_udp_has_input = false
	_udp_look = Vector2.ZERO
	_udp_thrust = 0.0
	_udp_brake = false

	if use_udp:
		server.poll()
		if server.is_connection_available():
			var peer = server.take_connection()
			while peer.get_available_packet_count() > 0:
				var packet = peer.get_packet()
				print("Accepted peer: %s:%s" % [peer.get_packet_ip(), peer.get_packet_port()])
				var res = packet.get_string_from_utf8()
				print("Received data: %s" % [res])
				var parts = res.split(",")
				if parts.size() >= 4:
					_udp_has_input = true
					_udp_look = Vector2(float(parts[0]) * 0.0001, float(parts[1]) * 0.0001)
					_udp_thrust = float(parts[2])
					_udp_brake = bool(int(parts[3]))

	if use_local:
		roll = local_roll
		strafe = local_strafe
		lift = local_lift
	else:
		roll = 0.0
		strafe = 0.0
		lift = 0.0

	var use_udp_active := input_mode == InputMode.UDP or (input_mode == InputMode.AUTO and _udp_has_input)
	if use_udp_active:
		thrust = _udp_thrust
		brake = _udp_brake
		_look_dx = _udp_look.x
		_look_dy = _udp_look.y
	else:
		thrust = local_thrust
		brake = local_brake
		_look_dx += local_look.x
		_look_dy += local_look.y

static func _axis(positive: Key, negative: Key) -> float:
	return float(Input.is_physical_key_pressed(positive)) - float(Input.is_physical_key_pressed(negative))

func consume_look() -> Vector2:
	var out := Vector2(_look_dx, _look_dy)
	_look_dx = 0.0
	_look_dy = 0.0
	return out
