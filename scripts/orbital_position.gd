class_name OrbitalPosition
## Simplified Keplerian propagation: TLE → current lat/lon → EarthFrame scene direction.
## Not full SGP4 (no drag/perturbations), but accurate to within ~5° for most LEO sats.

const GM_KM3_S2: float = 398600.4418   # Earth gravitational parameter
const EARTH_R_KM: float = 6378.137
const J2000_UNIX: float = 946728000.0   # 2000-01-01 12:00:00 UTC in Unix seconds

## Returns a unit direction Vector3 in EarthFrame-local space (Y=north, X=0°lon, Z=90°E).
## Multiply by your desired orbital radius (e.g. SatelliteSpawner.SAT_ORBIT_RADIUS).
static func compute_direction(tle_line1: String, tle_line2: String) -> Vector3:
	if tle_line1.length() < 69 or tle_line2.length() < 69:
		return Vector3.FORWARD   # fallback: in front of camera

	# --- Parse TLE epoch ---
	var yy: int = int(tle_line1.substr(18, 2))
	var year: int = (2000 + yy) if yy < 57 else (1900 + yy)
	var day_frac: float = float(tle_line1.substr(20, 12))
	var day_int: int = int(day_frac)
	var day_frac_part: float = day_frac - float(day_int)
	var jan1_unix: float = float(Time.get_unix_time_from_datetime_dict({
		"year": year, "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0
	}))
	var epoch_unix: float = jan1_unix + float(day_int - 1) * 86400.0 + day_frac_part * 86400.0

	# --- Parse orbital elements from TLE line 2 ---
	var incl_deg: float  = float(tle_line2.substr(8,  8))   # inclination °
	var raan_deg: float  = float(tle_line2.substr(17, 8))   # right ascension of ascending node °
	var ecc: float       = float("0." + tle_line2.substr(26, 7))  # eccentricity (no decimal point in TLE)
	var argp_deg: float  = float(tle_line2.substr(34, 8))   # argument of perigee °
	var m0_deg: float    = float(tle_line2.substr(43, 8))   # mean anomaly at epoch °
	var mm_rev_day: float= float(tle_line2.substr(52, 11))  # mean motion rev/day

	var incl:  float = deg_to_rad(incl_deg)
	var raan:  float = deg_to_rad(raan_deg)
	var argp:  float = deg_to_rad(argp_deg)
	var m0:    float = deg_to_rad(m0_deg)
	var n_rad_s: float = mm_rev_day * TAU / 86400.0   # mean motion rad/s

	# --- Semi-major axis from mean motion ---
	var a_km: float = pow(GM_KM3_S2 / (n_rad_s * n_rad_s), 1.0 / 3.0)

	# --- Propagate mean anomaly to now ---
	var now_unix: float = float(Time.get_unix_time_from_system())
	var dt_sec: float = now_unix - epoch_unix
	var M: float = fmod(m0 + n_rad_s * dt_sec, TAU)
	if M < 0.0:
		M += TAU

	# --- Kepler's equation: M = E - e*sin(E) → Newton's method ---
	var E: float = M
	for _i in range(10):
		E = E - (E - ecc * sin(E) - M) / (1.0 - ecc * cos(E))

	# --- True anomaly ---
	var sin_nu: float = sqrt(1.0 - ecc * ecc) * sin(E) / (1.0 - ecc * cos(E))
	var cos_nu: float = (cos(E) - ecc) / (1.0 - ecc * cos(E))
	var nu: float = atan2(sin_nu, cos_nu)

	# --- Orbital radius ---
	var r_km: float = a_km * (1.0 - ecc * cos(E))

	# --- Position in perifocal (orbital-plane) frame ---
	var x_orb: float = r_km * cos(nu)
	var y_orb: float = r_km * sin(nu)

	# --- Rotate perifocal → ECI (Earth-Centered Inertial) ---
	# Standard 3-1-3 Euler: Rz(-Ω) * Rx(-i) * Rz(-ω)
	var cos_raan := cos(raan);  var sin_raan := sin(raan)
	var cos_incl := cos(incl);  var sin_incl := sin(incl)
	var cos_argp := cos(argp);  var sin_argp := sin(argp)

	var eci_x: float = (
		x_orb * (cos_raan * cos_argp - sin_raan * sin_argp * cos_incl)
		- y_orb * (cos_raan * sin_argp + sin_raan * cos_argp * cos_incl)
	)
	var eci_y: float = (
		x_orb * (sin_raan * cos_argp + cos_raan * sin_argp * cos_incl)
		- y_orb * (sin_raan * sin_argp - cos_raan * cos_argp * cos_incl)
	)
	var eci_z: float = x_orb * sin_argp * sin_incl + y_orb * cos_argp * sin_incl

	# --- Rotate ECI → ECEF via Greenwich Mean Sidereal Time ---
	var d_j2000: float = (now_unix - J2000_UNIX) / 86400.0
	var gmst_deg: float = 280.46061837 + 360.98564736629 * d_j2000
	var gmst: float = deg_to_rad(fmod(gmst_deg, 360.0))
	var cos_g := cos(gmst);  var sin_g := sin(gmst)
	var ecef_x: float =  eci_x * cos_g + eci_y * sin_g
	var ecef_y: float = -eci_x * sin_g + eci_y * cos_g
	var ecef_z: float =  eci_z

	# --- ECEF → latitude / longitude ---
	var lon: float = atan2(ecef_y, ecef_x)
	var lat: float = atan2(ecef_z, sqrt(ecef_x * ecef_x + ecef_y * ecef_y))

	# --- Map to EarthFrame unit direction (Y=north, X=0°lon, Z=90°E) ---
	var dir := Vector3(
		cos(lat) * cos(lon),
		sin(lat),
		cos(lat) * sin(lon)
	)
	return dir.normalized()
