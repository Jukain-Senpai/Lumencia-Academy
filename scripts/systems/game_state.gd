extends Node

const SAVE_PATH := "user://lumencia_save.json"

var flags: Dictionary = {}
var bonds: Dictionary = {}
var pending_battle_context: Dictionary = {}
var persistence_error := ""


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


func prepare_battle_context(encounter_id: String, return_sequence: String) -> bool:
	if encounter_id.is_empty() or return_sequence.is_empty() or not pending_battle_context.is_empty():
		return false
	pending_battle_context = {
		"encounter_id": encounter_id,
		"return_sequence": return_sequence,
	}
	return true


func get_pending_battle_context() -> Dictionary:
	return pending_battle_context.duplicate(true)


func clear_pending_battle_context() -> void:
	pending_battle_context.clear()


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
