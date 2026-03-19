extends Node
class_name InputRouter

signal context_flag_changed(flag_name: StringName, value: bool)
signal permissions_changed()
signal router_reset()
signal category_override_changed(category: int, is_overridden: bool, allowed: bool)

enum Category {
	NONE = 0,
	GAMEPLAY_MOVE = 1,
	GAMEPLAY_ACTION = 2,
	UI_NAVIGATION = 3,
	UI_CONFIRM = 4,
	UI_CANCEL = 5,
	PAUSE_TOGGLE = 6,
	DIALOGUE_ADVANCE = 7,
	DIALOGUE_CHOICE = 8,
	DEBUG = 9,
	SYSTEM = 10,
}

const FLAG_MENU_OPEN: StringName = &"menu_open"
const FLAG_PAUSE_OPEN: StringName = &"pause_open"
const FLAG_DIALOGUE_ACTIVE: StringName = &"dialogue_active"
const FLAG_CINEMATIC_ACTIVE: StringName = &"cinematic_active"
const FLAG_TRANSITION_ACTIVE: StringName = &"transition_active"
const FLAG_INPUT_GLOBALLY_BLOCKED: StringName = &"input_globally_blocked"

var _flags: Dictionary = {}
var _category_overrides: Dictionary = {}
var _action_category_map: Dictionary = {}

func _ready() -> void:
	_rebuild_action_category_map_from_registry()
	reset()


func reset() -> void:
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


func reload_action_registry() -> void:
	_rebuild_action_category_map_from_registry()
	permissions_changed.emit()


func set_flag(flag_name: StringName, value: bool) -> void:
	var previous: bool = _flags.get(flag_name, false)
	if previous == value:
		return

	_flags[flag_name] = value
	context_flag_changed.emit(flag_name, value)
	permissions_changed.emit()


func get_flag(flag_name: StringName) -> bool:
	return _flags.get(flag_name, false)


func clear_flag(flag_name: StringName) -> void:
	set_flag(flag_name, false)


func clear_all_flags() -> void:
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


func get_category_override(category: int) -> bool:
	return bool(_category_overrides.get(category, false))


func is_action_allowed(action_name: StringName) -> bool:
	var category: int = _get_action_category(action_name)
	if category == Category.NONE:
		return true
	return is_category_allowed(category)


func is_category_allowed(category: int) -> bool:
	if _category_overrides.has(category):
		return bool(_category_overrides[category])

	if get_flag(FLAG_INPUT_GLOBALLY_BLOCKED):
		return category == Category.SYSTEM

	if get_flag(FLAG_TRANSITION_ACTIVE):
		return category in [Category.SYSTEM, Category.DEBUG]

	if get_flag(FLAG_CINEMATIC_ACTIVE):
		return category in [Category.SYSTEM, Category.DEBUG, Category.PAUSE_TOGGLE]

	if get_flag(FLAG_DIALOGUE_ACTIVE):
		return category in [
			Category.SYSTEM,
			Category.DEBUG,
			Category.DIALOGUE_ADVANCE,
			Category.DIALOGUE_CHOICE,
			Category.PAUSE_TOGGLE,
		]

	if get_flag(FLAG_PAUSE_OPEN):
		return category in [
			Category.SYSTEM,
			Category.DEBUG,
			Category.UI_NAVIGATION,
			Category.UI_CONFIRM,
			Category.UI_CANCEL,
			Category.PAUSE_TOGGLE,
		]

	if get_flag(FLAG_MENU_OPEN):
		return category in [
			Category.SYSTEM,
			Category.DEBUG,
			Category.UI_NAVIGATION,
			Category.UI_CONFIRM,
			Category.UI_CANCEL,
		]

	return true


func is_gameplay_input_allowed() -> bool:
	return is_category_allowed(Category.GAMEPLAY_MOVE) and is_category_allowed(Category.GAMEPLAY_ACTION)


func is_ui_input_allowed() -> bool:
	return (
		is_category_allowed(Category.UI_NAVIGATION)
		and is_category_allowed(Category.UI_CONFIRM)
		and is_category_allowed(Category.UI_CANCEL)
	)


func is_pause_toggle_allowed() -> bool:
	return is_category_allowed(Category.PAUSE_TOGGLE)


func is_dialogue_input_allowed() -> bool:
	return is_category_allowed(Category.DIALOGUE_ADVANCE) or is_category_allowed(Category.DIALOGUE_CHOICE)


static func get_category_name(category: int) -> String:
	match category:
		Category.NONE:
			return "NONE"
		Category.GAMEPLAY_MOVE:
			return "GAMEPLAY_MOVE"
		Category.GAMEPLAY_ACTION:
			return "GAMEPLAY_ACTION"
		Category.UI_NAVIGATION:
			return "UI_NAVIGATION"
		Category.UI_CONFIRM:
			return "UI_CONFIRM"
		Category.UI_CANCEL:
			return "UI_CANCEL"
		Category.PAUSE_TOGGLE:
			return "PAUSE_TOGGLE"
		Category.DIALOGUE_ADVANCE:
			return "DIALOGUE_ADVANCE"
		Category.DIALOGUE_CHOICE:
			return "DIALOGUE_CHOICE"
		Category.DEBUG:
			return "DEBUG"
		Category.SYSTEM:
			return "SYSTEM"
		_:
			return "UNKNOWN(%s)" % str(category)


static func category_name_to_value(category_name: StringName) -> int:
	match String(category_name):
		"NONE":
			return Category.NONE
		"GAMEPLAY_MOVE":
			return Category.GAMEPLAY_MOVE
		"GAMEPLAY_ACTION":
			return Category.GAMEPLAY_ACTION
		"UI_NAVIGATION":
			return Category.UI_NAVIGATION
		"UI_CONFIRM":
			return Category.UI_CONFIRM
		"UI_CANCEL":
			return Category.UI_CANCEL
		"PAUSE_TOGGLE":
			return Category.PAUSE_TOGGLE
		"DIALOGUE_ADVANCE":
			return Category.DIALOGUE_ADVANCE
		"DIALOGUE_CHOICE":
			return Category.DIALOGUE_CHOICE
		"DEBUG":
			return Category.DEBUG
		"SYSTEM":
			return Category.SYSTEM
		_:
			return Category.NONE


func _rebuild_action_category_map_from_registry() -> void:
	_action_category_map = InputRegistry.get_action_category_map()


func _get_action_category(action_name: StringName) -> int:
	return int(_action_category_map.get(action_name, Category.NONE))
