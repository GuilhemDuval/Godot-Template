extends Control

var ACTION_SPECS: Array = InputRegistry.get_smoke_test_action_specs()
var FLAG_SPECS: Array = InputRegistry.get_flag_specs_for_smoke_test()
var CATEGORY_ORDER: Array = InputRegistry.get_category_order()

var router: InputRouter
var owns_router_instance := false

var passed_count := 0
var failed_count := 0
var action_press_counts: Dictionary = {}
var action_last_status: Dictionary = {}
var missing_action_names: Array[String] = []
var actions_missing_bindings: Array[String] = []
var fallback_injected_actions: Array[String] = []

var smoke_summary_label: Label
var missing_actions_label: RichTextLabel
var context_panel: VBoxContainer
var categories_panel: VBoxContainer
var actions_panel: VBoxContainer
var event_log: RichTextLabel
var signal_log: RichTextLabel

var categories_title_label: Label
var actions_title_label: Label

var show_only_allowed_categories := false
var show_only_allowed_live_inputs := false

var flag_buttons: Dictionary = {}
var category_rows: Dictionary = {}
var category_allowed_labels: Dictionary = {}
var category_override_labels: Dictionary = {}
var category_actions_labels: Dictionary = {}
var action_rows: Dictionary = {}
var action_status_labels: Dictionary = {}
var action_count_labels: Dictionary = {}
var action_bindings_labels: Dictionary = {}
var action_category_labels: Dictionary = {}


func _ready() -> void:
	_resolve_router()
	_ensure_test_actions_exist()
	_build_ui()
	_connect_router_signals()
	_reset_runtime_buffers()
	_run_smoke_tests()
	_refresh_all_views()
	_append_event_log("Interactive InputRouter smoke scene ready.")
	_append_event_log("Press the listed keys and use the buttons on the left to change flags and category overrides.")


func _exit_tree() -> void:
	if owns_router_instance and is_instance_valid(router):
		router.queue_free()


func _input(event: InputEvent) -> void:
	for spec in ACTION_SPECS:
		var action_name: StringName = spec["name"]
		if event.is_action_pressed(action_name, false, true):
			_register_action_event(action_name, true)
		elif event.is_action_released(action_name):
			_register_action_event(action_name, false)


func _resolve_router() -> void:
	var root := get_tree().root
	var singleton := root.get_node_or_null("InputRouter")
	if singleton != null:
		router = singleton as InputRouter
		owns_router_instance = false
		return

	router = InputRouter.new()
	router.name = "InputRouterSmokeLocal"
	add_child(router)
	owns_router_instance = true


func _ensure_test_actions_exist() -> void:
	missing_action_names.clear()
	actions_missing_bindings.clear()
	fallback_injected_actions.clear()

	for spec in ACTION_SPECS:
		var action_name: StringName = spec["name"]
		var action_name_text := String(action_name)
		var had_action_before := InputMap.has_action(action_name)
		if not had_action_before:
			missing_action_names.append(action_name_text)
			InputMap.add_action(action_name)
		elif InputMap.action_get_events(action_name).is_empty():
			actions_missing_bindings.append(action_name_text)

		var injected_fallback := false
		for keycode in spec.get("fallback_keys", []):
			if not _action_has_key(action_name, keycode):
				var key_event := InputEventKey.new()
				key_event.physical_keycode = keycode
				key_event.keycode = keycode
				InputMap.action_add_event(action_name, key_event)
				injected_fallback = true

		if injected_fallback:
			fallback_injected_actions.append(action_name_text)


func _action_has_key(action_name: StringName, keycode: int) -> bool:
	for existing_event in InputMap.action_get_events(action_name):
		if existing_event is InputEventKey:
			var key_event := existing_event as InputEventKey
			if key_event.physical_keycode == keycode or key_event.keycode == keycode:
				return true
	return false


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(root_vbox)

	var title := Label.new()
	title.text = "InputRouter interactive smoke test"
	title.add_theme_font_size_override("font_size", 22)
	root_vbox.add_child(title)

	var instructions := Label.new()
	instructions.text = "Use the left panel to toggle context flags or force category overrides. Press the keys shown on the right to verify which actions are allowed or blocked in the current context. Missing InputMap actions are reported below and get temporary fallback keys so the scene stays testable."
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_vbox.add_child(instructions)

	smoke_summary_label = Label.new()
	smoke_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_vbox.add_child(smoke_summary_label)

	missing_actions_label = RichTextLabel.new()
	missing_actions_label.bbcode_enabled = true
	missing_actions_label.fit_content = true
	missing_actions_label.scroll_active = false
	root_vbox.add_child(missing_actions_label)

	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root_vbox.add_child(body)

	context_panel = VBoxContainer.new()
	context_panel.custom_minimum_size = Vector2(320, 0)
	context_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_wrap_in_scroll("Context and controls", context_panel))

	categories_panel = VBoxContainer.new()
	categories_panel.custom_minimum_size = Vector2(360, 0)
	categories_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_wrap_in_scroll_with_title_ref("Categories", categories_panel, "categories"))

	actions_panel = VBoxContainer.new()
	actions_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_wrap_in_scroll_with_title_ref("Actions and live input", actions_panel, "actions"))

	_build_context_panel()
	_build_categories_panel()
	_build_actions_panel()

	var log_split := HSplitContainer.new()
	log_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(log_split)

	event_log = RichTextLabel.new()
	event_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	event_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	event_log.bbcode_enabled = true
	event_log.fit_content = false
	log_split.add_child(_wrap_log("Input events", event_log))

	signal_log = RichTextLabel.new()
	signal_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	signal_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	signal_log.bbcode_enabled = true
	signal_log.fit_content = false
	log_split.add_child(_wrap_log("Router signals and smoke assertions", signal_log))


func _wrap_in_scroll(title_text: String, content: Control) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)

	return panel


func _wrap_in_scroll_with_title_ref(title_text: String, content: Control, slot: String) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	if slot == "categories":
		categories_title_label = title
	elif slot == "actions":
		actions_title_label = title

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)

	return panel


func _wrap_log(title_text: String, log_widget: RichTextLabel) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	log_widget.scroll_following = true
	log_widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_widget.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(log_widget)
	return panel


func _build_context_panel() -> void:
	var status := Label.new()
	status.text = "Toggle context flags, category overrides, and the visibility filters below. The warning panel above tells you which actions were missing from InputMap and got temporary fallback keys."
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	context_panel.add_child(status)

	var filters_title := Label.new()
	filters_title.text = "Visibility filters"
	filters_title.add_theme_font_size_override("font_size", 16)
	context_panel.add_child(filters_title)

	var allowed_categories_toggle := CheckButton.new()
	allowed_categories_toggle.text = "Show only allowed categories"
	allowed_categories_toggle.toggled.connect(_on_show_only_allowed_categories_toggled)
	context_panel.add_child(allowed_categories_toggle)

	var allowed_live_inputs_toggle := CheckButton.new()
	allowed_live_inputs_toggle.text = "Show only allowed live inputs"
	allowed_live_inputs_toggle.toggled.connect(_on_show_only_allowed_live_inputs_toggled)
	context_panel.add_child(allowed_live_inputs_toggle)

	var flags_title := Label.new()
	flags_title.text = "Context flags"
	flags_title.add_theme_font_size_override("font_size", 16)
	context_panel.add_child(flags_title)

	for spec in FLAG_SPECS:
		var button := CheckButton.new()
		button.text = spec["label"]
		button.toggled.connect(_on_flag_button_toggled.bind(spec["name"]))
		context_panel.add_child(button)
		flag_buttons[spec["name"]] = button

	var button_row := HBoxContainer.new()
	context_panel.add_child(button_row)

	var clear_flags_button := Button.new()
	clear_flags_button.text = "Clear all flags"
	clear_flags_button.pressed.connect(_on_clear_flags_pressed)
	button_row.add_child(clear_flags_button)

	var clear_overrides_button := Button.new()
	clear_overrides_button.text = "Clear all category overrides"
	clear_overrides_button.pressed.connect(_on_clear_overrides_pressed)
	button_row.add_child(clear_overrides_button)

	var full_reset_button := Button.new()
	full_reset_button.text = "Full router reset"
	full_reset_button.pressed.connect(_on_full_reset_pressed)
	context_panel.add_child(full_reset_button)

	var smoke_rerun_button := Button.new()
	smoke_rerun_button.text = "Run smoke assertions again"
	smoke_rerun_button.pressed.connect(_on_rerun_smoke_pressed)
	context_panel.add_child(smoke_rerun_button)


func _build_categories_panel() -> void:
	for category in CATEGORY_ORDER:
		var panel := PanelContainer.new()
		categories_panel.add_child(panel)
		category_rows[category] = panel

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)
		panel.add_child(vbox)

		var title := Label.new()
		title.text = InputRegistry.get_category_name(category)
		title.add_theme_font_size_override("font_size", 16)
		vbox.add_child(title)

		var allowed_label := Label.new()
		vbox.add_child(allowed_label)
		category_allowed_labels[category] = allowed_label

		var override_label := Label.new()
		vbox.add_child(override_label)
		category_override_labels[category] = override_label

		var actions_label := Label.new()
		actions_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(actions_label)
		category_actions_labels[category] = actions_label

		var buttons := HBoxContainer.new()
		vbox.add_child(buttons)

		var force_block_button := Button.new()
		force_block_button.text = "Force block"
		force_block_button.pressed.connect(_on_force_block_category_pressed.bind(category))
		buttons.add_child(force_block_button)

		var force_allow_button := Button.new()
		force_allow_button.text = "Force allow"
		force_allow_button.pressed.connect(_on_force_allow_category_pressed.bind(category))
		buttons.add_child(force_allow_button)

		var clear_button := Button.new()
		clear_button.text = "Clear override"
		clear_button.pressed.connect(_on_clear_category_override_pressed.bind(category))
		buttons.add_child(clear_button)


func _build_actions_panel() -> void:
	for spec in ACTION_SPECS:
		var action_name: StringName = spec["name"]

		var panel := PanelContainer.new()
		actions_panel.add_child(panel)
		action_rows[action_name] = panel

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)
		panel.add_child(vbox)

		var title := Label.new()
		title.text = "%s (%s)" % [spec.get("label", String(action_name)), String(action_name)]
		title.add_theme_font_size_override("font_size", 16)
		vbox.add_child(title)

		var category_label := Label.new()
		vbox.add_child(category_label)
		action_category_labels[action_name] = category_label

		var bindings_label := Label.new()
		bindings_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(bindings_label)
		action_bindings_labels[action_name] = bindings_label

		var status_label := Label.new()
		vbox.add_child(status_label)
		action_status_labels[action_name] = status_label

		var count_label := Label.new()
		vbox.add_child(count_label)
		action_count_labels[action_name] = count_label


func _connect_router_signals() -> void:
	if not router.context_flag_changed.is_connected(_on_router_context_flag_changed):
		router.context_flag_changed.connect(_on_router_context_flag_changed)
	if not router.permissions_changed.is_connected(_on_router_permissions_changed):
		router.permissions_changed.connect(_on_router_permissions_changed)
	if not router.router_reset.is_connected(_on_router_reset):
		router.router_reset.connect(_on_router_reset)
	if router.has_signal("category_override_changed") and not router.category_override_changed.is_connected(_on_category_override_changed):
		router.category_override_changed.connect(_on_category_override_changed)


func _run_smoke_tests() -> void:
	passed_count = 0
	failed_count = 0
	signal_log.clear()

	router.reset()
	_assert_true(router.is_gameplay_input_allowed(), "Default state allows gameplay input")
	_assert_true(router.is_ui_input_allowed(), "Default state allows UI input")
	_assert_true(router.is_action_allowed(&"move_left"), "Default state allows move_left")
	_assert_true(router.is_action_allowed(&"ui_accept"), "Default state allows ui_accept")

	router.set_flag(InputRouter.FLAG_MENU_OPEN, true)
	_assert_true(not router.is_gameplay_input_allowed(), "Menu flag blocks gameplay input")
	_assert_true(router.is_ui_input_allowed(), "Menu flag keeps UI input enabled")
	_assert_true(not router.is_action_allowed(&"interact"), "Menu flag blocks gameplay action interact")

	router.reset()
	router.set_flag(InputRouter.FLAG_PAUSE_OPEN, true)
	_assert_true(not router.is_gameplay_input_allowed(), "Pause flag blocks gameplay input")
	_assert_true(router.is_pause_toggle_allowed(), "Pause flag keeps pause toggle enabled")
	_assert_true(router.is_ui_input_allowed(), "Pause flag keeps UI input enabled")

	router.reset()
	router.set_flag(InputRouter.FLAG_DIALOGUE_ACTIVE, true)
	_assert_true(not router.is_action_allowed(&"attack"), "Dialogue flag blocks attack")
	_assert_true(router.is_action_allowed(&"dialogue_advance"), "Dialogue flag allows dialogue advance")
	_assert_true(router.is_action_allowed(&"pause"), "Dialogue flag still allows pause")

	router.reset()
	router.set_flag(InputRouter.FLAG_TRANSITION_ACTIVE, true)
	_assert_true(not router.is_action_allowed(&"ui_accept"), "Transition flag blocks UI confirm")
	_assert_true(not router.is_action_allowed(&"move_up"), "Transition flag blocks movement")
	_assert_true(router.is_action_allowed(&"debug_toggle"), "Transition flag still allows debug")

	router.reset()
	router.set_flag(InputRouter.FLAG_INPUT_GLOBALLY_BLOCKED, true)
	_assert_true(not router.is_action_allowed(&"pause"), "Global block disables pause")
	_assert_true(not router.is_action_allowed(&"move_right"), "Global block disables movement")
	_assert_true(router.is_category_allowed(InputRouter.Category.SYSTEM), "Global block still allows SYSTEM category")

	router.reset()
	router.set_category_override(InputRouter.Category.GAMEPLAY_MOVE, false)
	_assert_true(not router.is_action_allowed(&"move_left"), "Category override can force block GAMEPLAY_MOVE")
	router.set_flag(InputRouter.FLAG_MENU_OPEN, true)
	router.set_category_override(InputRouter.Category.GAMEPLAY_ACTION, true)
	_assert_true(router.is_action_allowed(&"interact"), "Category override can force allow GAMEPLAY_ACTION")
	router.clear_all_category_overrides()
	_assert_true(not router.is_action_allowed(&"interact"), "Clearing overrides restores normal flag policy")

	router.reset()
	_update_smoke_summary_label()


func _assert_true(condition: bool, description: String) -> void:
	if condition:
		passed_count += 1
		_append_signal_log("[color=green]PASS[/color] %s" % description)
	else:
		failed_count += 1
		_append_signal_log("[color=red]FAIL[/color] %s" % description)


func _reset_runtime_buffers() -> void:
	action_press_counts.clear()
	action_last_status.clear()
	for spec in ACTION_SPECS:
		action_press_counts[spec["name"]] = 0
		action_last_status[spec["name"]] = "No input yet"


func _register_action_event(action_name: StringName, pressed: bool) -> void:
	var allowed := router.is_action_allowed(action_name)
	var category := _get_action_category_from_specs(action_name)
	var verb := "pressed" if pressed else "released"
	if pressed:
		action_press_counts[action_name] = int(action_press_counts.get(action_name, 0)) + 1
	action_last_status[action_name] = "%s, %s" % [verb, "ALLOWED" if allowed else "BLOCKED"]
	_append_event_log("%s -> %s (%s)" % [String(action_name), verb, "allowed" if allowed else "blocked"])
	_refresh_action_row(action_name, category)


func _refresh_all_views() -> void:
	_refresh_flag_buttons()
	_refresh_missing_actions_warning()
	_refresh_section_titles()
	for category in CATEGORY_ORDER:
		_refresh_category_row(category)
	for spec in ACTION_SPECS:
		_refresh_action_row(spec["name"], spec["category"])
	_update_smoke_summary_label()


func _refresh_missing_actions_warning() -> void:
	if missing_actions_label == null:
		return

	if missing_action_names.is_empty() and actions_missing_bindings.is_empty() and fallback_injected_actions.is_empty():
		missing_actions_label.text = "[color=green]InputMap coverage looks complete for the registered smoke-test actions.[/color]"
		return

	var lines: Array[String] = []
	lines.append("[color=yellow]InputMap audit warning[/color]")
	if not missing_action_names.is_empty():
		lines.append("Missing actions before fallback injection: %s" % ", ".join(missing_action_names))
	if not actions_missing_bindings.is_empty():
		lines.append("Existing actions with no bindings before fallback injection: %s" % ", ".join(actions_missing_bindings))
	if not fallback_injected_actions.is_empty():
		lines.append("Fallback keys injected so the scene stays testable: %s" % ", ".join(fallback_injected_actions))
	lines.append("Review Project Settings > Input Map after this test and replace missing bindings with real project bindings.")
	missing_actions_label.text = "
".join(lines)


func _refresh_section_titles() -> void:
	if categories_title_label != null:
		categories_title_label.text = "Categories (allowed only)" if show_only_allowed_categories else "Categories"

	if actions_title_label != null:
		actions_title_label.text = "Actions and live input (allowed only)" if show_only_allowed_live_inputs else "Actions and live input"


func _refresh_flag_buttons() -> void:
	for spec in FLAG_SPECS:
		var flag_name: StringName = spec["name"]
		var button: CheckButton = flag_buttons.get(flag_name)
		if button == null:
			continue
		button.set_pressed_no_signal(router.get_flag(flag_name))


func _refresh_category_row(category: int) -> void:
	var row: Control = category_rows.get(category)
	if row == null:
		return

	var is_allowed: bool = router.is_category_allowed(category)

	if show_only_allowed_categories and not is_allowed:
		row.visible = false
		return

	row.visible = true

	var allowed_label: Label = category_allowed_labels.get(category)
	if allowed_label != null:
		allowed_label.text = "Router result: %s" % ("ALLOWED" if is_allowed else "BLOCKED")

	var override_label: Label = category_override_labels.get(category)
	if override_label != null:
		if router.has_category_override(category):
			var forced: bool = router.get_category_override(category)
			override_label.text = "Override: forced %s" % ("ALLOWED" if forced else "BLOCKED")
		else:
			override_label.text = "Override: none"

	var actions_label: Label = category_actions_labels.get(category)
	if actions_label != null:
		actions_label.text = "Actions: %s" % ", ".join(_get_action_names_for_category(category))


func _refresh_action_row(action_name: StringName, category: int) -> void:
	var row: Control = action_rows.get(action_name)
	if row == null:
		return

	var is_allowed: bool = router.is_action_allowed(action_name)

	if show_only_allowed_live_inputs and not is_allowed:
		row.visible = false
		return

	row.visible = true

	var category_label: Label = action_category_labels.get(action_name)
	if category_label != null:
		category_label.text = "Category: %s" % InputRegistry.get_category_name(category)

	var bindings_label: Label = action_bindings_labels.get(action_name)
	if bindings_label != null:
		bindings_label.text = "Bindings: %s" % _get_action_bindings_text(action_name)

	var status_label: Label = action_status_labels.get(action_name)
	if status_label != null:
		status_label.text = "Current permission: %s | Last event: %s" % ["ALLOWED" if is_allowed else "BLOCKED", action_last_status.get(action_name, "No input yet")]

	var count_label: Label = action_count_labels.get(action_name)
	if count_label != null:
		count_label.text = "Press count: %d" % int(action_press_counts.get(action_name, 0))


func _get_action_bindings_text(action_name: StringName) -> String:
	var parts: Array[String] = []
	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey:
			var key_event := event as InputEventKey
			parts.append(OS.get_keycode_string(key_event.keycode))
	return ", ".join(parts)


func _get_action_names_for_category(category: int) -> Array[String]:
	var names: Array[String] = []
	for spec in ACTION_SPECS:
		if spec["category"] == category:
			names.append(String(spec["name"]))
	return names


func _get_action_category_from_specs(action_name: StringName) -> int:
	var spec := InputRegistry.get_action_spec(action_name)
	if spec.is_empty():
		return InputRouter.Category.NONE
	return int(spec["category"])


func _update_smoke_summary_label() -> void:
	smoke_summary_label.text = "Smoke assertions: %d passed, %d failed." % [passed_count, failed_count]


func _append_event_log(message: String) -> void:
	event_log.append_text("%s
" % message)


func _append_signal_log(message: String) -> void:
	signal_log.append_text("%s
" % message)


func _on_flag_button_toggled(button_pressed: bool, flag_name: StringName) -> void:
	router.set_flag(flag_name, button_pressed)


func _on_clear_flags_pressed() -> void:
	router.clear_all_flags()


func _on_clear_overrides_pressed() -> void:
	router.clear_all_category_overrides()


func _on_full_reset_pressed() -> void:
	router.reset()
	_reset_runtime_buffers()
	_append_event_log("Full router reset requested from UI.")
	_refresh_all_views()


func _on_rerun_smoke_pressed() -> void:
	_append_signal_log("--- Re-running smoke assertions ---")
	_run_smoke_tests()
	_refresh_all_views()


func _on_force_block_category_pressed(category: int) -> void:
	router.set_category_override(category, false)


func _on_force_allow_category_pressed(category: int) -> void:
	router.set_category_override(category, true)


func _on_clear_category_override_pressed(category: int) -> void:
	router.clear_category_override(category)


func _on_show_only_allowed_categories_toggled(button_pressed: bool) -> void:
	show_only_allowed_categories = button_pressed
	_refresh_all_views()


func _on_show_only_allowed_live_inputs_toggled(button_pressed: bool) -> void:
	show_only_allowed_live_inputs = button_pressed
	_refresh_all_views()


func _on_router_context_flag_changed(flag_name: StringName, value: bool) -> void:
	_append_signal_log("Flag changed: %s -> %s" % [String(flag_name), str(value)])
	_refresh_all_views()


func _on_router_permissions_changed() -> void:
	_append_signal_log("Permissions changed")
	_refresh_all_views()


func _on_router_reset() -> void:
	_append_signal_log("Router reset")
	_refresh_all_views()


func _on_category_override_changed(category: int, is_overridden: bool, allowed: bool) -> void:
	var message := "Category override changed: %s -> %s" % [
		InputRegistry.get_category_name(category),
		"forced %s" % ("ALLOWED" if allowed else "BLOCKED") if is_overridden else "cleared"
	]
	_append_signal_log(message)
	_refresh_all_views()
