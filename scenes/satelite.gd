extends Node3D

@export_node_path("Node3D") var sun_node

@onready var wing_holder: MeshInstance3D = $"wing holder"
@onready var label_3d: Label3D = $Label3D

var _sun: Node3D
var data: SatelliteData = null


func _ready() -> void:
	if _sun == null and sun_node != NodePath():
		_sun = get_node_or_null(sun_node)

func set_country_text(text:String)->void: #use on init
	label_3d.text = text
	
func set_sun(node: Node3D) -> void:
	_sun = node


func _process(_delta: float) -> void:
	pass
	#if _sun != null:
		#wing_holder.look_at(_sun.global_position)
