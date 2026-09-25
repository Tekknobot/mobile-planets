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
@onready var save_button: Button = $UI/NavControls/Save
@onready var catalog_button: Button = $UI/NavControls/Catalog
@onready var catalog_panel: PanelContainer = $UI/CatalogPanel
@onready var catalog_list: ItemList = $UI/CatalogPanel/Margin/VBox/CatalogList
@onready var catalog_close_button: Button = $UI/CatalogPanel/Margin/VBox/CloseCatalog
@onready var meteor: Control = $MeteorLayer/Meteor
@onready var impact_burst: Node2D = $MeteorLayer/ImpactBurst
@onready var black_hole_effect: Node2D = $MeteorLayer/BlackHoleEffect
@onready var tools_button: Button = $UI/NavControls/Tools
@onready var tools_panel: PanelContainer = $UI/ToolsPanel
@onready var water_add_button: Button = $UI/ToolsPanel/Margin/VBox/Grid/WaterAdd
@onready var water_remove_button: Button = $UI/ToolsPanel/Margin/VBox/Grid/WaterRemove
@onready var atmos_add_button: Button = $UI/ToolsPanel/Margin/VBox/Grid/AtmosAdd
@onready var atmos_remove_button: Button = $UI/ToolsPanel/Margin/VBox/Grid/AtmosRemove
@onready var seed_life_button: Button = $UI/ToolsPanel/Margin/VBox/Grid/SeedLife
@onready var evolve_button: Button = $UI/ToolsPanel/Margin/VBox/Grid/Evolve
@onready var storm_button: Button = $UI/ToolsPanel/Margin/VBox/Grid/Storm
@onready var time_button: Button = $UI/ToolsPanel/Margin/VBox/Grid/TimeAdvance
@onready var flare_button: Button = $UI/ToolsPanel/Margin/VBox/Grid/Flare
@onready var tools_close_button: Button = $UI/ToolsPanel/Margin/VBox/CloseTools
@onready var radial_menu: Node2D = $UI/RadialMenu
@onready var war_overlay: Node2D = $MeteorLayer/WarOverlay

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
var state_tween: Tween = null
var flare_tween: Tween = null
var blackhole_active := false
var storm_target_mode := false
var war_target_mode := false
var war_strike_active := false
var war_launch_index := -1
var ai_response_pending := false
var ai_response_faction := -1

var hold_pending := false
var hold_elapsed := 0.0
var hold_origin := Vector2.ZERO
var hold_pointer_id := -999
var radial_active := false
const RADIAL_HOLD_TIME := 0.38
const RADIAL_MOVE_THRESHOLD := 13.0

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
	tools_button.pressed.connect(_toggle_tools_panel)
	water_add_button.pressed.connect(_adjust_water.bind(0.12))
	water_remove_button.pressed.connect(_adjust_water.bind(-0.12))
	atmos_add_button.pressed.connect(_adjust_atmosphere.bind(0.12))
	atmos_remove_button.pressed.connect(_adjust_atmosphere.bind(-0.12))
	seed_life_button.pressed.connect(_seed_life)
	evolve_button.pressed.connect(_evolve_world)
	storm_button.pressed.connect(_trigger_storm)
	time_button.pressed.connect(_advance_time)
	flare_button.pressed.connect(_trigger_flare)
	tools_close_button.pressed.connect(_toggle_tools_panel)
	save_button.pressed.connect(_save_current_to_favorites)
	catalog_button.pressed.connect(_toggle_catalog)
	catalog_close_button.pressed.connect(_toggle_catalog)
	catalog_list.item_selected.connect(_on_catalog_item_selected)
	if war_overlay.has_signal("strike_completed"):
		war_overlay.connect("strike_completed", Callable(self, "_on_war_strike_completed"))
	if radial_menu.has_method("set_menu_font"):
		radial_menu.call("set_menu_font", $UI.theme.default_font)
	hint_label.text = "DRAG TO ROTATE  HOLD FOR WAR"
	catalog_panel.visible = false
	tools_panel.visible = false
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
	if radial_menu != null and radial_menu.has_method("set_menu_font"):
		radial_menu.call("set_menu_font", loaded_font)

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

	if hold_pending and not radial_active:
		hold_elapsed += delta
		if hold_elapsed >= RADIAL_HOLD_TIME:
			_open_radial_menu(hold_origin)

	if blackhole_active:
		planet_rotation.x += auto_rotation_speed * 4.0 * delta
	elif not dragging and not meteor_target_mode and not storm_target_mode and not war_target_mode and not radial_active and not hold_pending:
		if rotation_velocity.length() > 0.001:
			planet_rotation += rotation_velocity * delta
			rotation_velocity = rotation_velocity.move_toward(Vector2.ZERO, 1.65 * delta)
		else:
			planet_rotation.x += auto_rotation_speed * delta

	planet_rotation.y = clamp(planet_rotation.y, -1.35, 1.35)
	_apply_celestial_transform()
	_update_rotation_uniforms()
	_update_moons()
	_update_war_overlay()

func _input(event: InputEvent) -> void:
	if blackhole_active or war_strike_active:
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if radial_active or hold_pending:
			_cancel_radial_hold()
			return
		if war_target_mode:
			_cancel_war_target(true)
			return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_change_zoom(0.10)
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_change_zoom(-0.10)
			return

	if war_target_mode:
		if event is InputEventScreenTouch and event.pressed:
			_attempt_war_target(event.position)
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_attempt_war_target(event.position)
			return
		return

	if storm_target_mode:
		if event is InputEventScreenTouch and event.pressed:
			if not _pointer_over_controls(event.position):
				_attempt_storm_target(event.position)
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if not _pointer_over_controls(event.position):
				_attempt_storm_target(event.position)
			return
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

	# Touch: a stationary hold opens the radial menu; moving first converts the
	# gesture into the existing planet rotation interaction.
	if event is InputEventScreenTouch:
		if event.pressed:
			if _pointer_over_controls(event.position):
				return
			if _is_point_on_planet(event.position):
				_begin_radial_hold(event.position, event.index)
		elif event.index == hold_pointer_id:
			if radial_active:
				_finish_radial_action(event.position)
			elif hold_pending:
				_cancel_radial_hold()
			elif dragging:
				dragging = false
				active_touch = -1
				hint_label.text = "DRAG TO ROTATE  HOLD FOR WAR"
		return

	if event is InputEventScreenDrag and event.index == hold_pointer_id:
		if radial_active:
			radial_menu.call("update_pointer", event.position)
			return
		if hold_pending:
			if event.position.distance_to(hold_origin) > RADIAL_MOVE_THRESHOLD:
				hold_pending = false
				dragging = true
				active_touch = event.index
				rotation_velocity = Vector2.ZERO
				hint_label.text = "ROTATING"
				_apply_drag(event.relative)
			return
		if dragging:
			_apply_drag(event.relative)
		return

	# Mouse version of the same hold-versus-drag gesture.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _pointer_over_controls(event.position):
				return
			if _is_point_on_planet(event.position):
				_begin_radial_hold(event.position, -1)
		else:
			if radial_active:
				_finish_radial_action(event.position)
			elif hold_pending:
				_cancel_radial_hold()
			elif dragging:
				dragging = false
				hint_label.text = "DRAG TO ROTATE  HOLD FOR WAR"
		return

	if event is InputEventMouseMotion:
		if radial_active:
			radial_menu.call("update_pointer", event.position)
			return
		if hold_pending and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if event.position.distance_to(hold_origin) > RADIAL_MOVE_THRESHOLD:
				hold_pending = false
				dragging = true
				last_mouse_pos = event.position
				rotation_velocity = Vector2.ZERO
				hint_label.text = "ROTATING"
				_apply_drag(event.relative)
			return
		if dragging and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_apply_drag(event.relative)

func _begin_radial_hold(position: Vector2, pointer_id: int) -> void:
	if current_entry.is_empty() or meteor_active or blackhole_active or war_strike_active:
		return
	hold_pending = true
	hold_elapsed = 0.0
	hold_origin = position
	hold_pointer_id = pointer_id
	dragging = false
	active_touch = pointer_id
	rotation_velocity = Vector2.ZERO
	hint_label.text = "HOLD FOR WAR"

func _cancel_radial_hold() -> void:
	hold_pending = false
	hold_elapsed = 0.0
	radial_active = false
	hold_pointer_id = -999
	active_touch = -1
	if radial_menu.has_method("hide_menu"):
		radial_menu.call("hide_menu")
	if not war_target_mode and not meteor_target_mode and not storm_target_mode:
		hint_label.text = "DRAG TO ROTATE  HOLD FOR WAR"

func _open_radial_menu(position: Vector2) -> void:
	if not hold_pending or current_entry.is_empty():
		return
	hold_pending = false
	radial_active = true
	dragging = false
	rotation_velocity = Vector2.ZERO
	var viewport_size := get_viewport_rect().size
	var center := Vector2(clamp(position.x, 150.0, viewport_size.x - 150.0), clamp(position.y, 150.0, viewport_size.y - 150.0))
	if radial_menu.has_method("open_menu"):
		radial_menu.call("open_menu", center, _radial_actions())
	hint_label.text = "DRAG TO ACTION  RELEASE TO SELECT"

func _finish_radial_action(position: Vector2) -> void:
	if not radial_active:
		return
	var action := ""
	if radial_menu.has_method("finish"):
		action = str(radial_menu.call("finish", position))
	radial_active = false
	hold_pointer_id = -999
	active_touch = -1
	if action.is_empty():
		hint_label.text = "DRAG TO ROTATE  HOLD FOR WAR"
		return
	_execute_radial_action(action)

func _radial_actions() -> Array[Dictionary]:
	if current_entry.get("kind", "world") == "star":
		return [
			{"id":"flare", "label":"FLARE", "enabled":true},
			{"id":"blackhole", "label":"BLACK HOLE", "enabled":true}
		]
	return [
		{"id":"war", "label":"WAR", "enabled":true},
		{"id":"meteor", "label":"METEOR", "enabled":true},
		{"id":"storm", "label":"STORM", "enabled":true},
		{"id":"blackhole", "label":"BLACK HOLE", "enabled":true}
	]

func _execute_radial_action(action: String) -> void:
	match action:
		"freeze": _freeze_current()
		"heat": _heat_current()
		"water": _adjust_water(0.12)
		"atmos": _adjust_atmosphere(0.12)
		"life":
			if float(current_entry.get("life_level", 0.0)) < 0.05:
				_seed_life()
			else:
				_evolve_world()
		"time": _advance_time()
		"storm": _trigger_storm()
		"meteor": _trigger_meteor()
		"war": _trigger_war()
		"flare": _trigger_flare()
		"blackhole": _trigger_blackhole()

func _is_point_on_planet(screen_position: Vector2) -> bool:
	if current_entry.is_empty():
		return false
	var local_position: Vector2 = planet.get_global_transform().affine_inverse() * screen_position
	var center := planet.size * 0.5
	var visual_radius: float = planet.size.x * 0.5 * float(current_entry.get("radius", 0.78))
	return visual_radius > 0.0 and local_position.distance_to(center) <= visual_radius * 1.02

func _trigger_war() -> void:
	if not _is_current_world() or blackhole_active or meteor_active:
		return
	_ensure_war_state(current_entry)
	var cities: Array = current_entry.get("cities", [])
	if cities.size() < 2:
		hint_label.text = "NO VALID WAR NODES"
		return
	var player_alive := 0
	var enemy_alive := 0
	for city_value in cities:
		var city: Dictionary = city_value
		if float(city.get("damage", 0.0)) >= 0.98:
			continue
		if int(city.get("faction", -1)) == 0:
			player_alive += 1
		else:
			enemy_alive += 1
	if player_alive <= 0:
		hint_label.text = "YOUR FACTION HAS FALLEN"
		return
	if enemy_alive <= 0:
		hint_label.text = "PLANET PACIFIED"
		return
	war_target_mode = true
	war_launch_index = -1
	dragging = false
	active_touch = -1
	rotation_velocity = Vector2.ZERO
	_set_event_controls_disabled(true, true)
	if war_overlay.has_method("set_war_mode"):
		war_overlay.call("set_war_mode", true, -1)
	var faction_list: Array = current_entry.get("factions", [])
	var faction_count := faction_list.size()
	hint_label.text = "SELECT YOUR LAUNCH NODE  ENEMIES %d  TENSION %d" % [max(1, faction_count - 1), int(current_entry.get("tension", 0))]

func _cancel_war_target(show_hint: bool) -> void:
	if not war_target_mode:
		return
	war_target_mode = false
	war_launch_index = -1
	if war_overlay.has_method("set_war_mode"):
		war_overlay.call("set_war_mode", false, -1)
	_set_event_controls_disabled(false, false)
	_update_buttons()
	if show_hint:
		hint_label.text = "WAR TARGETING CANCELED"

func _attempt_war_target(screen_position: Vector2) -> void:
	if not _is_point_on_planet(screen_position):
		_cancel_war_target(true)
		return
	if not war_overlay.has_method("pick_city"):
		return
	var city_index := int(war_overlay.call("pick_city", screen_position))
	if city_index < 0:
		hint_label.text = "SELECT A CIVILIZATION NODE"
		return
	var cities: Array = current_entry.get("cities", [])
	if city_index >= cities.size():
		return
	if war_launch_index < 0:
		var candidate_source: Dictionary = cities[city_index]
		if int(candidate_source.get("faction", -1)) != 0:
			hint_label.text = "SELECT YOUR FACTION NODE"
			return
		war_launch_index = city_index
		if war_overlay.has_method("set_war_mode"):
			war_overlay.call("set_war_mode", true, war_launch_index)
		var faction_name := _faction_name(0)
		hint_label.text = "SELECT ENEMY TARGET  %s" % faction_name
		return

	if city_index == war_launch_index:
		hint_label.text = "SELECT A DIFFERENT TARGET"
		return
	var source_city: Dictionary = cities[war_launch_index]
	var target_city: Dictionary = cities[city_index]
	if int(target_city.get("faction", 0)) == 0:
		hint_label.text = "SELECT AN ENEMY FACTION"
		return

	var tension := int(current_entry.get("tension", 0))
	var nuclear := tension >= 80
	if war_overlay.has_method("launch_missile"):
		war_overlay.call("launch_missile", war_launch_index, city_index, nuclear, false)
	current_entry["tension"] = clamp(tension + (12 if nuclear else 8), 0, 100)
	current_entry["war_history"] = int(current_entry.get("war_history", 0)) + 1
	_commit_current_entry()
	info_label.text = _format_info_line(current_entry)
	war_target_mode = false
	war_strike_active = true
	war_launch_index = -1
	if war_overlay.has_method("set_war_mode"):
		war_overlay.call("set_war_mode", false, -1)
	_set_event_controls_disabled(true, true)
	hint_label.text = "NUCLEAR LAUNCH DETECTED" if nuclear else "MISSILE LAUNCH DETECTED"

func _faction_name(index: int) -> String:
	var factions: Array = current_entry.get("factions", [])
	if index >= 0 and index < factions.size():
		var faction: Dictionary = factions[index]
		return str(faction.get("name", "FACTION"))
	return "FACTION"

func _on_war_strike_completed(target_index: int, nuclear: bool, impact_position: Vector2, attacker_faction: int, ai_controlled: bool) -> void:
	if not _is_current_world():
		return
	var cities: Array = current_entry.get("cities", [])
	if target_index < 0 or target_index >= cities.size():
		return
	var city: Dictionary = cities[target_index]
	var defending_faction := int(city.get("faction", -1))
	var damage_add := 0.48 if nuclear else 0.22
	city["damage"] = clamp(float(city.get("damage", 0.0)) + damage_add, 0.0, 1.0)
	city["population"] = max(0.0, float(city.get("population", 0.6)) * (0.54 if nuclear else 0.82))
	city["defense"] = max(0.0, float(city.get("defense", 0.5)) * (0.42 if nuclear else 0.74))
	cities[target_index] = city
	current_entry["cities"] = cities
	current_entry["stability"] = clamp(float(current_entry.get("stability", 1.0)) - (0.12 if nuclear else 0.04), 0.0, 1.0)
	current_entry["civilization_level"] = clamp(float(current_entry.get("civilization_level", 0.0)) * (0.91 if nuclear else 0.985), 0.22, 1.0)
	current_entry["tension"] = clamp(int(current_entry.get("tension", 0)) + (9 if nuclear else 5), 0, 100)
	if nuclear:
		current_entry["climate_shift"] = clamp(float(current_entry.get("climate_shift", 0.0)) - 0.055, -1.0, 1.0)
		climate_visual = float(current_entry["climate_shift"])
		current_entry["impact_enabled"] = true
		current_entry["impact_center"] = city.get("surface", Vector3(0.0, 0.0, 1.0))
		current_entry["impact_radius"] = 0.09
	_recalculate_world_state()
	_apply_survival_constraints()
	_recalculate_world_state()
	_apply_world_state_to_material(current_entry)
	_apply_impact_to_material(current_entry)
	_commit_current_entry()
	if impact_position.x > -500.0 and impact_burst.has_method("burst"):
		impact_burst.call("burst", impact_position)
	info_label.text = _format_info_line(current_entry)

	if not ai_controlled and defending_faction > 0:
		hint_label.text = "ENEMY RESPONSE COMPUTING"
		_schedule_enemy_retaliation(defending_faction)
		return

	ai_response_pending = false
	war_strike_active = false
	_set_event_controls_disabled(false, false)
	_update_buttons()
	if ai_controlled:
		hint_label.text = "ENEMY NUCLEAR IMPACT" if nuclear else "ENEMY IMPACT"
	else:
		hint_label.text = "NUCLEAR IMPACT" if nuclear else "MISSILE IMPACT"

func _schedule_enemy_retaliation(defender_faction: int) -> void:
	ai_response_pending = true
	ai_response_faction = defender_faction
	war_strike_active = true
	_set_event_controls_disabled(true, true)
	var response_delay := rng.randf_range(0.72, 1.25)
	var response_tween := create_tween()
	response_tween.tween_interval(response_delay)
	response_tween.tween_callback(_launch_enemy_retaliation.bind(defender_faction))

func _launch_enemy_retaliation(defender_faction: int) -> void:
	if not _is_current_world() or blackhole_active:
		ai_response_pending = false
		war_strike_active = false
		_set_event_controls_disabled(false, false)
		_update_buttons()
		return
	var cities: Array = current_entry.get("cities", [])
	var enemy_sources: Array[int] = []
	var player_targets: Array[int] = []
	for i in range(cities.size()):
		var city: Dictionary = cities[i]
		if float(city.get("damage", 0.0)) >= 0.98:
			continue
		var faction := int(city.get("faction", -1))
		if faction == defender_faction:
			enemy_sources.append(i)
		elif faction == 0:
			player_targets.append(i)

	# If the struck faction was completely destroyed, another hostile faction answers.
	if enemy_sources.is_empty():
		for i in range(cities.size()):
			var city: Dictionary = cities[i]
			if int(city.get("faction", -1)) > 0 and float(city.get("damage", 0.0)) < 0.98:
				enemy_sources.append(i)
	if enemy_sources.is_empty() or player_targets.is_empty():
		ai_response_pending = false
		war_strike_active = false
		_set_event_controls_disabled(false, false)
		_update_buttons()
		hint_label.text = "NO RETALIATION CAPABLE"
		return

	var source_index := enemy_sources[0]
	var source_score := -999.0
	for index in enemy_sources:
		var source_city: Dictionary = cities[index]
		var score := float(source_city.get("military", 0.5)) * 1.35 + float(source_city.get("defense", 0.5)) * 0.35 - float(source_city.get("damage", 0.0)) * 1.15
		if score > source_score:
			source_score = score
			source_index = index

	var target_index := player_targets[0]
	var target_score := -999.0
	for index in player_targets:
		var target_city: Dictionary = cities[index]
		var score := float(target_city.get("population", 0.5)) * 1.15 + float(target_city.get("military", 0.5)) * 0.45 - float(target_city.get("damage", 0.0)) * 0.25
		if score > target_score:
			target_score = score
			target_index = index

	var tension := int(current_entry.get("tension", 0))
	var nuclear := tension >= 88 or (tension >= 72 and rng.randf() < 0.48)
	if war_overlay.has_method("launch_missile"):
		war_overlay.call("launch_missile", source_index, target_index, nuclear, true)
	current_entry["tension"] = clamp(tension + (12 if nuclear else 7), 0, 100)
	current_entry["war_history"] = int(current_entry.get("war_history", 0)) + 1
	_commit_current_entry()
	info_label.text = _format_info_line(current_entry)
	hint_label.text = "ENEMY NUCLEAR RETALIATION" if nuclear else "ENEMY RETALIATION"

func _update_war_overlay() -> void:
	if war_overlay == null or not war_overlay.has_method("set_context"):
		return
	if current_entry.is_empty() or current_entry.get("kind", "world") != "world":
		war_overlay.call("set_context", planet, planet_rotation, float(current_entry.get("radius", 0.78)) if not current_entry.is_empty() else 0.78, [], [], false)
		return
	_ensure_war_state(current_entry)
	var civ := float(current_entry.get("civilization_level", 0.0))
	war_overlay.call("set_context", planet, planet_rotation, float(current_entry.get("radius", 0.78)), current_entry.get("cities", []), current_entry.get("factions", []), civ >= 0.15 and not blackhole_active)

func _ensure_war_state(entry: Dictionary) -> void:
	if entry.get("kind", "world") != "world":
		return
	if not entry.has("tension"):
		entry["tension"] = 38
	if not entry.has("war_history"):
		entry["war_history"] = 0
	if not entry.has("player_faction"):
		entry["player_faction"] = 0

	var existing_cities: Array = entry.get("cities", [])
	var existing_factions: Array = entry.get("factions", [])
	if existing_factions.size() >= 2 and existing_cities.size() >= 4:
		for i in range(existing_factions.size()):
			var faction: Dictionary = existing_factions[i]
			faction["role"] = "player" if i == 0 else "enemy"
			existing_factions[i] = faction
		entry["factions"] = existing_factions
		if int(entry.get("tension", 0)) <= 0:
			entry["tension"] = 38
		return

	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = int(float(entry.get("seed", 1.0))) + 7319
	var faction_count := 2 + local_rng.randi_range(0, 1)
	var faction_prefixes := ["ORION", "VESTA", "KALDAN", "MERIDIAN", "HELIOS", "AEGIS", "NOVA", "SABLE", "THARSIS", "CYGNUS"]
	var faction_suffixes := ["UNION", "REPUBLIC", "PACT", "LEAGUE", "STATE", "ACCORD", "DIRECTORATE", "COMMONWEALTH", "HIVE", "DOMINION"]
	var palette := [Color(0.34, 0.82, 0.96, 1.0), Color(1.0, 0.46, 0.22, 1.0), Color(0.78, 0.46, 0.96, 1.0)]
	var factions: Array[Dictionary] = []
	for i in range(faction_count):
		var prefix = faction_prefixes[(local_rng.randi_range(0, faction_prefixes.size() - 1) + i) % faction_prefixes.size()]
		var suffix = faction_suffixes[(local_rng.randi_range(0, faction_suffixes.size() - 1) + i * 2) % faction_suffixes.size()]
		factions.append({
			"id": i,
			"name": "%s %s" % [prefix, suffix],
			"color": palette[i % palette.size()],
			"role": "player" if i == 0 else "enemy"
		})

	var city_roots := ["NOVA", "HAVEN", "CROWN", "DELTA", "ZENITH", "ORBIT", "ARC", "EMBER", "VECTOR", "AURORA", "CITADEL", "MERIDIAN", "SPIRE", "NEXUS"]
	var city_count := local_rng.randi_range(7, 10)
	var cities: Array[Dictionary] = []
	for i in range(city_count):
		var latitude := deg_to_rad(local_rng.randf_range(-58.0, 58.0))
		var longitude := local_rng.randf_range(-PI, PI)
		var surface := Vector3(cos(latitude) * sin(longitude), sin(latitude), cos(latitude) * cos(longitude)).normalized()
		var faction_index := i % faction_count
		cities.append({
			"name":"%s %02d" % [city_roots[(i + local_rng.randi_range(0, city_roots.size() - 1)) % city_roots.size()], i + 1],
			"faction":faction_index,
			"surface":surface,
			"population":local_rng.randf_range(0.48, 1.0),
			"military":local_rng.randf_range(0.38, 0.96),
			"defense":local_rng.randf_range(0.24, 0.82),
			"damage":0.0
		})
	entry["factions"] = factions
	entry["cities"] = cities
	entry["player_faction"] = 0
	entry["tension"] = local_rng.randi_range(34, 62)

func _apply_drag(relative: Vector2) -> void:
	var delta_rotation := relative * 0.0105
	planet_rotation.x += delta_rotation.x
	planet_rotation.y += delta_rotation.y
	planet_rotation.y = clamp(planet_rotation.y, -1.35, 1.35)
	rotation_velocity = delta_rotation * 11.0
	_update_rotation_uniforms()

func _generate_new() -> void:
	_cancel_radial_hold()
	_cancel_war_target(false)
	_cancel_meteor_target(false)
	tools_panel.visible = false
	if current_index < discoveries.size() - 1:
		discoveries = discoveries.slice(0, current_index + 1)
	var entry := _build_random_entry()
	discoveries.append(entry)
	current_index = discoveries.size() - 1
	_apply_entry(entry)

func _show_previous() -> void:
	_cancel_radial_hold()
	_cancel_war_target(false)
	_cancel_meteor_target(false)
	tools_panel.visible = false
	if current_index > 0:
		current_index -= 1
		_apply_entry(discoveries[current_index])

func _show_next() -> void:
	_cancel_radial_hold()
	_cancel_war_target(false)
	_cancel_meteor_target(false)
	tools_panel.visible = false
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
	if meteor_active or meteor_target_mode or storm_target_mode or blackhole_active:
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
	current_entry["climate_shift"] = value
	_recalculate_world_state()
	var material := planet.material as ShaderMaterial
	if material and current_entry.get("kind", "world") == "world":
		material.set_shader_parameter("climate_shift", climate_visual)
		_apply_world_state_to_material(current_entry)
	info_label.text = _format_info_line(current_entry)

func _finish_climate(value: float) -> void:
	climate_visual = value
	current_entry["climate_shift"] = value
	_recalculate_world_state()
	_apply_survival_constraints()
	_recalculate_world_state()
	_commit_current_entry()
	_apply_world_state_to_material(current_entry)
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

	tools_panel.visible = false
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
		current_entry["stability"] = clamp(float(current_entry.get("stability", 1.0)) - 0.12, 0.0, 1.0)
		current_entry["life_level"] = float(current_entry.get("life_level", 0.0)) * 0.88
		current_entry["civilization_level"] = float(current_entry.get("civilization_level", 0.0)) * 0.78
		_recalculate_world_state()
		_apply_impact_to_material(current_entry)
		_apply_world_state_to_material(current_entry)
		_commit_current_entry()
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
	tools_button.disabled = disabled
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
	if blackhole_active or meteor_active or meteor_target_mode or storm_target_mode:
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
	if blackhole_active or meteor_active or storm_target_mode or current_entry.is_empty():
		return
	_cancel_meteor_target(false)
	tools_panel.visible = false
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
	if meteor_target_mode or storm_target_mode or war_target_mode or war_strike_active or meteor_active or blackhole_active:
		return
	catalog_panel.visible = not catalog_panel.visible
	if catalog_panel.visible:
		tools_panel.visible = false
		_update_catalog_list()
		hint_label.text = "CATALOG OPEN"
	else:
		hint_label.text = "DRAG TO ROTATE"

func _toggle_tools_panel() -> void:
	if meteor_target_mode or storm_target_mode or meteor_active or blackhole_active or current_entry.is_empty():
		return
	tools_panel.visible = not tools_panel.visible
	if tools_panel.visible:
		catalog_panel.visible = false
		_update_tools_buttons()
		hint_label.text = "INTERVENTION TOOLS"
	else:
		hint_label.text = "DRAG TO ROTATE"

func _adjust_water(amount: float) -> void:
	if not _is_current_world():
		hint_label.text = "WATER CONTROL UNAVAILABLE"
		return
	var body_type := int(current_entry.get("body_type", 0))
	if body_type == 3 or body_type == 4:
		hint_label.text = "NO STABLE SURFACE WATER"
		return
	var target = clamp(float(current_entry.get("water_level", 0.0)) + amount, 0.0, 1.0)
	_animate_world_state("water_level", target, "ADDING WATER" if amount > 0.0 else "DRYING WORLD", "HYDROLOGY STABILIZED", 1.25)

func _adjust_atmosphere(amount: float) -> void:
	if not _is_current_world():
		hint_label.text = "ATMOSPHERE CONTROL UNAVAILABLE"
		return
	var target = clamp(float(current_entry.get("atmosphere_level", 0.0)) + amount, 0.0, 1.0)
	_animate_world_state("atmosphere_level", target, "BUILDING ATMOSPHERE" if amount > 0.0 else "STRIPPING ATMOSPHERE", "ATMOSPHERE STABILIZED", 1.25)

func _seed_life() -> void:
	if not _is_current_world():
		hint_label.text = "LIFE CONTROL UNAVAILABLE"
		return
	var body_type := int(current_entry.get("body_type", 0))
	if body_type > 2:
		hint_label.text = "NO VIABLE SURFACE BIOSPHERE"
		return
	_recalculate_world_state()
	if int(current_entry.get("habitability", 0)) < 45 or float(current_entry.get("water_level", 0.0)) < 0.18 or float(current_entry.get("atmosphere_level", 0.0)) < 0.25:
		hint_label.text = "CONDITIONS HOSTILE TO LIFE"
		return
	var target = max(float(current_entry.get("life_level", 0.0)), 0.20)
	if target <= float(current_entry.get("life_level", 0.0)) + 0.001:
		hint_label.text = "BIOSPHERE ALREADY SEEDED"
		return
	_animate_world_state("life_level", target, "SEEDING BIOSPHERE", "MICROBIAL LIFE ESTABLISHED", 1.55)

func _evolve_world() -> void:
	if not _is_current_world():
		hint_label.text = "EVOLUTION UNAVAILABLE"
		return
	_recalculate_world_state()
	var hab := int(current_entry.get("habitability", 0))
	if hab < 48:
		hint_label.text = "CONDITIONS TOO HOSTILE"
		return
	var life := float(current_entry.get("life_level", 0.0))
	var civ := float(current_entry.get("civilization_level", 0.0))
	if life < 0.05:
		_seed_life()
	elif life < 0.72:
		_animate_world_state("life_level", min(1.0, life + 0.22), "EVOLUTION ACCELERATED", "BIOSPHERE ADVANCED", 1.35)
	elif civ < 1.0:
		_animate_world_state("civilization_level", min(1.0, civ + 0.18), "CIVILIZATION EMERGING", "CIVILIZATION EXPANDED", 1.35)
	else:
		hint_label.text = "CIVILIZATION AT PEAK"

func _advance_time() -> void:
	if not _is_current_world():
		hint_label.text = "TIME CONTROL IS PLANETARY"
		return
	current_entry["age_steps"] = int(current_entry.get("age_steps", 0)) + 1
	var climate := float(current_entry.get("climate_shift", 0.0))
	if climate > 0.55:
		current_entry["water_level"] = clamp(float(current_entry.get("water_level", 0.0)) - 0.04, 0.0, 1.0)
	elif climate < -0.70:
		current_entry["atmosphere_level"] = clamp(float(current_entry.get("atmosphere_level", 0.0)) - 0.015, 0.0, 1.0)
	_recalculate_world_state()
	var hab := int(current_entry.get("habitability", 0))
	var life := float(current_entry.get("life_level", 0.0))
	var civ := float(current_entry.get("civilization_level", 0.0))
	if hab >= 55 and life > 0.0:
		life = min(1.0, life + 0.07)
		current_entry["life_level"] = life
		if life >= 0.62:
			current_entry["civilization_level"] = min(1.0, civ + 0.05)
	elif hab < 30:
		current_entry["life_level"] = life * 0.92
		current_entry["civilization_level"] = civ * 0.84
	var storm_strength = max(0.0, float(current_entry.get("storm_strength", 0.0)) - 0.14)
	current_entry["storm_strength"] = storm_strength
	if storm_strength < 0.08:
		current_entry["storm_enabled"] = false
	current_entry["stability"] = min(1.0, float(current_entry.get("stability", 1.0)) + 0.02)
	_recalculate_world_state()
	_ensure_war_state(current_entry)
	if float(current_entry.get("civilization_level", 0.0)) >= 0.15:
		current_entry["tension"] = clamp(int(current_entry.get("tension", 32)) + rng.randi_range(-5, 8), 0, 100)
	_commit_current_entry()
	_apply_world_state_to_material(current_entry)
	info_label.text = _format_info_line(current_entry)
	_update_tools_buttons()
	hint_label.text = "TIME ADVANCED"

func _trigger_storm() -> void:
	if not _is_current_world() or meteor_active or blackhole_active:
		return
	var body_type := int(current_entry.get("body_type", 0))
	if body_type == 4:
		hint_label.text = "ATMOSPHERIC STORM UNAVAILABLE"
		return
	tools_panel.visible = false
	storm_target_mode = true
	dragging = false
	active_touch = -1
	rotation_velocity = Vector2.ZERO
	_set_event_controls_disabled(true, true)
	hint_label.text = "TAP PLANET FOR STORM"

func _attempt_storm_target(screen_position: Vector2) -> void:
	var local_position: Vector2 = planet.get_global_transform().affine_inverse() * screen_position
	var center := planet.size * 0.5
	var visual_radius: float = planet.size.x * 0.5 * float(current_entry.get("radius", 0.78))
	if visual_radius <= 0.0:
		return
	var target_p := (local_position - center) / visual_radius
	if target_p.length() > 0.97:
		hint_label.text = "TAP DIRECTLY ON PLANET"
		return
	var z := sqrt(max(0.0, 1.0 - target_p.dot(target_p)))
	var normal := Vector3(target_p.x, target_p.y, z).normalized()
	var storm_center := _rotate_y_vec3(normal, planet_rotation.x)
	storm_center = _rotate_x_vec3(storm_center, planet_rotation.y).normalized()
	current_entry["storm_enabled"] = true
	current_entry["storm_center"] = storm_center
	current_entry["storm_radius"] = rng.randf_range(0.14, 0.23)
	current_entry["storm_strength"] = 1.0
	storm_target_mode = false
	_apply_world_state_to_material(current_entry)
	_commit_current_entry()
	_set_event_controls_disabled(false, false)
	_update_buttons()
	hint_label.text = "STORM SYSTEM FORMED"

func _trigger_flare() -> void:
	if current_entry.is_empty() or current_entry.get("kind", "world") != "star" or blackhole_active:
		hint_label.text = "SOLAR FLARE REQUIRES A STAR"
		return
	tools_panel.visible = false
	var material := planet.material as ShaderMaterial
	if material == null:
		return
	if flare_tween != null and flare_tween.is_valid():
		flare_tween.kill()
	var angle := rng.randf_range(-PI, PI)
	current_entry["flare_angle"] = angle
	material.set_shader_parameter("flare_angle", angle)
	material.set_shader_parameter("flare_strength", 0.0)
	hint_label.text = "SOLAR FLARE"
	flare_tween = create_tween()
	flare_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	flare_tween.tween_method(_set_flare_strength, 0.0, 1.0, 0.55)
	flare_tween.tween_interval(0.45)
	flare_tween.tween_method(_set_flare_strength, 1.0, 0.0, 0.85)
	flare_tween.tween_callback(func() -> void: hint_label.text = "STELLAR ACTIVITY STABILIZED")

func _set_flare_strength(value: float) -> void:
	var material := planet.material as ShaderMaterial
	if material and current_entry.get("kind", "world") == "star":
		material.set_shader_parameter("flare_strength", value)

func _animate_world_state(key: String, target: float, start_message: String, end_message: String, duration: float) -> void:
	if state_tween != null and state_tween.is_valid():
		state_tween.kill()
	var start := float(current_entry.get(key, 0.0))
	if is_equal_approx(start, target):
		hint_label.text = "STATE LIMIT REACHED"
		return
	hint_label.text = start_message
	state_tween = create_tween()
	state_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	state_tween.tween_method(_set_world_state_visual.bind(key), start, target, duration)
	state_tween.tween_callback(_finish_world_state.bind(end_message))

func _set_world_state_visual(value: float, key: String) -> void:
	current_entry[key] = value
	_recalculate_world_state()
	_apply_world_state_to_material(current_entry)
	info_label.text = _format_info_line(current_entry)

func _finish_world_state(message: String) -> void:
	_recalculate_world_state()
	_apply_survival_constraints()
	_recalculate_world_state()
	_ensure_war_state(current_entry)
	_commit_current_entry()
	_apply_world_state_to_material(current_entry)
	info_label.text = _format_info_line(current_entry)
	_update_tools_buttons()
	hint_label.text = message

func _update_tools_buttons() -> void:
	var is_star = not current_entry.is_empty() and current_entry.get("kind", "world") == "star"
	var is_world = not current_entry.is_empty() and current_entry.get("kind", "world") == "world"
	var body_type := int(current_entry.get("body_type", 0)) if is_world else -1
	water_add_button.disabled = not is_world or body_type == 3 or body_type == 4 or float(current_entry.get("water_level", 0.0)) >= 0.995
	water_remove_button.disabled = not is_world or body_type == 3 or body_type == 4 or float(current_entry.get("water_level", 0.0)) <= 0.005
	atmos_add_button.disabled = not is_world or float(current_entry.get("atmosphere_level", 0.0)) >= 0.995
	atmos_remove_button.disabled = not is_world or float(current_entry.get("atmosphere_level", 0.0)) <= 0.005
	seed_life_button.disabled = not is_world or body_type > 2
	evolve_button.disabled = not is_world or body_type > 2
	storm_button.disabled = not is_world or body_type == 4
	time_button.disabled = not is_world
	flare_button.disabled = not is_star

func _is_current_world() -> bool:
	return not current_entry.is_empty() and current_entry.get("kind", "world") == "world"

func _commit_current_entry() -> void:
	if current_index >= 0 and current_index < discoveries.size():
		discoveries[current_index] = current_entry.duplicate(true)

func _ensure_entry_state(entry: Dictionary) -> void:
	if entry.get("kind", "world") == "star":
		if not entry.has("flare_angle"):
			entry["flare_angle"] = 0.0
		return
	var body_type := int(entry.get("body_type", 0))
	var migrating_to_war_world := not entry.has("native_life")
	if not entry.has("water_level"):
		entry["water_level"] = clamp(float(entry.get("water", 0)) / 100.0, 0.0, 1.0)
	if not entry.has("atmosphere_level"):
		entry["atmosphere_level"] = _initial_atmosphere_level(body_type)
	entry["native_life"] = true
	if not entry.has("life_form"):
		entry["life_form"] = _life_form_for_body(body_type)
	if not entry.has("life_level"):
		entry["life_level"] = 0.78
	elif migrating_to_war_world:
		entry["life_level"] = max(float(entry.get("life_level", 0.0)), 0.62)
	if not entry.has("civilization_level"):
		entry["civilization_level"] = 0.68
	elif migrating_to_war_world:
		entry["civilization_level"] = max(float(entry.get("civilization_level", 0.0)), 0.48)
	if not entry.has("stability"):
		entry["stability"] = 1.0
	if not entry.has("age_steps"):
		entry["age_steps"] = 0
	if not entry.has("storm_enabled"):
		entry["storm_enabled"] = false
	if not entry.has("storm_center"):
		entry["storm_center"] = Vector3(0.0, 0.0, 1.0)
	if not entry.has("storm_radius"):
		entry["storm_radius"] = 0.18
	if not entry.has("storm_strength"):
		entry["storm_strength"] = 0.0
	_recalculate_entry_state(entry)
	_ensure_war_state(entry)

func _apply_world_state_to_material(entry: Dictionary) -> void:
	if entry.is_empty() or entry.get("kind", "world") != "world":
		return
	var material := planet.material as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("water_level", float(entry.get("water_level", 0.0)))
	material.set_shader_parameter("atmosphere_level", float(entry.get("atmosphere_level", 0.0)))
	material.set_shader_parameter("life_level", float(entry.get("life_level", 0.0)))
	material.set_shader_parameter("civilization_level", float(entry.get("civilization_level", 0.0)))
	material.set_shader_parameter("storm_enabled", bool(entry.get("storm_enabled", false)))
	material.set_shader_parameter("storm_center", entry.get("storm_center", Vector3(0.0, 0.0, 1.0)))
	material.set_shader_parameter("storm_radius", float(entry.get("storm_radius", 0.18)))
	material.set_shader_parameter("storm_strength", float(entry.get("storm_strength", 0.0)))

func _recalculate_world_state() -> void:
	if not _is_current_world():
		return
	_recalculate_entry_state(current_entry)

func _apply_survival_constraints() -> void:
	if not _is_current_world():
		return
	# All generated worlds now host native alien life adapted to their local
	# environment. Climate, water and atmosphere no longer erase civilizations
	# simply because the world is hostile by human standards. War and direct
	# catastrophic damage remain the primary threats to civilization.
	var life := float(current_entry.get("life_level", 0.75))
	var civ := float(current_entry.get("civilization_level", 0.65))
	var stability := float(current_entry.get("stability", 1.0))
	if stability < 0.18:
		life *= 0.96
		civ *= 0.92
	current_entry["life_level"] = clamp(max(life, 0.34), 0.0, 1.0)
	current_entry["civilization_level"] = clamp(max(civ, 0.22), 0.0, 1.0)

func _recalculate_entry_state(entry: Dictionary) -> void:
	if entry.get("kind", "world") != "world":
		return
	entry["water"] = int(round(clamp(float(entry.get("water_level", 0.0)), 0.0, 1.0) * 100.0))
	entry["habitability"] = _calculate_habitability(entry)

func _calculate_habitability(entry: Dictionary) -> int:
	var body_type := int(entry.get("body_type", 0))
	if body_type == 3 or body_type == 4:
		return 0
	var temp := _current_temperature(entry)
	var temp_score = 1.0 - clamp(abs(float(temp) - 18.0) / 95.0, 0.0, 1.0)
	var water := float(entry.get("water_level", 0.0))
	var water_score = 1.0 - clamp(abs(water - 0.55) / 0.58, 0.0, 1.0)
	var atmosphere := float(entry.get("atmosphere_level", 0.0))
	var atmosphere_score = 1.0 - clamp(abs(atmosphere - 0.72) / 0.72, 0.0, 1.0)
	var stability := float(entry.get("stability", 1.0))
	var score = temp_score * 0.42 + water_score * 0.25 + atmosphere_score * 0.23 + stability * 0.10
	if body_type == 1:
		score *= 0.86
	elif body_type == 2:
		score *= 0.80
	if bool(entry.get("impact_enabled", false)):
		score *= 0.92
	return int(round(clamp(score, 0.0, 1.0) * 100.0))

func _current_temperature(entry: Dictionary) -> int:
	var base_temp := _base_temperature(entry)
	var body_type := int(entry.get("body_type", 0))
	var temp_scale := 150.0
	if body_type == 3:
		temp_scale = 110.0
	elif body_type == 4:
		temp_scale = 320.0
	var atmosphere := float(entry.get("atmosphere_level", 0.5))
	var greenhouse := int(round((atmosphere - 0.5) * 28.0))
	return base_temp + int(round(float(entry.get("climate_shift", 0.0)) * temp_scale)) + greenhouse

func _initial_atmosphere_level(body_type: int) -> float:
	match body_type:
		0:
			return rng.randf_range(0.62, 0.86)
		1:
			return rng.randf_range(0.18, 0.42)
		2:
			return rng.randf_range(0.28, 0.56)
		3:
			return rng.randf_range(0.86, 1.0)
		4:
			return rng.randf_range(0.12, 0.34)
		_:
			return 0.08

func _life_form_for_body(body_type: int) -> String:
	match body_type:
		0:
			return "CARBON BIOSPHERE"
		1:
			return "SILICATE COLONIES"
		2:
			return "CRYOGENIC HIVE"
		3:
			return "AERIAL FLOATERS"
		4:
			return "MAGMA BORNE NETWORK"
		_:
			return "ALIEN BIOSPHERE"

func _initial_life_level(body_type: int, habitability: int) -> float:
	if body_type == 0 and habitability >= 65 and rng.randf() < 0.18:
		return rng.randf_range(0.12, 0.38)
	if (body_type == 1 or body_type == 2) and habitability >= 14 and rng.randf() < 0.04:
		return rng.randf_range(0.06, 0.16)
	return 0.0

func _on_catalog_item_selected(index: int) -> void:
	if index >= 0 and index < favorites.size():
		var loaded_entry := favorites[index].duplicate(true)
		if current_index < discoveries.size() - 1:
			discoveries = discoveries.slice(0, current_index + 1)
		discoveries.append(loaded_entry.duplicate(true))
		current_index = discoveries.size() - 1
		_apply_entry(loaded_entry)
		catalog_panel.visible = false
		tools_panel.visible = false
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
	if state_tween != null and state_tween.is_valid():
		state_tween.kill()
	if flare_tween != null and flare_tween.is_valid():
		flare_tween.kill()
	storm_target_mode = false
	war_target_mode = false
	war_strike_active = false
	war_launch_index = -1
	ai_response_pending = false
	ai_response_faction = -1
	_cancel_radial_hold()
	current_entry = entry.duplicate(true)
	_ensure_entry_state(current_entry)
	_commit_current_entry()
	entry = current_entry
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
		material.set_shader_parameter("flare_strength", 0.0)
		material.set_shader_parameter("flare_angle", float(entry.get("flare_angle", 0.0)))
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
		_apply_world_state_to_material(entry)
		_apply_impact_to_material(entry)
		_configure_moons(entry)

	auto_rotation_speed = float(entry["rotation_speed"])
	title_label.text = str(entry["title"])
	if entry.get("kind", "world") == "world":
		subtitle_label.text = "%s  %s" % [str(entry["subtitle"]).to_upper(), str(entry.get("life_form", "ALIEN BIOSPHERE"))]
	else:
		subtitle_label.text = str(entry["subtitle"]).to_upper()
	info_label.text = _format_info_line(entry)
	meteor_button.text = "METEOR"
	meteor_button.disabled = entry.get("kind", "world") != "world" or meteor_active
	freeze_button.disabled = entry.get("kind", "world") != "world"
	heat_button.disabled = entry.get("kind", "world") != "world"
	_update_tools_buttons()
	_apply_celestial_transform()
	_update_rotation_uniforms()
	_update_buttons()
	_update_war_overlay()

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
			mat.set_shader_parameter("water_level", 0.0)
			mat.set_shader_parameter("atmosphere_level", 0.08)
			mat.set_shader_parameter("life_level", 0.0)
			mat.set_shader_parameter("civilization_level", 0.0)
			mat.set_shader_parameter("storm_enabled", false)
			moon.visible = true
		else:
			moon.visible = false

func _format_info_line(entry: Dictionary) -> String:
	if entry.is_empty():
		return ""
	if entry.get("kind", "world") == "star":
		return "TEMP %d K  STELLAR ACTIVITY" % _base_temperature(entry)

	var cities: Array = entry.get("cities", [])
	var player_nodes := 0
	var enemy_nodes := 0
	for city_value in cities:
		var city: Dictionary = city_value
		if float(city.get("damage", 0.0)) >= 0.98:
			continue
		if int(city.get("faction", -1)) == 0:
			player_nodes += 1
		else:
			enemy_nodes += 1
	var tension := int(entry.get("tension", 0))
	return "YOU %d  ENEMY %d  TENSION %d" % [player_nodes, enemy_nodes, tension]

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
			"flare_angle": rng.randf_range(-PI, PI),
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

	# Every generated world now carries a mature native biosphere and a
	# technological civilization. Gas giants, ice worlds and lava worlds use
	# alien life adapted to those environments rather than human habitability.
	var initial_life := rng.randf_range(0.72, 0.98)
	var initial_civ := rng.randf_range(0.58, 0.92)
	var life_form := _life_form_for_body(world_index)

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
		"water_level": clamp(float(water) / 100.0, 0.0, 1.0),
		"atmosphere_level": _initial_atmosphere_level(world_index),
		"native_life": true,
		"life_form": life_form,
		"life_level": initial_life,
		"civilization_level": initial_civ,
		"stability": 1.0,
		"age_steps": 0,
		"storm_enabled": false,
		"storm_center": Vector3(0.0, 0.0, 1.0),
		"storm_radius": 0.18,
		"storm_strength": 0.0,
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
	if meteor_active or meteor_target_mode or storm_target_mode or war_target_mode or war_strike_active or blackhole_active:
		return
	prev_button.disabled = current_index <= 0
	next_button.disabled = current_index >= discoveries.size() - 1
	generate_button.disabled = false
	save_button.disabled = false
	catalog_button.disabled = false
	tools_button.disabled = current_entry.is_empty()
	black_hole_button.disabled = current_entry.is_empty()
	zoom_out_button.disabled = zoom_factor <= 0.665
	zoom_in_button.disabled = zoom_factor >= 1.455
	var is_world = current_entry.get("kind", "world") == "world"
	meteor_button.disabled = not is_world
	freeze_button.disabled = not is_world
	heat_button.disabled = not is_world
	_update_tools_buttons()

func _pointer_over_controls(global_position: Vector2) -> bool:
	if $UI/NavControls.visible and $UI/NavControls.get_global_rect().has_point(global_position):
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
