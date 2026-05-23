Context

The previous plan (Orbit Entry Cinematic + In-Orbit Slowdown) is fully implemented. Playtesting surfaced three more issues that build directly on that work:

1. Entry position is unpredictable. The player crosses ORBIT_ENTER_RADIUS = 0.80 at whatever angle they happened to be coming in at, leaving them anywhere from 0.79 to a hair above Earth's surface (0.50). The cinematic helps, but there's no consistent "you have arrived in a stable orbit" moment.
2. Inherited momentum is still load-bearing. The previous plan clamped incoming velocity to IN_ORBIT_MAX_SPEED = 1.0 (later tuned to 0.4), which prevents crashing through Earth but leaves the player with non-zero motion they didn't ask for. The user wants a full stop at entry — the ship is now in Earth's inertial frame, period.
3. Earth fills the view with no proximity feedback. Once inside orbit, players can drift down toward the surface without realizing they're about to crash — the Earth texture doesn't give a strong depth cue, and the only signal is _on_area_3d_body_entered firing GameOver after they've already hit it.

This plan adds a deterministic entry snap (position + velocity), and adds a persistent HUD warning when the player gets too close to Earth's surface.

Design

Part 1 — Deterministic entry: snap position + zero velocity

In flight_controller.gd::on_orbit_entered:
- Add a new constant ORBIT_ENTRY_DROP_RADIUS: float = 0.655 (midpoint between Earth's surface at EARTH_RADIUS = 0.51 and OrbitManager.ORBIT_ENTER_RADIUS = 0.80). Hard-coded value, with a comment explaining the relationship — neither file should import the other's constant.
- Replace body with:
func on_orbit_entered(_earth_world_velocity: Vector3) -> void:
    in_orbit = true
    velocity = Vector3.ZERO
    var dir: Vector3 = position.normalized() if position.length() > 0.001 else Vector3.BACK
    position = dir * ORBIT_ENTRY_DROP_RADIUS
- The _earth_world_velocity arg becomes unused (prefixed with _). The previous subtraction is now meaningless because we're zeroing velocity anyway, and the velocity clamp from the prior plan is also obsolete.
- position is local to EarthFrame at this point (the player is reparented BEFORE on_orbit_entered is called — see orbit_manager.gd:78), and EarthFrame.global_position == Earth.global_position, so position.length() is the player's distance from Earth's center. Normalizing it preserves the entry direction; multiplying by 0.655 snaps to the midpoint shell.

Why direction-preserving: the player keeps their orientation relative to Earth, just gets dropped to a consistent distance. No abrupt teleport across to the other side of Earth — they slide outward (if they were below 0.655) or inward (if above), only along the radial axis.

Why this is "inertial frame with Earth as point of reference": with velocity = 0 in EarthFrame's local space, and EarthFrame's global_position tracking Earth each _process tick (orbit_manager.gd:55), the player drifts along with Earth's orbital motion automatically — no thrust needed, no inherited momentum from the cinematic. Earth's spin doesn't drag the player because EarthFrame holds identity rotation (only translation tracks Earth).

Part 2 — Earth-proximity warning

In orbit_manager.gd:
- Add constants:
const PROXIMITY_WARN_RADIUS:  float = 0.61   # ~0.10 above Earth surface
const PROXIMITY_CLEAR_RADIUS: float = 0.64   # hysteresis band (0.03 wide)
- Add signals:
signal proximity_alert_started
signal proximity_alert_cleared
- Add state: var _proximity_active: bool = false.
- In _process inside match state: State.IN_ORBIT: branch, after the existing exit/warn checks, add:
if dist < PROXIMITY_WARN_RADIUS and not _proximity_active:
    _proximity_active = true
    proximity_alert_started.emit()
elif dist > PROXIMITY_CLEAR_RADIUS and _proximity_active:
    _proximity_active = false
    proximity_alert_cleared.emit()
- In _exit_orbit: if _proximity_active, emit cleared and reset the flag so the warning doesn't persist after orbit exit.

In scenes/HUD.tscn:
- Add a new ProximityLabel Label node, anchored top-center, visible = false, red, text "⚠ PROXIMITY ALERT — PULL UP". Use a new Theme sub-resource with default_font_size = 56 (visible but smaller than the cinematic banner so it doesn't compete).

In scripts/hud.gd:
- @onready var proximity_label: Label = $ProximityLabel
- var _proximity_tween: Tween
- In _ready, connect orbit_manager.proximity_alert_started.connect(_on_proximity_started) and …cleared.connect(_on_proximity_cleared).
- Handlers:
func _on_proximity_started() -> void:
    proximity_label.visible = true
    proximity_label.modulate.a = 1.0
    if _proximity_tween != null and _proximity_tween.is_valid():
        _proximity_tween.kill()
    _proximity_tween = create_tween().set_loops()
    _proximity_tween.tween_property(proximity_label, "modulate:a", 0.3, 0.4)
    _proximity_tween.tween_property(proximity_label, "modulate:a", 1.0, 0.4)

func _on_proximity_cleared() -> void:
    if _proximity_tween != null and _proximity_tween.is_valid():
        _proximity_tween.kill()
    proximity_label.visible = false

The tween runs at normal time_scale = 1.0 (proximity only triggers while in orbit, after the cinematic has restored normal time), so the 0.4s pulse is real-time.

Critical Files

- C:\Users\adamr\hackathon2026\scripts\flight_controller.gd — add ORBIT_ENTRY_DROP_RADIUS constant; rewrite on_orbit_entered body to zero velocity and snap radial position; drop the now-obsolete earth_world_velocity subtraction and velocity clamp from the prior plan.
- C:\Users\adamr\hackathon2026\scripts\orbit_manager.gd — add proximity constants, two new signals, _proximity_active flag, in-process detection block with hysteresis, and a clear-on-exit guard in _exit_orbit.
- C:\Users\adamr\hackathon2026\scenes\HUD.tscn — add Theme_hud_proximity (size 56) sub-resource and ProximityLabel node (top-center, red, hidden initially).
- C:\Users\adamr\hackathon2026\scripts\hud.gd — @onready ref, tween var, signal connections in _ready, two handlers with a looping pulse tween.

No changes to collision_shape_3d.tscn, PlayerSat.tscn, or the orbit cinematic logic from the previous plan.

Verification

Run collision_shape_3d.tscn (F5):

1. Deterministic snap on entry. Approach Earth from any angle and any speed. The instant you cross ORBIT_ENTER_RADIUS = 0.80, the cinematic fires AND the ship snaps to distance ~0.655 from Earth's center along the entry direction, with zero velocity. After the cinematic ends, the ship is hanging still relative to Earth — no drift unless you thrust.
2. Earth's orbital motion no longer affects the ship. Sit still after the snap. The ship visually translates with Earth around the Sun (because it's reparented under EarthFrame which tracks Earth), but its position relative to Earth stays fixed. No spurious sliding.
3. Proximity warning fires when close. From the entry shell (0.655), thrust toward Earth. At distance ~0.61 from Earth's center (~0.10 above surface), the red "⚠ PROXIMITY ALERT — PULL UP" label appears top-center and pulses. Back off — at distance ~0.64, the warning disappears.
4. No flicker at the boundary. Hover around distance 0.62 (between WARN and CLEAR). The 0.03 hysteresis band should prevent the warning from rapidly toggling.
5. Warning clears on orbit exit. If you happen to be in the warning zone when you drift back out past ORBIT_EXIT_RADIUS = 0.95 (unlikely combo, but possible if you boost outward while close to Earth), the warning should disappear on exit, not stick.
6. No regression on collision. Fly straight into Earth from inside orbit — proximity warning fires, then _on_area_3d_body_entered fires GameOver at the surface. Both behaviors coexist.
7. No regression on entry cinematic / in-orbit slowdown / exit alert. The 1.5s slow-mo cinematic still fires once on entry; the IN_ORBIT_MAX_SPEED cap on thrust still applies; "ORBIT LOST" still fires on exit.

If 0.10 above surface feels too late, lower PROXIMITY_WARN_RADIUS toward 0.66 (more lead time). If the pulse feels too fast/slow, tune the 0.4 second tween durations. If the snap distance feels off, tune ORBIT_ENTRY_DROP_RADIUS (0.655 = midpoint; lower = closer to Earth, higher = closer to exit).