extends Control

# DialogueBridge smoke test
#
# Goal:
# - manually test DialogueBridge.start_dialogue(...)
# - observe how DialogueBridge affects StateManager, InputRouter and SessionManager
# - expose simple context methods that can be called from dialogue files
# - demonstrate audio calls through AudioManager
# - show the current dialogue phase: line, choice, opening or none
#
# Important:
# - this scene expects DialogueBridge, InputRouter, StateManager, SessionManager and AudioManager
#   to be available as autoloads
# - this scene also expects the Dialogue Manager plugin to be enabled
# - the dialogue file is loaded at runtime instead of preloaded, to avoid parse-time issues

const TEST_DIALOGUE_PATH := "res://data/dialogues/tests/dialogue_bridge_smoke_main.dialogue"

const CATEGORY_MUSIC := 0
const CATEGORY_SFX := 1
const CATEGORY_UI := 2

const CONTEXT_KEY := &"dialogue_smoke"

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
		"id": &"ui_select",
		"path": "res://audio/ui/CGM3_Select_Button_01_4.wav",
		"category": CATEGORY_UI,
		"base_volume_db": -8.0,
		"preload": true,
	},
]

var _test_dialogue: DialogueResource = null

var _status_label: RichTextLabel
var _log_label: RichTextLabel
var _context_message_label: Label
var _mood_label: Label
var _phase_label: Label
var _color_panel: ColorRect

var _log_lines: Array[String] = []
var _current_mood: String = "neutral"
var demo_mood: String = "neutral"
var _dialogue_phase: String = "none"
var _dialogue_has_choices: bool = false
var _color_cycle_index: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_test_dialogue = load(TEST_DIALOGUE_PATH) as DialogueResource
	if _test_dialogue == null:
		push_error("Failed to load dialogue resource at: %s" % TEST_DIALOGUE_PATH)
		return

	_ensure_session()
	_ensure_test_sounds_registered()
	_build_test_scene()
	_connect_bridge_signals()

	DialogueBridge.register_context_node(CONTEXT_KEY, self)

	_append_log("DialogueBridge smoke test ready.")
	_append_log("Dialogue resource loaded from: %s" % TEST_DIALOGUE_PATH)
	_append_log("Use the buttons or hotkeys to start and stop dialogues.")
	_refresh_status_panel()


func _exit_tree() -> void:
	if DialogueBridge != null:
		DialogueBridge.unregister_context_node(CONTEXT_KEY)


func _process(_delta: float) -> void:
	_refresh_status_panel()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_start_main_dialogue()
			KEY_2:
				_start_alt_dialogue()
			KEY_3:
				_cancel_dialogue()
			KEY_R:
				_reset_smoke_data()
			KEY_M:
				play_demo_music()
			KEY_N:
				stop_demo_audio()
			KEY_F:
				play_demo_sfx()
			KEY_U:
				play_demo_ui()


func _ensure_session() -> void:
	if SessionManager.has_method("has_session") and SessionManager.has_method("start_new_session"):
		if not SessionManager.has_session():
			SessionManager.start_new_session(AppConfig.DEFAULT_LEVEL_ID)


func _build_test_scene() -> void:
	var root_margin := MarginContainer.new()
	root_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_margin.add_theme_constant_override("margin_left", 16)
	root_margin.add_theme_constant_override("margin_top", 16)
	root_margin.add_theme_constant_override("margin_right", 16)
	root_margin.add_theme_constant_override("margin_bottom", 16)
	add_child(root_margin)

	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 12)
	root_margin.add_child(layout)

	var title := Label.new()
	title.text = "DialogueBridge Smoke Test"
	title.add_theme_font_size_override("font_size", 24)
	layout.add_child(title)

	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = "Hotkeys: 1 start main dialogue, 2 start alt label, 3 cancel dialogue, R reset smoke data, M play music, N stop audio, F play SFX, U play UI."
	layout.add_child(help)

	var buttons_row_a := HBoxContainer.new()
	buttons_row_a.add_child(_make_button("Start main dialogue", _start_main_dialogue))
	buttons_row_a.add_child(_make_button("Start alt label", _start_alt_dialogue))
	buttons_row_a.add_child(_make_button("Cancel active dialogue", _cancel_dialogue))
	layout.add_child(buttons_row_a)

	var buttons_row_b := HBoxContainer.new()
	buttons_row_b.add_child(_make_button("Reset smoke data", _reset_smoke_data))
	buttons_row_b.add_child(_make_button("Play music", play_demo_music))
	buttons_row_b.add_child(_make_button("Stop audio", stop_demo_audio))
	buttons_row_b.add_child(_make_button("Play SFX", play_demo_sfx))
	buttons_row_b.add_child(_make_button("Play UI", play_demo_ui))
	layout.add_child(buttons_row_b)

	var context_panel := PanelContainer.new()
	context_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(context_panel)

	var context_margin := MarginContainer.new()
	context_margin.add_theme_constant_override("margin_left", 10)
	context_margin.add_theme_constant_override("margin_top", 10)
	context_margin.add_theme_constant_override("margin_right", 10)
	context_margin.add_theme_constant_override("margin_bottom", 10)
	context_panel.add_child(context_margin)

	var context_box := VBoxContainer.new()
	context_box.add_theme_constant_override("separation", 8)
	context_margin.add_child(context_box)

	var context_title := Label.new()
	context_title.text = "Context feedback area"
	context_title.add_theme_font_size_override("font_size", 18)
	context_box.add_child(context_title)

	_context_message_label = Label.new()
	_context_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_context_message_label.text = "No context action triggered yet."
	context_box.add_child(_context_message_label)

	_mood_label = Label.new()
	_mood_label.text = "Current mood: neutral"
	context_box.add_child(_mood_label)

	_phase_label = Label.new()
	_phase_label.text = "Dialogue phase: none"
	context_box.add_child(_phase_label)

	_color_panel = ColorRect.new()
	_color_panel.custom_minimum_size = Vector2(0.0, 60.0)
	_color_panel.color = Color(0.18, 0.18, 0.22, 1.0)
	context_box.add_child(_color_panel)

	_status_label = RichTextLabel.new()
	_status_label.fit_content = false
	_status_label.scroll_active = false
	_status_label.custom_minimum_size = Vector2(0.0, 240.0)
	layout.add_child(_wrap_panel("Live status", _status_label))

	_log_label = RichTextLabel.new()
	_log_label.fit_content = false
	_log_label.custom_minimum_size = Vector2(0.0, 260.0)
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(_wrap_panel("Log", _log_label, true))


func _make_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 36.0)
	button.button_down.connect(callback)
	return button


func _wrap_panel(title_text: String, content: Control, expand_vertical: bool = false) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if expand_vertical:
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)

	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if expand_vertical:
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(content)

	return panel


func _connect_bridge_signals() -> void:
	if not DialogueBridge.dialogue_started.is_connected(_on_dialogue_started):
		DialogueBridge.dialogue_started.connect(_on_dialogue_started)

	if not DialogueBridge.dialogue_finished.is_connected(_on_dialogue_finished):
		DialogueBridge.dialogue_finished.connect(_on_dialogue_finished)

	if not DialogueBridge.dialogue_start_rejected.is_connected(_on_dialogue_start_rejected):
		DialogueBridge.dialogue_start_rejected.connect(_on_dialogue_start_rejected)

	if not DialogueBridge.dialogue_phase_changed.is_connected(_on_dialogue_phase_changed):
		DialogueBridge.dialogue_phase_changed.connect(_on_dialogue_phase_changed)


func _start_main_dialogue() -> void:
	if _test_dialogue == null:
		_append_log("Cannot start main dialogue: test dialogue resource is missing.")
		return

	var started := DialogueBridge.start_dialogue(_test_dialogue, "start")
	_append_log("Requested main dialogue start: %s" % str(started))


func _start_alt_dialogue() -> void:
	if _test_dialogue == null:
		_append_log("Cannot start alt dialogue: test dialogue resource is missing.")
		return

	var started := DialogueBridge.start_dialogue(_test_dialogue, "alt_start")
	_append_log("Requested alt dialogue start: %s" % str(started))


func _cancel_dialogue() -> void:
	DialogueBridge.stop_dialogue()
	_dialogue_phase = "none"
	_dialogue_has_choices = false
	_update_phase_label()
	_append_log("Requested active dialogue cancellation.")


func _reset_smoke_data() -> void:
	SessionManager.clear_flag("dialogue/tutorial_seen")
	SessionManager.clear_flag("dialogue/has_test_key")
	SessionManager.clear_flag("dialogue/import_seen")
	SessionManager.clear_flag("dialogue/demo_key")
	SessionManager.clear_data("dialogue/player_name")
	SessionManager.clear_data("dialogue/visit_count")
	SessionManager.clear_data("dialogue/last_choice")
	SessionManager.clear_data("dialogue/demo_counter")
	SessionManager.clear_data("dialogue/demo_branch")
	SessionManager.clear_data("dialogue/demo_note")

	set_context_message("Smoke data reset.")
	set_mood("neutral")
	set_demo_color("neutral")

	demo_mood = "neutral"
	_dialogue_phase = "none"
	_dialogue_has_choices = false
	_color_cycle_index = 0
	_update_phase_label()

	_append_log("Smoke dialogue data has been reset.")


func _refresh_status_panel() -> void:
	if _status_label == null:
		return

	var state_name := GameStates.get_state_name(StateManager.get_state())

	var lines: Array[String] = []
	lines.append("Dialogue resource loaded: %s" % str(_test_dialogue != null))
	lines.append("DialogueBridge.has_active_dialogue = %s" % str(DialogueBridge.has_active_dialogue()))
	lines.append("Dialogue phase = %s" % _dialogue_phase)
	lines.append("Dialogue phase has choices = %s" % str(_dialogue_has_choices))
	lines.append("StateManager.current_state = %s" % state_name)
	lines.append("StateManager.is_paused = %s" % str(StateManager.is_paused))
	lines.append("InputRouter.FLAG_DIALOGUE_ACTIVE = %s" % str(InputRouter.get_flag(InputRouter.FLAG_DIALOGUE_ACTIVE)))
	lines.append("InputRouter.FLAG_CINEMATIC_ACTIVE = %s" % str(InputRouter.get_flag(InputRouter.FLAG_CINEMATIC_ACTIVE)))
	lines.append("")
	lines.append("Session-backed smoke data:")
	lines.append("dialogue/tutorial_seen = %s" % str(SessionManager.get_flag("dialogue/tutorial_seen", false)))
	lines.append("dialogue/has_test_key = %s" % str(SessionManager.get_flag("dialogue/has_test_key", false)))
	lines.append("dialogue/import_seen = %s" % str(SessionManager.get_flag("dialogue/import_seen", false)))
	lines.append("dialogue/demo_key = %s" % str(SessionManager.get_flag("dialogue/demo_key", false)))
	lines.append("dialogue/player_name = %s" % str(SessionManager.get_data("dialogue/player_name", "Hero")))
	lines.append("dialogue/visit_count = %s" % str(SessionManager.get_data("dialogue/visit_count", 0)))
	lines.append("dialogue/last_choice = %s" % str(SessionManager.get_data("dialogue/last_choice", "")))
	lines.append("dialogue/demo_counter = %s" % str(SessionManager.get_data("dialogue/demo_counter", 0)))
	lines.append("dialogue/demo_branch = %s" % str(SessionManager.get_data("dialogue/demo_branch", "")))
	lines.append("dialogue/demo_note = %s" % str(SessionManager.get_data("dialogue/demo_note", "")))
	lines.append("")
	lines.append("Current mood = %s" % _current_mood)

	_status_label.text = "\n".join(lines)


func _append_log(message: String) -> void:
	var timestamp := Time.get_time_string_from_system()
	_log_lines.append("[%s] %s" % [timestamp, message])

	while _log_lines.size() > 50:
		_log_lines.remove_at(0)

	if _log_label != null:
		_log_label.text = "\n".join(_log_lines)
		_log_label.scroll_to_line(max(_log_lines.size() - 1, 0))


func _update_phase_label() -> void:
	if _phase_label == null:
		return

	var suffix := "line"
	if _dialogue_phase == "choice":
		suffix = "choice"
	elif _dialogue_phase == "opening":
		suffix = "opening"
	elif _dialogue_phase == "none":
		suffix = "none"

	_phase_label.text = "Dialogue phase: %s" % suffix


func _on_dialogue_started(dialogue_resource: DialogueResource, dialogue_start: String, balloon_instance: Node) -> void:
	var path := ""
	if dialogue_resource != null:
		path = dialogue_resource.resource_path

	_append_log("Dialogue started: %s / %s" % [path, dialogue_start])

	if balloon_instance != null:
		_append_log("Balloon instance created: %s" % balloon_instance.name)


func _on_dialogue_finished(dialogue_resource: DialogueResource, dialogue_start: String) -> void:
	var path := ""
	if dialogue_resource != null:
		path = dialogue_resource.resource_path

	_dialogue_phase = "none"
	_dialogue_has_choices = false
	_update_phase_label()
	_append_log("Dialogue finished: %s / %s" % [path, dialogue_start])


func _on_dialogue_start_rejected(reason: String) -> void:
	_append_log("Dialogue start rejected: %s" % reason)


func _on_dialogue_phase_changed(phase_name: String, has_choices: bool, _line) -> void:
	_dialogue_phase = phase_name
	_dialogue_has_choices = has_choices
	_update_phase_label()
	_append_log("Dialogue phase changed to: %s | choices=%s" % [phase_name, str(has_choices)])


func _ensure_test_sounds_registered() -> void:
	if AudioManager == null:
		return

	for entry in TEST_SOUNDS:
		var sound_id: StringName = entry["id"]

		if AudioManager.has_sound(sound_id):
			continue

		var options := {
			"base_volume_db": float(entry.get("base_volume_db", 0.0)),
			"pitch_random": float(entry.get("pitch_random", 0.0)),
			"preload": bool(entry.get("preload", false)),
		}

		AudioManager.register_sound(
			sound_id,
			String(entry["path"]),
			int(entry["category"]),
			options
		)

	AudioManager.warmup_all()


# -------------------------------------------------------------------
# Context methods meant to be called through DialogueBridge
# -------------------------------------------------------------------

func set_context_message(message: String) -> void:
	if _context_message_label != null:
		_context_message_label.text = message
	_append_log("Context message changed to: %s" % message)


func mark_context_pinged() -> void:
	set_context_message("Context ping received from the dialogue.")


func set_panel_message_intro() -> void:
	set_context_message("The intro context action was triggered.")


func set_panel_message_imported() -> void:
	set_context_message("The imported snippet reached the scene context.")


func set_mood(new_mood: String) -> void:
	# Update the textual mood state.
	_current_mood = new_mood
	demo_mood = new_mood

	if _mood_label != null:
		_mood_label.text = "Current mood: %s" % new_mood

	# Keep the color preview in sync with the mood.
	match new_mood:
		"happy":
			set_demo_color("green")
		"surprised":
			set_demo_color("gold")
		"angry":
			set_demo_color("red")
		"sad":
			set_demo_color("blue")
		"neutral":
			set_demo_color("neutral")
		_:
			set_demo_color("neutral")

	_append_log("Mood changed to: %s" % new_mood)


func set_mood_happy() -> void:
	set_mood("happy")


func set_mood_surprised() -> void:
	set_mood("surprised")


func set_demo_color(color_name: String) -> void:
	if _color_panel == null:
		return

	match color_name:
		"red":
			_color_panel.color = Color(0.75, 0.25, 0.25, 1.0)
		"green":
			_color_panel.color = Color(0.25, 0.75, 0.35, 1.0)
		"blue":
			_color_panel.color = Color(0.25, 0.45, 0.85, 1.0)
		"gold":
			_color_panel.color = Color(0.85, 0.70, 0.25, 1.0)
		"neutral":
			_color_panel.color = Color(0.18, 0.18, 0.22, 1.0)
		_:
			_color_panel.color = Color(0.4, 0.4, 0.4, 1.0)

	_append_log("Demo color changed to: %s" % color_name)


func cycle_demo_box_color() -> void:
	var palette := ["red", "green", "blue", "gold", "neutral"]
	_color_cycle_index = (_color_cycle_index + 1) % palette.size()
	set_demo_color(palette[_color_cycle_index])


func increment_demo_counter() -> void:
	var value := int(SessionManager.get_data("dialogue/demo_counter", 0))
	value += 1
	SessionManager.set_data("dialogue/demo_counter", value)
	_append_log("Demo counter incremented to: %d" % value)


func mark_tutorial_seen() -> void:
	SessionManager.set_flag("dialogue/tutorial_seen", true)
	_append_log("Tutorial seen flag set to true.")


func grant_test_key() -> void:
	SessionManager.set_flag("dialogue/has_test_key", true)
	_append_log("Test key flag granted.")


func rename_player(new_name: String) -> void:
	SessionManager.set_data("dialogue/player_name", new_name)
	_append_log("Player name changed to: %s" % new_name)


func remember_choice(choice_id: String) -> void:
	SessionManager.set_data("dialogue/last_choice", choice_id)
	_append_log("Remembered last choice: %s" % choice_id)


func add_visit() -> void:
	var visits := int(SessionManager.get_data("dialogue/visit_count", 0))
	visits += 1
	SessionManager.set_data("dialogue/visit_count", visits)
	_append_log("Visit count incremented to: %d" % visits)


func play_demo_music() -> void:
	if AudioManager == null:
		return

	AudioManager.play_music(&"music_chill")
	_append_log("Requested demo music.")


func play_alt_demo_music() -> void:
	if AudioManager == null:
		return

	AudioManager.play_music(&"music_assault")
	_append_log("Requested alternate demo music.")


func stop_demo_audio() -> void:
	if AudioManager == null:
		return

	AudioManager.stop_all()
	_append_log("Requested stop of all demo audio.")


func play_demo_sfx() -> void:
	if AudioManager == null:
		return

	AudioManager.play_sfx(&"sfx_impact")
	_append_log("Requested demo SFX.")


func play_alt_demo_sfx() -> void:
	if AudioManager == null:
		return

	AudioManager.play_sfx(&"sfx_cat")
	_append_log("Requested alternate demo SFX.")


func play_demo_ui() -> void:
	if AudioManager == null:
		return

	AudioManager.play_ui(&"ui_select")
	_append_log("Requested demo UI sound.")


func play_demo_bubble() -> void:
	if AudioManager == null:
		return

	AudioManager.play_ui(&"ui_bubble")
	_append_log("Requested demo bubble UI sound.")
