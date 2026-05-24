# Orbital Hunter

**SPACE 4 TALENTS — Stalowa Wola 2026 / Challenge: SPACE ENTERTAINER**

Orbital Hunter is a playable spectacle that turns real satellite motion, live
orbital data and the poetry of cosmic chance into a marketing-grade interactive
experience. The city of Stalowa Wola becomes a glowing ground station on a
spinning Earth; the night sky becomes a hunting ground; every captured
satellite triggers a *Cosmic Lottery* whose reels are seeded by that
satellite's real orbital parameters.

Built in Godot 4.6 for the SPACE ENTERTAINER open challenge.

---

## Koncepcja / Concept

> *„SPACE ENTERTAINER to twórca światów, który potrafi przekuć najbardziej
> złożone zjawiska — ruch satelitów, układ miejski, historię regionu,
> przepływy danych, nawet samą losowość losu — w formy, które bawią,
> inspirują i przyciągają uwagę.”*

Orbital Hunter realizuje ten brief w formie krótkiej, efektownej gry 3D:

- **Ruch satelitów** — pozycje obiektów na orbicie liczone są w czasie
  rzeczywistym z prawdziwych elementów TLE pobieranych ze Space-Track.
- **Zobrazowania kosmiczne** — opisy i miniatury złapanych satelitów
  generowane są przez Google Gemini na żywo, w języku polskim.
- **Układ miejski / historia regionu** — Stalowa Wola jest osadzona na
  globie jako świecący znacznik naziemnej stacji uplinku
  (50.5826° N, 22.0533° E), z pulsującą wiązką uaktywnianą, gdy nad
  miastem przelatuje aktualnie śledzony satelita.
- **Kosmiczny przypadek** — każdy zdobyty satelita uruchamia trzybębnowy
  *Cosmic Lottery* slot, w którym symbole są wyprowadzone z realnych
  parametrów orbitalnych (NORAD ID, inklinacja, okres obiegu) plus
  drobna losowość, więc każdy spin opowiada inną „historię losu”
  konkretnego obiektu na niebie.

Nie jest to hazard — to fabularna i marketingowa metafora przypadku,
zgodna z opisem wyzwania.

---

## Pętla rozgrywki / Gameplay loop

1. **Start w głębokim kosmosie** — sterujesz statkiem 6-DoF
   z proceduralnie cieniowanym Słońcem i Drogą Mleczną w tle.
2. **Podejście do Ziemi** — HUD pokazuje strzałkę naprowadzającą
   na Ziemię, gdy planeta wypada z kadru, oraz odległość w jednostkach
   sceny.
3. **Wejście na orbitę** — po przekroczeniu progu
   `ORBIT_ENTER_RADIUS = 0.80` aktywuje się cinematic „WCHODZISZ NA
   ORBITĘ”, statek jest przepinany do układu odniesienia Ziemi
   (`EarthFrame`) i zatrzymywany — od tej chwili lecisz razem z planetą.
4. **Polowanie** — w widoku orbitalnym widać satelity propagowane
   z prawdziwych TLE; podlatujesz blisko jednego z nich.
5. **Capture (X)** — otwiera się modal z polskim opisem satelity od
   Gemini + miniaturą; aby zdobyć obiekt, musisz przejść mini-grę
   *connect wires* (wiązka kabli — diagnostyka uplinku).
6. **Cosmic Lottery** — po rozwiązaniu zagadki spinają się trzy bębny;
   wynik zależy od NORAD ID, inklinacji i okresu wybranego satelity.
   Jeśli akurat nad Stalową Wolą przelatuje śledzony obiekt — mnożnik
   ×2 „STALOWA WOLA UPLINK ACTIVE”.
7. **Respawn** — zdobyty satelita znika gdy wyjdzie z kadru, w jego
   miejsce pojawia się nowy, losowy obiekt z katalogu NORAD i pętla
   powtarza się dowolnie długo.

Cały scenariusz został zaprojektowany jako lekki, widowiskowy
„przerywnik” pasujący do materiałów promocyjnych przyszłych edycji
SPACE 4 TALENTS.

---

## Sterowanie / Controls

| Akcja | Klawisz |
|---|---|
| Ciąg do przodu / wstecz | `W` / `S` |
| Strafe lewo / prawo | `A` / `D` |
| Strafe góra / dół | `Spacja` / `Shift` |
| Yaw / Pitch | Mysz |
| Roll | `Q` / `E` |
| Capture satelity | `X` |
| Pomoc | `H` |

Obsługa pada (lewy/prawy drążek, triggery) jest skonfigurowana w
`project.godot`. Istnieje również eksperymentalny most wejściowy
przez UDP dla sterowania z zewnętrznego urządzenia (Raspberry Pi z
żyroskopem — patrz `raspberryPi/`).

---

## Zastosowane technologie i dane / Tech stack and data sources

**Silnik i język**
- Godot 4.6 (GL Compatibility renderer, Jolt Physics)
- GDScript

**Dane satelitarne (na żywo)**
- **Space-Track.org REST API** — pobieranie aktualnych dwuliniowych
  elementów orbitalnych (TLE) dla losowanych NORAD ID
  (`scripts/satellite_service.gd`).
- **Lokalny katalog NORAD ID** (`norad_ids.json`,
  `scripts/satellite_catalog.gd`) — pula zaufanych identyfikatorów
  losowanych przed pobraniem TLE z sieci.
- **Propagator orbitalny** (`scripts/orbital_position.gd`) — liczy
  kierunek satelity z TLE w czasie rzeczywistym; satelity są
  umieszczane na powłoce `SAT_ORBIT_RADIUS` zgodnie z ich realnym
  położeniem w danej chwili (okres ~90 min jest zachowany).

**Treści generowane przez AI**
- **Google Gemini API** (`scripts/gemini_service.gd`) — generuje
  polskojęzyczne, popularno-naukowe opisy każdego zdobytego
  satelity wraz z jego zastosowaniem i ciekawostkami.

**Zobrazowania kosmiczne**
- Tekstury planet Układu Słonecznego (Jowisz, Mars, Merkury, Neptun,
  Saturn z pierścieniami, Uran, Wenus) w rozdzielczości 2K.
- Ziemia 8K — mapa dzienna, mapa nocna (świecące miasta) i mapa
  normalnych, mieszane shaderem dnia/nocy względem kierunku Słońca.
- Tło Drogi Mlecznej 8K.
- Proceduralny shader Słońca z pulsacją emisji.

**Mechaniki**
- `scripts/orbit_manager.gd` — automat stanów IN_SPACE / IN_ORBIT,
  histereza wejścia/wyjścia, ostrzeżenie zbliżenia do powierzchni,
  reparenting statku do układu odniesienia Ziemi.
- `scripts/flight_controller.gd` — fizyka 6-DoF, deterministyczny snap
  pozycji i zerowanie prędkości przy wejściu na orbitę, korekcja
  prędkości przy zmianie układu.
- `scripts/satellite_spawner.gd` — losowanie NORAD ID, spawn/despawn
  poza frustum kamery, anchor pozycji do live TLE.
- `connect_wires.gd` + `puzzle_minigame.gd` + `memory.gd` — mini-gry
  capture'u (połącz przewody, pamięć).
- `scripts/cosmic_lottery.gd` *(slot inspirowany realnymi parametrami
  orbitalnymi)* — bębny z symbolami wyprowadzonymi z NORAD ID,
  inklinacji i okresu obiegu.
- `scripts/ground_station.gd` — znacznik Stalowej Woli na globie,
  detekcja przelotu satelity i sygnał aktywujący mnożnik loterii.
- `scripts/hud.gd` + `scenes/HUD.tscn` — komunikaty „ENTERING ORBIT”,
  „PROXIMITY ALERT”, „ORBIT LOST”, branding SPACE 4 TALENTS /
  STALOWA WOLA, licznik kredytów.

**Opcjonalny kontroler hardware'owy**
- `raspberryPi/gyro.py` + `raspberryPi/screen.py` — sterowanie statkiem
  i wyświetlanie mini-gry slotów na ekranie LCD przy użyciu Raspberry
  Pi z żyroskopem; komunikacja UDP z grą. Flaga `DISABLE_PI` w
  silniku pozwala demonstrować projekt bez podpiętego Pi.

---

## Uruchomienie / How to run

### Wersja zbudowana (Windows)

W katalogu projektu znajduje się gotowy build:

```
Orbital Hunter.exe
Orbital Hunter.pck
```

Uruchom `Orbital Hunter.exe`. Wymagane jest połączenie z Internetem
dla pobierania TLE ze Space-Track i opisów z Gemini (gra ma fallback
na lokalne dane, jeśli sieć zawiedzie).

### Wersja źródłowa

1. Zainstaluj **Godot 4.6** (https://godotengine.org).
2. Otwórz `project.godot` w edytorze.
3. Skonfiguruj klucze API (jeśli chcesz danych na żywo):
   - Space-Track — w `scripts/satellite_service.gd`
   - Gemini — w `scripts/gemini_service.gd`
4. `F5`, scena startowa: `collision_shape_3d.tscn`.

### Sterowanie z Raspberry Pi (opcjonalne)

1. Wgraj zawartość `raspberryPi/` na Pi z czujnikiem żyroskopu.
2. Ustaw IP Pi na `192.168.0.128` (lub zmień w
   `scripts/input_bridge.gd` / `scripts/minigame_broadcaster.gd`).
3. Uruchom `gyro.py` (sterowanie) i `screen.py` (mini-gra slotów na
   ekranie Pi).

---

## Struktura projektu / Project layout

```
collision_shape_3d.tscn    Główna scena gry (Słońce, planety, Ziemia, gracz)
scenes/
  PlayerSat.tscn           Statek gracza (kamera + sterowanie)
  HUD.tscn                 Nakładka UI (alerty, kredyty, branding)
  satelite.tscn            Pojedynczy satelita z panelami słonecznymi
  puzzle_minigame.tscn     Mini-gra capture'u
connect_wires.tscn         Mini-gra „połącz przewody” (diagnostyka uplinku)
scripts/
  orbit_manager.gd         Automat stanów orbitalnych
  flight_controller.gd     Fizyka statku 6-DoF
  satellite_service.gd     Klient Space-Track (TLE na żywo)
  satellite_catalog.gd     Lokalny katalog NORAD ID
  orbital_position.gd      Propagator pozycji z TLE
  satellite_spawner.gd     Spawn/despawn satelitów w orbicie
  gemini_service.gd        Klient Google Gemini (opisy PL)
  ground_station.gd        Stalowa Wola — uplink + mnożnik loterii
  cosmic_lottery.gd        Slot machine sterowany danymi satelity
  hud.gd                   Logika nakładki UI
raspberryPi/
  gyro.py                  Sterowanie statkiem przez UDP z Pi
  screen.py                Mini-gra slotów na LCD Pi
norad_ids.json             Pula NORAD ID do losowania
```

Pliki planu (`orbit.md`, `impl.md`, `plan2.md`, `satelites.md`,
`improvements.md`) dokumentują kolejne fazy projektu i mogą służyć
jako materiał do prezentacji.

---

## Zgodność z wymaganiami formalnymi wyzwania

- **Opis rozwiązania** — niniejszy README oraz osobna prezentacja
  (≤10 slajdów / film ≤3 min) dostarczana razem z buildem.
- **Wizualizacja koncepcji** — playable build (`Orbital Hunter.exe`)
  + zrzuty ekranu z głównych etapów rozgrywki + dokumenty
  projektowe w katalogu głównym.
- **Opis zastosowanych rozwiązań** — sekcja
  *Zastosowane technologie i dane* powyżej wymienia narzędzia,
  technologie, dane i mechaniki, w tym źródła danych satelitarnych
  (Space-Track, lokalny katalog NORAD) oraz sposób ich przetworzenia
  (propagacja TLE w `scripts/orbital_position.gd`, fabularne
  mapowanie parametrów orbitalnych na symbole slot machine'a w
  `scripts/cosmic_lottery.gd`).
