extends Node2D

signal completed

@onready var polygon_2d: Polygon2D = $Polygon2D
@export var subdivide:=3
var all_polygons = []
func _ready() -> void:
	InputBridge.disabled_input=true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	all_polygons = [polygon_2d]
	for i in pow(2,subdivide)-1:
		var polys=_split_poly_half(all_polygons.pop_front())
		all_polygons.append(polys[0])
		all_polygons.append(polys[1])
	_debug_color_poly()
	_add_areas_to_polygons()
	_move_to_random_positions()
		

func _split_poly_half(poly:Polygon2D):
	var point1:Vector2
	var point2:Vector2
	var polygon_1 :=poly.duplicate()
	var polygon_2 :=poly.duplicate()
	var pionowo = randf()>0.5
	if pionowo:
		point1 = lerp(poly.polygon[0],poly.polygon[1],randf_range(0.3,0.7))
		point2 = lerp(poly.polygon[2],poly.polygon[3],randf_range(0.3,0.7))
		polygon_1.polygon=[poly.polygon[0],point1,point2,poly.polygon[3]]
		polygon_2.polygon=[point1,poly.polygon[1],poly.polygon[2],point2]
	else:
		point1 = lerp(poly.polygon[1],poly.polygon[2],randf_range(0.3,0.7))
		point2 = lerp(poly.polygon[3],poly.polygon[0],randf_range(0.3,0.7))
		polygon_1.polygon=[poly.polygon[1],point1,point2,poly.polygon[0]]
		polygon_2.polygon=[point1,poly.polygon[2],poly.polygon[3],point2]
	poly.queue_free()
	add_child(polygon_1)
	add_child(polygon_2)
	return [polygon_1,polygon_2]
		

func _move_to_random_positions():
	var t := get_tree().create_tween()
	for polygon2d in all_polygons:
		t.tween_property(polygon2d,'position',Vector2(randi_range(0,300),randi_range(0,200)),0.2)

var select_lock = null
func _add_areas_to_polygons():
	for polygon2d in all_polygons:
		var new_area = Area2D.new()
		polygon2d.add_child(new_area)
		var new_collisionpolygon:CollisionPolygon2D = CollisionPolygon2D.new()
		new_area.add_child(new_collisionpolygon)
		new_collisionpolygon.polygon = polygon2d.polygon
		var _on_area2d_input_event=func (viewport:Node,event:InputEvent,shape_idx:int):
			if c:
				return
			if event is InputEventMouse:
				if event is InputEventMouseButton:
					if event.button_mask == MOUSE_BUTTON_LEFT:
						if event.pressed:
							select_lock = polygon2d
						else:
							select_lock = null
				if event is InputEventMouseMotion:
					if select_lock==polygon2d and event.button_mask==MOUSE_BUTTON_LEFT:
						polygon2d.position+= event.relative
						_check_absolute_sum()
	
		new_area.connect("input_event",_on_area2d_input_event)

func _debug_color_poly():
	for polygon2d in all_polygons:
		polygon2d.color = Color.from_hsv(randf(),0.5,1.0)

var c=false
func _check_absolute_sum():
	var p = all_polygons[0].position
	var prog = 100.0
	var sum = 0.0
	for polygon2d in all_polygons:
		sum+=p.distance_to(polygon2d.position)
	if sum<prog and not c:
		print('wygrales')
		var t := get_tree().create_tween()
		for polygon2d in all_polygons:
			t.tween_property(polygon2d,'position',all_polygons[0].position,0.05)
			t.tween_property(polygon2d,'color',Color.WHITE,0.05)
		await t.finished
		completed.emit()
		c=true
	else:
		print('zabraklo ci!')
		print(sum)
	
