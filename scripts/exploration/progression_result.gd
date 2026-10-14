extends Control

@onready var save_button: Button = %ResultSaveButton
@onready var load_button: Button = %ResultLoadButton
@onready var status_label: Label = %ResultSaveLoadStatus


func _ready() -> void:
	save_button.pressed.connect(_on_save)
	load_button.pressed.connect(_on_load)
	load_button.disabled = not GameState.has_save_file()
	status_label.text = GameState.persistence_feedback if not GameState.persistence_feedback.is_empty() else "Save / Load"


func _on_save() -> void:
	if GameState.save_result_game():
		status_label.text = "Saved successfully."
	else:
		status_label.text = "Save failed: %s" % GameState.persistence_error
	load_button.disabled = not GameState.has_save_file()


func _on_load() -> void:
	if GameState.load_saved_game():
		return
	status_label.text = "Load failed: %s" % GameState.persistence_error
	load_button.disabled = not GameState.has_save_file()
