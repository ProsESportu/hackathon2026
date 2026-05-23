extends CanvasLayer
## HUD for Earth-orbit gameplay.
## - Subscribes to OrbitManager signals; shows tween-faded alert text.
## - Each _process tick, projects Earth into screen space and either hides the
##   directional indicator (Earth on-screen, in front of camera) or pins an
##   arrow to the viewport edge pointing toward it.

const ORBIT_MANAGER_PATH: NodePath = ^"../OrbitManager"
const EARTH_PATH:         NodePath = ^"../Słońce/ziemia axis/Ziemia"
const PLAYER_PATH:        NodePath = ^"../PlayerSat"

const EDGE_MARGIN_PX: float = 60.0

@onready var alert_label: Label = $AlertLabel
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
var _cinematic_active: bool = false


func _ready() -> void:
	earth = get_node(EARTH_PATH)
	player = get_node(PLAYER_PATH)

	var orbit_manager: Node = get_node(ORBIT_MANAGER_PATH)
	orbit_manager.orbit_entered.connect(_on_orbit_entered)
	orbit_manager.orbit_exit_warning.connect(_on_orbit_exit_warning)
	orbit_manager.orbit_exited.connect(_on_orbit_exited)

	arrow.texture = _make_arrow_texture()
	arrow.pivot_offset = arrow.size * 0.5
	alert_label.modulate.a = 0.0
	earth_indicator.visible = false


# Generate a small white right-pointing triangle so rotation 0 == "points right".
func _make_arrow_texture() -> ImageTexture:
	var size: int = 32
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(size):
		# Horizontal taper: at x=0 use full height, at x=size-1 collapse to center.
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


# --- Orbit-entry cinematic ----------------------------------------------------

# Drop time_scale, show banner, wait in real-time, restore. The 4th arg to
# create_timer (ignore_time_scale=true) is what lets the timer fire in wall-clock
# seconds while the rest of the engine is running at 0.1x.
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

	# Behind-camera projections are mirrored through the center; flip them
	# so the arrow points in the true off-screen direction.
	var dir: Vector2 = projected - screen_center
	if behind:
		dir = -dir
	if dir.length_squared() < 0.0001:
		dir = Vector2.RIGHT
	dir = dir.normalized()

	# Clamp along the direction so the arrow sits on the viewport edge minus margin.
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
	# Sit the distance label just inward of the arrow so it's always readable.
	distance_label.position = edge_pos - dir * 40.0 - distance_label.size * 0.5
