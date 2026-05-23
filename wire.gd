extends Node2D

@onready var wire_head: Area2D = $"wire head"
@onready var connection_hub: Area2D = $"connection hub"
@onready var line_2d: Line2D = $Line2D
@onready var hub_poly: Polygon2D = $"connection hub/hub poly"
@onready var head_poly: Polygon2D = $"wire head/head poly"

var connected = false
var selected = false

func _set_color(color:Color):
	line_2d.default_color = color
	head_poly.color = color
	hub_poly.color = color

func _ready() -> void:
	line_2d.add_point(wire_head.position)
	line_2d.add_point(Vector2.ZERO)
	line_2d.add_point(Vector2.LEFT*50)
	
	var random_color := Color.from_hsv(randf(),0.3,0.5)
	_set_color(random_color)

func _process(delta: float) -> void:
	if selected:
		wire_head.global_position=get_global_mouse_position()
		wire_head.look_at(global_position)
		wire_head.rotate(PI)
		line_2d.points[0]=wire_head.position


func _on_wire_head_input_event(viewport: Node, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton:
		selected = !selected
		if connected:
			wire_head.input_pickable=false
			selected=false
			wire_head.global_position = connection_hub.global_position
			line_2d.points[0]=wire_head.position
			wire_head.rotation=0.0

func _on_connection_hub_area_entered(area: Area2D) -> void:
	if area==wire_head:
		connected=true



func _on_connection_hub_area_exited(area: Area2D) -> void:
	if area==wire_head:
		connected=false
