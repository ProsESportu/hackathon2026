extends Node

const PI_IP: String = "192.168.0.128"
const PI_PORT: int = 5001
const RECEIVE_PORT: int = 5002
const MINIGAME_COUNT: int = 1  # bump when new minigames are added

var _peer: PacketPeerUDP
var _server: UDPServer

signal minigame_completed(reward: String)

func _ready() -> void:
	_server = UDPServer.new()
	_server.listen(RECEIVE_PORT)
	_peer = PacketPeerUDP.new()
	# Bind is mandatory in Godot 4 to open the local socket
	var err := _peer.bind(0)  
	if err != OK:
		push_error("[MinigameBroadcaster] bind failed: %d" % err)
		return
	
	# Set target destination
	_peer.set_dest_address(PI_IP, PI_PORT)
	print("[MinigameBroadcaster] ready, will send to %s:%d" % [PI_IP, PI_PORT])

func send_minigame(id: int) -> void:
	var payload: PackedByteArray = ("%d" % id).to_utf8_buffer()
	
	# Check for transmission errors
	var err := _peer.put_packet(payload)
	if err == OK:
		print("[MinigameBroadcaster] sent minigame id=%d to %s:%d" % [id, PI_IP, PI_PORT])
	else:
		push_error("[MinigameBroadcaster] failed to send packet: %d" % err)

func get_random_minigame_id() -> int:
	return randi_range(1, MINIGAME_COUNT)

func send_satellite_id(norad_id: int) -> void:
	var payload: PackedByteArray = ("sat:%d" % norad_id).to_utf8_buffer()
	var err := _peer.put_packet(payload)
	if err == OK:
		print("[MinigameBroadcaster] sent satellite id=%d to %s:%d" % [norad_id, PI_IP, PI_PORT])
	else:
		push_error("[MinigameBroadcaster] failed to send satellite id: %d" % err)
func send_distance(dist:float)->void:
	var payload: PackedByteArray = ("%d" % dist).to_utf8_buffer()
	
	# Check for transmission errors
	var err := _peer.put_packet(payload)
	if err == OK:
		print("[MinigameBroadcaster] sent distamce id=%d to %s:%d" % [dist, PI_IP, PI_PORT])
	else:
		push_error("[MinigameBroadcaster] failed to send dsitcance packet: %d" % err)

func _process(_delta: float) -> void:
	_server.poll()
	if _server.is_connection_available():
		var peer: PacketPeerUDP = _server.take_connection()
		while peer.get_available_packet_count() > 0:
			var packet: PackedByteArray = peer.get_packet()
			var res: String = packet.get_string_from_utf8()
			print("[MinigameBroadcaster] Received result: %s" % res)
			minigame_completed.emit(res)

# Add this function to your existing script
func _unhandled_input(event: InputEvent) -> void:
	# Checks if the Spacebar was just pressed down
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_0:
			var random_id = get_random_minigame_id()
			send_minigame(random_id)
