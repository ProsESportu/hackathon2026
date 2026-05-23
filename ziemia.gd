extends RigidBody3D
@onready var słońce: StaticBody3D = $"../Słońce"
@export var G:float
@export var initial_velocity:float
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	apply_central_force(Vector3.BACK*initial_velocity)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	apply_central_force((słońce.global_position-global_position)*G)
