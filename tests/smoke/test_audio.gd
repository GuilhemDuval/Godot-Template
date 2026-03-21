extends Control

const CATEGORY_MUSIC := 0
const CATEGORY_SFX := 1
const CATEGORY_UI := 2
const CATEGORY_AMBIENCE := 3

const BUS_NAMES := [AppConfig.BUS_MASTER, AppConfig.BUS_MUSIC, AppConfig.BUS_SFX, AppConfig.BUS_UI, AppConfig.BUS_AMBIENCE]

const TEST_SOUNDS := [
	{
		"id": &"music_chill",
		"path": "res://audio/music/Funky Chill 2 loop.wav",
		"category": CATEGORY_MUSIC,
		"base_volume_db": -6.0,
		"preload": true,
	},
	{
		"id": &"music_assault",
		"path": "res://audio/music/BRPG_Assault_Rhythm_Loop.wav",
		"category": CATEGORY_MUSIC,
		"base_volume_db": -8.0,
		"preload": true,
	},
	{
		"id": &"pause_theme",
		"path": "res://audio/music/Funky Chill 2 loop.wav",
		"category": CATEGORY_MUSIC,
		"base_volume_db": -14.0,
		"preload": true,
	},
	{
		"id": &"ambience_crowd",
		"path": "res://audio/ambience/background_crowd_people_chatter_loop_01.wav",
		"category": CATEGORY_AMBIENCE,
		"base_volume_db": -18.0,
		"preload": true,
	},
	{
		"id": &"ambience_hum",
		"path": "res://audio/ambience/background_room_interior_hum_loop_01.wav",
		"category": CATEGORY_AMBIENCE,
		"base_volume_db": -16.0,
		"preload": true,
	},
	{
		"id": &"ambience_wind",
		"path": "res://audio/ambience/wind_cold_howling_haunted_night_loop_01.wav",
		"category": CATEGORY_AMBIENCE,
		"base_volume_db": -15.0,
		"preload": true,
	},
	{
		"id": &"sfx_impact",
		"path": "res://audio/sfx/PP_Cute_Impact_1_2.wav",
		"category": CATEGORY_SFX,
		"base_volume_db": -8.0,
		"pitch_random": 0.04,
		"preload": true,
	},
	{
		"id": &"sfx_cat",
		"path": "res://audio/sfx/cat_2_meow_06.wav",
		"category": CATEGORY_SFX,
		"base_volume_db": -10.0,
		"pitch_random": 0.08,
		"preload": true,
	},
	{
		"id": &"ui_bubble",
		"path": "res://audio/ui/CGM3_Bubble_Button_01_1.wav",
		"category": CATEGORY_UI,
		"base_volume_db": -10.0,
		"preload": true,
	},
	{
		"id": &"ui_dialogue",
		"path": "res://audio/ui/CGM3_Dialogue_Text_01_1.wav",
		"category": CATEGORY_UI,
		"base_volume_db": -14.0,
		"preload": true,
	},
	{
		"id": &"ui_select",
		"path": "res://audio/ui/CGM3_Select_Button_01_4.wav",
		"category": CATEGORY_UI,
		"base_volume_db": -8.0,
		"preload": true,
	},
]

var _status_label: RichTextLabel
var _registry_label: RichTextLabel
var _log_label: RichTextLabel
var _music_fade_in_spin: SpinBox
var _music_fade_out_spin: SpinBox
var _pause_fade_in_spin: SpinBox
var _pause_fade_out_spin: SpinBox
var _bus_sliders: Dictionary = {}
var _bus_value_labels: Dictionary = {}
var _log_lines: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()

	if not _has_audio_manager():
		_append_log("ERROR: /root/AudioManager not found. Add AudioManager as an autoload before using this smoke test.")
		_update_status_panel()
		return

	_ensure_test_sounds_registered()
	_apply_default_fades_to_audio_manager()
	_connect_audio_signals()
	_refresh_registry_panel()
	_refresh_bus_sliders()
	_append_log("Audio smoke test ready.")
	_append_log("This scene registers a small sample library in AudioManager if missing.")
	_append_log("Use the ambience panel to layer several ambience loops together.")
	_append_log("Use the pause section to verify that main music and all ambience layers resume correctly.")
	_update_status_panel()


func _process(_delta: float) -> void:
	_update_status_panel()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_play_music(&"music_chill")
			KEY_2:
				_play_music(&"music_assault")
			KEY_3:
				_play_ambience(&"ambience_hum")
			KEY_4:
				_burst_sfx(&"sfx_impact", 8)
			KEY_5:
				_burst_ui(&"ui_select", 4)
			KEY_P:
				_pause_game_with_theme()
			KEY_R:
				_resume_game()
			KEY_S:
				_stop_all()


func _audio() -> Node:
	return get_node_or_null("/root/AudioManager")


func _has_audio_manager() -> bool:
	return _audio() != null


func _ensure_test_sounds_registered() -> void:
	var audio := _audio()
	if audio == null:
		return

	for entry in TEST_SOUNDS:
		var sound_id: StringName = entry["id"]
		if audio.has_sound(sound_id):
			continue

		var options := {
			"base_volume_db": float(entry.get("base_volume_db", 0.0)),
			"pitch_random": float(entry.get("pitch_random", 0.0)),
			"preload": bool(entry.get("preload", false)),
		}

		audio.register_sound(
			sound_id,
			String(entry["path"]),
			int(entry["category"]),
			options
		)

	audio.warmup_all()


func _connect_audio_signals() -> void:
	var audio := _audio()
	if audio == null:
		return

	if not audio.music_changed.is_connected(_on_music_changed):
		audio.music_changed.connect(_on_music_changed)

	if not audio.ambience_changed.is_connected(_on_ambience_changed):
		audio.ambience_changed.connect(_on_ambience_changed)

	if not audio.ambience_layers_changed.is_connected(_on_ambience_layers_changed):
		audio.ambience_layers_changed.connect(_on_ambience_layers_changed)

	if not audio.bus_volume_changed.is_connected(_on_bus_volume_changed):
		audio.bus_volume_changed.connect(_on_bus_volume_changed)

	if not audio.sound_missing.is_connected(_on_sound_missing):
		audio.sound_missing.connect(_on_sound_missing)


func _build_ui() -> void:
	var root_margin := MarginContainer.new()
	root_margin.process_mode = Node.PROCESS_MODE_ALWAYS
	root_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_margin.add_theme_constant_override("margin_left", 16)
	root_margin.add_theme_constant_override("margin_top", 16)
	root_margin.add_theme_constant_override("margin_right", 16)
	root_margin.add_theme_constant_override("margin_bottom", 16)
	add_child(root_margin)

	var split := HSplitContainer.new()
	split.process_mode = Node.PROCESS_MODE_ALWAYS
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 760
	root_margin.add_child(split)

	var left_scroll := ScrollContainer.new()
	left_scroll.process_mode = Node.PROCESS_MODE_ALWAYS
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(left_scroll)

	var left_column := VBoxContainer.new()
	left_column.process_mode = Node.PROCESS_MODE_ALWAYS
	left_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_column.add_theme_constant_override("separation", 12)
	left_scroll.add_child(left_column)

	var right_column := VBoxContainer.new()
	right_column.process_mode = Node.PROCESS_MODE_ALWAYS
	right_column.custom_minimum_size = Vector2(440.0, 0.0)
	right_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_column.add_theme_constant_override("separation", 12)
	split.add_child(right_column)

	left_column.add_child(_make_title_label(
		"AudioManager Smoke Test",
		"This scene is a hands-on dashboard for music, layered ambience, SFX, UI sounds, pause flow, bus volumes, and overlapping playback."
	))

	left_column.add_child(_build_keyboard_shortcuts_panel())
	left_column.add_child(_build_setup_panel())
	left_column.add_child(_build_music_panel())
	left_column.add_child(_build_pause_panel())
	left_column.add_child(_build_ambience_panel())
	left_column.add_child(_build_sfx_panel())
	left_column.add_child(_build_ui_panel())
	left_column.add_child(_build_stress_panel())
	left_column.add_child(_build_bus_panel())

	_status_label = RichTextLabel.new()
	_status_label.process_mode = Node.PROCESS_MODE_ALWAYS
	_status_label.fit_content = false
	_status_label.scroll_active = false
	_status_label.bbcode_enabled = false
	_status_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status_label.custom_minimum_size = Vector2(0.0, 260.0)
	right_column.add_child(_make_titled_box("Live status", _status_label))

	_registry_label = RichTextLabel.new()
	_registry_label.process_mode = Node.PROCESS_MODE_ALWAYS
	_registry_label.bbcode_enabled = false
	_registry_label.fit_content = false
	_registry_label.custom_minimum_size = Vector2(0.0, 280.0)
	_registry_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_column.add_child(_make_titled_box("Registered smoke test sounds", _registry_label, true))

	_log_label = RichTextLabel.new()
	_log_label.process_mode = Node.PROCESS_MODE_ALWAYS
	_log_label.bbcode_enabled = false
	_log_label.fit_content = false
	_log_label.custom_minimum_size = Vector2(0.0, 260.0)
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_column.add_child(_make_titled_box("Signal and action log", _log_label, true))


func _build_keyboard_shortcuts_panel() -> Control:
	var text := Label.new()
	text.process_mode = Node.PROCESS_MODE_ALWAYS
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.text = "Hotkeys: 1 chill music, 2 assault music, 3 hum ambience layer, 4 SFX burst, 5 UI burst, P pause game with pause music, R resume game, S stop all."
	return _make_titled_box("Quick shortcuts", text)


func _build_setup_panel() -> Control:
	var box := VBoxContainer.new()
	box.process_mode = Node.PROCESS_MODE_ALWAYS
	box.add_theme_constant_override("separation", 8)

	var info := Label.new()
	info.process_mode = Node.PROCESS_MODE_ALWAYS
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "Use this first section to register the sample sounds, warm them up, and reset the test state."
	box.add_child(info)

	var row_a := HBoxContainer.new()
	row_a.process_mode = Node.PROCESS_MODE_ALWAYS
	row_a.add_child(_make_button("Register sample sounds", _ensure_test_sounds_registered))
	row_a.add_child(_make_button("Warmup all", _warmup_all))
	row_a.add_child(_make_button("Refresh registry view", _refresh_registry_panel))
	box.add_child(row_a)

	var row_b := HBoxContainer.new()
	row_b.process_mode = Node.PROCESS_MODE_ALWAYS
	row_b.add_child(_make_button("Stop all", _stop_all))
	row_b.add_child(_make_button("Reset bus volumes to 1.0", _reset_bus_volumes))
	row_b.add_child(_make_button("Apply fade values", _apply_default_fades_to_audio_manager))
	box.add_child(row_b)

	var fades_row := HBoxContainer.new()
	fades_row.process_mode = Node.PROCESS_MODE_ALWAYS
	fades_row.add_child(_make_labeled_spinbox("Music fade in", 0.0, 4.0, 0.05, 0.6, func(spin): _music_fade_in_spin = spin))
	fades_row.add_child(_make_labeled_spinbox("Music fade out", 0.0, 4.0, 0.05, 0.6, func(spin): _music_fade_out_spin = spin))
	fades_row.add_child(_make_labeled_spinbox("Pause fade in", 0.0, 4.0, 0.05, 0.2, func(spin): _pause_fade_in_spin = spin))
	fades_row.add_child(_make_labeled_spinbox("Pause fade out", 0.0, 4.0, 0.05, 0.2, func(spin): _pause_fade_out_spin = spin))
	box.add_child(fades_row)

	return _make_titled_box("Setup and defaults", box)


func _build_music_panel() -> Control:
	var box := VBoxContainer.new()
	box.process_mode = Node.PROCESS_MODE_ALWAYS
	box.add_theme_constant_override("separation", 8)

	var info := Label.new()
	info.process_mode = Node.PROCESS_MODE_ALWAYS
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "Main music uses the regular music players. Switching tracks should crossfade. Replaying the same track without restart should keep it running."
	box.add_child(info)

	var row_a := HBoxContainer.new()
	row_a.process_mode = Node.PROCESS_MODE_ALWAYS
	row_a.add_child(_make_button("Play chill music", func(): _play_music(&"music_chill")))
	row_a.add_child(_make_button("Play assault music", func(): _play_music(&"music_assault")))
	row_a.add_child(_make_button("Restart chill music", func(): _play_music(&"music_chill", true)))
	box.add_child(row_a)

	var row_b := HBoxContainer.new()
	row_b.process_mode = Node.PROCESS_MODE_ALWAYS
	row_b.add_child(_make_button("Stop main music", _stop_music))
	row_b.add_child(_make_button("A -> B crossfade demo", _music_crossfade_demo))
	row_b.add_child(_make_button("B -> A crossfade demo", _music_crossfade_demo_reverse))
	box.add_child(row_b)

	return _make_titled_box("Main music", box)


func _build_pause_panel() -> Control:
	var box := VBoxContainer.new()
	box.process_mode = Node.PROCESS_MODE_ALWAYS
	box.add_theme_constant_override("separation", 8)

	var info := Label.new()
	info.process_mode = Node.PROCESS_MODE_ALWAYS
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "Pause music should not destroy the regular music state. The regular track and all ambience layers are paused, not restarted, and should resume from the same playback positions."
	box.add_child(info)

	var row_a := HBoxContainer.new()
	row_a.process_mode = Node.PROCESS_MODE_ALWAYS
	row_a.add_child(_make_button("Enter pause music only", _enter_pause_music))
	row_a.add_child(_make_button("Exit pause music only", _exit_pause_music))
	row_a.add_child(_make_button("Pause game without pause track", _pause_game_without_theme))
	box.add_child(row_a)

	var row_b := HBoxContainer.new()
	row_b.process_mode = Node.PROCESS_MODE_ALWAYS
	row_b.add_child(_make_button("Pause game with pause track", _pause_game_with_theme))
	row_b.add_child(_make_button("Resume game", _resume_game))
	row_b.add_child(_make_button("Resume paused ambience only", _resume_ambiences_only))
	box.add_child(row_b)

	return _make_titled_box("Pause flow", box)


func _build_ambience_panel() -> Control:
	var box := VBoxContainer.new()
	box.process_mode = Node.PROCESS_MODE_ALWAYS
	box.add_theme_constant_override("separation", 8)

	var info := Label.new()
	info.process_mode = Node.PROCESS_MODE_ALWAYS
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "Ambience now supports layering. Start several loops together, stop them individually, then verify they all pause and resume correctly."
	box.add_child(info)

	var row_a := HBoxContainer.new()
	row_a.process_mode = Node.PROCESS_MODE_ALWAYS
	row_a.add_child(_make_button("Play crowd layer", func(): _play_ambience(&"ambience_crowd")))
	row_a.add_child(_make_button("Play hum layer", func(): _play_ambience(&"ambience_hum")))
	row_a.add_child(_make_button("Play wind layer", func(): _play_ambience(&"ambience_wind")))
	box.add_child(row_a)

	var row_b := HBoxContainer.new()
	row_b.process_mode = Node.PROCESS_MODE_ALWAYS
	row_b.add_child(_make_button("Stop crowd", func(): _stop_ambience(&"ambience_crowd")))
	row_b.add_child(_make_button("Stop hum", func(): _stop_ambience(&"ambience_hum")))
	row_b.add_child(_make_button("Stop wind", func(): _stop_ambience(&"ambience_wind")))
	row_b.add_child(_make_button("Stop all ambience", _stop_all_ambiences))
	box.add_child(row_b)

	var row_c := HBoxContainer.new()
	row_c.process_mode = Node.PROCESS_MODE_ALWAYS
	row_c.add_child(_make_button("Play all ambience layers", _play_all_ambience_layers))
	row_c.add_child(_make_button("Music + layered ambience demo", _music_and_ambience_demo))
	row_c.add_child(_make_button("Pause ambience only", _pause_ambiences_only))
	box.add_child(row_c)

	return _make_titled_box("Layered ambience", box)


func _build_sfx_panel() -> Control:
	var box := VBoxContainer.new()
	box.process_mode = Node.PROCESS_MODE_ALWAYS
	box.add_theme_constant_override("separation", 8)

	var info := Label.new()
	info.process_mode = Node.PROCESS_MODE_ALWAYS
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "SFX use a small pool of players. Burst tests help you hear overlap and pool reuse."
	box.add_child(info)

	var row_a := HBoxContainer.new()
	row_a.process_mode = Node.PROCESS_MODE_ALWAYS
	row_a.add_child(_make_button("Impact once", func(): _play_sfx(&"sfx_impact")))
	row_a.add_child(_make_button("Cat once", func(): _play_sfx(&"sfx_cat")))
	row_a.add_child(_make_button("Impact x4", func(): _burst_sfx(&"sfx_impact", 4)))
	row_a.add_child(_make_button("Impact x12", func(): _burst_sfx(&"sfx_impact", 12)))
	box.add_child(row_a)

	var row_b := HBoxContainer.new()
	row_b.process_mode = Node.PROCESS_MODE_ALWAYS
	row_b.add_child(_make_button("Cat x4", func(): _burst_sfx(&"sfx_cat", 4)))
	row_b.add_child(_make_button("Mixed SFX burst", _mixed_sfx_burst))
	box.add_child(row_b)

	return _make_titled_box("SFX pool", box)


func _build_ui_panel() -> Control:
	var box := VBoxContainer.new()
	box.process_mode = Node.PROCESS_MODE_ALWAYS
	box.add_theme_constant_override("separation", 8)

	var info := Label.new()
	info.process_mode = Node.PROCESS_MODE_ALWAYS
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "UI sounds should remain distinct from gameplay SFX. Burst them separately to verify the UI pool and its bus."
	box.add_child(info)

	var row_a := HBoxContainer.new()
	row_a.process_mode = Node.PROCESS_MODE_ALWAYS
	row_a.add_child(_make_button("Bubble once", func(): _play_ui(&"ui_bubble")))
	row_a.add_child(_make_button("Dialogue once", func(): _play_ui(&"ui_dialogue")))
	row_a.add_child(_make_button("Select once", func(): _play_ui(&"ui_select")))
	box.add_child(row_a)

	var row_b := HBoxContainer.new()
	row_b.process_mode = Node.PROCESS_MODE_ALWAYS
	row_b.add_child(_make_button("Select x4", func(): _burst_ui(&"ui_select", 4)))
	row_b.add_child(_make_button("Dialogue x6", func(): _burst_ui(&"ui_dialogue", 6)))
	row_b.add_child(_make_button("Mixed UI combo", _mixed_ui_burst))
	box.add_child(row_b)

	return _make_titled_box("UI sound pool", box)


func _build_stress_panel() -> Control:
	var box := VBoxContainer.new()
	box.process_mode = Node.PROCESS_MODE_ALWAYS
	box.add_theme_constant_override("separation", 8)

	var info := Label.new()
	info.process_mode = Node.PROCESS_MODE_ALWAYS
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "These actions launch several categories together. They are useful to understand how music, layered ambience, SFX, and UI sounds coexist on separate buses and player pools."
	box.add_child(info)

	var row := HBoxContainer.new()
	row.process_mode = Node.PROCESS_MODE_ALWAYS
	row.add_child(_make_button("All categories demo", _all_categories_demo))
	row.add_child(_make_button("Heavy overlap demo", _heavy_overlap_demo))
	row.add_child(_make_button("Stop everything", _stop_all))
	box.add_child(row)

	return _make_titled_box("Stress and overlap tests", box)


func _build_bus_panel() -> Control:
	var box := VBoxContainer.new()
	box.process_mode = Node.PROCESS_MODE_ALWAYS
	box.add_theme_constant_override("separation", 8)

	var info := Label.new()
	info.process_mode = Node.PROCESS_MODE_ALWAYS
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "Bus sliders change the global family volume. Use them while sounds are already playing to understand the difference between per-sound balancing and bus mixing."
	box.add_child(info)

	for bus_name in BUS_NAMES:
		box.add_child(_make_bus_row(bus_name))

	return _make_titled_box("Audio buses", box)


func _make_title_label(title: String, subtitle: String) -> Control:
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


func _make_titled_box(title: String, content: Control, expand_vertical: bool = false) -> PanelContainer:
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


func _make_labeled_spinbox(
	label_text: String,
	min_value: float,
	max_value: float,
	step: float,
	default_value: float,
	on_created: Callable
) -> Control:
	var wrapper := VBoxContainer.new()
	wrapper.process_mode = Node.PROCESS_MODE_ALWAYS
	wrapper.custom_minimum_size = Vector2(150.0, 0.0)

	var label := Label.new()
	label.process_mode = Node.PROCESS_MODE_ALWAYS
	label.text = label_text
	wrapper.add_child(label)

	var spin := SpinBox.new()
	spin.process_mode = Node.PROCESS_MODE_ALWAYS
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = default_value
	spin.custom_minimum_size = Vector2(120.0, 0.0)
	wrapper.add_child(spin)

	on_created.call(spin)
	return wrapper


func _make_bus_row(bus_name: StringName) -> Control:
	var row := HBoxContainer.new()
	row.process_mode = Node.PROCESS_MODE_ALWAYS
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)

	var label := Label.new()
	label.process_mode = Node.PROCESS_MODE_ALWAYS
	label.text = String(bus_name)
	label.custom_minimum_size = Vector2(90.0, 0.0)
	row.add_child(label)

	var slider := HSlider.new()
	slider.process_mode = Node.PROCESS_MODE_ALWAYS
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)

	var value_label := Label.new()
	value_label.process_mode = Node.PROCESS_MODE_ALWAYS
	value_label.text = "1.00"
	value_label.custom_minimum_size = Vector2(44.0, 0.0)
	row.add_child(value_label)

	var mute_button := Button.new()
	mute_button.process_mode = Node.PROCESS_MODE_ALWAYS
	mute_button.text = "Mute"
	mute_button.pressed.connect(func(): _set_bus_volume(bus_name, 0.0))
	row.add_child(mute_button)

	var full_button := Button.new()
	full_button.process_mode = Node.PROCESS_MODE_ALWAYS
	full_button.text = "1.0"
	full_button.pressed.connect(func(): _set_bus_volume(bus_name, 1.0))
	row.add_child(full_button)

	slider.value_changed.connect(_on_bus_slider_changed.bind(bus_name, value_label))

	_bus_sliders[bus_name] = slider
	_bus_value_labels[bus_name] = value_label
	return row


func _apply_default_fades_to_audio_manager() -> void:
	var audio := _audio()
	if audio == null:
		return

	audio.set_default_music_fades(_music_fade_in_spin.value, _music_fade_out_spin.value)
	audio.set_default_pause_music_fades(_pause_fade_in_spin.value, _pause_fade_out_spin.value)
	_append_log(
		"Applied fade defaults: music in %.2f / out %.2f, pause in %.2f / out %.2f"
		% [_music_fade_in_spin.value, _music_fade_out_spin.value, _pause_fade_in_spin.value, _pause_fade_out_spin.value]
	)


func _refresh_registry_panel() -> void:
	var lines: Array[String] = []
	lines.append("Expected sample library used by this smoke test:\n")

	for entry in TEST_SOUNDS:
		lines.append(
			"- %s | %s | base %.1f dB | %s"
			% [
				String(entry["id"]),
				_category_name(int(entry["category"])),
				float(entry.get("base_volume_db", 0.0)),
				String(entry["path"]),
			]
		)

	_registry_label.text = "\n".join(lines)


func _refresh_bus_sliders() -> void:
	var audio := _audio()
	if audio == null:
		return

	for bus_name in BUS_NAMES:
		if not _bus_sliders.has(bus_name):
			continue

		var value := float(audio.get_bus_volume_linear(bus_name))
		var slider: HSlider = _bus_sliders[bus_name]
		var label: Label = _bus_value_labels[bus_name]
		slider.set_value_no_signal(value)
		label.text = "%.2f" % value


func _update_status_panel() -> void:
	if _status_label == null:
		return

	var audio := _audio()
	if audio == null:
		_status_label.text = "AudioManager not found at /root/AudioManager.\n\nAdd it as an autoload first."
		return

	var ambience_ids: Array[StringName] = audio.get_current_ambience_ids()
	var ambience_texts: Array[String] = []
	for sound_id in ambience_ids:
		ambience_texts.append(String(sound_id))

	var ambience_display := "[none]"
	if not ambience_texts.is_empty():
		ambience_display = "[" + ", ".join(ambience_texts) + "]"

	var lines: Array[String] = []
	lines.append("Tree paused: %s" % str(get_tree().paused))
	lines.append("Current main music id: %s" % String(audio.get_current_music_id()))
	lines.append("Pause music active: %s" % str(audio.is_pause_music_active()))
	lines.append("Current pause music id: %s" % String(audio.get_pause_music_id()))
	lines.append("Current ambience ids: %s" % ambience_display)
	lines.append("Ambience layer count: %d" % ambience_ids.size())
	lines.append("")
	lines.append("What to verify:")
	lines.append("1. Switch between the two main music tracks and listen for crossfades.")
	lines.append("2. Start several ambience loops together and stop them independently.")
	lines.append("3. Trigger SFX and UI bursts to hear overlap and pool reuse.")
	lines.append("4. Pause the game with pause music, then resume and confirm that the original music and ambience layers continue instead of restarting.")
	lines.append("5. Change bus sliders while sounds are already playing.")

	_status_label.text = "\n".join(lines)


func _append_log(message: String) -> void:
	var timestamp := Time.get_time_string_from_system()
	_log_lines.append("[%s] %s" % [timestamp, message])

	while _log_lines.size() > 50:
		_log_lines.remove_at(0)

	if _log_label != null:
		_log_label.text = "\n".join(_log_lines)
		_log_label.scroll_to_line(max(_log_lines.size() - 1, 0))


func _category_name(category: int) -> String:
	match category:
		CATEGORY_MUSIC:
			return "MUSIC"
		CATEGORY_SFX:
			return "SFX"
		CATEGORY_UI:
			return "UI"
		CATEGORY_AMBIENCE:
			return "AMBIENCE"
		_:
			return "UNKNOWN"


func _play_music(sound_id: StringName, restart: bool = false) -> void:
	var audio := _audio()
	if audio == null:
		return

	_apply_default_fades_to_audio_manager()
	audio.play_music(
		sound_id,
		restart,
		0.0,
		0.0,
		_music_fade_in_spin.value,
		_music_fade_out_spin.value
	)
	_append_log("Requested main music: %s" % String(sound_id))


func _stop_music() -> void:
	var audio := _audio()
	if audio == null:
		return

	audio.stop_music(_music_fade_out_spin.value)
	_append_log("Requested main music stop.")


func _enter_pause_music() -> void:
	var audio := _audio()
	if audio == null:
		return

	_apply_default_fades_to_audio_manager()
	audio.enter_pause_music(&"pause_theme", _pause_fade_in_spin.value)
	_append_log("Entered pause music overlay.")


func _exit_pause_music() -> void:
	var audio := _audio()
	if audio == null:
		return

	audio.exit_pause_music(_pause_fade_out_spin.value, true)
	_append_log("Exited pause music overlay and requested resume of main music and ambience layers.")


func _pause_game_without_theme() -> void:
	var audio := _audio()
	if audio == null:
		return

	audio.pause_game(&"", _pause_fade_in_spin.value)
	_append_log("Paused the tree without a dedicated pause track.")


func _pause_game_with_theme() -> void:
	var audio := _audio()
	if audio == null:
		return

	_apply_default_fades_to_audio_manager()
	audio.pause_game(&"pause_theme", _pause_fade_in_spin.value)
	_append_log("Paused the tree with pause music.")


func _resume_game() -> void:
	var audio := _audio()
	if audio == null:
		return

	audio.resume_game(_pause_fade_out_spin.value)
	_append_log("Resumed the tree and exited pause music.")


func _pause_ambiences_only() -> void:
	var audio := _audio()
	if audio == null:
		return

	audio.pause_ambiences()
	_append_log("Paused active ambience layers only.")


func _resume_ambiences_only() -> void:
	var audio := _audio()
	if audio == null:
		return

	audio.resume_ambiences()
	_append_log("Resumed paused ambience layers only.")


func _play_ambience(sound_id: StringName) -> void:
	var audio := _audio()
	if audio == null:
		return

	audio.play_ambience(sound_id)
	_append_log("Requested ambience layer: %s" % String(sound_id))


func _stop_ambience(sound_id: StringName) -> void:
	var audio := _audio()
	if audio == null:
		return

	audio.stop_ambience(sound_id)
	_append_log("Requested stop for ambience layer: %s" % String(sound_id))


func _stop_all_ambiences() -> void:
	var audio := _audio()
	if audio == null:
		return

	audio.stop_all_ambiences()
	_append_log("Requested stop for all ambience layers.")


func _play_all_ambience_layers() -> void:
	_play_ambience(&"ambience_crowd")
	_play_ambience(&"ambience_hum")
	_play_ambience(&"ambience_wind")
	_append_log("Started all ambience layers.")


func _play_sfx(sound_id: StringName) -> void:
	var audio := _audio()
	if audio == null:
		return

	audio.play_sfx(sound_id)
	_append_log("Played SFX once: %s" % String(sound_id))


func _play_ui(sound_id: StringName) -> void:
	var audio := _audio()
	if audio == null:
		return

	audio.play_ui(sound_id)
	_append_log("Played UI sound once: %s" % String(sound_id))


func _burst_sfx(sound_id: StringName, count: int) -> void:
	var audio := _audio()
	if audio == null:
		return

	for i in range(count):
		audio.play_sfx(sound_id, 0.0, 1.0 + float(i) * 0.02)

	_append_log("Played SFX burst: %s x%d" % [String(sound_id), count])


func _burst_ui(sound_id: StringName, count: int) -> void:
	var audio := _audio()
	if audio == null:
		return

	for i in range(count):
		audio.play_ui(sound_id, 0.0, 1.0 + float(i) * 0.01)

	_append_log("Played UI burst: %s x%d" % [String(sound_id), count])


func _mixed_sfx_burst() -> void:
	var audio := _audio()
	if audio == null:
		return

	for i in range(6):
		if i % 2 == 0:
			audio.play_sfx(&"sfx_impact", 0.0, 1.0 + float(i) * 0.02)
		else:
			audio.play_sfx(&"sfx_cat", 0.0, 1.0 + float(i) * 0.03)

	_append_log("Played mixed SFX burst.")


func _mixed_ui_burst() -> void:
	var audio := _audio()
	if audio == null:
		return

	audio.play_ui(&"ui_bubble")
	audio.play_ui(&"ui_dialogue")
	audio.play_ui(&"ui_select")
	audio.play_ui(&"ui_dialogue")
	_append_log("Played mixed UI combo.")


func _music_crossfade_demo() -> void:
	_play_music(&"music_chill")
	_play_music(&"music_assault")
	_append_log("Triggered chill -> assault crossfade demo.")


func _music_crossfade_demo_reverse() -> void:
	_play_music(&"music_assault")
	_play_music(&"music_chill")
	_append_log("Triggered assault -> chill crossfade demo.")


func _music_and_ambience_demo() -> void:
	_play_music(&"music_chill")
	_play_ambience(&"ambience_hum")
	_play_ambience(&"ambience_wind")
	_append_log("Started a combined music + layered ambience demo.")


func _all_categories_demo() -> void:
	_play_music(&"music_chill")
	_play_ambience(&"ambience_crowd")
	_play_ambience(&"ambience_hum")
	_burst_sfx(&"sfx_impact", 4)
	_burst_ui(&"ui_select", 3)
	_append_log("Started all-categories demo.")


func _heavy_overlap_demo() -> void:
	_play_music(&"music_assault")
	_play_ambience(&"ambience_crowd")
	_play_ambience(&"ambience_hum")
	_play_ambience(&"ambience_wind")
	_burst_sfx(&"sfx_impact", 12)
	_burst_sfx(&"sfx_cat", 6)
	_burst_ui(&"ui_dialogue", 6)
	_burst_ui(&"ui_select", 4)
	_append_log("Started heavy overlap demo.")


func _stop_all() -> void:
	var audio := _audio()
	if audio == null:
		return

	audio.stop_all()
	get_tree().paused = false
	_append_log("Stopped all audio and unpaused the tree.")


func _warmup_all() -> void:
	var audio := _audio()
	if audio == null:
		return

	audio.warmup_all()
	_append_log("Warmup requested for all registered sounds.")


func _reset_bus_volumes() -> void:
	for bus_name in BUS_NAMES:
		_set_bus_volume(bus_name, 1.0)

	_append_log("Reset all bus volumes to 1.0.")


func _set_bus_volume(bus_name: StringName, value: float) -> void:
	var audio := _audio()
	if audio == null:
		return

	audio.set_bus_volume_linear(bus_name, value)
	_refresh_bus_sliders()


func _on_bus_slider_changed(value: float, bus_name: StringName, value_label: Label) -> void:
	value_label.text = "%.2f" % value
	_set_bus_volume(bus_name, value)


func _on_music_changed(previous_id: StringName, new_id: StringName) -> void:
	_append_log("Signal music_changed: %s -> %s" % [String(previous_id), String(new_id)])


func _on_ambience_changed(previous_ids: Array, new_ids: Array) -> void:
	_append_log("Signal ambience_changed: %s -> %s" % [_array_to_string(previous_ids), _array_to_string(new_ids)])


func _on_ambience_layers_changed(active_ids: Array) -> void:
	_append_log("Signal ambience_layers_changed: %s" % _array_to_string(active_ids))


func _on_bus_volume_changed(bus_name: StringName, linear_value: float, db_value: float) -> void:
	_append_log("Signal bus_volume_changed: %s = %.2f (%.2f dB)" % [String(bus_name), linear_value, db_value])
	_refresh_bus_sliders()


func _on_sound_missing(sound_id: StringName, path: String) -> void:
	_append_log("Signal sound_missing: %s at %s" % [String(sound_id), path])


func _array_to_string(values: Array) -> String:
	var texts: Array[String] = []
	for value in values:
		texts.append(String(value))
	return "[" + ", ".join(texts) + "]"
