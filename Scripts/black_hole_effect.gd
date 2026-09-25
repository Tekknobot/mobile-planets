extends Node2D

@export var duration: float = 8.8
@export var accretion_pixels: int = 96
@export var pixel_size: float = 4.0
@export var dissolve_pixel_size: float = 4.0
@export var dissolve_fraction: float = 0.78
@export var dissolve_stagger_time: float = 2.30
@export var dissolve_travel_time: float = 1.35
@export var dissolve_sample_step: int = 2

var _active := false
var _elapsed := 0.0
var _center := Vector2.ZERO
var _viewport_size := Vector2(1280.0, 720.0)
var _particles: Array[Dictionary] = []
var _dissolve_particles: Array[Dictionary] = []
var _dissolve_started := false
var _dissolve_begin := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	visible = false
	set_process(false)

func start(center: Vector2, viewport_size: Vector2) -> void:
	_center = center
	_viewport_size = viewport_size
	_elapsed = 0.0
	_active = true
	_dissolve_started = false
	_dissolve_begin = 0.0
	_particles.clear()
	_dissolve_particles.clear()
	_rng.seed = Time.get_ticks_usec()

	for i in range(accretion_pixels):
		_particles.append({
			"angle": TAU * float(i) / float(accretion_pixels) + _rng.randf_range(-0.07, 0.07),
			"radius": _rng.randf_range(67.0, 128.0),
			"speed": _rng.randf_range(0.55, 1.45),
			"heat": _rng.randf(),
			"phase": _rng.randf_range(0.0, TAU)
		})

	visible = true
	set_process(true)
	queue_redraw()

func begin_dissolve(source_image, source_rect: Rect2) -> void:
	if not _active or source_image == null:
		return

	_dissolve_particles.clear()
	_dissolve_started = true
	_dissolve_begin = _elapsed

	var rect := source_rect
	var image_width = source_image.get_width()
	var image_height = source_image.get_height()
	var sample_step := dissolve_sample_step
	var body_center := rect.position + rect.size * 0.5
	var body_radius = min(rect.size.x, rect.size.y) * 0.49
	var consume_start := 1.0 - dissolve_fraction

	for y in range(int(rect.position.y), int(rect.position.y + rect.size.y), sample_step):
		for x in range(int(rect.position.x), int(rect.position.x + rect.size.x), sample_step):
			var sample_pos := Vector2(float(x) + sample_step * 0.5, float(y) + sample_step * 0.5)
			if sample_pos.distance_to(body_center) > body_radius:
				continue

			var norm_x = clamp((sample_pos.x - rect.position.x) / max(rect.size.x, 1.0), 0.0, 1.0)
			if norm_x < consume_start:
				continue

			var sx := clampi(int(sample_pos.x), 0, image_width - 1)
			var sy := clampi(int(sample_pos.y), 0, image_height - 1)
			var color: Color = source_image.get_pixel(sx, sy)
			if color.a <= 0.02 or color.r + color.g + color.b < 0.05:
				continue

			# Pixels nearest the hole go first, then the sequence walks leftward.
			var progress_across = clamp((norm_x - consume_start) / max(dissolve_fraction, 0.001), 0.0, 1.0)
			var delay = (1.0 - progress_across) * dissolve_stagger_time
			delay += abs((sample_pos.y - body_center.y) / max(body_radius, 1.0)) * 0.045
			delay += _rng.randf_range(0.0, 0.018)

			var to_hole := _center - sample_pos
			var tangent := Vector2(-to_hole.y, to_hole.x).normalized()
			# Keep swirl direction mostly coherent so it reads as a stream rather than an explosion.
			if sample_pos.y < body_center.y:
				tangent *= -1.0

			_dissolve_particles.append({
				"start_pos": sample_pos,
				"color": color,
				"delay": delay,
				"arc": _rng.randf_range(8.0, 18.0),
				"phase": _rng.randf_range(-0.18, 0.18),
				"tangent": tangent,
				"spin": _rng.randf_range(0.72, 0.96)
			})

	queue_redraw()

func stop() -> void:
	_active = false
	visible = false
	set_process(false)
	_dissolve_particles.clear()
	_particles.clear()

func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	queue_redraw()
	if _elapsed >= duration:
		stop()

func _draw() -> void:
	if not _active:
		return

	var t = clamp(_elapsed / duration, 0.0, 1.0)
	var appear := smoothstep(0.0, 0.12, t)
	var peak := 1.0 - smoothstep(0.90, 1.0, t)
	var strength := appear * peak

	draw_rect(Rect2(Vector2.ZERO, _viewport_size), Color(0.0, 0.0, 0.0, 0.11 * appear), true)

	var horizon_radius := 8.0 + 48.0 * appear
	var photon_radius := horizon_radius + 7.0
	var lens_radius := horizon_radius + 22.0

	draw_arc(_center, lens_radius, -2.75, -0.35, 64, Color(0.72, 0.82, 1.0, 0.18 * strength), 2.0, true)
	draw_arc(_center, lens_radius + 5.0, 0.38, 2.62, 64, Color(1.0, 0.67, 0.31, 0.18 * strength), 2.0, true)

	for particle in _particles:
		var base_radius: float = particle["radius"]
		var speed: float = particle["speed"]
		var angle: float = particle["angle"] + _elapsed * speed * (122.0 / base_radius)
		var pulse := sin(_elapsed * 2.4 + float(particle["phase"])) * 3.0
		var radius := base_radius + pulse
		var pos := _center + Vector2(cos(angle) * radius, sin(angle) * radius * 0.27)
		var heat: float = particle["heat"]
		var inner = clamp((128.0 - radius) / 68.0, 0.0, 1.0)
		var color := Color(0.95, 0.27, 0.05, 0.72)
		color = color.lerp(Color(1.0, 0.78, 0.28, 0.92), inner)
		color = color.lerp(Color(0.78, 0.86, 1.0, 0.96), inner * inner * (0.45 + heat * 0.35))
		color.a *= strength
		_draw_pixel(pos, color, pixel_size)

	if _dissolve_started:
		_draw_dissolve_particles()

	# Draw the horizon after matter so the final pixels visibly disappear beneath it.
	draw_circle(_center, horizon_radius, Color(0.0, 0.0, 0.0, 1.0 * appear))
	draw_arc(_center, photon_radius, 0.0, TAU, 96, Color(0.95, 0.86, 0.66, 0.72 * strength), 3.0, true)
	draw_arc(_center, photon_radius + 3.0, 0.15, 2.95, 72, Color(0.60, 0.74, 1.0, 0.24 * strength), 2.0, true)

func _draw_dissolve_particles() -> void:
	var elapsed_since = max(0.0, _elapsed - _dissolve_begin)

	for particle in _dissolve_particles:
		var delay: float = particle["delay"]
		if elapsed_since < delay:
			continue

		var dt = clamp((elapsed_since - delay) / dissolve_travel_time, 0.0, 1.0)
		if dt >= 1.0:
			continue

		var start_pos: Vector2 = particle["start_pos"]
		var tangent: Vector2 = particle["tangent"]
		var arc: float = particle["arc"]
		var phase: float = particle["phase"]
		var spin: float = particle["spin"]

		# Ease into the pull, then accelerate hard near the event horizon.
		var pull_t := pow(dt, 1.72)
		var pull := start_pos.lerp(_center, pull_t)
		var swirl = tangent * sin(dt * PI * spin + phase) * arc * (1.0 - dt) * 0.92
		var pos = pull + swirl

		var color: Color = particle["color"]
		color = color.lerp(Color(1.0, 0.67, 0.20, color.a), clamp(dt * 0.42, 0.0, 1.0))
		color = color.lerp(Color(0.22, 0.11, 0.06, color.a), clamp((dt - 0.76) / 0.24, 0.0, 1.0))
		color.a *= pow(1.0 - dt, 0.22)
		_draw_pixel(pos, color, dissolve_pixel_size)

func _draw_pixel(position: Vector2, color: Color, size: float) -> void:
	var snapped := (position / size).round() * size
	var top_left := snapped - Vector2.ONE * size * 0.5
	draw_rect(Rect2(top_left, Vector2.ONE * size), color, true)
