extends CanvasLayer

const SAVE_PATH: String = "user://highscore.save"

var _spawner: Node = null
var _player: Node = null

var _score_label: Label
var _best_label: Label
var _lives_box: HBoxContainer
var _breach_label: Label
var _breach_bar: ProgressBar

var _menu_panel: Control
var _pause_panel: Control
var _over_panel: Control
var _over_text: Label

var _play_btn: Button
var _resume_btn: Button
var _restart_btn: Button

var _high_score: int = 0
var _last_lives: int = -1
var _state: String = "menu"   # menu, playing, paused, over


func _ready() -> void:
	layer = 150
	process_mode = Node.PROCESS_MODE_ALWAYS

	_load_high_score()
	_build_hud()
	_menu_panel = _build_menu()
	_pause_panel = _build_pause()
	_over_panel = _build_game_over()
	_hide_all_panels()

	var skip_menu: bool = false
	if Engine.has_meta("skip_menu"):
		skip_menu = Engine.get_meta("skip_menu")
	Engine.set_meta("skip_menu", false)

	if skip_menu:
		_state = "playing"
	else:
		_show_menu()

	# Wait one frame so the other nodes are ready
	await get_tree().process_frame

	_spawner = get_parent().get_node_or_null("EnemySpawner")
	_player = get_tree().get_first_node_in_group("player")

	if _spawner == null:
		push_warning("UI: no node named 'EnemySpawner' next to UI.")
	else:
		# Hide the spawner's old text HUD, this UI replaces it
		for child in _spawner.get_children():
			if child is CanvasLayer:
				child.visible = false
		_spawner.connect("game_over", _on_game_over)
		_set_spawner_active(_state == "playing")

	if _player == null:
		push_warning("UI: no node in group 'player'. Is player.gd on your ship?")


func _process(_delta: float) -> void:
	if _spawner == null:
		return

	var score: int = _spawner.get("_score")
	var escaped: int = _spawner.get("_escaped")
	var max_esc: int = _spawner.get("max_escapes")

	if score > _high_score:
		_high_score = score

	_score_label.text = "SCORE  %d" % score
	_best_label.text = "BEST  %d" % _high_score
	_breach_bar.max_value = max_esc
	_breach_bar.value = escaped
	_breach_label.text = "BREACH  %d / %d" % [escaped, max_esc]

	if _player != null:
		var lives: int = _player.get("lives")
		if lives != _last_lives:
			_rebuild_lives(lives)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _state == "playing":
			_pause()
		elif _state == "paused":
			_resume()


# ---------------- State changes ----------------

func _show_menu() -> void:
	_state = "menu"
	_hide_all_panels()
	_menu_panel.visible = true
	get_tree().paused = true
	_set_spawner_active(false)
	_play_btn.grab_focus()


func _start_game() -> void:
	_state = "playing"
	_hide_all_panels()
	get_tree().paused = false
	_set_spawner_active(true)


func _pause() -> void:
	_state = "paused"
	_hide_all_panels()
	_pause_panel.visible = true
	get_tree().paused = true
	_set_spawner_active(false)
	_resume_btn.grab_focus()


func _resume() -> void:
	_state = "playing"
	_hide_all_panels()
	get_tree().paused = false
	_set_spawner_active(true)


func _restart() -> void:
	Engine.set_meta("skip_menu", true)
	get_tree().paused = false
	get_tree().reload_current_scene()


func _to_menu() -> void:
	Engine.set_meta("skip_menu", false)
	get_tree().paused = false
	get_tree().reload_current_scene()


func _quit() -> void:
	get_tree().quit()


func _on_game_over() -> void:
	_state = "over"
	# Any restart (including Space) skips the main menu
	Engine.set_meta("skip_menu", true)

	var score: int = _spawner.get("_score")
	if score > _high_score:
		_high_score = score
	_save_high_score()

	var reason: String = "Too many enemies got past you!"
	if _player != null:
		var lives: int = _player.get("lives")
		if lives <= 0:
			reason = "You were destroyed!"

	_over_text.text = "%s\n\nScore: %d\nBest: %d" % [reason, score, _high_score]
	_hide_all_panels()
	_over_panel.visible = true

	# Short delay so you don't restart by accident while still firing
	_restart_btn.disabled = true
	await get_tree().create_timer(1.0).timeout
	_restart_btn.disabled = false
	_restart_btn.grab_focus()


func _set_spawner_active(active: bool) -> void:
	if _spawner != null:
		_spawner.set_process(active)


func _hide_all_panels() -> void:
	_menu_panel.visible = false
	_pause_panel.visible = false
	_over_panel.visible = false


# ---------------- High score ----------------

func _load_high_score() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f != null:
			_high_score = f.get_32()


func _save_high_score() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_32(_high_score)


# ---------------- HUD ----------------

func _build_hud() -> void:
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	root.add_theme_constant_override("margin_left", 16)
	root.add_theme_constant_override("margin_right", 16)
	root.add_theme_constant_override("margin_top", 10)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(row)

	# Left side: score and best
	var left := VBoxContainer.new()
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(left)

	_score_label = Label.new()
	_score_label.add_theme_font_size_override("font_size", 28)
	left.add_child(_score_label)

	_best_label = Label.new()
	_best_label.add_theme_font_size_override("font_size", 18)
	_best_label.modulate = Color(1, 1, 1, 0.6)
	left.add_child(_best_label)

	# Middle spacer
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	# Right side: lives and breach bar
	var right := VBoxContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)

	_lives_box = HBoxContainer.new()
	_lives_box.alignment = BoxContainer.ALIGNMENT_END
	_lives_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(_lives_box)

	_breach_label = Label.new()
	_breach_label.add_theme_font_size_override("font_size", 16)
	_breach_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_breach_label)

	_breach_bar = ProgressBar.new()
	_breach_bar.custom_minimum_size = Vector2(180, 14)
	_breach_bar.show_percentage = false
	_breach_bar.min_value = 0
	_breach_bar.max_value = 3
	right.add_child(_breach_bar)


func _rebuild_lives(lives: int) -> void:
	_last_lives = lives
	for c in _lives_box.get_children():
		c.queue_free()

	var tex: Texture2D = null
	if _player != null:
		tex = _player.get("texture") as Texture2D

	for i in range(lives):
		if tex != null:
			var icon := TextureRect.new()
			icon.texture = tex
			icon.custom_minimum_size = Vector2(30, 30)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			_lives_box.add_child(icon)
		else:
			var box := ColorRect.new()
			box.color = Color(1, 0.3, 0.3)
			box.custom_minimum_size = Vector2(24, 24)
			_lives_box.add_child(box)


# ---------------- Panels ----------------

func _build_menu() -> Control:
	var overlay := _make_overlay()
	var box: VBoxContainer = overlay.get_node("Center/Box")

	_add_label(box, "SPACE SHOOTER", 56)
	_add_label(box, "Arrows: move    Space: fire    Esc: pause", 18)
	_add_spacer(box, 20)
	_play_btn = _add_button(box, "Play", _start_game)
	_add_button(box, "Quit", _quit)
	return overlay


func _build_pause() -> Control:
	var overlay := _make_overlay()
	var box: VBoxContainer = overlay.get_node("Center/Box")

	_add_label(box, "PAUSED", 48)
	_add_spacer(box, 20)
	_resume_btn = _add_button(box, "Resume", _resume)
	_add_button(box, "Restart", _restart)
	_add_button(box, "Main Menu", _to_menu)
	return overlay


func _build_game_over() -> Control:
	var overlay := _make_overlay()
	var box: VBoxContainer = overlay.get_node("Center/Box")

	_add_label(box, "GAME OVER", 56)
	_over_text = _add_label(box, "", 22)
	_add_spacer(box, 20)
	_restart_btn = _add_button(box, "Restart", _restart)
	_add_button(box, "Main Menu", _to_menu)
	return overlay


func _make_overlay() -> Control:
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	return overlay


func _add_label(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _add_spacer(parent: Node, height: float) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	parent.add_child(s)


func _add_button(parent: Node, text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, 50)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(callback)
	parent.add_child(b)
	return b
