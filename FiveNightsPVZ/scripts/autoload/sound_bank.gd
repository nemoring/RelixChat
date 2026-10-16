extends Node
## Процедурный звуковой банк. Все звуки синтезируются при первом обращении
## (без внешних ассетов) и кэшируются. Автозагрузка "Sfx".
##
## Громкие звуки специально ограничены по пиковой амплитуде, а на мастер-шине
## стоит лимитер: скримеры пугают не громкостью.

const RATE := 22050

var _cache := {}
var _rng := RandomNumberGenerator.new()
## Звуки, которые нужно сгенерировать заранее (на загрузочном экране).
const WARMUP := [
	"hum", "vent", "room_tone", "street", "step", "step_soft", "step_heavy", "breath",
	"rustle", "creak", "door_open", "door_close", "click", "beep", "static", "drone",
	"curtain", "whisper", "knock", "bell", "phone", "printer", "breaker", "heartbeat",
	"sting_faceless", "sting_woman", "sting_courier", "sting_return", "sting_inspector",
	"thud", "glass_tap", "buzz", "cloth", "drip", "relay", "handle", "keyboard", "shutter",
]

## Мягкий ограничитель: голос ли, шум ли — пики не выше этого уровня.
const PEAK := 0.82


func _ready() -> void:
	_rng.seed = 1337


func has_sound(sound_name: String) -> bool:
	return has_method("_gen_" + sound_name)


func get_stream(sound_name: String) -> AudioStreamWAV:
	if _cache.has(sound_name):
		return _cache[sound_name]
	if not has_sound(sound_name):
		push_warning("Нет звука: " + sound_name)
		sound_name = "click"
		if _cache.has(sound_name):
			return _cache[sound_name]
	var samples: PackedFloat32Array = call("_gen_" + sound_name)
	var looped := sound_name in ["hum", "vent", "room_tone", "street", "breath", "static", "drone", "whisper", "phone", "heartbeat", "buzz"]
	var stream := _to_wav(samples, looped)
	_cache[sound_name] = stream
	return stream


## Пошаговая генерация на загрузочном экране; возвращает долю готовности.
func warmup_step() -> float:
	for s in WARMUP:
		if not _cache.has(s):
			get_stream(s)
			break
	var done := 0
	for s in WARMUP:
		if _cache.has(s):
			done += 1
	return float(done) / WARMUP.size()


# ---------------------------------------------------------------- Воспроизведение

## Одиночный позиционный звук. Учитывает перекрытие стенами (глушение).
func play_3d(sound_name: String, pos: Vector3, volume_db := 0.0, pitch := 1.0, max_dist := 22.0, parent: Node = null) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = get_stream(sound_name)
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.max_distance = max_dist
	p.unit_size = 3.0
	p.bus = "SFX"
	p.attenuation_filter_db = -18.0
	var host: Node = parent if parent else get_tree().current_scene
	if host == null:
		p.free()
		return null
	host.add_child(p)
	p.global_position = pos
	apply_occlusion(p)
	p.play()
	p.finished.connect(p.queue_free)
	return p


## Постоянный зацикленный источник (гул ламп, вентиляция, дыхание).
func make_loop(sound_name: String, parent: Node, local_pos := Vector3.ZERO, volume_db := 0.0, bus := "Ambience", max_dist := 12.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = get_stream(sound_name)
	p.volume_db = volume_db
	p.max_distance = max_dist
	p.unit_size = 2.0
	p.bus = bus
	p.autoplay = true
	p.attenuation_filter_db = -18.0
	p.position = local_pos
	parent.add_child(p)
	return p


func play_ui(sound_name: String, volume_db := -6.0, pitch := 1.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = get_stream(sound_name)
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.bus = "UI"
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


## Глушение звука сквозь стены и двери: луч от слушателя к источнику.
func apply_occlusion(p: AudioStreamPlayer3D) -> void:
	if not p.is_inside_tree():
		return
	var cam := p.get_viewport().get_camera_3d()
	if cam == null:
		return
	var space := p.get_world_3d().direct_space_state
	if space == null:
		return
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, p.global_position, 1)
	var hits := 0
	var from := cam.global_position
	for i in 3:
		q.from = from
		var r := space.intersect_ray(q)
		if r.is_empty():
			break
		hits += 1
		from = r.position + (p.global_position - cam.global_position).normalized() * 0.3
	if hits > 0:
		p.attenuation_filter_cutoff_hz = 900.0 / hits
		p.volume_db -= 5.0 * hits
	else:
		p.attenuation_filter_cutoff_hz = 9000.0


# ---------------------------------------------------------------- DSP-утилиты

func _to_wav(samples: PackedFloat32Array, looped: bool) -> AudioStreamWAV:
	var peak := 0.0001
	for s in samples:
		peak = maxf(peak, absf(s))
	var gain := PEAK / peak if peak > PEAK else 1.0
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i] * gain, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if looped:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _buf(seconds: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(int(seconds * RATE))
	return a


func _noise() -> float:
	return _rng.randf() * 2.0 - 1.0


## Плавное зацикливание: перекрёстное затухание конца с началом.
func _loopify(a: PackedFloat32Array, fade_s := 0.25) -> PackedFloat32Array:
	var n := int(fade_s * RATE)
	var size := a.size()
	if n * 2 >= size:
		return a
	var out := a.slice(0, size - n)
	for i in n:
		var t := float(i) / n
		out[i] = a[i] * t + a[size - n + i] * (1.0 - t)
	return out


func _lowpass(a: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var rc := 1.0 / (TAU * cutoff)
	var dt := 1.0 / RATE
	var k := dt / (rc + dt)
	var y := 0.0
	for i in a.size():
		y += k * (a[i] - y)
		a[i] = y
	return a


func _highpass(a: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var rc := 1.0 / (TAU * cutoff)
	var dt := 1.0 / RATE
	var k := rc / (rc + dt)
	var y := 0.0
	var px := 0.0
	for i in a.size():
		var x := a[i]
		y = k * (y + x - px)
		px = x
		a[i] = y
	return a


## Двухполюсный резонансный полосовой фильтр (для форматнт, скрипа).
func _bandpass(a: PackedFloat32Array, freq: float, q: float) -> PackedFloat32Array:
	var w0 := TAU * freq / RATE
	var alpha := sin(w0) / (2.0 * q)
	var b0 := alpha
	var a0 := 1.0 + alpha
	var a1 := -2.0 * cos(w0)
	var a2 := 1.0 - alpha
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in a.size():
		var x := a[i]
		var y := (b0 * x - b0 * x2 - a1 * y1 - a2 * y2) / a0
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		a[i] = y
	return a


func _env_ad(i: int, attack: int, decay: int) -> float:
	if i < attack:
		return float(i) / maxf(attack, 1)
	return exp(-float(i - attack) / maxf(decay, 1))


func _mix(dst: PackedFloat32Array, src: PackedFloat32Array, offset: int, gain := 1.0) -> void:
	for i in src.size():
		var j := offset + i
		if j >= 0 and j < dst.size():
			dst[j] += src[i] * gain


# ---------------------------------------------------------------- Генераторы

## Гул люминесцентной лампы: 100 Гц + гармоники + треск дросселя.
func _gen_hum() -> PackedFloat32Array:
	var a := _buf(2.0)
	for i in a.size():
		var t := float(i) / RATE
		var v := sin(TAU * 100.0 * t) * 0.35 + sin(TAU * 200.0 * t) * 0.15 + sin(TAU * 300.0 * t) * 0.08
		v += sin(TAU * 1200.0 * t) * 0.015 * (0.5 + 0.5 * sin(TAU * 3.0 * t))
		v += _noise() * 0.02
		a[i] = v * 0.5
	return a


## Короткое жужжание при мерцании.
func _gen_buzz() -> PackedFloat32Array:
	var a := _buf(1.0)
	for i in a.size():
		var t := float(i) / RATE
		var saw := fmod(t * 100.0, 1.0) * 2.0 - 1.0
		a[i] = (saw * 0.4 + _noise() * 0.15) * (0.6 + 0.4 * sin(TAU * 7.0 * t))
	return _lowpass(a, 2500.0)


func _gen_vent() -> PackedFloat32Array:
	var a := _buf(4.0)
	var brown := 0.0
	for i in a.size():
		brown = clampf(brown + _noise() * 0.06, -1.0, 1.0) * 0.995
		var t := float(i) / RATE
		a[i] = brown * 0.6 + sin(TAU * 47.0 * t) * 0.05
	a = _lowpass(a, 700.0)
	return _loopify(a, 0.5)


func _gen_room_tone() -> PackedFloat32Array:
	var a := _buf(4.0)
	var brown := 0.0
	for i in a.size():
		brown = clampf(brown + _noise() * 0.03, -1.0, 1.0) * 0.997
		a[i] = brown * 0.5
	a = _lowpass(a, 250.0)
	return _loopify(a, 0.6)


## Улица: далёкие машины, ветер.
func _gen_street() -> PackedFloat32Array:
	var a := _buf(10.0)
	var brown := 0.0
	var car_t := [2.0, 6.5]
	for i in a.size():
		var t := float(i) / RATE
		brown = clampf(brown + _noise() * 0.04, -1.0, 1.0) * 0.996
		var wind := brown * (0.4 + 0.2 * sin(TAU * 0.13 * t))
		var car := 0.0
		for c in car_t:
			var d: float = t - c
			car += exp(-d * d * 0.8) * _noise() * 0.5
		a[i] = wind + car
	a = _lowpass(a, 600.0)
	return _loopify(a, 1.0)


func _step(weight: float, bright: float) -> PackedFloat32Array:
	var a := _buf(0.32)
	var thump_f := 70.0 + _rng.randf() * 20.0
	for i in a.size():
		var t := float(i) / RATE
		var e := _env_ad(i, 60, int(0.03 * RATE))
		var heel := sin(TAU * thump_f * t) * exp(-t * 30.0) * weight
		var scuff := _noise() * e * bright
		var toe := 0.0
		if t > 0.09:
			toe = _noise() * exp(-(t - 0.09) * 60.0) * bright * 0.6
		a[i] = heel + scuff + toe
	return _lowpass(a, 1800.0 + bright * 2500.0)


func _gen_step() -> PackedFloat32Array:
	return _step(0.8, 0.5)


func _gen_step_soft() -> PackedFloat32Array:
	return _step(0.4, 0.2)


func _gen_step_heavy() -> PackedFloat32Array:
	var a := _step(1.0, 0.35)
	var b := _step(0.6, 0.2)
	_mix(a, b, int(0.02 * RATE), 0.5)
	return a


## Медленное дыхание: вдох-выдох, зацикленное.
func _gen_breath() -> PackedFloat32Array:
	var a := _buf(4.2)
	for i in a.size():
		var t := float(i) / RATE
		var phase := fmod(t, 4.2)
		var env := 0.0
		if phase < 1.6:
			env = sin(PI * phase / 1.6) * 0.6
		elif phase > 1.9 and phase < 4.0:
			env = sin(PI * (phase - 1.9) / 2.1) * 0.9
		a[i] = _noise() * env
	a = _bandpass(a, 900.0, 0.8)
	var b := a.duplicate()
	b = _bandpass(b, 2400.0, 2.0)
	for i in a.size():
		a[i] = a[i] * 1.4 + b[i] * 0.5
	return a


## Невнятный шёпот: шум, модулированный «слогами» и формантами.
func _gen_whisper() -> PackedFloat32Array:
	var a := _buf(5.0)
	var formants := [[600.0, 1100.0], [400.0, 2000.0], [750.0, 1250.0], [300.0, 2300.0]]
	var syl_len := int(0.16 * RATE)
	var out := _buf(5.0)
	var pos := 0
	while pos < out.size():
		var f: Array = formants[_rng.randi() % formants.size()]
		var seg := _buf(0.16 + _rng.randf() * 0.1)
		for i in seg.size():
			seg[i] = _noise() * sin(PI * float(i) / seg.size())
		var s1 := _bandpass(seg.duplicate(), f[0], 3.0)
		var s2 := _bandpass(seg.duplicate(), f[1], 4.0)
		for i in seg.size():
			seg[i] = s1[i] + s2[i] * 0.7 + seg[i] * 0.05
		_mix(out, seg, pos, 1.0)
		pos += seg.size() + (syl_len if _rng.randf() < 0.25 else int(0.03 * RATE))
	a = out
	return _loopify(a, 0.3)


## Шорох картона.
func _gen_rustle() -> PackedFloat32Array:
	var a := _buf(0.9)
	var crackle := 0.0
	for i in a.size():
		var t := float(i) / RATE
		var env := sin(PI * t / 0.9)
		if _rng.randf() < 0.004:
			crackle = 1.0
		crackle *= 0.995
		a[i] = _noise() * (0.25 * env + crackle * 0.8)
	return _highpass(a, 600.0)


## Скрип металла (стеллаж) — резонансный тон со «скольжением».
func _gen_creak() -> PackedFloat32Array:
	var a := _buf(1.4)
	var phase := 0.0
	for i in a.size():
		var t := float(i) / RATE
		var f := 180.0 + 90.0 * sin(TAU * 0.6 * t) + 30.0 * sin(TAU * 5.0 * t)
		phase += TAU * f / RATE
		var stick := 1.0 if fmod(t * 38.0, 1.0) < 0.35 else 0.2
		var env := sin(PI * t / 1.4)
		a[i] = (sin(phase) * 0.5 + sin(phase * 2.01) * 0.3 + sin(phase * 3.7) * 0.15) * stick * env + _noise() * 0.03
	return _bandpass(a, 600.0, 1.2)


func _gen_door_open() -> PackedFloat32Array:
	var a := _gen_handle()
	var c := _gen_creak()
	var out := _buf(1.6)
	_mix(out, a, 0, 0.8)
	_mix(out, c, int(0.15 * RATE), 0.5)
	return out


func _gen_door_close() -> PackedFloat32Array:
	var a := _buf(0.6)
	for i in a.size():
		var t := float(i) / RATE
		a[i] = sin(TAU * 60.0 * t) * exp(-t * 14.0) + _noise() * exp(-t * 40.0) * 0.6
	var latch := _gen_click()
	_mix(a, latch, int(0.04 * RATE), 0.4)
	return _lowpass(a, 2500.0)


func _gen_handle() -> PackedFloat32Array:
	var a := _buf(0.35)
	for i in a.size():
		var t := float(i) / RATE
		a[i] = _noise() * (exp(-t * 80.0) + exp(-absf(t - 0.18) * 90.0) * 0.6)
	return _bandpass(a, 2200.0, 1.5)


func _gen_click() -> PackedFloat32Array:
	var a := _buf(0.08)
	for i in a.size():
		var t := float(i) / RATE
		a[i] = _noise() * exp(-t * 300.0) + sin(TAU * 3000.0 * t) * exp(-t * 200.0) * 0.4
	return a


## Щелчок реле: двойной сухой клик + короткий гул катушки.
func _gen_relay() -> PackedFloat32Array:
	var a := _buf(0.3)
	var c := _gen_click()
	_mix(a, c, 0, 1.0)
	_mix(a, c, int(0.035 * RATE), 0.6)
	for i in a.size():
		var t := float(i) / RATE
		a[i] += sin(TAU * 50.0 * t) * 0.2 * exp(-t * 12.0)
	return a


func _gen_beep() -> PackedFloat32Array:
	var a := _buf(0.14)
	for i in a.size():
		var t := float(i) / RATE
		var env := minf(1.0, t * 400.0) * minf(1.0, (0.14 - t) * 200.0)
		a[i] = (1.0 if sin(TAU * 1850.0 * t) > 0 else -1.0) * 0.25 * env
	return _lowpass(a, 6000.0)


func _gen_keyboard() -> PackedFloat32Array:
	var a := _buf(0.6)
	var c := _gen_click()
	for k in 5:
		_mix(a, c, int((0.05 + k * 0.1 + _rng.randf() * 0.04) * RATE), 0.35 + _rng.randf() * 0.2)
	return _lowpass(a, 4000.0)


## Помехи камер: шум с «потрескиванием».
func _gen_static() -> PackedFloat32Array:
	var a := _buf(2.0)
	for i in a.size():
		var t := float(i) / RATE
		a[i] = _noise() * (0.3 + 0.1 * sin(TAU * 60.0 * t))
	a = _bandpass(a, 3000.0, 0.5)
	return _loopify(a, 0.2)


## Низкий тревожный гул — используется очень редко и тихо.
func _gen_drone() -> PackedFloat32Array:
	var a := _buf(8.0)
	for i in a.size():
		var t := float(i) / RATE
		a[i] = sin(TAU * 41.0 * t) * 0.4 + sin(TAU * 41.7 * t) * 0.35 + sin(TAU * 61.5 * t + sin(TAU * 0.1 * t)) * 0.2
	return _loopify(a, 1.0)


func _gen_curtain() -> PackedFloat32Array:
	var a := _buf(0.8)
	for i in a.size():
		var t := float(i) / RATE
		var rings := 0.0
		if fmod(t, 0.07) < 0.004 and t < 0.5:
			rings = 1.0
		a[i] = _noise() * sin(PI * t / 0.8) * 0.4 + rings * sin(TAU * 4200.0 * t) * 0.3
	return _highpass(a, 300.0)


func _gen_cloth() -> PackedFloat32Array:
	var a := _buf(0.5)
	for i in a.size():
		var t := float(i) / RATE
		a[i] = _noise() * sin(PI * t / 0.5) * 0.4
	return _bandpass(a, 1500.0, 0.7)


func _gen_knock() -> PackedFloat32Array:
	var a := _buf(1.2)
	var one := _buf(0.15)
	for i in one.size():
		var t := float(i) / RATE
		one[i] = sin(TAU * 140.0 * t) * exp(-t * 35.0) + _noise() * exp(-t * 120.0) * 0.4
	for k in 3:
		_mix(a, one, int((0.05 + k * 0.28) * RATE), 0.9)
	return _lowpass(a, 1800.0)


func _gen_glass_tap() -> PackedFloat32Array:
	var a := _buf(0.8)
	var one := _buf(0.2)
	for i in one.size():
		var t := float(i) / RATE
		one[i] = (sin(TAU * 2300.0 * t) * 0.4 + sin(TAU * 3700.0 * t) * 0.2) * exp(-t * 40.0) + _noise() * exp(-t * 200.0) * 0.3
	_mix(a, one, int(0.02 * RATE))
	_mix(a, one, int(0.4 * RATE), 0.8)
	return a


## Звонок на стойке.
func _gen_bell() -> PackedFloat32Array:
	var a := _buf(1.8)
	for i in a.size():
		var t := float(i) / RATE
		a[i] = (sin(TAU * 2093.0 * t) * 0.5 + sin(TAU * 5340.0 * t) * 0.15 + sin(TAU * 2110.0 * t) * 0.3) * exp(-t * 2.5) * minf(1.0, t * 3000.0)
	return a


## Звонок старого телефона (425 Гц, российский тональный сигнал).
func _gen_phone() -> PackedFloat32Array:
	var a := _buf(5.0)
	for i in a.size():
		var t := float(i) / RATE
		var on := 1.0 if fmod(t, 5.0) < 1.0 else 0.0
		var bell: float = sin(TAU * 425.0 * t) * (0.5 + 0.5 * signf(sin(TAU * 25.0 * t)))
		a[i] = bell * on * 0.4
	return _lowpass(a, 3000.0)


func _gen_printer() -> PackedFloat32Array:
	var a := _buf(2.5)
	for i in a.size():
		var t := float(i) / RATE
		var motor := sin(TAU * (380.0 + 30.0 * sin(TAU * 2.0 * t)) * t) * 0.15
		var tick := _noise() * (1.0 if fmod(t, 0.05) < 0.006 else 0.0) * 0.5
		var env := minf(1.0, t * 10.0) * minf(1.0, (2.5 - t) * 6.0)
		a[i] = (motor + tick + _noise() * 0.05) * env
	return a


func _gen_breaker() -> PackedFloat32Array:
	var a := _buf(1.2)
	for i in a.size():
		var t := float(i) / RATE
		a[i] = sin(TAU * 55.0 * t) * exp(-t * 10.0) * 0.8 + _noise() * exp(-t * 60.0) * 0.8
		if t > 0.05 and t < 0.7:
			a[i] += (fmod(t * 100.0, 1.0) * 2.0 - 1.0) * 0.2 * (0.7 - t)
	return _lowpass(a, 3000.0)


func _gen_heartbeat() -> PackedFloat32Array:
	var a := _buf(1.0)
	for i in a.size():
		var t := float(i) / RATE
		var b1 := exp(-pow((t - 0.05) * 30.0, 2.0))
		var b2 := exp(-pow((t - 0.32) * 30.0, 2.0)) * 0.7
		a[i] = sin(TAU * 48.0 * t) * (b1 + b2)
	return a


func _gen_thud() -> PackedFloat32Array:
	var a := _buf(0.9)
	for i in a.size():
		var t := float(i) / RATE
		a[i] = sin(TAU * (55.0 - t * 20.0) * t) * exp(-t * 7.0) + _noise() * exp(-t * 30.0) * 0.5
	return _lowpass(a, 900.0)


func _gen_drip() -> PackedFloat32Array:
	var a := _buf(0.3)
	for i in a.size():
		var t := float(i) / RATE
		a[i] = sin(TAU * (900.0 + 1400.0 * t) * t) * exp(-t * 30.0) * 0.5
	return a


## Рольставня склада.
func _gen_shutter() -> PackedFloat32Array:
	var a := _buf(2.5)
	for i in a.size():
		var t := float(i) / RATE
		var rattle := _noise() * (0.4 + 0.4 * sin(TAU * 18.0 * t))
		a[i] = rattle * minf(1.0, t * 4.0) * minf(1.0, (2.5 - t) * 3.0) + sin(TAU * 90.0 * t) * 0.1
	return _bandpass(a, 900.0, 0.6)


# --- Звуки нападений: у каждого врага свой, громкость ограничена.

func _gen_sting_faceless() -> PackedFloat32Array:
	# Не крик: втягивающий вдох и тихое искажённое «щёлканье» прямо у уха.
	var a := _buf(2.2)
	for i in a.size():
		var t := float(i) / RATE
		var inhale := _noise() * minf(1.0, t * 1.2) * (1.0 if t < 1.4 else maxf(0.0, 1.0 - (t - 1.4) * 4.0))
		var clicks := (_noise() if fmod(t * (8.0 + t * 30.0), 1.0) < 0.05 else 0.0) * 0.8
		a[i] = inhale * 0.5 + clicks
	a = _bandpass(a, 1200.0, 0.7)
	for i in a.size():
		var t := float(i) / RATE
		a[i] += sin(TAU * 38.0 * t) * 0.3 * minf(1.0, t)
	return a


func _gen_sting_woman() -> PackedFloat32Array:
	# Сорванный шёпот, переходящий в хриплый выдох с формантой «а».
	var a := _buf(1.8)
	for i in a.size():
		var t := float(i) / RATE
		var env := minf(1.0, t * 8.0) * exp(-maxf(0.0, t - 0.6) * 2.0)
		var glott := (fmod(t * (140.0 + 80.0 * t), 1.0) * 2.0 - 1.0) * 0.4
		a[i] = (_noise() * 0.7 + glott) * env
	var f1 := _bandpass(a.duplicate(), 800.0, 3.0)
	var f2 := _bandpass(a.duplicate(), 1300.0, 4.0)
	for i in a.size():
		a[i] = f1[i] + f2[i] * 0.8
	return a


func _gen_sting_courier() -> PackedFloat32Array:
	# Удар, падение коробок, тяжёлый выдох.
	var a := _buf(2.0)
	_mix(a, _gen_thud(), 0, 1.0)
	_mix(a, _gen_rustle(), int(0.1 * RATE), 0.7)
	_mix(a, _gen_thud(), int(0.45 * RATE), 0.5)
	var b := _buf(1.0)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = _noise() * sin(PI * t) * 0.6
	_mix(a, _bandpass(b, 500.0, 1.0), int(0.9 * RATE), 1.0)
	return a


func _gen_sting_return() -> PackedFloat32Array:
	# Хруст и голос, повторяющий одну ноту, ниже и ниже.
	var a := _buf(2.2)
	var phase := 0.0
	for i in a.size():
		var t := float(i) / RATE
		var f := 160.0 - t * 50.0
		phase += TAU * f / RATE
		var voice := (sin(phase) + 0.5 * sin(phase * 2.0) + 0.3 * sin(phase * 3.0)) * 0.3
		var crunch := _noise() * (1.0 if _rng.randf() < 0.02 else 0.0)
		a[i] = voice * minf(1.0, t * 5.0) + crunch * 0.6
	return _lowpass(a, 2500.0)


func _gen_sting_inspector() -> PackedFloat32Array:
	# Сухой щелчок ручки, затем низкий, почти спокойный выдох — и тишина.
	var a := _buf(2.0)
	_mix(a, _gen_click(), 0, 0.9)
	var b := _buf(1.4)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = _noise() * sin(PI * t / 1.4) * 0.5
	_mix(a, _bandpass(b, 350.0, 1.2), int(0.3 * RATE), 1.2)
	return a
