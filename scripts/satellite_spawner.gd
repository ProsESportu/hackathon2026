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

const SAT_COUNT: int = 12
const SAT_ORBIT_RADIUS: float = 0.72   # between PROXIMITY_WARN (0.61) and ORBIT_ENTER (0.80)
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
	47954, # Radiometer Sat
	44387, # LightSail 2
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
	47954: "Radiometer Sat",
	44387: "LightSail 2",
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


>>>>>>> 5b52dd0573222d02a6b4246d2e7fb93748cd3c36
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

	_spawn_satellites()



func _process(delta: float) -> void:
	rotate_y(REVOLUTION_RAD_PER_SEC * delta)
	if state == State.IN_ORBIT:
		_update_proximity()


# --- Spawning & API Fetching -------------------------------------------------

func _spawn_satellites() -> void:
	var golden_angle: float = PI * (3.0 - sqrt(5.0))
	for i in range(SAT_COUNT):
		var y: float = 1.0 - (float(i) / float(SAT_COUNT - 1)) * 2.0
		var radius_at_y: float = sqrt(max(0.0, 1.0 - y * y))
		var theta: float = golden_angle * float(i)
		var pos: Vector3 = Vector3(
			cos(theta) * radius_at_y,
			y,
			sin(theta) * radius_at_y
		) * SAT_ORBIT_RADIUS

		var sat: Node3D = SATELLITE_SCENE.instantiate()
		sat.set_sun(sun)
		sat.visible = false
		sat.position = pos
		
		# Przypisujemy unikalne ID satelity
		var target_id = NORAD_IDS[i]
		sat.name = "Satellite_" + str(target_id)
		sat.set_meta("norad_id", target_id)
		
		# Provide mock data immediately to avoid crashes on interaction before network response
		sat.data = SatelliteData.new()
		sat.data.norad_id = target_id
		sat.data.name = "Loading..."

		add_child(sat)
		_satellites.append(sat)
		
		# Odpalenie zapytania HTTP bezpośrednio z tego samego obiektu
		fetch_satellite_data(target_id)


func fetch_satellite_data(norad_id: int) -> void:
	var http_client = HTTPRequest.new()
	add_child(http_client)
	
	http_client.request_completed.connect(
		func(result, response_code, headers, body): 
			_on_request_completed(result, response_code, headers, body, norad_id, http_client)
	)

	var custom_headers = [
		"User-Agent: GodotSatelliteApp/1.0",
		"Accept: application/json"
	]
	
	http_client.use_threads = false
	
	var url = "https://celestrak.org/satcat/records.php?CATNR=%d&FORMAT=json" % norad_id

	var error = http_client.request(url, custom_headers, HTTPClient.METHOD_GET)
	if error != OK:
		satellite_fetch_failed.emit(norad_id, "HTTP Initial Request Failed")
		http_client.queue_free()



func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, norad_id: int, client_node: Node) -> void:
	client_node.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		satellite_fetch_failed.emit(norad_id, "TLE HTTP %d" % result)
		return

	if response_code != 200:
		satellite_fetch_failed.emit(norad_id, "Server Rejected Code %d" % response_code)
		return

	var json = JSON.new()
	var parse_err = json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		satellite_fetch_failed.emit(norad_id, "JSON parsing error")
		return

	var response_data = json.get_data()
	
	# Celestrak SATCAT returns a JSON array, one object per satellite
	if typeof(response_data) != TYPE_ARRAY or response_data.is_empty():
		satellite_fetch_failed.emit(norad_id, "No valid JSON array returned")
		return

	var sat_json: Dictionary = response_data[0]
	if sat_json == null:
		satellite_fetch_failed.emit(norad_id, "Array element is not a dictionary")
		return

	var satellite_data = SatelliteData.new()
	satellite_data.norad_id    = norad_id
	satellite_data.name        = sat_json.get("SATNAME", "Unknown")
	satellite_data.country     = sat_json.get("COUNTRY", "")
	satellite_data.launch_date = sat_json.get("LAUNCH", "")
	satellite_data.object_type = sat_json.get("OBJECT_TYPE", "")
	satellite_data.period_min      = float(sat_json.get("PERIOD", 0))
	satellite_data.inclination_deg = float(sat_json.get("INCLINATION", 0))
	satellite_data.apogee_km   = float(sat_json.get("APOGEE", 0))
	satellite_data.perigee_km  = float(sat_json.get("PERIGEE", 0))

	satellite_fetched.emit(satellite_data)


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
	fallback.name = NORAD_NAMES.get(norad_id, "Satellite %d" % norad_id)
	
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
	_current_target = null
	satellite_out_of_range.emit()
