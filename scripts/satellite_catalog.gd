class_name SatelliteCatalog

static var _satellites: Array = []
static var _initialized: bool = false

static func _initialize() -> void:
	if _initialized:
		return
	_initialized = true
	var file := FileAccess.open("res://norad_ids.json", FileAccess.READ)
	if file == null:
		push_error("[SatelliteCatalog] Cannot open res://norad_ids.json")
		return
	var result = JSON.parse_string(file.get_as_text())
	file.close()
	if result == null or not result is Array:
		push_error("[SatelliteCatalog] Invalid JSON in norad_ids.json")
		return
	for id_val in result:
		_satellites.append({"norad_id": int(id_val), "display_name": "Satellite %d" % int(id_val)})

static func get_satellites() -> Array:
	_initialize()
	return _satellites

static func get_random() -> Dictionary:
	_initialize()
	return _satellites[randi_range(0, _satellites.size() - 1)]

static func get_random_excluding(exclude_norad_id: int) -> Dictionary:
	_initialize()
	var candidates: Array = _satellites.filter(func(s): return s["norad_id"] != exclude_norad_id)
	return candidates[randi_range(0, candidates.size() - 1)]
