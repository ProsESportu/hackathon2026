extends Control
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

# Called when the node enters the scene tree for the first time.
var target:Array[int]=[]
func _ready() -> void:
	for i in range(4):
		var l=randi()%9 +1
		if l not in target:
			target.push_back(l)
	for i in target:
		await get_tree().create_timer(1).timeout
		label.text=str(i)
	target.sort()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var buttons=[]
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
	print(buttons,target)
	if buttons==target:
		label.text="win"
