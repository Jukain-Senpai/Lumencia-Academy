class_name HirukoCombatState
extends RefCounted

## Hiruko-only Milestone 4 prototype state owned by the battle sandbox.
## Seal capacities are temporary fixture values, not final balance data.

enum State {
	SEALED,
	FLAMING_SWORD,
	LAEVATAIN,
}

enum ActiveSeal {
	NONE,
	CHAINS,
	WRAPPER,
}

const CHAINS_MAX := 100
const WRAPPER_MAX := 100
const SEALED_RESISTANCE_PERCENT := 70
const FLAMING_SWORD_RESISTANCE_PERCENT := 35
const LAEVATAIN_RESISTANCE_PERCENT := 0
const SEALED_BASIC_ATTACK_PERCENT := 100
const FLAMING_SWORD_BASIC_ATTACK_PERCENT := 120
const LAEVATAIN_BASIC_ATTACK_PERCENT := 140

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


func get_resistance_percent(state: State = get_state()) -> int:
	match state:
		State.SEALED:
			return SEALED_RESISTANCE_PERCENT
		State.FLAMING_SWORD:
			return FLAMING_SWORD_RESISTANCE_PERCENT
		State.LAEVATAIN:
			return LAEVATAIN_RESISTANCE_PERCENT
	return 0


func get_active_seal(state: State = get_state()) -> ActiveSeal:
	match state:
		State.SEALED:
			return ActiveSeal.CHAINS
		State.FLAMING_SWORD:
			return ActiveSeal.WRAPPER
		State.LAEVATAIN:
			return ActiveSeal.NONE
	return ActiveSeal.NONE


func get_active_seal_label(state: State = get_state()) -> String:
	match get_active_seal(state):
		ActiveSeal.CHAINS:
			return "Chains"
		ActiveSeal.WRAPPER:
			return "Wrapper"
	return "None"


func get_basic_attack_percent(state: State = get_state()) -> int:
	match state:
		State.SEALED:
			return SEALED_BASIC_ATTACK_PERCENT
		State.FLAMING_SWORD:
			return FLAMING_SWORD_BASIC_ATTACK_PERCENT
		State.LAEVATAIN:
			return LAEVATAIN_BASIC_ATTACK_PERCENT
	return 100


func get_basic_attack_type_label(state: State = get_state()) -> String:
	return "BLUNT" if state == State.SEALED else "SLASH"


func get_basic_attack_damage(base_atk: int, state: State = get_state()) -> int:
	return _scale_damage_ceil(base_atk, get_basic_attack_percent(state))


func get_profile_label() -> String:
	return "DR %d%%  •  Basic %s ×%.1f" % [
		get_resistance_percent(),
		get_basic_attack_type_label(),
		get_basic_attack_percent() / 100.0,
	]


func prepare_hostile_hit(raw_damage: int) -> Dictionary:
	var safe_raw := maxi(0, raw_damage)
	var state_at_hit_start := get_state()
	var active_seal := get_active_seal(state_at_hit_start)
	var seal_before := _seal_value(active_seal)
	var resistance_percent := get_resistance_percent(state_at_hit_start)
	return {
		"state_at_hit_start": state_at_hit_start,
		"state_at_hit_start_label": _state_label(state_at_hit_start),
		"raw_damage": safe_raw,
		"resistance_percent": resistance_percent,
		"hp_damage": _scale_damage_ceil(safe_raw, 100 - resistance_percent),
		"active_seal": active_seal,
		"active_seal_label": get_active_seal_label(state_at_hit_start),
		"seal_before": seal_before,
	}


func apply_prepared_seal_damage(hit: Dictionary) -> Dictionary:
	var result := hit.duplicate()
	var captured_state: State = result.get("state_at_hit_start", get_state())
	var active_seal: ActiveSeal = result.get("active_seal", ActiveSeal.NONE)
	var raw_damage: int = maxi(0, result.get("raw_damage", 0))
	var seal_before: int = result.get("seal_before", _seal_value(active_seal))

	# The synchronous battle controller must finish HP application before this call.
	# Reject a stale/mismatched prepared result instead of damaging a different Seal.
	if captured_state != get_state() or active_seal != get_active_seal(captured_state):
		result["applied"] = false
		result["seal_after"] = _seal_value(active_seal)
		result["seal_broke"] = false
		result["state_after"] = get_state()
		result["state_after_label"] = get_state_label()
		return result

	match active_seal:
		ActiveSeal.CHAINS:
			chains_current = maxi(0, chains_current - raw_damage)
		ActiveSeal.WRAPPER:
			wrapper_current = maxi(0, wrapper_current - raw_damage)
		ActiveSeal.NONE:
			pass

	var seal_after := _seal_value(active_seal)
	result["applied"] = true
	result["seal_after"] = seal_after
	result["seal_broke"] = active_seal != ActiveSeal.NONE and seal_before > 0 and seal_after == 0
	result["state_after"] = get_state()
	result["state_after_label"] = get_state_label()
	return result


func _seal_value(active_seal: ActiveSeal) -> int:
	match active_seal:
		ActiveSeal.CHAINS:
			return chains_current
		ActiveSeal.WRAPPER:
			return wrapper_current
	return 0


func _state_label(state: State) -> String:
	match state:
		State.SEALED:
			return "SEALED"
		State.FLAMING_SWORD:
			return "FLAMING SWORD"
		State.LAEVATAIN:
			return "LAEVATAIN"
	return "UNKNOWN"


func _scale_damage_ceil(base_damage: int, percentage: int) -> int:
	var safe_damage := maxi(0, base_damage)
	var safe_percentage := maxi(0, percentage)
	return (safe_damage * safe_percentage + 99) / 100
