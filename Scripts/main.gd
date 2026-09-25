extends Control

const WORLD_SHADER := preload("res://Shaders/world_generator.gdshader")
const STAR_SHADER := preload("res://Shaders/star_generator.gdshader")

@onready var planet: ColorRect = $Planet
@onready var planet_shadow: ColorRect = $PlanetShadow
@onready var moon_a: ColorRect = $OrbitLayer/MoonA
@onready var moon_b: ColorRect = $OrbitLayer/MoonB
@onready var title_label: Label = $UI/Header/Title
@onready var subtitle_label: Label = $UI/Header/SubTitle
@onready var info_label: Label = $UI/InfoLine
@onready var hint_label: Label = $UI/Hint
@onready var prev_button: Button = $UI/NavControls/Prev
@onready var generate_button: Button = $UI/NavControls/Generate
@onready var next_button: Button = $UI/NavControls/Next
@onready var zoom_out_button: Button = $UI/NavControls/ZoomOut
@onready var zoom_in_button: Button = $UI/NavControls/ZoomIn
@onready var freeze_button: Button = $UI/ActionControls/Freeze
@onready var heat_button: Button = $UI/ActionControls/Heat
@onready var meteor_button: Button = $UI/ActionControls/Meteor
@onready var black_hole_button: Button = $UI/ActionControls/BlackHole
@onready var save_button: Button = $UI/ActionControls/Save
@onready var catalog_button: Button = $UI/ActionControls/Catalog
@onready var catalog_panel: PanelContainer = $UI/CatalogPanel
@onready var catalog_list: ItemList = $UI/CatalogPanel/Margin/VBox/CatalogList
@onready var catalog_close_button: Button = $UI/CatalogPanel/Margin/VBox/CloseCatalog
@onready var meteor: Control = $MeteorLayer/Meteor
@onready var impact_burst: Node2D = $MeteorLayer/ImpactBurst
@onready var black_hole_effect: Node2D = $MeteorLayer/BlackHoleEffect

var planet_rotation := Vector2(0.45, -0.08)
var rotation_velocity := Vector2.ZERO
var dragging := false
var active_touch := -1
var last_mouse_pos := Vector2.ZERO
var auto_rotation_speed := 0.085
var orbit_time := 0.0

var meteor_active := false
var meteor_target_mode := false
var climate_visual := 0.0
var climate_tween: Tween = null
var zoom_tween: Tween = null
var blackhole_tween: Tween = null
var blackhole_active := false

var zoom_factor := 1.0
var event_scale := 1.0
var event_stretch := Vector2.ONE
var event_offset := Vector2.ZERO
var planet_base_position := Vector2.ZERO
var shadow_base_position := Vector2.ZERO

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
	planet_base_position = planet.position
	shadow_base_position = planet_shadow.position
	planet.pivot_offset = planet.size * 0.5
	planet_shadow.pivot_offset = planet_shadow.size * 0.5
	prev_button.pressed.connect(_show_previous)
	generate_button.pressed.connect(_generate_new)
	next_button.pressed.connect(_show_next)
	zoom_out_button.pressed.connect(_zoom_out)
	zoom_in_button.pressed.connect(_zoom_in)
	freeze_button.pressed.connect(_freeze_current)
	heat_button.pressed.connect(_heat_current)
	meteor_button.pressed.connect(_trigger_meteor)
	black_hole_button.pressed.connect(_trigger_blackhole)
	save_button.pressed.connect(_save_current_to_favorites)
	catalog_button.pressed.connect(_toggle_catalog)
	catalog_close_button.pressed.connect(_toggle_catalog)
	catalog_list.item_selected.connect(_on_catalog_item_selected)
	hint_label.text = "DRAG TO ROTATE"
	catalog_panel.visible = false
	meteor.visible = false
	black_hole_effect.visible = false
	_apply_celestial_transform()
	_load_favorites()
	_generate_new()

func _setup_materials() -> void:
	for moon in [moon_a, moon_b]:
		var moon_material := ShaderMaterial.new()
		moon_material.shader = WORLD_SHADER
		moon.material = moon_material
		moon.visible = false

func _apply_mago_font() -> void:
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
	if blackhole_active:
		planet_rotation.x += auto_rotation_speed * 4.0 * delta
	elif not dragging and not meteor_target_mode:
		if rotation_velocity.length() > 0.001:
			planet_rotation += rotation_velocity * delta
			rotation_velocity = rotation_velocity.move_toward(Vector2.ZERO, 1.65 * delta)
		else:
			planet_rotation.x += auto_rotation_speed * delta

	planet_rotation.y = clamp(planet_rotation.y, -1.35, 1.35)
	_apply_celestial_transform()
	_update_rotation_uniforms()
	_update_moons()

func _input(event: InputEvent) -> void:
	if blackhole_active:
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_change_zoom(0.10)
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_change_zoom(-0.10)
			return

	if meteor_target_mode:
		if event is InputEventScreenTouch and event.pressed:
			if not _pointer_over_controls(event.position):
				_attempt_meteor_target(event.position)
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if not _pointer_over_controls(event.position):
				_attempt_meteor_target(event.position)
			return
		return

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
			hint_label.text = "DRAG TO ROTATE"
	elif event is InputEventScreenDrag and event.index == active_touch:
		_apply_drag(event.relative)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _pointer_over_controls(event.position):
			return
		dragging = event.pressed
		if event.pressed:
			rotation_velocity = Vector2.ZERO
		last_mouse_pos = event.position
		hint_label.text = "ROTATING" if event.pressed else "DRAG TO ROTATE"
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
	_cancel_meteor_target(false)
	if current_index < discoveries.size() - 1:
		discoveries = discoveries.slice(0, current_index + 1)
	var entry := _build_random_entry()
	discoveries.append(entry)
	current_index = discoveries.size() - 1
	_apply_entry(entry)

func _show_previous() -> void:
	_cancel_meteor_target(false)
	if current_index > 0:
		current_index -= 1
		_apply_entry(discoveries[current_index])

func _show_next() -> void:
	_cancel_meteor_target(false)
	if current_index < discoveries.size() - 1:
		current_index += 1
		_apply_entry(discoveries[current_index])

func _freeze_current() -> void:
	_adjust_climate(-0.34)

func _heat_current() -> void:
	_adjust_climate(0.34)

func _adjust_climate(amount: float) -> void:
	if current_entry.is_empty() or current_entry.get("kind", "world") != "world":
		hint_label.text = "CLIMATE CONTROL UNAVAILABLE"
		return
	if meteor_active or meteor_target_mode:
		return

	var target = clamp(climate_visual + amount, -1.0, 1.0)
	if is_equal_approx(target, climate_visual):
		hint_label.text = "CLIMATE LIMIT REACHED"
		return

	if climate_tween != null and climate_tween.is_valid():
		climate_tween.kill()
	rotation_velocity = Vector2.ZERO
	hint_label.text = "FREEZING WORLD" if amount < 0.0 else "HEATING WORLD"
	climate_tween = create_tween()
	climate_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	climate_tween.tween_method(_set_climate_visual, climate_visual, target, 1.65)
	climate_tween.tween_callback(_finish_climate.bind(target))

func _set_climate_visual(value: float) -> void:
	climate_visual = value
	var material := planet.material as ShaderMaterial
	if material and current_entry.get("kind", "world") == "world":
		material.set_shader_parameter("climate_shift", climate_visual)
	info_label.text = _format_info_line(current_entry)

func _finish_climate(value: float) -> void:
	climate_visual = value
	current_entry["climate_shift"] = value
	if current_index >= 0 and current_index < discoveries.size():
		discoveries[current_index] = current_entry.duplicate(true)
	info_label.text = _format_info_line(current_entry)
	hint_label.text = "CLIMATE STABILIZED"

func _trigger_meteor() -> void:
	if meteor_active or current_entry.is_empty():
		return
	if current_entry.get("kind", "world") != "world":
		hint_label.text = "NO PLANETARY TARGET"
		return
	if meteor_target_mode:
		_cancel_meteor_target(true)
		return

	meteor_target_mode = true
	rotation_velocity = Vector2.ZERO
	dragging = false
	active_touch = -1
	meteor_button.text = "CANCEL"
	hint_label.text = "TAP PLANET TO TARGET"
	_set_event_controls_disabled(true, false)

func _cancel_meteor_target(show_hint: bool) -> void:
	if not meteor_target_mode:
		return
	meteor_target_mode = false
	meteor_button.text = "METEOR"
	_set_event_controls_disabled(false, false)
	_update_buttons()
	if show_hint:
		hint_label.text = "METEOR TARGETING CANCELED"

func _attempt_meteor_target(screen_position: Vector2) -> void:
	# Convert the screen tap back into the planet's local pixel space so targeting
	# remains exact at every zoom level.
	var local_position: Vector2 = planet.get_global_transform().affine_inverse() * screen_position
	var center := planet.size * 0.5
	var visual_radius: float = planet.size.x * 0.5 * float(current_entry.get("radius", 0.78))
	if visual_radius <= 0.0:
		return
	var target_p := (local_position - center) / visual_radius
	if target_p.length() > 0.97:
		hint_label.text = "TAP DIRECTLY ON PLANET"
		return
	_launch_meteor(screen_position, target_p)

func _launch_meteor(target: Vector2, target_p: Vector2) -> void:
	meteor_target_mode = false
	meteor_active = true
	meteor_button.text = "METEOR"
	_set_event_controls_disabled(true, true)
	rotation_velocity = Vector2.ZERO
	hint_label.text = "METEOR INBOUND"

	var start := target + Vector2(rng.randf_range(300.0, 430.0), rng.randf_range(-340.0, -240.0))
	var direction := target - start
	meteor.position = start - meteor.pivot_offset
	meteor.rotation = direction.angle()
	meteor.modulate = Color(1, 1, 1, 1)
	meteor.visible = true

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(meteor, "position", target - meteor.pivot_offset, 0.72)
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
		if current_index >= 0 and current_index < discoveries.size():
			discoveries[current_index] = current_entry.duplicate(true)
		info_label.text = _format_info_line(current_entry)
		hint_label.text = "IMPACT CRATER FORMED"

	meteor_active = false
	_set_event_controls_disabled(false, false)
	_update_buttons()

func _set_event_controls_disabled(disabled: bool, disable_meteor: bool) -> void:
	prev_button.disabled = disabled
	generate_button.disabled = disabled
	next_button.disabled = disabled
	freeze_button.disabled = disabled
	heat_button.disabled = disabled
	save_button.disabled = disabled
	catalog_button.disabled = disabled
	black_hole_button.disabled = disabled
	zoom_out_button.disabled = disabled
	zoom_in_button.disabled = disabled
	meteor_button.disabled = disabled if disable_meteor else false

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

func _zoom_out() -> void:
	_change_zoom(-0.12)

func _zoom_in() -> void:
	_change_zoom(0.12)

func _change_zoom(amount: float) -> void:
	if blackhole_active or meteor_active or meteor_target_mode:
		return
	var target = clamp(zoom_factor + amount, 0.66, 1.46)
	if is_equal_approx(target, zoom_factor):
		return
	if zoom_tween != null and zoom_tween.is_valid():
		zoom_tween.kill()
	zoom_tween = create_tween()
	zoom_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	zoom_tween.tween_property(self, "zoom_factor", target, 0.22)
	hint_label.text = "ZOOM %d" % int(round(target * 100.0))

func _apply_celestial_transform() -> void:
	var combined := zoom_factor * event_scale
	planet.position = planet_base_position + event_offset
	planet_shadow.position = shadow_base_position + event_offset
	planet.scale = Vector2(combined * event_stretch.x, combined * event_stretch.y)
	planet_shadow.scale = Vector2(combined * event_stretch.x, combined * event_stretch.y)

func _trigger_blackhole() -> void:
	if blackhole_active or meteor_active or current_entry.is_empty():
		return
	_cancel_meteor_target(false)
	blackhole_active = true
	dragging = false
	active_touch = -1
	rotation_velocity = Vector2.ZERO
	if climate_tween != null and climate_tween.is_valid():
		climate_tween.kill()
	if zoom_tween != null and zoom_tween.is_valid():
		zoom_tween.kill()
	_set_event_controls_disabled(true, true)
	black_hole_button.disabled = true
	hint_label.text = "GRAVITATIONAL ANOMALY DETECTED"

	event_scale = 1.0
	event_stretch = Vector2.ONE
	event_offset = Vector2.ZERO
	_set_blackhole_dissolve(0.0)
	planet.modulate = Color.WHITE
	planet_shadow.modulate = Color(1, 1, 1, 1)
	moon_a.modulate = Color.WHITE
	moon_b.modulate = Color.WHITE

	var viewport_size := get_viewport_rect().size
	var hole_center := Vector2(viewport_size.x * 0.79, viewport_size.y * 0.47)
	if black_hole_effect.has_method("start"):
		black_hole_effect.call("start", hole_center, viewport_size)

	var snapshot := _capture_planet_snapshot()
	var planet_center := planet.global_position + planet.size * 0.5
	var pull_vector := hole_center - planet_center

	blackhole_tween = create_tween()
	blackhole_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# PHASE 1 - Hold the planet mostly intact while its hole-facing pixels are
	# pulled off sequentially into the accretion flow.
	blackhole_tween.tween_interval(0.46)
	blackhole_tween.tween_callback(func() -> void: hint_label.text = "PIXEL SHEAR")
	blackhole_tween.tween_callback(func() -> void: _begin_blackhole_dissolve(snapshot))
	blackhole_tween.tween_method(_set_blackhole_dissolve, 0.0, 0.48, 2.45)
	blackhole_tween.parallel().tween_property(self, "event_offset", pull_vector * 0.07, 2.45)
	blackhole_tween.parallel().tween_property(self, "event_scale", 0.98, 2.45)

	# PHASE 2 - Once the pixel stream has finished, the remaining body enters
	# the familiar tidal warp sequence.
	blackhole_tween.tween_callback(func() -> void: hint_label.text = "TIDAL FORCES RISING")
	blackhole_tween.tween_property(self, "event_scale", 0.86, 0.62)
	blackhole_tween.parallel().tween_property(self, "event_stretch", Vector2(1.34, 0.82), 0.62)
	blackhole_tween.parallel().tween_property(self, "event_offset", pull_vector * 0.24, 0.62)

	blackhole_tween.tween_callback(func() -> void: hint_label.text = "ACCRETION CAPTURE")
	blackhole_tween.tween_property(self, "event_scale", 0.54, 0.78)
	blackhole_tween.parallel().tween_property(self, "event_stretch", Vector2(1.72, 0.58), 0.78)
	blackhole_tween.parallel().tween_property(self, "event_offset", pull_vector * 0.63, 0.78)
	blackhole_tween.parallel().tween_property(planet, "modulate", Color(1, 1, 1, 0.68), 0.78)
	blackhole_tween.parallel().tween_property(planet_shadow, "modulate", Color(1, 1, 1, 0.50), 0.78)
	blackhole_tween.parallel().tween_property(moon_a, "modulate", Color(1, 1, 1, 0.58), 0.78)
	blackhole_tween.parallel().tween_property(moon_b, "modulate", Color(1, 1, 1, 0.58), 0.78)

	blackhole_tween.tween_callback(func() -> void: hint_label.text = "EVENT HORIZON")
	blackhole_tween.tween_property(self, "event_scale", 0.07, 0.72)
	blackhole_tween.parallel().tween_property(self, "event_stretch", Vector2(2.55, 0.20), 0.72)
	blackhole_tween.parallel().tween_property(self, "event_offset", pull_vector, 0.72)
	blackhole_tween.parallel().tween_property(planet, "modulate", Color(1, 1, 1, 0), 0.72)
	blackhole_tween.parallel().tween_property(planet_shadow, "modulate", Color(1, 1, 1, 0), 0.72)
	blackhole_tween.parallel().tween_property(moon_a, "modulate", Color(1, 1, 1, 0), 0.72)
	blackhole_tween.parallel().tween_property(moon_b, "modulate", Color(1, 1, 1, 0), 0.72)
	blackhole_tween.tween_callback(_finish_blackhole)

func _set_blackhole_dissolve(value: float) -> void:
	var material := planet.material as ShaderMaterial
	if material:
		material.set_shader_parameter("blackhole_dissolve", value)

func _get_planet_screen_rect() -> Rect2:
	var transform := planet.get_global_transform()
	var corners := [
		transform * Vector2.ZERO,
		transform * Vector2(planet.size.x, 0.0),
		transform * planet.size,
		transform * Vector2(0.0, planet.size.y)
	]
	var min_p: Vector2 = corners[0]
	var max_p: Vector2 = corners[0]
	for point in corners:
		min_p.x = min(min_p.x, point.x)
		min_p.y = min(min_p.y, point.y)
		max_p.x = max(max_p.x, point.x)
		max_p.y = max(max_p.y, point.y)
	return Rect2(min_p, max_p - min_p)

func _capture_planet_snapshot() -> Dictionary:
	var data: Dictionary = {}
	var viewport_texture := get_viewport().get_texture()
	if viewport_texture == null:
		return data
	var image := viewport_texture.get_image()
	if image == null:
		return data
	data["image"] = image
	data["rect"] = _get_planet_screen_rect()
	return data

func _begin_blackhole_dissolve(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	if not black_hole_effect.has_method("begin_dissolve"):
		return
	var image = snapshot.get("image", null)
	var rect: Rect2 = snapshot.get("rect", Rect2())
	black_hole_effect.call("begin_dissolve", image, rect)

func _finish_blackhole() -> void:
	hint_label.text = "OBJECT CONSUMED"
	var post := create_tween()
	post.tween_interval(0.60)
	post.tween_callback(_reset_after_blackhole)

func _reset_after_blackhole() -> void:
	if black_hole_effect.has_method("stop"):
		black_hole_effect.call("stop")
	event_scale = 1.0
	event_stretch = Vector2.ONE
	event_offset = Vector2.ZERO
	_set_blackhole_dissolve(0.0)
	planet.modulate = Color.WHITE
	planet_shadow.modulate = Color.WHITE
	moon_a.modulate = Color.WHITE
	moon_b.modulate = Color.WHITE
	blackhole_active = false
	_apply_celestial_transform()
	_generate_new()
	hint_label.text = "NEW DISCOVERY"

func _save_current_to_favorites() -> void:
	if current_entry.is_empty():
		return
	var signature := "%s|%s" % [str(current_entry.get("title", "")), str(current_entry.get("seed", ""))]
	for i in range(favorites.size()):
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

func _toggle_catalog() -> void:
	if meteor_target_mode or meteor_active or blackhole_active:
		return
	catalog_panel.visible = not catalog_panel.visible
	if catalog_panel.visible:
		_update_catalog_list()
		hint_label.text = "CATALOG OPEN"
	else:
		hint_label.text = "DRAG TO ROTATE"

func _on_catalog_item_selected(index: int) -> void:
	if index >= 0 and index < favorites.size():
		_apply_entry(favorites[index].duplicate(true))
		catalog_panel.visible = false
		hint_label.text = "CATALOG ENTRY LOADED"

func _update_catalog_list() -> void:
	catalog_list.clear()
	for entry in favorites:
		catalog_list.add_item("%s  %s" % [entry.get("title", "UNKNOWN"), entry.get("subtitle", "BODY")])

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
	for i in range(moon_nodes.size()):
		var moon: ColorRect = moon_nodes[i]
		if i < moon_specs.size():
			var spec := moon_specs[i]
			var angle: float = orbit_time * float(spec["speed"]) + float(spec["phase"])
			var combined := zoom_factor * event_scale
			var offset := Vector2(
				cos(angle) * float(spec["orbit_x"]) * combined * event_stretch.x,
				sin(angle) * float(spec["orbit_y"]) * combined * event_stretch.y
			)
			moon.scale = Vector2.ONE * combined
			moon.position = center + offset - moon.size * 0.5
			moon.visible = true
		else:
			moon.visible = false

func _apply_entry(entry: Dictionary) -> void:
	if climate_tween != null and climate_tween.is_valid():
		climate_tween.kill()
	current_entry = entry.duplicate(true)
	moon_specs.clear()
	climate_visual = float(current_entry.get("climate_shift", 0.0))
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
		material.set_shader_parameter("blackhole_dissolve", 0.0)
	else:
		planet_shadow.visible = true
		material.shader = WORLD_SHADER
		material.set_shader_parameter("seed", entry["seed"])
		material.set_shader_parameter("pixel_resolution", entry["pixel_resolution"])
		material.set_shader_parameter("planet_radius", entry["radius"])
		material.set_shader_parameter("body_type", entry["body_type"])
		material.set_shader_parameter("local_light_dir", entry["light_dir"])
		material.set_shader_parameter("lighting_strength", 0.86)
		material.set_shader_parameter("blackhole_dissolve", 0.0)
		material.set_shader_parameter("climate_shift", climate_visual)
		_apply_impact_to_material(entry)
		_configure_moons(entry)

	auto_rotation_speed = float(entry["rotation_speed"])
	title_label.text = str(entry["title"])
	subtitle_label.text = str(entry["subtitle"]).to_upper()
	info_label.text = _format_info_line(entry)
	meteor_button.text = "METEOR"
	meteor_button.disabled = entry.get("kind", "world") != "world" or meteor_active
	freeze_button.disabled = entry.get("kind", "world") != "world"
	heat_button.disabled = entry.get("kind", "world") != "world"
	_apply_celestial_transform()
	_update_rotation_uniforms()
	_update_buttons()

func _configure_moons(entry: Dictionary) -> void:
	moon_specs = entry.get("moons", [])
	var moon_nodes := [moon_a, moon_b]
	for i in range(moon_nodes.size()):
		var moon: ColorRect = moon_nodes[i]
		if i < moon_specs.size():
			var spec := moon_specs[i]
			moon.size = Vector2.ONE * float(spec["size"])
			moon.pivot_offset = moon.size * 0.5
			var mat := moon.material as ShaderMaterial
			mat.shader = WORLD_SHADER
			mat.set_shader_parameter("seed", spec["seed"])
			mat.set_shader_parameter("pixel_resolution", 96.0)
			mat.set_shader_parameter("planet_radius", 0.78)
			mat.set_shader_parameter("body_type", spec["body_type"])
			mat.set_shader_parameter("local_light_dir", entry["light_dir"])
			mat.set_shader_parameter("lighting_strength", 0.80)
			mat.set_shader_parameter("climate_shift", 0.0)
			mat.set_shader_parameter("impact_enabled", false)
			mat.set_shader_parameter("blackhole_dissolve", 0.0)
			moon.visible = true
		else:
			moon.visible = false

func _format_info_line(entry: Dictionary) -> String:
	if entry.is_empty():
		return ""
	if entry.get("kind", "world") == "star":
		return "TEMP %d K  STELLAR PLASMA" % _base_temperature(entry)

	var base_temp := _base_temperature(entry)
	var body_type := int(entry.get("body_type", 0))
	var temp_scale := 150.0
	if body_type == 3:
		temp_scale = 110.0
	elif body_type == 4:
		temp_scale = 320.0
	var displayed_temp := base_temp + int(round(climate_visual * temp_scale))
	var base_water := int(entry.get("water", 0))
	var displayed_water = clamp(base_water - int(max(climate_visual, 0.0) * 28.0), 0, 100)
	var base_hab := int(entry.get("habitability", 0))
	var displayed_hab = clamp(base_hab - int(abs(climate_visual) * 52.0), 0, 100)
	var moon_count := (entry.get("moons", []) as Array).size()
	var line := "TEMP %d C  WATER %d  HAB %d  MOONS %d" % [displayed_temp, displayed_water, displayed_hab, moon_count]
	if entry.get("impact_enabled", false):
		line += "  CRATER 1"
	return line

func _base_temperature(entry: Dictionary) -> int:
	if entry.has("base_temperature"):
		return int(entry["base_temperature"])
	var temperature_text := str(entry.get("temperature_text", "0"))
	var cleaned := temperature_text.replace("°", "").replace("C", "").replace("K", "").strip_edges()
	return int(cleaned)

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
			"core_color": palette[0],
			"mid_color": palette[1],
			"edge_color": palette[2],
			"glow_color": palette[3],
			"radius": rng.randf_range(0.72, 0.82),
			"pixel_resolution": 128.0,
			"rotation_speed": rng.randf_range(0.05, 0.10),
			"base_temperature": star_temp,
			"temperature_text": "%d K" % star_temp,
			"water": -1,
			"habitability": 0,
			"light_dir": light_dir
		}

	var world_index := _weighted_world_type()
	var moon_count := rng.randi_range(1, 2) if world_index == 3 else rng.randi_range(0, 2)
	var atmosphere := "UNKNOWN"
	var temp_value := 0
	var water := 0
	var habitability := 0

	match world_index:
		0:
			atmosphere = ["BREATHABLE NITROGEN OXYGEN", "TEMPERATE CLOUD LAYER", "OCEANIC AIR MASS"][rng.randi_range(0, 2)]
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
			atmosphere = ["HYDROGEN HELIUM ENVELOPE", "BAND STORM SYSTEM", "DEEP AMMONIA CLOUDS"][rng.randi_range(0, 2)]
			temp_value = rng.randi_range(-140, 90)
			water = rng.randi_range(0, 5)
			habitability = 0
		4:
			atmosphere = ["VOLCANIC ASH PLUME", "SULFURIC FUMES", "SUPERHEATED MINERAL VAPOR"][rng.randi_range(0, 2)]
			temp_value = rng.randi_range(280, 980)
			water = 0
			habitability = rng.randi_range(0, 4)

	var moons: Array[Dictionary] = []
	for i in range(moon_count):
		var moon_type := 5
		if world_index == 3 and rng.randf() < 0.35:
			moon_type = 2
		moons.append({
			"seed": float(seed_value + 91 + i * 17),
			"size": 38.0 + float(i) * 10.0 + rng.randf_range(-4.0, 8.0),
			"orbit_x": 215.0 + float(i) * 48.0 + rng.randf_range(-8.0, 18.0),
			"orbit_y": 118.0 + float(i) * 28.0 + rng.randf_range(-6.0, 14.0),
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
		"radius": rng.randf_range(0.73, 0.82),
		"pixel_resolution": 128.0,
		"rotation_speed": rng.randf_range(0.07, 0.12),
		"atmosphere": atmosphere,
		"base_temperature": temp_value,
		"temperature_text": "%d C" % temp_value,
		"water": water,
		"habitability": habitability,
		"impact_enabled": false,
		"impact_center": Vector3(0.0, 0.0, 1.0),
		"impact_radius": 0.13,
		"climate_shift": 0.0,
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
	if meteor_active or meteor_target_mode or blackhole_active:
		return
	prev_button.disabled = current_index <= 0
	next_button.disabled = current_index >= discoveries.size() - 1
	generate_button.disabled = false
	save_button.disabled = false
	catalog_button.disabled = false
	black_hole_button.disabled = current_entry.is_empty()
	zoom_out_button.disabled = zoom_factor <= 0.665
	zoom_in_button.disabled = zoom_factor >= 1.455
	var is_world = current_entry.get("kind", "world") == "world"
	meteor_button.disabled = not is_world
	freeze_button.disabled = not is_world
	heat_button.disabled = not is_world

func _pointer_over_controls(global_position: Vector2) -> bool:
	if $UI/ActionControls.get_global_rect().has_point(global_position):
		return true
	if $UI/NavControls.get_global_rect().has_point(global_position):
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
