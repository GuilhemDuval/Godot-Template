extends RefCounted
class_name InputRegistry

# Shared registry describing the project's known input actions.
#
# Role:
# - provide one source of truth for action names used by InputRouter and smoke tests
# - expose UI/debug metadata such as labels and display order
# - provide fallback keys for tests when InputMap is incomplete in a fresh environment
#
# Important:
# - InputMap remains the source of truth for the real project bindings
# - fallback_keys are only there to keep smoke tests usable and to reveal missing bindings
# - InputRouter remains the authority for category ids and permission logic

const CATEGORY_ORDER_NAMES := [
	&"GAMEPLAY_MOVE",
	&"GAMEPLAY_ACTION",
	&"UI_NAVIGATION",
	&"UI_CONFIRM",
	&"UI_CANCEL",
	&"PAUSE_TOGGLE",
	&"DIALOGUE_ADVANCE",
	&"DIALOGUE_CHOICE",
	&"DEBUG",
	&"SYSTEM",
]

const ACTION_SPECS := [
	{
		"name": &"move_left",
		"label": "Move left",
		"category_name": &"GAMEPLAY_MOVE",
		"show_in_smoke_test": true,
		"fallback_keys": [KEY_A, KEY_LEFT],
	},
	{
		"name": &"move_right",
		"label": "Move right",
		"category_name": &"GAMEPLAY_MOVE",
		"show_in_smoke_test": true,
		"fallback_keys": [KEY_D, KEY_RIGHT],
	},
	{
		"name": &"move_up",
		"label": "Move up",
		"category_name": &"GAMEPLAY_MOVE",
		"show_in_smoke_test": true,
		"fallback_keys": [KEY_W, KEY_UP],
	},
	{
		"name": &"move_down",
		"label": "Move down",
		"category_name": &"GAMEPLAY_MOVE",
		"show_in_smoke_test": true,
		"fallback_keys": [KEY_S, KEY_DOWN],
	},
	{
		"name": &"interact",
		"label": "Interact",
		"category_name": &"GAMEPLAY_ACTION",
		"show_in_smoke_test": true,
		"fallback_keys": [KEY_E, KEY_SPACE],
	},
	{
		"name": &"attack",
		"label": "Attack",
		"category_name": &"GAMEPLAY_ACTION",
		"show_in_smoke_test": true,
		"fallback_keys": [KEY_F],
	},
	{
		"name": &"submit",
		"label": "Submit",
		"category_name": &"UI_CONFIRM",
		"show_in_smoke_test": false,
		"fallback_keys": [KEY_ENTER],
	},
	{
		"name": &"ui_accept",
		"label": "UI accept",
		"category_name": &"UI_CONFIRM",
		"show_in_smoke_test": true,
		"fallback_keys": [KEY_ENTER],
	},
	{
		"name": &"ui_cancel",
		"label": "UI cancel",
		"category_name": &"UI_CANCEL",
		"show_in_smoke_test": true,
		"fallback_keys": [KEY_ESCAPE],
	},
	{
		"name": &"ui_up",
		"label": "UI up",
		"category_name": &"UI_NAVIGATION",
		"show_in_smoke_test": true,
		"fallback_keys": [KEY_UP],
	},
	{
		"name": &"ui_down",
		"label": "UI down",
		"category_name": &"UI_NAVIGATION",
		"show_in_smoke_test": true,
		"fallback_keys": [KEY_DOWN],
	},
	{
		"name": &"ui_left",
		"label": "UI left",
		"category_name": &"UI_NAVIGATION",
		"show_in_smoke_test": true,
		"fallback_keys": [KEY_LEFT],
	},
	{
		"name": &"ui_right",
		"label": "UI right",
		"category_name": &"UI_NAVIGATION",
		"show_in_smoke_test": true,
		"fallback_keys": [KEY_RIGHT],
	},
	{
		"name": &"pause",
		"label": "Pause",
		"category_name": &"PAUSE_TOGGLE",
		"show_in_smoke_test": true,
		"fallback_keys": [KEY_P],
	},
	{
		"name": &"dialogue_advance",
		"label": "Dialogue advance",
		"category_name": &"DIALOGUE_ADVANCE",
		"show_in_smoke_test": true,
		"fallback_keys": [KEY_SPACE],
	},
	{
		"name": &"dialogue_choice_up",
		"label": "Dialogue choice up",
		"category_name": &"DIALOGUE_CHOICE",
		"show_in_smoke_test": true,
		"fallback_keys": [KEY_PAGEUP],
	},
	{
		"name": &"dialogue_choice_down",
		"label": "Dialogue choice down",
		"category_name": &"DIALOGUE_CHOICE",
		"show_in_smoke_test": true,
		"fallback_keys": [KEY_PAGEDOWN],
	},
	{
		"name": &"debug_toggle",
		"label": "Debug toggle",
		"category_name": &"DEBUG",
		"show_in_smoke_test": true,
		"fallback_keys": [KEY_F3],
	},
]

static func get_action_specs() -> Array:
	var results: Array = []
	for spec in ACTION_SPECS:
		results.append(_resolve_action_spec(spec))
	return results


static func get_smoke_test_action_specs() -> Array:
	var results: Array = []
	for spec in ACTION_SPECS:
		if spec.get("show_in_smoke_test", true):
			results.append(_resolve_action_spec(spec))
	return results


static func get_action_spec(action_name: StringName) -> Dictionary:
	for spec in ACTION_SPECS:
		if spec["name"] == action_name:
			return _resolve_action_spec(spec)
	return {}


static func get_action_category_map() -> Dictionary:
	var mapping: Dictionary = {}
	for spec in ACTION_SPECS:
		mapping[spec["name"]] = InputRouter.category_name_to_value(spec["category_name"])
	return mapping


static func get_category_order() -> Array:
	var results: Array = []
	for category_name in CATEGORY_ORDER_NAMES:
		results.append(InputRouter.category_name_to_value(category_name))
	return results


static func get_category_name(category: int) -> String:
	return InputRouter.get_category_name(category)


static func get_flag_specs_for_smoke_test() -> Array:
	return [
		{"name": InputRouter.FLAG_MENU_OPEN, "label": "Menu open", "show_in_smoke_test": true},
		{"name": InputRouter.FLAG_PAUSE_OPEN, "label": "Pause open", "show_in_smoke_test": true},
		{"name": InputRouter.FLAG_DIALOGUE_ACTIVE, "label": "Dialogue active", "show_in_smoke_test": true},
		{"name": InputRouter.FLAG_CINEMATIC_ACTIVE, "label": "Cinematic active", "show_in_smoke_test": true},
		{"name": InputRouter.FLAG_TRANSITION_ACTIVE, "label": "Transition active", "show_in_smoke_test": true},
		{"name": InputRouter.FLAG_INPUT_GLOBALLY_BLOCKED, "label": "Global block", "show_in_smoke_test": true},
	]


static func _resolve_action_spec(spec: Dictionary) -> Dictionary:
	var resolved := spec.duplicate(true)
	resolved["category"] = InputRouter.category_name_to_value(resolved["category_name"])
	return resolved
