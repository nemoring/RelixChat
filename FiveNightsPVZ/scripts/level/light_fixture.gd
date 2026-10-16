class_name LightFixture
extends Node3D
## Потолочный светильник с люминесцентными лампами: свет, гул, мерцание.

var zone := ""
var light: OmniLight3D
var tube_mat: StandardMaterial3D
var hum: AudioStreamPlayer3D
var base_energy := 1.0
var faulty := false  # неисправная — мерцает
var powered := true
var _flicker_t := 0.0
var _burst := 0.0
var _rng := RandomNumberGenerator.new()
var _state_on := true
var _dead := false  # полностью перегоревшая


func build(z: String, energy: float, rng_range: float, color := Color(0.86, 0.93, 1.0), is_faulty := false, length := 1.2) -> void:
	zone = z
	faulty = is_faulty
	base_energy = energy
	_rng.seed = hash(str(global_position) + z)
	Build.box(self, Vector3(length + 0.1, 0.06, 0.32), Vector3(0, 0, 0), Mats.color(Color(0.8, 0.8, 0.78), 0.6))
	tube_mat = StandardMaterial3D.new()
	tube_mat.albedo_color = Color(0.9, 0.95, 1.0)
	tube_mat.emission_enabled = true
	tube_mat.emission = color
	tube_mat.emission_energy_multiplier = 2.0
	for dz in [-0.07, 0.07]:
		var t := Build.cyl(self, 0.016, length, Vector3(0, -0.05, dz), tube_mat, Vector3(0, 0, 90), 6)
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	light = OmniLight3D.new()
	light.position = Vector3(0, -0.25, 0)
	light.omni_range = rng_range
	light.omni_attenuation = 1.2
	light.light_energy = energy
	light.light_color = color
	light.light_specular = 0.3
	add_child(light)
	hum = Sfx.make_loop("hum", self, Vector3(0, -0.1, 0), -24.0 if not faulty else -18.0, "Ambience", 7.0)


func set_shadow(on: bool) -> void:
	light.shadow_enabled = on
	light.shadow_bias = 0.08
	light.shadow_normal_bias = 1.5


func set_powered(v: bool) -> void:
	powered = v
	_apply(v and not _dead)


func kill_tube() -> void:
	_dead = true
	_apply(false)


func burst(seconds: float) -> void:
	_burst = maxf(_burst, seconds)


func is_lit() -> bool:
	return powered and not _dead and _state_on


func _apply(on: bool) -> void:
	_state_on = on
	light.visible = on
	tube_mat.emission_energy_multiplier = 2.0 if on else 0.0
	tube_mat.albedo_color = Color(0.9, 0.95, 1.0) if on else Color(0.35, 0.36, 0.37)
	if hum:
		hum.stream_paused = not on


func _process(delta: float) -> void:
	if not powered or _dead:
		return
	var flicker_allowed: bool = GameState.settings.get("flicker", true)
	if _burst > 0.0:
		_burst -= delta
		if flicker_allowed:
			_flicker_t -= delta
			if _flicker_t <= 0.0:
				_flicker_t = _rng.randf_range(0.03, 0.18)
				var on := _rng.randf() > 0.45
				_apply(on)
				if on and _rng.randf() < 0.3:
					Sfx.play_3d("buzz", global_position, -20.0, _rng.randf_range(0.9, 1.2))
		else:
			light.light_energy = base_energy * 0.6
		if _burst <= 0.0:
			_apply(true)
			light.light_energy = base_energy
		return
	if faulty:
		if flicker_allowed:
			_flicker_t -= delta
			if _flicker_t <= 0.0:
				if _state_on:
					_flicker_t = _rng.randf_range(1.5, 9.0)
					if _rng.randf() < 0.6:
						_burst = _rng.randf_range(0.2, 0.9)
				else:
					_flicker_t = _rng.randf_range(0.05, 0.3)
					_apply(true)
			light.light_energy = base_energy * (0.85 + 0.1 * sin(Time.get_ticks_msec() * 0.05))
		else:
			light.light_energy = base_energy * 0.8
