extends Control

const DIALOGUE_PATH := "res://data/dialogue/vn_prototype_m1.json"

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

var dialogue_nodes: Dictionary = {}
var start_node_id := ""
var current_node_id := ""
var awaiting_choice := false
var scene_ended := false
var dialogue_ready := false


func _ready() -> void:
	option_a_button.pressed.connect(_on_option_selected.bind(0))
	option_b_button.pressed.connect(_on_option_selected.bind(1))
	restart_button.pressed.connect(_restart_scene)

	dialogue_ready = _load_dialogue_data()
	if dialogue_ready:
		_reset_prototype()
	else:
		_show_dialogue_error()


func _input(event: InputEvent) -> void:
	if not dialogue_ready or scene_ended or awaiting_choice:
		return

	var requested_advance := false
	if event is InputEventMouseButton:
		requested_advance = event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	elif event.is_action_pressed("ui_accept"):
		requested_advance = true

	if requested_advance:
		get_viewport().set_input_as_handled()
		_advance_dialogue()


func _load_dialogue_data() -> bool:
	var file := FileAccess.open(DIALOGUE_PATH, FileAccess.READ)
	if file == null:
		return _report_dialogue_error(
			"Could not open %s: %s" % [DIALOGUE_PATH, error_string(FileAccess.get_open_error())]
		)

	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	if parse_error != OK:
		return _report_dialogue_error(
			"Malformed JSON in %s at line %d: %s"
			% [DIALOGUE_PATH, json.get_error_line(), json.get_error_message()]
		)

	if typeof(json.data) != TYPE_DICTIONARY:
		return _report_dialogue_error("Dialogue root must be an object in %s." % DIALOGUE_PATH)

	return _validate_and_index_dialogue(json.data)


func _validate_and_index_dialogue(data: Dictionary) -> bool:
	dialogue_nodes.clear()
	start_node_id = _required_string(data, "start")
	if start_node_id.is_empty():
		return false

	var raw_nodes: Variant = data.get("nodes", [])
	if typeof(raw_nodes) != TYPE_ARRAY or raw_nodes.is_empty():
		return _report_dialogue_error("Dialogue data requires a non-empty 'nodes' array.")

	for raw_node: Variant in raw_nodes:
		if typeof(raw_node) != TYPE_DICTIONARY:
			return _report_dialogue_error("Every dialogue node must be an object.")

		var node: Dictionary = raw_node
		var node_id := _required_string(node, "id")
		var node_type := _required_string(node, "type")
		if node_id.is_empty() or node_type.is_empty():
			return false
		if dialogue_nodes.has(node_id):
			return _report_dialogue_error("Duplicate dialogue node ID '%s'." % node_id)

		match node_type:
			"line":
				if not _validate_line_node(node, node_id):
					return false
			"choice":
				if not _validate_choice_node(node, node_id):
					return false
			"condition":
				if not _validate_condition_node(node, node_id):
					return false
			"end":
				pass
			_:
				return _report_dialogue_error(
					"Node '%s' has unsupported type '%s'." % [node_id, node_type]
				)

		dialogue_nodes[node_id] = node

	if not dialogue_nodes.has(start_node_id):
		return _report_dialogue_error("Start node '%s' does not exist." % start_node_id)

	for node_id: String in dialogue_nodes:
		var node: Dictionary = dialogue_nodes[node_id]
		if node["type"] == "line":
			if not dialogue_nodes.has(node["next"]):
				return _report_dialogue_error(
					"Line node '%s' targets missing node '%s'." % [node_id, node["next"]]
				)
		elif node["type"] == "choice":
			for option: Dictionary in node["options"]:
				if not dialogue_nodes.has(option["target"]):
					return _report_dialogue_error(
						"Choice node '%s' targets missing branch '%s'."
						% [node_id, option["target"]]
					)
		elif node["type"] == "condition":
			for target_field in ["true_target", "false_target"]:
				if not dialogue_nodes.has(node[target_field]):
					return _report_dialogue_error(
						"Condition node '%s' has missing %s '%s'."
						% [node_id, target_field, node[target_field]]
					)

	return true


func _validate_line_node(node: Dictionary, node_id: String) -> bool:
	var speaker := _required_string(node, "speaker", node_id)
	var text := _required_string(node, "text", node_id)
	var expression := _required_string(node, "expression", node_id)
	var next_node := _required_string(node, "next", node_id)
	if speaker.is_empty() or text.is_empty() or expression.is_empty() or next_node.is_empty():
		return false

	if not CHARACTER_TEXTURES.has(speaker):
		return _report_dialogue_error("Line node '%s' has unknown speaker '%s'." % [node_id, speaker])
	var speaker_textures: Dictionary = CHARACTER_TEXTURES[speaker]
	if not speaker_textures.has(expression):
		return _report_dialogue_error(
			"Line node '%s' has invalid expression '%s' for %s."
			% [node_id, expression, speaker]
		)

	return true


func _validate_choice_node(node: Dictionary, node_id: String) -> bool:
	var options: Variant = node.get("options", [])
	if typeof(options) != TYPE_ARRAY or options.size() != 2:
		return _report_dialogue_error(
			"Choice node '%s' must contain exactly two options for the existing UI." % node_id
		)

	for option_index in options.size():
		var raw_option: Variant = options[option_index]
		if typeof(raw_option) != TYPE_DICTIONARY:
			return _report_dialogue_error(
				"Option %d in choice node '%s' must be an object." % [option_index, node_id]
			)
		var option: Dictionary = raw_option
		if _required_string(option, "text", "%s option %d" % [node_id, option_index]).is_empty():
			return false
		if _required_string(option, "target", "%s option %d" % [node_id, option_index]).is_empty():
			return false
		if not _validate_effects(option, "%s option %d" % [node_id, option_index]):
			return false

	return true


func _validate_effects(option: Dictionary, context: String) -> bool:
	var effects: Variant = option.get("effects", [])
	if typeof(effects) != TYPE_ARRAY:
		return _report_dialogue_error("The 'effects' field in %s must be an array." % context)

	for effect_index in effects.size():
		var raw_effect: Variant = effects[effect_index]
		var effect_context := "%s effect %d" % [context, effect_index]
		if typeof(raw_effect) != TYPE_DICTIONARY:
			return _report_dialogue_error("%s must be an object." % effect_context)

		var effect: Dictionary = raw_effect
		var effect_type := _required_string(effect, "type", effect_context)
		if effect_type.is_empty():
			return false

		match effect_type:
			"set_flag":
				if not _has_only_fields(effect, ["type", "flag", "value"], effect_context):
					return false
				if _required_string(effect, "flag", effect_context).is_empty():
					return false
				if not effect.has("value") or typeof(effect["value"]) != TYPE_BOOL:
					return _report_dialogue_error(
						"Missing or invalid boolean 'value' in %s." % effect_context
					)
			"adjust_bond":
				if not _has_only_fields(effect, ["type", "bond", "amount"], effect_context):
					return false
				if _required_string(effect, "bond", effect_context).is_empty():
					return false
				if not _is_integer_value(effect.get("amount")):
					return _report_dialogue_error(
						"Missing or invalid integer 'amount' in %s." % effect_context
					)
			_:
				return _report_dialogue_error(
					"Unknown effect type '%s' in %s." % [effect_type, effect_context]
				)

	return true


func _validate_condition_node(node: Dictionary, node_id: String) -> bool:
	var raw_condition: Variant = node.get("condition")
	if typeof(raw_condition) != TYPE_DICTIONARY:
		return _report_dialogue_error("Condition node '%s' requires a condition object." % node_id)

	var condition: Dictionary = raw_condition
	if not _has_only_fields(condition, ["type", "flag", "value"], "condition node '%s'" % node_id):
		return false
	var condition_type := _required_string(condition, "type", "condition node '%s'" % node_id)
	if condition_type != "flag_equals":
		return _report_dialogue_error(
			"Unknown condition type '%s' in node '%s'." % [condition_type, node_id]
		)
	if _required_string(condition, "flag", "condition node '%s'" % node_id).is_empty():
		return false
	if not condition.has("value") or typeof(condition["value"]) != TYPE_BOOL:
		return _report_dialogue_error(
			"Condition node '%s' requires a boolean 'value'." % node_id
		)
	if _required_string(node, "true_target", node_id).is_empty():
		return false
	if _required_string(node, "false_target", node_id).is_empty():
		return false

	return true


func _has_only_fields(data: Dictionary, allowed_fields: Array, context: String) -> bool:
	for field: Variant in data:
		if not allowed_fields.has(field):
			return _report_dialogue_error("Unknown field '%s' in %s." % [field, context])
	return true


func _is_integer_value(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and value == floor(value)


func _required_string(data: Dictionary, field: String, context := "dialogue root") -> String:
	if not data.has(field) or typeof(data[field]) != TYPE_STRING or data[field].is_empty():
		_report_dialogue_error("Missing or invalid '%s' in %s." % [field, context])
		return ""
	return data[field]


func _report_dialogue_error(message: String) -> bool:
	push_error("VN dialogue error: %s" % message)
	return false


func _show_dialogue_error() -> void:
	awaiting_choice = false
	scene_ended = false
	choice_panel.hide()
	end_background.hide()
	end_content.hide()
	story_background.show()
	character_layer.show()
	dialogue_panel.show()
	speaker_name.text = "Dialogue Error"
	dialogue_text.text = "The scene data could not be loaded. Check the Godot debugger for details."


func _reset_prototype() -> void:
	current_node_id = ""
	awaiting_choice = false
	scene_ended = false

	story_background.show()
	character_layer.show()
	dialogue_panel.show()
	choice_panel.hide()
	end_background.hide()
	end_content.hide()

	jukain_sprite.texture = CHARACTER_TEXTURES["Jukain"]["tired"]
	hiruko_sprite.texture = CHARACTER_TEXTURES["Hiruko"]["neutral"]
	_show_node(start_node_id)


func _advance_dialogue() -> void:
	var current_node: Dictionary = dialogue_nodes.get(current_node_id, {})
	if current_node.get("type", "") != "line":
		_report_runtime_error("Cannot advance from node '%s'." % current_node_id)
		return
	_show_node(current_node["next"])


func _show_node(node_id: String) -> void:
	if not dialogue_nodes.has(node_id):
		_report_runtime_error("Tried to show missing node '%s'." % node_id)
		return

	current_node_id = node_id
	var node: Dictionary = dialogue_nodes[node_id]
	match node["type"]:
		"line":
			_show_line(node)
		"choice":
			_show_choices(node)
		"condition":
			_show_condition(node)
		"end":
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


func _show_choices(choice: Dictionary) -> void:
	var options: Array = choice["options"]
	option_a_button.text = options[0]["text"]
	option_b_button.text = options[1]["text"]
	awaiting_choice = true
	choice_panel.show()
	option_a_button.grab_focus()


func _on_option_selected(option_index: int) -> void:
	if not awaiting_choice:
		return

	var choice: Dictionary = dialogue_nodes.get(current_node_id, {})
	var options: Array = choice.get("options", [])
	if choice.get("type", "") != "choice" or option_index >= options.size():
		_report_runtime_error("Current choice data is invalid at node '%s'." % current_node_id)
		return

	awaiting_choice = false
	choice_panel.hide()
	var selected_option: Dictionary = options[option_index]
	if not _apply_choice_effects(selected_option):
		return
	_show_node(selected_option["target"])


func _apply_choice_effects(option: Dictionary) -> bool:
	for effect: Dictionary in option.get("effects", []):
		match effect["type"]:
			"set_flag":
				GameState.set_flag(effect["flag"], effect["value"])
			"adjust_bond":
				GameState.adjust_bond(effect["bond"], int(effect["amount"]))
			_:
				_report_runtime_error("Unknown effect type '%s'." % effect["type"])
				return false
	return true


func _show_condition(node: Dictionary) -> void:
	var condition: Dictionary = node["condition"]
	if condition["type"] != "flag_equals":
		_report_runtime_error("Unknown condition type '%s'." % condition["type"])
		return

	var condition_matches: bool = GameState.get_flag(condition["flag"]) == condition["value"]
	var target: String = node["true_target"] if condition_matches else node["false_target"]
	_show_node(target)


func _report_runtime_error(message: String) -> void:
	dialogue_ready = false
	_report_dialogue_error(message)
	_show_dialogue_error()


func _finish_scene() -> void:
	scene_ended = true
	awaiting_choice = false
	choice_panel.hide()
	dialogue_panel.hide()
	character_layer.hide()
	story_background.hide()
	end_background.show()
	end_content.show()
	restart_button.grab_focus()


func _restart_scene() -> void:
	GameState.reset_state()
	get_tree().reload_current_scene()
