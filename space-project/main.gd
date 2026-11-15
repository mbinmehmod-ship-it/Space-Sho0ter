extends Node2D

signal enemy_killed(points: int)
signal game_over

@export var spawn_interval: float = 1.0
@export var min_spawn_interval: float = 0.4
@export var enemy_speed: float = 120.0
@export var enemy_health: int = 2
@export var wave_amplitude: float = 80.0
@export var enemy_shoots: bool = true
@export var shoot_interval: float = 1.5
@export var points_per_kill: int = 10
@export var max_escapes: int = 3
@export var defeat_line_margin: float = 0.0
@export var show_defeat_line: bool = true

# Change these paths if your images are in a subfolder (e.g. res://sprites/...)
const SHIP_PATHS: Array[String] = [
	"res://ship_yellow_stroked.png",
	"res://ship_blue_stroked.png",
	"res://ship_green_stroked.png",
	"res://ship_orange_stroked.png",
	"res://ship_purple_stroked.png",
]

var _textures: Array[Texture2D] = []
var _timer: float = 0.0
var _score: int = 0
var _escaped: int = 0
var _lives: int = 3
var _is_game_over: bool = false
var _restart_delay: float = 0.0
var _hud: Label
var _center_label: Label


# ---------- Enemy bullet ----------
class EnemyBullet extends Node2D:
	var velocity: Vector2 = Vector2.DOWN * 300.0

	func _ready() -> void:
		z_index = 50

	func _draw() -> void:
		draw_rect(Rect2(-3, -10, 6, 20), Color.RED)

	func _process(delta: float) -> void:
		global_position += velocity * delta

		for p in get_tree().get_nodes_in_group("player"):
			if p.global_position.distance_to(global_position) < 30.0:
				if p.has_method("take_hit"):
					p.take_hit()
				queue_free()
				return

		if not get_viewport_rect().grow(200.0).has_point(global_position):
			queue_free()


# ---------- Enemy ship ----------
class Enemy extends Sprite2D:
	signal died
	signal escaped

	var speed: float = 120.0
	var health: int = 2
	var amplitude: float = 80.0
	var shoots: bool = true
	var shoot_interval: float = 1.5
	var defeat_y: float = 700.0

	var _start_x: float = 0.0
	var _time: float = 0.0
	var _shoot_timer: float = 0.0
	var _hit_radius: float = 30.0

	func _ready() -> void:
		flip_v = true
		_start_x = global_position.x
		_time = randf() * TAU
		_shoot_timer = randf_range(0.3, shoot_interval)
		if texture:
			_hit_radius = minf(texture.get_width(), texture.get_height()) * 0.4 * absf(scale.x)

	func _process(delta: float) -> void:
		_time += delta
		global_position.y += speed * delta
		global_position.x = _start_x + sin(_time * 2.0) * amplitude

		if shoots:
			_shoot_timer -= delta
			if _shoot_timer <= 0.0:
				_shoot_timer = shoot_interval
				_shoot()

		for b in get_tree().get_nodes_in_group("player_bullets"):
			if b.global_position.distance_to(global_position) < _hit_radius:
				b.queue_free()
				_take_damage(1)
				if health <= 0:
					return

		for p in get_tree().get_nodes_in_group("player"):
			if p.global_position.distance_to(global_position) < _hit_radius + 20.0:
				if p.has_method("take_hit"):
					p.take_hit()
				died.emit()
				queue_free()
				return

		if global_position.y > defeat_y:
			escaped.emit()
			queue_free()

	func _shoot() -> void:
		var bullet := EnemyBullet.new()
		get_tree().current_scene.add_child(bullet)
		bullet.global_position = global_position + Vector2(0, 40)

	func _take_damage(amount: int) -> void:
		health -= amount
		modulate = Color(3, 3, 3)
		create_tween().tween_property(self, "modulate", Color.WHITE, 0.1)
		if health <= 0:
			died.emit()
			queue_free()


# ---------- Spawner ----------
func _ready() -> void:
	randomize()
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 200

	for path in SHIP_PATHS:
		if ResourceLoader.exists(path):
			_textures.append(load(path))
		else:
			push_warning("Ship image not found: " + path)
	if _textures.is_empty():
		push_error("No ship textures loaded. Fix SHIP_PATHS in enemy_spawner.gd")

	_build_ui()
	queue_redraw()

	await get_tree().process_frame
	var player := get_tree().get_first_node_in_group("player")
	if player:
		_lives = player.lives
		player.hit.connect(_on_player_hit)
		player.dead.connect(_on_player_dead)
	else:
		push_warning("No node in group 'player'. Is player.gd attached to your ship?")
	_update_hud()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)

	_hud = Label.new()
	_hud.position = Vector2(12, 8)
	_hud.add_theme_font_size_override("font_size", 24)
	layer.add_child(_hud)

	_center_label = Label.new()
	_center_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_center_label.add_theme_font_size_override("font_size", 48)
	_center_label.visible = false
	layer.add_child(_center_label)


func _update_hud() -> void:
	_hud.text = "Score: %d    Lives: %d    Escaped: %d/%d" % [_score, _lives, _escaped, max_escapes]


func _defeat_y() -> float:
	return get_viewport_rect().size.y - defeat_line_margin


func _draw() -> void:
	if show_defeat_line:
		var w := get_viewport_rect().size.x
		var y := _defeat_y()
		draw_line(Vector2(0, y), Vector2(w, y), Color(1, 0.2, 0.2, 0.6), 2.0)


func _process(delta: float) -> void:
	if _is_game_over:
		_restart_delay -= delta
		if _restart_delay <= 0.0 and Input.is_action_just_pressed("ui_accept"):
			get_tree().paused = false
			get_tree().reload_current_scene()
		return

	if _textures.is_empty():
		return

	_timer -= delta
	if _timer <= 0.0:
		_timer = spawn_interval
		_spawn_enemy()
		spawn_interval = maxf(min_spawn_interval, spawn_interval - 0.01)


func _spawn_enemy() -> void:
	var enemy := Enemy.new()
	enemy.texture = _textures.pick_random()
	enemy.speed = enemy_speed
	enemy.health = enemy_health
	enemy.amplitude = wave_amplitude
	enemy.shoots = enemy_shoots
	enemy.shoot_interval = shoot_interval
	enemy.defeat_y = _defeat_y()
	enemy.z_index = 10
	enemy.died.connect(_on_enemy_died)
	enemy.escaped.connect(_on_enemy_escaped)

	# Set the position BEFORE add_child so _ready() records the right start X
	var margin := wave_amplitude + 40.0
	var width := get_viewport_rect().size.x
	enemy.position = Vector2(randf_range(margin, maxf(margin, width - margin)), -60.0)

	get_tree().current_scene.add_child(enemy)
	print("Enemy spawned at ", enemy.global_position)


func _on_enemy_died() -> void:
	_score += points_per_kill
	enemy_killed.emit(points_per_kill)
	_update_hud()


func _on_enemy_escaped() -> void:
	if _is_game_over:
		return
	_escaped += 1
	_update_hud()
	if _escaped >= max_escapes:
		_trigger_game_over("An enemy got past you!")


func _on_player_hit(lives_left: int) -> void:
	_lives = lives_left
	_update_hud()


func _on_player_dead() -> void:
	_trigger_game_over("You were destroyed!")


func _trigger_game_over(reason: String) -> void:
	if _is_game_over:
		return
	_is_game_over = true
	_restart_delay = 1.0
	_center_label.text = "GAME OVER\n%s\nScore: %d\n\nPress Space to restart" % [reason, _score]
	_center_label.visible = true
	game_over.emit()
	get_tree().paused = true
