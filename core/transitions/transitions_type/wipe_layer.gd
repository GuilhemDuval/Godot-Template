extends CanvasLayer

signal transition_finished(direction: String)

enum WipeDirection {
	LEFT_TO_RIGHT,
	RIGHT_TO_LEFT,
	TOP_TO_BOTTOM,
	BOTTOM_TO_TOP
}

@export var duration: float = 0.4
@export var wipe_color: Color = Color.BLACK
@export var wipe_direction: WipeDirection = WipeDirection.LEFT_TO_RIGHT

@onready var color_rect: ColorRect = $ColorRect

var _tween: Tween = null
var _is_playing: bool = false
var _current_phase: String = ""


func _ready() -> void:
	_setup_color_rect()
	_apply_hidden_state()


func play_out() -> void:
	_play_transition("out")


func play_in() -> void:
	_play_transition("in")


func skip() -> void:
	if not _is_playing:
		return

	if _tween != null:
		_tween.kill()
		_tween = null

	if _current_phase == "out":
		_apply_shown_state()
	elif _current_phase == "in":
		_apply_hidden_state()

	_is_playing = false
	transition_finished.emit(_current_phase)


func is_playing() -> bool:
	return _is_playing


func _play_transition(phase: String) -> void:
	if _tween != null:
		_tween.kill()
		_tween = null

	_current_phase = phase
	_is_playing = true

	color_rect.visible = true
	_setup_color_rect()

	var hidden_position := _get_hidden_position()
	var shown_position := Vector2.ZERO

	if phase == "out":
		color_rect.position = hidden_position
		_tween = create_tween()
		_tween.tween_property(color_rect, "position", shown_position, duration)
	else:
		color_rect.position = shown_position
		_tween = create_tween()
		_tween.tween_property(color_rect, "position", hidden_position, duration)

	_tween.finished.connect(_on_tween_finished)


func _on_tween_finished() -> void:
	_tween = null
	_is_playing = false

	if _current_phase == "in":
		color_rect.visible = false

	transition_finished.emit(_current_phase)


func _setup_color_rect() -> void:
	color_rect.color = wipe_color
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	color_rect.offset_left = 0
	color_rect.offset_top = 0
	color_rect.offset_right = 0
	color_rect.offset_bottom = 0


func _apply_hidden_state() -> void:
	color_rect.position = _get_hidden_position()
	color_rect.visible = false


func _apply_shown_state() -> void:
	color_rect.position = Vector2.ZERO
	color_rect.visible = true


func _get_hidden_position() -> Vector2:
	var viewport_size := get_viewport().get_visible_rect().size

	match wipe_direction:
		WipeDirection.LEFT_TO_RIGHT:
			return Vector2(-viewport_size.x, 0.0)
		WipeDirection.RIGHT_TO_LEFT:
			return Vector2(viewport_size.x, 0.0)
		WipeDirection.TOP_TO_BOTTOM:
			return Vector2(0.0, -viewport_size.y)
		WipeDirection.BOTTOM_TO_TOP:
			return Vector2(0.0, viewport_size.y)
		_:
			return Vector2(-viewport_size.x, 0.0)
