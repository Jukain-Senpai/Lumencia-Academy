extends Node

const SAVE_PATH := "user://lumencia_save.json"
const ExplorationStateModel := preload("res://scripts/systems/exploration_state.gd")
const InventoryStateModel := preload("res://scripts/systems/inventory_state.gd")
const PartyRuntimeStateModel := preload("res://scripts/systems/party_runtime_state.gd")
const ItemCatalogModel := preload("res://scripts/systems/item_catalog.gd")
const EXPLORATION_CONTENT_TYPES := ["vn_event", "battle", "resource"]
const MAX_MONEY := 9223372036854775807
const PROGRESSION_RESULT_SCENE_PATH := "res://scenes/exploration/m7_7_progression_result.tscn"
const PROGRESSION_SOURCE_SCENE_PATHS := [
	"res://scenes/exploration/m7_7_progression_prototype.tscn",
	"res://scenes/exploration/exploration_map.tscn",
]

var flags: Dictionary = {}
var bonds: Dictionary = {}
var pending_battle_context: Dictionary = {}
var pending_battle_result: Dictionary = {}
var pending_vn_sequence := ""
var pending_exploration_content: Dictionary = {}
var persistence_error := ""
var exploration_state := ExplorationStateModel.new()
var inventory_state := InventoryStateModel.new()
var party_runtime_state := PartyRuntimeStateModel.new()
var _money := 0
var _missable_content_warning_enabled := true


func set_flag(flag_name: String, value: bool) -> void:
	if flag_name.is_empty():
		push_error("GameState cannot set a flag with an empty name.")
		return
	flags[flag_name] = value


func get_flag(flag_name: String) -> bool:
	return flags.get(flag_name, false)


func adjust_bond(bond_name: String, amount: int) -> void:
	if bond_name.is_empty():
		push_error("GameState cannot adjust a Bond with an empty name.")
		return
	bonds[bond_name] = get_bond(bond_name) + amount


func get_bond(bond_name: String) -> int:
	return bonds.get(bond_name, 0)


func reset_state() -> void:
	flags.clear()
	bonds.clear()
	pending_battle_context.clear()
	pending_battle_result.clear()
	pending_vn_sequence = ""
	pending_exploration_content.clear()
	exploration_state.reset_session()
	inventory_state.clear()
	party_runtime_state.reset()
	_money = 0
	_missable_content_warning_enabled = true


func is_missable_content_warning_enabled() -> bool:
	return _missable_content_warning_enabled


func set_missable_content_warning_enabled(enabled: Variant) -> bool:
	if typeof(enabled) != TYPE_BOOL:
		return false
	_missable_content_warning_enabled = enabled
	return true


func advance_story_from_exploration(expected_context_id: String, expected_node_id: String) -> Dictionary:
	var result := {"success": false, "message": "Story progression is unavailable."}
	if not exploration_state.can_advance_from_current_node(expected_context_id, expected_node_id):
		return result
	if (
		not pending_battle_context.is_empty()
		or not pending_battle_result.is_empty()
		or not pending_vn_sequence.is_empty()
		or not pending_exploration_content.is_empty()
	):
		result["message"] = "Another story interaction is still pending."
		return result
	var final_definition: Dictionary = exploration_state.get_node_definition(expected_node_id).get("final_progression", {})
	if final_definition.get("destination") != ExplorationStateModel.PROTOTYPE_FINAL_DESTINATION:
		result["message"] = "Story destination is unsupported."
		return result
	if not ResourceLoader.exists(PROGRESSION_RESULT_SCENE_PATH):
		result["message"] = "Story destination scene is missing."
		return result
	var destination_resource: Resource = load(PROGRESSION_RESULT_SCENE_PATH)
	if not destination_resource is PackedScene or not destination_resource.can_instantiate():
		result["message"] = "Story destination scene cannot be instantiated."
		return result
	var scene_tree: SceneTree = get_tree()
	var source_scene: Node = scene_tree.current_scene
	if (
		source_scene == null
		or not source_scene.is_inside_tree()
		or not PROGRESSION_SOURCE_SCENE_PATHS.has(source_scene.scene_file_path)
	):
		result["message"] = "Current exploration scene is unavailable."
		return result
	var destination_scene: Node = destination_resource.instantiate()
	if destination_scene == null:
		result["message"] = "Story destination could not be prepared."
		return result
	if destination_scene is CanvasItem:
		destination_scene.visible = false
	scene_tree.root.add_child(destination_scene)
	if not destination_scene.is_inside_tree():
		destination_scene.free()
		result["message"] = "Story destination could not enter the scene tree."
		return result
	if not exploration_state.close_active_context(expected_context_id, expected_node_id):
		destination_scene.queue_free()
		result["message"] = "Exploration context could not close."
		return result
	scene_tree.current_scene = destination_scene
	if destination_scene is CanvasItem:
		destination_scene.visible = true
	source_scene.queue_free()
	result["success"] = true
	result["message"] = "Exploration complete."
	return result


func get_money() -> int:
	return _money


func gain_money(amount: int) -> bool:
	if amount <= 0 or amount > MAX_MONEY - _money:
		return false
	_money += amount
	return true


func spend_money(amount: int) -> bool:
	if amount <= 0 or amount > _money:
		return false
	_money -= amount
	return true


func buy_from_current_shop(expected_node_id: String, action_id: String, item_id: String) -> Dictionary:
	var result := {"success": false, "message": "Shop unavailable.", "money": _money,
		"quantity": inventory_state.get_quantity(item_id)}
	if (
		expected_node_id.is_empty()
		or action_id.is_empty()
		or item_id.is_empty()
		or not exploration_state.has_active_context()
		or exploration_state.current_node_id != expected_node_id
		or not exploration_state.has_node(expected_node_id)
	):
		return result
	var node_definition: Dictionary = exploration_state.get_node_definition(expected_node_id)
	if not node_definition.get("reusable", false):
		return result
	var raw_actions: Variant = node_definition.get("hub_actions")
	if typeof(raw_actions) != TYPE_ARRAY:
		return result
	var offer: Dictionary = {}
	for raw_action: Variant in raw_actions:
		if typeof(raw_action) != TYPE_DICTIONARY:
			return result
		var action: Dictionary = raw_action
		if action.get("id") != action_id:
			continue
		if action.get("type") != "shop" or typeof(action.get("catalog")) != TYPE_ARRAY:
			return result
		for raw_offer: Variant in action["catalog"]:
			if typeof(raw_offer) != TYPE_DICTIONARY:
				return result
			if raw_offer.get("item_id") == item_id:
				offer = raw_offer
				break
		break
	if offer.is_empty():
		return result
	var price: Variant = offer.get("price")
	if typeof(price) != TYPE_INT or price <= 0:
		result["message"] = "Shop price is invalid."
		return result
	if inventory_state.get_item_definition(item_id).is_empty():
		result["message"] = "Shop item is unknown."
		return result
	if inventory_state.get_quantity(item_id) >= InventoryStateModel.STACK_CAP:
		result["message"] = "Inventory full."
		return result
	if _money < price:
		result["message"] = "Not enough money."
		return result
	if not spend_money(price):
		return result
	var gain_result: Dictionary = inventory_state.gain_item(item_id, 1)
	if gain_result.get("accepted") != 1:
		gain_money(price)
		result["message"] = "Purchase could not complete."
		return result
	result["success"] = true
	result["message"] = "Purchased %s." % inventory_state.get_item_definition(item_id)["display_name"]
	result["money"] = _money
	result["quantity"] = inventory_state.get_quantity(item_id)
	return result


func use_current_camp_rest(expected_node_id: String, action_id: String) -> Dictionary:
	var result := {"success": false, "message": "Camp Rest unavailable.",
		"uses_remaining": exploration_state.get_hub_action_uses_remaining(expected_node_id, action_id),
		"hp_restored": 0, "members_revived": 0, "time_result": {}}
	var action := _get_current_hub_action(expected_node_id, action_id, "rest")
	if action.is_empty() or not exploration_state.can_spend_timed_action():
		return result
	if result["uses_remaining"] <= 0:
		result["message"] = "No Camp Rest uses remain."
		return result
	var hp_before: Dictionary = party_runtime_state.get_hp_snapshot()
	var recovery: Dictionary = party_runtime_state.recover_party_percent(50)
	if not recovery["success"]:
		result["message"] = "Camp Rest recovery failed."
		return result
	if not exploration_state.consume_hub_action_use(expected_node_id, action_id):
		party_runtime_state.apply_hp_snapshot(hp_before)
		return result
	var time_result := _charge_exploration_action()
	result["success"] = true
	result["message"] = "Camp Rest: party recovered HP."
	result["uses_remaining"] = exploration_state.get_hub_action_uses_remaining(expected_node_id, action_id)
	result["hp_restored"] = recovery["hp_restored"]
	result["members_revived"] = recovery["members_revived"]
	result["time_result"] = time_result
	return result


func wait_at_current_hub(expected_node_id: String, action_id: String) -> Dictionary:
	var result := {"success": false, "message": "Wait unavailable.", "time_result": {}}
	if (
		_get_current_hub_action(expected_node_id, action_id, "wait").is_empty()
		or exploration_state.time_mode == ExplorationStateModel.NO_TIME
		or not exploration_state.can_spend_timed_action()
	):
		return result
	var time_result := _charge_exploration_action()
	result["success"] = time_result["success"]
	result["message"] = "One action passed." if result["success"] else "Wait could not advance time."
	result["time_result"] = time_result
	return result


func _get_current_hub_action(expected_node_id: String, action_id: String, action_type: String) -> Dictionary:
	if (
		expected_node_id.is_empty()
		or action_id.is_empty()
		or not exploration_state.has_active_context()
		or exploration_state.current_node_id != expected_node_id
		or not exploration_state.has_node(expected_node_id)
	):
		return {}
	var node_definition: Dictionary = exploration_state.get_node_definition(expected_node_id)
	if not node_definition.get("reusable", false):
		return {}
	for raw_action: Variant in node_definition.get("hub_actions", []):
		if raw_action.get("id") == action_id and raw_action.get("type") == action_type:
			return raw_action
	return {}


func _charge_exploration_action() -> Dictionary:
	var time_result: Dictionary = exploration_state.spend_timed_action()
	if not time_result["success"]:
		return time_result
	if time_result["night_rest_due"]:
		var recovery: Dictionary = party_runtime_state.recover_party_percent(20)
		if not recovery["success"]:
			push_error("Night Rest could not recover PartyRuntimeState.")
		else:
			time_result["night_recovery"] = recovery
	if time_result["day_boundary"]:
		if not exploration_state.finish_day_transition():
			push_error("Exploration day transition could not finish.")
			time_result["success"] = false
			return time_result
		if time_result["night_rest_due"]:
			exploration_state.set_time_feedback("Night Rest: The party recovered HP.")
		else:
			exploration_state.set_time_feedback("Day %d — Morning" % exploration_state.day_number)
	elif time_result["charged"]:
		exploration_state.set_time_feedback("")
	return time_result


func use_item_in_exploration(item_id: String, member_id: String) -> Dictionary:
	var result := {
		"success": false,
		"healed": 0,
		"current_hp": 0,
		"max_hp": 0,
	}
	if not inventory_state.can_use_in_context(item_id, ItemCatalogModel.EXPLORATION_ONLY):
		return result
	var definition: Dictionary = inventory_state.get_item_definition(item_id)
	var effect: Dictionary = definition.get("effect", {})
	var member: Dictionary = party_runtime_state.get_member(member_id)
	if effect.get("type") != "heal" or member.is_empty() or member["current_hp"] <= 0:
		return result
	if not inventory_state.consume_item(item_id, 1):
		return result
	var heal_result: Dictionary = party_runtime_state.heal_member(member_id, effect["amount"])
	if not heal_result["success"]:
		inventory_state.gain_item(item_id, 1)
		return result
	return heal_result


func prepare_battle_context(encounter_id: String, return_sequence: String) -> bool:
	if encounter_id.is_empty() or return_sequence.is_empty() or not pending_battle_context.is_empty():
		return false
	pending_battle_result.clear()
	pending_battle_context = {
		"encounter_id": encounter_id,
		"return_sequence": return_sequence,
	}
	return true


func get_pending_battle_context() -> Dictionary:
	return pending_battle_context.duplicate(true)


func clear_pending_battle_context() -> void:
	pending_battle_context.clear()


func set_pending_battle_result(result: Dictionary) -> void:
	pending_battle_result = result.duplicate(true)


func get_pending_battle_result() -> Dictionary:
	return pending_battle_result.duplicate(true)


func clear_pending_battle_result() -> void:
	pending_battle_result.clear()


func prepare_pending_vn_sequence(sequence_id: String) -> bool:
	if sequence_id.is_empty() or not pending_vn_sequence.is_empty():
		return false
	pending_vn_sequence = sequence_id
	return true


func get_pending_vn_sequence() -> String:
	return pending_vn_sequence


func clear_pending_vn_sequence() -> void:
	pending_vn_sequence = ""


func prepare_exploration_content(content_type: String, content_id: String) -> bool:
	if (
		content_type.is_empty()
		or not EXPLORATION_CONTENT_TYPES.has(content_type)
		or content_id.is_empty()
		or not pending_exploration_content.is_empty()
		or not exploration_state.has_active_context()
	):
		return false
	var node_id: String = exploration_state.current_node_id
	var node_definition: Dictionary = exploration_state.get_node_definition(node_id)
	var primary_content: Variant = node_definition.get("primary_content")
	if typeof(primary_content) != TYPE_DICTIONARY:
		return false
	if (
		primary_content.get("type") != content_type
		or primary_content.get("id") != content_id
		or exploration_state.is_node_completed(node_id)
	):
		return false
	pending_exploration_content = {
		"context_id": exploration_state.active_context_id,
		"node_id": node_id,
		"content_type": content_type,
		"content_id": content_id,
	}
	return true


func get_pending_exploration_content() -> Dictionary:
	return pending_exploration_content.duplicate(true)


func validate_pending_exploration_content(
	expected_type := "",
	expected_content_id := ""
) -> bool:
	for field: String in ["context_id", "node_id", "content_type", "content_id"]:
		if (
			not pending_exploration_content.has(field)
			or typeof(pending_exploration_content[field]) != TYPE_STRING
			or String(pending_exploration_content[field]).is_empty()
		):
			return false
	if pending_exploration_content.keys().size() != 4:
		return false
	if (
		pending_exploration_content["context_id"] != exploration_state.active_context_id
		or pending_exploration_content["node_id"] != exploration_state.current_node_id
		or not exploration_state.has_node(pending_exploration_content["node_id"])
	):
		return false
	if not expected_type.is_empty() and pending_exploration_content["content_type"] != expected_type:
		return false
	if (
		not expected_content_id.is_empty()
		and pending_exploration_content["content_id"] != expected_content_id
	):
		return false
	var node_definition: Dictionary = exploration_state.get_node_definition(
		pending_exploration_content["node_id"]
	)
	var primary_content: Variant = node_definition.get("primary_content")
	return (
		typeof(primary_content) == TYPE_DICTIONARY
		and primary_content.get("type") == pending_exploration_content["content_type"]
		and primary_content.get("id") == pending_exploration_content["content_id"]
	)


func resolve_pending_exploration_content(
	expected_type: String,
	expected_content_id: String
) -> bool:
	if not validate_pending_exploration_content(expected_type, expected_content_id):
		return false
	var node_id: String = pending_exploration_content["node_id"]
	if exploration_state.is_node_completed(node_id):
		return true
	var node_definition: Dictionary = exploration_state.get_node_definition(node_id)
	var action_cost: int = node_definition["primary_content"].get("action_cost", 1)
	if action_cost > 0 and not exploration_state.can_spend_timed_action():
		return false
	if not exploration_state.complete_primary_content(node_id):
		return false
	if action_cost == 0:
		return true
	return _charge_exploration_action()["success"]


func clear_pending_exploration_content() -> void:
	pending_exploration_content.clear()


func has_save_file() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game(sequence_path: String, node_id: String) -> bool:
	persistence_error = ""
	if sequence_path.is_empty() or node_id.is_empty():
		return _report_persistence_error("Cannot save without a dialogue sequence and node.")

	var save_data := {
		"sequence": sequence_path,
		"node": node_id,
		"flags": flags.duplicate(true),
		"bonds": bonds.duplicate(true),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return _report_persistence_error(
			"Could not open %s for writing: %s" % [SAVE_PATH, error_string(FileAccess.get_open_error())]
		)
	file.store_string(JSON.stringify(save_data, "\t"))
	file.flush()
	if file.get_error() != OK:
		return _report_persistence_error(
			"Could not finish writing %s: %s" % [SAVE_PATH, error_string(file.get_error())]
		)
	return true


func read_save_data() -> Dictionary:
	persistence_error = ""
	if not has_save_file():
		persistence_error = "No save file exists."
		push_warning("Save load failed: %s" % persistence_error)
		return {}

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		_report_persistence_error(
			"Could not open %s for reading: %s" % [SAVE_PATH, error_string(FileAccess.get_open_error())]
		)
		return {}

	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	if parse_error != OK:
		_report_persistence_error(
			"Malformed save JSON at line %d: %s"
			% [json.get_error_line(), json.get_error_message()]
		)
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		_report_persistence_error("Save data root must be an object.")
		return {}

	return _normalize_save_data(json.data)


func restore_from_save_data(save_data: Dictionary) -> void:
	flags = save_data["flags"].duplicate(true)
	bonds = save_data["bonds"].duplicate(true)


func _normalize_save_data(save_data: Dictionary) -> Dictionary:
	for field in ["sequence", "node", "flags", "bonds"]:
		if not save_data.has(field):
			_report_persistence_error("Save data is missing required field '%s'." % field)
			return {}
	if typeof(save_data["sequence"]) != TYPE_STRING or save_data["sequence"].is_empty():
		_report_persistence_error("Save field 'sequence' must be a non-empty string.")
		return {}
	if typeof(save_data["node"]) != TYPE_STRING or save_data["node"].is_empty():
		_report_persistence_error("Save field 'node' must be a non-empty string.")
		return {}
	if typeof(save_data["flags"]) != TYPE_DICTIONARY:
		_report_persistence_error("Save field 'flags' must be an object.")
		return {}
	if typeof(save_data["bonds"]) != TYPE_DICTIONARY:
		_report_persistence_error("Save field 'bonds' must be an object.")
		return {}

	var normalized_flags: Dictionary = {}
	for flag_name: Variant in save_data["flags"]:
		if typeof(flag_name) != TYPE_STRING or typeof(save_data["flags"][flag_name]) != TYPE_BOOL:
			_report_persistence_error("Every saved flag must have a string name and boolean value.")
			return {}
		normalized_flags[flag_name] = save_data["flags"][flag_name]

	var normalized_bonds: Dictionary = {}
	for bond_name: Variant in save_data["bonds"]:
		var amount: Variant = save_data["bonds"][bond_name]
		if typeof(bond_name) != TYPE_STRING or not _is_integer_value(amount):
			_report_persistence_error("Every saved Bond must have a string name and integer value.")
			return {}
		normalized_bonds[bond_name] = int(amount)

	return {
		"sequence": save_data["sequence"],
		"node": save_data["node"],
		"flags": normalized_flags,
		"bonds": normalized_bonds,
	}


func _is_integer_value(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and value == floor(value)


func _report_persistence_error(message: String) -> bool:
	persistence_error = message
	push_error("Save data error: %s" % message)
	return false
