extends Control

signal scene_enter_transition_finished
signal scene_exit_transition_finished

@export var enter_delay: float = 0.05
@export var exit_delay: float = 0.05


func play_scene_enter_transition() -> void:
	await get_tree().create_timer(enter_delay).timeout
	scene_enter_transition_finished.emit()


func play_scene_exit_transition() -> void:
	await get_tree().create_timer(exit_delay).timeout
	scene_exit_transition_finished.emit()
