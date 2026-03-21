extends Node

signal music_changed(previous_id: StringName, new_id: StringName)
signal ambience_changed(previous_id: Array, new_id: Array)
signal ambience_layers_changed(active_ids: Array)
signal bus_volume_changed(bus_name: StringName, linear_value: float, db_value: float)
signal sound_missing(sound_id: StringName, path: String)

enum Category {
	MUSIC,
	SFX,
	UI,
	AMBIENCE,
}

const BUS_MASTER := AppConfig.BUS_MASTER
const BUS_MUSIC := AppConfig.BUS_MUSIC
const BUS_SFX := AppConfig.BUS_SFX
const BUS_UI := AppConfig.BUS_UI
const BUS_AMBIENCE := AppConfig.BUS_AMBIENCE

const SILENT_DB := -80.0
const DEFAULT_SFX_POOL_SIZE := 8
const DEFAULT_UI_POOL_SIZE := 4

var default_music_fade_in_sec: float = 0.6
var default_music_fade_out_sec: float = 0.6
var default_pause_music_fade_in_sec: float = 0.2
var default_pause_music_fade_out_sec: float = 0.2


class AudioCue extends RefCounted:
	# Lightweight data container for one registered sound.
	var id: StringName
	var path: String
	var category: int
	var bus: StringName
	var base_volume_db: float
	var pitch_scale: float
	var pitch_random: float
	var preload_on_ready: bool
	var stream: AudioStream = null

	func _init(
		p_id: StringName,
		p_path: String,
		p_category: int,
		p_bus: StringName,
		p_base_volume_db: float = 0.0,
		p_pitch_scale: float = 1.0,
		p_pitch_random: float = 0.0,
		p_preload_on_ready: bool = false
	) -> void:
		id = p_id
		path = p_path
		category = p_category
		bus = p_bus
		base_volume_db = p_base_volume_db
		pitch_scale = p_pitch_scale
		pitch_random = p_pitch_random
		preload_on_ready = p_preload_on_ready


# Sound registry.
# Key = sound id, value = AudioCue
var _cues: Dictionary = {}

# Two main music players are used for crossfades.
var _music_player_a: AudioStreamPlayer
var _music_player_b: AudioStreamPlayer
var _active_music_player: AudioStreamPlayer
var _inactive_music_player: AudioStreamPlayer

# Dedicated pause music player.
# It keeps pause music independent from normal game music.
var _pause_music_player: AudioStreamPlayer

# One player per active ambience layer.
# Key = ambience sound id, value = AudioStreamPlayer
var _ambience_players_by_id: Dictionary = {}

# Ordered list of currently active ambience ids.
var _active_ambience_ids: Array[StringName] = []

# Pools for one-shot sounds.
var _sfx_players: Array[AudioStreamPlayer] = []
var _ui_players: Array[AudioStreamPlayer] = []

# Tweens currently used by music systems.
var _music_tween: Tween = null
var _pause_music_tween: Tween = null

# Current regular music state.
var _current_music_id: StringName = &""
var _current_music_target_volume_db: float = 0.0

# Pause music state.
var _pause_overlay_active: bool = false
var _pause_music_id: StringName = &""

# Snapshot of the regular music paused for the pause menu.
var _should_resume_main_music_after_pause: bool = false
var _paused_main_music_player: AudioStreamPlayer = null
var _paused_main_music_id: StringName = &""
var _paused_main_music_target_volume_db: float = 0.0
var _paused_main_music_position_sec: float = 0.0

# Snapshot of ambience layers paused for the pause menu.
var _ambience_pause_snapshot_active: bool = false
var _paused_ambience_ids: Array[StringName] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()

	_create_core_players()
	_validate_buses()

	# Fill this method with the sounds of your project.
	_register_project_sounds()
	_warmup_flagged_sounds()


func _register_project_sounds() -> void:
	# Example:
	#
	# register_sound(&"ui_hover", "res://audio/ui/ui_hover.ogg", Category.UI, {
	# 	"base_volume_db": -12.0,
	# 	"preload": true,
	# })
	#
	# register_sound(&"ui_click", "res://audio/ui/ui_click.ogg", Category.UI, {
	# 	"base_volume_db": -8.0,
	# 	"preload": true,
	# })
	#
	# register_sound(&"title_theme", "res://audio/music/title_theme.ogg", Category.MUSIC, {
	# 	"base_volume_db": -4.0,
	# 	"preload": true,
	# })
	#
	# register_sound(&"pause_theme", "res://audio/music/pause_theme.ogg", Category.MUSIC, {
	# 	"base_volume_db": -8.0,
	# 	"preload": true,
	# })
	#
	# register_sound(&"forest_loop", "res://audio/ambience/forest_loop.ogg", Category.AMBIENCE, {
	# 	"base_volume_db": -10.0,
	# 	"preload": true,
	# })
	#
	# register_sound(&"wind_loop", "res://audio/ambience/wind_loop.ogg", Category.AMBIENCE, {
	# 	"base_volume_db": -14.0,
	# 	"preload": true,
	# })
	#
	# register_sound(&"player_jump", "res://audio/sfx/player_jump.ogg", Category.SFX, {
	# 	"base_volume_db": -6.0,
	# 	"pitch_random": 0.03,
	# 	"preload": true,
	# })
	pass


func register_sound(
	sound_id: StringName,
	path: String,
	category: int,
	options: Dictionary = {}
) -> void:
	var bus_name: StringName = _default_bus_for_category(category)
	if options.has("bus"):
		bus_name = StringName(str(options["bus"]))

	var cue := AudioCue.new(
		sound_id,
		path,
		category,
		bus_name,
		float(options.get("base_volume_db", 0.0)),
		float(options.get("pitch_scale", 1.0)),
		float(options.get("pitch_random", 0.0)),
		bool(options.get("preload", false))
	)

	_cues[sound_id] = cue

	if cue.preload_on_ready:
		_load_stream(cue)


func unregister_sound(sound_id: StringName) -> void:
	_cues.erase(sound_id)


func has_sound(sound_id: StringName) -> bool:
	return _cues.has(sound_id)


func warmup_sound(sound_id: StringName) -> void:
	var cue := _get_cue(sound_id)
	if cue == null:
		return
	_load_stream(cue)


func warmup_all() -> void:
	for cue_variant in _cues.values():
		var cue := cue_variant as AudioCue
		_load_stream(cue)


func set_default_music_fades(fade_in_sec: float, fade_out_sec: float) -> void:
	default_music_fade_in_sec = maxf(0.0, fade_in_sec)
	default_music_fade_out_sec = maxf(0.0, fade_out_sec)


func set_default_pause_music_fades(fade_in_sec: float, fade_out_sec: float) -> void:
	default_pause_music_fade_in_sec = maxf(0.0, fade_in_sec)
	default_pause_music_fade_out_sec = maxf(0.0, fade_out_sec)


func play_sound(
	sound_id: StringName,
	extra_volume_db: float = 0.0,
	pitch_multiplier: float = 1.0,
	restart: bool = false
) -> AudioStreamPlayer:
	var cue := _get_cue(sound_id)
	if cue == null:
		return null

	match cue.category:
		Category.MUSIC:
			return play_music(sound_id, restart, extra_volume_db)
		Category.AMBIENCE:
			return play_ambience(sound_id, restart, extra_volume_db)
		Category.SFX:
			return play_sfx(sound_id, extra_volume_db, pitch_multiplier)
		Category.UI:
			return play_ui(sound_id, extra_volume_db, pitch_multiplier)
		_:
			return null


func play_music(
	sound_id: StringName,
	restart: bool = false,
	extra_volume_db: float = 0.0,
	from_position: float = 0.0,
	fade_in_sec: float = -1.0,
	fade_out_sec: float = -1.0
) -> AudioStreamPlayer:
	var cue := _get_cue(sound_id, Category.MUSIC)
	if cue == null:
		return null

	if fade_in_sec < 0.0:
		fade_in_sec = default_music_fade_in_sec
	if fade_out_sec < 0.0:
		fade_out_sec = default_music_fade_out_sec

	# If pause music is active and a new main music is explicitly requested,
	# the previous paused main music should not be restored later.
	if _pause_overlay_active and _should_resume_main_music_after_pause:
		_discard_paused_main_music_snapshot(true)

	if not restart and _current_music_id == sound_id and _active_music_player.playing:
		return _active_music_player

	var stream := _load_stream(cue)
	if stream == null:
		return null

	_kill_music_tween_and_normalize()

	var previous_id := _current_music_id
	var old_player := _active_music_player
	var new_player := _inactive_music_player
	var target_db := cue.base_volume_db + extra_volume_db

	new_player.stop()
	new_player.stream = stream
	new_player.bus = _resolve_bus_name(cue.bus)
	new_player.pitch_scale = cue.pitch_scale
	new_player.stream_paused = false
	new_player.volume_db = SILENT_DB if fade_in_sec > 0.0 else target_db
	new_player.play(from_position)

	_active_music_player = new_player
	_inactive_music_player = old_player
	_current_music_id = sound_id
	_current_music_target_volume_db = target_db
	music_changed.emit(previous_id, sound_id)

	var should_fade_in := fade_in_sec > 0.0
	var should_fade_out := old_player.playing and fade_out_sec > 0.0

	if old_player.playing and not should_fade_out:
		old_player.stop()
		old_player.stream = null
		old_player.stream_paused = false

	if not should_fade_in and not should_fade_out:
		return _active_music_player

	_music_tween = create_tween()
	_music_tween.set_parallel(true)

	if should_fade_in:
		_music_tween.tween_property(new_player, "volume_db", target_db, fade_in_sec)

	if should_fade_out:
		_music_tween.tween_property(old_player, "volume_db", SILENT_DB, fade_out_sec)

	_music_tween.finished.connect(_on_music_crossfade_finished.bind(old_player))

	return _active_music_player


func stop_music(fade_out_sec: float = -1.0) -> void:
	if _current_music_id == &"" and not _active_music_player.playing:
		return

	if fade_out_sec < 0.0:
		fade_out_sec = default_music_fade_out_sec

	_kill_music_tween_and_normalize()

	var previous_id := _current_music_id
	var player := _active_music_player

	if fade_out_sec <= 0.0 or not player.playing:
		player.stop()
		player.stream = null
		player.stream_paused = false
		_current_music_id = &""
		_current_music_target_volume_db = 0.0
		music_changed.emit(previous_id, &"")

		if _paused_main_music_player == player:
			_clear_paused_main_music_snapshot()
		return

	_music_tween = create_tween()
	_music_tween.tween_property(player, "volume_db", SILENT_DB, fade_out_sec)
	_music_tween.finished.connect(_on_music_stop_fade_finished.bind(player, previous_id))


func fade_out_music(duration_sec: float = -1.0) -> void:
	stop_music(duration_sec)


func enter_pause_music(
	pause_music_id: StringName,
	fade_in_sec: float = -1.0,
	from_position: float = 0.0
) -> AudioStreamPlayer:
	var cue := _get_cue(pause_music_id, Category.MUSIC)
	if cue == null:
		return null

	if fade_in_sec < 0.0:
		fade_in_sec = default_pause_music_fade_in_sec

	if _pause_overlay_active and _pause_music_id == pause_music_id and _pause_music_player.playing:
		return _pause_music_player

	_capture_and_pause_main_music()
	_capture_and_pause_all_ambiences()

	_kill_pause_music_tween()

	var stream := _load_stream(cue)
	if stream == null:
		return null

	var target_db := cue.base_volume_db

	_pause_music_player.stop()
	_pause_music_player.stream = stream
	_pause_music_player.bus = _resolve_bus_name(cue.bus)
	_pause_music_player.pitch_scale = cue.pitch_scale
	_pause_music_player.stream_paused = false
	_pause_music_player.volume_db = SILENT_DB if fade_in_sec > 0.0 else target_db
	_pause_music_player.play(from_position)

	_pause_overlay_active = true
	_pause_music_id = pause_music_id

	if fade_in_sec <= 0.0:
		return _pause_music_player

	_pause_music_tween = create_tween()
	_pause_music_tween.tween_property(_pause_music_player, "volume_db", target_db, fade_in_sec)

	return _pause_music_player


func exit_pause_music(
	fade_out_sec: float = -1.0,
	resume_main_music: bool = true
) -> void:
	if fade_out_sec < 0.0:
		fade_out_sec = default_pause_music_fade_out_sec

	if resume_main_music:
		_resume_saved_main_music_if_needed()
		_resume_paused_ambiences_if_needed()

	if not _pause_overlay_active:
		return

	_kill_pause_music_tween()

	if fade_out_sec <= 0.0 or not _pause_music_player.playing:
		_pause_music_player.stop()
		_pause_music_player.stream = null
		_pause_music_player.stream_paused = false
		_pause_overlay_active = false
		_pause_music_id = &""
		return

	_pause_music_tween = create_tween()
	_pause_music_tween.tween_property(_pause_music_player, "volume_db", SILENT_DB, fade_out_sec)
	_pause_music_tween.finished.connect(_on_pause_music_exit_fade_finished)


func pause_game(pause_music_id: StringName = &"", fade_in_sec: float = -1.0) -> void:
	# This is a convenience helper.
	# Use it if you want AudioManager to handle the pause flow directly.
	if pause_music_id == &"":
		_capture_and_pause_main_music()
		_capture_and_pause_all_ambiences()
	else:
		enter_pause_music(pause_music_id, fade_in_sec)

	get_tree().paused = true


func resume_game(fade_out_sec: float = -1.0) -> void:
	# This is a convenience helper.
	# Use it if you want AudioManager to handle the resume flow directly.
	get_tree().paused = false
	exit_pause_music(fade_out_sec, true)


func play_ambience(
	sound_id: StringName,
	restart: bool = false,
	extra_volume_db: float = 0.0,
	from_position: float = 0.0
) -> AudioStreamPlayer:
	var cue := _get_cue(sound_id, Category.AMBIENCE)
	if cue == null:
		return null

	var player := _get_or_create_ambience_player(sound_id, cue.bus)
	if player == null:
		return null

	if not restart and player.playing:
		return player

	var previous_ids := get_current_ambience_ids()

	var stream := _load_stream(cue)
	if stream == null:
		return null

	player.stop()
	player.stream = stream
	player.bus = _resolve_bus_name(cue.bus)
	player.volume_db = cue.base_volume_db + extra_volume_db
	player.pitch_scale = cue.pitch_scale
	player.stream_paused = false
	player.play(from_position)

	if not _active_ambience_ids.has(sound_id):
		_active_ambience_ids.append(sound_id)

	# If ambience layers are currently frozen by the pause flow,
	# newly started ambience should also remain paused until resume.
	if _ambience_pause_snapshot_active:
		player.stream_paused = true
		if not _paused_ambience_ids.has(sound_id):
			_paused_ambience_ids.append(sound_id)

	_emit_ambience_state_if_changed(previous_ids)
	return player


func stop_ambience(sound_id: StringName = &"") -> void:
	if sound_id == &"":
		stop_all_ambiences()
		return

	if not _ambience_players_by_id.has(sound_id):
		return

	var previous_ids := get_current_ambience_ids()
	var player := _ambience_players_by_id[sound_id] as AudioStreamPlayer

	if player != null:
		player.stop()
		player.stream = null
		player.stream_paused = false

	_active_ambience_ids.erase(sound_id)
	_paused_ambience_ids.erase(sound_id)

	if _ambience_pause_snapshot_active and _paused_ambience_ids.is_empty():
		_ambience_pause_snapshot_active = false

	_emit_ambience_state_if_changed(previous_ids)


func stop_all_ambiences() -> void:
	var previous_ids := get_current_ambience_ids()

	for player_variant in _ambience_players_by_id.values():
		var player := player_variant as AudioStreamPlayer
		if player != null:
			player.stop()
			player.stream = null
			player.stream_paused = false

	_active_ambience_ids.clear()
	_clear_paused_ambience_snapshot()
	_emit_ambience_state_if_changed(previous_ids)


func pause_ambiences() -> void:
	_capture_and_pause_all_ambiences()


func resume_ambiences() -> void:
	_resume_paused_ambiences_if_needed()


func get_current_music_id() -> StringName:
	return _current_music_id


func get_current_ambience_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for sound_id in _active_ambience_ids:
		var player := _ambience_players_by_id.get(sound_id) as AudioStreamPlayer
		if player != null and player.playing:
			ids.append(sound_id)
	return ids


func is_ambience_playing(sound_id: StringName) -> bool:
	var player := _ambience_players_by_id.get(sound_id) as AudioStreamPlayer
	return player != null and player.playing


func is_pause_music_active() -> bool:
	return _pause_overlay_active


func get_pause_music_id() -> StringName:
	return _pause_music_id


func play_sfx(
	sound_id: StringName,
	extra_volume_db: float = 0.0,
	pitch_multiplier: float = 1.0
) -> AudioStreamPlayer:
	var cue := _get_cue(sound_id, Category.SFX)
	return _play_one_shot(cue, _sfx_players, extra_volume_db, pitch_multiplier)


func play_ui(
	sound_id: StringName,
	extra_volume_db: float = 0.0,
	pitch_multiplier: float = 1.0
) -> AudioStreamPlayer:
	var cue := _get_cue(sound_id, Category.UI)
	return _play_one_shot(cue, _ui_players, extra_volume_db, pitch_multiplier)


func stop_all_one_shots() -> void:
	for player in _sfx_players:
		player.stop()
		player.stream_paused = false

	for player in _ui_players:
		player.stop()
		player.stream_paused = false


func stop_all() -> void:
	stop_music(0.0)
	stop_all_ambiences()
	_stop_pause_music_immediately()
	stop_all_one_shots()


func set_bus_volume_linear(bus_name: StringName, value: float) -> void:
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx == -1:
		push_warning("AudioManager: bus '%s' not found." % String(bus_name))
		return

	var safe_value := clampf(value, 0.0, 1.0)

	if safe_value <= 0.0001:
		AudioServer.set_bus_volume_db(bus_idx, SILENT_DB)
	else:
		AudioServer.set_bus_volume_linear(bus_idx, safe_value)

	bus_volume_changed.emit(
		bus_name,
		safe_value,
		AudioServer.get_bus_volume_db(bus_idx)
	)


func get_bus_volume_linear(bus_name: StringName) -> float:
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx == -1:
		return 1.0

	return AudioServer.get_bus_volume_linear(bus_idx)


func set_category_volume_linear(category: int, value: float) -> void:
	set_bus_volume_linear(_default_bus_for_category(category), value)


func apply_bus_preferences(values: Dictionary) -> void:
	if values.has("master"):
		set_bus_volume_linear(BUS_MASTER, float(values["master"]))

	if values.has("music"):
		set_bus_volume_linear(BUS_MUSIC, float(values["music"]))

	if values.has("sfx"):
		set_bus_volume_linear(BUS_SFX, float(values["sfx"]))

	if values.has("ui"):
		set_bus_volume_linear(BUS_UI, float(values["ui"]))

	if values.has("ambience"):
		set_bus_volume_linear(BUS_AMBIENCE, float(values["ambience"]))


func _play_one_shot(
	cue: AudioCue,
	players: Array[AudioStreamPlayer],
	extra_volume_db: float,
	pitch_multiplier: float
) -> AudioStreamPlayer:
	if cue == null:
		return null

	var stream := _load_stream(cue)
	if stream == null:
		return null

	var player := _get_player_from_pool(players)
	if player == null:
		return null

	player.stop()
	player.stream = stream
	player.bus = _resolve_bus_name(cue.bus)
	player.volume_db = cue.base_volume_db + extra_volume_db

	var random_offset := 0.0
	if cue.pitch_random > 0.0:
		random_offset = randf_range(-cue.pitch_random, cue.pitch_random)

	player.pitch_scale = maxf(0.01, cue.pitch_scale * pitch_multiplier + random_offset)
	player.stream_paused = false
	player.play()

	return player


func _get_player_from_pool(players: Array[AudioStreamPlayer]) -> AudioStreamPlayer:
	for player in players:
		if not player.playing:
			return player

	# If every player is busy, reuse the one that is furthest into playback.
	var fallback := players[0]
	var furthest_position := -1.0

	for player in players:
		var position := player.get_playback_position()
		if position > furthest_position:
			furthest_position = position
			fallback = player

	return fallback


func _get_cue(sound_id: StringName, expected_category: int = -1) -> AudioCue:
	var cue := _cues.get(sound_id) as AudioCue

	if cue == null:
		sound_missing.emit(sound_id, "")
		push_warning("AudioManager: unknown sound id '%s'." % String(sound_id))
		return null

	if expected_category != -1 and cue.category != expected_category:
		push_warning(
			"AudioManager: sound '%s' has category %s, expected %s."
			% [String(sound_id), str(cue.category), str(expected_category)]
		)
		return null

	return cue


func _load_stream(cue: AudioCue) -> AudioStream:
	if cue.stream != null:
		return cue.stream

	var stream := load(cue.path) as AudioStream
	if stream == null:
		sound_missing.emit(cue.id, cue.path)
		push_warning(
			"AudioManager: could not load sound '%s' at path '%s'."
			% [String(cue.id), cue.path]
		)
		return null

	cue.stream = stream
	return cue.stream


func _warmup_flagged_sounds() -> void:
	for cue_variant in _cues.values():
		var cue := cue_variant as AudioCue
		if cue.preload_on_ready:
			_load_stream(cue)


func _create_core_players() -> void:
	_music_player_a = _create_player("MusicPlayerA", BUS_MUSIC)
	_music_player_a.finished.connect(_on_music_player_finished.bind(_music_player_a))

	_music_player_b = _create_player("MusicPlayerB", BUS_MUSIC)
	_music_player_b.finished.connect(_on_music_player_finished.bind(_music_player_b))

	_active_music_player = _music_player_a
	_inactive_music_player = _music_player_b

	_pause_music_player = _create_player("PauseMusicPlayer", BUS_MUSIC)
	_pause_music_player.finished.connect(_on_pause_music_player_finished)

	for i in range(DEFAULT_SFX_POOL_SIZE):
		_sfx_players.append(_create_player("SFXPlayer_%d" % i, BUS_SFX))

	for i in range(DEFAULT_UI_POOL_SIZE):
		_ui_players.append(_create_player("UIPlayer_%d" % i, BUS_UI))


func _create_player(player_name: String, bus_name: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.bus = _resolve_bus_name(bus_name)
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	return player


func _validate_buses() -> void:
	for bus_name in [BUS_MASTER, BUS_MUSIC, BUS_SFX, BUS_UI, BUS_AMBIENCE]:
		if AudioServer.get_bus_index(bus_name) == -1:
			push_warning(
				"AudioManager: audio bus '%s' not found. Falling back to Master when needed."
				% String(bus_name)
			)


func _resolve_bus_name(bus_name: StringName) -> StringName:
	if AudioServer.get_bus_index(bus_name) == -1:
		return BUS_MASTER
	return bus_name


func _default_bus_for_category(category: int) -> StringName:
	match category:
		Category.MUSIC:
			return BUS_MUSIC
		Category.SFX:
			return BUS_SFX
		Category.UI:
			return BUS_UI
		Category.AMBIENCE:
			return BUS_AMBIENCE
		_:
			return BUS_MASTER


func _other_main_music_player(player: AudioStreamPlayer) -> AudioStreamPlayer:
	if player == _music_player_a:
		return _music_player_b
	return _music_player_a


func _get_or_create_ambience_player(sound_id: StringName, bus_name: StringName) -> AudioStreamPlayer:
	var player := _ambience_players_by_id.get(sound_id) as AudioStreamPlayer
	if player != null:
		return player

	player = _create_player("Ambience_%s" % String(sound_id), bus_name)
	player.finished.connect(_on_ambience_player_finished.bind(sound_id))
	_ambience_players_by_id[sound_id] = player
	return player


func _emit_ambience_state_if_changed(previous_ids: Array[StringName]) -> void:
	var new_ids := get_current_ambience_ids()
	ambience_layers_changed.emit(new_ids)

	if previous_ids != new_ids:
		ambience_changed.emit(previous_ids, new_ids)


func _capture_and_pause_main_music() -> void:
	# Stabilize the main music state before pausing it.
	_kill_music_tween_and_normalize()

	if _should_resume_main_music_after_pause:
		return

	if _active_music_player == null:
		return

	if not _active_music_player.playing:
		return

	if _current_music_id == &"":
		return

	_paused_main_music_player = _active_music_player
	_paused_main_music_id = _current_music_id
	_paused_main_music_target_volume_db = _current_music_target_volume_db
	_paused_main_music_position_sec = _active_music_player.get_playback_position()
	_should_resume_main_music_after_pause = true

	_paused_main_music_player.stream_paused = true


func _resume_saved_main_music_if_needed() -> void:
	if not _should_resume_main_music_after_pause:
		return

	if _paused_main_music_player == null:
		_clear_paused_main_music_snapshot()
		return

	_paused_main_music_player.volume_db = _paused_main_music_target_volume_db
	_paused_main_music_player.stream_paused = false

	_active_music_player = _paused_main_music_player
	_inactive_music_player = _other_main_music_player(_active_music_player)
	_current_music_id = _paused_main_music_id
	_current_music_target_volume_db = _paused_main_music_target_volume_db

	_clear_paused_main_music_snapshot()


func _discard_paused_main_music_snapshot(stop_saved_player: bool) -> void:
	if _paused_main_music_player != null and stop_saved_player:
		_paused_main_music_player.stream_paused = false
		_paused_main_music_player.stop()
		_paused_main_music_player.stream = null

	_clear_paused_main_music_snapshot()


func _clear_paused_main_music_snapshot() -> void:
	_should_resume_main_music_after_pause = false
	_paused_main_music_player = null
	_paused_main_music_id = &""
	_paused_main_music_target_volume_db = 0.0
	_paused_main_music_position_sec = 0.0


func _capture_and_pause_all_ambiences() -> void:
	if _ambience_pause_snapshot_active:
		return

	_ambience_pause_snapshot_active = true
	_paused_ambience_ids.clear()

	for sound_id in _active_ambience_ids:
		var player := _ambience_players_by_id.get(sound_id) as AudioStreamPlayer
		if player != null and player.playing and not player.stream_paused:
			player.stream_paused = true
			_paused_ambience_ids.append(sound_id)


func _resume_paused_ambiences_if_needed() -> void:
	if not _ambience_pause_snapshot_active:
		return

	for sound_id in _paused_ambience_ids:
		var player := _ambience_players_by_id.get(sound_id) as AudioStreamPlayer
		if player != null and player.playing:
			player.stream_paused = false

	_clear_paused_ambience_snapshot()


func _clear_paused_ambience_snapshot() -> void:
	_ambience_pause_snapshot_active = false
	_paused_ambience_ids.clear()


func _kill_music_tween_and_normalize() -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()

	_music_tween = null

	if _active_music_player != null and _active_music_player.playing:
		_active_music_player.volume_db = _current_music_target_volume_db

	if _inactive_music_player != null and _inactive_music_player.playing:
		_inactive_music_player.stop()
		_inactive_music_player.stream = null
		_inactive_music_player.stream_paused = false


func _kill_pause_music_tween() -> void:
	if _pause_music_tween != null and _pause_music_tween.is_valid():
		_pause_music_tween.kill()

	_pause_music_tween = null


func _stop_pause_music_immediately() -> void:
	_kill_pause_music_tween()

	if _pause_music_player != null:
		_pause_music_player.stop()
		_pause_music_player.stream = null
		_pause_music_player.stream_paused = false

	_pause_overlay_active = false
	_pause_music_id = &""
	_clear_paused_main_music_snapshot()
	_clear_paused_ambience_snapshot()


func _on_music_crossfade_finished(old_player: AudioStreamPlayer) -> void:
	if old_player != null:
		old_player.stop()
		old_player.stream = null
		old_player.stream_paused = false

	_music_tween = null


func _on_music_stop_fade_finished(player: AudioStreamPlayer, previous_id: StringName) -> void:
	player.stop()
	player.stream = null
	player.stream_paused = false
	_music_tween = null

	if player == _active_music_player:
		_current_music_id = &""
		_current_music_target_volume_db = 0.0
		music_changed.emit(previous_id, &"")

	if player == _paused_main_music_player:
		_clear_paused_main_music_snapshot()


func _on_pause_music_exit_fade_finished() -> void:
	_pause_music_player.stop()
	_pause_music_player.stream = null
	_pause_music_player.stream_paused = false
	_pause_music_tween = null
	_pause_overlay_active = false
	_pause_music_id = &""


func _on_music_player_finished(player: AudioStreamPlayer) -> void:
	if player != _active_music_player:
		return

	var previous_id := _current_music_id
	_current_music_id = &""
	_current_music_target_volume_db = 0.0
	music_changed.emit(previous_id, &"")

	if player == _paused_main_music_player:
		_clear_paused_main_music_snapshot()


func _on_pause_music_player_finished() -> void:
	# If the pause track ends naturally, keep the pause state alive.
	# The normal main music and ambience layers remain paused until resume.
	_pause_music_id = &""


func _on_ambience_player_finished(sound_id: StringName) -> void:
	var previous_ids := get_current_ambience_ids()

	_active_ambience_ids.erase(sound_id)
	_paused_ambience_ids.erase(sound_id)

	if _ambience_pause_snapshot_active and _paused_ambience_ids.is_empty():
		_ambience_pause_snapshot_active = false

	_emit_ambience_state_if_changed(previous_ids)
