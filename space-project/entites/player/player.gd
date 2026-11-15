extends Sprite2D

signal hit(lives_left: int)
signal dead
signal fired

@export var speed: float = 300.0
@export var fire_rate: float = 0.25
@export var bullet_speed: float = 700.0
@export var muzzle_offset: Vector2 = Vector2(0, -40)
@export var lives: int = 3
@export var invincible_time: float = 1.0

var _cooldown: float = 0.0
var _invincible: float = 0.0
var _is_dead: bool = false


class PlayerBullet extends Node2D:
	var velocity: Vector2 = Vector2.UP * 700.0

	func _ready() -> void:
		add_to_group("player_bullets")
		z_index = 100

	func _draw() -> void:
		draw_rect(Rect2(-3, -12, 6, 24), Color.YELLOW)

	func _process(delta: float) -> void:
		global_position += velocity * delta
		if global_position.y < -200.0:
			queue_free()


func _ready() -> void:
	add_to_group("player")


func _process(delta: float) -> void:
	var direction: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	global_position += direction * speed * delta
	_clamp_to_screen()

	_cooldown -= delta
	var fire_pressed: bool = Input.is_action_pressed("ui_accept") or Input.is_key_pressed(KEY_SPACE)
	if fire_pressed and _cooldown <= 0.0:
		_fire()
		_cooldown = fire_rate

	if _invincible > 0.0:
		_invincible -= delta
		if int(_invincible * 10.0) % 2 == 0:
			modulate.a = 0.35
		else:
			modulate.a = 1.0
	else:
		modulate.a = 1.0


func _fire() -> void:
	var bullet := PlayerBullet.new()
	bullet.velocity = Vector2.UP * bullet_speed
	bullet.position = global_position + muzzle_offset
	get_tree().current_scene.add_child(bullet)
	fired.emit()


func take_hit() -> void:
	if _is_dead:
		return
	if _invincible > 0.0:
		return
	lives -= 1
	_invincible = invincible_time
	hit.emit(lives)
	if lives <= 0:
		_is_dead = true
		visible = false
		remove_from_group("player")
		set_process(false)
		dead.emit()


func _clamp_to_screen() -> void:
	var screen: Vector2 = get_viewport_rect().size
	var half: Vector2 = get_rect().size * global_scale.abs() * 0.5
	global_position.x = clampf(global_position.x, half.x, screen.x - half.x)
	global_position.y = clampf(global_position.y, half.y, screen.y - half.y)
