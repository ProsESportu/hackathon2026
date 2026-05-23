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
var can_move: bool = true

# One-shot edge events. Listen with InputBridge.interact_pressed.connect(...).
signal interact_pressed   # X key tapped

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
		elif event.keycode == KEY_X:
			interact_pressed.emit()
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	var use_local := input_mode != InputMode.UDP
	var use_udp := input_mode != InputMode.LOCAL

	# Poll keyboard into the rate axes. is_physical_key_pressed uses physical
	# layout so this still works on non-QWERTY layouts.
	server.poll()
	if can_move:
		brake = Input.is_physical_key_pressed(KEY_SPACE)
		roll = _axis(KEY_E, KEY_Q)        # E = roll right (+), Q = roll left (-)
		thrust = _axis(KEY_W, KEY_S)
		strafe = _axis(KEY_D, KEY_A)
		lift = _axis(KEY_SHIFT, KEY_CTRL)
	
	if server.is_connection_available():
		var peer = server.take_connection()
		while peer.get_available_packet_count() > 0:
			var packet = peer.get_packet()
			print("Accepted peer: %s:%s" % [peer.get_packet_ip(), peer.get_packet_port()])
			var res=packet.get_string_from_utf8()
			print("Received data: %s" % [res])
			res=res.split(",")
			_look_dx=float(res[0])*0.0001
			_look_dy=float(res[1])*0.0001
			thrust=float(res[2])
			brake=bool(int(res[3]))

static func _axis(positive: Key, negative: Key) -> float:
	return float(Input.is_physical_key_pressed(positive)) - float(Input.is_physical_key_pressed(negative))

func consume_look() -> Vector2:
	var out := Vector2(_look_dx, _look_dy)
	_look_dx = 0.0
	_look_dy = 0.0
	return out
