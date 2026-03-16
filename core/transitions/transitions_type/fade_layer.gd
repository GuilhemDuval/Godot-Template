extends CanvasLayer

signal transition_finished(direction: String)

@export var duration: float = 0.35
@export var fade_color: Color = Color.BLACK

@onready var color_rect: ColorRect = $ColorRect

var _tween: Tween = null
var _is_playing: bool = false
var _current_direction: String = ""


func _ready() -> void:
	_setup_color_rect()
	_set_alpha(0.0)


func play_out() -> void:
	_play_transition("out", 1.0)


func play_in() -> void:
	_play_transition("in", 0.0)


func skip() -> void:
	if not _is_playing:
		return

	if _tween != null:
		_tween.kill()
		_tween = null

	match _current_direction:
		"out":
			_set_alpha(1.0)
		"in":
			_set_alpha(0.0)

	_is_playing = false
	transition_finished.emit(_current_direction)


func is_playing() -> bool:
	return _is_playing


func _play_transition(direction: String, target_alpha: float) -> void:
	if _tween != null:
		_tween.kill()
		_tween = null

	_current_direction = direction
	_is_playing = true

	color_rect.visible = true

	_tween = create_tween()
	_tween.tween_property(color_rect, "modulate:a", target_alpha, duration)
	_tween.finished.connect(_on_tween_finished)


func _on_tween_finished() -> void:
	_tween = null
	_is_playing = false

	if _current_direction == "in":
		color_rect.visible = false

	transition_finished.emit(_current_direction)


func _setup_color_rect() -> void:
	color_rect.color = fade_color
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	color_rect.offset_left = 0
	color_rect.offset_top = 0
	color_rect.offset_right = 0
	color_rect.offset_bottom = 0
	color_rect.visible = true


func _set_alpha(value: float) -> void:
	color_rect.modulate.a = value
	color_rect.visible = value > 0.0
