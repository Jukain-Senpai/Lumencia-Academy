extends SceneTree

const BattleUnitModel := preload("res://scripts/battle/battle_unit.gd")
const HirukoCombatStateModel := preload("res://scripts/battle/hiruko_combat_state.gd")
const JukainCombatStateModel := preload("res://scripts/battle/jukain_combat_state.gd")
const JukainPrescriptStateModel := preload("res://scripts/battle/jukain_prescript_state.gd")
const SANDBOX_PATH := "res://scenes/battle/battle_sandbox.tscn"

var failures: Array[String] = []
var checks := 0
var active_scene: Control


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_prescript_model()
	await _test_inspector_browsing_and_controls()
	await _test_inspector_live_refresh_and_restart()
	await _test_obey_confirmation_and_pipeline()
	await _test_exploit_route()
	await _test_defy_karma_and_replacement()
	await _test_targeting_and_generic_guards()
	await _test_victory_defeat_and_layout()

	if failures.is_empty():
		print("M5.2 Prescript and Character Inspector regression suite passed (%d checks)." % checks)
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	push_error("M5.2 regression suite failed: %d failure(s), %d checks." % [failures.size(), checks])
	quit(1)


func _test_prescript_model() -> void:
	var state := JukainPrescriptStateModel.new()
	state.reset(44)
	_check(JukainPrescriptStateModel.ORIGINAL_REQUIREMENT == "Make Hiruko lose HP before your next turn.", "Original Prescript text changed")
	_check(JukainPrescriptStateModel.REPLACEMENT_REQUIREMENT == "Take damage from an enemy.", "Replacement text changed")
	_check(state.phase == JukainPrescriptStateModel.Phase.ORIGINAL_ACTIVE and state.karma_stacks == 0, "Prescript model did not reset fresh")
	_check(state.on_jukain_turn_started(&"turn_a", 44) == &"activated", "First Jukain turn did not activate the deadline")
	_check(state.on_jukain_turn_started(&"turn_a", 44) == &"none", "Same Jukain turn token re-evaluated the deadline")
	_check(state.phase == JukainPrescriptStateModel.Phase.ORIGINAL_ACTIVE, "Prescript failed during its first action window")
	_check(state.on_jukain_turn_started(&"turn_b", 44) == &"defied", "Next Jukain turn did not Defy")
	_check(state.karma_stacks == 1 and state.deadline_evaluation_count == 1, "Defy did not add exactly one Karma/evaluation")
	_check(state.on_jukain_turn_started(&"turn_c", 44) == &"none" and state.karma_stacks == 1, "Resolved deadline evaluated again")
	var expected_damage := [5, 6, 7, 8]
	for stacks: int in 4:
		state.karma_stacks = stacks
		_check(state.get_enemy_damage_to_jukain(5) == expected_damage[stacks], "Karma ×%.2f damage is incorrect" % (1.0 + stacks * 0.2))


func _test_inspector_browsing_and_controls() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_check(scene.selected_inspector_unit_id == &"party_1", "Battle did not default inspector to Hiruko")
	_check(scene.get_node("%InspectorSelectionLabel").text == "INSPECTING: HIRUKO", "Initial inspector heading is not Hiruko")
	_check("State: SEALED" in _details(scene) and "Seal [Chains]: 100/100" in _details(scene), "Hiruko inspector lacks state/Seal content")
	_check(scene.get_node("%BreakChainsButton").visible and not scene.get_node("%UnlockJukainButton").visible, "Hiruko inspector debug controls are incorrect")
	var before := _combat_snapshot(scene)
	var prescript_before := _prescript_snapshot(scene)
	_click_card(scene, &"party_2")
	_check(scene.selected_inspector_unit_id == &"party_2", "Neutral Jukain card click did not select inspector")
	_check(scene.get_node("%InspectorSelectionLabel").text == "INSPECTING: JUKAIN", "Inspector did not switch to Jukain")
	_check("State: LOCKED" in _details(scene) and "Effective ATK 1" in _details(scene) and "Real ATK 9" in _details(scene), "Jukain inspector lacks M5.1 state/ATK content")
	_check(JukainPrescriptStateModel.ORIGINAL_REQUIREMENT in _details(scene) and "KARMA: 0" in _details(scene), "Jukain inspector lacks active Prescript/Karma")
	_check(scene.get_node("%UnlockJukainButton").visible and not scene.get_node("%BreakChainsButton").visible, "Jukain inspector debug controls are incorrect")
	_check(_combat_snapshot(scene) == before, "Inspector switching changed combat state")
	_check(_prescript_snapshot(scene) == prescript_before, "Inspector switching changed Prescript state")

	_click_card(scene, &"party_1")
	_check(scene.selected_inspector_unit_id == &"party_1" and "HIRUKO" in _details(scene), "Neutral Hiruko click did not restore Hiruko inspector")
	_click_card(scene, &"party_3")
	_check(scene.selected_inspector_unit_id == &"party_3", "Generic allied card did not select inspector")
	_check("PARTY 3" in _details(scene) and "ATK 8" in _details(scene) and "Status: ALIVE" in _details(scene), "Generic inspector content is incomplete")
	_check(not scene.get_node("%BreakChainsButton").visible and not scene.get_node("%UnlockJukainButton").visible, "Generic inspector exposes character-specific debug controls")
	_check(scene.get_node_or_null("%CharacterInspector") != null, "Shared Character Inspector is missing")
	_check(scene.get_node_or_null("Margin/Layout/TurnDebugPanel/Layout/HirukoDebug") == null and scene.get_node_or_null("Margin/Layout/TurnDebugPanel/Layout/JukainDebug") == null, "Permanent character-specific panels still exist")
	await _free_scene(scene)


func _test_inspector_live_refresh_and_restart() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_check(scene.debug_break_chains(), "Hiruko debug transition failed")
	_check("State: FLAMING SWORD" in _details(scene) and "Seal [Chains]: BROKEN" in _details(scene), "Selected Hiruko inspector did not refresh state")
	_click_card(scene, &"party_2")
	_check(scene.debug_unlock_jukain(), "Jukain DEBUG Unlock failed")
	_check("State: UNLOCKED" in _details(scene) and "Effective ATK 9" in _details(scene), "Selected Jukain inspector did not refresh unlock")
	_check(scene.jukain_prescript.phase == JukainPrescriptStateModel.Phase.ORIGINAL_ACTIVE, "DEBUG Unlock incorrectly resolved Prescript")

	_start_jukain_turn(scene)
	scene.round_number += 1
	_check(scene._process_jukain_turn_start() == &"defied", "Controlled next Jukain turn did not Defy")
	_check("ORIGINAL: DEFIED" in _details(scene) and "KARMA: 1" in _details(scene) and JukainPrescriptStateModel.REPLACEMENT_REQUIREMENT in _details(scene), "Jukain inspector did not refresh Defy/Karma/replacement")
	var evaluations_before: int = scene.jukain_prescript.deadline_evaluation_count
	scene._refresh_character_inspector()
	scene._render_battlefield()
	_check(scene.jukain_prescript.deadline_evaluation_count == evaluations_before, "Inspector refresh re-evaluated the deadline")

	scene.ally_attack_confirmation_target_id = &"party_1"
	scene.restart_battle()
	await process_frame
	_check(scene.selected_inspector_unit_id == &"party_1" and scene.get_node("%InspectorSelectionLabel").text == "INSPECTING: HIRUKO", "Restart did not reset inspector to rebuilt Hiruko")
	_check(scene.jukain_prescript.phase == JukainPrescriptStateModel.Phase.ORIGINAL_ACTIVE and scene.jukain_prescript.karma_stacks == 0, "Restart retained stale Prescript/Karma")
	_check(scene.ally_attack_confirmation_target_id == &"" and scene.get_node("%BreakChainsButton").visible and not scene.get_node("%UnlockJukainButton").visible, "Restart retained stale confirmation or controls")
	await _free_scene(scene)


func _test_obey_confirmation_and_pipeline() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_click_card(scene, &"party_2")
	_start_jukain_turn(scene)
	_check(scene.jukain_prescript.phase == JukainPrescriptStateModel.Phase.ORIGINAL_ACTIVE, "Prescript prematurely failed at activation")
	_check(scene.jukain_state.get_state() == JukainCombatStateModel.State.LOCKED and scene.jukain_state.get_effective_atk(scene.jukain_unit.atk) == 1, "Jukain is not Locked/effective ATK 1")
	var before := _combat_snapshot(scene)
	var hiruko_hp_before: int = scene.hiruko_unit.current_hp
	_check(scene.begin_attack_selection(), "Jukain could not begin Attack selection")
	_click_card(scene, &"party_1")
	_check(scene.ally_attack_confirmation_target_id == &"party_1", "Hiruko target click did not open ally confirmation")
	_check(scene.selected_inspector_unit_id == &"party_2", "Targeting click incorrectly switched inspector to Hiruko")
	_check(scene.hiruko_unit.current_hp == hiruko_hp_before and scene.current_unit == scene.jukain_unit, "Target click dealt damage or consumed the turn before confirmation")
	_check(scene.cancel_action_selection(), "Ally confirmation Cancel failed")
	_check(scene.ally_attack_confirmation_target_id == &"" and scene.selecting_target, "Cancel did not return to target selection")
	_check(scene.hiruko_unit.current_hp == hiruko_hp_before and scene.jukain_prescript.phase == JukainPrescriptStateModel.Phase.ORIGINAL_ACTIVE, "Cancel changed HP or Prescript progress")
	_check(_combat_snapshot(scene) == before, "Confirmation/Cancel changed turn, queue, line, HP, or result")
	_click_card(scene, &"party_1")
	_check(scene.confirm_ally_attack(), "Confirmed Jukain → Hiruko attack did not resolve")
	_check(hiruko_hp_before - scene.hiruko_unit.current_hp == 1, "Confirmed Locked attack did not cause authoritative 1 HP loss")
	_check(scene.hiruko_state.chains_current == 99 and scene.hiruko_state.wrapper_current == 100, "Obey bypassed Hiruko's M4 Seal pipeline")
	_check(scene.jukain_prescript.phase == JukainPrescriptStateModel.Phase.RESOLVED_OBEY and scene.jukain_prescript.get_route_label() == "OBEY", "Obey route did not resolve")
	_check(scene.jukain_prescript.karma_stacks == 0, "Obey incorrectly added Karma")
	_check(scene.jukain_state.get_state() == JukainCombatStateModel.State.UNLOCKED and scene.jukain_state.get_effective_atk(scene.jukain_unit.atk) == 9 and scene.jukain_unit.atk == 9, "Obey did not apply the M5.3 unlock while preserving real ATK")
	_check(_log_contains(scene, "Prescript resolved: OBEY."), "Obey resolution was not logged")
	await _free_scene(scene)


func _test_exploit_route() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_start_jukain_turn(scene)
	_check(scene.jukain_unit.line == BattleUnitModel.Line.FRONT and scene.hiruko_unit.line == BattleUnitModel.Line.MID, "Approved Prescript formation is incorrect")
	_check(scene.begin_move_selection() and scene.select_move_destination(BattleUnitModel.Line.MID), "Jukain could not Move Front → Mid")
	_check(scene.jukain_prescript.exploit_setup, "Jukain Move did not mark exploit setup")
	_check(scene.jukain_prescript.phase == JukainPrescriptStateModel.Phase.ORIGINAL_ACTIVE, "Move alone resolved the Prescript")
	_check(scene.current_unit.stable_id == &"enemy_c", "Controlled queue did not advance to deterministic Enemy C")
	var hp_before: int = scene.hiruko_unit.current_hp
	_check(scene.resolve_enemy_turn(), "Enemy C did not resolve its exposed-target attack")
	_check(scene.hiruko_unit.current_hp < hp_before, "Enemy did not actually damage Hiruko")
	_check(scene.jukain_prescript.phase == JukainPrescriptStateModel.Phase.RESOLVED_EXPLOIT, "Exploit route did not resolve")
	_check(scene.jukain_prescript.karma_stacks == 0, "Exploit incorrectly added Karma")
	_check(scene.jukain_state.get_state() == JukainCombatStateModel.State.UNLOCKED, "Exploit did not apply the M5.3 unlock")
	_check(_log_contains(scene, "Hiruko is exposed.") and _log_contains(scene, "Prescript resolved: EXPLOIT."), "Exploit log is incomplete")
	await _free_scene(scene)


func _test_defy_karma_and_replacement() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_start_jukain_turn(scene)
	var hiruko_hp: int = scene.hiruko_unit.current_hp
	scene.round_number += 1
	_check(scene._process_jukain_turn_start() == &"defied", "Deadline did not Defy on next real Jukain turn")
	_check(scene.hiruko_unit.current_hp == hiruko_hp, "Defy altered Hiruko HP")
	_check(scene.jukain_prescript.phase == JukainPrescriptStateModel.Phase.DEFY_REPLACEMENT_ACTIVE and scene.jukain_prescript.karma_stacks == 1, "Defy did not activate replacement with Karma 1")
	_check(not scene.jukain_prescript.is_resolved(), "Defy immediately completed replacement")
	var evaluation_count: int = scene.jukain_prescript.deadline_evaluation_count
	_check(scene._process_jukain_turn_start() == &"none" and scene.jukain_prescript.deadline_evaluation_count == evaluation_count, "Deadline evaluated twice on the same turn")

	var hp_before: int = scene.jukain_unit.current_hp
	scene._apply_burn(scene.jukain_unit)
	_check(scene._process_burn_tick(scene.jukain_unit), "Controlled Jukain Burn tick failed")
	_check(scene.jukain_unit.current_hp == hp_before - 5 and scene.jukain_prescript.phase == JukainPrescriptStateModel.Phase.DEFY_REPLACEMENT_ACTIVE, "Burn incorrectly completed replacement")
	scene.jukain_unit.current_hp = hp_before
	scene._clear_burn(scene.jukain_unit)
	var enemy_a := _find_unit(scene, &"enemy_a")
	_set_current(scene, enemy_a)
	hp_before = scene.jukain_unit.current_hp
	_check(scene.resolve_enemy_turn(), "Enemy could not attack Jukain for replacement")
	_check(hp_before - scene.jukain_unit.current_hp == 11, "Karma 1 did not apply ceiling-scaled ×1.20 enemy damage")
	_check(scene.jukain_prescript.phase == JukainPrescriptStateModel.Phase.RESOLVED_DEFY, "Enemy HP loss did not complete DEFY replacement")
	_check(scene.jukain_prescript.karma_stacks == 1, "Karma did not persist after replacement")
	_check(scene.jukain_state.get_state() == JukainCombatStateModel.State.UNLOCKED, "DEFY replacement did not apply the M5.3 unlock")
	_check(_log_contains(scene, "Replacement complete.") and _log_contains(scene, "Prescript resolved: DEFY."), "DEFY completion log is incomplete")

	scene = await _replace_scene(scene, false)
	_start_jukain_turn(scene)
	scene.round_number += 1
	scene._process_jukain_turn_start()
	var enemy := _find_unit(scene, &"enemy_a")
	_set_current(scene, scene.jukain_unit)
	var enemy_hp_before: int = enemy.current_hp
	_check(scene.begin_attack_selection() and scene.select_attack_target(enemy.stable_id), "Karma Jukain outgoing Basic Attack failed")
	_check(enemy_hp_before - enemy.current_hp == 1, "Karma modified Jukain outgoing Locked damage")
	await _free_scene(scene)


func _test_targeting_and_generic_guards() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	var party_3 := _find_unit(scene, &"party_3")
	_set_current(scene, party_3)
	_check(scene.begin_attack_selection(), "Generic Party 3 could not begin Attack")
	_click_card(scene, &"party_1")
	_check(scene.selected_inspector_unit_id == &"party_1" and scene.hiruko_unit.current_hp == 44 and scene.current_unit == party_3, "Generic unit gained friendly fire or targeting changed inspector")
	_check(scene.ally_attack_confirmation_target_id == &"", "Generic ally click opened Jukain confirmation")
	scene.cancel_action_selection()

	_set_current(scene, scene.hiruko_unit)
	var enemy_a := _find_unit(scene, &"enemy_a")
	var enemy_hp_before: int = enemy_a.current_hp
	_check(scene.begin_skill_selection() and scene.select_hiruko_skill(scene.HirukoSkill.KICK), "Hiruko Skill targeting did not open")
	_click_card(scene, &"enemy_a")
	_check(enemy_a.current_hp == enemy_hp_before - 10, "Inspector integration broke Hiruko Skill targeting")
	await _free_scene(scene)


func _test_victory_defeat_and_layout() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	for enemy: BattleUnit in scene.enemy_units:
		enemy.current_hp = 0
		enemy.defeated = true
	_check(scene._check_battle_result() and scene.battle_result == scene.BattleResult.VICTORY, "Victory no longer resolves")
	await _free_scene(scene)
	scene = await _new_scene(false)
	if scene == null:
		return
	for ally: BattleUnit in scene.party_units:
		ally.current_hp = 0
		ally.defeated = true
	_check(scene._check_battle_result() and scene.battle_result == scene.BattleResult.DEFEAT, "Defeat no longer resolves")
	await _free_scene(scene)

	root.size = Vector2i(1152, 648)
	scene = await _new_scene(false)
	if scene == null:
		return
	await process_frame
	_check(scene.get_node("Margin/Layout").size.y <= 624.0, "M5.2 content exceeds safe 1152×648 height")
	_check(_inside_viewport(scene.get_node("%CharacterInspector")) and _inside_viewport(scene.get_node("%CombatLog")), "Inspector or Combat Log is outside 1152×648")
	var battlefield: Control = scene.get_node("Margin/Layout/Battlefield")
	var stable_height := battlefield.size.y
	for index: int in 5:
		scene.party_units[index].line = BattleUnitModel.Line.MID
	scene.party_units[5].line = BattleUnitModel.Line.BACK
	scene._render_battlefield()
	await process_frame
	_check(scene.get_node("%AllyMidUnits").get_child_count() == 5, "Five-card line did not render")
	_check(is_equal_approx(battlefield.size.y, stable_height), "Five-card line changed battlefield height")
	root.size = Vector2i(1440, 810)
	await process_frame
	_check(scene.get_node("Margin/Layout").size.y <= 786.0, "M5.2 content exceeds safe 1440×810 height")
	await _free_scene(scene)


func _new_scene(automatic_enemies: bool) -> Control:
	var packed_scene: PackedScene = load(SANDBOX_PATH)
	_check(packed_scene != null, "Battle sandbox scene did not load")
	if packed_scene == null:
		return null
	var scene: Control = packed_scene.instantiate()
	scene.automatic_enemy_turns_enabled = automatic_enemies
	root.add_child(scene)
	active_scene = scene
	await process_frame
	return scene


func _replace_scene(scene: Control, automatic_enemies: bool) -> Control:
	await _free_scene(scene)
	return await _new_scene(automatic_enemies)


func _free_scene(scene: Control) -> void:
	if active_scene == scene:
		active_scene = null
	scene.queue_free()
	await process_frame


func _start_jukain_turn(scene: Control) -> void:
	_set_current(scene, scene.jukain_unit)
	_check(scene._process_jukain_turn_start() == &"activated", "Jukain's first real turn did not activate Prescript")


func _set_current(scene: Control, unit: BattleUnit) -> void:
	scene.current_unit = unit
	scene.turn_index = scene.turn_queue.find(unit)
	scene._clear_action_selection()
	scene._refresh_turn_ui()


func _click_card(scene: Control, unit_id: StringName) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	scene._on_unit_card_input(event, unit_id)


func _find_unit(scene: Control, id: StringName) -> BattleUnit:
	for unit: BattleUnit in scene.party_units + scene.enemy_units:
		if unit.stable_id == id:
			return unit
	return null


func _details(scene: Control) -> String:
	return scene.get_node("%InspectorDetailsLabel").text


func _combat_snapshot(scene: Control) -> Dictionary:
	return {
		"party_hp": scene.party_units.map(func(unit: BattleUnit) -> int: return unit.current_hp),
		"enemy_hp": scene.enemy_units.map(func(unit: BattleUnit) -> int: return unit.current_hp),
		"lines": scene.party_units.map(func(unit: BattleUnit) -> int: return unit.line),
		"round": scene.round_number,
		"turn_index": scene.turn_index,
		"current": scene.current_unit.stable_id if scene.current_unit != null else &"",
		"queue": _ids(scene.turn_queue),
		"result": scene.battle_result,
		"enemy_pending": scene.enemy_action_pending,
	}


func _prescript_snapshot(scene: Control) -> Dictionary:
	return {
		"phase": scene.jukain_prescript.phase,
		"karma": scene.jukain_prescript.karma_stacks,
		"token": scene.jukain_prescript.activation_turn_token,
		"baseline": scene.jukain_prescript.hiruko_baseline_hp,
		"exploit": scene.jukain_prescript.exploit_setup,
		"evaluations": scene.jukain_prescript.deadline_evaluation_count,
	}


func _ids(units: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for unit: BattleUnit in units:
		result.append(unit.stable_id)
	return result


func _log_contains(scene: Control, fragment: String) -> bool:
	for entry: String in scene.combat_log_entries:
		if fragment in entry:
			return true
	return false


func _inside_viewport(control: Control) -> bool:
	var rect := control.get_global_rect()
	return rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= 1152.0 and rect.end.y <= 648.0


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
