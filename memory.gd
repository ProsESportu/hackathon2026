extends Control

signal completed

@onready var control: Control = $"."
@onready var label: Label = $Label
@onready var button_2: Button = $GridContainer/Button2
@onready var button_3: Button = $GridContainer/Button3
@onready var button_4: Button = $GridContainer/Button4
@onready var button_5: Button = $GridContainer/Button5
@onready var button_6: Button = $GridContainer/Button6
@onready var button_7: Button = $GridContainer/Button7
@onready var button_8: Button = $GridContainer/Button8
@onready var button_9: Button = $GridContainer/Button9
@onready var button: Button = $GridContainer/Button

var target: Array[int] = []
var _done := false

func _ready() -> void:
	InputBridge.disabled_input = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	for i in range(4):
		var l = randi() % 9 + 1
		if l not in target:
			target.push_back(l)
	await get_tree().create_timer(1.5).timeout
	for i in target:
		await get_tree().create_timer(1).timeout
		label.text = str(i)
	label.text = "?"
	target.sort()


func _process(_delta: float) -> void:
	if _done:
		return
	var buttons: Array[int] = []
	if button.button_pressed:
		buttons.push_back(1)
	if button_2.button_pressed:
		buttons.push_back(2)
	if button_3.button_pressed:
		buttons.push_back(3)
	if button_4.button_pressed:
		buttons.push_back(4)
	if button_5.button_pressed:
		buttons.push_back(5)
	if button_6.button_pressed:
		buttons.push_back(6)
	if button_7.button_pressed:
		buttons.push_back(7)
	if button_8.button_pressed:
		buttons.push_back(8)
	if button_9.button_pressed:
		buttons.push_back(9)
	buttons.sort()
	if buttons == target:
		_done = true
		label.text = "WIN!"
		InputBridge.disabled_input = false
		completed.emit()
