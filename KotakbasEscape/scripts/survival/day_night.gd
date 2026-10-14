class_name DayNight
extends Node
## Смена дня и ночи. Игровые сутки = 1440 игровых минут = 24 реальные минуты
## (1 игровая минута в реальную секунду при обычной скорости).

const DAY_MIN := 1440.0
const MINUTES_PER_SECOND := 1.0

var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var weather_dim := 0.0 # 0..1 затемнение от погоды

func setup(s: DirectionalLight3D, e: Environment, sm: ProceduralSkyMaterial) -> void:
	sun = s
	env = e
	sky_mat = sm

static func time_of_day(total_min: float) -> float:
	return fposmod(total_min, DAY_MIN)

static func day_number(total_min: float) -> int:
	return int(floor(total_min / DAY_MIN)) + 1

static func clock_text(total_min: float) -> String:
	var t := time_of_day(total_min)
	return "%02d:%02d" % [int(t / 60.0), int(fmod(t, 60.0))]

static func is_night(total_min: float) -> bool:
	var t := time_of_day(total_min)
	return t < 360.0 or t >= 1260.0

## Следующее 06:00 строго после момента t.
static func next_morning(total_min: float) -> float:
	var day_start := floorf(total_min / DAY_MIN) * DAY_MIN
	var m := day_start + 360.0
	if m <= total_min:
		m += DAY_MIN
	return m

func apply(total_min: float) -> void:
	var t := time_of_day(total_min) / DAY_MIN # 0..1, 0.5 = полдень
	var sun_angle := (t - 0.25) * TAU # восход в 06:00
	var elev := sin(sun_angle)
	var day_k := clampf(elev * 3.0 + 0.3, 0.0, 1.0)
	sun.rotation = Vector3(-maxf(0.15, absf(elev)) * 1.2 - 0.2, sun_angle * 0.3 + 0.6, 0.0)
	var dim := 1.0 - weather_dim * 0.55
	sun.light_energy = lerpf(0.18, 1.15, day_k) * dim
	sun.light_color = Color(0.55, 0.62, 0.9).lerp(Color(1.0, 0.93, 0.82), day_k)
	if elev > -0.1 and elev < 0.25:
		sun.light_color = sun.light_color.lerp(Color(1.0, 0.6, 0.35), 0.5)
	env.ambient_light_energy = lerpf(0.35, 0.95, day_k) * dim
	var top := Color(0.04, 0.05, 0.12).lerp(Color(0.32, 0.52, 0.85), day_k)
	var hor := Color(0.08, 0.09, 0.16).lerp(Color(0.78, 0.8, 0.85), day_k)
	if elev > -0.15 and elev < 0.2:
		hor = hor.lerp(Color(0.95, 0.55, 0.35), 0.45)
	var grey := Color(0.45, 0.47, 0.5) * lerpf(0.25, 1.0, day_k)
	sky_mat.sky_top_color = top.lerp(grey, weather_dim)
	sky_mat.sky_horizon_color = hor.lerp(grey, weather_dim)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.ground_bottom_color = sky_mat.sky_horizon_color.darkened(0.5)
	env.fog_light_color = sky_mat.sky_horizon_color

## Температура окружения по времени суток, °C.
static func base_temperature(total_min: float) -> float:
	var t := time_of_day(total_min) / DAY_MIN
	return 10.0 + sin((t - 0.3) * TAU) * 8.0
