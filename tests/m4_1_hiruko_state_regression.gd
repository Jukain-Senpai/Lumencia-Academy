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
	_test_state_model_validation()
	await _test_roster_and_initial_state()
	await _test_debug_progression_and_ui()
	await _test_invalid_wrapper_first()
	await _test_debug_reset()
	await _test_restart()
	await _test_m3_actions_and_defeat()
	await _test_completion_flow()
	await _test_layout_and_five_card_capacity()

	if failures.is_empty():
		print("M4.1 Hiruko state regression suite passed (%d checks)." % checks)
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	push_error("M4.1 Hiruko state regression suite failed: %d failure(s), %d checks." % [failures.size(), checks])
	quit(1)


func _test_state_model_validation() -> void:
	var state := HirukoCombatStateModel.new()
	_check(state.chains_current == 100 and state.wrapper_current == 100, "Seal fixture maxima did not initialize to 100/100")
	_check(state.get_state() == HirukoCombatStateModel.State.SEALED, "Full Seals did not derive SEALED")
	_check(state.set_seals(50, 75), "Valid partial Seal values were rejected")
	_check(state.get_state() == HirukoCombatStateModel.State.SEALED, "Partial intact Seals did not remain SEALED")
	_check(not state.set_seals(50, 0), "Invalid Wrapper-first values were accepted")
	_check(state.chains_current == 50 and state.wrapper_current == 75, "Rejected Seal values mutated state")
	_check(state.set_seals(0, 75), "Valid Chains-broken values were rejected")
	_check(state.get_state() == HirukoCombatStateModel.State.FLAMING_SWORD, "Chains-broken values did not derive FLAMING_SWORD")
	_check(state.set_seals(0, 0), "Valid both-broken values were rejected")
	_check(state.get_state() == HirukoCombatStateModel.State.LAEVATAIN, "Both-broken values did not derive LAEVATAIN")


func _test_roster_and_initial_state() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_check(scene.party_units.size() == 6, "Party roster no longer contains exactly six combatants")
	_check(scene.enemy_units.size() == 4, "Enemy roster size changed")
	var hiruko_count := 0
	var other_names: Array[String] = []
	for unit: BattleUnit in scene.party_units:
		if unit.display_name == "Hiruko":
			hiruko_count += 1
		else:
			other_names.append(unit.display_name)
	_check(hiruko_count == 1, "Party roster must contain exactly one Hiruko")
	_check(other_names == ["Jukain", "Party 3", "Party 4", "Party 5", "Party 6"], "The M5.1 roster no longer preserves Hiruko plus Jukain and four generics")
	_check(_ids(scene.enemy_units) == [&"enemy_a", &"enemy_b", &"enemy_c", &"enemy_d"], "Enemy roster identity changed")
	var hiruko: BattleUnit = scene.hiruko_unit
	_check(hiruko.stable_id == &"party_1", "Hiruko did not replace Party 1's stable slot")
	_check(hiruko.current_hp == 44 and hiruko.max_hp == 44 and hiruko.atk == 10 and hiruko.spd == 14, "Hiruko did not retain Party 1's M3 stats")
	_check(hiruko.line == BattleUnitModel.Line.MID and not hiruko.defeated, "Hiruko did not start living in the approved M5 Mid formation")
	_check(scene.hiruko_state.chains_current == 100 and scene.hiruko_state.wrapper_current == 100, "Initial Seals are not full")
	_check(scene.hiruko_state.get_state() == HirukoCombatStateModel.State.SEALED, "Initial state is not SEALED")
	_check("State: SEALED" in _inspector_text(scene), "Initial inspector state disagrees with authoritative state")
	_check("Seal [Chains]: 100/100" in _inspector_text(scene) and "Seal [Wrapper]: 100/100" in _inspector_text(scene), "Initial inspector Seal values disagree with authoritative values")
	_check(_scene_has_text(scene, "Hiruko") and "State: SEALED" in _inspector_text(scene), "Hiruko card and inspector do not visibly identify Hiruko and SEALED")
	await _free_scene(scene)


func _test_debug_progression_and_ui() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_check(scene.hiruko_state.set_seals(50, 75), "Partial Seal values were rejected by the UI fixture")
	scene._render_battlefield()
	_check("Seal [Chains]: 50/100" in _inspector_text(scene), "Partial Chains UI disagrees with authoritative value")
	_check("Seal [Wrapper]: 75/100" in _inspector_text(scene), "Partial Wrapper UI disagrees with authoritative value")
	_check("State: SEALED" in _inspector_text(scene), "Partial intact Seals did not display SEALED")
	scene.hiruko_state.reset()
	scene._render_battlefield()
	var before := _combat_snapshot(scene)
	_check(scene.debug_break_chains(), "Break Chains debug path was rejected")
	_check(scene.hiruko_state.chains_current == 0 and scene.hiruko_state.wrapper_current == 100, "Break Chains changed incorrect Seal values")
	_check(scene.hiruko_state.get_state() == HirukoCombatStateModel.State.FLAMING_SWORD, "Break Chains did not derive FLAMING_SWORD")
	_check("State: FLAMING SWORD" in _inspector_text(scene), "FLAMING SWORD UI disagrees with state")
	_check("Seal [Chains]: BROKEN" in _inspector_text(scene), "Chains UI did not show broken")
	_check("Seal [Wrapper]: 100/100" in _inspector_text(scene), "Wrapper UI changed when Chains broke")
	_check(_combat_snapshot(scene) == before, "Break Chains changed HP, line, turn, queue, or battle result")
	_check(scene.combat_log_entries.has("Seal [Chains] broken.") and scene.combat_log_entries.has("Hiruko entered FLAMING SWORD."), "Break Chains feedback was not logged")

	before = _combat_snapshot(scene)
	_check(scene.debug_break_wrapper(), "Break Wrapper was rejected after Chains broke")
	_check(scene.hiruko_state.chains_current == 0 and scene.hiruko_state.wrapper_current == 0, "Break Wrapper changed incorrect Seal values")
	_check(scene.hiruko_state.get_state() == HirukoCombatStateModel.State.LAEVATAIN, "Break Wrapper did not derive LAEVATAIN")
	_check("State: LAEVATAIN" in _inspector_text(scene), "LAEVATAIN UI disagrees with state")
	_check("Seal [Wrapper]: BROKEN" in _inspector_text(scene), "Wrapper UI did not show broken")
	_check(_combat_snapshot(scene) == before, "Break Wrapper changed HP, line, turn, queue, or battle result")
	_check(scene.combat_log_entries.has("Seal [Wrapper] broken.") and scene.combat_log_entries.has("Hiruko entered LAEVATAIN."), "Break Wrapper feedback was not logged")
	await _free_scene(scene)


func _test_invalid_wrapper_first() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	var before := _combat_snapshot(scene)
	_check(not scene.debug_break_wrapper(), "Wrapper-first debug transition was accepted")
	_check(scene.hiruko_state.chains_current == 100 and scene.hiruko_state.wrapper_current == 100, "Wrapper-first attempt mutated Seals")
	_check(scene.hiruko_state.get_state() == HirukoCombatStateModel.State.SEALED, "Wrapper-first attempt changed derived state")
	_check(_combat_snapshot(scene) == before, "Wrapper-first attempt changed combat state")
	_check(scene.combat_log_entries.has("Cannot break Seal [Wrapper] while Seal [Chains] is intact."), "Wrapper-first rejection was not clearly logged")
	await _free_scene(scene)


func _test_debug_reset() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	scene.debug_break_chains()
	scene.debug_break_wrapper()
	var before := _combat_snapshot(scene)
	_check(scene.debug_reset_hiruko(), "Reset Hiruko debug path failed")
	_check(scene.hiruko_state.chains_current == 100 and scene.hiruko_state.wrapper_current == 100, "Debug reset did not restore both Seals")
	_check(scene.hiruko_state.get_state() == HirukoCombatStateModel.State.SEALED, "Debug reset did not derive SEALED")
	_check("State: SEALED" in _inspector_text(scene), "Debug reset left stale state UI")
	_check(_combat_snapshot(scene) == before, "Debug reset changed combat state")
	await _free_scene(scene)


func _test_restart() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	scene.debug_break_chains()
	scene.debug_break_wrapper()
	scene.advance_turn()
	var original: BattleUnit = scene.hiruko_unit
	original.current_hp = 3
	original.line = BattleUnitModel.Line.MID
	original.defeated = true
	scene.restart_battle()
	await process_frame
	_check(scene.hiruko_unit != original, "Restart retained the old Hiruko runtime object")
	_check(scene.hiruko_unit.display_name == "Hiruko" and scene.hiruko_unit.current_hp == 44, "Restart did not restore Hiruko identity and HP")
	_check(scene.hiruko_unit.atk == 10 and scene.hiruko_unit.spd == 14 and scene.hiruko_unit.line == BattleUnitModel.Line.MID, "Restart did not restore Hiruko fixture stats and approved line")
	_check(not scene.hiruko_unit.defeated, "Restart retained Hiruko defeat")
	_check(scene.hiruko_state.chains_current == 100 and scene.hiruko_state.wrapper_current == 100, "Restart did not restore full Seals")
	_check(scene.hiruko_state.get_state() == HirukoCombatStateModel.State.SEALED and "State: SEALED" in _inspector_text(scene), "Restart did not restore authoritative and visible SEALED state")
	_check(scene.party_units.size() == 6 and scene.get_node("%AllyFrontUnits").get_child_count() == 1, "Restart duplicated or lost party cards")
	await _free_scene(scene)


func _test_m3_actions_and_defeat() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	var hiruko: BattleUnit = scene.hiruko_unit
	scene.jukain_unit.line = BattleUnitModel.Line.MID
	_check(scene.resolve_enemy_turn(), "Enemy could not attack Hiruko through the M3 path")
	_check(hiruko.current_hp == 41, "Hiruko did not receive the superseding M4.2 SEALED damage")
	_check(scene.hiruko_state.chains_current == 91, "Enemy hit did not apply raw damage to Chains")
	_check(scene.current_unit == hiruko, "Hiruko did not receive her normal M3 turn")
	var enemy_a := _find_unit(scene, &"enemy_a")
	_check(scene.begin_attack_selection() and scene.select_attack_target(&"enemy_a"), "Hiruko could not use Basic Attack")
	_check(enemy_a.current_hp == 32, "SEALED Hiruko Basic Attack did not deal base ATK")

	scene.restart_battle()
	scene.advance_turn()
	hiruko = scene.hiruko_unit
	_check(scene.begin_move_selection() and scene.select_move_destination(BattleUnitModel.Line.FRONT), "Hiruko could not use Move")
	_check(hiruko.line == BattleUnitModel.Line.FRONT, "Hiruko Move did not change semantic line")

	scene.restart_battle()
	hiruko = scene.hiruko_unit
	hiruko.current_hp = 1
	scene.jukain_unit.line = BattleUnitModel.Line.MID
	_check(scene.resolve_enemy_turn(), "Enemy lethal attack against Hiruko failed")
	_check(hiruko.current_hp == 0 and hiruko.defeated, "Hiruko did not follow normal zero-HP defeat behavior")
	_check(not scene._is_living(hiruko), "Defeated Hiruko still occupied a semantic combat line")
	await _free_scene(scene)


func _test_completion_flow() -> void:
	var scene := await _new_scene(true)
	if scene == null:
		return
	var safety := 0
	while scene.battle_result == scene.BattleResult.NONE and safety < 100:
		if scene.current_unit == null or scene.current_unit.team == BattleUnitModel.Team.ENEMY:
			await process_frame
		else:
			if not scene.begin_attack_selection() or scene.valid_attack_targets.is_empty():
				break
			scene.select_attack_target(scene.valid_attack_targets[0].stable_id)
			await process_frame
		safety += 1
	_check(safety < 100 and scene.battle_result != scene.BattleResult.NONE, "Battle with Hiruko did not complete through the M3 loop")
	var result: int = scene.battle_result
	scene.restart_battle()
	await process_frame
	_check(result != scene.BattleResult.NONE and scene.battle_result == scene.BattleResult.NONE, "Restart did not clear completed battle result")
	_check(scene.hiruko_state.get_state() == HirukoCombatStateModel.State.SEALED, "Restart after completion did not restore SEALED")
	await _free_scene(scene)


func _test_layout_and_five_card_capacity() -> void:
	root.size = Vector2i(1152, 648)
	var scene := await _new_scene(false)
	if scene == null:
		return
	await process_frame
	_check(scene.get_node("Margin/Layout").size.y <= 624.0, "M4.1 controls exceed the safe 1152x648 content height (%s px)" % scene.get_node("Margin/Layout").size.y)
	_check(_inside_viewport(scene.get_node("%ResetHirukoButton")), "Hiruko debug controls are outside the 1152x648 viewport")
	var battlefield: Control = scene.get_node("Margin/Layout/Battlefield")
	var stable_height := battlefield.size.y
	for index: int in 5:
		scene.party_units[index].line = BattleUnitModel.Line.MID
	scene.party_units[5].line = BattleUnitModel.Line.BACK
	scene._render_battlefield()
	await process_frame
	_check(scene.get_node("%AllyMidUnits").get_child_count() == 5, "Five-card party line did not render all cards")
	_check(is_equal_approx(battlefield.size.y, stable_height), "Five-card line changed fixed battlefield height")
	_check(scene.get_node("Margin/Layout").size.y <= 624.0, "Five-card line pushed M4.1 below 1152x648 (%s px)" % scene.get_node("Margin/Layout").size.y)
	root.size = Vector2i(1440, 810)
	await process_frame
	_check(scene.get_node("Margin/Layout").size.y <= 786.0, "M4.1 layout exceeds the safe 1440x810 height")
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


func _free_scene(scene: Control) -> void:
	if active_scene == scene:
		active_scene = null
	scene.queue_free()
	await process_frame


func _combat_snapshot(scene: Control) -> Dictionary:
	return {
		"hp": scene.hiruko_unit.current_hp,
		"line": scene.hiruko_unit.line,
		"defeated": scene.hiruko_unit.defeated,
		"round": scene.round_number,
		"turn_index": scene.turn_index,
		"current": scene.current_unit.stable_id if scene.current_unit != null else &"",
		"queue": _ids(scene.turn_queue),
		"result": scene.battle_result,
		"enemy_pending": scene.enemy_action_pending,
	}


func _find_unit(scene: Control, id: StringName) -> BattleUnit:
	for unit: BattleUnit in scene.party_units + scene.enemy_units:
		if unit.stable_id == id:
			return unit
	return null


func _ids(units: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for unit: BattleUnit in units:
		result.append(unit.stable_id)
	return result


func _scene_has_text(node: Node, expected: String) -> bool:
	if node is Label and expected in node.text:
		return true
	for child: Node in node.get_children():
		if _scene_has_text(child, expected):
			return true
	return false


func _inspector_text(scene: Control) -> String:
	return scene.get_node("%InspectorDetailsLabel").text


func _inside_viewport(control: Control) -> bool:
	var rect := control.get_global_rect()
	return rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= 1152.0 and rect.end.y <= 648.0


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
