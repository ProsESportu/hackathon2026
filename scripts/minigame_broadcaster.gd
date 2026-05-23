extends Node

const PI_IP: String = "192.169.0.128"
const PI_PORT: int = 5001
const MINIGAME_COUNT: int = 1  # bump when new minigames are added

var _peer: PacketPeerUDP

func _ready() -> void:
	_peer = PacketPeerUDP.new()
	_peer.set_dest_address(PI_IP, PI_PORT)

func send_minigame(id: int) -> void:
	var payload: PackedByteArray = ("%d" % id).to_utf8_buffer()
	_peer.put_packet(payload)
	print("[MinigameBroadcaster] sent minigame id=%d to %s:%d" % [id, PI_IP, PI_PORT])

func get_random_minigame_id() -> int:
	return randi_range(1, MINIGAME_COUNT)
