extends RefCounted
class_name StateSceneRegistry

# Central registry that maps broad application states to their root scene.
#
# Role:
# - keep scene-path knowledge out of SceneManager
# - keep GameStates focused on state definitions and transitions
# - provide a single place to adjust app-level routing
#
# Scope:
# - only broad root scenes should be registered here
# - do not put save-slot, checkpoint, chapter, or level-selection logic here
# - detailed content routing belongs to SessionManager and dedicated content registries

const STATE_TO_SCENE_PATH := {
	GameStates.State.TITLE: "res://scenes/menus/title_screen.tscn",
	GameStates.State.MAIN_MENU: "res://scenes/menus/main_menu.tscn",
	GameStates.State.LOADING: "res://scenes/common/loading_screen.tscn",
	GameStates.State.IN_GAME: "res://scenes/gameplay/game_root.tscn",
	GameStates.State.OPTIONS: "res://scenes/menus/options_menu.tscn",
	GameStates.State.CREDITS: "res://scenes/menus/credits.tscn"
}

static func get_scene_path_for_state(state: int) -> String:
	return STATE_TO_SCENE_PATH.get(state, "")

static func has_scene_for_state(state: int) -> bool:
	return STATE_TO_SCENE_PATH.has(state)

static func get_all_mappings() -> Dictionary:
	return STATE_TO_SCENE_PATH.duplicate()
