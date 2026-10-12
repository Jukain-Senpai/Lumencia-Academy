class_name ExplorationMapController
extends Control

const MARKER_SIZE := Vector2(164.0, 64.0)
const GOLD := Color(0.96, 0.76, 0.30, 1.0)
const PALE_GOLD := Color(1.0, 0.90, 0.62, 1.0)
const VIOLET := Color(0.17, 0.10, 0.24, 0.96)
const VIOLET_HOVER := Color(0.25, 0.15, 0.34, 0.98)
const MUTED := Color(0.18, 0.20, 0.22, 0.94)
const UNAVAILABLE := Color(0.10, 0.11, 0.14, 0.88)
const ROADBLOCK_RED := Color(1.0, 0.35, 0.30, 1.0)
const REUSABLE_TEAL := Color(0.48, 0.92, 0.84, 1.0)

@onready var map_frame: Control = %MapFrame
@onready var map_texture: TextureRect = %MapTexture
@onready var marker_layer: Control = %MarkerLayer
@onready var context_title: Label = %ContextTitle
@onready var current_location_label: Label = %CurrentLocationLabel
@onready var diagnostic_panel: PanelContainer = %DiagnosticPanel
@onready var diagnostic_label: Label = %DiagnosticLabel

var marker_buttons: Dictionary = {}
var rendered_map_rect := Rect2()
var exploration_state: RefCounted


func _ready() -> void:
	exploration_state = GameState.exploration_state
	resized.connect(_on_resized)
	call_deferred("refresh_map")


func refresh_map() -> bool:
	if exploration_state == null:
		return _show_diagnostic("Exploration state is unavailable.")
	if map_texture.texture == null:
		return _show_diagnostic("Exploration map background is missing.")
	if not exploration_state.has_active_context():
		return _show_diagnostic("No active Exploration context.")

	var context_definition: Dictionary = exploration_state.get_active_context_definition()
	var node_definitions: Array = exploration_state.get_active_node_definitions()
	var validation_error := _get_presentation_validation_error(context_definition, node_definitions)
	if not validation_error.is_empty():
		return _show_diagnostic(validation_error)
	if not _update_marker_layer_rect():
		return _show_diagnostic("Exploration map has no drawable area.")

	context_title.text = context_definition["display_name"]
	var current_definition: Dictionary = exploration_state.get_node_definition(exploration_state.current_node_id)
	current_location_label.text = "Current: %s" % current_definition["display_name"]
	_sync_marker_controls(node_definitions)
	_update_marker_positions(node_definitions)
	marker_layer.visible = true
	diagnostic_panel.visible = false
	return true


func get_marker_button(node_id: String) -> Button:
	return marker_buttons.get(node_id) as Button


func _on_resized() -> void:
	if is_node_ready():
		call_deferred("refresh_map")


func _on_marker_pressed(node_id: String) -> void:
	if not exploration_state.has_active_context():
		refresh_map()
		return
	if not exploration_state.has_node(node_id):
		_show_diagnostic("Map marker references unknown node '%s'." % node_id)
		return
	exploration_state.move_to_node(node_id)
	refresh_map()


func _sync_marker_controls(node_definitions: Array) -> void:
	var visible_node_definitions: Dictionary = {}
	for raw_definition: Variant in node_definitions:
		var node_definition: Dictionary = raw_definition
		var node_id: String = node_definition["id"]
		if exploration_state.is_node_revealed(node_id):
			visible_node_definitions[node_id] = node_definition

	for raw_existing_id: Variant in marker_buttons.keys():
		var existing_id: String = raw_existing_id
		if visible_node_definitions.has(existing_id):
			continue
		var old_button: Button = marker_buttons[existing_id]
		old_button.visible = false
		old_button.disabled = true
		marker_buttons.erase(existing_id)
		old_button.queue_free()

	for raw_node_id: Variant in visible_node_definitions:
		var node_id: String = raw_node_id
		var node_definition: Dictionary = visible_node_definitions[node_id]
		if not marker_buttons.has(node_id):
			marker_buttons[node_id] = _create_marker_button(node_id, node_definition["display_name"])
		_update_marker_visuals(node_id, node_definition)


func _create_marker_button(node_id: String, display_name: String) -> Button:
	var button := Button.new()
	button.name = "Marker_%s" % node_id
	button.text = display_name
	button.custom_minimum_size = MARKER_SIZE
	button.size = MARKER_SIZE
	button.clip_text = true
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.set_meta("node_id", node_id)
	button.pressed.connect(_on_marker_pressed.bind(node_id))
	marker_layer.add_child(button)

	_add_indicator(button, "CompletedBadge", "✓", HORIZONTAL_ALIGNMENT_LEFT, Color(0.72, 0.90, 0.72, 1.0))
	_add_indicator(button, "RoadblockBadge", "!", HORIZONTAL_ALIGNMENT_RIGHT, ROADBLOCK_RED)
	_add_indicator(button, "ReusableBadge", "↻", HORIZONTAL_ALIGNMENT_RIGHT, REUSABLE_TEAL, true)
	var current_tag := _add_indicator(button, "CurrentTag", "CURRENT", HORIZONTAL_ALIGNMENT_CENTER, PALE_GOLD, true)
	current_tag.offset_right = -22.0
	return button


func _add_indicator(
	button: Button,
	indicator_name: String,
	indicator_text: String,
	alignment: HorizontalAlignment,
	color: Color,
	bottom: bool = false
) -> Label:
	var label := Label.new()
	label.name = indicator_name
	label.text = indicator_text
	label.horizontal_alignment = alignment
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.04, 0.025, 0.06, 1.0))
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_font_size_override("font_size", 13 if indicator_name == "CurrentTag" else 18)
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE if bottom else Control.PRESET_TOP_WIDE)
	if bottom:
		label.offset_top = -22.0
	else:
		label.offset_bottom = 24.0
	label.visible = false
	button.add_child(label)
	return label


func _update_marker_visuals(node_id: String, node_definition: Dictionary) -> void:
	var button: Button = marker_buttons[node_id]
	var is_current: bool = exploration_state.current_node_id == node_id
	var is_completed: bool = exploration_state.is_node_completed(node_id)
	var is_roadblocked: bool = exploration_state.is_node_roadblocked(node_id)
	var is_reusable: bool = exploration_state.is_node_reusable(node_id)
	var is_reachable: bool = not is_current and exploration_state.can_travel_to(node_id)

	button.text = node_definition["display_name"]
	button.disabled = not is_reachable
	button.focus_mode = Control.FOCUS_ALL if is_reachable else Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if is_reachable else Control.CURSOR_ARROW
	button.set_meta("map_position", node_definition["map_position"])
	button.set_meta("is_current", is_current)
	button.set_meta("is_completed", is_completed)
	button.set_meta("is_roadblocked", is_roadblocked)
	button.set_meta("is_reusable", is_reusable)
	button.set_meta("is_reachable", is_reachable)

	button.get_node("CompletedBadge").visible = is_completed
	button.get_node("CurrentTag").visible = is_current
	button.get_node("RoadblockBadge").visible = is_roadblocked
	button.get_node("ReusableBadge").visible = is_reusable

	var background := MUTED if is_completed else (VIOLET if is_reachable or is_current else UNAVAILABLE)
	var border := GOLD if is_current else (Color(0.76, 0.62, 0.32, 0.95) if is_reachable else Color(0.42, 0.43, 0.46, 0.85))
	var border_width := 4 if is_current else 2
	var normal_style := _make_marker_style(background, border, border_width)
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("disabled", normal_style)
	button.add_theme_stylebox_override("hover", _make_marker_style(VIOLET_HOVER, GOLD, 3))
	button.add_theme_stylebox_override("pressed", _make_marker_style(Color(0.32, 0.20, 0.40, 1.0), PALE_GOLD, 3))
	button.add_theme_stylebox_override("focus", _make_marker_style(Color(0.0, 0.0, 0.0, 0.0), PALE_GOLD, 3))
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", PALE_GOLD)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", PALE_GOLD if is_current else Color(0.72, 0.72, 0.74, 1.0))
	button.add_theme_font_size_override("font_size", 17)

	var tooltip_parts: Array[String] = [node_definition["display_name"]]
	if is_current:
		tooltip_parts.append("Current location")
	elif is_reachable:
		tooltip_parts.append("Available destination")
	else:
		tooltip_parts.append("Not reachable from here")
	if is_completed:
		tooltip_parts.append("Completed")
	if is_roadblocked:
		tooltip_parts.append("Roadblock present")
	if is_reusable:
		tooltip_parts.append("Reusable location")
	button.tooltip_text = " • ".join(tooltip_parts)


func _update_marker_positions(node_definitions: Array) -> void:
	for raw_definition: Variant in node_definitions:
		var node_definition: Dictionary = raw_definition
		var node_id: String = node_definition["id"]
		if not marker_buttons.has(node_id):
			continue
		var button: Button = marker_buttons[node_id]
		var normalized_position: Vector2 = node_definition["map_position"]
		button.size = MARKER_SIZE
		button.position = normalized_position * marker_layer.size - MARKER_SIZE * 0.5


func _update_marker_layer_rect() -> bool:
	var available_size := map_texture.size
	var texture_size := Vector2(map_texture.texture.get_size())
	if available_size.x <= 0.0 or available_size.y <= 0.0 or texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return false
	var image_scale: float = minf(available_size.x / texture_size.x, available_size.y / texture_size.y)
	var rendered_size: Vector2 = texture_size * image_scale
	var rendered_offset: Vector2 = (available_size - rendered_size) * 0.5
	rendered_map_rect = Rect2(map_texture.position + rendered_offset, rendered_size)
	marker_layer.position = rendered_map_rect.position
	marker_layer.size = rendered_map_rect.size
	return true


func _get_presentation_validation_error(context_definition: Dictionary, node_definitions: Array) -> String:
	if typeof(context_definition.get("display_name")) != TYPE_STRING or context_definition["display_name"].is_empty():
		return "Active Exploration context has no display name."
	if node_definitions.is_empty():
		return "Active Exploration context has no map nodes."
	for raw_definition: Variant in node_definitions:
		if typeof(raw_definition) != TYPE_DICTIONARY:
			return "Exploration map contains malformed node data."
		var node_definition: Dictionary = raw_definition
		var node_id: Variant = node_definition.get("id")
		if typeof(node_id) != TYPE_STRING or node_id.is_empty() or not exploration_state.has_node(node_id):
			return "Exploration map contains an unknown node."
		if typeof(node_definition.get("display_name")) != TYPE_STRING or node_definition["display_name"].is_empty():
			return "Exploration node '%s' has no display name." % node_id
		if typeof(node_definition.get("map_position")) != TYPE_VECTOR2:
			return "Exploration node '%s' has no normalized map position." % node_id
		var map_position: Vector2 = node_definition["map_position"]
		if (
			is_nan(map_position.x)
			or is_inf(map_position.x)
			or is_nan(map_position.y)
			or is_inf(map_position.y)
			or map_position.x < 0.0
			or map_position.x > 1.0
			or map_position.y < 0.0
			or map_position.y > 1.0
		):
			return "Exploration node '%s' has an invalid normalized map position." % node_id
	return ""


func _show_diagnostic(message: String) -> bool:
	marker_layer.visible = false
	diagnostic_label.text = message
	diagnostic_panel.visible = true
	return false


func _make_marker_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(18)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 16.0
	style.shadow_color = Color(0.02, 0.015, 0.03, 0.72)
	style.shadow_size = 7
	return style
