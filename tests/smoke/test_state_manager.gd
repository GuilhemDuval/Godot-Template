extends Node

var passed_count: int = 0
var failed_count: int = 0

var state_changed_events: Array = []
var pause_changed_events: Array = []
var rejected_events: Array = []


func _ready() -> void:
	print("\n=== StateManager smoke test started ===")

	_connect_signals()
	_reset_event_buffers()

	_run_all_tests()

	print("\n=== StateManager smoke test finished ===")
	print("Passed: %d" % passed_count)
	print("Failed: %d" % failed_count)

	if failed_count == 0:
		print("All tests passed.")
	else:
		push_error("Some StateManager tests failed.")


func _connect_signals() -> void:
	if not StateManager.state_changed.is_connected(_on_state_changed):
		StateManager.state_changed.connect(_on_state_changed)

	if not StateManager.pause_changed.is_connected(_on_pause_changed):
		StateManager.pause_changed.connect(_on_pause_changed)

	if not StateManager.state_change_rejected.is_connected(_on_state_change_rejected):
		StateManager.state_change_rejected.connect(_on_state_change_rejected)


func _run_all_tests() -> void:
	_test_initial_reset()
	_test_valid_transition()
	_test_same_state_is_no_op()
	_test_invalid_transition_is_rejected()
	_test_invalid_state_is_rejected()
	_test_state_helpers()
	_test_pause_allowed_in_game()
	_test_pause_forbidden_in_menu()
	_test_pause_cleared_on_non_pausable_transition()
	_test_lock_blocks_transition()
	_test_reset_to_boot()
	_test_get_state_name()
	_test_can_transition_to()
	_test_can_pause_in_state()


func _test_initial_reset() -> void:
	_prepare_clean_state()

	_assert_true(StateManager.get_state() == GameStates.State.BOOT, "Initial reset puts current state to BOOT")
	_assert_true(StateManager.get_previous_state() == GameStates.State.BOOT, "Initial reset puts previous state to BOOT")
	_assert_true(not StateManager.is_paused, "Initial reset clears pause")
	_assert_true(not StateManager.is_locked(), "Initial reset clears lock")


func _test_valid_transition() -> void:
	_prepare_clean_state()

	var result := StateManager.set_state(GameStates.State.MAIN_MENU)

	_assert_true(result, "BOOT -> MAIN_MENU is allowed")
	_assert_true(StateManager.get_state() == GameStates.State.MAIN_MENU, "Current state becomes MAIN_MENU")
	_assert_true(StateManager.get_previous_state() == GameStates.State.BOOT, "Previous state becomes BOOT")

	_assert_true(state_changed_events.size() == 1, "Valid transition emits one state_changed signal")
	if state_changed_events.size() == 1:
		_assert_true(state_changed_events[0]["from"] == GameStates.State.BOOT, "state_changed previous_state is correct")
		_assert_true(state_changed_events[0]["to"] == GameStates.State.MAIN_MENU, "state_changed new_state is correct")


func _test_same_state_is_no_op() -> void:
	_prepare_clean_state()
	StateManager.set_state(GameStates.State.MAIN_MENU)
	_reset_event_buffers()

	var result := StateManager.set_state(GameStates.State.MAIN_MENU)

	_assert_true(result, "Setting the same state returns true")
	_assert_true(StateManager.get_state() == GameStates.State.MAIN_MENU, "Current state stays MAIN_MENU")
	_assert_true(state_changed_events.is_empty(), "Same-state request emits no state_changed signal")
	_assert_true(rejected_events.is_empty(), "Same-state request emits no rejection signal")


func _test_invalid_transition_is_rejected() -> void:
	_prepare_clean_state()
	StateManager.set_state(GameStates.State.MAIN_MENU)
	_reset_event_buffers()

	var result := StateManager.set_state(GameStates.State.IN_GAME)

	_assert_true(not result, "MAIN_MENU -> IN_GAME is rejected if not explicitly allowed")
	_assert_true(StateManager.get_state() == GameStates.State.MAIN_MENU, "Current state remains MAIN_MENU after invalid transition")
	_assert_true(rejected_events.size() == 1, "Invalid transition emits one rejection signal")


func _test_invalid_state_is_rejected() -> void:
	_prepare_clean_state()
	_reset_event_buffers()

	var invalid_state := 999999
	var result := StateManager.set_state(invalid_state)

	_assert_true(not result, "Invalid target state is rejected")
	_assert_true(StateManager.get_state() == GameStates.State.BOOT, "Current state stays unchanged after invalid state request")
	_assert_true(rejected_events.size() == 1, "Invalid target state emits one rejection signal")


func _test_state_helpers() -> void:
	_prepare_clean_state()
	StateManager.set_state(GameStates.State.LOADING)

	_assert_true(StateManager.is_in_state(GameStates.State.LOADING), "is_in_state works for current state")
	_assert_true(not StateManager.is_in_state(GameStates.State.IN_GAME), "is_in_state returns false for another state")

	_assert_true(
		StateManager.get_state_category() == GameStates.Category.LOADING,
		"get_state_category() uses current state by default"
	)

	_assert_true(
		StateManager.get_state_category(GameStates.State.IN_GAME) == GameStates.Category.GAMEPLAY,
		"get_state_category(state) works with explicit state"
	)

	_assert_true(StateManager.is_loading_state(), "is_loading_state() works")
	_assert_true(StateManager.is_gameplay_state(GameStates.State.IN_GAME), "is_gameplay_state(state) works")
	_assert_true(StateManager.is_ui_state(GameStates.State.MAIN_MENU), "is_ui_state(state) works")
	_assert_true(StateManager.is_cinematic_state(GameStates.State.CUTSCENE), "is_cinematic_state(state) works")


func _test_pause_allowed_in_game() -> void:
	_prepare_clean_state()
	StateManager.set_state(GameStates.State.MAIN_MENU)
	StateManager.set_state(GameStates.State.LOADING)
	StateManager.set_state(GameStates.State.IN_GAME)
	_reset_event_buffers()

	var result := StateManager.set_paused(true)

	_assert_true(result, "Pause is allowed in IN_GAME")
	_assert_true(StateManager.is_paused, "Pause flag becomes true")
	_assert_true(pause_changed_events.size() == 1, "Pausing emits one pause_changed signal")
	if pause_changed_events.size() == 1:
		_assert_true(pause_changed_events[0] == true, "pause_changed emits true when pausing")

	var toggle_result := StateManager.toggle_pause()

	_assert_true(toggle_result, "toggle_pause() succeeds when unpausing")
	_assert_true(not StateManager.is_paused, "toggle_pause() clears pause")
	_assert_true(pause_changed_events.size() == 2, "Unpausing emits a second pause_changed signal")
	if pause_changed_events.size() == 2:
		_assert_true(pause_changed_events[1] == false, "pause_changed emits false when unpausing")


func _test_pause_forbidden_in_menu() -> void:
	_prepare_clean_state()
	StateManager.set_state(GameStates.State.MAIN_MENU)
	_reset_event_buffers()

	var result := StateManager.set_paused(true)

	_assert_true(not result, "Pause is rejected in MAIN_MENU")
	_assert_true(not StateManager.is_paused, "Pause flag stays false when pause is forbidden")
	_assert_true(pause_changed_events.is_empty(), "Rejected pause emits no pause_changed signal")


func _test_pause_cleared_on_non_pausable_transition() -> void:
	_prepare_clean_state()
	StateManager.set_state(GameStates.State.MAIN_MENU)
	StateManager.set_state(GameStates.State.LOADING)
	StateManager.set_state(GameStates.State.IN_GAME)
	StateManager.set_paused(true)
	_reset_event_buffers()

	var result := StateManager.set_state(GameStates.State.OPTIONS)

	_assert_true(result, "IN_GAME -> OPTIONS is allowed")
	_assert_true(StateManager.get_state() == GameStates.State.OPTIONS, "Current state becomes OPTIONS")
	_assert_true(not StateManager.is_paused, "Pause is automatically cleared when entering a non-pausable state")

	_assert_true(pause_changed_events.size() == 1, "Auto-unpause emits one pause_changed signal")
	if pause_changed_events.size() == 1:
		_assert_true(pause_changed_events[0] == false, "Auto-unpause emits false")


func _test_lock_blocks_transition() -> void:
	_prepare_clean_state()
	_reset_event_buffers()

	StateManager.lock_state()
	var result := StateManager.set_state(GameStates.State.MAIN_MENU)

	_assert_true(not result, "Locked state manager rejects transitions")
	_assert_true(StateManager.get_state() == GameStates.State.BOOT, "Current state stays unchanged while locked")
	_assert_true(rejected_events.size() == 1, "Rejected transition while locked emits one rejection signal")

	StateManager.unlock_state()
	_assert_true(not StateManager.is_locked(), "unlock_state() clears the lock")


func _test_reset_to_boot() -> void:
	_prepare_clean_state()
	StateManager.set_state(GameStates.State.MAIN_MENU)
	StateManager.set_state(GameStates.State.LOADING)
	StateManager.set_state(GameStates.State.IN_GAME)
	StateManager.set_paused(true)
	StateManager.lock_state()
	_reset_event_buffers()

	StateManager.reset_to_boot()

	_assert_true(StateManager.get_state() == GameStates.State.BOOT, "reset_to_boot() restores BOOT as current state")
	_assert_true(StateManager.get_previous_state() == GameStates.State.IN_GAME, "reset_to_boot() preserves the previous state information")
	_assert_true(not StateManager.is_paused, "reset_to_boot() clears pause")
	_assert_true(not StateManager.is_locked(), "reset_to_boot() clears lock")

	_assert_true(state_changed_events.size() == 1, "reset_to_boot() emits one state_changed signal")
	_assert_true(pause_changed_events.size() == 1, "reset_to_boot() emits one pause_changed signal if pause was active")


func _test_get_state_name() -> void:
	_prepare_clean_state()

	_assert_true(StateManager.get_state_name() == "BOOT", "get_state_name() uses current state by default")
	_assert_true(
		StateManager.get_state_name(GameStates.State.IN_GAME) == "IN_GAME",
		"get_state_name(state) works with explicit state"
	)
	_assert_true(StateManager.get_state_name(999999) == "UNKNOWN", "get_state_name() returns UNKNOWN for invalid state")


func _test_can_transition_to() -> void:
	_prepare_clean_state()

	_assert_true(
		StateManager.can_transition_to(GameStates.State.MAIN_MENU),
		"can_transition_to() returns true for an allowed transition from BOOT"
	)
	_assert_true(
		not StateManager.can_transition_to(GameStates.State.IN_GAME),
		"can_transition_to() returns false for a forbidden transition from BOOT"
	)

	StateManager.set_state(GameStates.State.MAIN_MENU)
	_assert_true(
		StateManager.can_transition_to(GameStates.State.LOADING),
		"can_transition_to() returns true for MAIN_MENU -> LOADING"
	)
	_assert_true(
		not StateManager.can_transition_to(GameStates.State.IN_GAME),
		"can_transition_to() returns false for MAIN_MENU -> IN_GAME"
	)


func _test_can_pause_in_state() -> void:
	_prepare_clean_state()

	_assert_true(
		not StateManager.can_pause_in_state(),
		"can_pause_in_state() uses current state by default"
	)
	_assert_true(
		StateManager.can_pause_in_state(GameStates.State.IN_GAME),
		"can_pause_in_state(state) returns true for IN_GAME"
	)
	_assert_true(
		StateManager.can_pause_in_state(GameStates.State.CUTSCENE),
		"can_pause_in_state(state) returns true for CUTSCENE"
	)
	_assert_true(
		not StateManager.can_pause_in_state(GameStates.State.MAIN_MENU),
		"can_pause_in_state(state) returns false for MAIN_MENU"
	)


func _prepare_clean_state() -> void:
	StateManager.reset_to_boot()
	StateManager.unlock_state()
	if StateManager.is_paused:
		StateManager.set_paused(false)
	_reset_event_buffers()


func _reset_event_buffers() -> void:
	state_changed_events.clear()
	pause_changed_events.clear()
	rejected_events.clear()


func _on_state_changed(previous_state: int, new_state: int) -> void:
	state_changed_events.append({
		"from": previous_state,
		"to": new_state
	})


func _on_pause_changed(value: bool) -> void:
	pause_changed_events.append(value)


func _on_state_change_rejected(from_state: int, to_state: int, reason: String) -> void:
	rejected_events.append({
		"from": from_state,
		"to": to_state,
		"reason": reason
	})


func _assert_true(condition: bool, message: String) -> void:
	if condition:
		passed_count += 1
		print("  [PASS] %s" % message)
	else:
		failed_count += 1
		push_error("  [FAIL] %s" % message)
