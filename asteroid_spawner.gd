extends Node3D
@onready var asteroid: StaticBody3D = $asteroid
@export var asteroid_amount =500
@export var rang=500
func _ready() -> void:
	for i in asteroid_amount:
		var n_a=asteroid.duplicate()
		add_child(n_a)
		asteroid.position=Vector3(randi_range(-rang,rang),randi_range(-rang,rang),randi_range(-rang,rang))
