extends Node3D

@export_node_path("Node3D") var sun_node

@onready var wing_holder: MeshInstance3D = $"wing holder"


func _process(delta: float) -> void:
	wing_holder.look_at(get_node(sun_node).global_position)
