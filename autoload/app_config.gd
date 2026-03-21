extends RefCounted
class_name AppConfig

# Shared identifiers genuinely useful across the jam template.

const DEFAULT_LEVEL_ID: StringName = &"test_level"


# Shared group names.

const GROUP_PLAYER: StringName = &"player"
const GROUP_ENEMY: StringName = &"enemy"
const GROUP_INTERACTABLE: StringName = &"interactable"
const GROUP_DAMAGEABLE: StringName = &"damageable"
const GROUP_PAUSABLE: StringName = &"pausable"


# Shared audio bus names.

const BUS_MASTER: StringName = &"Master"
const BUS_MUSIC: StringName = &"Music"
const BUS_SFX: StringName = &"SFX"
const BUS_UI: StringName = &"UI"
const BUS_AMBIENCE: StringName = &"Ambience"


# Shared display modes for the template.
# Borderless is intentionally omitted to keep the jam template lean.

enum WindowMode {
	WINDOWED,
	FULLSCREEN,
}

const DEFAULT_WINDOW_MODE := WindowMode.WINDOWED


# Simple global helpers.
# These helpers stay stateless and intentionally tiny.

static func set_window_mode(mode: int) -> void:
	match mode:
		WindowMode.WINDOWED:
			# Fullscreen forces the borderless flag on some platforms.
			# Reset it explicitly when leaving fullscreen.
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

		WindowMode.FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

		_:
			push_warning("AppConfig.set_window_mode: unknown mode %s" % mode)


static func get_window_mode() -> int:
	var mode := DisplayServer.window_get_mode()

	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		return WindowMode.FULLSCREEN

	return WindowMode.WINDOWED


static func is_fullscreen() -> bool:
	return get_window_mode() == WindowMode.FULLSCREEN


static func toggle_fullscreen() -> void:
	if is_fullscreen():
		set_window_mode(WindowMode.WINDOWED)
	else:
		set_window_mode(WindowMode.FULLSCREEN)


static func can_request_fullscreen() -> bool:
	# On Web, fullscreen must be requested from an actual input callback
	# such as a button press or _input/_unhandled_input.
	# This helper only tells you whether fullscreen exists as a feature path.
	return true


static func quit_game(exit_code: int = 0) -> void:
	var main_loop := Engine.get_main_loop()
	if main_loop is SceneTree:
		(main_loop as SceneTree).quit(exit_code)
	else:
		push_warning("AppConfig.quit_game: SceneTree not available")


static func is_web() -> bool:
	return OS.has_feature("web")


static func level_scene_path(level_id: StringName) -> String:
	return "res://levels/%s.tscn" % String(level_id)
