extends Node2D

@onready var to_connect: Area2D = $"to connect"
@onready var connection_hub: Area2D = $"connection hub"

var connected = false

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)




func _on_to_connect_area_entered(area: Area2D) -> void:
	pass # Replace with function body.


func _on_to_connect_area_exited(area: Area2D) -> void:
	pass # Replace with function body.

var selected = false
