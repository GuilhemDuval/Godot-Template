extends Node

# Signals emitted when the visible scene structure changes.
signal main_scene_changed(old_scene: Node, new_scene: Node, scene_path: String)
signal overlay_opened(scene: Node, scene_path: String)
signal overlay_closed(scene_path: String)
signal level_loaded(level_scene: Node, scene_path: String)
signal level_unloaded(scene_path: String)
signal scene_load_failed(scene_path: String, reason: String)

# Signals emitted around transition playback.
signal transition_started(transition_path: String, phase: String)
signal transition_finished(transition_path: String, phase: String)

# References to the persistent nodes of the application shell.
# These are resolved once in setup() and then reused.
var app_root: Node = null
var main_layer: Node = null
var ui_layer: Node = null
var transition_layer: Node = null

# References to the currently loaded runtime scenes.
# main_scene: the current root content, for example TitleScreen or GameRoot
# overlay_scene: UI shown on top, for example pause or options popup
# level_scene: gameplay content injected inside GameRoot
var current_main_scene: Node = null
var current_overlay_scene: Node = null
var current_level_scene: Node = null

# Stored paths for reloads, diagnostics, and emitted events.
var current_main_scene_path: String = ""
var current_overlay_scene_path: String = ""
var current_level_scene_path: String = ""

# Guard used to avoid starting two main-scene transitions at once.
var _main_scene_transition_running: bool = false

# Expected children inside AppRoot.
const MAIN_LAYER_PATH := NodePath("MainLayer")
const UI_LAYER_PATH := NodePath("UILayer")
const TRANSITION_LAYER_PATH := NodePath("TransitionLayer")

# Expected child inside GameRoot where gameplay levels are inserted.
# If it does not exist yet, SceneManager can create it as a fallback.
const LEVEL_CONTAINER_PATH := NodePath("LevelContainer")

# State-to-scene routing is delegated to StateSceneRegistry.
# SceneManager only consumes that mapping to know which root scene to load.

func _ready() -> void:
	# SceneManager does nothing by itself on startup.
	# Another bootstrap point must call setup() explicitly.
	pass


func setup(root: Node) -> bool:
	# Connect SceneManager to the persistent application shell.
	# Without this, it cannot attach main scenes, overlays, or transitions.
	if root == null:
		push_error("SceneManager.setup() received a null root.")
		return false

	app_root = root
	main_layer = app_root.get_node_or_null(MAIN_LAYER_PATH)
	ui_layer = app_root.get_node_or_null(UI_LAYER_PATH)
	transition_layer = app_root.get_node_or_null(TRANSITION_LAYER_PATH)

	if main_layer == null:
		push_error("SceneManager could not find MainLayer in AppRoot.")
		return false

	if ui_layer == null:
		push_warning("SceneManager could not find UILayer in AppRoot. Overlay features will be unavailable.")

	if transition_layer == null:
		push_warning("SceneManager could not find TransitionLayer in AppRoot. General transition scenes will be unavailable.")

	return true


func sync_main_scene_with_state(new_state: int) -> bool:
	return load_main_scene_from_state(new_state)


func sync_main_scene_with_state_transition(new_state: int) -> bool:
	return await transition_main_scene_from_state(new_state)


func load_main_scene_from_state(state: int) -> bool:
	var scene_path: String = StateSceneRegistry.get_scene_path_for_state(state)
	if scene_path == "":
		_emit_load_failed("", "No scene is mapped for state %s." % GameStates.get_state_name(state))
		return false

	return change_main_scene(scene_path)


func transition_main_scene_from_state(
	state: int,
	exit_transition_path: String = "",
	enter_transition_path: String = ""
) -> bool:
	var scene_path: String = StateSceneRegistry.get_scene_path_for_state(state)
	if scene_path == "":
		_emit_load_failed("", "No scene is mapped for state %s." % GameStates.get_state_name(state))
		return false

	return await transition_to_main_scene(scene_path, exit_transition_path, enter_transition_path)


func change_main_scene(scene_path: String) -> bool:
	# Load and replace the current main scene immediately.
	# This is the core low-level operation used by several public methods.
	if main_layer == null:
		_emit_load_failed(scene_path, "MainLayer is not configured.")
		return false

	var packed_scene: PackedScene = load(scene_path) as PackedScene
	if packed_scene == null:
		_emit_load_failed(scene_path, "Could not load PackedScene.")
		return false

	var new_scene: Node = packed_scene.instantiate()
	if new_scene == null:
		_emit_load_failed(scene_path, "Could not instantiate scene.")
		return false

	var old_scene: Node = current_main_scene

	if old_scene != null:
		old_scene.queue_free()

	main_layer.add_child(new_scene)
	current_main_scene = new_scene
	current_main_scene_path = scene_path

	main_scene_changed.emit(old_scene, new_scene, scene_path)
	return true


func transition_to_main_scene(
	scene_path: String,
	exit_transition_path: String = "",
	enter_transition_path: String = ""
) -> bool:
	# Full main-scene change with optional exit and enter transitions.
	# Transition sources can come from:
	# 1. explicit arguments
	# 2. methods exposed by the current/new scene
	# 3. nothing, in which case the switch is still performed
	if _main_scene_transition_running:
		_emit_load_failed(scene_path, "A main scene transition is already running.")
		return false

	_main_scene_transition_running = true

	var old_scene: Node = current_main_scene
	var resolved_exit_transition_path := _resolve_exit_transition_path(old_scene, exit_transition_path)
	var resolved_enter_transition_path := enter_transition_path

	if resolved_exit_transition_path != "":
		var exit_ok := await _play_general_transition(resolved_exit_transition_path, "out")
		if not exit_ok:
			_main_scene_transition_running = false
			return false
	else:
		var scene_exit_ok := await _play_scene_owned_exit_transition(old_scene)
		if not scene_exit_ok:
			_main_scene_transition_running = false
			return false

	var change_ok := change_main_scene(scene_path)
	if not change_ok:
		_main_scene_transition_running = false
		return false

	var new_scene: Node = current_main_scene

	if resolved_enter_transition_path == "":
		resolved_enter_transition_path = _resolve_enter_transition_path(new_scene)

	if resolved_enter_transition_path != "":
		var enter_ok := await _play_general_transition(resolved_enter_transition_path, "in")
		if not enter_ok:
			_main_scene_transition_running = false
			return false
	else:
		var scene_enter_ok := await _play_scene_owned_enter_transition(new_scene)
		if not scene_enter_ok:
			_main_scene_transition_running = false
			return false

	_main_scene_transition_running = false
	return true


func clear_main_scene() -> void:
	# Remove the current main scene without replacing it.
	if current_main_scene == null:
		return

	var old_path := current_main_scene_path
	current_main_scene.queue_free()
	current_main_scene = null
	current_main_scene_path = ""

	main_scene_changed.emit(null, null, old_path)


func reload_main_scene() -> bool:
	if current_main_scene_path == "":
		return false

	return change_main_scene(current_main_scene_path)


func reload_main_scene_with_transition(
	exit_transition_path: String = "",
	enter_transition_path: String = ""
) -> bool:
	if current_main_scene_path == "":
		return false

	return await transition_to_main_scene(current_main_scene_path, exit_transition_path, enter_transition_path)


func open_overlay(scene_path: String) -> bool:
	# Only one overlay is managed at a time.
	# Opening a new one first closes the previous one.
	if ui_layer == null:
		_emit_load_failed(scene_path, "UILayer is not configured.")
		return false

	close_overlay()

	var packed_scene: PackedScene = load(scene_path) as PackedScene
	if packed_scene == null:
		_emit_load_failed(scene_path, "Could not load overlay PackedScene.")
		return false

	var overlay: Node = packed_scene.instantiate()
	if overlay == null:
		_emit_load_failed(scene_path, "Could not instantiate overlay.")
		return false

	ui_layer.add_child(overlay)
	current_overlay_scene = overlay
	current_overlay_scene_path = scene_path

	overlay_opened.emit(overlay, scene_path)
	return true


func close_overlay() -> void:
	if current_overlay_scene == null:
		return

	var old_path := current_overlay_scene_path
	current_overlay_scene.queue_free()
	current_overlay_scene = null
	current_overlay_scene_path = ""

	overlay_closed.emit(old_path)


func load_level(scene_path: String) -> bool:
	# Level loading is separate from main-scene loading.
	# The expected use case is:
	# - main scene is GameRoot
	# - level scene is inserted inside GameRoot/LevelContainer
	var level_container := _get_or_create_level_container()
	if level_container == null:
		_emit_load_failed(scene_path, "Could not resolve LevelContainer.")
		return false

	var packed_scene: PackedScene = load(scene_path) as PackedScene
	if packed_scene == null:
		_emit_load_failed(scene_path, "Could not load level PackedScene.")
		return false

	var new_level: Node = packed_scene.instantiate()
	if new_level == null:
		_emit_load_failed(scene_path, "Could not instantiate level.")
		return false

	if current_level_scene != null:
		current_level_scene.queue_free()

	level_container.add_child(new_level)
	current_level_scene = new_level
	current_level_scene_path = scene_path

	level_loaded.emit(new_level, scene_path)
	return true


func unload_level() -> void:
	if current_level_scene == null:
		return

	var old_path := current_level_scene_path
	current_level_scene.queue_free()
	current_level_scene = null
	current_level_scene_path = ""

	level_unloaded.emit(old_path)


func reload_level() -> bool:
	if current_level_scene_path == "":
		return false

	return load_level(current_level_scene_path)


func get_current_main_scene() -> Node:
	return current_main_scene


func get_current_overlay_scene() -> Node:
	return current_overlay_scene


func get_current_level_scene() -> Node:
	return current_level_scene


func is_main_scene_transition_running() -> bool:
	return _main_scene_transition_running


func _get_or_create_level_container() -> Node:
	# Levels are expected to live inside the current main scene.
	# In practice, this means the main scene should usually be GameRoot.
	if current_main_scene == null:
		return null

	var level_container := current_main_scene.get_node_or_null(LEVEL_CONTAINER_PATH)
	if level_container != null:
		return level_container

	# Fallback used when the current main scene does not expose a
	# dedicated LevelContainer yet.
	level_container = Node.new()
	level_container.name = "LevelContainer"
	current_main_scene.add_child(level_container)
	return level_container


func _resolve_exit_transition_path(scene: Node, explicit_path: String) -> String:
	# Priority:
	# 1. explicit path given by caller
	# 2. transition path exposed by the scene itself
	if explicit_path != "":
		return explicit_path

	if scene != null and scene.has_method("get_exit_transition_path"):
		var path: Variant = scene.call("get_exit_transition_path")
		if path is String:
			return path

	return ""


func _resolve_enter_transition_path(scene: Node) -> String:
	# Enter transition can be provided by the new scene itself.
	if scene != null and scene.has_method("get_enter_transition_path"):
		var path: Variant = scene.call("get_enter_transition_path")
		if path is String:
			return path

	return ""


func _play_general_transition(transition_scene_path: String, phase: String) -> bool:
	# Plays a standalone transition scene inside TransitionLayer.
	# Contract expected from the transition scene:
	# - signal transition_finished
	# - method play_out() or play_in() depending on phase
	if transition_scene_path == "":
		return true

	if transition_layer == null:
		_emit_load_failed(transition_scene_path, "TransitionLayer is not configured.")
		return false

	var packed_scene: PackedScene = load(transition_scene_path) as PackedScene
	if packed_scene == null:
		_emit_load_failed(transition_scene_path, "Could not load transition PackedScene.")
		return false

	var transition_instance: Node = packed_scene.instantiate()
	if transition_instance == null:
		_emit_load_failed(transition_scene_path, "Could not instantiate transition scene.")
		return false

	transition_layer.add_child(transition_instance)

	if not transition_instance.has_signal("transition_finished"):
		transition_instance.queue_free()
		_emit_load_failed(transition_scene_path, "Transition scene is missing 'transition_finished' signal.")
		return false

	if phase == "out" and not transition_instance.has_method("play_out"):
		transition_instance.queue_free()
		_emit_load_failed(transition_scene_path, "Transition scene is missing play_out().")
		return false

	if phase == "in" and not transition_instance.has_method("play_in"):
		transition_instance.queue_free()
		_emit_load_failed(transition_scene_path, "Transition scene is missing play_in().")
		return false

	transition_started.emit(transition_scene_path, phase)

	if phase == "out":
		transition_instance.call("play_out")
	else:
		transition_instance.call("play_in")

	await transition_instance.transition_finished

	transition_finished.emit(transition_scene_path, phase)

	transition_instance.queue_free()
	await get_tree().process_frame
	return true


func _play_scene_owned_exit_transition(scene: Node) -> bool:
	# Alternative transition model:
	# the currently active scene can animate its own exit.
	if scene == null:
		return true

	if scene.has_method("play_scene_exit_transition"):
		if not scene.has_signal("scene_exit_transition_finished"):
			_emit_load_failed(current_main_scene_path, "Scene has play_scene_exit_transition() but no scene_exit_transition_finished signal.")
			return false

		scene.call("play_scene_exit_transition")
		await scene.scene_exit_transition_finished

	return true


func _play_scene_owned_enter_transition(scene: Node) -> bool:
	# Mirror of _play_scene_owned_exit_transition() for scene entry.
	if scene == null:
		return true

	if scene.has_method("play_scene_enter_transition"):
		if not scene.has_signal("scene_enter_transition_finished"):
			_emit_load_failed(current_main_scene_path, "Scene has play_scene_enter_transition() but no scene_enter_transition_finished signal.")
			return false

		scene.call("play_scene_enter_transition")
		await scene.scene_enter_transition_finished

	return true


func _emit_load_failed(scene_path: String, reason: String) -> void:
	# Centralized failure reporting for both signals and console output.
	scene_load_failed.emit(scene_path, reason)
	push_error("SceneManager load failed for '%s': %s" % [scene_path, reason])
