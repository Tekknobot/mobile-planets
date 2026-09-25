extends Node2D

@export var duration: float = 1.35
@export var particle_count: int = 34

var _active := false
var _elapsed := 0.0
var _particles: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	visible = false
	set_process(false)

func burst(world_position: Vector2) -> void:
	global_position = world_position
	_elapsed = 0.0
	_active = true
	_particles.clear()
	_rng.seed = Time.get_ticks_usec()

	for i in particle_count:
		var base_angle := TAU * float(i) / float(particle_count)
		var angle := base_angle + _rng.randf_range(-0.14, 0.14)
		var direction := Vector2(cos(angle), sin(angle))
		_particles.append({
			"direction": direction,
			"speed": _rng.randf_range(62.0, 168.0),
			"size": float(_rng.randi_range(3, 7)),
			"delay": _rng.randf_range(0.0, 0.14),
			"warmth": _rng.randf(),
			"drag": _rng.randf_range(0.28, 0.48)
		})

	# A few slower blocky fragments keep the impact readable after the first pop.
	for i in 10:
		var angle := _rng.randf_range(0.0, TAU)
		_particles.append({
			"direction": Vector2(cos(angle), sin(angle)),
			"speed": _rng.randf_range(30.0, 78.0),
			"size": float(_rng.randi_range(5, 9)),
			"delay": _rng.randf_range(0.05, 0.22),
			"warmth": _rng.randf_range(0.55, 1.0),
			"drag": _rng.randf_range(0.36, 0.58)
		})

	visible = true
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	queue_redraw()
	if _elapsed >= duration:
		_active = false
		visible = false
		set_process(false)

func _draw() -> void:
	if not _active:
		return

	# Short-lived white/yellow core made from several pixels, never a solid square decal.
	var core_t = clamp(_elapsed / 0.32, 0.0, 1.0)
	var core_alpha = 1.0 - core_t
	if core_alpha > 0.0:
		var core_size = 4.0 + core_t * 14.0
		_draw_pixel(Vector2.ZERO, core_size, Color(1.0, 0.90, 0.52, core_alpha))
		_draw_pixel(Vector2(core_size, 0.0), max(3.0, core_size * 0.45), Color(1.0, 0.48, 0.12, core_alpha * 0.82))
		_draw_pixel(Vector2(-core_size, 0.0), max(3.0, core_size * 0.45), Color(1.0, 0.48, 0.12, core_alpha * 0.82))
		_draw_pixel(Vector2(0.0, core_size), max(3.0, core_size * 0.45), Color(1.0, 0.36, 0.08, core_alpha * 0.72))
		_draw_pixel(Vector2(0.0, -core_size), max(3.0, core_size * 0.45), Color(1.0, 0.60, 0.15, core_alpha * 0.82))

	for particle in _particles:
		var delay: float = particle["delay"]
		if _elapsed < delay:
			continue
		var local_duration = max(0.1, duration - delay)
		var t = clamp((_elapsed - delay) / local_duration, 0.0, 1.0)
		var speed: float = particle["speed"]
		var drag: float = particle["drag"]
		var travel = speed * (t - drag * t * t)
		var position: Vector2 = particle["direction"] * travel
		position.y += 18.0 * t * t
		# Snap movement to a small grid so the explosion retains a pixel-art cadence.
		position = (position / 2.0).round() * 2.0

		var warmth: float = particle["warmth"]
		var hot := Color(1.0, 0.82, 0.34, 1.0)
		var ember := Color(1.0, 0.26, 0.06, 1.0)
		var smoke := Color(0.28, 0.20, 0.18, 1.0)
		var color := hot.lerp(ember, clamp(t * 1.45 + warmth * 0.18, 0.0, 1.0))
		if t > 0.62:
			color = color.lerp(smoke, (t - 0.62) / 0.38)
		color.a = pow(1.0 - t, 1.35)

		var size: float = particle["size"]
		if t > 0.72:
			size *= 0.72
		_draw_pixel(position, max(2.0, size), color)

func _draw_pixel(position: Vector2, size: float, color: Color) -> void:
	var snapped_size = max(2.0, round(size / 2.0) * 2.0)
	var top_left = position - Vector2.ONE * snapped_size * 0.5
	top_left = (top_left / 2.0).round() * 2.0
	draw_rect(Rect2(top_left, Vector2.ONE * snapped_size), color, true)
