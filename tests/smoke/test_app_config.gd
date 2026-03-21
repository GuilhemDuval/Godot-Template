extends Control

var _status_label: RichTextLabel
var _log_label: RichTextLabel
var _log_lines: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_append_log("AppConfig smoke test ready.")
	_refresh_status()


func _process(_delta: float) -> void:
	_refresh_status()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F11:
				_on_toggle_fullscreen_pressed()
			KEY_ESCAPE:
				_on_quit_pressed()


func _build_ui() -> void:
	var root_margin := MarginContainer.new()
	root_margin.process_mode = Node.PROCESS_MODE_ALWAYS
	root_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_margin.add_theme_constant_override("margin_left", 20)
	root_margin.add_theme_constant_override("margin_top", 20)
	root_margin.add_theme_constant_override("margin_right", 20)
	root_margin.add_theme_constant_override("margin_bottom", 20)
	add_child(root_margin)

	var column := VBoxContainer.new()
	column.process_mode = Node.PROCESS_MODE_ALWAYS
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	root_margin.add_child(column)

	column.add_child(_make_title_box(
		"AppConfig Smoke Test",
		"This scene lets you test the tiny app-level helpers exposed by AppConfig: windowed mode, fullscreen mode, fullscreen toggle, level path helper, and quit."
	))

	column.add_child(_build_actions_panel())
	column.add_child(_build_info_panel())
	column.add_child(_build_log_panel())


func _build_actions_panel() -> Control:
	var box := VBoxContainer.new()
	box.process_mode = Node.PROCESS_MODE_ALWAYS
	box.add_theme_constant_override("separation", 8)

	var info := Label.new()
	info.process_mode = Node.PROCESS_MODE_ALWAYS
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "Use the buttons to apply AppConfig helpers directly. F11 toggles fullscreen. Escape calls quit_game()."
	box.add_child(info)

	var row_a := HBoxContainer.new()
	row_a.process_mode = Node.PROCESS_MODE_ALWAYS
	row_a.add_child(_make_button("Set windowed", _on_set_windowed_pressed))
	row_a.add_child(_make_button("Set fullscreen", _on_set_fullscreen_pressed))
	row_a.add_child(_make_button("Toggle fullscreen", _on_toggle_fullscreen_pressed))
	box.add_child(row_a)

	var row_b := HBoxContainer.new()
	row_b.process_mode = Node.PROCESS_MODE_ALWAYS
	row_b.add_child(_make_button("Refresh status", _refresh_status))
	row_b.add_child(_make_button("Print default level path", _on_print_level_path_pressed))
	row_b.add_child(_make_button("Quit game", _on_quit_pressed))
	box.add_child(row_b)

	return _make_panel("Actions", box)


func _build_info_panel() -> Control:
	_status_label = RichTextLabel.new()
	_status_label.process_mode = Node.PROCESS_MODE_ALWAYS
	_status_label.bbcode_enabled = false
	_status_label.fit_content = false
	_status_label.scroll_active = false
	_status_label.custom_minimum_size = Vector2(0.0, 220.0)
	return _make_panel("Live status", _status_label)


func _build_log_panel() -> Control:
	_log_label = RichTextLabel.new()
	_log_label.process_mode = Node.PROCESS_MODE_ALWAYS
	_log_label.bbcode_enabled = false
	_log_label.fit_content = false
	_log_label.custom_minimum_size = Vector2(0.0, 260.0)
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return _make_panel("Action log", _log_label, true)


func _make_title_box(title: String, subtitle: String) -> Control:
	var wrapper := VBoxContainer.new()
	wrapper.process_mode = Node.PROCESS_MODE_ALWAYS
	wrapper.add_theme_constant_override("separation", 6)

	var title_label := Label.new()
	title_label.process_mode = Node.PROCESS_MODE_ALWAYS
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 24)
	wrapper.add_child(title_label)

	var subtitle_label := Label.new()
	subtitle_label.process_mode = Node.PROCESS_MODE_ALWAYS
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_label.text = subtitle
	wrapper.add_child(subtitle_label)

	return wrapper


func _make_panel(title: String, content: Control, expand_vertical: bool = false) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if expand_vertical:
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.process_mode = Node.PROCESS_MODE_ALWAYS
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.process_mode = Node.PROCESS_MODE_ALWAYS
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var label := Label.new()
	label.process_mode = Node.PROCESS_MODE_ALWAYS
	label.text = title
	label.add_theme_font_size_override("font_size", 18)
	box.add_child(label)

	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if expand_vertical:
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(content)

	return panel


func _make_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 36.0)
	button.pressed.connect(callback)
	return button


func _refresh_status() -> void:
	if _status_label == null:
		return

	var lines: Array[String] = []
	lines.append("Running on web: %s" % str(AppConfig.is_web()))
	lines.append("Can request fullscreen: %s" % str(AppConfig.can_request_fullscreen()))
	lines.append("Current window mode enum: %s" % _window_mode_name(AppConfig.get_window_mode()))
	lines.append("Is fullscreen: %s" % str(AppConfig.is_fullscreen()))
	lines.append("Default window mode enum: %s" % _window_mode_name(AppConfig.DEFAULT_WINDOW_MODE))
	lines.append("")
	lines.append("Shared groups:")
	lines.append("- %s" % String(AppConfig.GROUP_PLAYER))
	lines.append("- %s" % String(AppConfig.GROUP_ENEMY))
	lines.append("- %s" % String(AppConfig.GROUP_INTERACTABLE))
	lines.append("- %s" % String(AppConfig.GROUP_DAMAGEABLE))
	lines.append("- %s" % String(AppConfig.GROUP_PAUSABLE))
	lines.append("")
	lines.append("Shared audio buses:")
	lines.append("- %s" % String(AppConfig.BUS_MASTER))
	lines.append("- %s" % String(AppConfig.BUS_MUSIC))
	lines.append("- %s" % String(AppConfig.BUS_SFX))
	lines.append("- %s" % String(AppConfig.BUS_UI))
	lines.append("- %s" % String(AppConfig.BUS_AMBIENCE))
	lines.append("")
	lines.append("Default level id: %s" % String(AppConfig.DEFAULT_LEVEL_ID))
	lines.append("Default level path: %s" % AppConfig.level_scene_path(AppConfig.DEFAULT_LEVEL_ID))

	_status_label.text = "\n".join(lines)


func _append_log(message: String) -> void:
	var timestamp := Time.get_time_string_from_system()
	_log_lines.append("[%s] %s" % [timestamp, message])

	while _log_lines.size() > 40:
		_log_lines.remove_at(0)

	if _log_label != null:
		_log_label.text = "\n".join(_log_lines)
		_log_label.scroll_to_line(max(_log_lines.size() - 1, 0))


func _window_mode_name(mode: int) -> String:
	match mode:
		AppConfig.WindowMode.WINDOWED:
			return "WINDOWED"
		AppConfig.WindowMode.FULLSCREEN:
			return "FULLSCREEN"
		_:
			return "UNKNOWN"


func _on_set_windowed_pressed() -> void:
	AppConfig.set_window_mode(AppConfig.WindowMode.WINDOWED)
	_append_log("Requested windowed mode.")
	_refresh_status()


func _on_set_fullscreen_pressed() -> void:
	AppConfig.set_window_mode(AppConfig.WindowMode.FULLSCREEN)
	_append_log("Requested fullscreen mode.")
	_refresh_status()


func _on_toggle_fullscreen_pressed() -> void:
	AppConfig.toggle_fullscreen()
	_append_log("Requested fullscreen toggle.")
	_refresh_status()


func _on_print_level_path_pressed() -> void:
	var path := AppConfig.level_scene_path(AppConfig.DEFAULT_LEVEL_ID)
	_append_log("Default level path: %s" % path)
	_refresh_status()


func _on_quit_pressed() -> void:
	_append_log("Quit requested through AppConfig.quit_game().")
	AppConfig.quit_game()
