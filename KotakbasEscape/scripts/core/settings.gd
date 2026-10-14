extends Node
## Настройки Android-версии: графика, FPS, управление, звук, дополнительные.

signal changed

const PATH := "user://settings.cfg"

enum Quality { MINIMAL, LOW, MEDIUM, HIGH }

const QUALITY_NAMES := ["Минимальная", "Низкая", "Средняя", "Высокая"]
const FPS_OPTIONS := [30, 60, 90, 120, 0]

var data := {
	"graphics": Quality.MEDIUM,
	"fps": 60,
	"joystick_size": 1.0,
	"button_size": 1.0,
	"cam_sens": 1.0,
	"invert_y": false,
	"left_handed": false,
	"vibration": true,
	"vol_master": 0.9,
	"vol_music": 0.6,
	"vol_sfx": 0.9,
	"vol_ambient": 0.7,
	"language": "ru",
	"subtitles": true,
	"autosave": true,
	"show_fps": false,
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	var first_run := not FileAccess.file_exists(PATH)
	load_settings()
	if first_run:
		# Подбираем стартовое качество по количеству ядер — грубая эвристика для слабых телефонов.
		var cores := OS.get_processor_count()
		data.graphics = Quality.LOW if cores <= 4 else Quality.MEDIUM
		save_settings()
	apply_all()

func _ensure_buses() -> void:
	for bus_name in ["Music", "SFX", "Ambient"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")

func get_value(key: String, default = null):
	return data.get(key, default)

func set_value(key: String, value) -> void:
	data[key] = value
	apply_all()
	save_settings()
	changed.emit()

func quality() -> int:
	return int(data.graphics)

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for k in data.keys():
		if cfg.has_section_key("settings", k):
			var v = cfg.get_value("settings", k)
			if typeof(v) == typeof(data[k]) or (typeof(v) in [TYPE_INT, TYPE_FLOAT] and typeof(data[k]) in [TYPE_INT, TYPE_FLOAT]):
				data[k] = v

func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in data.keys():
		cfg.set_value("settings", k, data[k])
	var tmp := PATH + ".tmp"
	if cfg.save(tmp) == OK:
		DirAccess.rename_absolute(tmp, PATH)

func apply_all() -> void:
	Engine.max_fps = int(data.fps)
	_apply_volume("Master", data.vol_master)
	_apply_volume("Music", data.vol_music)
	_apply_volume("SFX", data.vol_sfx)
	_apply_volume("Ambient", data.vol_ambient)
	TranslationServer.set_locale(str(data.language))
	apply_graphics(get_tree().root if is_inside_tree() else null)

func _apply_volume(bus_name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(idx, v <= 0.001)

## Реальное влияние качества на нагрузку: масштаб 3D-рендера, тени, дальность, частицы.
func apply_graphics(vp: Viewport) -> void:
	if vp == null:
		return
	var q := quality()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = [0.55, 0.7, 0.85, 1.0][q]
	vp.msaa_3d = Viewport.MSAA_DISABLED if q < Quality.HIGH else Viewport.MSAA_2X
	vp.positional_shadow_atlas_size = 0 if q < Quality.MEDIUM else 1024

func shadows_enabled() -> bool:
	return quality() >= Quality.MEDIUM

func view_distance() -> float:
	return [70.0, 95.0, 130.0, 170.0][quality()]

func particle_scale() -> float:
	return [0.15, 0.35, 0.7, 1.0][quality()]

func decor_density() -> float:
	return [0.35, 0.55, 0.8, 1.0][quality()]

func effects_enabled() -> bool:
	return quality() > Quality.MINIMAL
