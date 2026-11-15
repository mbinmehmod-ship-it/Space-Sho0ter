extends Node

@export var sfx_volume_db: float = 0.0
@export var music_volume_db: float = -10.0
@export var play_music: bool = true

var _streams: Dictionary = {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer = null
var _spawner: Node = null
var _player: Node = null
var _last_escaped: int = 0
var _music_muted: bool = false
var _hooked_buttons: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Load every sound by file name (searches the whole project)
	var names: Array[String] = ["laser", "explosion", "player_hit", "breach", "click", "game_over", "music"]
	for n in names:
		var path: String = _find_file(n + ".wav", "res://")
		if path == "":
			push_warning("Sound: could not find " + n + ".wav (put it in res://audio/)")
		else:
			_streams[n] = load(path)

	# A small pool of players so several sounds can overlap
	for i in range(8):
		var p := AudioStreamPlayer.new()
		p.volume_db = sfx_volume_db
		add_child(p)
		_sfx_players.append(p)

	_music = AudioStreamPlayer.new()
	_music.volume_db = music_volume_db
	add_child(_music)
	_music.finished.connect(_on_music_finished)
	if play_music and _streams.has("music"):
		_music.stream = _streams["music"]
		_music.play()

	# Wait one frame so the other nodes (and the UI buttons) exist
	await get_tree().process_frame
	_hook_game()
	_hook_buttons(get_parent())


func _hook_game() -> void:
	_spawner = get_parent().get_node_or_null("EnemySpawner")
	_player = get_tree().get_first_node_in_group("player")

	if _spawner != null:
		_spawner.connect("enemy_killed", _on_enemy_killed)
		_spawner.connect("game_over", _on_game_over)
	else:
		push_warning("Sound: no node named 'EnemySpawner' next to Sound.")

	if _player != null:
		_player.connect("hit", _on_player_hit)
		if _player.has_signal("fired"):
			_player.connect("fired", _on_player_fired)
		else:
			push_warning("Sound: add 'signal fired' to player.gd for laser sounds.")
	else:
		push_warning("Sound: no node in group 'player'.")


func _hook_buttons(node: Node) -> void:
	for child in node.get_children():
		if child is Button and not _hooked_buttons.has(child):
			_hooked_buttons.append(child)
			child.pressed.connect(_on_button_pressed)
		_hook_buttons(child)


func _process(_delta: float) -> void:
	# Breach alarm when an enemy gets past the bottom line
	if _spawner != null:
		var escaped: int = _spawner.get("_escaped")
		if escaped > _last_escaped:
			play("breach")
		_last_escaped = escaped


func _input(event: InputEvent) -> void:
	# M toggles the music
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M:
			_music_muted = not _music_muted
			_music.stream_paused = _music_muted


# ---------------- Play helpers ----------------

func play(sound_name: String, volume_offset_db: float = 0.0) -> void:
	if not _streams.has(sound_name):
		return
	for p in _sfx_players:
		if not p.playing:
			p.stream = _streams[sound_name]
			p.volume_db = sfx_volume_db + volume_offset_db
			p.play()
			return
	# All players are busy, so steal the first one
	_sfx_players[0].stream = _streams[sound_name]
	_sfx_players[0].volume_db = sfx_volume_db + volume_offset_db
	_sfx_players[0].play()


func _on_music_finished() -> void:
	if play_music and not _music_muted:
		_music.play()


# ---------------- Game events ----------------

func _on_player_fired() -> void:
	play("laser", -6.0)


func _on_enemy_killed(_points: int) -> void:
	play("explosion")


func _on_player_hit(_lives_left: int) -> void:
	play("player_hit")


func _on_game_over() -> void:
	play_music = false
	_music.stop()
	play("game_over")


func _on_button_pressed() -> void:
	play("click")


# ---------------- File search ----------------

func _find_file(file_name: String, dir_path: String) -> String:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return ""
	dir.list_dir_begin()
	var f: String = dir.get_next()
	while f != "":
		if not f.begins_with("."):
			if dir.current_is_dir():
				var sub: String = _find_file(file_name, dir_path.path_join(f))
				if sub != "":
					dir.list_dir_end()
					return sub
			else:
				var clean: String = f.trim_suffix(".import").trim_suffix(".remap")
				if clean == file_name:
					dir.list_dir_end()
					return dir_path.path_join(clean)
		f = dir.get_next()
	dir.list_dir_end()
	return ""
