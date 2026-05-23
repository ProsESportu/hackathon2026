extends Node

signal description_ready(norad_id: int, description: String)

const API_KEY: String = "AIzaSyBiDOTjhJn6M8Szt4X7ojwU9dnbOM0Z5tw"

const PROMPT_TEMPLATE: String = (
	"Wygeneruj krótki, encyklopedyczny opis satelity o nazwie {name} (NORAD ID: {norad_id}). " +
	"Informacje dodatkowe: kraj: {country}, data wystrzelenia: {launch_date}, okres: {period} min, inklinacja: {inclination}°. " +
	"\n\nZastosuj się bezwzględnie do poniższych zasad formatowania:" +
	"\n1. Odpowiedź musi składać się z dokładnie 5 punktów (wypunktowana lista)." +
	"\n2. Każdy punkt musi być wyłącznie jednym, krótkim zdaniem." +
	"\n3. Pierwszy punkt musi zawierać oficjalną nazwę satelity oraz datę jej wystrzelenia." +
	"\n4. Kolejne punkty mają opisywać odpowiednio: misję/cel, orbitę, historyczne osiągnięcie lub ciekawostkę oraz obecny status satelity." +
	"\n5. Użyj pogrubienia na początku każdego punktu dla kluczowych fraz (np. **Nazwa i data:**, **Misja:**, **Orbita:**, **Ciekawostka:**, **Status:**)." +
	"\n6. Pisz w języku polskim, zachowaj zwięzły i profesjonalny ton. Nie dodawaj żadnego wstępu ani podsumowania."
)

const API_URL: String = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent?key="

# Zmienna blokująca wielokrotne wywołania
var _is_fetching: bool = false

func fetch_description(sat_data: SatelliteData) -> void:
	# 1. Sprawdzenie blokady
	if _is_fetching:
		push_warning("[GeminiService] Zapytanie w toku. Ignoruję próbę pobrania dla NORAD: %d" % sat_data.norad_id)
		return
		
	if API_KEY == "AIzaSyBiDOTjhJn6M8Szt4X7ojwU9dnbOM0Z5twa":
		push_warning("[GeminiService] API key not set — skipping description fetch.")
		return

	# 2. Założenie blokady
	_is_fetching = true
	print("[GeminiService] Rozpoczynam pobieranie dla NORAD: %d" % sat_data.norad_id)

	var prompt: String = PROMPT_TEMPLATE.format({
		"name":        sat_data.name if not sat_data.name.is_empty() else "Nieznany satelita",
		"norad_id":    str(sat_data.norad_id),
		"country":     sat_data.country if not sat_data.country.is_empty() else "nieznany kraj",
		"launch_date": sat_data.launch_date if not sat_data.launch_date.is_empty() else "nieznana data",
		"period":      "%.1f" % sat_data.period_min,
		"inclination": "%.1f" % sat_data.inclination_deg,
	})

	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_response.bind(sat_data.norad_id, http))

	var body: String = JSON.stringify({
		"contents": [{"parts": [{"text": prompt}]}]
	})
	
	http.request(API_URL + API_KEY, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)


func _on_response(result: int, response_code: int, _headers: PackedStringArray,
		body: PackedByteArray, norad_id: int, http: HTTPRequest) -> void:
	
	# 3. Zdjęcie blokady niezależnie od wyniku
	_is_fetching = false
	http.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		var error_msg = "Błąd HTTP %d" % response_code
		push_warning("[GeminiService] %s dla NORAD %d" % [error_msg, norad_id])
		description_ready.emit(norad_id, "Wystąpił błąd połączenia z AI (%s)." % error_msg)
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		push_warning("[GeminiService] JSON parse error for NORAD %d" % norad_id)
		description_ready.emit(norad_id, "Błąd odczytu danych z AI.")
		return

	var data = json.get_data()
	var candidates = data.get("candidates", [])
	if candidates.is_empty():
		description_ready.emit(norad_id, "AI nie zwróciło żadnych wyników.")
		return

	var parts = candidates[0].get("content", {}).get("parts", [])
	if parts.is_empty():
		description_ready.emit(norad_id, "AI zwróciło pustą treść.")
		return

	var text: String = parts[0].get("text", "").strip_edges()
	if not text.is_empty():
		description_ready.emit(norad_id, text)
	else:
		description_ready.emit(norad_id, "Błąd: Brak wygenerowanego tekstu.")
