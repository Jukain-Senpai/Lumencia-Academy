class_name ExplorationState
extends RefCounted

const NO_TIME := "NO_TIME"
const TIME_SLOTS := "TIME_SLOTS"
const MULTI_DAY := "MULTI_DAY"
const DAYPARTS := ["Morning", "Afternoon", "Night"]
const MAX_TIME_COUNTER := 9223372036854775807
const MAX_SAFE_SAVE_INTEGER := 9007199254740991
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


func get_save_snapshot() -> Dictionary:
	var leftovers: Array = []
	for node_id: String in leftover_rewards:
		var reward: Dictionary = leftover_rewards[node_id]
		leftovers.append({"node_id": node_id, "item_id": reward["item_id"], "quantity": reward["quantity"]})
	leftovers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["node_id"] < b["node_id"])
	var uses: Array = []
	for node_id: String in hub_action_uses:
		for action_id: String in hub_action_uses[node_id]:
			uses.append({"node_id": node_id, "action_id": action_id,
				"remaining": hub_action_uses[node_id][action_id]})
	uses.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["node_id"] < b["node_id"] or (a["node_id"] == b["node_id"] and a["action_id"] < b["action_id"]))
	return {
		"active_context_id": active_context_id,
		"current_node_id": current_node_id,
		"revealed_nodes": _sorted_keys(revealed_nodes),
		"completed_nodes": _sorted_keys(completed_nodes),
		"roadblocked_nodes": _sorted_keys(roadblocked_nodes),
		"leftover_rewards": leftovers,
		"time": {"mode": time_mode, "day": day_number, "daypart_index": daypart_index,
			"actions_spent": actions_spent_in_daypart, "total_actions": total_timed_actions},
		"hub_action_uses": uses,
		"closed_context_ids": _sorted_keys(_closed_context_ids),
	}


func apply_save_snapshot(snapshot: Dictionary) -> bool:
	if not _has_exact_keys(snapshot, ["active_context_id", "current_node_id", "revealed_nodes",
		"completed_nodes", "roadblocked_nodes", "leftover_rewards", "time",
		"hub_action_uses", "closed_context_ids"]):
		return false
	var context_id: Variant = snapshot["active_context_id"]
	var node_id: Variant = snapshot["current_node_id"]
	if typeof(context_id) != TYPE_STRING or typeof(node_id) != TYPE_STRING:
		return false
	var closed := _validate_saved_node_ids(snapshot["closed_context_ids"], _context_definitions)
	if not closed["valid"] or (not context_id.is_empty() and closed["ids"].has(context_id)):
		return false
	var nodes: Dictionary = {}
	if not context_id.is_empty():
		if not _context_definitions.has(context_id):
			return false
		for raw_node: Dictionary in _context_definitions[context_id]["nodes"]:
			nodes[raw_node["id"]] = raw_node
		if not nodes.has(node_id):
			return false
	elif not node_id.is_empty():
		return false
	var revealed := _validate_saved_node_ids(snapshot["revealed_nodes"], nodes)
	var completed := _validate_saved_node_ids(snapshot["completed_nodes"], nodes)
	var roadblocked := _validate_saved_node_ids(snapshot["roadblocked_nodes"], nodes)
	if not revealed["valid"] or not completed["valid"] or not roadblocked["valid"]:
		return false
	if not context_id.is_empty():
		if not revealed["ids"].has(node_id):
			return false
		for known_id: String in nodes:
			if nodes[known_id]["initially_revealed"] and not revealed["ids"].has(known_id):
				return false
	for completed_id: String in completed["ids"]:
		if not revealed["ids"].has(completed_id):
			return false
	var validated_leftovers := _validate_saved_leftovers(snapshot["leftover_rewards"], nodes, completed["ids"])
	var validated_uses := _validate_saved_hub_uses(snapshot["hub_action_uses"], nodes)
	if not validated_leftovers["valid"] or not validated_uses["valid"]:
		return false
	var saved_time: Variant = snapshot["time"]
	if typeof(saved_time) != TYPE_DICTIONARY or not _has_exact_keys(saved_time,
		["mode", "day", "daypart_index", "actions_spent", "total_actions"]):
		return false
	var expected_mode: String = NO_TIME if context_id.is_empty() else _context_definitions[context_id].get("time", {}).get("mode", NO_TIME)
	if saved_time["mode"] != expected_mode:
		return false
	if (
		not _is_saved_integer(saved_time["day"], 1, MAX_SAFE_SAVE_INTEGER)
		or not _is_saved_integer(saved_time["daypart_index"], 0, 2)
		or not _is_saved_integer(saved_time["actions_spent"], 0, 1)
		or not _is_saved_integer(saved_time["total_actions"], 0, MAX_SAFE_SAVE_INTEGER)
	):
		return false
	var day: int = int(saved_time["day"])
	var part: int = int(saved_time["daypart_index"])
	var spent: int = int(saved_time["actions_spent"])
	var total: int = int(saved_time["total_actions"])
	if expected_mode == NO_TIME:
		if day != 1 or part != 0 or spent != 0 or total != 0:
			return false
	elif day > int((MAX_SAFE_SAVE_INTEGER - part * 2 - spent) / 6) + 1 or total != (day - 1) * 6 + part * 2 + spent:
		return false

	# All validation precedes the first mutation of this state object.
	clear_runtime()
	_closed_context_ids = closed["ids"].duplicate(true)
	if not context_id.is_empty():
		if not activate_context(context_id):
			return false
		current_node_id = node_id
		revealed_nodes = revealed["ids"]
		completed_nodes = completed["ids"]
		roadblocked_nodes = roadblocked["ids"]
		leftover_rewards = validated_leftovers["rewards"]
		hub_action_uses = validated_uses["uses"]
	time_mode = expected_mode
	day_number = day
	daypart_index = part
	actions_spent_in_daypart = spent
	total_timed_actions = total
	return true


func _validate_saved_node_ids(raw_ids: Variant, allowed: Dictionary) -> Dictionary:
	var result := {"valid": false, "ids": {}}
	if typeof(raw_ids) != TYPE_ARRAY:
		return result
	for raw_id: Variant in raw_ids:
		if typeof(raw_id) != TYPE_STRING or not allowed.has(raw_id) or result["ids"].has(raw_id):
			return result
		result["ids"][raw_id] = true
	result["valid"] = true
	return result


func _validate_saved_leftovers(raw_rewards: Variant, nodes: Dictionary, completed: Dictionary) -> Dictionary:
	var result := {"valid": false, "rewards": {}}
	if typeof(raw_rewards) != TYPE_ARRAY:
		return result
	for raw_reward: Variant in raw_rewards:
		if typeof(raw_reward) != TYPE_DICTIONARY or not _has_exact_keys(raw_reward,
			["node_id", "item_id", "quantity"]):
			return result
		var reward_node: Variant = raw_reward["node_id"]
		var item_id: Variant = raw_reward["item_id"]
		if typeof(reward_node) != TYPE_STRING or not nodes.has(reward_node) or result["rewards"].has(reward_node) or not completed.has(reward_node):
			return result
		var primary: Variant = nodes[reward_node].get("primary_content")
		if typeof(primary) != TYPE_DICTIONARY or primary.get("type") != "resource":
			return result
		var authored_reward: Variant = primary.get("reward")
		if typeof(authored_reward) != TYPE_DICTIONARY or authored_reward.get("type") != "item" or item_id != authored_reward.get("item_id"):
			return result
		if not _is_saved_integer(raw_reward["quantity"], 1, int(authored_reward.get("quantity", 0))):
			return result
		result["rewards"][reward_node] = {"item_id": item_id, "quantity": int(raw_reward["quantity"])}
	result["valid"] = true
	return result


func _validate_saved_hub_uses(raw_uses: Variant, nodes: Dictionary) -> Dictionary:
	var result := {"valid": false, "uses": {}}
	if typeof(raw_uses) != TYPE_ARRAY:
		return result
	var expected := 0
	for node_id: String in nodes:
		for raw_action: Variant in nodes[node_id].get("hub_actions", []):
			if raw_action.get("type") == "rest":
				expected += 1
	for raw_use: Variant in raw_uses:
		if typeof(raw_use) != TYPE_DICTIONARY or not _has_exact_keys(raw_use,
			["node_id", "action_id", "remaining"]):
			return result
		var node_id: Variant = raw_use["node_id"]
		var action_id: Variant = raw_use["action_id"]
		if typeof(node_id) != TYPE_STRING or typeof(action_id) != TYPE_STRING or not nodes.has(node_id):
			return result
		if not result["uses"].has(node_id):
			result["uses"][node_id] = {}
		if result["uses"][node_id].has(action_id):
			return result
		var maximum := -1
		for raw_action: Variant in nodes[node_id].get("hub_actions", []):
			if raw_action.get("type") == "rest" and raw_action.get("id") == action_id:
				maximum = raw_action["max_uses"]
				break
		if maximum < 0 or not _is_saved_integer(raw_use["remaining"], 0, maximum):
			return result
		result["uses"][node_id][action_id] = int(raw_use["remaining"])
	if raw_uses.size() != expected:
		return result
	result["valid"] = true
	return result


func _is_saved_integer(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) == TYPE_INT:
		return value >= minimum and value <= maximum
	if typeof(value) != TYPE_FLOAT or is_nan(value) or is_inf(value):
		return false
	return value == floor(value) and value >= float(minimum) and value <= float(maximum)


func _has_exact_keys(data: Dictionary, required: Array[String]) -> bool:
	if data.size() != required.size():
		return false
	for key: String in required:
		if not data.has(key):
			return false
	return true


func _sorted_keys(data: Dictionary) -> Array:
	var keys: Array = data.keys()
	keys.sort()
	return keys


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
