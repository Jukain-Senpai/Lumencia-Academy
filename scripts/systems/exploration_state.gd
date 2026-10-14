class_name ExplorationState
extends RefCounted

const NO_TIME := "NO_TIME"
const TIME_SLOTS := "TIME_SLOTS"
const MULTI_DAY := "MULTI_DAY"
const DAYPARTS := ["Morning", "Afternoon", "Night"]
const MAX_TIME_COUNTER := 9223372036854775807
const PROTOTYPE_FINAL_DESTINATION := "prototype_story_result"

var active_context_id := ""
var current_node_id := ""
var revealed_nodes: Dictionary = {}
var completed_nodes: Dictionary = {}
var roadblocked_nodes: Dictionary = {}
var leftover_rewards: Dictionary = {}
var time_mode := NO_TIME
var day_number := 1
var daypart_index := 0
var actions_spent_in_daypart := 0
var total_timed_actions := 0
var time_feedback := ""
var day_transition_pending := false
var hub_action_uses: Dictionary = {}

var _context_definitions: Dictionary = {}
var _active_nodes: Dictionary = {}
var _closed_context_ids: Dictionary = {}


func define_context(context_definition: Dictionary) -> bool:
	if not _is_valid_context_definition(context_definition):
		return false
	var context_id: String = context_definition["id"]
	_context_definitions[context_id] = context_definition.duplicate(true)
	return true


func activate_context(context_id: String) -> bool:
	if not _context_definitions.has(context_id) or is_context_closed(context_id):
		return false

	var context: Dictionary = _context_definitions[context_id]
	var nodes: Dictionary = {}
	for raw_node: Variant in context["nodes"]:
		var node_definition: Dictionary = raw_node
		nodes[node_definition["id"]] = node_definition.duplicate(true)

	clear_runtime()
	active_context_id = context_id
	time_mode = context.get("time", {}).get("mode", NO_TIME)
	_active_nodes = nodes
	current_node_id = context["starting_node"]
	for node_id: String in _active_nodes:
		var node_definition: Dictionary = _active_nodes[node_id]
		if node_definition["initially_revealed"]:
			revealed_nodes[node_id] = true
		if node_definition["initial_roadblock"]:
			roadblocked_nodes[node_id] = true
		for raw_action: Variant in node_definition.get("hub_actions", []):
			if raw_action["type"] == "rest":
				if not hub_action_uses.has(node_id):
					hub_action_uses[node_id] = {}
				hub_action_uses[node_id][raw_action["id"]] = raw_action["max_uses"]
	return true


func clear_runtime() -> void:
	active_context_id = ""
	current_node_id = ""
	revealed_nodes.clear()
	completed_nodes.clear()
	roadblocked_nodes.clear()
	leftover_rewards.clear()
	hub_action_uses.clear()
	time_mode = NO_TIME
	day_number = 1
	daypart_index = 0
	actions_spent_in_daypart = 0
	total_timed_actions = 0
	time_feedback = ""
	day_transition_pending = false
	_active_nodes.clear()


func reset_session() -> void:
	clear_runtime()
	_closed_context_ids.clear()


func is_context_closed(context_id: String) -> bool:
	return _closed_context_ids.has(context_id)


func has_final_progression_node() -> bool:
	if not has_active_context():
		return false
	for node_id: String in _active_nodes:
		if _active_nodes[node_id].has("final_progression"):
			return true
	return false


func can_advance_from_current_node(expected_context_id: String, expected_node_id: String) -> bool:
	if (
		expected_context_id.is_empty()
		or expected_node_id.is_empty()
		or active_context_id != expected_context_id
		or current_node_id != expected_node_id
		or is_context_closed(expected_context_id)
		or not has_node(expected_node_id)
		or not is_node_revealed(expected_node_id)
		or is_node_roadblocked(expected_node_id)
	):
		return false
	return _active_nodes[expected_node_id].has("final_progression")


func close_active_context(expected_context_id: String, expected_node_id: String) -> bool:
	if not can_advance_from_current_node(expected_context_id, expected_node_id):
		return false
	_closed_context_ids[expected_context_id] = true
	clear_runtime()
	return true


func get_missable_content_summary() -> Dictionary:
	var summary := {
		"optional_primary_count": 0,
		"leftover_reward_count": 0,
		"optional_roadblock_count": 0,
		"total": 0,
	}
	if not has_active_context():
		return summary
	for node_id: String in _active_nodes:
		var node_definition: Dictionary = _active_nodes[node_id]
		if node_definition.has("final_progression"):
			continue
		var primary_content: Variant = node_definition.get("primary_content")
		if (
			typeof(primary_content) == TYPE_DICTIONARY
			and primary_content.get("optional", false)
			and not is_node_completed(node_id)
		):
			summary["optional_primary_count"] += 1
		if has_leftover_reward(node_id):
			summary["leftover_reward_count"] += 1
		if node_definition.get("optional_missable_roadblock", false) and is_node_roadblocked(node_id):
			summary["optional_roadblock_count"] += 1
	summary["total"] = (
		summary["optional_primary_count"]
		+ summary["leftover_reward_count"]
		+ summary["optional_roadblock_count"]
	)
	return summary


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


func get_time_snapshot() -> Dictionary:
	if not has_active_context():
		return {}
	return {
		"mode": time_mode,
		"day": day_number,
		"daypart": DAYPARTS[daypart_index],
		"actions_spent": actions_spent_in_daypart,
		"total_actions": total_timed_actions,
		"feedback": time_feedback,
		"transition_pending": day_transition_pending,
	}


func can_spend_timed_action() -> bool:
	if not has_active_context():
		return false
	if time_mode == NO_TIME:
		return true
	return not day_transition_pending and total_timed_actions < MAX_TIME_COUNTER and day_number < MAX_TIME_COUNTER


func spend_timed_action() -> Dictionary:
	var result := {"success": false, "charged": false, "day_boundary": false,
		"night_rest_due": false}
	if not can_spend_timed_action():
		return result
	result["success"] = true
	if time_mode == NO_TIME:
		return result
	total_timed_actions += 1
	result["charged"] = true
	actions_spent_in_daypart += 1
	if actions_spent_in_daypart == 2:
		if daypart_index == DAYPARTS.size() - 1:
			day_transition_pending = true
			result["day_boundary"] = true
			result["night_rest_due"] = time_mode == MULTI_DAY
		else:
			actions_spent_in_daypart = 0
			daypart_index += 1
	return result


func finish_day_transition() -> bool:
	if not day_transition_pending or day_number >= MAX_TIME_COUNTER:
		return false
	day_number += 1
	daypart_index = 0
	actions_spent_in_daypart = 0
	day_transition_pending = false
	return true


func get_hub_action_uses_remaining(node_id: String, action_id: String) -> int:
	if not has_node(node_id) or not hub_action_uses.has(node_id):
		return -1
	return hub_action_uses[node_id].get(action_id, -1)


func consume_hub_action_use(node_id: String, action_id: String) -> bool:
	if current_node_id != node_id or get_hub_action_uses_remaining(node_id, action_id) <= 0:
		return false
	hub_action_uses[node_id][action_id] -= 1
	return true


func set_time_feedback(message: String) -> void:
	time_feedback = message


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
	var time_definition: Variant = context_definition.get("time", {"mode": NO_TIME})
	if (
		typeof(time_definition) != TYPE_DICTIONARY
		or time_definition.keys().size() != 1
		or not [NO_TIME, TIME_SLOTS, MULTI_DAY].has(time_definition.get("mode"))
	):
		return false

	var node_definitions: Array = context_definition["nodes"]
	if node_definitions.is_empty():
		return false
	var nodes_by_id: Dictionary = {}
	var final_node_count := 0
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
		if node_definition.has("final_progression"):
			final_node_count += 1
			if final_node_count > 1:
				return false

	var starting_node: String = context_definition["starting_node"]
	if not nodes_by_id.has(starting_node):
		return false
	if not nodes_by_id[starting_node]["initially_revealed"]:
		return false
	for node_id: String in nodes_by_id:
		var node_definition: Dictionary = nodes_by_id[node_id]
		if time_definition["mode"] == NO_TIME:
			for raw_action: Variant in node_definition.get("hub_actions", []):
				if raw_action["type"] == "wait":
					return false
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
	if node_definition.has("primary_content"):
		var primary_content: Variant = node_definition["primary_content"]
		if typeof(primary_content) != TYPE_DICTIONARY:
			return false
		if primary_content.has("action_cost"):
			if typeof(primary_content["action_cost"]) != TYPE_INT or not [0, 1].has(primary_content["action_cost"]):
				return false
		if primary_content.has("optional") and typeof(primary_content["optional"]) != TYPE_BOOL:
			return false
	if node_definition.has("optional_missable_roadblock") and typeof(node_definition["optional_missable_roadblock"]) != TYPE_BOOL:
		return false
	if node_definition.has("final_progression"):
		var final_definition: Variant = node_definition["final_progression"]
		if (
			typeof(final_definition) != TYPE_DICTIONARY
			or final_definition.keys().size() != 1
			or final_definition.get("destination") != PROTOTYPE_FINAL_DESTINATION
			or node_definition.has("primary_content")
			or node_definition.has("hub_actions")
			or node_definition["reusable"]
		):
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
		if not _has_non_empty_string(action, "id") or action_ids.has(action["id"]) or not _has_non_empty_string(action, "display_name"):
			return false
		action_ids[action["id"]] = true
		match action.get("type"):
			"shop":
				if action.keys().size() != 4 or typeof(action.get("catalog")) != TYPE_ARRAY or action["catalog"].is_empty():
					return false
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
			"rest":
				if action.keys().size() != 4 or typeof(action.get("max_uses")) != TYPE_INT or int(action["max_uses"]) <= 0:
					return false
			"wait":
				if action.keys().size() != 3:
					return false
			_:
				return false
	return true


func _has_non_empty_string(data: Dictionary, field: String) -> bool:
	return data.has(field) and typeof(data[field]) == TYPE_STRING and not data[field].is_empty()
