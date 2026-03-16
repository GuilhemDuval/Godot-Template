extends RefCounted
class_name GameStates

enum State {
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

enum Category {
	SYSTEM,
	UI,
	GAMEPLAY,
	CINEMATIC,
	LOADING
}

const STATE_CATEGORIES := {
	State.BOOT: Category.SYSTEM,
	State.TITLE: Category.UI,
	State.MAIN_MENU: Category.UI,
	State.LOADING: Category.LOADING,
	State.IN_GAME: Category.GAMEPLAY,
	State.CUTSCENE: Category.CINEMATIC,
	State.OPTIONS: Category.UI,
	State.CREDITS: Category.UI,
	State.QUITTING: Category.SYSTEM,
}

const PAUSABLE_STATES := [
	State.IN_GAME,
	State.CUTSCENE,
]

const ALLOWED_TRANSITIONS := {
	State.BOOT: [
		State.TITLE,
		State.MAIN_MENU,
		State.LOADING,
	],
	State.TITLE: [
		State.MAIN_MENU,
		State.LOADING,
		State.CREDITS,
		State.QUITTING,
	],
	State.MAIN_MENU: [
		State.LOADING,
		State.OPTIONS,
		State.CREDITS,
		State.QUITTING,
	],
	State.LOADING: [
		State.IN_GAME,
		State.MAIN_MENU,
		State.TITLE,
		State.CUTSCENE,
	],
	State.IN_GAME: [
		State.LOADING,
		State.MAIN_MENU,
		State.CUTSCENE,
		State.OPTIONS,
		State.QUITTING,
	],
	State.CUTSCENE: [
		State.IN_GAME,
		State.LOADING,
		State.MAIN_MENU,
		State.OPTIONS,
		State.CREDITS,
	],
	State.OPTIONS: [
		State.MAIN_MENU,
		State.IN_GAME,
		State.TITLE,
		State.CUTSCENE,
	],
	State.CREDITS: [
		State.TITLE,
		State.MAIN_MENU,
		State.QUITTING,
	],
	State.QUITTING: [],
}

const STATE_NAMES := {
	State.BOOT: "BOOT",
	State.TITLE: "TITLE",
	State.MAIN_MENU: "MAIN_MENU",
	State.LOADING: "LOADING",
	State.IN_GAME: "IN_GAME",
	State.CUTSCENE: "CUTSCENE",
	State.OPTIONS: "OPTIONS",
	State.CREDITS: "CREDITS",
	State.QUITTING: "QUITTING",
}


static func is_valid_state(state: int) -> bool:
	return state in STATE_CATEGORIES


static func get_category(state: int) -> int:
	return STATE_CATEGORIES.get(state, Category.SYSTEM)


static func is_pausable(state: int) -> bool:
	return state in PAUSABLE_STATES


static func can_transition(from_state: int, to_state: int) -> bool:
	if not is_valid_state(from_state):
		return false

	var allowed: Array = ALLOWED_TRANSITIONS.get(from_state, [])
	return to_state in allowed


static func get_state_name(state: int) -> String:
	return STATE_NAMES.get(state, "UNKNOWN")
