extends Control

const WORLD_SHADER := preload("res://Shaders/world_generator.gdshader")
const STAR_SHADER := preload("res://Shaders/star_generator.gdshader")

@onready var planet: ColorRect = $Planet
@onready var planet_shadow: ColorRect = $PlanetShadow
@onready var moon_a: ColorRect = $OrbitLayer/MoonA
@onready var moon_b: ColorRect = $OrbitLayer/MoonB
@onready var title_label: Label = $UI/Header/Title
@onready var subtitle_label: Label = $UI/Header/SubTitle
@onready var meta_label: Label = $UI/Header/Meta
@onready var readout_panel: PanelContainer = $UI/ReadoutPanel
@onready var readout_label: Label = $UI/ReadoutPanel/Margin/ReadoutText
@onready var hint_label: Label = $UI/Hint
@onready var prev_button: Button = $UI/Controls/Prev
@onready var generate_button: Button = $UI/Controls/Generate
@onready var next_button: Button = $UI/Controls/Next
@onready var save_button: Button = $UI/SecondaryControls/Save
@onready var meteor_button: Button = $UI/SecondaryControls/Meteor
@onready var catalog_button: Button = $UI/SecondaryControls/Catalog
@onready var catalog_panel: PanelContainer = $UI/CatalogPanel
@onready var catalog_list: ItemList = $UI/CatalogPanel/Margin/VBox/CatalogList
@onready var catalog_close_button: Button = $UI/CatalogPanel/Margin/VBox/CloseCatalog
@onready var meteor: Control = $MeteorLayer/Meteor
@onready var impact_burst: Node2D = $MeteorLayer/ImpactBurst

var planet_rotation := Vector2(0.45, -0.08)
var rotation_velocity := Vector2.ZERO
var dragging := false
var active_touch := -1
var last_mouse_pos := Vector2.ZERO
var auto_rotation_speed := 0.085
var orbit_time := 0.0
var meteor_active := false

var rng := RandomNumberGenerator.new()
var discoveries: Array[Dictionary] = []
var favorites: Array[Dictionary] = []
var current_index := -1
var current_entry: Dictionary = {}
var moon_specs: Array[Dictionary] = []

const WORLD_TYPES := ["Earthlike", "Desert", "Ice", "Gas Giant", "Lava"]
const STAR_CLASSES := ["M-Type Red Dwarf", "K-Type Orange", "G-Type Yellow", "F-Type White", "A-Type Blue White"]

func _ready() -> void:
	rng.randomize()
	_setup_materials()
	_apply_mago_font()
	prev_button.pressed.connect(_show_previous)
	generate_button.pressed.connect(_generate_new)
	next_button.pressed.connect(_show_next)
	save_button.pressed.connect(_save_current_to_favorites)
	meteor_button.pressed.connect(_trigger_meteor)
	catalog_button.pressed.connect(_toggle_catalog)
	catalog_close_button.pressed.connect(_toggle_catalog)
	catalog_list.item_selected.connect(_on_catalog_item_selected)
	hint_label.text = "DRAG ANY DIRECTION TO ROTATE"
	catalog_panel.visible = false
	readout_panel.visible = true
	meteor.visible = false
	_load_favorites()
	_generate_new()

func _setup_materials() -> void:
	for moon in [moon_a, moon_b]:
		var moon_material := ShaderMaterial.new()
		moon_material.shader = WORLD_SHADER
		moon.material = moon_material
		moon.visible = false


func _apply_mago_font() -> void:
	# Scan the project's Fonts folder and use the first Mago TTF/OTF found.
	# If the font is unavailable, the scene's pixel-safe monospace fallback remains active.
	var font_path := _find_pixel_font("res://FONTS")
	if font_path.is_empty():
		font_path = _find_pixel_font("res://Fonts")
	if font_path.is_empty():
		return
	var loaded_font := ResourceLoader.load(font_path) as Font
	if loaded_font == null:
		return
	var ui_theme := $UI.theme.duplicate() as Theme
	ui_theme.default_font = loaded_font
	$UI.theme = ui_theme

func _find_pixel_font(directory_path: String) -> String:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return ""
	directory.list_dir_begin()
	var fallback := ""
	while true:
		var file_name := directory.get_next()
		if file_name.is_empty():
			break
		if file_name.begins_with("."):
			continue
		var full_path := directory_path.path_join(file_name)
		if directory.current_is_dir():
			var nested := _find_pixel_font(full_path)
			if not nested.is_empty():
				if nested.get_file().to_lower().contains("mago"):
					directory.list_dir_end()
					return nested
				if fallback.is_empty():
					fallback = nested
		else:
			var extension := file_name.get_extension().to_lower()
			if extension == "ttf" or extension == "otf":
				if file_name.to_lower().contains("mago"):
					directory.list_dir_end()
					return full_path
				if fallback.is_empty():
					fallback = full_path
	directory.list_dir_end()
	return fallback

func _process(delta: float) -> void:
	orbit_time += delta
	if not dragging:
		if rotation_velocity.length() > 0.001:
			planet_rotation += rotation_velocity * delta
			rotation_velocity = rotation_velocity.move_toward(Vector2.ZERO, 1.65 * delta)
		else:
			planet_rotation.x += auto_rotation_speed * delta

	planet_rotation.y = clamp(planet_rotation.y, -1.35, 1.35)
	_update_rotation_uniforms()
	_update_moons()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _pointer_over_controls(event.position):
			return
		if event.pressed and active_touch == -1:
			active_touch = event.index
			dragging = true
			rotation_velocity = Vector2.ZERO
			hint_label.text = "ROTATING"
		elif not event.pressed and event.index == active_touch:
			active_touch = -1
			dragging = false
			hint_label.text = "DRAG ANY DIRECTION TO ROTATE"
	elif event is InputEventScreenDrag and event.index == active_touch:
		_apply_drag(event.relative)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _pointer_over_controls(event.position):
			return
		dragging = event.pressed
		if event.pressed:
			rotation_velocity = Vector2.ZERO
		last_mouse_pos = event.position
		hint_label.text = "ROTATING" if event.pressed else "DRAG ANY DIRECTION TO ROTATE"
	elif event is InputEventMouseMotion and dragging and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var drag_delta = event.position - last_mouse_pos
		last_mouse_pos = event.position
		_apply_drag(drag_delta)

func _apply_drag(relative: Vector2) -> void:
	var delta_rotation := relative * 0.0105
	planet_rotation.x += delta_rotation.x
	planet_rotation.y += delta_rotation.y
	planet_rotation.y = clamp(planet_rotation.y, -1.35, 1.35)
	rotation_velocity = delta_rotation * 11.0
	_update_rotation_uniforms()

func _generate_new() -> void:
	if current_index < discoveries.size() - 1:
		discoveries = discoveries.slice(0, current_index + 1)
	var entry := _build_random_entry()
	discoveries.append(entry)
	current_index = discoveries.size() - 1
	_apply_entry(entry)

func _show_previous() -> void:
	if current_index > 0:
		current_index -= 1
		_apply_entry(discoveries[current_index])

func _show_next() -> void:
	if current_index < discoveries.size() - 1:
		current_index += 1
		_apply_entry(discoveries[current_index])

func _save_current_to_favorites() -> void:
	if current_entry.is_empty():
		return
	var signature := "%s|%s" % [str(current_entry.get("title", "")), str(current_entry.get("seed", ""))]
	for i in favorites.size():
		var entry := favorites[i]
		var existing_signature := "%s|%s" % [str(entry.get("title", "")), str(entry.get("seed", ""))]
		if existing_signature == signature:
			favorites[i] = current_entry.duplicate(true)
			_persist_favorites()
			_update_catalog_list()
			hint_label.text = "CATALOG ENTRY UPDATED"
			return
	favorites.append(current_entry.duplicate(true))
	_persist_favorites()
	_update_catalog_list()
	hint_label.text = "SAVED TO CATALOG"

func _persist_favorites() -> void:
	var file := FileAccess.open("user://planet_favorites.save", FileAccess.WRITE)
	if file:
		file.store_string(var_to_str(favorites))

func _load_favorites() -> void:
	if not FileAccess.file_exists("user://planet_favorites.save"):
		return
	var file := FileAccess.open("user://planet_favorites.save", FileAccess.READ)
	if file == null:
		return
	var loaded = str_to_var(file.get_as_text())
	if loaded is Array:
		favorites.clear()
		for item in loaded:
			if item is Dictionary:
				favorites.append(item)
	_update_catalog_list()

func _trigger_meteor() -> void:
	if meteor_active or current_entry.is_empty():
		return
	if current_entry.get("kind", "world") != "world":
		hint_label.text = "NO SOLID OR ATMOSPHERIC TARGET"
		return

	meteor_active = true
	meteor_button.disabled = true
	prev_button.disabled = true
	generate_button.disabled = true
	next_button.disabled = true
	save_button.disabled = true
	catalog_button.disabled = true
	rotation_velocity = Vector2.ZERO
	hint_label.text = "METEOR INBOUND"

	var target_p := Vector2.ZERO
	while target_p.length() < 0.18 or target_p.length() > 0.58:
		target_p = Vector2(rng.randf_range(-0.52, 0.52), rng.randf_range(-0.46, 0.46))

	var visual_radius: float = planet.size.x * 0.5 * float(current_entry.get("radius", 0.78))
	var planet_center := planet.position + planet.size * 0.5
	var target := planet_center + target_p * visual_radius
	var start := target + Vector2(rng.randf_range(245.0, 320.0), rng.randf_range(-390.0, -310.0))
	var direction := target - start

	meteor.position = start - meteor.pivot_offset
	meteor.rotation = direction.angle()
	meteor.modulate = Color(1, 1, 1, 1)
	meteor.visible = true

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(meteor, "position", target - meteor.pivot_offset, 0.78)
	tween.tween_callback(_meteor_impact.bind(target, target_p))

func _meteor_impact(target: Vector2, target_p: Vector2) -> void:
	meteor.visible = false
	if impact_burst.has_method("burst"):
		impact_burst.call("burst", target)

	var body_type := int(current_entry.get("body_type", 0))
	if body_type == 3:
		hint_label.text = "METEOR LOST IN DEEP ATMOSPHERE"
	else:
		var z := sqrt(max(0.0, 1.0 - target_p.dot(target_p)))
		var normal := Vector3(target_p.x, target_p.y, z).normalized()
		var impact_center := _rotate_y_vec3(normal, planet_rotation.x)
		impact_center = _rotate_x_vec3(impact_center, planet_rotation.y).normalized()
		current_entry["impact_enabled"] = true
		current_entry["impact_center"] = impact_center
		current_entry["impact_radius"] = rng.randf_range(0.105, 0.155)
		_apply_impact_to_material(current_entry)
		readout_label.text = _format_readout(current_entry)
		if current_index >= 0 and current_index < discoveries.size():
			discoveries[current_index] = current_entry.duplicate(true)
		hint_label.text = "IMPACT CRATER DETECTED"

	meteor_active = false
	meteor_button.disabled = false
	generate_button.disabled = false
	save_button.disabled = false
	catalog_button.disabled = false
	_update_buttons()

func _apply_impact_to_material(entry: Dictionary) -> void:
	var material := planet.material as ShaderMaterial
	if material == null or entry.get("kind", "world") != "world":
		return
	material.set_shader_parameter("impact_enabled", bool(entry.get("impact_enabled", false)))
	material.set_shader_parameter("impact_center", entry.get("impact_center", Vector3(0.0, 0.0, 1.0)))
	material.set_shader_parameter("impact_radius", float(entry.get("impact_radius", 0.13)))

func _rotate_y_vec3(v: Vector3, angle: float) -> Vector3:
	var c := cos(angle)
	var sn := sin(angle)
	return Vector3(c * v.x + sn * v.z, v.y, -sn * v.x + c * v.z)

func _rotate_x_vec3(v: Vector3, angle: float) -> Vector3:
	var c := cos(angle)
	var sn := sin(angle)
	return Vector3(v.x, c * v.y - sn * v.z, sn * v.y + c * v.z)

func _toggle_catalog() -> void:
	catalog_panel.visible = not catalog_panel.visible
	if catalog_panel.visible:
		_update_catalog_list()
		hint_label.text = "CATALOG OPEN"
	else:
		hint_label.text = "DRAG ANY DIRECTION TO ROTATE"

func _on_catalog_item_selected(index: int) -> void:
	if index >= 0 and index < favorites.size():
		_apply_entry(favorites[index].duplicate(true))
		catalog_panel.visible = false
		hint_label.text = "CATALOG ENTRY LOADED"

func _update_catalog_list() -> void:
	catalog_list.clear()
	for entry in favorites:
		catalog_list.add_item("%s  •  %s" % [entry.get("title", "UNKNOWN"), entry.get("subtitle", "BODY")])

func _update_rotation_uniforms() -> void:
	var planet_material := planet.material as ShaderMaterial
	if planet_material:
		planet_material.set_shader_parameter("rotation_xy", planet_rotation)
	for moon in [moon_a, moon_b]:
		var moon_material := moon.material as ShaderMaterial
		if moon.visible and moon_material:
			moon_material.set_shader_parameter("rotation_xy", planet_rotation + Vector2(orbit_time * 0.2, 0.0))

func _update_moons() -> void:
	var center := planet.position + planet.size * 0.5
	var moon_nodes := [moon_a, moon_b]
	for i in moon_nodes.size():
		var moon: ColorRect = moon_nodes[i]
		if i < moon_specs.size():
			var spec := moon_specs[i]
			var angle = orbit_time * spec["speed"] + spec["phase"]
			var offset := Vector2(cos(angle) * spec["orbit_x"], sin(angle) * spec["orbit_y"])
			moon.position = center + offset - moon.size * 0.5
			moon.visible = true
		else:
			moon.visible = false

func _apply_entry(entry: Dictionary) -> void:
	current_entry = entry.duplicate(true)
	moon_specs.clear()
	var material := planet.material as ShaderMaterial
	if material == null:
		return

	if entry.get("kind", "world") == "star":
		planet_shadow.visible = false
		moon_a.visible = false
		moon_b.visible = false
		material.shader = STAR_SHADER
		material.set_shader_parameter("seed", entry["seed"])
		material.set_shader_parameter("pixel_resolution", entry["pixel_resolution"])
		material.set_shader_parameter("planet_radius", entry["radius"])
		material.set_shader_parameter("core_color", entry["core_color"])
		material.set_shader_parameter("mid_color", entry["mid_color"])
		material.set_shader_parameter("edge_color", entry["edge_color"])
		material.set_shader_parameter("glow_color", entry["glow_color"])
		material.set_shader_parameter("local_light_dir", entry["light_dir"])
		material.set_shader_parameter("lighting_strength", 0.55)
	else:
		planet_shadow.visible = true
		material.shader = WORLD_SHADER
		material.set_shader_parameter("seed", entry["seed"])
		material.set_shader_parameter("pixel_resolution", entry["pixel_resolution"])
		material.set_shader_parameter("planet_radius", entry["radius"])
		material.set_shader_parameter("body_type", entry["body_type"])
		material.set_shader_parameter("local_light_dir", entry["light_dir"])
		material.set_shader_parameter("lighting_strength", 0.92)
		_apply_impact_to_material(entry)
		_configure_moons(entry)

	auto_rotation_speed = entry["rotation_speed"]
	title_label.text = entry["title"]
	subtitle_label.text = entry["subtitle"]
	meta_label.text = entry["meta"]
	readout_label.text = _format_readout(entry)
	meteor_button.disabled = entry.get("kind", "world") != "world" or meteor_active
	_update_rotation_uniforms()
	_update_buttons()

func _configure_moons(entry: Dictionary) -> void:
	moon_specs = entry.get("moons", [])
	var moon_nodes := [moon_a, moon_b]
	for i in moon_nodes.size():
		var moon: ColorRect = moon_nodes[i]
		if i < moon_specs.size():
			var spec := moon_specs[i]
			moon.size = Vector2.ONE * spec["size"]
			var mat := moon.material as ShaderMaterial
			mat.shader = WORLD_SHADER
			mat.set_shader_parameter("seed", spec["seed"])
			mat.set_shader_parameter("pixel_resolution", 96.0)
			mat.set_shader_parameter("planet_radius", 0.78)
			mat.set_shader_parameter("body_type", spec["body_type"])
			mat.set_shader_parameter("local_light_dir", entry["light_dir"])
			mat.set_shader_parameter("lighting_strength", 0.82)
			moon.visible = true
		else:
			moon.visible = false

func _format_readout(entry: Dictionary) -> String:
	var water_text := "N/A"
	if entry.get("water", -1) >= 0:
		water_text = "%d%%" % int(entry["water"])
	var habitability_text := "%d%%" % int(entry.get("habitability", 0))
	var moons_count := 0
	if entry.get("kind", "world") == "world":
		moons_count = (entry.get("moons", []) as Array).size()
	return "SCAN READOUT\nATMOSPHERE: %s\nTEMPERATURE: %s\nWATER: %s\nHABITABILITY: %s\nMOONS: %d\nIMPACT SCAR: %s" % [
		entry.get("atmosphere", "UNKNOWN"),
		entry.get("temperature_text", "UNKNOWN"),
		water_text,
		habitability_text,
		moons_count,
		"DETECTED" if entry.get("impact_enabled", false) else "NONE"
	]

func _build_random_entry() -> Dictionary:
	var seed_value := rng.randi_range(1000, 999999)
	var light_dir := Vector3(rng.randf_range(-0.75, -0.25), rng.randf_range(-0.35, 0.25), rng.randf_range(0.55, 0.92)).normalized()
	var roll := rng.randi_range(0, 99)
	var is_star := roll < 18
	if is_star:
		var class_index := rng.randi_range(0, STAR_CLASSES.size() - 1)
		var palette := _star_palette(class_index)
		var star_temp = [3200, 4500, 5800, 7200, 9400][class_index]
		return {
			"kind": "star",
			"seed": float(seed_value),
			"title": _make_name(true),
			"subtitle": STAR_CLASSES[class_index],
			"meta": "STAR • CLASS %s • SEED %d" % [STAR_CLASSES[class_index].substr(0, 1), seed_value],
			"core_color": palette[0],
			"mid_color": palette[1],
			"edge_color": palette[2],
			"glow_color": palette[3],
			"radius": rng.randf_range(0.72, 0.82),
			"pixel_resolution": 128.0,
			"rotation_speed": rng.randf_range(0.05, 0.10),
			"atmosphere": "STELLAR PLASMA",
			"temperature_text": "%d K" % star_temp,
			"water": -1,
			"habitability": 0,
			"has_rings": false,
			"light_dir": light_dir
		}

	var world_index := _weighted_world_type()
	var moon_count := 0
	if world_index == 3:
		moon_count = rng.randi_range(1, 2)
	else:
		moon_count = rng.randi_range(0, 2)

	var atmosphere := "UNKNOWN"
	var temp_value := 0
	var water := 0
	var habitability := 0

	match world_index:
		0:
			atmosphere = ["BREATHABLE NITROGEN-OXYGEN", "TEMPERATE CLOUD LAYER", "OCEANIC AIR MASS"][rng.randi_range(0, 2)]
			temp_value = rng.randi_range(-8, 34)
			water = rng.randi_range(42, 86)
			habitability = rng.randi_range(48, 93)
		1:
			atmosphere = ["THIN DUST ATMOSPHERE", "ARID MINERAL HAZE", "DRY CO2 LAYER"][rng.randi_range(0, 2)]
			temp_value = rng.randi_range(14, 96)
			water = rng.randi_range(0, 22)
			habitability = rng.randi_range(4, 30)
		2:
			atmosphere = ["FROZEN METHANE HAZE", "THIN CRYOGENIC AIR", "SUBSURFACE VAPOR TRACES"][rng.randi_range(0, 2)]
			temp_value = rng.randi_range(-170, -6)
			water = rng.randi_range(38, 97)
			habitability = rng.randi_range(0, 18)
		3:
			atmosphere = ["HYDROGEN-HELIUM ENVELOPE", "BAND STORM SYSTEM", "DEEP AMMONIA CLOUDS"][rng.randi_range(0, 2)]
			temp_value = rng.randi_range(-140, 90)
			water = rng.randi_range(0, 5)
			habitability = 0
		4:
			atmosphere = ["VOLCANIC ASH PLUME", "SULFURIC FUMES", "SUPERHEATED MINERAL VAPOR"][rng.randi_range(0, 2)]
			temp_value = rng.randi_range(280, 980)
			water = 0
			habitability = rng.randi_range(0, 4)

	var moons: Array[Dictionary] = []
	for i in moon_count:
		var moon_type := 5
		if world_index == 3 and rng.randf() < 0.35:
			moon_type = 2
		moons.append({
			"seed": float(seed_value + 91 + i * 17),
			"size": 38.0 + float(i) * 10.0 + rng.randf_range(-4.0, 8.0),
			"orbit_x": 168.0 + float(i) * 44.0 + rng.randf_range(-8.0, 18.0),
			"orbit_y": 108.0 + float(i) * 30.0 + rng.randf_range(-6.0, 14.0),
			"speed": 0.38 + float(i) * 0.09 + rng.randf_range(-0.05, 0.07),
			"phase": rng.randf_range(0.0, TAU),
			"body_type": moon_type
		})


	return {
		"kind": "world",
		"body_type": world_index,
		"seed": float(seed_value),
		"title": _make_name(false),
		"subtitle": WORLD_TYPES[world_index],
		"meta": "WORLD • SEED %d • TYPE %s" % [seed_value, WORLD_TYPES[world_index].to_upper()],
		"radius": rng.randf_range(0.73, 0.82),
		"pixel_resolution": 128.0,
		"rotation_speed": rng.randf_range(0.07, 0.12),
		"atmosphere": atmosphere,
		"temperature_text": "%d°C" % temp_value,
		"water": water,
		"habitability": habitability,
		"has_rings": false,
		"impact_enabled": false,
		"impact_center": Vector3(0.0, 0.0, 1.0),
		"impact_radius": 0.13,
		"moons": moons,
		"light_dir": light_dir
	}

func _weighted_world_type() -> int:
	var roll := rng.randi_range(0, 99)
	if roll < 30:
		return 0
	elif roll < 48:
		return 1
	elif roll < 64:
		return 2
	elif roll < 84:
		return 3
	return 4

func _update_buttons() -> void:
	prev_button.disabled = current_index <= 0
	next_button.disabled = current_index >= discoveries.size() - 1

func _pointer_over_controls(global_position: Vector2) -> bool:
	if $UI/Controls.get_global_rect().has_point(global_position):
		return true
	if $UI/SecondaryControls.get_global_rect().has_point(global_position):
		return true
	if catalog_panel.visible and catalog_panel.get_global_rect().has_point(global_position):
		return true
	return false

func _make_name(is_star: bool) -> String:
	var starts := ["AR", "VE", "CY", "NO", "TA", "EL", "OR", "LU", "KA", "ZE", "THA", "SOL", "MY", "XA"]
	var mids := ["ra", "li", "no", "the", "sa", "ve", "ko", "dra", "mi", "ta", "ru", "za", "ion", "os"]
	var ends := ["-3", "-7", "-9", " PRIME", " MINOR", " IX", " V", "-12", " MAJOR", "-81", " A", " B"]
	var base = starts[rng.randi_range(0, starts.size() - 1)] + mids[rng.randi_range(0, mids.size() - 1)]
	if is_star:
		return base.to_upper() + ends[rng.randi_range(0, ends.size() - 1)]
	return (base + ends[rng.randi_range(0, ends.size() - 1)]).to_upper()

func _star_palette(class_index: int) -> Array:
	match class_index:
		0:
			return [Color(1.00, 0.74, 0.52), Color(0.98, 0.47, 0.22), Color(0.83, 0.23, 0.10), Color(1.00, 0.42, 0.18)]
		1:
			return [Color(1.00, 0.88, 0.58), Color(1.00, 0.68, 0.24), Color(0.97, 0.47, 0.16), Color(1.00, 0.62, 0.21)]
		2:
			return [Color(1.00, 0.97, 0.72), Color(1.00, 0.82, 0.32), Color(0.99, 0.56, 0.14), Color(1.00, 0.72, 0.24)]
		3:
			return [Color(1.00, 0.99, 0.90), Color(0.98, 0.92, 0.70), Color(0.96, 0.76, 0.44), Color(0.94, 0.86, 0.58)]
		_:
			return [Color(0.90, 0.95, 1.00), Color(0.73, 0.86, 0.99), Color(0.50, 0.70, 0.95), Color(0.58, 0.77, 1.00)]
