extends Node3D

## Spawns a constellation of satellites that follow Earth (via EarthFrame),
## reveals/hides them on orbit entry/exit, slowly revolves them, and emits
## proximity signals so the HUD can show a "Press X to play" prompt.

signal satellite_in_range(satellite: Node3D)
signal satellite_out_of_range
signal minigame_requested(satellite: Node3D, data: SatelliteData)

# Sygnały sieciowe (teraz w tym samym pliku)
signal satellite_fetched(data: SatelliteData)
signal satellite_fetch_failed(norad_id: int, reason: String)

const SUN_PATH:           NodePath = ^"../../Słońce"
const PLAYER_PATH:        NodePath = ^"../../PlayerSat"
const ORBIT_MANAGER_PATH: NodePath = ^"../../OrbitManager"

const SATELLITE_SCENE: PackedScene = preload("res://scenes/satelite.tscn")

const SAT_COUNT: int = 1
const SAT_ORBIT_RADIUS: float = 0.76   # between PROXIMITY_WARN (0.61) and ORBIT_ENTER (0.80)
const REVOLUTION_RAD_PER_SEC: float = 0.05

const INTERACT_ENTER_RADIUS: float = 0.08
const INTERACT_EXIT_RADIUS:  float = 0.11  # hysteresis band

enum State { IN_SPACE, IN_ORBIT }

var state: State = State.IN_SPACE
var _satellites: Array[Node3D] = []
var _current_target: Node3D = null

var sun: Node3D
var player: Node3D

# Lista prawdziwych NORAD ID dla Twoich 12 satelitów
const NORAD_IDS: Array[int] = [
	25544, # ISS (Międzynarodowa Stacja Kosmiczna)
	41335, # GRACE-FO 1
	43476, # TESS
	28485, # Aura
	25994, # Terra
	27424, # Aqua
	40059, # OCO-2
	39086, # Landsat 8
	40390, # DSCOVR
	41866, # GOES-16
	43013, # NOAA 20
	40376  # SMAP
]

const NORAD_NAMES: Dictionary = {
	25544: "ISS",
	41335: "GRACE-FO 1",
	43476: "TESS",
	28485: "Aura",
	25994: "Terra",
	27424: "Aqua",
	40059: "OCO-2",
	39086: "Landsat 8",
	40390: "DSCOVR",
	41866: "GOES-16",
	43013: "NOAA 20",
	40376: "SMAP",
}


func get_satellites()->Array[Node3D]:
	return _satellites
const FALLBACK_DATA: Dictionary = {
	25544: {"country": "ISS", "launch": "1998-11-20", "type": "PAYLOAD", "period": 92.9, "inclination": 51.6},
	41335: {"country": "US/DE", "launch": "2018-05-22", "type": "PAYLOAD", "period": 94.6, "inclination": 89.0},
	43476: {"country": "US", "launch": "2018-04-18", "type": "PAYLOAD", "period": 19685.2, "inclination": 28.5},
	28485: {"country": "US", "launch": "2004-07-15", "type": "PAYLOAD", "period": 98.8, "inclination": 98.2},
	25994: {"country": "US", "launch": "1999-12-18", "type": "PAYLOAD", "period": 98.8, "inclination": 98.2},
	27424: {"country": "US", "launch": "2002-05-04", "type": "PAYLOAD", "period": 98.8, "inclination": 98.2},
	40059: {"country": "US", "launch": "2014-07-02", "type": "PAYLOAD", "period": 98.8, "inclination": 98.2},
	39086: {"country": "US", "launch": "2013-02-11", "type": "PAYLOAD", "period": 98.8, "inclination": 98.2},
	47954: {"country": "US", "launch": "2021-03-22", "type": "PAYLOAD", "period": 95.3, "inclination": 97.5},
	44387: {"country": "US", "launch": "2019-06-25", "type": "PAYLOAD", "period": 93.3, "inclination": 24.0},
	43013: {"country": "US", "launch": "2017-11-18", "type": "PAYLOAD", "period": 101.4, "inclination": 98.7},
	40376: {"country": "US", "launch": "2015-01-31", "type": "PAYLOAD", "period": 98.5, "inclination": 98.1},
}


func _ready() -> void:
	# 1. Bezpieczne przypisanie Słońca
	sun = get_node_or_null(SUN_PATH)
	if sun == null:
		# Próba ratunku: szukamy węzła o nazwie Słońce w całej scenie
		sun = get_tree().current_scene.find_child("Słońce", true, false)
	
	# 2. Bezpieczne przypisanie Gracza
	player = get_node_or_null(PLAYER_PATH)
	if player == null:
		player = get_tree().current_scene.find_child("PlayerSat", true, false)

	# Podłączamy sygnały sieciowe
	satellite_fetched.connect(_on_network_data_received)
	satellite_fetch_failed.connect(_on_network_data_failed)

	# 3. Dynamiczne i bezpieczne szukanie OrbitManager
	var orbit_manager: Node = get_node_or_null(ORBIT_MANAGER_PATH)
	if orbit_manager == null:
		# Jeśli ścieżka zawiodła, przeszukaj całą aktywną scenę w dół
		orbit_manager = get_tree().current_scene.find_child("OrbitManager", true, false)

	# Walidacja: Jeśli nadal nie ma managera, wypisz błąd i nie wysypuj gry
	if orbit_manager != null:
		orbit_manager.orbit_entered.connect(_on_orbit_entered)
		orbit_manager.orbit_exited.connect(_on_orbit_exited)
	else:
		push_error("[CRITICAL] SatelliteSpawner: Nie znaleziono węzła OrbitManager w scenie!")

	InputBridge.interact_pressed.connect(_on_interact_pressed)

	_spawn_satellite()



func _process(delta: float) -> void:
	if state == State.IN_ORBIT:
		_update_proximity()
	
	for sat in _satellites:
		if sat.data != null and sat.data.tle_line1 != "":
			var dir = OrbitalPosition.compute_direction(sat.data.tle_line1, sat.data.tle_line2)
			sat.position = dir * SAT_ORBIT_RADIUS


# --- Spawning & API Fetching -------------------------------------------------

func _spawn_satellite(exclude_id: int = -1) -> void:
	var cat_data: Dictionary
	if exclude_id == -1:
		cat_data = SatelliteCatalog.get_random()
	else:
		cat_data = SatelliteCatalog.get_random_excluding(exclude_id)
		
	var target_id: int = cat_data["norad_id"]

	var sat: Node3D = SATELLITE_SCENE.instantiate()
	sat.set_sun(sun)
	sat.visible = state == State.IN_ORBIT
	# Initial position will be updated by TLE once available
	sat.position = Vector3(SAT_ORBIT_RADIUS, 0, 0)
	
	sat.name = "Satellite_" + str(target_id)
	sat.set_meta("norad_id", target_id)
	
	# Provide mock data immediately
	sat.data = SatelliteData.new()
	sat.data.norad_id = target_id
	sat.data.name = "Loading..."

	add_child(sat)
	_satellites.append(sat)
	
	var service = get_node_or_null("/root/SatelliteService")
	if service:
		if not service.is_connected("satellite_fetched", _on_network_data_received):
			service.satellite_fetched.connect(_on_network_data_received)
		if not service.is_connected("satellite_fetch_failed", _on_network_data_failed):
			service.satellite_fetch_failed.connect(_on_network_data_failed)
		service.fetch_satellite_data(target_id)
	else:
		push_error("SatelliteService not found!")


	# (Removed old local Celestrak functions)

func _on_network_data_received(api_data: SatelliteData) -> void:
	for sat in _satellites:
		if sat.has_meta("norad_id") and sat.get_meta("norad_id") == api_data.norad_id:
			# Nadpisujemy domyślne dane (mocki) nową strukturą z API
			sat.data = api_data
			print("[Spawner] Pobrano dane z API dla: ", api_data.name)
			break


func _on_network_data_failed(norad_id: int, reason: String) -> void:
	print("[Spawner] Problem z API dla ID ", norad_id, ": ", reason, " — using local fallback")
	var fallback := SatelliteData.new()
	fallback.norad_id = norad_id
	var display_name: String = NORAD_NAMES.get(norad_id, "")
	if display_name.is_empty():
		for entry in SatelliteCatalog.SATELLITES:
			if entry["norad_id"] == norad_id:
				display_name = entry["display_name"]
				break
	fallback.name = display_name if not display_name.is_empty() else "Satellite %d" % norad_id
	
	if FALLBACK_DATA.has(norad_id):
		var details = FALLBACK_DATA[norad_id]
		fallback.country = details.get("country", "")
		fallback.launch_date = details.get("launch", "")
		fallback.object_type = details.get("type", "")
		fallback.period_min = details.get("period", 0.0)
		fallback.inclination_deg = details.get("inclination", 0.0)
		
	_on_network_data_received(fallback)


# --- Orbit state handlers ----------------------------------------------------

func _on_orbit_entered() -> void:
	state = State.IN_ORBIT
	for sat in _satellites:
		sat.visible = true


func _on_orbit_exited() -> void:
	state = State.IN_SPACE
	for sat in _satellites:
		sat.visible = false
	if _current_target != null:
		_current_target = null
		satellite_out_of_range.emit()


# --- Proximity ---------------------------------------------------------------

func _update_proximity() -> void:
	var player_pos: Vector3 = player.global_position
	var nearest: Node3D = null
	var nearest_dist: float = INF
	for sat in _satellites:
		var d: float = player_pos.distance_to(sat.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = sat

	if _current_target == null:
		if nearest_dist < INTERACT_ENTER_RADIUS:
			_current_target = nearest
			satellite_in_range.emit(nearest)
	else:
		var target_dist: float = player_pos.distance_to(_current_target.global_position)
		if target_dist > INTERACT_EXIT_RADIUS:
			_current_target = null
			satellite_out_of_range.emit()
			if nearest != null and nearest_dist < INTERACT_ENTER_RADIUS:
				_current_target = nearest
				satellite_in_range.emit(nearest)


# --- Interaction -------------------------------------------------------------

func _on_interact_pressed() -> void:
	if state != State.IN_ORBIT or _current_target == null:
		return
	if _current_target.data == null:
		print("[SatelliteSpawner] Data not yet loaded for satellite.")
		return
	print("[SatelliteSpawner] minigame requested for ", _current_target.data.name)
	minigame_requested.emit(_current_target, _current_target.data)


func consume_current() -> void:
	if _current_target == null:
		return
	var old_id: int = _current_target.get_meta("norad_id", -1)
	_satellites.erase(_current_target)
	_current_target.queue_free()
	_current_target = null
	satellite_out_of_range.emit()
	_spawn_satellite(old_id)
