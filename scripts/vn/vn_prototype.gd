extends Control

enum DialogueState {
	INTRO,
	BRANCH,
	SHARED_ENDING,
	ENDED,
}

const INTRO_LINES := [
	{"speaker": "Jukain", "expression": "tired", "text": "...Why are we still here?"},
	{"speaker": "Hiruko", "expression": "neutral", "text": "Because Valentine told us to clean the classroom."},
	{"speaker": "Jukain", "expression": "tired", "text": "She also said, \"I'll be back in five minutes.\""},
	{"speaker": "Hiruko", "expression": "neutral", "text": "Yes."},
	{"speaker": "Jukain", "expression": "smirk", "text": "That was thirty minutes ago."},
	{"speaker": "Hiruko", "expression": "annoyed", "text": "Are you going to complain, or are you going to move those chairs?"},
	{"speaker": "Jukain", "expression": "smirk", "text": "Important question. What happens if I choose complaining?"},
]

const OPTION_A_LINES := [
	{"speaker": "Jukain", "expression": "tired", "text": "Fine. I'll help. But I want it officially recorded that I did so unwillingly."},
	{"speaker": "Hiruko", "expression": "faint_smile", "text": "Your sacrifice will be remembered."},
]

const OPTION_B_LINES := [
	{"speaker": "Jukain", "expression": "smirk", "text": "I think my role here should be moral support."},
	{"speaker": "Hiruko", "expression": "annoyed", "text": "Then morally support that chair into the corner."},
]

const SHARED_ENDING_LINES := [
	{"speaker": "Jukain", "expression": "tired", "text": "You know, you're surprisingly difficult to argue with."},
	{"speaker": "Hiruko", "expression": "neutral", "text": "Pick up the chair, Jukain."},
	{"speaker": "Jukain", "expression": "smirk", "text": "See? Completely unreasonable."},
	{"speaker": "Hiruko", "expression": "faint_smile", "text": "Move."},
]

const CHARACTER_TEXTURES := {
	"Jukain": {
		"tired": preload("res://assets/art/characters/Jukain/Jukain_tired.png"),
		"smirk": preload("res://assets/art/characters/Jukain/Jukain_smirk.png"),
	},
	"Hiruko": {
		"neutral": preload("res://assets/art/characters/Hiruko/Hiruko_neutral.png"),
		"annoyed": preload("res://assets/art/characters/Hiruko/Hiruko_annoyed.png"),
		"faint_smile": preload("res://assets/art/characters/Hiruko/Hiruko_faint_smile.png"),
	},
}

@onready var story_background: TextureRect = %StoryBackground
@onready var character_layer: Control = %CharacterLayer
@onready var jukain_sprite: TextureRect = %JukainSprite
@onready var hiruko_sprite: TextureRect = %HirukoSprite
@onready var dialogue_panel: PanelContainer = %DialoguePanel
@onready var speaker_name: Label = %SpeakerName
@onready var dialogue_text: RichTextLabel = %DialogueText
@onready var choice_panel: PanelContainer = %ChoicePanel
@onready var option_a_button: Button = %OptionAButton
@onready var option_b_button: Button = %OptionBButton
@onready var end_background: ColorRect = %EndBackground
@onready var end_content: VBoxContainer = %EndContent
@onready var restart_button: Button = %RestartButton

var dialogue_state := DialogueState.INTRO
var line_index := 0
var branch_lines: Array = []
var awaiting_choice := false


func _ready() -> void:
	option_a_button.pressed.connect(_on_option_selected.bind(OPTION_A_LINES))
	option_b_button.pressed.connect(_on_option_selected.bind(OPTION_B_LINES))
	restart_button.pressed.connect(_restart_scene)
	_reset_prototype()


func _input(event: InputEvent) -> void:
	if dialogue_state == DialogueState.ENDED or awaiting_choice:
		return

	var requested_advance := false
	if event is InputEventMouseButton:
		requested_advance = event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	elif event.is_action_pressed("ui_accept"):
		requested_advance = true

	if requested_advance:
		get_viewport().set_input_as_handled()
		_advance_dialogue()


func _reset_prototype() -> void:
	dialogue_state = DialogueState.INTRO
	line_index = 0
	branch_lines = []
	awaiting_choice = false

	story_background.show()
	character_layer.show()
	dialogue_panel.show()
	choice_panel.hide()
	end_background.hide()
	end_content.hide()

	jukain_sprite.texture = CHARACTER_TEXTURES["Jukain"]["tired"]
	hiruko_sprite.texture = CHARACTER_TEXTURES["Hiruko"]["neutral"]
	_show_line(INTRO_LINES[line_index])


func _advance_dialogue() -> void:
	match dialogue_state:
		DialogueState.INTRO:
			if line_index < INTRO_LINES.size() - 1:
				line_index += 1
				_show_line(INTRO_LINES[line_index])
			else:
				_show_choices()
		DialogueState.BRANCH:
			if line_index < branch_lines.size() - 1:
				line_index += 1
				_show_line(branch_lines[line_index])
			else:
				dialogue_state = DialogueState.SHARED_ENDING
				line_index = 0
				_show_line(SHARED_ENDING_LINES[line_index])
		DialogueState.SHARED_ENDING:
			if line_index < SHARED_ENDING_LINES.size() - 1:
				line_index += 1
				_show_line(SHARED_ENDING_LINES[line_index])
			else:
				_finish_scene()


func _show_line(line: Dictionary) -> void:
	var speaker: String = line["speaker"]
	var expression: String = line["expression"]

	speaker_name.text = speaker
	dialogue_text.text = line["text"]
	if speaker == "Jukain":
		jukain_sprite.texture = CHARACTER_TEXTURES[speaker][expression]
		jukain_sprite.modulate = Color.WHITE
		hiruko_sprite.modulate = Color(0.58, 0.58, 0.64, 0.82)
	else:
		hiruko_sprite.texture = CHARACTER_TEXTURES[speaker][expression]
		hiruko_sprite.modulate = Color.WHITE
		jukain_sprite.modulate = Color(0.58, 0.58, 0.64, 0.82)


func _show_choices() -> void:
	awaiting_choice = true
	choice_panel.show()
	option_a_button.grab_focus()


func _on_option_selected(selected_branch: Array) -> void:
	if not awaiting_choice:
		return

	awaiting_choice = false
	choice_panel.hide()
	branch_lines = selected_branch
	dialogue_state = DialogueState.BRANCH
	line_index = 0
	_show_line(branch_lines[line_index])


func _finish_scene() -> void:
	dialogue_state = DialogueState.ENDED
	awaiting_choice = false
	choice_panel.hide()
	dialogue_panel.hide()
	character_layer.hide()
	story_background.hide()
	end_background.show()
	end_content.show()
	restart_button.grab_focus()


func _restart_scene() -> void:
	get_tree().reload_current_scene()
