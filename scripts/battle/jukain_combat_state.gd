class_name JukainCombatState
extends RefCounted

## Jukain-only Milestone 5.1 state owned by the battle sandbox.
## The BattleUnit ATK remains the authoritative temporary real-ATK fixture.

enum State {
	LOCKED,
	UNLOCKED,
}

const LOCKED_EFFECTIVE_ATK := 1

var current_state: State = State.LOCKED


func reset() -> void:
	current_state = State.LOCKED


func debug_unlock() -> bool:
	if current_state == State.UNLOCKED:
		return false
	current_state = State.UNLOCKED
	return true


func get_state() -> State:
	return current_state


func get_state_label() -> String:
	return "LOCKED" if current_state == State.LOCKED else "UNLOCKED"


func get_effective_atk(real_atk: int) -> int:
	if current_state == State.LOCKED:
		return LOCKED_EFFECTIVE_ATK
	return maxi(0, real_atk)
