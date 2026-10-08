class_name HirukoCombatState
extends RefCounted

## Hiruko-only Milestone 4 prototype state owned by the battle sandbox.
## Seal capacities are temporary fixture values, not final balance data.

enum State {
	SEALED,
	FLAMING_SWORD,
	LAEVATAIN,
}

const CHAINS_MAX := 100
const WRAPPER_MAX := 100

var chains_current := CHAINS_MAX
var wrapper_current := WRAPPER_MAX


func reset() -> void:
	chains_current = CHAINS_MAX
	wrapper_current = WRAPPER_MAX


func break_chains() -> bool:
	if chains_current == 0:
		return false
	return set_seals(0, wrapper_current)


func break_wrapper() -> bool:
	if chains_current > 0 or wrapper_current == 0:
		return false
	return set_seals(chains_current, 0)


func set_seals(chains: int, wrapper: int) -> bool:
	if chains < 0 or chains > CHAINS_MAX:
		return false
	if wrapper < 0 or wrapper > WRAPPER_MAX:
		return false
	if chains > 0 and wrapper == 0:
		return false
	chains_current = chains
	wrapper_current = wrapper
	return true


func get_state() -> State:
	if chains_current > 0:
		return State.SEALED
	if wrapper_current > 0:
		return State.FLAMING_SWORD
	return State.LAEVATAIN


func get_state_label() -> String:
	match get_state():
		State.SEALED:
			return "SEALED"
		State.FLAMING_SWORD:
			return "FLAMING SWORD"
		State.LAEVATAIN:
			return "LAEVATAIN"
	return "UNKNOWN"
