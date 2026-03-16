extends Node

# Emitted when the global state changes successfully.
signal state_changed(previous_state: int, new_state: int)

# Emitted when pause is toggled on or off.
signal pause_changed(is_paused: bool)

# Emitted when a requested state change is refused.
signal state_change_rejected(from_state: int, to_state: int, reason: String)


# High-level application states.
# These should remain broad and reusable across projects.
enum GameState {
	BOOT,
	TITLE,
	MAIN_MENU,
	LOADING,
	IN_GAME,
	CUTSCENE,
	OPTIONS,
	CREDITS,
	QUITTING
}

# Lightweight grouping used by other systems that only care
# about the kind of state, not the exact one.
enum StateCategory {
	SYSTEM,
	UI,
	GAMEPLAY,
	CINEMATIC,
	LOADING
}


# Current global state and previous one.
# previous_state is kept to support simple return flows and debugging.
var current_state: int = GameState.BOOT
var previous_state: int = GameState.BOOT

# Pause is handled separately from the main state.
# This keeps the current context explicit, for example IN_GAME + paused.
var is_paused: bool = false

# Temporary safeguard used to block transitions during sensitive operations.
var _state_locked: bool = false


# Maps each state to a broader category.
# This avoids scattering hardcoded state checks across the project.
const STATE_CATEGORIES := {
	GameState.BOOT: StateCategory.SYSTEM,
	GameState.TITLE: StateCategory.UI,
	GameState.MAIN_MENU: StateCategory.UI,
	GameState.LOADING: StateCategory.LOADING,
	GameState.IN_GAME: StateCategory.GAMEPLAY,
	GameState.CUTSCENE: StateCategory.CINEMATIC,
	GameState.OPTIONS: StateCategory.UI,
	GameState.CREDITS: StateCategory.UI,
	GameState.QUITTING: StateCategory.SYSTEM,
}

# Only these states are allowed to enter pause.
# This can easily evolve later if the project needs different pause rules.
const PAUSABLE_STATES := [
	GameState.IN_GAME,
	GameState.CUTSCENE,
]

# Explicit transition rules keep the flow predictable and easy to debug.
# A transition must be intentionally allowed here to be valid.
const ALLOWED_TRANSITIONS := {
	GameState.BOOT: [
		GameState.TITLE,
		GameState.MAIN_MENU,
		GameState.LOADING,
	],
	GameState.TITLE: [
		GameState.MAIN_MENU,
		GameState.LOADING,
		GameState.CREDITS,
		GameState.QUITTING,
	],
	GameState.MAIN_MENU: [
		GameState.LOADING,
		GameState.OPTIONS,
		GameState.CREDITS,
		GameState.QUITTING,
	],
	GameState.LOADING: [
		GameState.IN_GAME,
		GameState.MAIN_MENU,
		GameState.TITLE,
	],
	GameState.IN_GAME: [
		GameState.LOADING,
		GameState.MAIN_MENU,
		GameState.CUTSCENE,
		GameState.OPTIONS,
		GameState.QUITTING,
	],
	GameState.CUTSCENE: [
		GameState.IN_GAME,
		GameState.LOADING,
		GameState.MAIN_MENU,
		GameState.OPTIONS,
	],
	GameState.OPTIONS: [
		GameState.MAIN_MENU,
		GameState.IN_GAME,
		GameState.TITLE,
	],
	GameState.CREDITS: [
		GameState.TITLE,
		GameState.MAIN_MENU,
		GameState.QUITTING,
	],
	GameState.QUITTING: [],
}


func _ready() -> void:
	# Intentionally passive.
	# This manager stores and validates state,
	# but does not trigger scene, audio, or save behavior directly.
	pass


func set_state(new_state: int) -> bool:
	if _state_locked:
		_reject_transition(current_state, new_state, "State manager is locked.")
		return false

	if not _is_valid_state(new_state):
		_reject_transition(current_state, new_state, "Target state is invalid.")
		return false

	# Reaching the same state is treated as a no-op, not an error.
	if new_state == current_state:
		return true

	if not can_transition_to(new_state):
		_reject_transition(current_state, new_state, "Transition is not allowed.")
		return false

	var old_state := current_state
	previous_state = old_state
	current_state = new_state

	# Pause cannot survive into states that do not support it.
	if is_paused and not can_pause_in_state(current_state):
		is_paused = false
		pause_changed.emit(false)

	state_changed.emit(old_state, new_state)
	return true


func get_state() -> int:
	return current_state


func get_previous_state() -> int:
	return previous_state


func is_in_state(state: int) -> bool:
	return current_state == state


func get_state_category(state: int = -1) -> int:
	var target_state := current_state if state == -1 else state
	return STATE_CATEGORIES.get(target_state, StateCategory.SYSTEM)


func is_gameplay_state(state: int = -1) -> bool:
	return get_state_category(state) == StateCategory.GAMEPLAY


func is_ui_state(state: int = -1) -> bool:
	return get_state_category(state) == StateCategory.UI


func is_loading_state(state: int = -1) -> bool:
	return get_state_category(state) == StateCategory.LOADING


func is_cinematic_state(state: int = -1) -> bool:
	return get_state_category(state) == StateCategory.CINEMATIC


func can_transition_to(new_state: int) -> bool:
	# Defensive check in case the current state is corrupted or incomplete.
	if not _is_valid_state(current_state):
		return false

	var allowed: Array = ALLOWED_TRANSITIONS.get(current_state, [])
	return new_state in allowed


func can_pause_in_state(state: int = -1) -> bool:
	var target_state := current_state if state == -1 else state
	return target_state in PAUSABLE_STATES


func set_paused(value: bool) -> bool:
	# No-op if nothing changes.
	if value == is_paused:
		return true

	# Refuse pause if the current state is not meant to support it.
	if value and not can_pause_in_state():
		return false

	is_paused = value
	pause_changed.emit(is_paused)
	return true


func toggle_pause() -> bool:
	return set_paused(not is_paused)


func lock_state() -> void:
	_state_locked = true


func unlock_state() -> void:
	_state_locked = false


func is_locked() -> bool:
	return _state_locked


func reset_to_boot() -> void:
	# Preserve the current state so the emitted transition remains informative.
	var old_state := current_state

	# A full reset should also clear temporary protections such as state locking.
	_state_locked = false
	previous_state = old_state
	current_state = GameState.BOOT

	# Pause does not make sense in BOOT, so it is cleared explicitly.
	if is_paused:
		is_paused = false
		pause_changed.emit(false)

	# Emit the reset as a regular state transition so listeners can react consistently.
	state_changed.emit(old_state, current_state)


func get_state_name(state: int = -1) -> String:
	var target_state := current_state if state == -1 else state

	match target_state:
		GameState.BOOT:
			return "BOOT"
		GameState.TITLE:
			return "TITLE"
		GameState.MAIN_MENU:
			return "MAIN_MENU"
		GameState.LOADING:
			return "LOADING"
		GameState.IN_GAME:
			return "IN_GAME"
		GameState.CUTSCENE:
			return "CUTSCENE"
		GameState.OPTIONS:
			return "OPTIONS"
		GameState.CREDITS:
			return "CREDITS"
		GameState.QUITTING:
			return "QUITTING"
		_:
			return "UNKNOWN"


func _is_valid_state(state: int) -> bool:
	return state in STATE_CATEGORIES


func _reject_transition(from_state: int, to_state: int, reason: String) -> void:
	state_change_rejected.emit(from_state, to_state, reason)
