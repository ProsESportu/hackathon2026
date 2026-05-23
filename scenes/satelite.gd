extends Node3D

@export_node_path("Node3D") var sun_node

@onready var wing_holder: MeshInstance3D = $"wing holder"

var _sun: Node3D


func _ready() -> void:
	if _sun == null and sun_node != NodePath():
		_sun = get_node_or_null(sun_node)


func set_sun(node: Node3D) -> void:
	_sun = node


func _process(_delta: float) -> void:
	if _sun != null:
		wing_holder.look_at(_sun.global_position)
