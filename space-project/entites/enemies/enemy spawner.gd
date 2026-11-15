extends Node2D

signal enemy_killed(points: int)
signal game_over

@export var enemy_scale: Vector2 = Vector2(0.4, 0.4)
@export var spawn_interval: float = 2.0
@export var min_spawn_interval: float = 0.8
@export var enemy_speed: float = 60.0
@export var enemy_health: int = 2
@export var wave_amplitude: float = 80.0
@export var enemy_shoots: bool = true
@export var shoot_interval: float = 1.0
@export var points_per_kill: int = 10
@export var max_escapes: int = 3
@export var defeat_line_margin: float = 0.0
@export var show_defeat_line: bool = true

var _textures: Array[Texture2D] = []
var _timer: float = 0.5
var _score: int = 0
var _escaped: int = 0
var _lives: int = 3
var _is_game_over: bool = false
var _restart_delay: float = 0.0
var _hud: Label
var _center_label: Label


class EnemyBullet extends Node2D:
	var velocity: Vector2 = Vector2.DOWN * 300.0

	func _ready() -> void:
		z_index = 50

	func _draw() -> void:
		draw_rect(Rect2(-3, -10, 6, 20), Color.RED)

	func _process(delta: float) -> void:
		global_position += velocity * delta
		var my_rect := Rect2(global_position + Vector2(-3, -10), Vector2(6, 20))

		for n in get_tree().get_nodes_in_group("player"):
			var p := n as Sprite2D
			if p == null:
				continue
			var ps: Vector2 = p.get_rect().size * p.global_scale.abs()
			var p_rect := Rect2(p.global_position - ps * 0.5, ps)
			if p_rect.intersects(my_rect):
				p.call("take_hit")
				queue_free()
				return

		if global_position.y > 2000.0:
			queue_free()


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

	func _ready() -> void:
		flip_v = true
		_start_x = position.x
		_time = randf() * TAU
		_shoot_timer = randf_range(0.3, shoot_interval)

	func _world_rect() -> Rect2:
		var sz := Vector2(32, 32)
		if texture != null:
			sz = texture.get_size()
		sz = sz * global_scale.abs()
		return Rect2(global_position - sz * 0.5, sz)

	func _process(delta: float) -> void:
		_time += delta
		position.y += speed * delta
		position.x = _start_x + sin(_time * 2.0) * amplitude

		if shoots:
			_shoot_timer -= delta
			if _shoot_timer <= 0.0:
				_shoot_timer = shoot_interval
				_shoot()

		var rect: Rect2 = _world_rect()
		var hit_rect: Rect2 = rect.grow(6.0)

		for n in get_tree().get_nodes_in_group("player_bullets"):
			var b := n as Node2D
			if b == null:
				continue
			var b_rect := Rect2(b.global_position + Vector2(-3, -12), Vector2(6, 24))
			if hit_rect.intersects(b_rect):
				b.queue_free()
				health -= 1
				modulate = Color(3, 3, 3)
				create_tween().tween_property(self, "modulate", Color.WHITE, 0.1)
				if health <= 0:
					died.emit()
					queue_free()
					return

		for n in get_tree().get_nodes_in_group("player"):
			var p := n as Sprite2D
			if p == null:
				continue
			var ps: Vector2 = p.get_rect().size * p.global_scale.abs()
			var p_rect := Rect2(p.global_position - ps * 0.5, ps)
			if p_rect.intersects(rect):
				p.call("take_hit")
				died.emit()
				queue_free()
				return

		if global_position.y > defeat_y:
			escaped.emit()
			queue_free()

	func _shoot() -> void:
		var bullet := EnemyBullet.new()
		bullet.position = global_position + Vector2(0, _world_rect().size.y * 0.5)
		get_tree().current_scene.add_child(bullet)


func _ready() -> void:
	randomize()
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 200
	print("EnemySpawner is running")

	_load_textures()
	_build_ui()
	queue_redraw()
	_update_hud()

	await get_tree().process_frame
	var player = get_tree().get_first_node_in_group("player")
	if player != null:
		_lives = player.get("lives")
		player.connect("hit", _on_player_hit)
		player.connect("dead", _on_player_dead)
		_update_hud()
	else:
		push_warning("No node in group 'player'. Is player.gd attached to ShipRedStroked?")


func _load_textures() -> void:
	var paths: Array[String] = _find_ships("res://")
	for path in paths:
		var tex := load(path) as Texture2D
		if tex != null:
			_textures.append(tex)

	print("Enemy textures found: ", _textures.size())

	if _textures.is_empty():
		push_warning("No ship images found. Using orange squares instead.")
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		img.fill(Color(1.0, 0.5, 0.1))
		_textures.append(ImageTexture.create_from_image(img))


func _find_ships(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found

	dir.list_dir_begin()
	var file: String = dir.get_next()
	while file != "":
		if not file.begins_with("."):
			if dir.current_is_dir():
				found.append_array(_find_ships(dir_path.path_join(file)))
			else:
				var clean: String = file.trim_suffix(".import")
				var is_ship: bool = clean.begins_with("ship_") and clean.ends_with(".png")
				var is_red: bool = clean.contains("red")
				if is_ship and not is_red:
					var full: String = dir_path.path_join(clean)
					if not found.has(full):
						found.append(full)
		file = dir.get_next()
	dir.list_dir_end()
	return found


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
		var y: float = _defeat_y()
		var w: float = get_viewport_rect().size.x
		draw_line(Vector2(0, y), Vector2(w, y), Color(1, 0.2, 0.2, 0.6), 2.0)


func _process(delta: float) -> void:
	if _is_game_over:
		_restart_delay -= delta
		var restart: bool = Input.is_action_just_pressed("ui_accept")
		if _restart_delay <= 0.0 and restart:
			get_tree().paused = false
			get_tree().reload_current_scene()
		return

	_timer -= delta
	if _timer <= 0.0:
		_timer = spawn_interval
		_spawn_enemy()
		spawn_interval = maxf(min_spawn_interval, spawn_interval - 0.01)


func _spawn_enemy() -> void:
	var enemy := Enemy.new()
	enemy.texture = _textures.pick_random()
	enemy.scale = enemy_scale
	enemy.speed = enemy_speed
	enemy.health = enemy_health
	enemy.amplitude = wave_amplitude
	enemy.shoots = enemy_shoots
	enemy.shoot_interval = shoot_interval
	enemy.defeat_y = _defeat_y()
	enemy.z_index = 10
	enemy.died.connect(_on_enemy_died)
	enemy.escaped.connect(_on_enemy_escaped)

	var margin: float = wave_amplitude + 40.0
	var width: float = get_viewport_rect().size.x
	var x: float = randf_range(margin, maxf(margin, width - margin))
	enemy.position = Vector2(x, -60.0)

	get_tree().current_scene.add_child(enemy)


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
