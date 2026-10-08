extends SceneTree

const BattleUnitModel := preload("res://scripts/battle/battle_unit.gd")
const HirukoCombatStateModel := preload("res://scripts/battle/hiruko_combat_state.gd")
const SANDBOX_PATH := "res://scenes/battle/battle_sandbox.tscn"

var failures: Array[String] = []
var checks := 0
var active_scene: Control


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_root_actions_and_skill_menu()
	await _test_navigation_and_protected_targets()
	await _test_kick_profiles_and_movement()
	await _test_gut_stab_profiles_and_movement()
	await _test_gut_stab_defeat_boundaries()
	await _test_one_action_burn_and_aura_guards()
	await _test_basic_move_and_prior_mechanics()
	await _test_restart_cleanup()
	await _test_full_battle_flow()
	await _test_layout()

	if failures.is_empty():
		print("M4.4 Hiruko skills regression suite passed (%d checks)." % checks)
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	push_error("M4.4 Hiruko skills regression suite failed: %d failure(s), %d checks." % [failures.size(), checks])
	quit(1)


func _test_root_actions_and_skill_menu() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_set_current(scene, scene.hiruko_unit)
	_check(scene.get_node("%AttackButton").visible, "Hiruko root menu is missing Attack")
	_check(scene.get_node("%SkillButton").visible, "Hiruko root menu is missing Skill")
	_check(scene.get_node("%MoveButton").visible, "Hiruko root menu is missing Move")
	_check(scene.get_node("%ActionModeLabel").text == "Choose action", "Hiruko root action mode is unclear")
	_check(scene.begin_skill_selection(), "Hiruko could not open the Skill menu")
	_check(scene.selecting_skill and scene.selected_hiruko_skill == scene.HirukoSkill.NONE, "Skill menu state was not authoritative")
	_check(scene.get_node("%KickSkillButton").visible, "Skill menu is missing Kick")
	_check(scene.get_node("%GutStabSkillButton").visible, "Skill menu is missing Gut Stab")
	_check(scene.get_node("%SkillBackButton").visible, "Skill menu is missing Back")
	_check(not scene.get_node("%AttackButton").visible and not scene.get_node("%MoveButton").visible, "Root actions remained visible inside Skill menu")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	var party_2 := _find_unit(scene, &"party_2")
	_set_current(scene, party_2)
	_check(scene.get_node("%AttackButton").visible and scene.get_node("%MoveButton").visible, "Generic ally lost Attack or Move")
	_check(not scene.get_node("%SkillButton").visible, "Generic ally gained a Skill action")
	_check(not scene.begin_skill_selection(), "Generic ally entered Hiruko's Skill menu")
	await _free_scene(scene)


func _test_navigation_and_protected_targets() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_set_current(scene, scene.hiruko_unit)
	var actor_before: BattleUnit = scene.current_unit
	var index_before: int = scene.turn_index
	var hp_before: int = scene.hiruko_unit.current_hp
	var line_before: int = scene.hiruko_unit.line
	var enemy_a := _find_unit(scene, &"enemy_a")
	var enemy_hp_before: int = enemy_a.current_hp
	_check(scene.begin_skill_selection() and scene.back_from_skill_menu(), "Skill → Back navigation failed")
	_check(scene.current_unit == actor_before and scene.turn_index == index_before, "Skill → Back advanced the queue")
	_check(scene.hiruko_unit.current_hp == hp_before and scene.hiruko_unit.line == line_before and enemy_a.current_hp == enemy_hp_before, "Skill → Back changed battle state")
	_check(not scene.selecting_skill and scene.selected_hiruko_skill == scene.HirukoSkill.NONE, "Skill → Back retained selection state")

	_check(scene.begin_skill_selection(), "Could not reopen Skill menu for Gut Stab Cancel")
	_check(scene.select_hiruko_skill(scene.HirukoSkill.GUT_STAB), "Could not enter Gut Stab target selection")
	_check(scene.get_node("%ActionModeLabel").text == "Gut Stab — Select Target", "Gut Stab target mode label is incorrect")
	_check(not scene.begin_attack_selection() and not scene.begin_move_selection(), "Attack or Move opened during skill target selection")
	_check(scene.cancel_action_selection(), "Gut Stab target Cancel failed")
	_check(scene.selecting_skill and scene.selected_hiruko_skill == scene.HirukoSkill.NONE, "Gut Stab Cancel did not return to Skill menu")
	_check(scene.hiruko_unit.line == line_before and enemy_a.current_hp == enemy_hp_before and scene._get_burn_ticks(enemy_a) == 0, "Gut Stab Cancel changed movement, HP, or Burn")
	_check(scene.back_from_skill_menu(), "Back failed after Gut Stab Cancel")

	_check(scene.begin_skill_selection(), "Could not reopen Skill menu for Kick Cancel")
	_check(scene.select_hiruko_skill(scene.HirukoSkill.KICK), "Could not enter Kick target selection")
	_check(scene.get_node("%ActionModeLabel").text == "Kick — Select Target", "Kick target mode label is incorrect")
	_check(scene.cancel_action_selection(), "Kick target Cancel failed")
	_check(scene.selecting_skill and scene.current_unit == actor_before and scene.turn_index == index_before, "Kick Cancel changed actor or failed to return to Skills")

	_check(scene.select_hiruko_skill(scene.HirukoSkill.KICK), "Could not reopen Kick targets after Cancel")
	var enemy_c := _find_unit(scene, &"enemy_c")
	_check(not _contains_unit(scene.valid_skill_targets, enemy_c), "Protected Mid enemy appeared in skill target list")
	_check(not scene.select_hiruko_skill_target(&"enemy_c"), "Kick accepted protected Mid enemy")
	_check(scene.selected_hiruko_skill == scene.HirukoSkill.KICK and enemy_c.current_hp == enemy_c.max_hp, "Invalid skill target canceled selection or took damage")
	await _free_scene(scene)


func _test_kick_profiles_and_movement() -> void:
	await _check_kick(HirukoCombatStateModel.State.SEALED, BattleUnitModel.Line.BACK, BattleUnitModel.Line.MID)
	await _check_kick(HirukoCombatStateModel.State.FLAMING_SWORD, BattleUnitModel.Line.MID, BattleUnitModel.Line.FRONT)
	await _check_kick(HirukoCombatStateModel.State.LAEVATAIN, BattleUnitModel.Line.FRONT, BattleUnitModel.Line.FRONT)


func _check_kick(state: int, origin: int, destination: int) -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_set_hiruko_state(scene, state)
	scene.hiruko_unit.line = origin as BattleUnitModel.Line
	_set_current(scene, scene.hiruko_unit)
	var enemy_a := _find_unit(scene, &"enemy_a")
	var hp_before: int = enemy_a.current_hp
	_check(_use_skill(scene, scene.HirukoSkill.KICK, &"enemy_a"), "Kick did not resolve in state %d" % state)
	_check(hp_before - enemy_a.current_hp == 10, "Kick did not deal exactly 10 damage in state %d" % state)
	_check(scene.hiruko_unit.line == destination, "Kick moved from %s to the wrong line" % BattleUnitModel.line_name(origin))
	_check(scene._get_burn_ticks(enemy_a) == 0, "Kick applied Burn in state %d" % state)
	_check(_log_contains(scene, "10 Blunt damage"), "Kick did not log Blunt damage")
	_check(not _log_contains(scene, "sword follow-up"), "Kick incorrectly executed a sword follow-up")
	_check(scene.current_unit == _find_unit(scene, &"party_5"), "Kick advanced the queue more or less than once")
	_check(scene.hiruko_unit.atk == 10, "Kick mutated Hiruko's stored ATK")
	await _free_scene(scene)


func _test_gut_stab_profiles_and_movement() -> void:
	await _check_gut_stab(HirukoCombatStateModel.State.SEALED, BattleUnitModel.Line.BACK, BattleUnitModel.Line.MID, 20, "10 Blunt", 0)
	await _check_gut_stab(HirukoCombatStateModel.State.SEALED, BattleUnitModel.Line.MID, BattleUnitModel.Line.FRONT, 20, "10 Blunt", 0)
	await _check_gut_stab(HirukoCombatStateModel.State.SEALED, BattleUnitModel.Line.FRONT, BattleUnitModel.Line.FRONT, 20, "10 Blunt", 0)
	await _check_gut_stab(HirukoCombatStateModel.State.FLAMING_SWORD, BattleUnitModel.Line.BACK, BattleUnitModel.Line.MID, 22, "12 Slash", 2)
	await _check_gut_stab(HirukoCombatStateModel.State.LAEVATAIN, BattleUnitModel.Line.MID, BattleUnitModel.Line.FRONT, 24, "14 Slash", 2)


func _check_gut_stab(state: int, origin: int, destination: int, expected_damage: int, sword_fragment: String, expected_burn: int) -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_set_hiruko_state(scene, state)
	scene.hiruko_unit.line = origin as BattleUnitModel.Line
	_set_current(scene, scene.hiruko_unit)
	var enemy_a := _find_unit(scene, &"enemy_a")
	var hp_before: int = enemy_a.current_hp
	_check(_use_skill(scene, scene.HirukoSkill.GUT_STAB, &"enemy_a"), "Gut Stab did not resolve in state %d" % state)
	_check(hp_before - enemy_a.current_hp == expected_damage, "Gut Stab direct total is incorrect in state %d" % state)
	_check(scene.hiruko_unit.line == destination, "Gut Stab movement is incorrect from %s" % BattleUnitModel.line_name(origin))
	_check(_log_contains(scene, "Gut Stab Kick hits Enemy A for 10 Blunt damage."), "Gut Stab Kick was not a distinct 10 Blunt hit")
	_check(_log_contains(scene, "sword follow-up hits Enemy A for %s damage." % sword_fragment), "Gut Stab sword profile is incorrect")
	_check(scene._get_burn_ticks(enemy_a) == expected_burn, "Gut Stab Burn result is incorrect in state %d" % state)
	_check(scene.current_unit == _find_unit(scene, &"party_5"), "Gut Stab did not consume exactly one queue position")
	_check(scene.hiruko_unit.atk == 10, "Gut Stab mutated Hiruko's stored ATK")
	await _free_scene(scene)


func _test_gut_stab_defeat_boundaries() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	scene.hiruko_unit.line = BattleUnitModel.Line.BACK
	_set_current(scene, scene.hiruko_unit)
	var enemy_a := _find_unit(scene, &"enemy_a")
	enemy_a.current_hp = 10
	_check(_use_skill(scene, scene.HirukoSkill.GUT_STAB, &"enemy_a"), "Kick-lethal Gut Stab did not resolve")
	_check(enemy_a.defeated and enemy_a.current_hp == 0, "Gut Stab Kick did not defeat 10 HP target")
	_check(scene.hiruko_unit.line == BattleUnitModel.Line.MID, "Hiruko did not advance after a lethal Kick")
	_check(not _log_contains(scene, "sword follow-up hits Enemy A"), "Sword followed a lethal Gut Stab Kick")
	_check(scene._get_burn_ticks(enemy_a) == 0, "Lethal Kick left Burn")
	_check(_find_unit(scene, &"enemy_b").current_hp == _find_unit(scene, &"enemy_b").max_hp, "Gut Stab retargeted after lethal Kick")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	_set_hiruko_state(scene, HirukoCombatStateModel.State.FLAMING_SWORD)
	_set_current(scene, scene.hiruko_unit)
	enemy_a = _find_unit(scene, &"enemy_a")
	enemy_a.current_hp = 20
	_check(_use_skill(scene, scene.HirukoSkill.GUT_STAB, &"enemy_a"), "Sword-lethal Gut Stab did not resolve")
	_check(enemy_a.defeated and enemy_a.current_hp == 0, "Gut Stab sword did not defeat surviving Kick target")
	_check(_log_contains(scene, "Gut Stab Kick hits") and _log_contains(scene, "sword follow-up hits"), "Sword-lethal Gut Stab did not retain two hit events")
	_check(scene._get_burn_ticks(enemy_a) == 0, "Sword-lethal target retained Burn")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	for enemy: BattleUnit in scene.enemy_units:
		if enemy.stable_id != &"enemy_a":
			_defeat(enemy)
	scene.hiruko_unit.line = BattleUnitModel.Line.BACK
	_set_current(scene, scene.hiruko_unit)
	enemy_a = _find_unit(scene, &"enemy_a")
	enemy_a.current_hp = 10
	scene._apply_burn(scene.hiruko_unit)
	var hiruko_hp_before: int = scene.hiruko_unit.current_hp
	_check(_use_skill(scene, scene.HirukoSkill.GUT_STAB, &"enemy_a"), "Final-enemy Kick kill did not resolve")
	_check(scene.battle_result == scene.BattleResult.VICTORY and scene.current_unit == null, "Final-enemy Kick kill did not produce immediate Victory")
	_check(scene.hiruko_unit.line == BattleUnitModel.Line.MID, "Final-enemy Kick kill omitted committed movement")
	_check(scene.hiruko_unit.current_hp == hiruko_hp_before, "Hiruko took post-Victory Burn after Kick kill")
	_check(not _log_contains(scene, "sword follow-up hits Enemy A"), "Final-enemy Kick kill executed sword follow-up")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	for enemy: BattleUnit in scene.enemy_units:
		if enemy.stable_id != &"enemy_a":
			_defeat(enemy)
	_set_hiruko_state(scene, HirukoCombatStateModel.State.FLAMING_SWORD)
	_set_current(scene, scene.hiruko_unit)
	enemy_a = _find_unit(scene, &"enemy_a")
	enemy_a.current_hp = 20
	scene._apply_burn(scene.hiruko_unit)
	hiruko_hp_before = scene.hiruko_unit.current_hp
	_check(_use_skill(scene, scene.HirukoSkill.GUT_STAB, &"enemy_a"), "Final-enemy sword kill did not resolve")
	_check(scene.battle_result == scene.BattleResult.VICTORY, "Final-enemy sword kill did not produce Victory")
	_check(scene._get_burn_ticks(enemy_a) == 0, "Final sword kill retained target Burn")
	_check(scene.hiruko_unit.current_hp == hiruko_hp_before, "Hiruko took post-Victory Burn after sword kill")
	await _free_scene(scene)


func _test_one_action_burn_and_aura_guards() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	scene.hiruko_unit.line = BattleUnitModel.Line.BACK
	_set_current(scene, scene.hiruko_unit)
	scene._apply_burn(scene.hiruko_unit)
	var hp_before: int = scene.hiruko_unit.current_hp
	_check(_use_skill(scene, scene.HirukoSkill.GUT_STAB, &"enemy_a"), "Burned Hiruko Gut Stab did not resolve")
	_check(scene.hiruko_unit.current_hp == hp_before - 5, "Gut Stab processed Hiruko Burn zero or multiple times")
	_check(scene._get_burn_ticks(scene.hiruko_unit) == 1, "Gut Stab did not consume exactly one Burn tick")
	_check(_log_count_containing(scene, "Hiruko takes 5 Burn damage.") == 1, "Gut Stab logged multiple Hiruko Burn ticks")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	scene.debug_break_chains()
	scene.debug_break_wrapper()
	scene.advance_turn()
	_check(scene.current_unit == scene.hiruko_unit, "Could not reach real Laevatain Hiruko turn")
	var aura_count := _log_count_containing(scene, "Laevatain turn-start aura")
	_check(aura_count == 1, "Laevatain aura did not trigger once before Skill selection")
	_check(scene.begin_skill_selection() and scene.back_from_skill_menu(), "Skill → Back failed during aura guard")
	_check(scene.begin_skill_selection() and scene.select_hiruko_skill(scene.HirukoSkill.GUT_STAB) and scene.cancel_action_selection(), "Gut Stab Cancel failed during aura guard")
	_check(scene.back_from_skill_menu(), "Back failed after Gut Stab Cancel during aura guard")
	_check(scene.begin_skill_selection() and scene.select_hiruko_skill(scene.HirukoSkill.KICK) and scene.cancel_action_selection(), "Kick Cancel failed during aura guard")
	_check(_log_count_containing(scene, "Laevatain turn-start aura") == aura_count, "Skill navigation retriggered Laevatain aura")
	await _free_scene(scene)


func _test_basic_move_and_prior_mechanics() -> void:
	for fixture: Array in [
		[HirukoCombatStateModel.State.SEALED, 10, 0],
		[HirukoCombatStateModel.State.FLAMING_SWORD, 12, 2],
		[HirukoCombatStateModel.State.LAEVATAIN, 14, 2],
	]:
		var scene := await _new_scene(false)
		if scene == null:
			return
		_set_hiruko_state(scene, fixture[0])
		_set_current(scene, scene.hiruko_unit)
		var enemy_a := _find_unit(scene, &"enemy_a")
		var hp_before: int = enemy_a.current_hp
		_check(scene.begin_attack_selection() and scene.select_attack_target(&"enemy_a"), "Existing Basic Attack failed in state %d" % fixture[0])
		_check(hp_before - enemy_a.current_hp == fixture[1], "Existing Basic Attack damage changed in state %d" % fixture[0])
		_check(scene._get_burn_ticks(enemy_a) == fixture[2], "Existing Basic Attack Burn changed in state %d" % fixture[0])
		_check(not _log_contains(scene, "Hiruko uses Kick") and not _log_contains(scene, "Gut Stab"), "Basic Attack invoked a skill stage")
		await _free_scene(scene)

	var move_scene := await _new_scene(false)
	if move_scene == null:
		return
	move_scene.hiruko_unit.line = BattleUnitModel.Line.BACK
	_set_current(move_scene, move_scene.hiruko_unit)
	var enemy_a := _find_unit(move_scene, &"enemy_a")
	var enemy_hp_before: int = enemy_a.current_hp
	_check(move_scene.begin_move_selection() and move_scene.select_move_destination(BattleUnitModel.Line.MID), "Existing normal Move failed")
	_check(move_scene.hiruko_unit.line == BattleUnitModel.Line.MID and enemy_a.current_hp == enemy_hp_before, "Normal Move caused skill damage or wrong movement")
	_check(not _log_contains(move_scene, "Kick") and not _log_contains(move_scene, "Gut Stab"), "Normal Move invoked a skill")
	await _free_scene(move_scene)

	var incoming_scene := await _new_scene(false)
	if incoming_scene == null:
		return
	_check(incoming_scene.resolve_enemy_turn(), "M4.2 incoming hit no longer resolves")
	_check(incoming_scene.hiruko_unit.current_hp == 41 and incoming_scene.hiruko_state.chains_current == 91, "M4.2 SEALED HP/Chains behavior regressed")
	await _free_scene(incoming_scene)

	var burn_scene := await _new_scene(false)
	if burn_scene == null:
		return
	var burning_enemy := _find_unit(burn_scene, &"enemy_a")
	burn_scene._apply_burn(burning_enemy)
	_check(burn_scene.resolve_enemy_turn(), "M4.3 Burned enemy action no longer resolves")
	_check(burning_enemy.current_hp == 37 and burn_scene._get_burn_ticks(burning_enemy) == 1, "M4.3 Burn tick behavior regressed")
	await _free_scene(burn_scene)


func _test_restart_cleanup() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_set_current(scene, scene.hiruko_unit)
	_check(scene.begin_skill_selection(), "Could not enter Skill menu before Restart")
	scene.restart_battle()
	_check(not scene.selecting_skill and scene.selected_hiruko_skill == scene.HirukoSkill.NONE and scene.valid_skill_targets.is_empty(), "Restart retained Skill menu state")
	_check(scene.current_unit == _find_unit(scene, &"enemy_a") and scene.hiruko_unit.line == BattleUnitModel.Line.MID, "Restart did not restore the approved actor/line fixture")

	_set_current(scene, scene.hiruko_unit)
	_check(scene.begin_skill_selection() and scene.select_hiruko_skill(scene.HirukoSkill.GUT_STAB), "Could not enter skill target selection before Restart")
	scene.restart_battle()
	_check(not scene.selecting_skill and scene.selected_hiruko_skill == scene.HirukoSkill.NONE and scene.valid_skill_targets.is_empty(), "Restart retained skill target selection")
	_check(not scene.select_hiruko_skill_target(&"enemy_a"), "A stale skill executed after Restart")
	_check(scene.hiruko_state.get_state() == HirukoCombatStateModel.State.SEALED and scene.burn_remaining_ticks_by_unit_id.is_empty(), "Restart regressed M4 state reset")
	await _free_scene(scene)


func _test_full_battle_flow() -> void:
	var scene := await _new_scene(true)
	if scene == null:
		return
	var used_basic := false
	var used_move := false
	var used_kick := false
	var used_gut_stab := false
	var safety := 0
	while scene.battle_result == scene.BattleResult.NONE and safety < 160:
		if scene.current_unit == null or scene.current_unit.team == BattleUnitModel.Team.ENEMY:
			await process_frame
		elif scene.current_unit == scene.hiruko_unit and not used_move:
			used_move = scene.begin_move_selection() and scene.select_move_destination(BattleUnitModel.Line.MID)
		elif scene.current_unit == scene.hiruko_unit and not used_kick:
			used_kick = _use_skill(scene, scene.HirukoSkill.KICK, scene._get_valid_attack_targets(scene.hiruko_unit)[0].stable_id)
		elif scene.current_unit == scene.hiruko_unit and not used_gut_stab:
			used_gut_stab = _use_skill(scene, scene.HirukoSkill.GUT_STAB, scene._get_valid_attack_targets(scene.hiruko_unit)[0].stable_id)
		else:
			if scene.begin_attack_selection() and not scene.valid_attack_targets.is_empty():
				used_basic = scene.select_attack_target(scene.valid_attack_targets[0].stable_id) or used_basic
		await process_frame
		safety += 1
	_check(safety < 160 and scene.battle_result != scene.BattleResult.NONE, "Mixed-action M4.4 battle did not reach a terminal result")
	_check(used_basic and used_move and used_kick and used_gut_stab, "Full battle did not exercise Basic, Move, Kick, and Gut Stab")
	_check(scene.current_unit == null and not scene.action_in_progress, "Completed M4.4 battle retained active turn state")
	await _free_scene(scene)


func _test_layout() -> void:
	root.size = Vector2i(1152, 648)
	var scene := await _new_scene(false)
	if scene == null:
		return
	_set_current(scene, scene.hiruko_unit)
	await process_frame
	_check(scene.get_node("Margin/Layout").size.y <= 624.0, "M4.4 root controls exceed safe 1152×648 height")
	_check(_inside_viewport(scene.get_node("%AttackButton")) and _inside_viewport(scene.get_node("%SkillButton")) and _inside_viewport(scene.get_node("%MoveButton")), "Hiruko root actions are outside 1152×648")
	_check(scene.begin_skill_selection(), "Could not open Skill menu for layout test")
	await process_frame
	_check(_inside_viewport(scene.get_node("%KickSkillButton")) and _inside_viewport(scene.get_node("%GutStabSkillButton")) and _inside_viewport(scene.get_node("%SkillBackButton")), "Skill menu is outside 1152×648")
	var battlefield: Control = scene.get_node("Margin/Layout/Battlefield")
	var stable_height := battlefield.size.y
	for index: int in 5:
		scene.party_units[index].line = BattleUnitModel.Line.MID
	scene.party_units[5].line = BattleUnitModel.Line.BACK
	scene._render_battlefield()
	await process_frame
	_check(scene.get_node("%AllyMidUnits").get_child_count() == 5, "Five-card M4.4 line did not render")
	_check(is_equal_approx(battlefield.size.y, stable_height), "M4.4 Skill UI changed fixed battlefield height")
	root.size = Vector2i(1440, 810)
	await process_frame
	_check(scene.get_node("Margin/Layout").size.y <= 786.0, "M4.4 content exceeds safe 1440×810 height")
	await _free_scene(scene)


func _use_skill(scene: Control, skill: int, target_id: StringName) -> bool:
	return (
		scene.begin_skill_selection()
		and scene.select_hiruko_skill(skill)
		and scene.select_hiruko_skill_target(target_id)
	)


func _set_hiruko_state(scene: Control, state: int) -> void:
	match state:
		HirukoCombatStateModel.State.SEALED:
			scene.hiruko_state.set_seals(100, 100)
		HirukoCombatStateModel.State.FLAMING_SWORD:
			scene.hiruko_state.set_seals(0, 100)
		HirukoCombatStateModel.State.LAEVATAIN:
			scene.hiruko_state.set_seals(0, 0)
	scene._render_battlefield()


func _instantiate_scene(automatic_enemies: bool) -> Control:
	var packed_scene: PackedScene = load(SANDBOX_PATH)
	_check(packed_scene != null, "Battle sandbox scene did not load")
	if packed_scene == null:
		return null
	var scene: Control = packed_scene.instantiate()
	scene.automatic_enemy_turns_enabled = automatic_enemies
	return scene


func _new_scene(automatic_enemies: bool) -> Control:
	var scene := _instantiate_scene(automatic_enemies)
	if scene == null:
		return null
	root.add_child(scene)
	active_scene = scene
	_expose_hiruko(scene)
	await process_frame
	return scene


func _free_scene(scene: Control) -> void:
	if active_scene == scene:
		active_scene = null
	scene.queue_free()
	await process_frame


func _set_current(scene: Control, unit: BattleUnit) -> void:
	scene.current_unit = unit
	scene.turn_index = scene.turn_queue.find(unit)
	scene.action_in_progress = false
	scene._clear_action_selection()
	scene._refresh_turn_ui()


func _find_unit(scene: Control, id: StringName) -> BattleUnit:
	for unit: BattleUnit in scene.party_units + scene.enemy_units:
		if unit.stable_id == id:
			return unit
	return null


func _expose_hiruko(scene: Control) -> void:
	scene.hiruko_unit.line = BattleUnitModel.Line.FRONT
	_find_unit(scene, &"party_2").line = BattleUnitModel.Line.MID
	scene._render_battlefield()


func _defeat(unit: BattleUnit) -> void:
	unit.current_hp = 0
	unit.defeated = true


func _contains_unit(units: Array[BattleUnit], target: BattleUnit) -> bool:
	for unit: BattleUnit in units:
		if unit == target:
			return true
	return false


func _log_contains(scene: Control, fragment: String) -> bool:
	for entry: String in scene.combat_log_entries:
		if fragment in entry:
			return true
	return false


func _log_count_containing(scene: Control, fragment: String) -> int:
	var count := 0
	for entry: String in scene.combat_log_entries:
		if fragment in entry:
			count += 1
	return count


func _inside_viewport(control: Control) -> bool:
	var rect := control.get_global_rect()
	return rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= 1152.0 and rect.end.y <= 648.0


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
