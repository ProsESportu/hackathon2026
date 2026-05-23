extends Label
@onready var player_sat: Node3D = $"../../../PlayerSat"
@onready var progress_bar: ProgressBar = $"../ProgressBar"


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	text="Speed: " + str(player_sat.velocity.length())
	progress_bar.value=player_sat.velocity.length()
