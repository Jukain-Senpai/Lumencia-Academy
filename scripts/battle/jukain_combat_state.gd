class_name JukainCombatState
extends RefCounted

## Jukain-only battle state owned by the battle sandbox.
## BattleUnit ATK remains the authoritative temporary real-ATK fixture; Blessing
## modifies only already-resolved outgoing damage.

enum State {
	LOCKED,
	UNLOCKED,
}

const LOCKED_EFFECTIVE_ATK := 1
const BLESSING_DAMAGE_PERCENT_PER_STACK := 10

var current_state: State = State.LOCKED
var blessing_stacks := 0


func reset() -> void:
	current_state = State.LOCKED
	blessing_stacks = 0


func grant_blessing() -> void:
	blessing_stacks += 1


func clear_blessing() -> void:
	blessing_stacks = 0


func get_blessing_damage_percent() -> int:
	return blessing_stacks * BLESSING_DAMAGE_PERCENT_PER_STACK


func apply_blessing_to_resolved_damage(resolved_damage: int) -> int:
	var safe_damage := maxi(0, resolved_damage)
	var percentage := 100 + get_blessing_damage_percent()
	# TEMPORARY M6 PROTOTYPE ROUNDING: positive percentage damage rounds upward.
	return (safe_damage * percentage + 99) / 100


func debug_unlock() -> bool:
	return unlock()


func unlock() -> bool:
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
