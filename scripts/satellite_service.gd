extends Node

# Sygnały dla skryptu Spawner
signal satellite_fetched(data: SatelliteData)
signal satellite_fetch_failed(norad_id: int, reason: String)

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
	
	http_client.use_threads = true

	# POPRAWKA: Prawidłowy URL do Celestrak API pobierający dane w formacie JSON
	var url = "https://celestrak.org" % norad_id

	var error = http_client.request(url, custom_headers, HTTPClient.METHOD_GET)
	if error != OK:
		satellite_fetch_failed.emit(norad_id, "HTTP Initial Request Failed")
		http_client.queue_free()

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, norad_id: int, client_node: Node) -> void:
	client_node.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		satellite_fetch_failed.emit(norad_id, "TLE HTTP %d (Engine Result Code)" % result)
		return

	if response_code != 200:
		satellite_fetch_failed.emit(norad_id, "Server Rejected Code %d" % response_code)
		return

	# ... (góra funkcji pozostaje bez zmian, podmieniamy od tego miejsca):

	var json = JSON.new()
	var parse_err = json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		satellite_fetch_failed.emit(norad_id, "JSON parsing error")
		return

	var response_data = json.get_data()
	
	# POPRAWKA: Celestrak zwraca tablicę obiektów [], a nie pojedynczy słownik {}
	if typeof(response_data) != TYPE_ARRAY or response_data.is_empty():
		satellite_fetch_failed.emit(norad_id, "No valid JSON array returned")
		return

	# Wyciągamy pierwszy (i jedyny) obiekt z tablicy
	var sat_json = response_data[0]
	if typeof(sat_json) != TYPE_DICTIONARY:
		satellite_fetch_failed.emit(norad_id, "Array element is not a dictionary")
		return

	# Tworzymy zestaw danych kosmicznych
	var satellite_data = SatelliteData.new()
	satellite_data.norad_id = norad_id
	
	# Wyciągamy prawdziwą nazwę z klucza OBJECT_NAME
	satellite_data.name = sat_json.get("OBJECT_NAME", "Unknown")
	
	# Celestrak w JSON przesyła surowe parametry zamiast linii tekstowych TLE.
	# Zapisujemy je pomocniczo, bazując na odpowiedzi z API:
	satellite_data.tle_line1 = "1 %05dU ... " % norad_id
	satellite_data.tle_line2 = "2 %05dU %s" % [norad_id, sat_json.get("MEAN_MOTION", "")]
	
	# Emitujemy sygnał – dane lecą do obiektów 3D
	satellite_fetched.emit(satellite_data)
