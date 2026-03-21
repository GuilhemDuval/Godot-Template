extends Node

# DialogueBridge is the project's single entry point for dialogue.
# Game code should call DialogueBridge, never DialogueManager directly.
#
# Responsibilities:
# - start one dialogue at a time
# - attach the balloon to SceneManager.ui_layer when available
# - update InputRouter while a dialogue is active
# - temporarily switch StateManager from IN_GAME to CUTSCENE
# - restore the previous context when the dialogue ends
# - expose a small context-node registry for scene-specific references
# - expose the current dialogue phase to the rest of the project

signal dialogue_started(dialogue_resource: DialogueResource, dialogue_start: String, balloon_instance: Node)
signal dialogue_finished(dialogue_resource: DialogueResource, dialogue_start: String)
signal dialogue_start_rejected(reason: String)
signal dialogue_phase_changed(phase_name: String, has_choices: bool, line)

const SESSION_FLAG_DIALOGUE_ACTIVE := "dialogue/active"
const SESSION_DATA_DIALOGUE_RESOURCE := "dialogue/resource_path"
const SESSION_DATA_DIALOGUE_START := "dialogue/start"

const CUSTOM_BALLOON_SCENE_PATH := "res://scenes/dialogue_balloon.tscn"

const _TEMP_ALLOWED_UI_CATEGORIES := [
	InputRouter.Category.UI_NAVIGATION,
	InputRouter.Category.UI_CONFIRM,
	InputRouter.Category.UI_CANCEL,
]

var active_balloon: Node = null
var active_dialogue_resource: DialogueResource = null
var active_dialogue_start: String = ""
var is_dialogue_running: bool = false

var _restore_state: int = GameStates.State.BOOT
var _restore_state_needed: bool = false
var _saved_category_overrides: Dictionary = {}

var _context_nodes: Dictionary = {}

var _current_phase: String = "none"
var _current_line = null
var _current_has_choices: bool = false


func _ready() -> void:
	var dialogue_manager: Node = _get_dialogue_manager()
	if dialogue_manager == null:
		push_warning("DialogueBridge: DialogueManager autoload not found. Enable the plugin first.")
		return

	# Force the plugin to attach balloons to the UI layer managed by SceneManager.
	dialogue_manager.get_current_scene = func() -> Node:
		return _resolve_balloon_parent()

	if not dialogue_manager.dialogue_ended.is_connected(_on_dialogue_ended):
		dialogue_manager.dialogue_ended.connect(_on_dialogue_ended)

	if dialogue_manager.has_signal("got_dialogue") and not dialogue_manager.got_dialogue.is_connected(_on_got_dialogue):
		dialogue_manager.got_dialogue.connect(_on_got_dialogue)

	_set_phase("none", false, null)


func start_dialogue(dialogue_resource: DialogueResource, dialogue_start: String = "") -> bool:
	if dialogue_resource == null:
		_reject_start("Dialogue resource is null.")
		return false

	if is_dialogue_running:
		_reject_start("A dialogue is already running.")
		return false

	if _get_dialogue_manager() == null:
		_reject_start("DialogueManager is not available.")
		return false

	if InputRouter.get_flag(InputRouter.FLAG_TRANSITION_ACTIVE):
		_reject_start("Cannot start a dialogue during a scene transition.")
		return false

	if StateManager.is_loading_state():
		_reject_start("Cannot start a dialogue while loading.")
		return false

	_capture_restore_context()
	_apply_dialogue_context()

	active_dialogue_resource = dialogue_resource
	active_dialogue_start = dialogue_start
	is_dialogue_running = true

	SessionManager.set_flag(SESSION_FLAG_DIALOGUE_ACTIVE, true)
	SessionManager.set_data(SESSION_DATA_DIALOGUE_RESOURCE, dialogue_resource.resource_path)
	SessionManager.set_data(SESSION_DATA_DIALOGUE_START, dialogue_start)

	_set_phase("opening", false, null)

	var dialogue_manager := _get_dialogue_manager()

	if dialogue_manager.has_method("show_dialogue_balloon_scene") and ResourceLoader.exists(CUSTOM_BALLOON_SCENE_PATH):
		active_balloon = dialogue_manager.show_dialogue_balloon_scene(
			CUSTOM_BALLOON_SCENE_PATH,
			dialogue_resource,
			dialogue_start,
			[self]
		)
	else:
		active_balloon = dialogue_manager.show_dialogue_balloon(
			dialogue_resource,
			dialogue_start,
			[self]
		)

	if is_instance_valid(active_balloon):
		if not active_balloon.tree_exited.is_connected(_on_active_balloon_tree_exited):
			active_balloon.tree_exited.connect(_on_active_balloon_tree_exited, CONNECT_ONE_SHOT)

	dialogue_started.emit(dialogue_resource, dialogue_start, active_balloon)
	return true


func stop_dialogue() -> void:
	if not is_dialogue_running:
		return

	if is_instance_valid(active_balloon):
		active_balloon.queue_free()

	_finish_dialogue()


func has_active_dialogue() -> bool:
	return is_dialogue_running


func get_active_balloon() -> Node:
	return active_balloon


func get_active_dialogue_resource() -> DialogueResource:
	return active_dialogue_resource


func get_active_dialogue_start() -> String:
	return active_dialogue_start


func get_current_phase() -> String:
	return _current_phase


func current_phase_has_choices() -> bool:
	return _current_has_choices


func get_current_line():
	return _current_line


func register_context_node(key: StringName, node: Node) -> void:
	if key == StringName():
		return

	if node == null:
		_context_nodes.erase(key)
		return

	_context_nodes[key] = weakref(node)


func unregister_context_node(key: StringName) -> void:
	if _context_nodes.has(key):
		_context_nodes.erase(key)


func clear_context_nodes() -> void:
	_context_nodes.clear()


func has_context_node(key: StringName) -> bool:
	return get_context_node(key) != null


func get_context_node(key: StringName) -> Node:
	var ref: Variant = _context_nodes.get(key, null)
	if ref == null:
		return null

	if ref is WeakRef:
		var weak_ref: WeakRef = ref
		var node: Node = weak_ref.get_ref() as Node
		if node == null:
			_context_nodes.erase(key)
		return node

	return null


func get_context_value(key: StringName, property_name: StringName, default_value: Variant = null) -> Variant:
	var node: Node = get_context_node(key)
	if node == null:
		return default_value

	var value: Variant = node.get(property_name)
	if value == null:
		return default_value

	return value


func call_context_node_method(key: StringName, method_name: StringName, args: Array = []) -> Variant:
	var node: Node = get_context_node(key)
	if node == null:
		push_warning("DialogueBridge: context node '%s' is missing." % String(key))
		return null

	if not node.has_method(method_name):
		push_warning("DialogueBridge: method '%s' was not found on context node '%s'." % [String(method_name), String(key)])
		return null

	return node.callv(method_name, args)


func session_get_flag(key: String, default_value: Variant = null) -> Variant:
	return SessionManager.get_flag(key, default_value)


func session_set_flag(key: String, value: Variant) -> void:
	SessionManager.set_flag(key, value)


func session_clear_flag(key: String) -> void:
	SessionManager.clear_flag(key)


func session_get_data(key: String, default_value: Variant = null) -> Variant:
	return SessionManager.get_data(key, default_value)


func session_set_data(key: String, value: Variant) -> void:
	SessionManager.set_data(key, value)


func session_clear_data(key: String) -> void:
	SessionManager.clear_data(key)


func _get_dialogue_manager() -> Node:
	return get_node_or_null("/root/DialogueManager")


func _resolve_balloon_parent() -> Node:
	if SceneManager.ui_layer != null:
		return SceneManager.ui_layer

	if SceneManager.current_overlay_scene != null:
		return SceneManager.current_overlay_scene

	if SceneManager.current_main_scene != null:
		return SceneManager.current_main_scene

	if get_tree().current_scene != null:
		return get_tree().current_scene

	return get_tree().root


func _capture_restore_context() -> void:
	_restore_state = StateManager.get_state()
	_restore_state_needed = false

	_saved_category_overrides.clear()

	for category in _TEMP_ALLOWED_UI_CATEGORIES:
		_saved_category_overrides[category] = {
			"had_override": InputRouter.has_category_override(category),
			"value": InputRouter.get_category_override(category),
		}


func _apply_dialogue_context() -> void:
	InputRouter.set_flag(InputRouter.FLAG_DIALOGUE_ACTIVE, true)

	for category in _TEMP_ALLOWED_UI_CATEGORIES:
		InputRouter.set_category_override(category, true)

	InputRouter.set_category_override(InputRouter.Category.PAUSE_TOGGLE, false)

	if StateManager.is_in_state(GameStates.State.IN_GAME):
		var changed: bool = StateManager.set_state(GameStates.State.CUTSCENE)
		_restore_state_needed = changed


func _restore_after_dialogue() -> void:
	InputRouter.clear_flag(InputRouter.FLAG_DIALOGUE_ACTIVE)

	for category in _TEMP_ALLOWED_UI_CATEGORIES:
		var restore_data: Dictionary = _saved_category_overrides.get(category, {})
		var had_override: bool = bool(restore_data.get("had_override", false))
		var value: bool = bool(restore_data.get("value", false))

		if had_override:
			InputRouter.set_category_override(category, value)
		else:
			InputRouter.clear_category_override(category)

	InputRouter.clear_category_override(InputRouter.Category.PAUSE_TOGGLE)

	if _restore_state_needed and StateManager.get_state() != _restore_state:
		StateManager.set_state(_restore_state)

	SessionManager.clear_flag(SESSION_FLAG_DIALOGUE_ACTIVE)
	SessionManager.clear_data(SESSION_DATA_DIALOGUE_RESOURCE)
	SessionManager.clear_data(SESSION_DATA_DIALOGUE_START)

	_restore_state_needed = false
	_saved_category_overrides.clear()


func _set_phase(phase_name: String, has_choices: bool, line) -> void:
	_current_phase = phase_name
	_current_has_choices = has_choices
	_current_line = line
	dialogue_phase_changed.emit(_current_phase, _current_has_choices, _current_line)


func _finish_dialogue() -> void:
	if not is_dialogue_running:
		return

	var finished_resource: DialogueResource = active_dialogue_resource
	var finished_start: String = active_dialogue_start

	active_balloon = null
	active_dialogue_resource = null
	active_dialogue_start = ""
	is_dialogue_running = false

	_restore_after_dialogue()
	_set_phase("none", false, null)

	dialogue_finished.emit(finished_resource, finished_start)


func _on_got_dialogue(line) -> void:
	if not is_dialogue_running:
		return

	if line == null:
		_set_phase("none", false, null)
		return

	var has_choices := false
	if line.responses != null and line.responses.size() > 0:
		has_choices = true

	if has_choices:
		_set_phase("choice", true, line)
	else:
		_set_phase("line", false, line)


func _on_dialogue_ended(ended_resource: DialogueResource) -> void:
	if not is_dialogue_running:
		return

	if ended_resource != active_dialogue_resource:
		return

	_finish_dialogue()


func _on_active_balloon_tree_exited() -> void:
	if is_dialogue_running:
		_finish_dialogue()


func _reject_start(reason: String) -> void:
	dialogue_start_rejected.emit(reason)
	push_warning("DialogueBridge: " + reason)
