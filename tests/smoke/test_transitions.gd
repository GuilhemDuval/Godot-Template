extends Control

@onready var current_transition_label: Label = $CenterPanel/MarginContainer/VBoxContainer/CurrentTransitionLabel
@onready var transition_host: Node = $TransitionHost

const TRANSITION_SCENES := [
	"res://core/transitions/transition_scenes/fade_black.tscn",
	"res://core/transitions/transition_scenes/fade_long_black.tscn",
	"res://core/transitions/transition_scenes/fade_white.tscn",
	"res://core/transitions/transition_scenes/fade_flash_white.tscn",
	"res://core/transitions/transition_scenes/wipe_left_to_right.tscn",
	"res://core/transitions/transition_scenes/wipe_right_to_left.tscn",
	"res://core/transitions/transition_scenes/wipe_top_to_bottom.tscn",
	"res://core/transitions/transition_scenes/wipe_bottom_to_top.tscn",
]

@export var auto_start: bool = true
@export var loop_sequence: bool = true
@export var delay_before_start: float = 1
@export var delay_between_transitions: float = 1
@export var hold_between_out_and_in: float = 0.3
@export var hold_after_in: float = 0.2

var _is_running: bool = false


func _ready() -> void:
	if auto_start:
		call_deferred("_start_sequence")


func _start_sequence() -> void:
	if _is_running:
		return

	_is_running = true
	await get_tree().create_timer(delay_before_start).timeout

	while true:
		for scene_path in TRANSITION_SCENES:
			await _play_transition_scene(scene_path)

		if not loop_sequence:
			break

	current_transition_label.text = "Sequence finished."
	_is_running = false


func _play_transition_scene(scene_path: String) -> void:
	var packed_scene: PackedScene = load(scene_path) as PackedScene
	if packed_scene == null:
		push_error("Could not load transition scene: %s" % scene_path)
		return

	var transition: Node = packed_scene.instantiate()
	if transition == null:
		push_error("Could not instantiate transition scene: %s" % scene_path)
		return

	transition_host.add_child(transition)

	var transition_name := _get_scene_name(scene_path)
	current_transition_label.text = "Testing: %s" % transition_name

	if not transition.has_signal("transition_finished"):
		push_error("Transition has no 'transition_finished' signal: %s" % scene_path)
		transition.queue_free()
		return

	if not transition.has_method("play_out"):
		push_error("Transition has no 'play_out()' method: %s" % scene_path)
		transition.queue_free()
		return

	if not transition.has_method("play_in"):
		push_error("Transition has no 'play_in()' method: %s" % scene_path)
		transition.queue_free()
		return

	transition.play_out()
	await transition.transition_finished

	await get_tree().create_timer(hold_between_out_and_in).timeout

	transition.play_in()
	await transition.transition_finished

	await get_tree().create_timer(hold_after_in).timeout

	transition.queue_free()
	await get_tree().process_frame

	await get_tree().create_timer(delay_between_transitions).timeout


func _get_scene_name(scene_path: String) -> String:
	return scene_path.get_file().get_basename()
