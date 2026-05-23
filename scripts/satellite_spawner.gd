extends Node3D

## Spawns a constellation of satellites that follow Earth (via EarthFrame),
## reveals/hides them on orbit entry/exit, slowly revolves them, and emits
## proximity signals so the HUD can show a "Press X to play" prompt.

signal satellite_in_range(satellite: Node3D)
signal satellite_out_of_range
signal minigame_requested(satellite: Node3D, data: SatelliteData)
signal satellite_data_ready(data: SatelliteData)

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

# NORAD IDs restricted to entries present in norad_ids.json
const NORAD_IDS: Array[int] = [634, 858, 1317, 2608, 2639, 2717, 2969, 3029, 3430, 3431, 3691, 4068, 4250, 4353, 4376, 4418, 4510, 4511, 4902, 5587, 5588, 5709, 5775, 5851, 5854, 6052, 6317, 6380, 6437, 6691, 7250, 7392, 7466, 7544, 7547, 7578, 7648, 7790, 8132, 8330, 8357, 8366, 8476, 8482, 8513, 8516, 8585, 8620, 8746, 8747, 8808, 8838, 8916, 8918, 9009, 9047, 9416, 9503, 9852, 9855, 9862, 10016, 10024, 10061, 10159, 10294, 10365, 10489, 10557, 10637, 10778, 10787, 10792, 10942, 10953, 10981, 10987, 11153, 11158, 11273, 11343, 11436, 11440, 11484, 11558, 11560, 11561, 11568, 11581, 11648, 11669, 11676, 11708, 11890, 11940, 12003, 12065, 12120, 12309, 12351, 12447, 12472, 12545, 12564, 12618, 12677, 12855, 12897, 12930, 12932, 12967, 12994, 12996, 13035, 13056, 13069, 13129, 13177, 13431, 13554, 13624, 13630, 13631, 13643, 13651, 13652, 13782, 13974, 13983, 13984, 14050, 14114, 14134, 14158, 14195, 14234, 14318, 14328, 14365, 14377, 14421, 14548, 14675, 14677, 14725, 14783, 14867, 14899, 14940, 14948, 14951, 14985, 15057, 15144, 15152, 15181, 15237, 15308, 15385, 15484, 15543, 15560, 15561, 15574, 15581, 15642, 15677, 15678, 15824, 15825, 15826, 15873, 15946, 15993, 15994, 16116, 16199, 16214, 16250, 16274, 16275, 16276, 16482, 16526, 16649, 16650, 16667, 16769, 17125, 17561, 17705, 17706, 17872, 17873, 17874, 17939, 18316, 18384, 18387, 18443, 18446, 18575, 18578, 18631, 18922, 18951, 19073, 19076, 19217, 19330, 19344, 19397, 19400, 19483, 19484, 19548, 19550, 19596, 19687, 19710, 19874, 19913, 19928, 19976, 19983, 20040, 20041, 20107, 20168, 20253, 20263, 20266, 20357, 20367, 20391, 20410, 20473, 20499, 20502, 20523, 20570, 20643, 20659, 20662, 20693, 20696, 20706, 20776, 20777, 20799, 20800, 20801, 20836, 20837, 20873, 20923, 20953, 21016, 21019, 21038, 21055, 21111, 21129, 21132, 21227, 21639, 21641, 21653, 21702, 21703, 21762, 21765, 21789, 21821, 21904, 21922, 21939, 21964, 22027, 22112, 22115, 22116, 22175, 22205, 22210, 22245, 22266, 22269, 22272, 22314, 22316, 22557, 22694, 22723, 22724, 22787, 22796, 22836, 22839, 22871, 22880, 22883, 22907, 22911, 22916, 22927, 22963, 22966, 22981, 22989, 23010, 23108, 23118, 23132, 23168, 23171, 23185, 23247, 23267, 23270, 23314, 23319, 23322, 23327, 23330, 23426, 23448, 23451, 23467, 23522, 23537, 23567, 23568, 23613, 23615, 23639, 23653, 23656, 23670, 23680, 23683, 23712, 23713, 23717, 23720, 23731, 23741, 23768, 23775, 23779, 23839, 23877, 23880, 23949, 23967, 24307, 24313, 24315, 24435, 24438, 24652, 24653, 24674, 24700, 24713, 24714, 24740, 24798, 24819, 24894, 24897, 24936, 25019, 25045, 25048, 25049, 25050, 25086, 25110, 25126, 25153, 25258, 25315, 25318, 25336, 25337, 25349, 25353, 25371, 25516, 25638, 25642, 25666, 25880, 25894, 25896, 25897, 25900, 25924, 25967, 26056, 26089, 26107, 26108, 26246, 26298, 26356, 26359, 26372, 26373, 26381, 26382, 26388, 26394, 26397, 26451, 26460, 26477, 26554, 26575, 26580, 26635, 26695, 26715, 26716, 26736, 26883, 26892, 26895, 26900, 26939, 26948, 27168, 27169, 27378, 27380, 27426, 27438, 27445, 27499, 27513, 27554, 27632, 27691, 27711, 27712, 27714, 27718, 27775, 27780, 27807, 27811, 27813, 27825, 27831, 27875, 27937, 27954, 28089, 28094, 28117, 28119, 28132, 28134, 28139, 28156, 28158, 28161, 28184, 28194, 28218, 28256, 28358, 28378, 28446, 28466, 28526, 28628, 28634, 28659, 28702, 28786, 28868, 28885, 28899, 28912, 28924, 28935, 28945, 29014, 29045, 29055, 29236, 29270, 29272, 29349, 29398, 29494, 29495, 29526, 29642, 29643, 29648, 30794, 31102, 31306, 31307, 31395, 32252, 32258, 32294, 32299, 32373, 32388, 32404, 32478, 32487, 32500, 32708, 32729, 32763, 32767, 32768, 32794, 32951, 33000, 33051, 33055, 33056, 33108, 33111, 33207, 33274, 33278, 33373, 33376, 33436, 33458, 33459, 33490, 33519, 33595, 33749, 34111, 34264, 34265, 34713, 34941, 35084, 35362, 35491, 35493, 35496, 35696, 35755, 35756, 35873, 35942, 35943, 36032, 36033, 36097, 36101, 36106, 36108, 36131, 36287, 36395, 36397, 36411, 36499, 36516, 36581, 36582, 36590, 36592, 36744, 36745, 36792, 36828, 36830, 36831, 36868, 37150, 37185, 37207, 37210, 37218, 37232, 37237, 37238, 37256, 37258, 37264, 37265, 37344, 37384, 37392, 37393, 37481, 37602, 37605, 37606, 37677, 37748, 37749, 37763, 37775, 37776, 37779, 37804, 37806, 37809, 37810, 37816, 37826, 37834, 37836, 37843, 37933, 37948, 37950, 37951, 38014, 38070, 38072, 38087, 38091, 38093, 38098, 38101, 38104, 38107, 38245, 38254, 38331, 38332, 38342, 38352, 38356, 38466, 38528, 38551, 38552, 38652, 38690, 38695, 38696, 38740, 38741, 38749, 38778, 38779, 38867, 38953, 38977, 38978, 38991, 38992, 39008, 39017, 39020, 39022, 39034, 39035, 39070, 39078, 39079, 39120, 39122, 39127, 39157, 39163, 39168, 39172, 39199, 39206, 39215, 39216, 39222, 39233, 39234, 39237, 39256, 39285, 39296, 39297, 39298, 39299, 39360, 39375, 39460, 39476, 39481, 39487, 39498, 39500, 39504, 39508, 39509, 39522, 39612, 39613, 39616, 39617, 39635, 39652, 39688, 39689, 39727, 39728, 39751, 39773, 40000, 40107, 40141, 40146, 40147, 40208, 40267, 40269, 40271, 40272, 40277, 40332, 40333, 40345, 40364, 40367, 40369, 40374, 40384, 40424, 40425, 40505, 40549, 40613, 40617, 40663, 40664, 40732, 40733, 40746, 40874, 40875, 40880, 40882, 40887, 40892, 40895, 40924, 40938, 40940, 40941, 40946, 40982, 40984, 40987, 41021, 41028, 41029, 41034, 41036, 41105, 41121, 41191, 41194, 41238, 41241, 41308, 41310, 41380, 41382, 41384, 41434, 41469, 41471, 41552, 41581, 41584, 41586, 41588, 41589, 41591, 41592, 41622, 41724, 41725, 41729, 41744, 41745, 41747, 41748, 41752, 41793, 41794, 41836, 41838, 41866, 41869, 41879, 41882, 41893, 41903, 41904, 41911, 41937, 41942, 41944, 41945, 42070, 42075, 42432, 42662, 42691, 42692, 42695, 42698, 42709, 42738, 42740, 42741, 42747, 42749, 42763, 42801, 42814, 42815, 42818, 42907, 42915, 42917, 42934, 42942, 42949, 42950, 42951, 42965, 42967, 42984, 43039, 43087, 43162, 43174, 43175, 43226, 43228, 43271, 43272, 43286, 43333, 43339, 43355, 43396, 43432, 43450, 43463, 43488, 43491, 43497, 43539, 43562, 43587, 43611, 43632, 43633, 43645, 43646, 43651, 43683, 43698, 43700, 43823, 43824, 43864, 43867, 43874, 43920, 44034, 44035, 44048, 44065, 44067, 44071, 44076, 44186, 44204, 44231, 44307, 44333, 44334, 44337, 44457, 44475, 44476, 44479, 44481, 44572, 44582, 44624, 44625, 44637, 44709, 44800, 44801, 44868, 44903, 44910, 44978, 45026, 45027, 45245, 45246, 45344, 45465, 45488, 45807, 45863, 45920, 45985, 45986, 46112, 46113, 46114, 46610, 46916, 47202, 47237, 47240, 47256, 47306, 47321, 47613, 47851, 48618, 48808, 48838, 49011, 49055, 49056, 49062, 49115, 49125, 49330, 49332, 49333, 49336, 49505, 49817, 50001, 50002, 50005, 50212, 50214, 50319, 50321, 50322, 50574, 51280, 51281, 51850, 52255, 52817, 52903, 52904, 52933, 52940, 53100, 53355, 53647, 53765, 53813, 53960, 53961, 54026, 54027, 54033, 54048, 54219, 54225, 54230, 54243, 54244, 54259, 54741, 54742, 54743, 55000, 55131, 55138, 55180, 55239, 55263, 55506, 55508, 55686, 55841, 55912, 55970, 55971, 56174, 56307, 56370, 56371, 56372, 56564, 56757, 56759, 57045, 57099, 57213, 57214, 57479, 57493, 57624, 57836, 57837, 57838, 58204, 58253, 58582, 58698, 58990, 58995, 59020, 59069, 59346, 59453, 59915, 59982, 59987, 60086, 60133, 60179, 60233, 60322, 60327, 60606, 61503, 61733, 61910, 61988, 61994, 61996, 61998, 62000, 62001, 62002, 62003, 62006, 62028, 62259, 62374, 62454, 62455, 62456, 62457, 62483, 62485, 62723, 62804, 62852, 62876, 63075, 63157, 63361, 63397, 63524, 63662, 63924, 64062, 64290, 64395, 64397, 64404, 64405, 64409, 64410, 64467, 64470, 64527, 64723, 64784, 65486, 65588, 65724, 66142, 66145, 66311, 66454, 66549, 66551, 66552, 66990, 67226, 67246, 67302, 67403, 67756, 67757, 67759, 67760, 68126]

const NORAD_NAMES: Dictionary = {
	41866: "GOES-16",
	43226: "Satellite 43226",
	43271: "Satellite 43271",
	43632: "Satellite 43632",
	44186: "Satellite 44186",
	44231: "Satellite 44231",
	44637: "Satellite 44637",
	45026: "Satellite 45026",
	45807: "Satellite 45807",
	48618: "Satellite 48618",
	54741: "Satellite 54741",
	55000: "Satellite 55000",
}


func get_satellites()->Array[Node3D]:
	return _satellites
const FALLBACK_DATA: Dictionary = {
	41866: {"country": "US", "launch": "2016-11-19", "type": "PAYLOAD", "period": 1436.1, "inclination": 0.0},
	43226: {"country": "IN", "launch": "2018-03-29", "type": "PAYLOAD", "period": 98.0, "inclination": 97.0},
	43271: {"country": "RU", "launch": "2018-07-14", "type": "PAYLOAD", "period": 97.3, "inclination": 97.5},
	43632: {"country": "US", "launch": "2018-11-19", "type": "PAYLOAD", "period": 96.0, "inclination": 53.0},
	44186: {"country": "IT", "launch": "2019-03-22", "type": "PAYLOAD", "period": 97.0, "inclination": 97.8},
	44231: {"country": "CN", "launch": "2019-04-20", "type": "PAYLOAD", "period": 376.6, "inclination": 55.0},
	44637: {"country": "US", "launch": "2019-11-11", "type": "PAYLOAD", "period": 95.9, "inclination": 53.0},
	45026: {"country": "US", "launch": "2020-01-29", "type": "PAYLOAD", "period": 94.0, "inclination": 53.0},
	45807: {"country": "US", "launch": "2020-09-03", "type": "PAYLOAD", "period": 96.0, "inclination": 53.0},
	48618: {"country": "US", "launch": "2021-06-30", "type": "PAYLOAD", "period": 97.4, "inclination": 53.0},
	54741: {"country": "US", "launch": "2022-12-28", "type": "PAYLOAD", "period": 95.8, "inclination": 43.0},
	55000: {"country": "US", "launch": "2023-02-27", "type": "PAYLOAD", "period": 96.1, "inclination": 53.0},
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
	sat.look_at($"../../Słońce/ziemia axis/Ziemia".global_position)
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
			sat.data = api_data
			sat.set_country_text(api_data.name)
			print("[Spawner] Pobrano dane z API dla: ", api_data.name)
			satellite_data_ready.emit(api_data)
			var gemini = get_node_or_null("/root/GeminiService")
			if gemini:
				gemini.fetch_description(api_data)
			break


func _on_network_data_failed(norad_id: int, reason: String) -> void:
	print("[Spawner] Problem z API dla ID ", norad_id, ": ", reason, " — using local fallback")
	var fallback := SatelliteData.new()
	fallback.norad_id = norad_id
	var display_name: String = NORAD_NAMES.get(norad_id, "")
	if display_name.is_empty():
		for entry in SatelliteCatalog.get_satellites():
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
