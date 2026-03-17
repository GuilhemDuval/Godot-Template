extends Node

signal session_started(is_new_game: bool)
signal session_ended()
signal session_reset()
signal session_loaded(slot_id: int)
signal session_unloaded()

signal level_changed(previous_level_id: String, new_level_id: String)
signal checkpoint_changed(previous_checkpoint_id: String, new_checkpoint_id: String)
signal cinematic_changed(previous_cinematic_id: String, new_cinematic_id: String)

# Whether a playable session currently exists in memory.
var has_active_session: bool = false

# True when the current session was created as a fresh run.
# This can be useful for onboarding, intro cinematics, or first-load logic.
var is_new_game: bool = false

# Save slot currently associated with the session.
# -1 means the session is not currently bound to a save slot.
var current_slot_id: int = -1

# Current logical destination of the session.
# These IDs are runtime identifiers, not scene paths.
var current_level_id: String = ""
var checkpoint_id: String = ""
var current_cinematic_id: String = ""

# Generic runtime data containers.
# session_flags is good for simple booleans and lightweight markers.
# session_data can hold broader runtime values if needed.
var session_flags: Dictionary = {}
var session_data: Dictionary = {}

# Lightweight session timer, updated manually if needed later.
var elapsed_run_time: float = 0.0


func _ready() -> void:
	# Intentionally passive.
	# SessionManager stores the current run state,
	# but does not load scenes or save files by itself.
	pass


func start_new_session(start_level_id: String = "", slot_id: int = -1) -> void:
	var resolved_level_id := start_level_id
	if resolved_level_id == "":
		resolved_level_id = AppConfig.DEFAULT_LEVEL_ID

	has_active_session = true
	is_new_game = true
	current_slot_id = slot_id

	current_level_id = resolved_level_id
	checkpoint_id = ""
	current_cinematic_id = ""

	session_flags.clear()
	session_data.clear()
	elapsed_run_time = 0.0

	session_started.emit(true)


func load_session_data(data: Dictionary, slot_id: int = -1) -> void:
	has_active_session = true
	is_new_game = false
	current_slot_id = slot_id

	current_level_id = str(data.get("current_level_id", AppConfig.DEFAULT_LEVEL_ID))
	checkpoint_id = str(data.get("checkpoint_id", ""))
	current_cinematic_id = str(data.get("current_cinematic_id", ""))

	session_flags = data.get("session_flags", {}).duplicate(true)
	session_data = data.get("session_data", {}).duplicate(true)
	elapsed_run_time = float(data.get("elapsed_run_time", 0.0))

	session_loaded.emit(slot_id)


func end_session() -> void:
	if not has_active_session:
		return

	has_active_session = false
	is_new_game = false
	current_slot_id = -1

	current_level_id = ""
	checkpoint_id = ""
	current_cinematic_id = ""

	session_flags.clear()
	session_data.clear()
	elapsed_run_time = 0.0

	session_ended.emit()
	session_unloaded.emit()


func reset_session() -> void:
	var had_session := has_active_session
	var preserved_slot_id := current_slot_id

	has_active_session = false
	is_new_game = false
	current_slot_id = preserved_slot_id

	current_level_id = ""
	checkpoint_id = ""
	current_cinematic_id = ""

	session_flags.clear()
	session_data.clear()
	elapsed_run_time = 0.0

	session_reset.emit()

	if had_session:
		session_unloaded.emit()


func has_session() -> bool:
	return has_active_session


func set_current_level(level_id: String) -> void:
	if level_id == current_level_id:
		return

	var previous_level_id := current_level_id
	current_level_id = level_id
	level_changed.emit(previous_level_id, current_level_id)


func get_current_level() -> String:
	return current_level_id


func set_checkpoint(new_checkpoint_id: String) -> void:
	if new_checkpoint_id == checkpoint_id:
		return

	var previous_checkpoint_id := checkpoint_id
	checkpoint_id = new_checkpoint_id
	checkpoint_changed.emit(previous_checkpoint_id, checkpoint_id)


func get_checkpoint() -> String:
	return checkpoint_id


func set_current_cinematic(cinematic_id: String) -> void:
	if cinematic_id == current_cinematic_id:
		return

	var previous_cinematic_id := current_cinematic_id
	current_cinematic_id = cinematic_id
	cinematic_changed.emit(previous_cinematic_id, current_cinematic_id)


func get_current_cinematic() -> String:
	return current_cinematic_id


func set_flag(key: String, value: Variant) -> void:
	session_flags[key] = value


func get_flag(key: String, default_value: Variant = null) -> Variant:
	return session_flags.get(key, default_value)


func clear_flag(key: String) -> void:
	if session_flags.has(key):
		session_flags.erase(key)


func set_data(key: String, value: Variant) -> void:
	session_data[key] = value


func get_data(key: String, default_value: Variant = null) -> Variant:
	return session_data.get(key, default_value)


func clear_data(key: String) -> void:
	if session_data.has(key):
		session_data.erase(key)


func export_save_data() -> Dictionary:
	return {
		"current_level_id": current_level_id,
		"checkpoint_id": checkpoint_id,
		"current_cinematic_id": current_cinematic_id,
		"session_flags": session_flags.duplicate(true),
		"session_data": session_data.duplicate(true),
		"elapsed_run_time": elapsed_run_time,
	}
