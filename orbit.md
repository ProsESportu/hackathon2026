Context

Right now the player ship is a 6-DoF arcade flyer drifting in world space. Earth (Ziemia) orbits the Sun via an AnimationPlayer at ~1.5 scene-units/s tangential speed, which means a player parked "next to" Earth gets left behind almost immediately — there's no notion of being captured in Earth's gravitational field. The whole intended gameplay loop (satellite hunting in Earth orbit) can't happen until the player can hold position relative to Earth without manually chasing it.

This plan adds: (1) a single orbital sphere of influence around Earth; (2) a frame switch that reparents the player into Earth's reference frame on entry / world frame on exit, with velocity correction so motion stays continuous; (3) a HUD with fade-in/out text alerts for ENTERED ORBIT, LEAVING ORBIT WARNING, LEFT ORBIT; (4) a screen-edge directional indicator pointing toward Earth when off-camera. Satellites are deliberately out of scope — they're the next plan.

Architecture

Three new pieces, one small edit to existing code:

- EarthFrame — a plain Node3D child of the scene root that each frame mirrors Earth's global_position but keeps identity rotation. This is what the player reparents to on orbit entry. We don't reparent under Ziemia directly because Earth has a spin animation that would also spin the player.
- OrbitManager (scripts/orbit_manager.gd) — a Node attached to the scene root. Owns the state machine (IN_SPACE / IN_ORBIT), runs the distance check in _physics_process, performs the reparent + velocity correction, and emits signals.
- HUD (scenes/HUD.tscn + scripts/hud.gd) — CanvasLayer with two children: a centered Label for alert text (tween-driven fade) and a Control with a TextureRect arrow + Label for the screen-edge Earth indicator. Subscribes to OrbitManager signals.
- scripts/flight_controller.gd — minimal edit: expose velocity (already a member) and add two hook methods on_orbit_entered(earth_vel) / on_orbit_exited(earth_vel) that subtract/add Earth's velocity to the internal velocity Vector3 so frame switches don't cause a perceived "jolt".

The chosen tools are all stock Godot 4.6: Node.reparent(new_parent, keep_global_transform=true), Camera3D.unproject_position() for the edge indicator, Tween for fades. No addons needed.

Constants (tune later)

In orbit_manager.gd:
ORBIT_ENTER_RADIUS  = 0.80   # scene units from Earth center; Earth radius is 0.50
ORBIT_EXIT_RADIUS   = 0.95   # hysteresis — must travel further out to "leave"
ORBIT_WARN_RADIUS   = 0.88   # in-orbit warning that you're approaching the boundary
EARTH_NODE_PATH     = NodePath("Słońce/ziemia axis/Ziemia")

The 0.80 / 0.95 split prevents flicker if the player skirts the boundary. Warning fires once when crossing 0.88 outbound while still in orbit.

Step-by-step Implementation

Step 1 — Add EarthFrame node to the scene

In collision_shape_3d.tscn, add a Node3D named EarthFrame as a direct child of the root, sibling to PlayerSat and Słońce. Leave its transform at identity — OrbitManager will drive global_position each frame.

Step 2 — Create scripts/orbit_manager.gd

Attach to a new Node named OrbitManager under the scene root. Responsibilities:

1. Cache references in _ready: earth, earth_frame, player (the PlayerSat root), flight_controller (script instance on it).
2. Track state: State (enum IN_SPACE, IN_ORBIT) and warned_this_orbit: bool.
3. Track _earth_prev_pos: Vector3 and compute earth_velocity = (earth.global_position - _earth_prev_pos) / delta each frame.
4. In _physics_process(delta):
  - Update EarthFrame.global_position = earth.global_position.
  - Compute dist = player.global_position.distance_to(earth.global_position).
  - State transitions:
      - IN_SPACE → IN_ORBIT when dist < ORBIT_ENTER_RADIUS: emit orbit_entered, call player.reparent(earth_frame, true), call flight_controller.on_orbit_entered(earth_velocity), reset warned_this_orbit = false.
    - IN_ORBIT → emit orbit_exit_warning once when dist > ORBIT_WARN_RADIUS and not yet warned; reset warning if player dips back below.
    - IN_ORBIT → IN_SPACE when dist > ORBIT_EXIT_RADIUS: emit orbit_exited, call player.reparent(scene_root, true), call flight_controller.on_orbit_exited(earth_velocity).
5. Signals: signal orbit_entered, signal orbit_exit_warning, signal orbit_exited.

Step 3 — Velocity correction in flight_controller.gd

The flight controller integrates a velocity: Vector3 member each frame. When we reparent the player from world frame to Earth frame, that Vector3 is now interpreted in Earth-local coordinates and "world drift from Earth's motion" needs to be subtracted out — otherwise the ship feels like it suddenly accelerates relative to Earth.

Add:
func on_orbit_entered(earth_world_velocity: Vector3) -> void:
    velocity -= earth_world_velocity   # was world-relative, now Earth-relative

func on_orbit_exited(earth_world_velocity: Vector3) -> void:
    velocity += earth_world_velocity   # convert back to world-relative
This is a 4-line edit. Hook methods only — no other flight-controller logic changes.

Step 4 — Build scenes/HUD.tscn

CanvasLayer root, with:
- AlertLabel: Label — centered top-third, large font (64px), starts modulate.a = 0.
- EarthIndicator: Control — full-rect, child Arrow: TextureRect (use a built-in icon for now, or a simple white triangle generated via ImageTexture) and DistanceLabel: Label. Hidden when Earth is on-screen.

Add HUD as a child of the scene root in collision_shape_3d.tscn (CanvasLayer renders independently of 3D hierarchy, so it's safe even after the player gets reparented).

Step 5 — Create scripts/hud.gd attached to HUD root

1. Connect to OrbitManager signals in _ready (find via get_node("/root/.../OrbitManager")).
2. _on_orbit_entered: call show_alert("ENTERING EARTH ORBIT", Color.CYAN, 2.5).
3. _on_orbit_exit_warning: show_alert("LEAVING ORBIT — TURN BACK", Color.YELLOW, 2.0).
4. _on_orbit_exited: show_alert("ORBIT LOST", Color.RED, 2.5).
5. show_alert(text, color, duration): cancel any running tween, set label text/color, tween modulate.a 0→1 over 0.25s, hold, fade 1→0 over 0.5s.
6. _process(delta): update edge indicator (see Step 6).

Step 6 — Screen-edge Earth indicator

In hud.gd._process(delta):
1. Get the active Camera3D via get_viewport().get_camera_3d().
2. Get Earth's global_position (cache reference once).
3. If Earth is behind the camera (camera.is_position_behind(earth_pos)) OR unproject_position returns a value outside the viewport rect → show indicator.
4. Compute the screen-edge intersection: take a 2D vector from screen center to projected Earth pos (flipping for behind-camera), normalize, clamp to viewport rect minus a margin (~60px). Set Arrow.position, set Arrow.rotation = vec.angle().
5. Update DistanceLabel.text with "EARTH %.2f" % player.global_position.distance_to(earth_pos).
6. Hide indicator when Earth is on-screen and in front of camera.

Step 7 — Wire everything in collision_shape_3d.tscn

Final node additions to the scene root:
- EarthFrame (Node3D)
- OrbitManager (Node, script attached)
- HUD (instance of scenes/HUD.tscn)

Confirm Player (the PlayerSat instance) is a direct child of root before play — the reparent operation needs to know its original parent to restore on exit. Store the original parent reference in OrbitManager._ready so exit restoration is robust even if the scene structure changes.

Critical Files

- C:\Users\adamr\hackathon2026\collision_shape_3d.tscn — add EarthFrame, OrbitManager, HUD nodes
- C:\Users\adamr\hackathon2026\scripts\orbit_manager.gd — new
- C:\Users\adamr\hackathon2026\scripts\hud.gd — new
- C:\Users\adamr\hackathon2026\scenes\HUD.tscn — new
- C:\Users\adamr\hackathon2026\scripts\flight_controller.gd — add on_orbit_entered / on_orbit_exited (~4 lines)

Verification

Run the project (F5 in Godot, main scene is collision_shape_3d.tscn). Test the full loop:

1. Approach — fly toward Earth (W to thrust). Watch the screen-edge arrow appear when Earth leaves the viewport, disappear when it returns. Distance label should count down.
2. Entry — cross ORBIT_ENTER_RADIUS. Expect: ENTERING EARTH ORBIT alert fades in/out; the ship visually "sticks" to Earth's frame instead of being left behind by Earth's orbital motion. Stop thrusting — the ship should drift with Earth, not back toward Sun.
3. Warning — drift outward past ORBIT_WARN_RADIUS (still inside EXIT_RADIUS). Expect: LEAVING ORBIT — TURN BACK alert exactly once. Dip back below and re-cross — should re-trigger.
4. Exit — cross ORBIT_EXIT_RADIUS. Expect: ORBIT LOST alert; ship reparents back to world space and Earth visibly resumes orbiting away from you.
5. Re-entry — fly back in. Whole cycle should repeat cleanly with no double-fires (the hysteresis gap + warned_this_orbit flag handle this).
6. Velocity continuity — at the moment of entry/exit there should be no visible "jolt" or teleport. If there is, check the sign on the velocity -= / velocity += in Step 3.
7. Collision — flying into Earth surface should still trigger the existing game-over (no regression on _on_area_3d_body_entered).

If the screen-edge arrow flickers or sits wrong: double-check the is_position_behind branch — projected points behind the camera need their vector flipped before clamping.