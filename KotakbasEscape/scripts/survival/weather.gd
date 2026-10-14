class_name WeatherSystem
extends Node3D
## Погода: ясно, облачно, дождь, гроза, туман. Частицы ограничены качеством графики.

signal weather_changed(kind: String)

const NAMES := {"clear": "Ясно", "cloudy": "Облачно", "rain": "Дождь", "storm": "Гроза", "fog": "Туман"}
const TEMP_MOD := {"clear": 0.0, "cloudy": -1.5, "rain": -4.0, "storm": -6.5, "fog": -2.0}

var kind := "clear"
var next_change := 240.0 # игровые минуты до смены
var rain: CPUParticles3D
var env: Environment
var day_night: DayNight
var target: Node3D
var _flash := 0.0
var _thunder_t := 8.0
var forced := false
var last_min := 0.0

func setup(e: Environment, dn: DayNight, follow: Node3D) -> void:
	env = e
	day_night = dn
	target = follow
	rain = CPUParticles3D.new()
	rain.amount = maxi(40, int(600 * Settings.particle_scale()))
	rain.lifetime = 1.2
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(18, 1, 18)
	rain.direction = Vector3(0.1, -1, 0)
	rain.spread = 4.0
	rain.gravity = Vector3(0, -30, 0)
	rain.initial_velocity_min = 14.0
	rain.initial_velocity_max = 18.0
	var drop := BoxMesh.new()
	drop.size = Vector3(0.02, 0.5, 0.02)
	rain.mesh = drop
	rain.material_override = MK.mat(Color(0.7, 0.8, 1.0, 0.55), true)
	rain.emitting = false
	rain.local_coords = false
	add_child(rain)

func set_weather(k: String) -> void:
	if k == kind:
		return
	kind = k
	weather_changed.emit(k)
	_apply_sound()

func _apply_sound() -> void:
	match kind:
		"rain", "storm":
			AudioManager.play_ambient("rain", -8.0 if kind == "rain" else -4.0)
		_:
			AudioManager.play_ambient("forest_night" if DayNight.is_night(last_min) else "forest_day", -10.0)

func tick(dt_min: float, total_min: float) -> void:
	var was_night := DayNight.is_night(last_min)
	last_min = total_min
	if was_night != DayNight.is_night(total_min):
		_apply_sound()
	if not forced:
		next_change -= dt_min
		if next_change <= 0.0:
			next_change = randf_range(180.0, 360.0)
			var r := randf()
			var k := "clear"
			if r < 0.35: k = "clear"
			elif r < 0.6: k = "cloudy"
			elif r < 0.8: k = "rain"
			elif r < 0.9: k = "storm"
			else: k = "fog"
			set_weather(k)

func _process(delta: float) -> void:
	if target:
		rain.global_position = target.global_position + Vector3(0, 12, 0)
	rain.emitting = kind in ["rain", "storm"]
	var dim_target := 0.0
	var fog_target := 0.008
	match kind:
		"cloudy": dim_target = 0.35
		"rain": dim_target = 0.6; fog_target = 0.016
		"storm": dim_target = 0.85; fog_target = 0.02
		"fog": dim_target = 0.3; fog_target = 0.045
	day_night.weather_dim = lerpf(day_night.weather_dim, dim_target, delta * 0.3)
	var base_fog := 2.2 / Settings.view_distance()
	env.fog_density = lerpf(env.fog_density, maxf(fog_target, base_fog), delta * 0.5)
	if kind == "storm":
		_thunder_t -= delta
		if _thunder_t <= 0.0:
			_thunder_t = randf_range(6.0, 16.0)
			_flash = 1.0
			get_tree().create_timer(randf_range(0.3, 1.5)).timeout.connect(func(): AudioManager.play_sfx("thunder", -2.0))
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 4.0)
		env.ambient_light_energy += _flash * 2.0

func temperature_mod() -> float:
	return TEMP_MOD.get(kind, 0.0)

func display_name() -> String:
	return NAMES.get(kind, kind)
