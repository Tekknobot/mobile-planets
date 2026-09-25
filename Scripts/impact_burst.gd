extends Node2D

@export var duration: float = 3.35
@export var particle_count: int = 42
@export var pixel_size: float = 4.0

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

	for i in range(particle_count):
		var base_angle := TAU * float(i) / float(particle_count)
		var angle := base_angle + _rng.randf_range(-0.16, 0.16)
		_particles.append({
			"direction": Vector2(cos(angle), sin(angle)),
			"speed": _rng.randf_range(54.0, 170.0),
			"delay": _rng.randf_range(0.0, 0.16),
			"warmth": _rng.randf(),
			"drag": _rng.randf_range(0.28, 0.50)
		})

	# Slower debris uses the exact same pixel size; only velocity differs.
	for i in range(12):
		var angle := _rng.randf_range(0.0, TAU)
		_particles.append({
			"direction": Vector2(cos(angle), sin(angle)),
			"speed": _rng.randf_range(28.0, 72.0),
			"delay": _rng.randf_range(0.05, 0.24),
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

	# The core is made from fixed-size pixels that spread apart. Nothing scales.
	var core_t = clamp(_elapsed / 0.34, 0.0, 1.0)
	var core_alpha = 1.0 - core_t
	if core_alpha > 0.0:
		var spread = round(core_t * 4.0) * pixel_size
		_draw_pixel(Vector2.ZERO, Color(1.0, 0.92, 0.58, core_alpha))
		_draw_pixel(Vector2(spread, 0.0), Color(1.0, 0.48, 0.10, core_alpha * 0.86))
		_draw_pixel(Vector2(-spread, 0.0), Color(1.0, 0.48, 0.10, core_alpha * 0.86))
		_draw_pixel(Vector2(0.0, spread), Color(1.0, 0.31, 0.06, core_alpha * 0.76))
		_draw_pixel(Vector2(0.0, -spread), Color(1.0, 0.62, 0.16, core_alpha * 0.86))

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
		position = (position / pixel_size).round() * pixel_size

		var warmth: float = particle["warmth"]
		var hot := Color(1.0, 0.82, 0.34, 1.0)
		var ember := Color(1.0, 0.26, 0.06, 1.0)
		var smoke := Color(0.28, 0.20, 0.18, 1.0)
		var color := hot.lerp(ember, clamp(t * 1.45 + warmth * 0.18, 0.0, 1.0))
		if t > 0.62:
			color = color.lerp(smoke, (t - 0.62) / 0.38)
		color.a = pow(1.0 - t, 1.35)
		_draw_pixel(position, color)

func _draw_pixel(position: Vector2, color: Color) -> void:
	var snapped := (position / pixel_size).round() * pixel_size
	var top_left := snapped - Vector2.ONE * pixel_size * 0.5
	draw_rect(Rect2(top_left, Vector2.ONE * pixel_size), color, true)
