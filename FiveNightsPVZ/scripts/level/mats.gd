class_name Mats
extends RefCounted
## Библиотека процедурных материалов (кэшируется).

static var _cache := {}
static var _surface_shader: Shader
static var _card_shader: Shader


static func surface(key: String) -> Material:
	if _cache.has(key):
		return _cache[key]
	if _surface_shader == null:
		_surface_shader = load("res://shaders/surface.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _surface_shader
	match key:
		"floor_tile":
			m.set_shader_parameter("mode", 1)
			m.set_shader_parameter("base_color", Color(0.56, 0.55, 0.52))
			m.set_shader_parameter("alt_color", Color(0.42, 0.4, 0.37))
			m.set_shader_parameter("grout_color", Color(0.2, 0.19, 0.17))
			m.set_shader_parameter("tile_size", Vector2(0.4, 0.4))
			m.set_shader_parameter("dirt", 0.45)
			m.set_shader_parameter("wet", 0.15)
		"wall_tile":
			m.set_shader_parameter("mode", 1)
			m.set_shader_parameter("base_color", Color(0.72, 0.76, 0.74))
			m.set_shader_parameter("alt_color", Color(0.6, 0.66, 0.65))
			m.set_shader_parameter("grout_color", Color(0.32, 0.31, 0.27))
			m.set_shader_parameter("tile_size", Vector2(0.2, 0.15))
			m.set_shader_parameter("leaks", 0.55)
			m.set_shader_parameter("dirt", 0.3)
		"wall_paint":
			m.set_shader_parameter("mode", 0)
			m.set_shader_parameter("base_color", Color(0.74, 0.72, 0.66))
			m.set_shader_parameter("leaks", 0.35)
			m.set_shader_parameter("dirt", 0.25)
		"wall_green":
			# советская панель: крашено зелёным до середины
			m.set_shader_parameter("mode", 0)
			m.set_shader_parameter("base_color", Color(0.36, 0.47, 0.4))
			m.set_shader_parameter("leaks", 0.6)
			m.set_shader_parameter("dirt", 0.4)
		"wall_warehouse":
			m.set_shader_parameter("mode", 2)
			m.set_shader_parameter("base_color", Color(0.55, 0.55, 0.53))
			m.set_shader_parameter("leaks", 0.7)
			m.set_shader_parameter("dirt", 0.45)
		"concrete":
			m.set_shader_parameter("mode", 2)
			m.set_shader_parameter("base_color", Color(0.45, 0.44, 0.42))
			m.set_shader_parameter("dirt", 0.55)
		"linoleum":
			m.set_shader_parameter("mode", 3)
			m.set_shader_parameter("base_color", Color(0.42, 0.33, 0.26))
			m.set_shader_parameter("dirt", 0.4)
		"ceiling":
			m.set_shader_parameter("mode", 4)
			m.set_shader_parameter("base_color", Color(0.78, 0.77, 0.73))
			m.set_shader_parameter("alt_color", Color(0.65, 0.6, 0.5))
			m.set_shader_parameter("grout_color", Color(0.5, 0.5, 0.48))
			m.set_shader_parameter("tile_size", Vector2(0.6, 0.6))
			m.set_shader_parameter("grout", 0.02)
			m.set_shader_parameter("dirt", 0.5)
			m.set_shader_parameter("dirt_color", Color(0.45, 0.36, 0.22))
		"asphalt":
			m.set_shader_parameter("mode", 2)
			m.set_shader_parameter("base_color", Color(0.17, 0.17, 0.18))
			m.set_shader_parameter("dirt", 0.3)
			m.set_shader_parameter("wet", 0.6)
		"exterior":
			m.set_shader_parameter("mode", 1)
			m.set_shader_parameter("base_color", Color(0.45, 0.38, 0.33))
			m.set_shader_parameter("alt_color", Color(0.4, 0.33, 0.3))
			m.set_shader_parameter("tile_size", Vector2(0.25, 0.08))
			m.set_shader_parameter("leaks", 0.6)
		_:
			m.set_shader_parameter("mode", 0)
	_cache[key] = m
	return m


static func color(c: Color, rough := 0.8, metal := 0.0, key := "") -> StandardMaterial3D:
	var k := key if key != "" else "c_%s_%.2f_%.2f" % [c.to_html(), rough, metal]
	if _cache.has(k):
		return _cache[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	_cache[k] = m
	return m


static func emissive(c: Color, energy := 1.0, key := "") -> StandardMaterial3D:
	var k := key if key != "" else "e_%s_%.2f" % [c.to_html(), energy]
	if _cache.has(k):
		return _cache[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	_cache[k] = m
	return m


static func glass() -> StandardMaterial3D:
	if _cache.has("glass"):
		return _cache["glass"]
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.55, 0.65, 0.7, 0.18)
	m.roughness = 0.05
	m.metallic = 0.2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache["glass"] = m
	return m


static func mirror() -> StandardMaterial3D:
	if _cache.has("mirror"):
		return _cache["mirror"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.32, 0.35, 0.36)
	m.roughness = 0.04
	m.metallic = 1.0
	_cache["mirror"] = m
	return m


static func cardboard(seed_v := -1.0, instanced := false) -> ShaderMaterial:
	if _card_shader == null:
		_card_shader = load("res://shaders/cardboard.gdshader")
	if instanced:
		if _cache.has("card_inst"):
			return _cache["card_inst"]
		var mi := ShaderMaterial.new()
		mi.shader = _card_shader
		mi.set_shader_parameter("use_instance", true)
		_cache["card_inst"] = mi
		return mi
	var m := ShaderMaterial.new()
	m.shader = _card_shader
	m.set_shader_parameter("seed", seed_v if seed_v >= 0.0 else randf() * 100.0)
	return m


static func metal(c := Color(0.45, 0.47, 0.5)) -> StandardMaterial3D:
	return color(c, 0.45, 0.7)


## Текстура штрихкода/надписи для плакатов и наклеек.
static func poster_texture(lines: PackedStringArray, bg: Color, fg: Color) -> ImageTexture:
	var key := "poster_" + "|".join(lines) + bg.to_html()
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(64, 96, false, Image.FORMAT_RGB8)
	img.fill(bg)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	for i in 6:
		var y := 10 + i * 13
		var w := rng.randi_range(20, 54)
		img.fill_rect(Rect2i(5, y, w, 4 if i > 0 else 9), fg)
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t
