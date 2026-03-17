extends Node

var passed_count: int = 0
var failed_count: int = 0

var main_scene_changed_events: Array = []
var overlay_opened_events: Array = []
var overlay_closed_events: Array = []
var level_loaded_events: Array = []
var level_unloaded_events: Array = []
var scene_load_failed_events: Array = []

var transition_started_events: Array = []
var transition_finished_events: Array = []

var _test_root: Node = null


func _ready() -> void:
	print("\n=== SceneManager smoke test started ===")

	_connect_signals()
	await _build_test_root()
	await _run_all_tests()

	print("\n=== SceneManager smoke test finished ===")
	print("Passed: %d" % passed_count)
	print("Failed: %d" % failed_count)

	if failed_count == 0:
		print("All tests passed.")
	else:
		push_error("Some SceneManager tests failed.")


func _connect_signals() -> void:
	if not SceneManager.main_scene_changed.is_connected(_on_main_scene_changed):
		SceneManager.main_scene_changed.connect(_on_main_scene_changed)

	if not SceneManager.overlay_opened.is_connected(_on_overlay_opened):
		SceneManager.overlay_opened.connect(_on_overlay_opened)

	if not SceneManager.overlay_closed.is_connected(_on_overlay_closed):
		SceneManager.overlay_closed.connect(_on_overlay_closed)

	if not SceneManager.level_loaded.is_connected(_on_level_loaded):
		SceneManager.level_loaded.connect(_on_level_loaded)

	if not SceneManager.level_unloaded.is_connected(_on_level_unloaded):
		SceneManager.level_unloaded.connect(_on_level_unloaded)

	if not SceneManager.scene_load_failed.is_connected(_on_scene_load_failed):
		SceneManager.scene_load_failed.connect(_on_scene_load_failed)

	if not SceneManager.transition_started.is_connected(_on_transition_started):
		SceneManager.transition_started.connect(_on_transition_started)

	if not SceneManager.transition_finished.is_connected(_on_transition_finished):
		SceneManager.transition_finished.connect(_on_transition_finished)


func _run_all_tests() -> void:
	_test_setup()
	_test_change_main_scene()
	_test_reload_main_scene()
	_test_open_and_close_overlay()
	_test_load_and_unload_level()
	_test_invalid_scene_load()
	_test_invalid_overlay_load()
	_test_invalid_level_load()

	await _test_transition_to_main_scene_with_general_transitions()
	_test_load_main_scene_from_state()
	_test_sync_main_scene_with_state()
	await _test_transition_main_scene_from_state_with_general_transitions()
	await _test_sync_main_scene_with_state_transition()
	await _test_invalid_general_transition_path()
	await _test_scene_owned_enter_and_exit_transitions()


func _test_setup() -> void:
	_reset_event_buffers()

	var result := SceneManager.setup(_test_root)

	_assert_true(result, "setup() succeeds with a valid test root")
	_assert_true(SceneManager.main_layer != null, "main_layer is cached after setup")
	_assert_true(SceneManager.ui_layer != null, "ui_layer is cached after setup")
	_assert_true(SceneManager.transition_layer != null, "transition_layer is cached after setup")


func _test_change_main_scene() -> void:
	_prepare_clean_scene_manager()

	var result := SceneManager.change_main_scene("res://scenes/menus/main_menu.tscn")

	_assert_true(result, "change_main_scene() succeeds with main_menu.tscn")
	_assert_true(SceneManager.get_current_main_scene() != null, "Current main scene is set")
	_assert_true(SceneManager.current_main_scene_path == "res://scenes/menus/main_menu.tscn", "Main scene path is updated")
	_assert_true(main_scene_changed_events.size() == 1, "main_scene_changed is emitted once")

	var main_layer: Node = SceneManager.main_layer
	_assert_true(main_layer.get_child_count() == 1, "MainLayer contains one scene after change_main_scene()")


func _test_reload_main_scene() -> void:
	_prepare_clean_scene_manager()
	SceneManager.change_main_scene("res://scenes/menus/main_menu.tscn")
	_reset_event_buffers()

	var previous_scene := SceneManager.get_current_main_scene()
	var result := SceneManager.reload_main_scene()

	_assert_true(result, "reload_main_scene() succeeds when a main scene is loaded")
	_assert_true(SceneManager.get_current_main_scene() != null, "A main scene still exists after reload")
	_assert_true(SceneManager.get_current_main_scene() != previous_scene, "reload_main_scene() replaces the previous scene instance")
	_assert_true(main_scene_changed_events.size() == 1, "reload_main_scene() emits one main_scene_changed signal")


func _test_open_and_close_overlay() -> void:
	_prepare_clean_scene_manager()
	_reset_event_buffers()

	var open_result := SceneManager.open_overlay("res://scenes/menus/pause_menu.tscn")

	_assert_true(open_result, "open_overlay() succeeds with pause_menu.tscn")
	_assert_true(SceneManager.get_current_overlay_scene() != null, "Current overlay scene is set")
	_assert_true(SceneManager.current_overlay_scene_path == "res://scenes/menus/pause_menu.tscn", "Overlay scene path is updated")
	_assert_true(overlay_opened_events.size() == 1, "overlay_opened is emitted once")

	SceneManager.close_overlay()

	_assert_true(SceneManager.get_current_overlay_scene() == null, "close_overlay() clears the current overlay")
	_assert_true(SceneManager.current_overlay_scene_path == "", "close_overlay() clears the overlay path")
	_assert_true(overlay_closed_events.size() == 1, "overlay_closed is emitted once")


func _test_load_and_unload_level() -> void:
	_prepare_clean_scene_manager()

	var main_scene_ok := SceneManager.change_main_scene("res://scenes/gameplay/game_root.tscn")
	_assert_true(main_scene_ok, "game_root.tscn can be set as the current main scene")

	_reset_event_buffers()

	var load_result := SceneManager.load_level("res://levels/test_level.tscn")

	_assert_true(load_result, "load_level() succeeds with test_level.tscn")
	_assert_true(SceneManager.get_current_level_scene() != null, "Current level scene is set")
	_assert_true(SceneManager.current_level_scene_path == "res://levels/test_level.tscn", "Level scene path is updated")
	_assert_true(level_loaded_events.size() == 1, "level_loaded is emitted once")

	SceneManager.unload_level()

	_assert_true(SceneManager.get_current_level_scene() == null, "unload_level() clears the current level")
	_assert_true(SceneManager.current_level_scene_path == "", "unload_level() clears the level path")
	_assert_true(level_unloaded_events.size() == 1, "level_unloaded is emitted once")


func _test_invalid_scene_load() -> void:
	_prepare_clean_scene_manager()
	_reset_event_buffers()

	var result := SceneManager.change_main_scene("res://scenes/menus/does_not_exist.tscn")

	_assert_true(not result, "change_main_scene() fails on an invalid path")
	_assert_true(scene_load_failed_events.size() == 1, "scene_load_failed is emitted for invalid main scene load")


func _test_invalid_overlay_load() -> void:
	_prepare_clean_scene_manager()
	_reset_event_buffers()

	var result := SceneManager.open_overlay("res://scenes/menus/does_not_exist.tscn")

	_assert_true(not result, "open_overlay() fails on an invalid path")
	_assert_true(scene_load_failed_events.size() == 1, "scene_load_failed is emitted for invalid overlay load")


func _test_invalid_level_load() -> void:
	_prepare_clean_scene_manager()
	SceneManager.change_main_scene("res://scenes/gameplay/game_root.tscn")
	_reset_event_buffers()

	var result := SceneManager.load_level("res://levels/does_not_exist.tscn")

	_assert_true(not result, "load_level() fails on an invalid path")
	_assert_true(scene_load_failed_events.size() == 1, "scene_load_failed is emitted for invalid level load")


func _test_transition_to_main_scene_with_general_transitions() -> void:
	_prepare_clean_scene_manager()
	SceneManager.change_main_scene("res://scenes/menus/main_menu.tscn")
	_reset_event_buffers()

	var transition_path := "res://core/transitions/transition_scenes/fade_black.tscn"
	var result := await SceneManager.transition_to_main_scene(
		"res://scenes/common/loading_screen.tscn",
		transition_path,
		transition_path
	)

	_assert_true(result, "transition_to_main_scene() succeeds with general enter/exit transitions")
	_assert_true(SceneManager.get_current_main_scene() != null, "Current main scene is still valid after transition")
	_assert_true(SceneManager.current_main_scene_path == "res://scenes/common/loading_screen.tscn", "Main scene path is updated after transitioned change")

	_assert_true(transition_started_events.size() == 2, "Two transition_started events are emitted for exit and enter")
	_assert_true(transition_finished_events.size() == 2, "Two transition_finished events are emitted for exit and enter")

	if transition_started_events.size() == 2:
		_assert_true(transition_started_events[0]["phase"] == "out", "First started transition phase is out")
		_assert_true(transition_started_events[1]["phase"] == "in", "Second started transition phase is in")

	if transition_finished_events.size() == 2:
		_assert_true(transition_finished_events[0]["phase"] == "out", "First finished transition phase is out")
		_assert_true(transition_finished_events[1]["phase"] == "in", "Second finished transition phase is in")


func _test_load_main_scene_from_state() -> void:
	_prepare_clean_scene_manager()
	_reset_event_buffers()

	var result := SceneManager.load_main_scene_from_state(GameStates.State.MAIN_MENU)

	_assert_true(result, "load_main_scene_from_state() succeeds for MAIN_MENU")
	_assert_true(SceneManager.current_main_scene_path == "res://scenes/menus/main_menu.tscn", "load_main_scene_from_state() loads the mapped main scene")
	_assert_true(main_scene_changed_events.size() == 1, "load_main_scene_from_state() emits one main_scene_changed signal")


func _test_sync_main_scene_with_state() -> void:
	_prepare_clean_scene_manager()
	_reset_event_buffers()

	var result := SceneManager.sync_main_scene_with_state(GameStates.State.TITLE)

	_assert_true(result, "sync_main_scene_with_state() succeeds for TITLE")
	_assert_true(SceneManager.current_main_scene_path == "res://scenes/menus/title_screen.tscn", "sync_main_scene_with_state() loads the mapped main scene")
	_assert_true(main_scene_changed_events.size() == 1, "sync_main_scene_with_state() emits one main_scene_changed signal")


func _test_transition_main_scene_from_state_with_general_transitions() -> void:
	_prepare_clean_scene_manager()
	SceneManager.change_main_scene("res://scenes/menus/title_screen.tscn")
	_reset_event_buffers()

	var transition_path := "res://core/transitions/transition_scenes/fade_black.tscn"
	var result := await SceneManager.transition_main_scene_from_state(
		GameStates.State.MAIN_MENU,
		transition_path,
		transition_path
	)

	_assert_true(result, "transition_main_scene_from_state() succeeds for TITLE -> MAIN_MENU")
	_assert_true(SceneManager.current_main_scene_path == "res://scenes/menus/main_menu.tscn", "transition_main_scene_from_state() loads the mapped main scene")
	_assert_true(transition_started_events.size() == 2, "transition_main_scene_from_state() emits two transition_started events")
	_assert_true(transition_finished_events.size() == 2, "transition_main_scene_from_state() emits two transition_finished events")


func _test_sync_main_scene_with_state_transition() -> void:
	_prepare_clean_scene_manager()
	SceneManager.change_main_scene("res://scenes/menus/title_screen.tscn")
	_reset_event_buffers()

	var result := await SceneManager.sync_main_scene_with_state_transition(
		GameStates.State.TITLE,
		GameStates.State.MAIN_MENU
	)

	_assert_true(result, "sync_main_scene_with_state_transition() succeeds for TITLE -> MAIN_MENU")
	_assert_true(SceneManager.current_main_scene_path == "res://scenes/menus/main_menu.tscn", "sync_main_scene_with_state_transition() loads the mapped main scene")


func _test_invalid_general_transition_path() -> void:
	_prepare_clean_scene_manager()
	SceneManager.change_main_scene("res://scenes/menus/main_menu.tscn")
	_reset_event_buffers()

	var result := await SceneManager.transition_to_main_scene(
		"res://scenes/common/loading_screen.tscn",
		"res://core/transitions/transition_scenes/does_not_exist.tscn",
		""
	)

	_assert_true(not result, "transition_to_main_scene() fails if the exit transition path is invalid")
	_assert_true(scene_load_failed_events.size() == 1, "scene_load_failed is emitted for invalid transition path")


func _test_scene_owned_enter_and_exit_transitions() -> void:
	_prepare_clean_scene_manager()

	var first_scene_ok := SceneManager.change_main_scene("res://tests/smoke/scene_manager_assets/transition_dummy_scene_a.tscn")
	_assert_true(first_scene_ok, "transition_dummy_scene_a.tscn can be loaded as current main scene")

	_reset_event_buffers()

	var result := await SceneManager.transition_to_main_scene(
		"res://tests/smoke/scene_manager_assets/transition_dummy_scene_b.tscn"
	)

	_assert_true(result, "transition_to_main_scene() succeeds with scene-owned transition fallback")
	_assert_true(
		SceneManager.current_main_scene_path == "res://tests/smoke/scene_manager_assets/transition_dummy_scene_b.tscn",
		"Scene path updates correctly after scene-owned transition"
	)

	# No general transition scene should have been played here.
	_assert_true(
		transition_started_events.is_empty(),
		"No general transition_started signal is emitted when only scene-owned transitions are used"
	)
	_assert_true(
		transition_finished_events.is_empty(),
		"No general transition_finished signal is emitted when only scene-owned transitions are used"
	)


func _prepare_clean_scene_manager() -> void:
	_clear_children(SceneManager.main_layer)
	_clear_children(SceneManager.ui_layer)
	_clear_children(SceneManager.transition_layer)

	SceneManager.current_main_scene = null
	SceneManager.current_overlay_scene = null
	SceneManager.current_level_scene = null

	SceneManager.current_main_scene_path = ""
	SceneManager.current_overlay_scene_path = ""
	SceneManager.current_level_scene_path = ""

	_reset_event_buffers()


func _build_test_root() -> void:
	if _test_root != null:
		_test_root.queue_free()
		await get_tree().process_frame

	_test_root = Node.new()
	_test_root.name = "AppRootTest"

	var main_layer := Node.new()
	main_layer.name = "MainLayer"
	_test_root.add_child(main_layer)

	var ui_layer := CanvasLayer.new()
	ui_layer.name = "UILayer"
	_test_root.add_child(ui_layer)

	var transition_layer := CanvasLayer.new()
	transition_layer.name = "TransitionLayer"
	_test_root.add_child(transition_layer)

	add_child(_test_root)


func _clear_children(node: Node) -> void:
	if node == null:
		return

	for child in node.get_children():
		child.queue_free()


func _reset_event_buffers() -> void:
	main_scene_changed_events.clear()
	overlay_opened_events.clear()
	overlay_closed_events.clear()
	level_loaded_events.clear()
	level_unloaded_events.clear()
	scene_load_failed_events.clear()
	transition_started_events.clear()
	transition_finished_events.clear()


func _on_main_scene_changed(old_scene: Node, new_scene: Node, scene_path: String) -> void:
	main_scene_changed_events.append({
		"old_scene": old_scene,
		"new_scene": new_scene,
		"scene_path": scene_path,
	})


func _on_overlay_opened(scene: Node, scene_path: String) -> void:
	overlay_opened_events.append({
		"scene": scene,
		"scene_path": scene_path,
	})


func _on_overlay_closed(scene_path: String) -> void:
	overlay_closed_events.append(scene_path)


func _on_level_loaded(level_scene: Node, scene_path: String) -> void:
	level_loaded_events.append({
		"level_scene": level_scene,
		"scene_path": scene_path,
	})


func _on_level_unloaded(scene_path: String) -> void:
	level_unloaded_events.append(scene_path)


func _on_scene_load_failed(scene_path: String, reason: String) -> void:
	scene_load_failed_events.append({
		"scene_path": scene_path,
		"reason": reason,
	})


func _on_transition_started(transition_path: String, phase: String) -> void:
	transition_started_events.append({
		"transition_path": transition_path,
		"phase": phase,
	})


func _on_transition_finished(transition_path: String, phase: String) -> void:
	transition_finished_events.append({
		"transition_path": transition_path,
		"phase": phase,
	})


func _assert_true(condition: bool, message: String) -> void:
	if condition:
		passed_count += 1
		print("  [PASS] %s" % message)
	else:
		failed_count += 1
		push_error("  [FAIL] %s" % message)
