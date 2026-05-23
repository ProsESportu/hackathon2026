extends CanvasLayer
## HUD for Earth-orbit gameplay.
## - Subscribes to OrbitManager signals; shows tween-faded alert text.
## - Each _process tick, projects Earth into screen space and either hides the
##   directional indicator (Earth on-screen, in front of camera) or pins an
##   arrow to the viewport edge pointing toward it.
## - Shows a full-screen info modal when the player interacts with a satellite.

const ORBIT_MANAGER_PATH:     NodePath = ^"../OrbitManager"
const EARTH_PATH:             NodePath = ^"../Słońce/ziemia axis/Ziemia"
const PLAYER_PATH:            NodePath = ^"../PlayerSat"
const SATELLITE_SPAWNER_PATH: NodePath = ^"../EarthFrame/SatelliteSpawner"

const EDGE_MARGIN_PX: float = 60.0

@onready var alert_label: Label = $AlertLabel
@onready var proximity_label: Label = $ProximityLabel
@onready var interaction_prompt: Label = $InteractionPrompt
@onready var earth_indicator: Control = $EarthIndicator
@onready var arrow: TextureRect = $EarthIndicator/Arrow
@onready var distance_label: Label = $EarthIndicator/DistanceLabel
@onready var cinematic_banner: Label = $CinematicBanner
@onready var cinematic_subtitle: Label = $CinematicSubtitle

const CINEMATIC_TIME_SCALE: float = 0.1
const CINEMATIC_DURATION_REAL_SEC: float = 1.5

var earth: Node3D
var player: Node3D
var _alert_tween: Tween
var _proximity_tween: Tween
var _cinematic_active: bool = false

# Satellite info modal (created programmatically)
var _satellite_spawner: Node
var _modal_active: bool = false
var _modal_root: ColorRect
var _modal_photo: TextureRect
var _modal_no_photo_label: Label
var _modal_name: Label
var _modal_norad: Label
var _modal_country: Label
var _modal_launch: Label
var _modal_type: Label
var _modal_orbit: Label


func _ready() -> void:
	earth = get_node(EARTH_PATH)
	player = get_node(PLAYER_PATH)

	var orbit_manager: Node = get_node(ORBIT_MANAGER_PATH)
	orbit_manager.orbit_entered.connect(_on_orbit_entered)
	orbit_manager.orbit_exit_warning.connect(_on_orbit_exit_warning)
	orbit_manager.orbit_exited.connect(_on_orbit_exited)
	orbit_manager.proximity_alert_started.connect(_on_proximity_started)
	orbit_manager.proximity_alert_cleared.connect(_on_proximity_cleared)

	_satellite_spawner = get_node(SATELLITE_SPAWNER_PATH)
	_satellite_spawner.satellite_in_range.connect(_on_satellite_in_range)
	_satellite_spawner.satellite_out_of_range.connect(_on_satellite_out_of_range)
	_satellite_spawner.minigame_requested.connect(_on_minigame_requested)

	arrow.texture = _make_arrow_texture()
	arrow.pivot_offset = arrow.size * 0.5
	alert_label.modulate.a = 0.0
	earth_indicator.visible = false
	interaction_prompt.visible = false

	_setup_satellite_modal()


func _input(event: InputEvent) -> void:
	if not _modal_active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_X or event.keycode == KEY_ESCAPE:
			_dismiss_satellite_modal()
			get_viewport().set_input_as_handled()


# Generate a small white right-pointing triangle so rotation 0 == "points right".
func _make_arrow_texture() -> ImageTexture:
	var size: int = 32
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(size):
		var t: float = float(x) / float(size - 1)
		var half_h: int = int(round((1.0 - t) * (size * 0.5 - 1.0)))
		var cy: int = size / 2
		for y in range(cy - half_h, cy + half_h + 1):
			img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)


func _process(_delta: float) -> void:
	_update_edge_indicator()


# --- Signal handlers ----------------------------------------------------------

func _on_orbit_entered() -> void:
	_play_orbit_entry_cinematic()

func _on_orbit_exit_warning() -> void:
	show_alert("LEAVING ORBIT — TURN BACK", Color.YELLOW, 2.0)

func _on_orbit_exited() -> void:
	show_alert("ORBIT LOST", Color.RED, 2.5)

func _on_proximity_started() -> void:
	proximity_label.visible = true
	proximity_label.modulate.a = 1.0
	if _proximity_tween != null and _proximity_tween.is_valid():
		_proximity_tween.kill()
	_proximity_tween = create_tween().set_loops()
	_proximity_tween.tween_property(proximity_label, "modulate:a", 0.3, 0.4)
	_proximity_tween.tween_property(proximity_label, "modulate:a", 1.0, 0.4)

func _on_proximity_cleared() -> void:
	if _proximity_tween != null and _proximity_tween.is_valid():
		_proximity_tween.kill()
	proximity_label.visible = false


func _on_satellite_in_range(_sat: Node3D) -> void:
	interaction_prompt.visible = true

func _on_satellite_out_of_range() -> void:
	interaction_prompt.visible = false


func _on_minigame_requested(_sat: Node3D, data: SatelliteData) -> void:
	_show_satellite_modal(data)


# --- Orbit-entry cinematic ----------------------------------------------------

func _play_orbit_entry_cinematic() -> void:
	if _cinematic_active:
		return
	_cinematic_active = true
	cinematic_banner.visible = true
	cinematic_subtitle.visible = true
	Engine.time_scale = CINEMATIC_TIME_SCALE
	await get_tree().create_timer(CINEMATIC_DURATION_REAL_SEC, true, false, true).timeout
	Engine.time_scale = 1.0
	cinematic_banner.visible = false
	cinematic_subtitle.visible = false
	_cinematic_active = false


# --- Alert fade ---------------------------------------------------------------

func show_alert(text: String, color: Color, duration: float) -> void:
	if _alert_tween != null and _alert_tween.is_valid():
		_alert_tween.kill()
	alert_label.text = text
	alert_label.modulate = Color(color.r, color.g, color.b, 0.0)

	var fade_in: float = 0.25
	var fade_out: float = 0.5
	var hold: float = max(0.0, duration - fade_in - fade_out)

	_alert_tween = create_tween()
	_alert_tween.tween_property(alert_label, "modulate:a", 1.0, fade_in)
	_alert_tween.tween_interval(hold)
	_alert_tween.tween_property(alert_label, "modulate:a", 0.0, fade_out)


# --- Satellite info modal ------------------------------------------------------

func _setup_satellite_modal() -> void:
	_modal_root = ColorRect.new()
	_modal_root.color = Color(0.02, 0.02, 0.08, 0.92)
	_modal_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_root.visible = false
	_modal_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_modal_root)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900.0, 480.0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_top", "margin_bottom", "margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 24)
	panel.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 24)
	margin.add_child(hbox)

	# Left: photo
	var photo_vbox := VBoxContainer.new()
	photo_vbox.custom_minimum_size = Vector2(380.0, 0.0)
	hbox.add_child(photo_vbox)

	_modal_photo = TextureRect.new()
	_modal_photo.custom_minimum_size = Vector2(380.0, 280.0)
	_modal_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_modal_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_modal_photo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	photo_vbox.add_child(_modal_photo)

	_modal_no_photo_label = Label.new()
	_modal_no_photo_label.text = "No image available"
	_modal_no_photo_label.add_theme_font_size_override("font_size", 16)
	_modal_no_photo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modal_no_photo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_modal_no_photo_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_modal_no_photo_label.visible = false
	photo_vbox.add_child(_modal_no_photo_label)

	# Right: info labels
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	hbox.add_child(vbox)

	_modal_name    = _modal_label("", 30, vbox)
	_modal_label("", 8, vbox)   # spacer
	_modal_norad   = _modal_label("", 18, vbox)
	_modal_country = _modal_label("", 18, vbox)
	_modal_launch  = _modal_label("", 18, vbox)
	_modal_type    = _modal_label("", 18, vbox)
	_modal_orbit   = _modal_label("", 18, vbox)

	# Fill the remaining space
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var hint := _modal_label("Press  [X]  or  [ESC]  to dismiss", 15, vbox)
	hint.modulate = Color(0.7, 0.7, 0.7, 1.0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _modal_label(text: String, font_size: int, parent: Node) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(lbl)
	return lbl


func _show_satellite_modal(data: SatelliteData) -> void:
	if data == null:
		return
	_modal_active = true
	interaction_prompt.visible = false

	_modal_name.text = data.name if not data.name.is_empty() else "Unknown Satellite"
	_modal_norad.text   = "NORAD ID:      %d" % data.norad_id
	_modal_country.text = "Country/Owner: %s" % (data.country if not data.country.is_empty() else "—")
	_modal_launch.text  = "Launch date:   %s" % (data.launch_date if not data.launch_date.is_empty() else "—")
	_modal_type.text    = "Type:          %s" % (data.object_type if not data.object_type.is_empty() else "—")

	var orbit_str: String = ""
	if data.period_min > 0.0:
		orbit_str += "Period: %.1f min" % data.period_min
	if data.inclination_deg > 0.0:
		orbit_str += "   Inc: %.1f°" % data.inclination_deg
	if data.apogee_km > 0.0:
		orbit_str += "   Apogee: %.0f km" % data.apogee_km
	if data.perigee_km > 0.0:
		orbit_str += "   Perigee: %.0f km" % data.perigee_km
	_modal_orbit.text = orbit_str if not orbit_str.is_empty() else "—"

	if data.photo_image != null:
		_modal_photo.texture = ImageTexture.create_from_image(data.photo_image)
		_modal_photo.visible = true
		_modal_no_photo_label.visible = false
	else:
		_modal_photo.texture = null
		_modal_photo.visible = false
		_modal_no_photo_label.visible = true

	Engine.time_scale = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_modal_root.visible = true


func _dismiss_satellite_modal() -> void:
	_modal_active = false
	_modal_root.visible = false
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_satellite_spawner.consume_current()


# --- Edge indicator -----------------------------------------------------------

func _update_edge_indicator() -> void:
	if earth == null or player == null:
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return

	var earth_pos: Vector3 = earth.global_position
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var screen_center: Vector2 = viewport_size * 0.5

	var behind: bool = camera.is_position_behind(earth_pos)
	var projected: Vector2 = camera.unproject_position(earth_pos)
	var on_screen: bool = (
		not behind
		and projected.x >= 0.0 and projected.x <= viewport_size.x
		and projected.y >= 0.0 and projected.y <= viewport_size.y
	)

	if on_screen:
		earth_indicator.visible = false
		return

	earth_indicator.visible = true

	var dir: Vector2 = projected - screen_center
	if behind:
		dir = -dir
	if dir.length_squared() < 0.0001:
		dir = Vector2.RIGHT
	dir = dir.normalized()

	var half_w: float = screen_center.x - EDGE_MARGIN_PX
	var half_h: float = screen_center.y - EDGE_MARGIN_PX
	var t_x: float = INF if abs(dir.x) < 0.0001 else half_w / abs(dir.x)
	var t_y: float = INF if abs(dir.y) < 0.0001 else half_h / abs(dir.y)
	var t: float = min(t_x, t_y)
	var edge_pos: Vector2 = screen_center + dir * t

	arrow.position = edge_pos - arrow.size * 0.5
	arrow.rotation = dir.angle()

	var dist: float = player.global_position.distance_to(earth_pos)
	distance_label.text = "EARTH %.2f" % dist
	distance_label.position = edge_pos - dir * 40.0 - distance_label.size * 0.5
