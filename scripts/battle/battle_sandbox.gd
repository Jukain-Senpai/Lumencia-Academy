extends Control

## Milestone 4 battle sandbox. Owns fixture, round, turn, and Hiruko prototype state locally.

const BattleUnitModel := preload("res://scripts/battle/battle_unit.gd")
const HirukoCombatStateModel := preload("res://scripts/battle/hiruko_combat_state.gd")
const UNIT_CARD_HEIGHT := 44.0
const UNIT_CARD_GAP := 2.0
const HIRUKO_UNIT_ID: StringName = &"party_1"
const BURN_DAMAGE := 5
const BURN_DURATION_TICKS := 2

enum BattleResult {
	NONE,
	VICTORY,
	DEFEAT,
}

enum HirukoSkill {
	NONE,
	KICK,
	GUT_STAB,
}

# Temporary sandbox fixtures. Hiruko retains Party 1's M3 values; none are final balance.
const PARTY_FIXTURES: Array[Dictionary] = [
	{"id": "party_1", "name": "Hiruko", "team": BattleUnitModel.Team.PARTY, "current_hp": 44, "max_hp": 44, "atk": 10, "spd": 14, "line": BattleUnitModel.Line.FRONT, "defeated": false},
	{"id": "party_2", "name": "Party 2", "team": BattleUnitModel.Team.PARTY, "current_hp": 40, "max_hp": 40, "atk": 9, "spd": 11, "line": BattleUnitModel.Line.FRONT, "defeated": false},
	{"id": "party_3", "name": "Party 3", "team": BattleUnitModel.Team.PARTY, "current_hp": 36, "max_hp": 36, "atk": 8, "spd": 9, "line": BattleUnitModel.Line.MID, "defeated": false},
	{"id": "party_4", "name": "Party 4", "team": BattleUnitModel.Team.PARTY, "current_hp": 34, "max_hp": 34, "atk": 7, "spd": 7, "line": BattleUnitModel.Line.MID, "defeated": false},
	{"id": "party_5", "name": "Party 5", "team": BattleUnitModel.Team.PARTY, "current_hp": 30, "max_hp": 30, "atk": 11, "spd": 13, "line": BattleUnitModel.Line.BACK, "defeated": false},
	{"id": "party_6", "name": "Party 6", "team": BattleUnitModel.Team.PARTY, "current_hp": 32, "max_hp": 32, "atk": 6, "spd": 5, "line": BattleUnitModel.Line.BACK, "defeated": false},
]

const ENEMY_FIXTURES: Array[Dictionary] = [
	{"id": "enemy_a", "name": "Enemy A", "team": BattleUnitModel.Team.ENEMY, "current_hp": 42, "max_hp": 42, "atk": 9, "spd": 15, "line": BattleUnitModel.Line.FRONT, "defeated": false},
	{"id": "enemy_b", "name": "Enemy B", "team": BattleUnitModel.Team.ENEMY, "current_hp": 38, "max_hp": 38, "atk": 8, "spd": 12, "line": BattleUnitModel.Line.FRONT, "defeated": false},
	{"id": "enemy_c", "name": "Enemy C", "team": BattleUnitModel.Team.ENEMY, "current_hp": 35, "max_hp": 35, "atk": 10, "spd": 10, "line": BattleUnitModel.Line.MID, "defeated": false},
	{"id": "enemy_d", "name": "Enemy D", "team": BattleUnitModel.Team.ENEMY, "current_hp": 46, "max_hp": 46, "atk": 7, "spd": 6, "line": BattleUnitModel.Line.BACK, "defeated": false},
]

@onready var restart_button: Button = %RestartButton
@onready var attack_button: Button = %AttackButton
@onready var skill_button: Button = %SkillButton
@onready var move_button: Button = %MoveButton
@onready var cancel_button: Button = %CancelButton
@onready var kick_skill_button: Button = %KickSkillButton
@onready var gut_stab_skill_button: Button = %GutStabSkillButton
@onready var skill_back_button: Button = %SkillBackButton
@onready var move_front_button: Button = %MoveFrontButton
@onready var move_mid_button: Button = %MoveMidButton
@onready var move_back_button: Button = %MoveBackButton
@onready var action_mode_label: Label = %ActionModeLabel
@onready var status_label: Label = %StatusLabel
@onready var round_label: Label = %RoundLabel
@onready var current_turn_label: Label = %CurrentTurnLabel
@onready var turn_order_label: Label = %TurnOrderLabel
@onready var combat_log_label: RichTextLabel = %CombatLog
@onready var hiruko_state_label: Label = %HirukoStateLabel
@onready var hiruko_profile_label: Label = %HirukoProfileLabel
@onready var chains_seal_bar: ProgressBar = %ChainsSealBar
@onready var chains_seal_value_label: Label = %ChainsSealValueLabel
@onready var wrapper_seal_bar: ProgressBar = %WrapperSealBar
@onready var wrapper_seal_value_label: Label = %WrapperSealValueLabel
@onready var break_chains_button: Button = %BreakChainsButton
@onready var break_wrapper_button: Button = %BreakWrapperButton
@onready var reset_hiruko_button: Button = %ResetHirukoButton

var party_units: Array[BattleUnit] = []
var enemy_units: Array[BattleUnit] = []
var round_number := 0
var turn_queue: Array[BattleUnit] = []
var turn_index := -1
var current_unit: BattleUnit = null
var combat_log_entries: Array[String] = []
var selecting_target := false
var valid_attack_targets: Array[BattleUnit] = []
var selecting_move := false
var valid_move_destinations: Array[int] = []
var selecting_skill := false
var selected_hiruko_skill: HirukoSkill = HirukoSkill.NONE
var valid_skill_targets: Array[BattleUnit] = []
var action_in_progress := false
var battle_result: BattleResult = BattleResult.NONE
var automatic_enemy_turns_enabled := true
var enemy_action_pending := false
var battle_generation := 0
var hiruko_unit: BattleUnit = null
var hiruko_state: RefCounted = null
var burn_remaining_ticks_by_unit_id: Dictionary = {}
var laevatain_aura_turn_token := ""


func _ready() -> void:
	restart_button.pressed.connect(restart_battle)
	attack_button.pressed.connect(begin_attack_selection)
	skill_button.pressed.connect(begin_skill_selection)
	move_button.pressed.connect(begin_move_selection)
	cancel_button.pressed.connect(cancel_action_selection)
	kick_skill_button.pressed.connect(select_hiruko_skill.bind(HirukoSkill.KICK))
	gut_stab_skill_button.pressed.connect(select_hiruko_skill.bind(HirukoSkill.GUT_STAB))
	skill_back_button.pressed.connect(back_from_skill_menu)
	move_front_button.pressed.connect(select_move_destination.bind(BattleUnitModel.Line.FRONT))
	move_mid_button.pressed.connect(select_move_destination.bind(BattleUnitModel.Line.MID))
	move_back_button.pressed.connect(select_move_destination.bind(BattleUnitModel.Line.BACK))
	break_chains_button.pressed.connect(debug_break_chains)
	break_wrapper_button.pressed.connect(debug_break_wrapper)
	reset_hiruko_button.pressed.connect(debug_reset_hiruko)
	restart_battle()


func restart_battle() -> void:
	battle_generation += 1
	enemy_action_pending = false
	var rebuilt_party := _build_units(PARTY_FIXTURES, BattleUnitModel.Team.PARTY)
	var rebuilt_enemies := _build_units(ENEMY_FIXTURES, BattleUnitModel.Team.ENEMY)
	if (
		rebuilt_party.is_empty()
		or rebuilt_enemies.is_empty()
		or not _has_unique_ids(rebuilt_party + rebuilt_enemies)
	):
		status_label.text = "Sandbox fixture error — check the debugger."
		return

	party_units.assign(rebuilt_party)
	enemy_units.assign(rebuilt_enemies)
	hiruko_unit = _find_unit_by_id(HIRUKO_UNIT_ID)
	hiruko_state = HirukoCombatStateModel.new()
	if hiruko_unit == null or hiruko_unit.display_name != "Hiruko":
		status_label.text = "Hiruko fixture error — check the debugger."
		return
	_reset_turn_state()
	_render_battlefield()
	_append_combat_log("Battle started.")
	_start_round()
	restart_button.release_focus()
	attack_button.release_focus()
	skill_button.release_focus()
	move_button.release_focus()
	cancel_button.release_focus()
	kick_skill_button.release_focus()
	gut_stab_skill_button.release_focus()
	skill_back_button.release_focus()
	move_front_button.release_focus()
	move_mid_button.release_focus()
	move_back_button.release_focus()
	break_chains_button.release_focus()
	break_wrapper_button.release_focus()
	reset_hiruko_button.release_focus()


func debug_break_chains() -> bool:
	if hiruko_state == null:
		return false
	if not hiruko_state.break_chains():
		_append_combat_log("Seal [Chains] is already broken.")
		return false
	_append_combat_log("Seal [Chains] broken.")
	_append_combat_log("Hiruko entered FLAMING SWORD.")
	_render_battlefield()
	return true


func debug_break_wrapper() -> bool:
	if hiruko_state == null:
		return false
	if hiruko_state.chains_current > 0:
		_append_combat_log("Cannot break Seal [Wrapper] while Seal [Chains] is intact.")
		return false
	if not hiruko_state.break_wrapper():
		_append_combat_log("Seal [Wrapper] is already broken.")
		return false
	_append_combat_log("Seal [Wrapper] broken.")
	_append_combat_log("Hiruko entered LAEVATAIN.")
	_render_battlefield()
	return true


func debug_reset_hiruko() -> bool:
	if hiruko_state == null:
		return false
	hiruko_state.reset()
	_append_combat_log("Hiruko debug state reset to SEALED.")
	_render_battlefield()
	return true


func advance_turn() -> void:
	# Kept for the M3.2 regression harness. No visible M3.3 control calls this directly.
	if action_in_progress or battle_result != BattleResult.NONE:
		return
	if current_unit == null:
		push_error("Cannot advance the sandbox turn without a current actor.")
		return
	_clear_action_selection()
	_activate_next_living_turn()


func begin_attack_selection() -> bool:
	if (
		action_in_progress
		or selecting_skill
		or selected_hiruko_skill != HirukoSkill.NONE
		or battle_result != BattleResult.NONE
		or current_unit == null
		or current_unit.team != BattleUnitModel.Team.PARTY
		or not _is_living(current_unit)
	):
		return false

	var targets := _get_valid_attack_targets(current_unit)
	if targets.is_empty():
		_check_battle_result()
		return false

	_clear_action_selection()
	valid_attack_targets = targets
	selecting_target = true
	_render_battlefield()
	_refresh_action_ui()
	return true


func cancel_target_selection() -> bool:
	if (
		(not selecting_target and selected_hiruko_skill == HirukoSkill.NONE)
		or action_in_progress
	):
		return false
	return cancel_action_selection()


func cancel_action_selection() -> bool:
	if action_in_progress:
		return false
	if selected_hiruko_skill != HirukoSkill.NONE:
		selected_hiruko_skill = HirukoSkill.NONE
		valid_skill_targets.clear()
		selecting_skill = true
		_render_battlefield()
		_refresh_action_ui()
		return true
	if selecting_skill:
		return back_from_skill_menu()
	if not selecting_target and not selecting_move:
		return false
	_clear_target_selection()
	selecting_move = false
	valid_move_destinations.clear()
	_render_battlefield()
	_refresh_action_ui()
	return true


func begin_move_selection() -> bool:
	if (
		action_in_progress
		or selecting_skill
		or selected_hiruko_skill != HirukoSkill.NONE
		or battle_result != BattleResult.NONE
		or current_unit == null
		or current_unit.team != BattleUnitModel.Team.PARTY
		or not _is_living(current_unit)
	):
		return false

	_clear_action_selection()
	valid_move_destinations = get_adjacent_lines(current_unit.line)
	selecting_move = true
	_refresh_action_ui()
	return true


func begin_skill_selection() -> bool:
	if (
		action_in_progress
		or battle_result != BattleResult.NONE
		or current_unit != hiruko_unit
		or not _is_living(hiruko_unit)
		or selecting_target
		or selecting_move
		or selecting_skill
		or selected_hiruko_skill != HirukoSkill.NONE
	):
		return false
	selecting_skill = true
	_refresh_action_ui()
	return true


func back_from_skill_menu() -> bool:
	if action_in_progress or not selecting_skill:
		return false
	selecting_skill = false
	selected_hiruko_skill = HirukoSkill.NONE
	valid_skill_targets.clear()
	_render_battlefield()
	_refresh_action_ui()
	return true


func select_hiruko_skill(skill: HirukoSkill) -> bool:
	if (
		action_in_progress
		or not selecting_skill
		or current_unit != hiruko_unit
		or not _is_living(hiruko_unit)
		or skill not in [HirukoSkill.KICK, HirukoSkill.GUT_STAB]
	):
		return false
	var targets := _get_valid_attack_targets(hiruko_unit)
	if targets.is_empty():
		_check_battle_result()
		return false
	selecting_skill = false
	selected_hiruko_skill = skill
	valid_skill_targets = targets
	_render_battlefield()
	_refresh_action_ui()
	return true


func select_move_destination(destination: int) -> bool:
	if action_in_progress or battle_result != BattleResult.NONE or not selecting_move:
		return false
	if current_unit == null or not _is_living(current_unit):
		return false
	if destination not in valid_move_destinations:
		return false
	return _commit_move(current_unit, destination)


func select_attack_target(target_id: StringName) -> bool:
	if not selecting_target or action_in_progress or current_unit == null:
		return false
	var target := _find_unit_by_id(target_id)
	if target == null:
		return false
	return _commit_basic_attack(current_unit, target)


func select_hiruko_skill_target(target_id: StringName) -> bool:
	if (
		action_in_progress
		or selected_hiruko_skill == HirukoSkill.NONE
		or current_unit != hiruko_unit
	):
		return false
	var target := _find_unit_by_id(target_id)
	if target == null or not _contains_unit(valid_skill_targets, target):
		return false
	return _commit_hiruko_skill(selected_hiruko_skill, target)


func resolve_enemy_turn() -> bool:
	if (
		action_in_progress
		or selecting_target
		or selecting_move
		or selecting_skill
		or selected_hiruko_skill != HirukoSkill.NONE
		or battle_result != BattleResult.NONE
		or current_unit == null
		or current_unit.team != BattleUnitModel.Team.ENEMY
		or not _is_living(current_unit)
	):
		return false

	var targets := _get_valid_attack_targets(current_unit)
	if targets.is_empty():
		_check_battle_result()
		return false
	return _commit_basic_attack(current_unit, targets[0])


func _reset_turn_state() -> void:
	round_number = 0
	turn_queue.clear()
	turn_index = -1
	current_unit = null
	combat_log_entries.clear()
	_clear_action_selection()
	action_in_progress = false
	battle_result = BattleResult.NONE
	enemy_action_pending = false
	burn_remaining_ticks_by_unit_id.clear()
	laevatain_aura_turn_token = ""
	combat_log_label.clear()
	_refresh_turn_ui()


func _start_round() -> void:
	if battle_result != BattleResult.NONE:
		return
	round_number += 1
	turn_queue = _build_turn_queue(party_units + enemy_units)
	turn_index = -1
	current_unit = null

	if turn_queue.is_empty():
		_check_battle_result()
		return

	_append_combat_log("Round %d started." % round_number)
	_activate_next_living_turn()


func _build_turn_queue(units: Array) -> Array[BattleUnit]:
	var queue: Array[BattleUnit] = []
	for unit: BattleUnit in units:
		if _is_living(unit):
			queue.append(unit)

	# Temporary M3 tie-break: ascending stable ID after descending SPD.
	queue.sort_custom(
		func(first: BattleUnit, second: BattleUnit) -> bool:
			if first.spd == second.spd:
				return String(first.stable_id) < String(second.stable_id)
			return first.spd > second.spd
	)

	if not _has_unique_ids(queue):
		push_error("A round queue cannot contain duplicate unit references or IDs.")
		return []
	return queue


func _activate_next_living_turn() -> void:
	if battle_result != BattleResult.NONE:
		return
	_clear_action_selection()
	current_unit = null
	while turn_index + 1 < turn_queue.size():
		turn_index += 1
		var candidate := turn_queue[turn_index]
		if not _is_living(candidate):
			_clear_burn(candidate)
			_append_combat_log("%s is defeated and skips their turn." % candidate.display_name)
			continue

		current_unit = candidate
		_append_combat_log("%s's turn." % current_unit.display_name)
		if _try_apply_hiruko_turn_start_aura():
			_render_battlefield()
		_refresh_turn_ui()
		_schedule_enemy_turn()
		return

	_start_round()


func _is_living(unit: BattleUnit) -> bool:
	return not unit.defeated and unit.current_hp > 0


func _get_nearest_occupied_line(team: BattleUnit.Team) -> int:
	var units := party_units if team == BattleUnitModel.Team.PARTY else enemy_units
	for line: BattleUnit.Line in [
		BattleUnitModel.Line.FRONT,
		BattleUnitModel.Line.MID,
		BattleUnitModel.Line.BACK,
	]:
		for unit: BattleUnit in units:
			if unit.line == line and _is_living(unit):
				return line
	return -1


func _get_valid_attack_targets(attacker: BattleUnit) -> Array[BattleUnit]:
	var targets: Array[BattleUnit] = []
	if attacker == null or not _is_living(attacker):
		return targets

	var opposing_team: BattleUnit.Team = (
		BattleUnitModel.Team.ENEMY
		if attacker.team == BattleUnitModel.Team.PARTY
		else BattleUnitModel.Team.PARTY
	)
	var nearest_line := _get_nearest_occupied_line(opposing_team)
	if nearest_line < 0:
		return targets

	var opposing_units := enemy_units if opposing_team == BattleUnitModel.Team.ENEMY else party_units
	for unit: BattleUnit in opposing_units:
		if unit.line == nearest_line and _is_living(unit):
			targets.append(unit)
	targets.sort_custom(
		func(first: BattleUnit, second: BattleUnit) -> bool:
			return String(first.stable_id) < String(second.stable_id)
	)
	return targets


func _commit_basic_attack(attacker: BattleUnit, target: BattleUnit) -> bool:
	if action_in_progress or attacker == null or target == null:
		return false
	if attacker != current_unit or not _is_living(attacker):
		return false
	if not _contains_unit(_get_valid_attack_targets(attacker), target):
		return false

	action_in_progress = true
	var raw_damage := maxi(0, attacker.atk)
	var hp_damage := raw_damage
	var attack_type := ""
	var hiruko_hit: Dictionary = {}
	var hiruko_attack_state := -1

	if attacker == hiruko_unit:
		hiruko_attack_state = hiruko_state.get_state()
		hp_damage = hiruko_state.get_basic_attack_damage(attacker.atk)
		attack_type = hiruko_state.get_basic_attack_type_label()
	elif target == hiruko_unit and attacker.team == BattleUnitModel.Team.ENEMY:
		hiruko_hit = hiruko_state.prepare_hostile_hit(raw_damage)
		hp_damage = hiruko_hit["hp_damage"]

	# HP is intentionally applied before raw Seal damage. The prepared result
	# captured Hiruko's state at hit start for this hit's resistance calculation.
	target.current_hp = maxi(0, target.current_hp - hp_damage)
	if target.current_hp == 0:
		target.defeated = true

	if not hiruko_hit.is_empty():
		hiruko_hit = hiruko_state.apply_prepared_seal_damage(hiruko_hit)
		_log_hiruko_incoming_hit(attacker, hiruko_hit)
		if (
			hiruko_hit["seal_broke"]
			and hiruko_hit["state_at_hit_start"] == HirukoCombatStateModel.State.FLAMING_SWORD
			and hiruko_hit["state_after"] == HirukoCombatStateModel.State.LAEVATAIN
		):
			_apply_laevatain_aura("activation")
	elif attack_type.is_empty():
		_append_combat_log(
			"%s attacks %s for %d damage." % [attacker.display_name, target.display_name, hp_damage]
		)
	else:
		_append_combat_log(
			"%s attacks %s for %d %s damage." % [
				attacker.display_name,
				target.display_name,
				hp_damage,
				attack_type.capitalize(),
			]
		)
	if target.defeated:
		_clear_burn(target)
		_append_combat_log("%s is defeated." % target.display_name)
	else:
		_append_combat_log("%s has %d HP remaining." % [target.display_name, target.current_hp])
		if (
			attacker == hiruko_unit
			and hiruko_attack_state != HirukoCombatStateModel.State.SEALED
		):
			var burn_was_active := _get_burn_ticks(target) > 0
			_apply_burn(target)
			_append_combat_log(
				"Hiruko %s Burn on %s (2 ticks)." % [
					"refreshes" if burn_was_active else "applies",
					target.display_name,
				]
			)

	_clear_action_selection()
	_render_battlefield()
	_finish_completed_action(attacker)
	return true


func _log_hiruko_incoming_hit(attacker: BattleUnit, hit: Dictionary) -> void:
	_append_combat_log(
		"%s attacks Hiruko for %d raw damage." % [attacker.display_name, hit["raw_damage"]]
	)
	_append_combat_log(
		"Hiruko resists %d%% and takes %d damage." % [
			hit["resistance_percent"],
			hit["hp_damage"],
		]
	)
	if hit["active_seal"] != HirukoCombatStateModel.ActiveSeal.NONE:
		_append_combat_log(
			"Seal [%s]: %d → %d." % [
				hit["active_seal_label"],
				hit["seal_before"],
				hit["seal_after"],
			]
		)
	if hit["seal_broke"]:
		_append_combat_log("Seal [%s] is broken." % hit["active_seal_label"])
	if hit["state_after"] != hit["state_at_hit_start"]:
		_append_combat_log("Hiruko enters %s." % hit["state_after_label"])


func _commit_move(unit: BattleUnit, destination: int) -> bool:
	if unit != current_unit or unit.team != BattleUnitModel.Team.PARTY:
		return false
	if destination not in get_adjacent_lines(unit.line):
		return false

	action_in_progress = true
	var origin: int = unit.line
	unit.line = destination as BattleUnit.Line
	_append_combat_log("%s moves from %s to %s." % [
		unit.display_name,
		BattleUnitModel.line_name(origin),
		BattleUnitModel.line_name(destination),
	])
	_clear_action_selection()
	_render_battlefield()
	_finish_completed_action(unit)
	return true


func _commit_hiruko_skill(skill: HirukoSkill, target: BattleUnit) -> bool:
	if action_in_progress or skill not in [HirukoSkill.KICK, HirukoSkill.GUT_STAB]:
		return false
	if hiruko_unit != current_unit or not _is_living(hiruko_unit) or target == null:
		return false
	if not _contains_unit(valid_skill_targets, target):
		return false
	if not _contains_unit(_get_valid_attack_targets(hiruko_unit), target):
		return false

	action_in_progress = true
	_clear_action_selection()
	if skill == HirukoSkill.KICK:
		_resolve_hiruko_kick(target)
	else:
		_resolve_hiruko_gut_stab(target)
	_render_battlefield()
	_finish_completed_action(hiruko_unit)
	return true


func _resolve_hiruko_kick(target: BattleUnit) -> void:
	var kick_damage := maxi(0, hiruko_unit.atk)
	_append_combat_log("Hiruko uses Kick on %s." % target.display_name)
	_apply_hiruko_skill_damage(target, kick_damage)
	_append_combat_log(
		"Hiruko kicks %s for %d Blunt damage." % [target.display_name, kick_damage]
	)
	_advance_hiruko_toward_front()
	_log_skill_target_result(target)


func _resolve_hiruko_gut_stab(target: BattleUnit) -> void:
	var kick_damage := maxi(0, hiruko_unit.atk)
	var sword_state: HirukoCombatStateModel.State = hiruko_state.get_state()
	_append_combat_log("Hiruko uses Gut Stab on %s." % target.display_name)
	_apply_hiruko_skill_damage(target, kick_damage)
	_append_combat_log(
		"Gut Stab Kick hits %s for %d Blunt damage." % [target.display_name, kick_damage]
	)
	_advance_hiruko_toward_front()
	_render_battlefield()
	if target.defeated:
		_clear_burn(target)
		_append_combat_log("%s is defeated by the Kick." % target.display_name)
		return

	_append_combat_log(
		"%s has %d HP remaining after the Kick." % [target.display_name, target.current_hp]
	)
	var sword_damage: int = hiruko_state.get_basic_attack_damage(hiruko_unit.atk, sword_state)
	var sword_type: String = hiruko_state.get_basic_attack_type_label(sword_state)
	_apply_hiruko_skill_damage(target, sword_damage)
	_append_combat_log(
		"Gut Stab sword follow-up hits %s for %d %s damage." % [
			target.display_name,
			sword_damage,
			sword_type.capitalize(),
		]
	)
	if target.defeated:
		_clear_burn(target)
		_append_combat_log("%s is defeated by the sword follow-up." % target.display_name)
		return

	_append_combat_log("%s has %d HP remaining." % [target.display_name, target.current_hp])
	if sword_state != HirukoCombatStateModel.State.SEALED:
		var burn_was_active := _get_burn_ticks(target) > 0
		_apply_burn(target)
		_append_combat_log(
			"Hiruko's sword %s Burn on %s (2 ticks)." % [
				"refreshes" if burn_was_active else "applies",
				target.display_name,
			]
		)


func _apply_hiruko_skill_damage(target: BattleUnit, damage: int) -> void:
	target.current_hp = maxi(0, target.current_hp - maxi(0, damage))
	if target.current_hp == 0:
		target.defeated = true


func _advance_hiruko_toward_front() -> void:
	var origin: BattleUnit.Line = hiruko_unit.line
	match hiruko_unit.line:
		BattleUnitModel.Line.BACK:
			hiruko_unit.line = BattleUnitModel.Line.MID
		BattleUnitModel.Line.MID:
			hiruko_unit.line = BattleUnitModel.Line.FRONT
		BattleUnitModel.Line.FRONT:
			pass
	if hiruko_unit.line == origin:
		_append_combat_log("Hiruko holds the Front line.")
	else:
		_append_combat_log(
			"Hiruko advances from %s to %s." % [
				BattleUnitModel.line_name(origin),
				BattleUnitModel.line_name(hiruko_unit.line),
			]
		)


func _log_skill_target_result(target: BattleUnit) -> void:
	if target.defeated:
		_clear_burn(target)
		_append_combat_log("%s is defeated." % target.display_name)
	else:
		_append_combat_log("%s has %d HP remaining." % [target.display_name, target.current_hp])


func _finish_completed_action(actor: BattleUnit) -> void:
	# Direct actions own the first result check. A terminal hit never grants the
	# acting unit a post-battle Burn tick.
	if _check_battle_result():
		action_in_progress = false
		return

	_process_burn_tick(actor)
	_render_battlefield()
	if _check_battle_result():
		action_in_progress = false
		return

	action_in_progress = false
	_activate_next_living_turn()


func _get_burn_ticks(unit: BattleUnit) -> int:
	if unit == null:
		return 0
	return int(burn_remaining_ticks_by_unit_id.get(unit.stable_id, 0))


func _apply_burn(unit: BattleUnit) -> bool:
	if unit == null or not _is_living(unit):
		return false
	burn_remaining_ticks_by_unit_id[unit.stable_id] = BURN_DURATION_TICKS
	return true


func _clear_burn(unit: BattleUnit) -> void:
	if unit != null:
		burn_remaining_ticks_by_unit_id.erase(unit.stable_id)


func _process_burn_tick(unit: BattleUnit) -> bool:
	var ticks_before := _get_burn_ticks(unit)
	if ticks_before <= 0:
		return false
	if not _is_living(unit):
		_clear_burn(unit)
		return false

	unit.current_hp = maxi(0, unit.current_hp - BURN_DAMAGE)
	var ticks_after := ticks_before - 1
	_append_combat_log("%s takes %d Burn damage." % [unit.display_name, BURN_DAMAGE])
	if unit.current_hp == 0:
		unit.defeated = true
		_clear_burn(unit)
		_append_combat_log("%s is defeated by Burn." % unit.display_name)
	elif ticks_after == 0:
		_clear_burn(unit)
		_append_combat_log("Burn expires on %s (%d HP remaining)." % [unit.display_name, unit.current_hp])
	else:
		burn_remaining_ticks_by_unit_id[unit.stable_id] = ticks_after
		_append_combat_log(
			"%s has Burn %d and %d HP remaining." % [unit.display_name, ticks_after, unit.current_hp]
		)
	return true


func _try_apply_hiruko_turn_start_aura() -> bool:
	if (
		current_unit != hiruko_unit
		or not _is_living(hiruko_unit)
		or hiruko_state.get_state() != HirukoCombatStateModel.State.LAEVATAIN
	):
		return false
	var token := "%d:%d:%d" % [battle_generation, round_number, turn_index]
	if token == laevatain_aura_turn_token:
		return false
	laevatain_aura_turn_token = token
	_apply_laevatain_aura("turn-start")
	return true


func _apply_laevatain_aura(aura_kind: String) -> void:
	var affected_names: Array[String] = []
	for unit: BattleUnit in party_units + enemy_units:
		if unit == hiruko_unit or not _is_living(unit):
			continue
		_apply_burn(unit)
		affected_names.append(unit.display_name)
	if affected_names.is_empty():
		return
	_append_combat_log(
		"Laevatain %s aura applies/refreshes Burn 2 on %s." % [
			aura_kind,
			", ".join(affected_names),
		]
	)


func get_adjacent_lines(origin: int) -> Array[int]:
	match origin:
		BattleUnitModel.Line.FRONT:
			return [BattleUnitModel.Line.MID]
		BattleUnitModel.Line.MID:
			return [BattleUnitModel.Line.FRONT, BattleUnitModel.Line.BACK]
		BattleUnitModel.Line.BACK:
			return [BattleUnitModel.Line.MID]
	return []


func _schedule_enemy_turn() -> void:
	if not automatic_enemy_turns_enabled or enemy_action_pending:
		return
	if battle_result != BattleResult.NONE or current_unit == null:
		return
	if current_unit.team != BattleUnitModel.Team.ENEMY or not _is_living(current_unit):
		return
	enemy_action_pending = true
	call_deferred("_process_enemy_turn", battle_generation)


func _process_enemy_turn(generation: int) -> bool:
	if generation != battle_generation or not enemy_action_pending:
		return false
	enemy_action_pending = false
	if battle_result != BattleResult.NONE or current_unit == null:
		return false
	if current_unit.team != BattleUnitModel.Team.ENEMY or not _is_living(current_unit):
		return false
	return resolve_enemy_turn()


func _check_battle_result() -> bool:
	if _living_units_for_team(BattleUnitModel.Team.ENEMY).is_empty():
		_end_battle(BattleResult.VICTORY)
		return true
	if _living_units_for_team(BattleUnitModel.Team.PARTY).is_empty():
		_end_battle(BattleResult.DEFEAT)
		return true
	return false


func _end_battle(result: BattleResult) -> void:
	if battle_result != BattleResult.NONE:
		return
	battle_result = result
	battle_generation += 1
	enemy_action_pending = false
	current_unit = null
	_clear_action_selection()
	if result == BattleResult.VICTORY:
		_append_combat_log("All enemies defeated.")
		_append_combat_log("Victory!")
	else:
		_append_combat_log("All party members defeated.")
		_append_combat_log("Defeat!")
	_render_battlefield()
	_refresh_turn_ui()


func _opposing_team(team: BattleUnit.Team) -> BattleUnit.Team:
	return (
		BattleUnitModel.Team.ENEMY
		if team == BattleUnitModel.Team.PARTY
		else BattleUnitModel.Team.PARTY
	)


func _living_units_for_team(team: BattleUnit.Team) -> Array[BattleUnit]:
	var result: Array[BattleUnit] = []
	var units := party_units if team == BattleUnitModel.Team.PARTY else enemy_units
	for unit: BattleUnit in units:
		if _is_living(unit):
			result.append(unit)
	return result


func _contains_unit(units: Array[BattleUnit], target: BattleUnit) -> bool:
	for unit: BattleUnit in units:
		if unit == target:
			return true
	return false


func _find_unit_by_id(target_id: StringName) -> BattleUnit:
	for unit: BattleUnit in party_units + enemy_units:
		if unit.stable_id == target_id:
			return unit
	return null


func _clear_target_selection() -> void:
	selecting_target = false
	valid_attack_targets.clear()


func _clear_action_selection() -> void:
	_clear_target_selection()
	selecting_move = false
	valid_move_destinations.clear()
	selecting_skill = false
	selected_hiruko_skill = HirukoSkill.NONE
	valid_skill_targets.clear()


func _append_combat_log(message: String) -> void:
	combat_log_entries.append(message)
	combat_log_label.text = "\n".join(combat_log_entries)
	combat_log_label.scroll_to_line(maxi(0, combat_log_label.get_line_count() - 1))


func _refresh_turn_ui() -> void:
	round_label.text = "Round %d" % round_number if round_number > 0 else "Round —"
	current_turn_label.text = current_unit.display_name if current_unit != null else "—"
	var order_names: PackedStringArray = []
	for unit: BattleUnit in turn_queue:
		order_names.append(unit.display_name)
	turn_order_label.text = " → ".join(order_names) if not order_names.is_empty() else "—"
	_refresh_action_ui()


func _refresh_action_ui() -> void:
	attack_button.hide()
	skill_button.hide()
	move_button.hide()
	cancel_button.hide()
	kick_skill_button.hide()
	gut_stab_skill_button.hide()
	skill_back_button.hide()
	move_front_button.hide()
	move_mid_button.hide()
	move_back_button.hide()
	if battle_result == BattleResult.VICTORY:
		action_mode_label.text = "VICTORY"
		status_label.text = "All enemies defeated. Restart to play again."
	elif battle_result == BattleResult.DEFEAT:
		action_mode_label.text = "DEFEAT"
		status_label.text = "All party members defeated. Restart to try again."
	elif current_unit == null:
		action_mode_label.text = "No current actor"
		status_label.text = "Turn engine paused."
	elif selecting_target:
		action_mode_label.text = "Attack — Select Target"
		cancel_button.show()
		status_label.text = "Choose a marked target or cancel."
	elif selected_hiruko_skill != HirukoSkill.NONE:
		action_mode_label.text = "%s — Select Target" % _hiruko_skill_label(selected_hiruko_skill)
		cancel_button.show()
		status_label.text = "Choose a marked target or cancel back to Skills."
	elif selecting_move:
		action_mode_label.text = "Move — Select Line"
		cancel_button.show()
		move_front_button.visible = BattleUnitModel.Line.FRONT in valid_move_destinations
		move_mid_button.visible = BattleUnitModel.Line.MID in valid_move_destinations
		move_back_button.visible = BattleUnitModel.Line.BACK in valid_move_destinations
		status_label.text = "Choose an adjacent line or cancel."
	elif selecting_skill:
		action_mode_label.text = "Choose Skill"
		kick_skill_button.show()
		gut_stab_skill_button.show()
		skill_back_button.show()
		status_label.text = "Kick advances; Gut Stab follows with the sword."
	elif current_unit.team == BattleUnitModel.Team.PARTY:
		action_mode_label.text = "Choose action"
		attack_button.show()
		if current_unit == hiruko_unit:
			skill_button.show()
		move_button.show()
		status_label.text = (
			"Hiruko's turn — Attack, Skill, or Move."
			if current_unit == hiruko_unit
			else "Party turn — Attack or move."
		)
	else:
		action_mode_label.text = "Enemy turn resolving…"
		status_label.text = "Enemy Basic Attack resolves automatically."


func _hiruko_skill_label(skill: HirukoSkill) -> String:
	match skill:
		HirukoSkill.KICK:
			return "Kick"
		HirukoSkill.GUT_STAB:
			return "Gut Stab"
	return "Skill"


func _build_units(fixtures: Array[Dictionary], expected_team: BattleUnit.Team) -> Array[BattleUnit]:
	var result: Array[BattleUnit] = []
	var ids: Dictionary = {}
	for fixture: Dictionary in fixtures:
		var unit := BattleUnitModel.from_fixture(fixture)
		if unit == null:
			return []
		if unit.team != expected_team:
			push_error(
				"Battle fixture '%s' is in the wrong fixture collection." % unit.stable_id
			)
			return []
		if ids.has(unit.stable_id):
			push_error("Duplicate battle unit ID '%s'." % unit.stable_id)
			return []
		ids[unit.stable_id] = true
		result.append(unit)
	return result


func _has_unique_ids(units: Array[BattleUnit]) -> bool:
	var ids: Dictionary = {}
	for unit: BattleUnit in units:
		if ids.has(unit.stable_id):
			push_error("Duplicate battle unit ID '%s'." % unit.stable_id)
			return false
		ids[unit.stable_id] = true
	return true


func _render_battlefield() -> void:
	var next_slots: Dictionary = {}
	for container: Control in _all_line_containers():
		for child: Node in container.get_children():
			container.remove_child(child)
			child.queue_free()
		next_slots[container] = 0

	for unit: BattleUnit in party_units + enemy_units:
		var container := _line_container_for(unit.team, unit.line)
		var slot: int = next_slots[container]
		var card := _create_unit_card(unit)
		container.add_child(card)
		_position_unit_card(card, slot)
		next_slots[container] = slot + 1
	_refresh_hiruko_ui()


func _refresh_hiruko_ui() -> void:
	if hiruko_state == null:
		hiruko_state_label.text = "UNAVAILABLE"
		return
	hiruko_state_label.text = hiruko_state.get_state_label()
	hiruko_profile_label.text = _get_hiruko_profile_text()
	hiruko_profile_label.tooltip_text = hiruko_profile_label.text
	chains_seal_bar.max_value = HirukoCombatStateModel.CHAINS_MAX
	chains_seal_bar.value = hiruko_state.chains_current
	wrapper_seal_bar.max_value = HirukoCombatStateModel.WRAPPER_MAX
	wrapper_seal_bar.value = hiruko_state.wrapper_current
	chains_seal_value_label.text = _seal_value_text(
		hiruko_state.chains_current, HirukoCombatStateModel.CHAINS_MAX
	)
	wrapper_seal_value_label.text = _seal_value_text(
		hiruko_state.wrapper_current, HirukoCombatStateModel.WRAPPER_MAX
	)
	chains_seal_bar.modulate = _seal_tint(
		hiruko_state.chains_current, HirukoCombatStateModel.CHAINS_MAX
	)
	wrapper_seal_bar.modulate = _seal_tint(
		hiruko_state.wrapper_current, HirukoCombatStateModel.WRAPPER_MAX
	)


func _get_hiruko_profile_text() -> String:
	if hiruko_state == null:
		return "UNAVAILABLE"
	var profile: String = hiruko_state.get_profile_label()
	if hiruko_state.get_state() == HirukoCombatStateModel.State.LAEVATAIN:
		profile += "  •  Aura ACTIVE"
	return profile


func _seal_value_text(current: int, maximum: int) -> String:
	return "BROKEN" if current == 0 else "%d/%d" % [current, maximum]


func _seal_tint(current: int, maximum: int) -> Color:
	if current == 0:
		return Color("d4858f")
	if current < maximum:
		return Color("f2c879")
	return Color("78b7d0")


func _all_line_containers() -> Array[Control]:
	return [
		%AllyBackUnits,
		%AllyMidUnits,
		%AllyFrontUnits,
		%EnemyFrontUnits,
		%EnemyMidUnits,
		%EnemyBackUnits,
	]


func _line_container_for(team: BattleUnit.Team, line: BattleUnit.Line) -> Control:
	if team == BattleUnitModel.Team.PARTY:
		match line:
			BattleUnitModel.Line.FRONT:
				return %AllyFrontUnits
			BattleUnitModel.Line.MID:
				return %AllyMidUnits
			BattleUnitModel.Line.BACK:
				return %AllyBackUnits
	else:
		match line:
			BattleUnitModel.Line.FRONT:
				return %EnemyFrontUnits
			BattleUnitModel.Line.MID:
				return %EnemyMidUnits
			BattleUnitModel.Line.BACK:
				return %EnemyBackUnits

	push_error("No visual container for team '%s', line '%s'." % [team, line])
	return %AllyBackUnits


func _create_unit_card(unit: BattleUnit) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, UNIT_CARD_HEIGHT)
	card.tooltip_text = "Stable ID: %s" % unit.stable_id
	var burn_ticks := _get_burn_ticks(unit)
	if burn_ticks > 0:
		card.tooltip_text += "\nBurn: %d tick(s), %d damage at end of this unit's turn" % [
			burn_ticks,
			BURN_DAMAGE,
		]
	if unit == hiruko_unit and hiruko_state != null:
		card.tooltip_text += "\n%s" % _get_hiruko_profile_text()

	var style := StyleBoxFlat.new()
	style.bg_color = Color("243b53") if unit.team == BattleUnitModel.Team.PARTY else Color("4a2837")
	style.border_color = Color("78b7d0") if unit.team == BattleUnitModel.Team.PARTY else Color("d4858f")
	style.set_border_width_all(2)
	if unit.defeated:
		style.bg_color = Color("242832")
		style.border_color = Color("5c626d")
	elif _is_current_target_choice(unit):
		style.border_color = Color("f2c879")
		style.set_border_width_all(4)
	style.set_corner_radius_all(8)
	style.content_margin_left = 5.0
	style.content_margin_top = 2.0
	style.content_margin_right = 5.0
	style.content_margin_bottom = 2.0
	card.add_theme_stylebox_override("panel", style)

	var details := VBoxContainer.new()
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_theme_constant_override("separation", 0)
	card.add_child(details)

	var identity_row := HBoxContainer.new()
	identity_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity_row.add_theme_constant_override("separation", 2)
	details.add_child(identity_row)

	var name_label := Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = unit.display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 13)
	identity_row.add_child(name_label)

	var state_label := Label.new()
	state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	state_label.add_theme_font_size_override("font_size", 9)
	if unit.defeated:
		state_label.text = "DEFEATED"
		state_label.add_theme_color_override("font_color", Color("d4858f"))
	elif _is_current_target_choice(unit):
		state_label.text = "SELECT"
		if burn_ticks > 0:
			state_label.text += " [BURN %d]" % burn_ticks
		state_label.add_theme_color_override("font_color", Color("f2c879"))
		card.tooltip_text += "\nClick to target %s" % unit.display_name
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.gui_input.connect(_on_target_card_input.bind(unit.stable_id))
	elif unit == hiruko_unit and hiruko_state != null:
		state_label.text = hiruko_state.get_state_label()
		if burn_ticks > 0:
			state_label.text += " [BURN %d]" % burn_ticks
		state_label.add_theme_color_override("font_color", Color("f2c879"))
	elif burn_ticks > 0:
		state_label.text = "[BURN %d]" % burn_ticks
		state_label.add_theme_color_override("font_color", Color("f2a65a"))
	identity_row.add_child(state_label)

	var line_label := Label.new()
	line_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line_label.text = BattleUnitModel.line_name(unit.line).to_upper()
	line_label.add_theme_color_override("font_color", Color("f2c879"))
	line_label.add_theme_font_size_override("font_size", 11)
	identity_row.add_child(line_label)

	var stats_label := Label.new()
	stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_label.text = "HP %d/%d  ATK %d  SPD %d" % [
		unit.current_hp,
		unit.max_hp,
		unit.atk,
		unit.spd,
	]
	stats_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stats_label.add_theme_font_size_override("font_size", 11)
	stats_label.add_theme_color_override("font_color", Color("c9d6e2"))
	details.add_child(stats_label)
	return card


func _position_unit_card(card: Control, slot: int) -> void:
	card.anchor_left = 0.0
	card.anchor_right = 1.0
	card.offset_left = 0.0
	card.offset_right = 0.0
	card.offset_top = slot * (UNIT_CARD_HEIGHT + UNIT_CARD_GAP)
	card.offset_bottom = card.offset_top + UNIT_CARD_HEIGHT


func _on_target_card_input(event: InputEvent, target_id: StringName) -> void:
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
	):
		get_viewport().set_input_as_handled()
		if selected_hiruko_skill != HirukoSkill.NONE:
			select_hiruko_skill_target(target_id)
		else:
			select_attack_target(target_id)


func _is_current_target_choice(unit: BattleUnit) -> bool:
	if selecting_target:
		return _contains_unit(valid_attack_targets, unit)
	if selected_hiruko_skill != HirukoSkill.NONE:
		return _contains_unit(valid_skill_targets, unit)
	return false
