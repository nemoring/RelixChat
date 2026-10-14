extends Node
## Музыка, звуковые эффекты и окружение. Звуки лежат в assets/audio (сгенерированы
## tools/gen_audio.py), загружаются лениво и кэшируются. Пулы плееров ограничены.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const LOOPING_SFX := ["ufo_hum", "beam", "rain", "wind", "forest_day", "forest_night", "city", "fire"]

var _cache := {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_current := ""
var _ambient: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_3d_pool: Array[AudioStreamPlayer3D] = []
var _sfx_index := 0
var _sfx3d_index := 0
var _ambient_name := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music_a = _make_player("Music")
	_music_b = _make_player("Music")
	_ambient = _make_player("Ambient")
	for i in 12:
		_sfx_pool.append(_make_player("SFX"))
	for i in 8:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.unit_size = 8.0
		p.max_distance = 70.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_sfx_3d_pool.append(p)

func _make_player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p

func _get_stream(dir: String, name: String, loop: bool) -> AudioStream:
	var key := dir + name
	if _cache.has(key):
		return _cache[key]
	var path := dir + name + ".wav"
	if not ResourceLoader.exists(path):
		_cache[key] = null
		return null
	var s: AudioStream = load(path)
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		if loop:
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			var bytes_per_sample := 2 if w.format == AudioStreamWAV.FORMAT_16_BITS else 1
			var channels := 2 if w.stereo else 1
			w.loop_end = w.data.size() / (bytes_per_sample * channels)
		else:
			w.loop_mode = AudioStreamWAV.LOOP_DISABLED
	_cache[key] = s
	return s

func play_sfx(name: String, volume_db := 0.0, pitch := 1.0, rand_pitch := 0.06) -> AudioStreamPlayer:
	var s := _get_stream(SFX_DIR, name, false)
	if s == null:
		return null
	var p := _sfx_pool[_sfx_index]
	_sfx_index = (_sfx_index + 1) % _sfx_pool.size()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = maxf(0.05, pitch + randf_range(-rand_pitch, rand_pitch))
	p.play()
	return p

func play_sfx_3d(name: String, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	var s := _get_stream(SFX_DIR, name, false)
	if s == null:
		return
	var p := _sfx_3d_pool[_sfx3d_index]
	_sfx3d_index = (_sfx3d_index + 1) % _sfx_3d_pool.size()
	if not p.is_inside_tree():
		return
	p.global_position = pos
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch + randf_range(-0.06, 0.06)
	p.play()

## Зацикленный звук, который живёт на узле-владельце (гул НЛО, луч, костёр).
func make_loop_player_3d(name: String, owner: Node3D, volume_db := 0.0, max_dist := 90.0) -> AudioStreamPlayer3D:
	var s := _get_stream(SFX_DIR, name, true)
	var p := AudioStreamPlayer3D.new()
	p.bus = "SFX"
	p.stream = s
	p.volume_db = volume_db
	p.max_distance = max_dist
	p.unit_size = 12.0
	owner.add_child(p)
	return p

func play_music(name: String, fade := 1.2) -> void:
	if name == _music_current:
		return
	_music_current = name
	var s := _get_stream(MUSIC_DIR, name, true)
	var old := _music_a if _music_a.playing else _music_b
	var new := _music_b if old == _music_a else _music_a
	if old.playing:
		var tw := create_tween()
		tw.tween_property(old, "volume_db", -40.0, fade)
		tw.tween_callback(old.stop)
	if s == null:
		return
	new.stream = s
	new.volume_db = -30.0
	new.play()
	var tw2 := create_tween()
	tw2.tween_property(new, "volume_db", 0.0, fade)

func stop_music(fade := 1.0) -> void:
	_music_current = ""
	for p in [_music_a, _music_b]:
		if p.playing:
			var tw := create_tween()
			tw.tween_property(p, "volume_db", -40.0, fade)
			tw.tween_callback(p.stop)

func play_ambient(name: String, volume_db := -6.0) -> void:
	if name == _ambient_name and _ambient.playing:
		return
	_ambient_name = name
	var s := _get_stream(SFX_DIR, name, true)
	if s == null:
		_ambient.stop()
		return
	_ambient.stream = s
	_ambient.volume_db = volume_db
	_ambient.play()

func stop_ambient() -> void:
	_ambient_name = ""
	_ambient.stop()

func stop_all_sfx() -> void:
	for p in _sfx_pool:
		p.stop()
	for p in _sfx_3d_pool:
		p.stop()
