extends Node

var passed_count: int = 0
var failed_count: int = 0

var session_started_events: Array = []
var session_ended_events: Array = []
var session_reset_events: Array = []
var session_loaded_events: Array = []
var session_unloaded_events: Array = []

var level_changed_events: Array = []
var checkpoint_changed_events: Array = []
var cinematic_changed_events: Array = []

var state_changed_events: Array = []
var pause_changed_events: Array = []

var main_scene_changed_events: Array = []
var level_loaded_events: Array = []
var scene_load_failed_events: Array = []

var _test_root: Node = null

const TEST_LEVEL_ID := "test_level"
const TEST_LEVEL_PATH := "res://levels/test_level.tscn"
const MAIN_MENU_PATH := "res://scenes/menus/main_menu.tscn"
const LOADING_PATH := "res://scenes/common/loading_screen.tscn"
const GAME_ROOT_PATH := "res://scenes/gameplay/game_root.tscn"


func _ready() -> void:
	print("\n=== SessionManager smoke test started ===")

	_connect_signals()
	await _build_test_root()
	await _run_all_tests()

	print("\n=== SessionManager smoke test finished ===")
	print("Passed: %d" % passed_count)
	print("Failed: %d" % failed_count)

	if failed_count == 0:
		print("All tests passed.")
	else:
		push_error("Some SessionManager tests failed.")


func _connect_signals() -> void:
	if not SessionManager.session_started.is_connected(_on_session_started):
		SessionManager.session_started.connect(_on_session_started)

	if not SessionManager.session_ended.is_connected(_on_session_ended):
		SessionManager.session_ended.connect(_on_session_ended)

	if not SessionManager.session_reset.is_connected(_on_session_reset):
		SessionManager.session_reset.connect(_on_session_reset)

	if not SessionManager.session_loaded.is_connected(_on_session_loaded):
		SessionManager.session_loaded.connect(_on_session_loaded)

	if not SessionManager.session_unloaded.is_connected(_on_session_unloaded):
		SessionManager.session_unloaded.connect(_on_session_unloaded)

	if not SessionManager.level_changed.is_connected(_on_level_changed):
		SessionManager.level_changed.connect(_on_level_changed)

	if not SessionManager.checkpoint_changed.is_connected(_on_checkpoint_changed):
		SessionManager.checkpoint_changed.connect(_on_checkpoint_changed)

	if not SessionManager.cinematic_changed.is_connected(_on_cinematic_changed):
		SessionManager.cinematic_changed.connect(_on_cinematic_changed)

	if not StateManager.state_changed.is_connected(_on_state_changed):
		StateManager.state_changed.connect(_on_state_changed)

	if not StateManager.pause_changed.is_connected(_on_pause_changed):
		StateManager.pause_changed.connect(_on_pause_changed)

	if not SceneManager.main_scene_changed.is_connected(_on_main_scene_changed):
		SceneManager.main_scene_changed.connect(_on_main_scene_changed)

	if not SceneManager.level_loaded.is_connected(_on_level_loaded):
		SceneManager.level_loaded.connect(_on_level_loaded)

	if not SceneManager.scene_load_failed.is_connected(_on_scene_load_failed):
		SceneManager.scene_load_failed.connect(_on_scene_load_failed)


func _run_all_tests() -> void:
	_test_setup_scene_manager()
	_test_start_new_session()
	_test_end_session()
	_test_reset_session()
	_test_load_session_data()
	_test_level_checkpoint_cinematic_changes()
	_test_flags_and_data_helpers()
	_test_export_save_data_roundtrip()
	await _test_new_game_flow_with_state_and_scene()
	await _test_pause_flow_does_not_mutate_session()
	await _test_return_to_menu_flow()


func _test_setup_scene_manager() -> void:
	_reset_event_buffers()

	var result := SceneManager.setup(_test_root)

	_assert_true(result, "SceneManager.setup() succeeds for SessionManager integration tests")
	_assert_true(SceneManager.main_layer != null, "SceneManager main_layer is available")
	_assert_true(SceneManager.ui_layer != null, "SceneManager ui_layer is available")
	_assert_true(SceneManager.transition_layer != null, "SceneManager transition_layer is available")


func _test_start_new_session() -> void:
	_prepare_clean_environment()

	SessionManager.start_new_session(TEST_LEVEL_ID, 2)

	_assert_true(SessionManager.has_session(), "start_new_session() creates an active session")
	_assert_true(SessionManager.has_active_session, "has_active_session is true after start_new_session()")
	_assert_true(SessionManager.is_new_game, "is_new_game is true after start_new_session()")
	_assert_true(SessionManager.current_slot_id == 2, "current_slot_id is set on new session")
	_assert_true(SessionManager.get_current_level() == TEST_LEVEL_ID, "current_level_id is initialized correctly")
	_assert_true(SessionManager.get_checkpoint() == "", "checkpoint starts empty on new session")
	_assert_true(SessionManager.get_current_cinematic() == "", "current_cinematic_id starts empty on new session")
	_assert_true(SessionManager.elapsed_run_time == 0.0, "elapsed_run_time is reset on new session")
	_assert_true(session_started_events.size() == 1, "session_started is emitted once on new session")

	if session_started_events.size() == 1:
		_assert_true(session_started_events[0] == true, "session_started emits true for a fresh session")


func _test_end_session() -> void:
	_prepare_clean_environment()
	SessionManager.start_new_session(TEST_LEVEL_ID, 4)
	_reset_event_buffers()

	SessionManager.end_session()

	_assert_true(not SessionManager.has_session(), "end_session() clears the active session")
	_assert_true(not SessionManager.has_active_session, "has_active_session becomes false after end_session()")
	_assert_true(not SessionManager.is_new_game, "is_new_game becomes false after end_session()")
	_assert_true(SessionManager.current_slot_id == -1, "current_slot_id resets to -1 after end_session()")
	_assert_true(SessionManager.get_current_level() == "", "current_level_id is cleared after end_session()")
	_assert_true(SessionManager.get_checkpoint() == "", "checkpoint is cleared after end_session()")
	_assert_true(SessionManager.get_current_cinematic() == "", "current_cinematic_id is cleared after end_session()")
	_assert_true(session_ended_events.size() == 1, "session_ended is emitted once")
	_assert_true(session_unloaded_events.size() == 1, "session_unloaded is emitted once")


func _test_reset_session() -> void:
	_prepare_clean_environment()
	SessionManager.start_new_session(TEST_LEVEL_ID, 7)
	SessionManager.set_checkpoint("checkpoint_alpha")
	SessionManager.set_current_cinematic("intro_01")
	SessionManager.set_flag("visited_room", true)
	SessionManager.set_data("score", 42)
	_reset_event_buffers()

	SessionManager.reset_session()

	_assert_true(not SessionManager.has_session(), "reset_session() clears active session state")
	_assert_true(SessionManager.current_slot_id == 7, "reset_session() preserves current_slot_id")
	_assert_true(SessionManager.get_current_level() == "", "reset_session() clears current_level_id")
	_assert_true(SessionManager.get_checkpoint() == "", "reset_session() clears checkpoint_id")
	_assert_true(SessionManager.get_current_cinematic() == "", "reset_session() clears current_cinematic_id")
	_assert_true(SessionManager.get_flag("visited_room", null) == null, "reset_session() clears session_flags")
	_assert_true(SessionManager.get_data("score", null) == null, "reset_session() clears session_data")
	_assert_true(session_reset_events.size() == 1, "session_reset is emitted once")
	_assert_true(session_unloaded_events.size() == 1, "session_unloaded is emitted once after reset_session() on an active session")


func _test_load_session_data() -> void:
	_prepare_clean_environment()

	var data := {
		"current_level_id": "forest_01",
		"checkpoint_id": "cp_forest_gate",
		"current_cinematic_id": "forest_intro",
		"session_flags": {
			"intro_seen": true
		},
		"session_data": {
			"coins": 12
		},
		"elapsed_run_time": 83.5
	}

	SessionManager.load_session_data(data, 1)

	_assert_true(SessionManager.has_session(), "load_session_data() creates an active session")
	_assert_true(not SessionManager.is_new_game, "load_session_data() marks the session as not new")
	_assert_true(SessionManager.current_slot_id == 1, "load_session_data() stores the slot id")
	_assert_true(SessionManager.get_current_level() == "forest_01", "load_session_data() restores current_level_id")
	_assert_true(SessionManager.get_checkpoint() == "cp_forest_gate", "load_session_data() restores checkpoint_id")
	_assert_true(SessionManager.get_current_cinematic() == "forest_intro", "load_session_data() restores current_cinematic_id")
	_assert_true(SessionManager.get_flag("intro_seen", false) == true, "load_session_data() restores session_flags")
	_assert_true(SessionManager.get_data("coins", 0) == 12, "load_session_data() restores session_data")
	_assert_true(is_equal_approx(SessionManager.elapsed_run_time, 83.5), "load_session_data() restores elapsed_run_time")
	_assert_true(session_loaded_events.size() == 1, "session_loaded is emitted once")

	if session_loaded_events.size() == 1:
		_assert_true(session_loaded_events[0] == 1, "session_loaded emits the correct slot id")


func _test_level_checkpoint_cinematic_changes() -> void:
	_prepare_clean_environment()
	SessionManager.start_new_session(TEST_LEVEL_ID, -1)
	_reset_event_buffers()

	SessionManager.set_current_level("forest_02")
	SessionManager.set_checkpoint("cp_bridge")
	SessionManager.set_current_cinematic("mid_boss_intro")

	_assert_true(SessionManager.get_current_level() == "forest_02", "set_current_level() updates current_level_id")
	_assert_true(SessionManager.get_checkpoint() == "cp_bridge", "set_checkpoint() updates checkpoint_id")
	_assert_true(SessionManager.get_current_cinematic() == "mid_boss_intro", "set_current_cinematic() updates current_cinematic_id")

	_assert_true(level_changed_events.size() == 1, "level_changed is emitted once")
	_assert_true(checkpoint_changed_events.size() == 1, "checkpoint_changed is emitted once")
	_assert_true(cinematic_changed_events.size() == 1, "cinematic_changed is emitted once")

	if level_changed_events.size() == 1:
		_assert_true(level_changed_events[0]["from"] == TEST_LEVEL_ID, "level_changed previous level is correct")
		_assert_true(level_changed_events[0]["to"] == "forest_02", "level_changed new level is correct")

	if checkpoint_changed_events.size() == 1:
		_assert_true(checkpoint_changed_events[0]["from"] == "", "checkpoint_changed previous checkpoint is correct")
		_assert_true(checkpoint_changed_events[0]["to"] == "cp_bridge", "checkpoint_changed new checkpoint is correct")

	if cinematic_changed_events.size() == 1:
		_assert_true(cinematic_changed_events[0]["from"] == "", "cinematic_changed previous cinematic is correct")
		_assert_true(cinematic_changed_events[0]["to"] == "mid_boss_intro", "cinematic_changed new cinematic is correct")


func _test_flags_and_data_helpers() -> void:
	_prepare_clean_environment()
	SessionManager.start_new_session(TEST_LEVEL_ID, -1)

	SessionManager.set_flag("door_open", true)
	SessionManager.set_data("player_hp", 3)

	_assert_true(SessionManager.get_flag("door_open", false) == true, "set_flag()/get_flag() work")
	_assert_true(SessionManager.get_data("player_hp", 0) == 3, "set_data()/get_data() work")

	SessionManager.clear_flag("door_open")
	SessionManager.clear_data("player_hp")

	_assert_true(SessionManager.get_flag("door_open", null) == null, "clear_flag() removes the flag")
	_assert_true(SessionManager.get_data("player_hp", null) == null, "clear_data() removes the data")


func _test_export_save_data_roundtrip() -> void:
	_prepare_clean_environment()
	SessionManager.start_new_session(TEST_LEVEL_ID, 5)
	SessionManager.set_checkpoint("cp_lab")
	SessionManager.set_current_cinematic("lab_intro")
	SessionManager.set_flag("boss_defeated", true)
	SessionManager.set_data("keys", 2)
	SessionManager.elapsed_run_time = 14.25

	var exported := SessionManager.export_save_data()

	_assert_true(exported.get("current_level_id", "") == TEST_LEVEL_ID, "export_save_data() exports current_level_id")
	_assert_true(exported.get("checkpoint_id", "") == "cp_lab", "export_save_data() exports checkpoint_id")
	_assert_true(exported.get("current_cinematic_id", "") == "lab_intro", "export_save_data() exports current_cinematic_id")
	_assert_true(exported.get("session_flags", {}).get("boss_defeated", false) == true, "export_save_data() exports session_flags")
	_assert_true(exported.get("session_data", {}).get("keys", 0) == 2, "export_save_data() exports session_data")
	_assert_true(is_equal_approx(float(exported.get("elapsed_run_time", 0.0)), 14.25), "export_save_data() exports elapsed_run_time")

	_prepare_clean_environment()
	SessionManager.load_session_data(exported, 5)

	_assert_true(SessionManager.current_slot_id == 5, "Round-trip reload preserves slot id")
	_assert_true(SessionManager.get_current_level() == TEST_LEVEL_ID, "Round-trip reload preserves current_level_id")
	_assert_true(SessionManager.get_checkpoint() == "cp_lab", "Round-trip reload preserves checkpoint_id")
	_assert_true(SessionManager.get_current_cinematic() == "lab_intro", "Round-trip reload preserves current_cinematic_id")
	_assert_true(SessionManager.get_flag("boss_defeated", false) == true, "Round-trip reload preserves flags")
	_assert_true(SessionManager.get_data("keys", 0) == 2, "Round-trip reload preserves data")


func _test_new_game_flow_with_state_and_scene() -> void:
	_prepare_clean_environment()

	SessionManager.start_new_session(TEST_LEVEL_ID, 3)

	var loading_state_ok := StateManager.set_state(GameStates.State.LOADING)
	_assert_true(loading_state_ok, "StateManager accepts LOADING during new game flow")

	var loading_scene_ok := SceneManager.load_main_scene_from_state(GameStates.State.LOADING)
	_assert_true(loading_scene_ok, "SceneManager loads the LOADING scene during new game flow")

	var in_game_state_ok := StateManager.set_state(GameStates.State.IN_GAME)
	_assert_true(in_game_state_ok, "StateManager accepts IN_GAME during new game flow")

	var game_root_ok := SceneManager.change_main_scene(GAME_ROOT_PATH)
	_assert_true(game_root_ok, "SceneManager loads game_root during new game flow")

	var level_ok := SceneManager.load_level(TEST_LEVEL_PATH)
	_assert_true(level_ok, "SceneManager loads the level indicated by the session during new game flow")

	_assert_true(SessionManager.get_current_level() == TEST_LEVEL_ID, "SessionManager still tracks the correct current level")
	_assert_true(SceneManager.current_main_scene_path == GAME_ROOT_PATH, "SceneManager main scene path is correct during gameplay")
	_assert_true(SceneManager.current_level_scene_path == TEST_LEVEL_PATH, "SceneManager level path is correct during gameplay")
	_assert_true(StateManager.is_in_state(GameStates.State.IN_GAME), "Global state is IN_GAME after new game flow")
	_assert_true(main_scene_changed_events.size() >= 2, "Main scene changed at least twice during the new game flow")
	_assert_true(level_loaded_events.size() == 1, "A level_loaded signal is emitted during the new game flow")
	_assert_true(scene_load_failed_events.is_empty(), "No scene load failure occurs during the new game flow")


func _test_pause_flow_does_not_mutate_session() -> void:
	_prepare_clean_environment()
	SessionManager.start_new_session(TEST_LEVEL_ID, 6)

	StateManager.set_state(GameStates.State.LOADING)
	SceneManager.load_main_scene_from_state(GameStates.State.LOADING)
	StateManager.set_state(GameStates.State.IN_GAME)
	SceneManager.change_main_scene(GAME_ROOT_PATH)
	SceneManager.load_level(TEST_LEVEL_PATH)

	_reset_event_buffers()

	var pause_ok := StateManager.set_paused(true)
	_assert_true(pause_ok, "StateManager accepts pause during gameplay")
	_assert_true(StateManager.is_paused, "StateManager pause flag becomes true")

	SceneManager.open_overlay("res://scenes/menus/pause_menu.tscn")

	_assert_true(SessionManager.has_session(), "Pausing does not destroy the session")
	_assert_true(SessionManager.get_current_level() == TEST_LEVEL_ID, "Pausing does not change current_level_id")
	_assert_true(SceneManager.current_overlay_scene_path == "res://scenes/menus/pause_menu.tscn", "Pause overlay opens correctly")

	SceneManager.close_overlay()
	StateManager.set_paused(false)

	_assert_true(not StateManager.is_paused, "StateManager pause flag clears correctly")
	_assert_true(SessionManager.get_current_level() == TEST_LEVEL_ID, "Unpausing does not change current_level_id")


func _test_return_to_menu_flow() -> void:
	_prepare_clean_environment()
	SessionManager.start_new_session(TEST_LEVEL_ID, 8)

	StateManager.set_state(GameStates.State.LOADING)
	SceneManager.load_main_scene_from_state(GameStates.State.LOADING)
	StateManager.set_state(GameStates.State.IN_GAME)
	SceneManager.change_main_scene(GAME_ROOT_PATH)
	SceneManager.load_level(TEST_LEVEL_PATH)

	_reset_event_buffers()

	SessionManager.end_session()
	StateManager.set_paused(false)
	var state_ok := StateManager.set_state(GameStates.State.MAIN_MENU)
	var scene_ok := SceneManager.change_main_scene(MAIN_MENU_PATH)

	_assert_true(state_ok, "StateManager accepts MAIN_MENU during return-to-menu flow")
	_assert_true(scene_ok, "SceneManager loads main_menu during return-to-menu flow")
	_assert_true(not SessionManager.has_session(), "SessionManager has no active session after return-to-menu flow")
	_assert_true(StateManager.is_in_state(GameStates.State.MAIN_MENU), "Global state is MAIN_MENU after return-to-menu flow")
	_assert_true(SceneManager.current_main_scene_path == MAIN_MENU_PATH, "Main scene path is main_menu after return-to-menu flow")


func _prepare_clean_environment() -> void:
	SessionManager.reset_session()
	StateManager.reset_to_boot()
	StateManager.unlock_state()
	StateManager.set_paused(false)

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

	await get_tree().process_frame


func _reset_event_buffers() -> void:
	session_started_events.clear()
	session_ended_events.clear()
	session_reset_events.clear()
	session_loaded_events.clear()
	session_unloaded_events.clear()

	level_changed_events.clear()
	checkpoint_changed_events.clear()
	cinematic_changed_events.clear()

	state_changed_events.clear()
	pause_changed_events.clear()

	main_scene_changed_events.clear()
	level_loaded_events.clear()
	scene_load_failed_events.clear()


func _on_session_started(is_new_game: bool) -> void:
	session_started_events.append(is_new_game)


func _on_session_ended() -> void:
	session_ended_events.append(true)


func _on_session_reset() -> void:
	session_reset_events.append(true)


func _on_session_loaded(slot_id: int) -> void:
	session_loaded_events.append(slot_id)


func _on_session_unloaded() -> void:
	session_unloaded_events.append(true)


func _on_level_changed(previous_level_id: String, new_level_id: String) -> void:
	level_changed_events.append({
		"from": previous_level_id,
		"to": new_level_id,
	})


func _on_checkpoint_changed(previous_checkpoint_id: String, new_checkpoint_id: String) -> void:
	checkpoint_changed_events.append({
		"from": previous_checkpoint_id,
		"to": new_checkpoint_id,
	})


func _on_cinematic_changed(previous_cinematic_id: String, new_cinematic_id: String) -> void:
	cinematic_changed_events.append({
		"from": previous_cinematic_id,
		"to": new_cinematic_id,
	})


func _on_state_changed(previous_state: int, new_state: int) -> void:
	state_changed_events.append({
		"from": previous_state,
		"to": new_state,
	})


func _on_pause_changed(is_paused: bool) -> void:
	pause_changed_events.append(is_paused)


func _on_main_scene_changed(old_scene: Node, new_scene: Node, scene_path: String) -> void:
	main_scene_changed_events.append({
		"old_scene": old_scene,
		"new_scene": new_scene,
		"scene_path": scene_path,
	})


func _on_level_loaded(level_scene: Node, scene_path: String) -> void:
	level_loaded_events.append({
		"level_scene": level_scene,
		"scene_path": scene_path,
	})


func _on_scene_load_failed(scene_path: String, reason: String) -> void:
	scene_load_failed_events.append({
		"scene_path": scene_path,
		"reason": reason,
	})


func _assert_true(condition: bool, message: String) -> void:
	if condition:
		passed_count += 1
		print("  [PASS] %s" % message)
	else:
		failed_count += 1
		push_error("  [FAIL] %s" % message)
