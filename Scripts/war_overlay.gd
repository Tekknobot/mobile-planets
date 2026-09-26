extends Node2D

signal strike_completed(target_index: int, nuclear: bool, impact_position: Vector2, attacker_faction: int, ai_controlled: bool)
signal strike_intercepted(target_index: int, impact_position: Vector2, attacker_faction: int, ai_controlled: bool, defense_index: int)

@export var city_pixel_size: float = 6.0
@export var missile_pixel_size: float = 5.0
@export var arc_height: float = 0.24

var _planet: Control = null
var _rotation := Vector2.ZERO
var _planet_radius := 0.78
var _cities: Array = []
var _factions: Array = []
var _impacts: Array = []
var _show_nodes := false
var _war_mode := false
var _selected_source := -1
var _missiles: Array[Dictionary] = []

const DESTROYED_DAMAGE := 0.999

func _ready() -> void:
	set_process(true)

func set_context(planet_node: Control, rotation: Vector2, planet_radius: float, cities: Array, factions: Array, impacts: Array, show_nodes: bool) -> void:
	_planet = planet_node
	_rotation = rotation
	_planet_radius = planet_radius
	_cities = cities
	_factions = factions
	_impacts = impacts
	_show_nodes = show_nodes
	queue_redraw()

func set_war_mode(active: bool, source_index: int = -1) -> void:
	_war_mode = active
	_selected_source = source_index
	queue_redraw()

func pick_city(screen_position: Vector2) -> int:
	if _planet == null:
		return -1
	var best := -1
	var best_distance := 26.0
	for i in range(_cities.size()):
		var city = _cities[i]
		if _city_is_destroyed(city):
			continue
		var projected := _project_surface(city.get("surface", Vector3(0.0, 0.0, 1.0)), 1.015)
		if not bool(projected.get("visible", false)):
			continue
		var distance := screen_position.distance_to(projected.get("position", Vector2.ZERO))
		if distance < best_distance:
			best_distance = distance
			best = i
	return best

func _city_is_destroyed(city: Dictionary) -> bool:
	return bool(city.get("destroyed", false)) or float(city.get("damage", 0.0)) >= DESTROYED_DAMAGE

func launch_missile(source_index: int, target_index: int, nuclear: bool, ai_controlled: bool = false, interception: Dictionary = {}) -> void:
	if source_index < 0 or target_index < 0 or source_index >= _cities.size() or target_index >= _cities.size():
		return
	var source: Dictionary = _cities[source_index]
	var target: Dictionary = _cities[target_index]
	var defense_index := int(interception.get("defense_index", -1))
	var defense_surface := Vector3.ZERO
	if defense_index >= 0 and defense_index < _cities.size():
		var defense_city: Dictionary = _cities[defense_index]
		defense_surface = defense_city.get("surface", Vector3.ZERO)
	_missiles.append({
		"source": source.get("surface", Vector3(0.0, 0.0, 1.0)),
		"target": target.get("surface", Vector3(0.0, 0.0, 1.0)),
		"target_index": target_index,
		"elapsed": 0.0,
		"duration": 2.45 if nuclear else 1.85,
		"nuclear": nuclear,
		"faction": int(source.get("faction", 0)),
		"ai_controlled": ai_controlled,
		"intercepted": bool(interception.get("intercepted", false)),
		"intercept_t": float(interception.get("intercept_t", 0.67)),
		"defense_index": defense_index,
		"defense_surface": defense_surface
	})
	queue_redraw()

func has_active_missiles() -> bool:
	return not _missiles.is_empty()

func _process(delta: float) -> void:
	if not _missiles.is_empty():
		for i in range(_missiles.size() - 1, -1, -1):
			var missile: Dictionary = _missiles[i]
			missile["elapsed"] = float(missile.get("elapsed", 0.0)) + delta
			var duration = max(0.01, float(missile.get("duration", 1.8)))
			var progress = clamp(float(missile["elapsed"]) / duration, 0.0, 1.0)
			var should_intercept = bool(missile.get("intercepted", false)) and progress >= float(missile.get("intercept_t", 0.67))
			if should_intercept:
				var target_index := int(missile.get("target_index", -1))
				var attacker_faction := int(missile.get("faction", 0))
				var ai_controlled := bool(missile.get("ai_controlled", false))
				var defense_index := int(missile.get("defense_index", -1))
				var intercept_t := float(missile.get("intercept_t", 0.67))
				var intercept_point := _arc_point(missile.get("source", Vector3(0.0, 0.0, 1.0)), missile.get("target", Vector3(0.0, 0.0, 1.0)), intercept_t)
				var projected := _project_surface(intercept_point.normalized(), intercept_point.length())
				var impact_position: Vector2 = projected.get("position", Vector2(-1000.0, -1000.0))
				_missiles.remove_at(i)
				strike_intercepted.emit(target_index, impact_position, attacker_faction, ai_controlled, defense_index)
			elif float(missile["elapsed"]) >= duration:
				var target_index := int(missile.get("target_index", -1))
				var nuclear := bool(missile.get("nuclear", false))
				var attacker_faction := int(missile.get("faction", 0))
				var ai_controlled := bool(missile.get("ai_controlled", false))
				var projected := _project_surface(missile.get("target", Vector3(0.0, 0.0, 1.0)), 1.01)
				var impact_position: Vector2 = projected.get("position", Vector2(-1000.0, -1000.0))
				_missiles.remove_at(i)
				strike_completed.emit(target_index, nuclear, impact_position, attacker_faction, ai_controlled)
			else:
				_missiles[i] = missile
		queue_redraw()

func _draw() -> void:
	if _planet == null:
		return
	_draw_craters()
	if _show_nodes:
		_draw_cities()
	_draw_missiles()

func _draw_craters() -> void:
	for impact_value in _impacts:
		var impact: Dictionary = impact_value
		var surface: Vector3 = impact.get("surface", Vector3(0.0, 0.0, 1.0))
		var projected := _project_surface(surface, 1.006)
		if not bool(projected.get("visible", false)):
			continue
		var depth = clamp(float(projected.get("depth", 0.0)), 0.0, 1.0)
		if depth <= 0.02:
			continue
		var nuclear := bool(impact.get("nuclear", false))
		var base_radius := 14.0 if nuclear else 8.5
		var radius := base_radius * sqrt(max(depth, 0.04))
		var pos: Vector2 = projected.get("position", Vector2.ZERO)
		pos = (pos / 2.0).round() * 2.0

		# A dark basin + broken hot rim reads as surface damage without hiding
		# civilization nodes. Nuclear strikes leave a larger, hotter scar.
		draw_circle(pos, radius, Color(0.025, 0.020, 0.018, 0.84), true, -1.0, false)
		draw_circle(pos, max(2.0, radius * 0.43), Color(0.005, 0.004, 0.004, 0.92), true, -1.0, false)
		var rim_color := Color(0.94, 0.30, 0.09, 0.68) if nuclear else Color(0.40, 0.26, 0.19, 0.54)
		draw_arc(pos, radius * 0.84, 0.22, 2.60, 12, rim_color, 2.0, false)
		draw_arc(pos, radius * 0.84, 3.30, 5.58, 12, rim_color, 2.0, false)
		if nuclear:
			_draw_pixel(pos + Vector2(radius * 0.58, -radius * 0.22), Color(1.0, 0.48, 0.12, 0.68), 3.0)
			_draw_pixel(pos + Vector2(-radius * 0.44, radius * 0.34), Color(0.76, 0.18, 0.06, 0.62), 3.0)

func _draw_cities() -> void:
	for i in range(_cities.size()):
		var city: Dictionary = _cities[i]
		var damage = clamp(float(city.get("damage", 0.0)), 0.0, 1.0)
		if _city_is_destroyed(city):
			continue
		var projected := _project_surface(city.get("surface", Vector3(0.0, 0.0, 1.0)), 1.012)
		if not bool(projected.get("visible", false)):
			continue
		var pos: Vector2 = projected.get("position", Vector2.ZERO)
		var faction_index := int(city.get("faction", 0))
		var color := _faction_color(faction_index)
		color = color.lerp(Color(0.20, 0.20, 0.20, 1.0), damage * 0.72)
		var size := city_pixel_size
		_draw_pixel(pos, color, size)
		_draw_node_role(pos, city, color, size)
		if faction_index == 0:
			draw_arc(pos, size + 3.0, 0.0, TAU, 16, Color(0.62, 0.94, 1.0, 0.72), 1.0, true)
		if damage > 0.001:
			var meter_radius := size + 5.0
			draw_arc(pos, meter_radius, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - damage), 18, Color(0.96, 0.72, 0.24, 0.92), 2.0, true)
			draw_line(pos + Vector2(-4.0, -4.0), pos + Vector2(4.0, 4.0), Color(1.0, 0.38, 0.20, 0.88), 1.5, true)
		if _war_mode:
			draw_rect(Rect2(pos - Vector2.ONE * (size + 4.0) * 0.5, Vector2.ONE * (size + 4.0)), Color(color.r, color.g, color.b, 0.72), false, 1.0)
		if i == _selected_source:
			draw_arc(pos, 11.0, 0.0, TAU, 20, Color(0.95, 0.95, 0.72, 0.95), 2.0, true)

func _draw_node_role(pos: Vector2, city: Dictionary, color: Color, size: float) -> void:
	var role := str(city.get("node_class", "industry"))
	var accent := color.lerp(Color.WHITE, 0.34)
	match role:
		"capital":
			draw_line(pos + Vector2(0.0, -8.0), pos + Vector2(7.0, 0.0), accent, 1.3, true)
			draw_line(pos + Vector2(7.0, 0.0), pos + Vector2(0.0, 8.0), accent, 1.3, true)
			draw_line(pos + Vector2(0.0, 8.0), pos + Vector2(-7.0, 0.0), accent, 1.3, true)
			draw_line(pos + Vector2(-7.0, 0.0), pos + Vector2(0.0, -8.0), accent, 1.3, true)
		"missile_base":
			draw_line(pos + Vector2(0.0, 7.0), pos + Vector2(0.0, -8.0), accent, 1.6, true)
			draw_line(pos + Vector2(0.0, -8.0), pos + Vector2(-3.0, -4.0), accent, 1.4, true)
			draw_line(pos + Vector2(0.0, -8.0), pos + Vector2(3.0, -4.0), accent, 1.4, true)
		"defense_array":
			draw_arc(pos, size + 5.0, 0.0, TAU, 18, Color(accent.r, accent.g, accent.b, 0.78), 1.4, true)
			draw_arc(pos, size + 8.0, -PI * 0.82, -PI * 0.18, 10, Color(accent.r, accent.g, accent.b, 0.52), 1.0, true)
		"industry":
			draw_rect(Rect2(pos + Vector2(-9.0, 2.0), Vector2(4.0, 5.0)), accent, false, 1.2)
			draw_rect(Rect2(pos + Vector2(5.0, -1.0), Vector2(4.0, 8.0)), accent, false, 1.2)
		"radar":
			draw_line(pos, pos + Vector2(0.0, -8.0), accent, 1.2, true)
			draw_arc(pos + Vector2(0.0, -7.0), 5.0, -PI * 0.86, -PI * 0.14, 8, accent, 1.2, true)
			draw_arc(pos + Vector2(0.0, -7.0), 8.0, -PI * 0.86, -PI * 0.14, 10, Color(accent.r, accent.g, accent.b, 0.58), 1.0, true)

func _draw_missiles() -> void:
	for missile in _missiles:
		var duration = max(0.01, float(missile.get("duration", 1.8)))
		var progress = clamp(float(missile.get("elapsed", 0.0)) / duration, 0.0, 1.0)
		var source: Vector3 = missile.get("source", Vector3(0.0, 0.0, 1.0))
		var target: Vector3 = missile.get("target", Vector3(0.0, 0.0, 1.0))
		var nuclear := bool(missile.get("nuclear", false))
		var faction_index := int(missile.get("faction", 0))
		var ai_controlled := bool(missile.get("ai_controlled", false))
		var trail_color := Color(1.0, 0.34, 0.15, 0.96) if ai_controlled else _faction_color(faction_index).lerp(Color.WHITE, 0.38)
		if nuclear:
			trail_color = Color(1.0, 0.48, 0.12, 0.98) if ai_controlled else Color(1.0, 0.70, 0.20, 0.96)
		var head_color := Color(1.0, 0.80, 0.58, 1.0) if ai_controlled else Color(0.88, 0.96, 1.0, 1.0)
		if nuclear:
			head_color = Color(1.0, 0.94, 0.72, 1.0)

		var trail_start = max(0.0, progress - 0.32)
		var samples := 30
		var previous_valid := false
		var previous_pos := Vector2.ZERO
		for s in range(samples + 1):
			var local_t = lerp(trail_start, progress, float(s) / float(samples))
			var point := _arc_point(source, target, local_t)
			var projected := _project_surface(point.normalized(), point.length())
			var visible := bool(projected.get("visible", false))
			var pos: Vector2 = projected.get("position", Vector2.ZERO)
			if visible:
				var fade := float(s) / float(samples)
				var c := Color(trail_color.r, trail_color.g, trail_color.b, trail_color.a * fade)
				if previous_valid:
					draw_line(previous_pos, pos, c, 2.0 if nuclear else 1.0, true)
				if s % 3 == 0:
					_draw_pixel(pos, c, missile_pixel_size)
			previous_valid = visible
			previous_pos = pos

		var head_point := _arc_point(source, target, progress)
		var head_projected := _project_surface(head_point.normalized(), head_point.length())
		if bool(missile.get("intercepted", false)):
			var intercept_t := float(missile.get("intercept_t", 0.67))
			if progress >= max(0.0, intercept_t - 0.16):
				var defense_surface: Vector3 = missile.get("defense_surface", Vector3.ZERO)
				if defense_surface.length() > 0.1:
					var defense_projected := _project_surface(defense_surface.normalized(), 1.035)
					if bool(defense_projected.get("visible", false)) and bool(head_projected.get("visible", false)):
						var defense_pos: Vector2 = defense_projected.get("position", Vector2.ZERO)
						var head_pos_for_beam: Vector2 = head_projected.get("position", Vector2.ZERO)
						draw_line(defense_pos, head_pos_for_beam, Color(0.74, 0.95, 1.0, 0.88), 1.5, true)
						draw_circle(defense_pos, 5.0, Color(0.72, 0.94, 1.0, 0.34), false, 1.0, true)
		if bool(head_projected.get("visible", false)):
			var head_pos: Vector2 = head_projected.get("position", Vector2.ZERO)
			_draw_pixel(head_pos, head_color, missile_pixel_size + (2.0 if nuclear else 0.0))

func _arc_point(a: Vector3, b: Vector3, t: float) -> Vector3:
	var unit := _slerp_unit(a.normalized(), b.normalized(), t)
	var altitude := 1.0 + sin(PI * t) * arc_height
	return unit * altitude

func _slerp_unit(a: Vector3, b: Vector3, t: float) -> Vector3:
	var dot_value = clamp(a.dot(b), -0.9999, 0.9999)
	var theta := acos(dot_value)
	if abs(theta) < 0.0001:
		return a.lerp(b, t).normalized()
	var sin_theta := sin(theta)
	return (a * sin((1.0 - t) * theta) + b * sin(t * theta)) / sin_theta

func _project_surface(surface: Vector3, altitude: float) -> Dictionary:
	if _planet == null:
		return {"visible": false, "position": Vector2.ZERO}
	var camera_space := _rotate_x(surface, -_rotation.y)
	camera_space = _rotate_y(camera_space, -_rotation.x)
	var visible := camera_space.z > -0.015
	var local_center := _planet.size * 0.5
	var radius := _planet.size.x * 0.5 * _planet_radius * altitude
	var local_pos := local_center + Vector2(camera_space.x, camera_space.y) * radius
	var screen_pos: Vector2 = _planet.get_global_transform() * local_pos
	return {"visible": visible, "position": screen_pos, "depth": camera_space.z}

func _rotate_y(v: Vector3, angle: float) -> Vector3:
	var c := cos(angle)
	var s := sin(angle)
	return Vector3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z)

func _rotate_x(v: Vector3, angle: float) -> Vector3:
	var c := cos(angle)
	var s := sin(angle)
	return Vector3(v.x, c * v.y - s * v.z, s * v.y + c * v.z)

func _faction_color(index: int) -> Color:
	if index >= 0 and index < _factions.size():
		var faction: Dictionary = _factions[index]
		var color: Color = faction.get("color", Color(0.75, 0.82, 0.88, 1.0))
		if str(faction.get("status", "active")) != "active":
			return color.lerp(Color(0.30, 0.30, 0.30, 1.0), 0.68)
		return color
	return Color(0.75, 0.82, 0.88, 1.0)

func _draw_pixel(position: Vector2, color: Color, size: float) -> void:
	var snapped := (position / size).round() * size
	draw_rect(Rect2(snapped - Vector2.ONE * size * 0.5, Vector2.ONE * size), color, true)
