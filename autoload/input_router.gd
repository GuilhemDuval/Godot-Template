extends Node
class_name InputRouter

# Emitted whenever a context flag changes.
# Example: pause_open becomes true, dialogue_active becomes false, etc.
signal context_flag_changed(flag_name: StringName, value: bool)

# Emitted whenever the global permission rules may have changed.
# Useful for UI, debugging, or systems that want to refresh their state.
signal permissions_changed()

# Emitted when the router is reset to its default state.
signal router_reset()

# Emitted when a category gets an explicit test/debug override.
# is_overridden tells whether the override exists.
# allowed is the forced result when the override exists.
signal category_override_changed(category: int, is_overridden: bool, allowed: bool)


# High-level input families used by the router.
# The goal is not to list every action in the game, but to group actions
# into a few meaningful categories that can be allowed or blocked together.
enum Category {
	NONE,
	GAMEPLAY_MOVE,
	GAMEPLAY_ACTION,
	UI_NAVIGATION,
	UI_CONFIRM,
	UI_CANCEL,
	PAUSE_TOGGLE,
	DIALOGUE_ADVANCE,
	DIALOGUE_CHOICE,
	DEBUG,
	SYSTEM,
}


# Context flags used to describe what is currently happening in the game.
# These are not key bindings and not game states by themselves.
# They are simple conditions that influence which input categories are allowed.
const FLAG_MENU_OPEN: StringName = &"menu_open"
const FLAG_PAUSE_OPEN: StringName = &"pause_open"
const FLAG_DIALOGUE_ACTIVE: StringName = &"dialogue_active"
const FLAG_CINEMATIC_ACTIVE: StringName = &"cinematic_active"
const FLAG_TRANSITION_ACTIVE: StringName = &"transition_active"
const FLAG_INPUT_GLOBALLY_BLOCKED: StringName = &"input_globally_blocked"


# Stores the current value of each context flag.
# Example:
# - pause_open = true
# - dialogue_active = false
var _flags: Dictionary = {}

# Optional hard overrides for one category.
# Intended mainly for smoke tests, debug tools, or temporary forcing.
# If a category is present here, its stored boolean wins over the normal rules.
var _category_overrides: Dictionary = {}

# Maps InputMap action names to one high-level input category.
# Godot's InputMap still handles actual bindings.
# InputRouter only decides whether a given action category is currently allowed.
var _action_category_map: Dictionary = {
	&"move_left": Category.GAMEPLAY_MOVE,
	&"move_right": Category.GAMEPLAY_MOVE,
	&"move_up": Category.GAMEPLAY_MOVE,
	&"move_down": Category.GAMEPLAY_MOVE,

	&"interact": Category.GAMEPLAY_ACTION,
	&"attack": Category.GAMEPLAY_ACTION,

	&"submit": Category.UI_CONFIRM,
	&"ui_accept": Category.UI_CONFIRM,
	&"ui_cancel": Category.UI_CANCEL,
	&"ui_up": Category.UI_NAVIGATION,
	&"ui_down": Category.UI_NAVIGATION,
	&"ui_left": Category.UI_NAVIGATION,
	&"ui_right": Category.UI_NAVIGATION,

	&"pause": Category.PAUSE_TOGGLE,

	&"dialogue_advance": Category.DIALOGUE_ADVANCE,
	&"dialogue_choice_up": Category.DIALOGUE_CHOICE,
	&"dialogue_choice_down": Category.DIALOGUE_CHOICE,

	&"debug_toggle": Category.DEBUG,
}


func _ready() -> void:
	# Initialize the router with a clean default state.
	reset()


func reset() -> void:
	# Reset all known context flags to their default value.
	# This represents the "normal" situation where no special blocking
	# context is active yet.
	_flags = {
		FLAG_MENU_OPEN: false,
		FLAG_PAUSE_OPEN: false,
		FLAG_DIALOGUE_ACTIVE: false,
		FLAG_CINEMATIC_ACTIVE: false,
		FLAG_TRANSITION_ACTIVE: false,
		FLAG_INPUT_GLOBALLY_BLOCKED: false,
	}

	clear_all_category_overrides()
	router_reset.emit()
	permissions_changed.emit()


func set_flag(flag_name: StringName, value: bool) -> void:
	# Update one context flag only if its value actually changes.
	# This avoids useless signal emissions.
	var previous: bool = _flags.get(flag_name, false)
	if previous == value:
		return

	_flags[flag_name] = value
	context_flag_changed.emit(flag_name, value)
	permissions_changed.emit()


func get_flag(flag_name: StringName) -> bool:
	# Returns the current value of a context flag.
	# Unknown flags default to false.
	return _flags.get(flag_name, false)


func clear_flag(flag_name: StringName) -> void:
	# Convenience helper to explicitly disable one flag.
	set_flag(flag_name, false)


func clear_all_flags() -> void:
	# Turns off every active flag.
	# Useful when leaving a complex situation or resetting test state.
	var changed := false

	for flag_name in _flags.keys():
		if _flags[flag_name]:
			_flags[flag_name] = false
			context_flag_changed.emit(flag_name, false)
			changed = true

	if changed:
		permissions_changed.emit()


func set_category_override(category: int, allowed: bool) -> void:
	var had_override := _category_overrides.has(category)
	if had_override and _category_overrides[category] == allowed:
		return

	_category_overrides[category] = allowed
	category_override_changed.emit(category, true, allowed)
	permissions_changed.emit()


func clear_category_override(category: int) -> void:
	if not _category_overrides.has(category):
		return

	_category_overrides.erase(category)
	category_override_changed.emit(category, false, false)
	permissions_changed.emit()


func clear_all_category_overrides() -> void:
	if _category_overrides.is_empty():
		return

	var categories := _category_overrides.keys().duplicate()
	_category_overrides.clear()

	for category in categories:
		category_override_changed.emit(category, false, false)

	permissions_changed.emit()


func has_category_override(category: int) -> bool:
	return _category_overrides.has(category)


func get_category_override(category: int) -> Variant:
	if not _category_overrides.has(category):
		return null

	return _category_overrides[category]


func is_action_allowed(action_name: StringName) -> bool:
	# Resolve an action into a category, then check whether that category
	# is currently allowed by the active context flags.
	var category: int = _get_action_category(action_name)

	if category == Category.NONE:
		# Unknown actions are allowed by default to avoid surprising hard locks.
		# This makes the router more permissive and easier to integrate at first.
		# Later, you could choose a stricter policy if needed.
		return true

	return is_category_allowed(category)


func is_category_allowed(category: int) -> bool:
	# Hard category overrides win over the regular policy.
	if _category_overrides.has(category):
		return _category_overrides[category]

	# Central permission logic of the router.
	#
	# The order matters:
	# more restrictive contexts are checked first.
	# For example, a global block takes priority over pause or menu rules.

	if get_flag(FLAG_INPUT_GLOBALLY_BLOCKED):
		# Hard lock: only SYSTEM inputs survive.
		return category == Category.SYSTEM

	if get_flag(FLAG_TRANSITION_ACTIVE):
		# During scene transitions, most input is blocked to prevent
		# accidental actions, double validation, or movement during loading.
		return category in [
			Category.SYSTEM,
			Category.DEBUG,
		]

	if get_flag(FLAG_CINEMATIC_ACTIVE):
		# During a cinematic, gameplay is blocked.
		# Here we still allow pause and debug, but this policy is adjustable.
		return category in [
			Category.SYSTEM,
			Category.DEBUG,
			Category.PAUSE_TOGGLE,
		]

	if get_flag(FLAG_DIALOGUE_ACTIVE):
		# During dialogue, movement and gameplay actions are blocked,
		# but dialogue progression and choices remain available.
		return category in [
			Category.SYSTEM,
			Category.DEBUG,
			Category.DIALOGUE_ADVANCE,
			Category.DIALOGUE_CHOICE,
			Category.PAUSE_TOGGLE,
		]

	if get_flag(FLAG_PAUSE_OPEN):
		# While paused, gameplay is blocked, but menu-like UI navigation stays active.
		return category in [
			Category.SYSTEM,
			Category.DEBUG,
			Category.UI_NAVIGATION,
			Category.UI_CONFIRM,
			Category.UI_CANCEL,
			Category.PAUSE_TOGGLE,
		]

	if get_flag(FLAG_MENU_OPEN):
		# In menus, we usually want UI navigation and confirmation/cancel only.
		return category in [
			Category.SYSTEM,
			Category.DEBUG,
			Category.UI_NAVIGATION,
			Category.UI_CONFIRM,
			Category.UI_CANCEL,
		]

	# Default case: nothing special is blocking input.
	return true


func is_gameplay_input_allowed() -> bool:
	# Convenience helper for gameplay scripts.
	# Returns true only if both movement and gameplay actions are allowed.
	return (
		is_category_allowed(Category.GAMEPLAY_MOVE)
		and is_category_allowed(Category.GAMEPLAY_ACTION)
	)


func is_ui_input_allowed() -> bool:
	# Convenience helper for menus and overlays.
	# Returns true only if the main UI interaction categories are allowed.
	return (
		is_category_allowed(Category.UI_NAVIGATION)
		and is_category_allowed(Category.UI_CONFIRM)
		and is_category_allowed(Category.UI_CANCEL)
	)


func is_pause_toggle_allowed() -> bool:
	# Convenience helper for pause handling.
	return is_category_allowed(Category.PAUSE_TOGGLE)


func is_dialogue_input_allowed() -> bool:
	# Convenience helper for dialogue systems.
	# Returns true if at least one dialogue-related input family is allowed.
	return (
		is_category_allowed(Category.DIALOGUE_ADVANCE)
		or is_category_allowed(Category.DIALOGUE_CHOICE)
	)	


func _get_action_category(action_name: StringName) -> int:
	# Returns the category associated with an action name.
	# If the action is unknown, Category.NONE is returned.
	return _action_category_map.get(action_name, Category.NONE)
