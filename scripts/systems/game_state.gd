extends Node

var flags: Dictionary = {}
var bonds: Dictionary = {}


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
