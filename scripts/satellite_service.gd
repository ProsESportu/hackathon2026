extends Node

# Sygnały dla skryptu Spawner
signal satellite_fetched(data: SatelliteData)
signal satellite_fetch_failed(norad_id: int, reason: String)

var _auth_cookie: String = ""
var _is_authenticating: bool = false
var _queued_requests: Array[int] = []

const SP_USER = "adamrzem08@gmail.com"
const SP_PASS = "ijRKZ9gxYCKFmWN"

func fetch_satellite_data(norad_id: int) -> void:
	if _auth_cookie.is_empty():
		_queued_requests.append(norad_id)
		if not _is_authenticating:
			_authenticate()
	else:
		_fetch_satcat(norad_id)

func _authenticate() -> void:
	_is_authenticating = true
	var http_client = HTTPRequest.new()
	add_child(http_client)
	
	http_client.request_completed.connect(_on_auth_completed.bind(http_client))
	
	var url = "https://www.space-track.org/ajaxauth/login"
	var body = "identity=" + SP_USER.uri_encode() + "&password=" + SP_PASS.uri_encode()
	var headers = ["Content-Type: application/x-www-form-urlencoded"]
	
	http_client.request(url, headers, HTTPClient.METHOD_POST, body)

func _on_auth_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, client: HTTPRequest) -> void:
	client.queue_free()
	_is_authenticating = false
	
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		for id in _queued_requests:
			satellite_fetch_failed.emit(id, "Auth Failed with code %d" % response_code)
		_queued_requests.clear()
		return
		
	for header in headers:
		var lower_header = header.to_lower()
		if lower_header.begins_with("set-cookie:"):
			var cookie_content = header.substr(11).strip_edges().split(";")[0]
			if not _auth_cookie.is_empty():
				_auth_cookie += "; "
			_auth_cookie += cookie_content
			
	for id in _queued_requests:
		_fetch_satcat(id)
	_queued_requests.clear()

func _fetch_satcat(norad_id: int) -> void:
	var client = HTTPRequest.new()
	add_child(client)
	var url = "https://www.space-track.org/basicspacedata/query/class/satcat/NORAD_CAT_ID/%d/emptyresult/show" % norad_id
	var headers = ["Cookie: " + _auth_cookie]
	client.request_completed.connect(_on_satcat_completed.bind(norad_id, client))
	client.request(url, headers, HTTPClient.METHOD_GET)

func _on_satcat_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, norad_id: int, client: HTTPRequest) -> void:
	client.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		if response_code == 401:
			_auth_cookie = "" # Reset on unauthorized
		satellite_fetch_failed.emit(norad_id, "Satcat fetch failed %d" % response_code)
		return
		
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		satellite_fetch_failed.emit(norad_id, "Satcat JSON parse error")
		return
		
	var data = json.get_data()
	if typeof(data) != TYPE_ARRAY or data.is_empty():
		satellite_fetch_failed.emit(norad_id, "Satcat Empty data")
		return
		
	var sat_json = data[0]
	var satellite_data = SatelliteData.new()
	satellite_data.norad_id = norad_id
	
	satellite_data.name = str(sat_json.get("SATNAME", "Unknown"))
	satellite_data.country = str(sat_json.get("COUNTRY", "Unknown"))
	satellite_data.launch_date = str(sat_json.get("LAUNCH", "Unknown"))
	satellite_data.object_type = str(sat_json.get("OBJECT_TYPE", "Unknown"))
	
	satellite_data.period_min = str(sat_json.get("PERIOD", "0.0")).to_float()
	satellite_data.inclination_deg = str(sat_json.get("INCLINATION", "0.0")).to_float()
	satellite_data.apogee_km = str(sat_json.get("APOGEE", "0.0")).to_float()
	satellite_data.perigee_km = str(sat_json.get("PERIGEE", "0.0")).to_float()

	# Po pobraniu SatCat, pobieramy TLE
	_fetch_tle(satellite_data)

func _fetch_tle(sat_data: SatelliteData) -> void:
	var client = HTTPRequest.new()
	add_child(client)
	var url = "https://www.space-track.org/basicspacedata/query/class/gp/NORAD_CAT_ID/%d/emptyresult/show" % sat_data.norad_id
	var headers = ["Cookie: " + _auth_cookie]
	client.request_completed.connect(_on_tle_completed.bind(sat_data, client))
	client.request(url, headers, HTTPClient.METHOD_GET)

func _on_tle_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, sat_data: SatelliteData, client: HTTPRequest) -> void:
	client.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		satellite_fetch_failed.emit(sat_data.norad_id, "TLE fetch failed %d" % response_code)
		return
		
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		satellite_fetch_failed.emit(sat_data.norad_id, "TLE JSON parse error")
		return
		
	var data = json.get_data()
	if typeof(data) != TYPE_ARRAY or data.is_empty():
		satellite_fetch_failed.emit(sat_data.norad_id, "TLE Empty data")
		return
		
	var tle_json = data[0]
	sat_data.tle_line1 = str(tle_json.get("TLE_LINE1", ""))
	sat_data.tle_line2 = str(tle_json.get("TLE_LINE2", ""))
	
	_fetch_image_metadata(sat_data)

func _fetch_image_metadata(sat_data: SatelliteData) -> void:
	if sat_data.norad_id == 40390: # DSCOVR
		_fetch_dscovr_metadata(sat_data)
	elif sat_data.norad_id == 41866 or sat_data.name.begins_with("GOES"): # GOES-16
		sat_data.photo_url = "https://cdn.star.nesdis.noaa.gov/GOES16/ABI/FD/GEOCOLOR/1808x1808.jpg"
		_download_image(sat_data)
	else:
		_fetch_wikipedia_metadata(sat_data)

func _fetch_dscovr_metadata(sat_data: SatelliteData) -> void:
	var client = HTTPRequest.new()
	add_child(client)
	var url = "https://api.nasa.gov/EPIC/api/natural/images?api_key=DEMO_KEY"
	client.request_completed.connect(_on_dscovr_metadata_completed.bind(sat_data, client))
	client.request(url)

func _on_dscovr_metadata_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, sat_data: SatelliteData, client: HTTPRequest) -> void:
	client.queue_free()
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			var data = json.get_data()
			if typeof(data) == TYPE_ARRAY and not data.is_empty():
				var img_data = data[0]
				var img_name = img_data.get("image", "")
				var date_str = img_data.get("date", "") # format "YYYY-MM-DD HH:MM:SS"
				if img_name != "" and date_str != "":
					var date_parts = date_str.split(" ")[0].split("-")
					if date_parts.size() == 3:
						var y = date_parts[0]
						var m = date_parts[1]
						var d = date_parts[2]
						sat_data.photo_url = "https://epic.gsfc.nasa.gov/archive/natural/%s/%s/%s/png/%s.png" % [y, m, d, img_name]
						_download_image(sat_data)
						return
						
	# Fallback if DSCOVR fails
	satellite_fetched.emit(sat_data)

func _fetch_wikipedia_metadata(sat_data: SatelliteData) -> void:
	var client = HTTPRequest.new()
	add_child(client)
	# Encode the satellite name
	var search_title = sat_data.name.uri_encode()
	var url = "https://en.wikipedia.org/w/api.php?action=query&titles=%s&prop=pageimages&format=json&pithumbsize=500" % search_title
	var custom_headers = ["User-Agent: GodotSatelliteApp/1.0"]
	client.request_completed.connect(_on_wikipedia_metadata_completed.bind(sat_data, client))
	client.request(url, custom_headers, HTTPClient.METHOD_GET)

func _on_wikipedia_metadata_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, sat_data: SatelliteData, client: HTTPRequest) -> void:
	client.queue_free()
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			var data = json.get_data()
			var pages = dict_get_path(data, ["query", "pages"])
			if typeof(pages) == TYPE_DICTIONARY and not pages.is_empty():
				var first_page = pages.values()[0]
				var thumbnail = first_page.get("thumbnail", {})
				if not thumbnail.is_empty():
					sat_data.photo_url = thumbnail.get("source", "")
					if not sat_data.photo_url.is_empty():
						_download_image(sat_data)
						return

	# No image found or error, just emit what we have
	satellite_fetched.emit(sat_data)

func _download_image(sat_data: SatelliteData) -> void:
	var client = HTTPRequest.new()
	add_child(client)
	client.request_completed.connect(_on_image_download_completed.bind(sat_data, client))
	client.request(sat_data.photo_url)

func _on_image_download_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, sat_data: SatelliteData, client: HTTPRequest) -> void:
	client.queue_free()
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var image = Image.new()
		var err = OK
		
		# Proste wykrywanie formatu
		var url_lower = sat_data.photo_url.to_lower()
		if url_lower.ends_with(".png"):
			err = image.load_png_from_buffer(body)
		elif url_lower.ends_with(".jpg") or url_lower.ends_with(".jpeg"):
			err = image.load_jpg_from_buffer(body)
		elif url_lower.ends_with(".webp"):
			err = image.load_webp_from_buffer(body)
		else:
			# Spróbuj wszystkie jeśli nieznane rozszerzenie
			err = image.load_jpg_from_buffer(body)
			if err != OK: err = image.load_png_from_buffer(body)
			if err != OK: err = image.load_webp_from_buffer(body)

		if err == OK:
			sat_data.photo_image = image

	satellite_fetched.emit(sat_data)

func dict_get_path(d: Dictionary, path: Array):
	var curr = d
	for key in path:
		if typeof(curr) == TYPE_DICTIONARY and curr.has(key):
			curr = curr[key]
		else:
			return null
	return curr
