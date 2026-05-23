class_name SatelliteCatalog

# Each entry: { norad_id: int, display_name: String }
const SATELLITES: Array = [
	{ "norad_id": 25544, "display_name": "ISS" },
	{ "norad_id": 20580, "display_name": "Hubble Space Telescope" },
	{ "norad_id": 49260, "display_name": "Landsat 9" },
	{ "norad_id": 39084, "display_name": "Landsat 8" },
	{ "norad_id": 25994, "display_name": "Terra" },
	{ "norad_id": 27424, "display_name": "Aqua" },
	{ "norad_id": 40069, "display_name": "Sentinel-1A" },
	{ "norad_id": 41335, "display_name": "Sentinel-3A" },
	{ "norad_id": 33591, "display_name": "NOAA-19" },
	{ "norad_id": 43013, "display_name": "NOAA-20" },
	{ "norad_id": 41866, "display_name": "GOES-16" },
	{ "norad_id": 40376, "display_name": "DSCOVR" },
	{ "norad_id": 38771, "display_name": "NuSTAR" },
	{ "norad_id": 36119, "display_name": "WISE" },
	{ "norad_id": 44713, "display_name": "Starlink-1007" },
]

static func get_random() -> Dictionary:
	return SATELLITES[randi_range(0, SATELLITES.size() - 1)]

static func get_random_excluding(exclude_norad_id: int) -> Dictionary:
	var candidates: Array = SATELLITES.filter(func(s): return s["norad_id"] != exclude_norad_id)
	return candidates[randi_range(0, candidates.size() - 1)]
