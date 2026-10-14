class_name InventoryState
extends RefCounted

const ItemCatalogModel := preload("res://scripts/systems/item_catalog.gd")
const STACK_CAP := 10

var _definitions: Dictionary = {}
var _quantities: Dictionary = {}


func _init(definitions: Dictionary = {}) -> void:
	_definitions = (
		ItemCatalogModel.get_all_definitions()
		if definitions.is_empty()
		else definitions.duplicate(true)
	)


func clear() -> void:
	_quantities.clear()


func has_definition(item_id: String) -> bool:
	return _is_valid_definition(_definitions.get(item_id, {}), item_id)


func get_item_definition(item_id: String) -> Dictionary:
	if not has_definition(item_id):
		return {}
	return _definitions[item_id].duplicate(true)


func get_quantity(item_id: String) -> int:
	if not has_definition(item_id):
		return 0
	return int(_quantities.get(item_id, 0))


func get_quantities() -> Dictionary:
	return _quantities.duplicate(true)


func get_save_snapshot() -> Array:
	var entries: Array = []
	for item_id: String in _quantities:
		entries.append({"item_id": item_id, "quantity": _quantities[item_id]})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["item_id"] < b["item_id"])
	return entries


func apply_save_snapshot(raw_entries: Variant) -> bool:
	if typeof(raw_entries) != TYPE_ARRAY:
		return false
	var quantities: Dictionary = {}
	for raw_entry: Variant in raw_entries:
		if typeof(raw_entry) != TYPE_DICTIONARY or raw_entry.size() != 2 or not raw_entry.has("item_id") or not raw_entry.has("quantity"):
			return false
		var item_id: Variant = raw_entry["item_id"]
		var quantity: Variant = raw_entry["quantity"]
		if typeof(item_id) != TYPE_STRING or not has_definition(item_id) or quantities.has(item_id):
			return false
		if not _is_save_quantity(quantity):
			return false
		if int(quantity) > 0:
			quantities[item_id] = int(quantity)
		else:
			quantities[item_id] = 0
	_quantities.clear()
	for item_id: String in quantities:
		if quantities[item_id] > 0:
			_quantities[item_id] = quantities[item_id]
	return true


func _is_save_quantity(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return value >= 0 and value <= STACK_CAP
	if typeof(value) != TYPE_FLOAT or is_nan(value) or is_inf(value):
		return false
	return value == floor(value) and value >= 0.0 and value <= float(STACK_CAP)


func gain_item(item_id: String, requested_quantity: int) -> Dictionary:
	var result := {
		"requested": requested_quantity,
		"accepted": 0,
		"remaining": maxi(0, requested_quantity),
	}
	if requested_quantity <= 0 or not has_definition(item_id):
		return result
	var current := get_quantity(item_id)
	var accepted := mini(requested_quantity, STACK_CAP - current)
	if accepted > 0:
		_quantities[item_id] = current + accepted
	result["accepted"] = accepted
	result["remaining"] = requested_quantity - accepted
	return result


func consume_item(item_id: String, quantity: int) -> bool:
	if quantity <= 0 or not has_definition(item_id):
		return false
	var current := get_quantity(item_id)
	if current < quantity:
		return false
	var next_quantity := current - quantity
	if next_quantity == 0:
		_quantities.erase(item_id)
	else:
		_quantities[item_id] = next_quantity
	return true


func can_use_in_context(item_id: String, use_context: String) -> bool:
	var definition := get_item_definition(item_id)
	if definition.is_empty() or get_quantity(item_id) <= 0:
		return false
	var authored_context: String = definition["use_context"]
	return (
		authored_context == ItemCatalogModel.BOTH
		or authored_context == use_context
	)


func _is_valid_definition(raw_definition: Variant, expected_id: String) -> bool:
	if typeof(raw_definition) != TYPE_DICTIONARY:
		return false
	var definition: Dictionary = raw_definition
	if (
		definition.get("id") != expected_id
		or typeof(definition.get("display_name")) != TYPE_STRING
		or String(definition.get("display_name")).is_empty()
		or definition.get("use_context") not in [
			ItemCatalogModel.BATTLE_ONLY,
			ItemCatalogModel.EXPLORATION_ONLY,
			ItemCatalogModel.BOTH,
		]
	):
		return false
	var effect: Variant = definition.get("effect")
	return (
		typeof(effect) == TYPE_DICTIONARY
		and effect.get("type") == "heal"
		and typeof(effect.get("amount")) == TYPE_INT
		and int(effect.get("amount")) > 0
	)
