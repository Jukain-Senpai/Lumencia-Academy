class_name ExplorationState
extends RefCounted

var active_context_id := ""
var current_node_id := ""
var revealed_nodes: Dictionary = {}
var completed_nodes: Dictionary = {}
var roadblocked_nodes: Dictionary = {}
var leftover_rewards: Dictionary = {}

var _context_definitions: Dictionary = {}
var _active_nodes: Dictionary = {}


func define_context(context_definition: Dictionary) -> bool:
	if not _is_valid_context_definition(context_definition):
		return false
	var context_id: String = context_definition["id"]
	_context_definitions[context_id] = context_definition.duplicate(true)
	return true


func activate_context(context_id: String) -> bool:
	if not _context_definitions.has(context_id):
		return false

	var context: Dictionary = _context_definitions[context_id]
	var nodes: Dictionary = {}
	for raw_node: Variant in context["nodes"]:
		var node_definition: Dictionary = raw_node
		nodes[node_definition["id"]] = node_definition.duplicate(true)

	clear_runtime()
	active_context_id = context_id
	_active_nodes = nodes
	current_node_id = context["starting_node"]
	for node_id: String in _active_nodes:
		var node_definition: Dictionary = _active_nodes[node_id]
		if node_definition["initially_revealed"]:
			revealed_nodes[node_id] = true
		if node_definition["initial_roadblock"]:
			roadblocked_nodes[node_id] = true
	return true


func clear_runtime() -> void:
	active_context_id = ""
	current_node_id = ""
	revealed_nodes.clear()
	completed_nodes.clear()
	roadblocked_nodes.clear()
	leftover_rewards.clear()
	_active_nodes.clear()


func has_active_context() -> bool:
	return not active_context_id.is_empty()


func get_active_context_definition() -> Dictionary:
	if not has_active_context():
		return {}
	return _context_definitions[active_context_id].duplicate(true)


func get_active_node_definitions() -> Array:
	if not has_active_context():
		return []
	var context_definition: Dictionary = _context_definitions[active_context_id]
	return context_definition["nodes"].duplicate(true)


func get_node_definition(node_id: String) -> Dictionary:
	if not has_node(node_id):
		return {}
	return _active_nodes[node_id].duplicate(true)


func has_node(node_id: String) -> bool:
	return has_active_context() and _active_nodes.has(node_id)


func is_node_revealed(node_id: String) -> bool:
	return has_node(node_id) and revealed_nodes.has(node_id)


func is_node_completed(node_id: String) -> bool:
	return has_node(node_id) and completed_nodes.has(node_id)


func is_node_roadblocked(node_id: String) -> bool:
	return has_node(node_id) and roadblocked_nodes.has(node_id)


func is_node_reusable(node_id: String) -> bool:
	if not has_node(node_id):
		return false
	return _active_nodes[node_id]["reusable"]


func can_travel_to(destination_id: String) -> bool:
	if not has_node(destination_id) or not is_node_revealed(destination_id):
		return false
	var current_node: Dictionary = _active_nodes[current_node_id]
	return destination_id in current_node["connections"]


func move_to_node(destination_id: String) -> bool:
	if not can_travel_to(destination_id):
		return false
	current_node_id = destination_id
	return true


func reveal_node(node_id: String) -> bool:
	if not has_node(node_id):
		return false
	revealed_nodes[node_id] = true
	return true


func complete_primary_content(node_id: String) -> bool:
	if not has_node(node_id):
		return false
	completed_nodes[node_id] = true
	var node_definition: Dictionary = _active_nodes[node_id]
	for revealed_node_id: String in node_definition["reveal_on_complete"]:
		revealed_nodes[revealed_node_id] = true
	return true


func set_node_roadblocked(node_id: String, roadblocked: bool) -> bool:
	if not has_node(node_id):
		return false
	if roadblocked:
		roadblocked_nodes[node_id] = true
	else:
		roadblocked_nodes.erase(node_id)
	return true


func set_leftover_reward(node_id: String, item_id: String, quantity: int) -> bool:
	if not has_node(node_id) or item_id.is_empty() or quantity <= 0:
		return false
	leftover_rewards[node_id] = {
		"item_id": item_id,
		"quantity": quantity,
	}
	return true


func has_leftover_reward(node_id: String) -> bool:
	return has_node(node_id) and leftover_rewards.has(node_id)


func get_leftover_reward(node_id: String) -> Dictionary:
	if not has_leftover_reward(node_id):
		return {}
	return leftover_rewards[node_id].duplicate(true)


func reduce_leftover_reward(node_id: String, quantity: int) -> bool:
	if quantity <= 0 or not has_leftover_reward(node_id):
		return false
	var current: int = leftover_rewards[node_id]["quantity"]
	if quantity > current:
		return false
	var remaining := current - quantity
	if remaining == 0:
		leftover_rewards.erase(node_id)
	else:
		leftover_rewards[node_id]["quantity"] = remaining
	return true


func _is_valid_context_definition(context_definition: Dictionary) -> bool:
	if not _has_non_empty_string(context_definition, "id"):
		return false
	if not _has_non_empty_string(context_definition, "starting_node"):
		return false
	if not context_definition.has("nodes") or typeof(context_definition["nodes"]) != TYPE_ARRAY:
		return false

	var node_definitions: Array = context_definition["nodes"]
	if node_definitions.is_empty():
		return false
	var nodes_by_id: Dictionary = {}
	for raw_node: Variant in node_definitions:
		if typeof(raw_node) != TYPE_DICTIONARY:
			return false
		var node_definition: Dictionary = raw_node
		if not _is_valid_node_shape(node_definition):
			return false
		var node_id: String = node_definition["id"]
		if nodes_by_id.has(node_id):
			return false
		nodes_by_id[node_id] = node_definition

	var starting_node: String = context_definition["starting_node"]
	if not nodes_by_id.has(starting_node):
		return false
	if not nodes_by_id[starting_node]["initially_revealed"]:
		return false
	for node_id: String in nodes_by_id:
		var node_definition: Dictionary = nodes_by_id[node_id]
		for connected_node_id: String in node_definition["connections"]:
			if not nodes_by_id.has(connected_node_id):
				return false
		for revealed_node_id: String in node_definition["reveal_on_complete"]:
			if not nodes_by_id.has(revealed_node_id):
				return false
	return true


func _is_valid_node_shape(node_definition: Dictionary) -> bool:
	if not _has_non_empty_string(node_definition, "id"):
		return false
	for array_field: String in ["connections", "reveal_on_complete"]:
		if not node_definition.has(array_field) or typeof(node_definition[array_field]) != TYPE_ARRAY:
			return false
		for value: Variant in node_definition[array_field]:
			if typeof(value) != TYPE_STRING or value.is_empty():
				return false
	for bool_field: String in ["initially_revealed", "reusable", "initial_roadblock"]:
		if not node_definition.has(bool_field) or typeof(node_definition[bool_field]) != TYPE_BOOL:
			return false
	if node_definition.has("hub_actions"):
		if not node_definition["reusable"] or not _is_valid_hub_actions(node_definition["hub_actions"]):
			return false
	return true


func _is_valid_hub_actions(raw_actions: Variant) -> bool:
	if typeof(raw_actions) != TYPE_ARRAY:
		return false
	var action_ids: Dictionary = {}
	for raw_action: Variant in raw_actions:
		if typeof(raw_action) != TYPE_DICTIONARY:
			return false
		var action: Dictionary = raw_action
		if (
			action.keys().size() != 4
			or not _has_non_empty_string(action, "id")
			or action_ids.has(action["id"])
			or action.get("type") != "shop"
			or not _has_non_empty_string(action, "display_name")
			or typeof(action.get("catalog")) != TYPE_ARRAY
			or action["catalog"].is_empty()
		):
			return false
		action_ids[action["id"]] = true
		var offer_ids: Dictionary = {}
		for raw_offer: Variant in action["catalog"]:
			if typeof(raw_offer) != TYPE_DICTIONARY:
				return false
			var offer: Dictionary = raw_offer
			if (
				offer.keys().size() != 2
				or not _has_non_empty_string(offer, "item_id")
				or offer_ids.has(offer["item_id"])
				or typeof(offer.get("price")) != TYPE_INT
				or int(offer["price"]) <= 0
			):
				return false
			offer_ids[offer["item_id"]] = true
	return true


func _has_non_empty_string(data: Dictionary, field: String) -> bool:
	return data.has(field) and typeof(data[field]) == TYPE_STRING and not data[field].is_empty()
