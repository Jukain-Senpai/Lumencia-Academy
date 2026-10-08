class_name JukainPrescriptState
extends RefCounted

## Narrow M5.2 state for one sandbox Prescript. Combat flow remains in battle_sandbox.gd.

enum Phase {
	ORIGINAL_ACTIVE,
	DEFY_REPLACEMENT_ACTIVE,
	RESOLVED_OBEY,
	RESOLVED_EXPLOIT,
	RESOLVED_DEFY,
}

const ORIGINAL_REQUIREMENT := "Make Hiruko lose HP before your next turn."
const REPLACEMENT_REQUIREMENT := "Take damage from an enemy."
const KARMA_DAMAGE_PERCENT_PER_STACK := 20
const SOURCE_JUKAIN_ALLY_ATTACK: StringName = &"jukain_ally_attack"
const SOURCE_ENEMY_ATTACK: StringName = &"enemy_attack"

var phase: Phase = Phase.ORIGINAL_ACTIVE
var karma_stacks := 0
var hiruko_baseline_hp := 0
var activation_turn_token: StringName = &""
var exploit_setup := false
var deadline_evaluation_count := 0


func reset(current_hiruko_hp: int) -> void:
	phase = Phase.ORIGINAL_ACTIVE
	karma_stacks = 0
	hiruko_baseline_hp = maxi(0, current_hiruko_hp)
	activation_turn_token = &""
	exploit_setup = false
	deadline_evaluation_count = 0


func on_jukain_turn_started(turn_token: StringName, current_hiruko_hp: int) -> StringName:
	if phase != Phase.ORIGINAL_ACTIVE or turn_token == &"":
		return &"none"
	if activation_turn_token == &"":
		activation_turn_token = turn_token
		hiruko_baseline_hp = maxi(0, current_hiruko_hp)
		return &"activated"
	if turn_token == activation_turn_token:
		return &"none"

	deadline_evaluation_count += 1
	phase = Phase.DEFY_REPLACEMENT_ACTIVE
	karma_stacks += 1
	return &"defied"


func can_offer_obey_target() -> bool:
	return phase == Phase.ORIGINAL_ACTIVE and activation_turn_token != &""


func mark_exploit_setup() -> bool:
	if not can_offer_obey_target() or exploit_setup:
		return false
	exploit_setup = true
	return true


func record_hiruko_hp_loss(source: StringName, hp_before: int, hp_after: int) -> bool:
	if not can_offer_obey_target() or hp_after >= hp_before:
		return false
	if source == SOURCE_JUKAIN_ALLY_ATTACK:
		phase = Phase.RESOLVED_OBEY
		return true
	if source == SOURCE_ENEMY_ATTACK and exploit_setup:
		phase = Phase.RESOLVED_EXPLOIT
		return true
	return false


func record_enemy_damage_to_jukain(hp_before: int, hp_after: int) -> bool:
	if phase != Phase.DEFY_REPLACEMENT_ACTIVE or hp_after >= hp_before:
		return false
	phase = Phase.RESOLVED_DEFY
	return true


func get_enemy_damage_to_jukain(raw_damage: int) -> int:
	var safe_damage := maxi(0, raw_damage)
	var percentage := 100 + karma_stacks * KARMA_DAMAGE_PERCENT_PER_STACK
	return (safe_damage * percentage + 99) / 100


func get_karma_multiplier_label() -> String:
	return "×%.2f" % ((100 + karma_stacks * KARMA_DAMAGE_PERCENT_PER_STACK) / 100.0)


func get_route_label() -> String:
	match phase:
		Phase.RESOLVED_OBEY:
			return "OBEY"
		Phase.RESOLVED_EXPLOIT:
			return "EXPLOIT"
		Phase.RESOLVED_DEFY:
			return "DEFY"
	return "NONE"


func is_resolved() -> bool:
	return phase in [Phase.RESOLVED_OBEY, Phase.RESOLVED_EXPLOIT, Phase.RESOLVED_DEFY]
