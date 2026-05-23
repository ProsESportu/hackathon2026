extends Node2D
@onready var wire: Node2D = $wire
@onready var label: RichTextLabel = $Label

var wires = []
func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	InputBridge.disabled_input=true
	var possible_positions = range(5)
	possible_positions.shuffle()
	
	for i in 5:
		var new_wire = wire.duplicate()
		add_child(new_wire)
		wires.append(new_wire)
		new_wire.global_position.y = i * 120 + 80
		new_wire.get_child(0).global_position.y = possible_positions.pop_back() * 120 + 80
		print(wire.global_position.y,wire.get_child(0).global_position.y)
	wire.queue_free()
	
	
		

func _process(delta: float) -> void:
	var all_connected = true
	for wire in wires:
		if !wire.connected:
			all_connected=false
			break
	if all_connected:
		wires[0].connected=false
		
		var tween = get_tree().create_tween()
		tween.set_trans(Tween.TRANS_BOUNCE)
		tween.set_parallel(true)
		tween.tween_property(label, "rotation_degrees", 360*5, 1.0)
		tween.tween_property(label, "scale", Vector2.ONE*3, 1.0)
			
			
			
			
			
			
			
