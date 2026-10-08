extends SceneTree

const BattleUnitModel := preload("res://scripts/battle/battle_unit.gd")
const HirukoCombatStateModel := preload("res://scripts/battle/hiruko_combat_state.gd")
const JukainCombatStateModel := preload("res://scripts/battle/jukain_combat_state.gd")
const SANDBOX_PATH := "res://scenes/battle/battle_sandbox.tscn"

var failures: Array[String] = []
var checks := 0
var active_scene: Control


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_state_model()
	await _test_roster_initial_state_and_ui()
	await _test_locked_and_unlocked_basic_attack()
	await _test_debug_controls_and_restart()
	await _test_generic_and_hiruko_regression()
	await _test_absent_future_mechanics()
	await _test_victory_and_defeat()
	await _test_layout_and_five_card_capacity()

	if failures.is_empty():
		print("M5.1 Jukain state regression suite passed (%d checks)." % checks)
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	push_error("M5.1 Jukain state regression suite failed: %d failure(s), %d checks." % [failures.size(), checks])
	quit(1)


func _test_state_model() -> void:
	var state := JukainCombatStateModel.new()
	_check(state.get_state() == JukainCombatStateModel.State.LOCKED, "Jukain state model did not start LOCKED")
	_check(state.get_effective_atk(9) == 1, "LOCKED effective ATK is not exactly 1")
	_check(state.debug_unlock(), "DEBUG Unlock did not transition to UNLOCKED")
	_check(state.get_state() == JukainCombatStateModel.State.UNLOCKED, "DEBUG Unlock state is not UNLOCKED")
	_check(state.get_effective_atk(9) == 9, "UNLOCKED effective ATK does not equal real ATK")
	state.reset()
	_check(state.get_state() == JukainCombatStateModel.State.LOCKED and state.get_effective_atk(9) == 1, "State reset did not restore LOCKED effective ATK 1")


func _test_roster_initial_state_and_ui() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_check(scene.party_units.size() == 6, "Party roster no longer contains six combatants")
	_check(scene.hiruko_unit.display_name == "Hiruko", "Hiruko is missing from the roster")
	_check(scene.jukain_unit.display_name == "Jukain", "Jukain is missing from the roster")
	_check(scene.jukain_unit.stable_id == &"party_2", "Jukain did not preserve stable Party 2 ID")
	_check(_ids(scene.party_units) == [&"party_1", &"party_2", &"party_3", &"party_4", &"party_5", &"party_6"], "Party stable IDs were renumbered")
	_check(_display_names(scene.party_units) == ["Hiruko", "Jukain", "Party 3", "Party 4", "Party 5", "Party 6"], "Roster is not Hiruko, Jukain, and four generics")
	_check(scene.jukain_unit.current_hp == 40 and scene.jukain_unit.max_hp == 40 and scene.jukain_unit.atk == 9 and scene.jukain_unit.spd == 11, "Jukain did not preserve Party 2 fixture stats")
	_check(scene.jukain_unit.line == BattleUnitModel.Line.FRONT, "Jukain did not preserve Party 2's initial line")
	_check(scene.jukain_state.get_state() == JukainCombatStateModel.State.LOCKED, "Jukain did not start LOCKED")
	_check(scene.jukain_state.get_effective_atk(scene.jukain_unit.atk) == 1, "Initial effective ATK is not 1")
	_check(scene.jukain_unit.atk == 9, "Initial real ATK was overwritten")
	_check(scene.get_node("%JukainStateLabel").text == "LOCKED", "Visible Jukain state does not say LOCKED")
	_check(scene.get_node("%JukainAtkLabel").text == "Effective ATK 1  •  Real ATK 9", "Visible Jukain ATK values are incorrect")
	await _free_scene(scene)


func _test_locked_and_unlocked_basic_attack() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	var enemy_a := _find_unit(scene, &"enemy_a")
	_set_current(scene, scene.jukain_unit)
	var hp_before: int = enemy_a.current_hp
	_check(scene.begin_attack_selection() and scene.select_attack_target(&"enemy_a"), "LOCKED Jukain Basic Attack did not resolve")
	_check(hp_before - enemy_a.current_hp == 1, "LOCKED Jukain Basic Attack did not use effective ATK 1")
	_check(scene.jukain_unit.atk == 9, "LOCKED Basic Attack overwrote real ATK")

	scene = await _replace_scene(scene, false)
	if scene == null:
		return
	enemy_a = _find_unit(scene, &"enemy_a")
	_check(scene.debug_unlock_jukain(), "DEBUG Unlock failed")
	_check(scene.jukain_state.get_effective_atk(scene.jukain_unit.atk) == 9, "UNLOCKED effective ATK does not equal real ATK")
	_set_current(scene, scene.jukain_unit)
	hp_before = enemy_a.current_hp
	_check(scene.begin_attack_selection() and scene.select_attack_target(&"enemy_a"), "UNLOCKED Jukain Basic Attack did not resolve")
	_check(hp_before - enemy_a.current_hp == 9, "UNLOCKED Jukain Basic Attack did not use real ATK")
	_check(scene.jukain_unit.atk == 9, "UNLOCKED Basic Attack overwrote real ATK")
	await _free_scene(scene)


func _test_debug_controls_and_restart() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	var before := _combat_snapshot(scene)
	_check(scene.debug_unlock_jukain(), "Jukain DEBUG Unlock was rejected")
	_check(_combat_snapshot(scene) == before, "DEBUG Unlock changed HP, line, turn, queue, enemy callback, or battle result")
	_check(scene.jukain_state.get_state() == JukainCombatStateModel.State.UNLOCKED, "DEBUG Unlock did not set UNLOCKED")
	_check(scene.jukain_unit.atk == 9, "DEBUG Unlock changed real ATK")
	before = _combat_snapshot(scene)
	_check(scene.debug_reset_jukain(), "Jukain DEBUG Reset was rejected")
	_check(_combat_snapshot(scene) == before, "DEBUG Reset changed HP, line, turn, queue, enemy callback, or battle result")
	_check(scene.jukain_state.get_state() == JukainCombatStateModel.State.LOCKED, "DEBUG Reset did not set LOCKED")
	_check(scene.jukain_unit.atk == 9, "DEBUG Reset changed real ATK")

	scene.debug_unlock_jukain()
	var old_unit: BattleUnit = scene.jukain_unit
	scene.jukain_unit.current_hp = 2
	scene.jukain_unit.line = BattleUnitModel.Line.BACK
	scene.restart_battle()
	await process_frame
	_check(scene.jukain_unit != old_unit and scene.jukain_unit.current_hp == 40 and scene.jukain_unit.line == BattleUnitModel.Line.FRONT and not scene.jukain_unit.defeated, "Restart did not rebuild Jukain's Party 2 fixture")
	_check(scene.jukain_state.get_state() == JukainCombatStateModel.State.LOCKED, "Restart retained stale UNLOCKED state")
	_check(scene.jukain_state.get_effective_atk(scene.jukain_unit.atk) == 1 and scene.jukain_unit.atk == 9, "Restart did not restore LOCKED effective ATK while preserving real ATK")
	await _free_scene(scene)


func _test_generic_and_hiruko_regression() -> void:
	for unit_id: StringName in [&"party_3", &"party_4", &"party_5", &"party_6"]:
		var scene := await _new_scene(false)
		if scene == null:
			return
		var generic := _find_unit(scene, unit_id)
		var enemy_a := _find_unit(scene, &"enemy_a")
		_set_current(scene, generic)
		var hp_before: int = enemy_a.current_hp
		_check(scene.begin_attack_selection() and scene.select_attack_target(&"enemy_a"), "%s Basic Attack did not resolve" % generic.display_name)
		_check(hp_before - enemy_a.current_hp == generic.atk, "%s Basic Attack no longer deals normal ATK" % generic.display_name)
		await _free_scene(scene)

	var scene := await _new_scene(false)
	if scene == null:
		return
	var enemy_a := _find_unit(scene, &"enemy_a")
	_set_current(scene, scene.hiruko_unit)
	var hp_before: int = enemy_a.current_hp
	_check(scene.begin_attack_selection() and scene.select_attack_target(&"enemy_a"), "Hiruko Basic Attack no longer resolves")
	_check(hp_before - enemy_a.current_hp == 10, "SEALED Hiruko Basic Attack changed")
	_check(scene.hiruko_state.get_state() == HirukoCombatStateModel.State.SEALED, "Jukain integration changed Hiruko state")
	await _free_scene(scene)


func _test_absent_future_mechanics() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_check(scene.get_node_or_null("%PrescriptPendingLabel") != null and scene.get_node("%PrescriptPendingLabel").text == "PRESCRIPT: PENDING M5.2", "Prescript placeholder is missing or claims implementation")
	_check(scene.get_node_or_null("%FormChainUnavailableLabel") != null and scene.get_node("%FormChainUnavailableLabel").text == "FORM CHAIN: NOT AVAILABLE", "Form Chain absence is not explicit")
	_check(scene.get_node_or_null("%PrescriptButton") == null, "A functional Prescript control exists in M5.1")
	_check(scene.get_node_or_null("%FormChainButton") == null, "A functional Form Chain control exists in M5.1")
	await _free_scene(scene)


func _test_victory_and_defeat() -> void:
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


func _test_layout_and_five_card_capacity() -> void:
	root.size = Vector2i(1152, 648)
	var scene := await _new_scene(false)
	if scene == null:
		return
	await process_frame
	_check(scene.get_node("Margin/Layout").size.y <= 624.0, "M5.1 content exceeds safe 1152x648 height")
	_check(_inside_viewport(scene.get_node("%JukainStateLabel")) and _inside_viewport(scene.get_node("%ResetJukainButton")), "Jukain state/debug UI is outside 1152x648")
	var battlefield: Control = scene.get_node("Margin/Layout/Battlefield")
	var stable_height := battlefield.size.y
	for index: int in 5:
		scene.party_units[index].line = BattleUnitModel.Line.MID
	scene.party_units[5].line = BattleUnitModel.Line.BACK
	scene._render_battlefield()
	await process_frame
	_check(scene.get_node("%AllyMidUnits").get_child_count() == 5, "Five-card line did not render all cards")
	_check(is_equal_approx(battlefield.size.y, stable_height), "Five-card line changed battlefield height")
	_check(scene.get_node("Margin/Layout").size.y <= 624.0, "Five-card line exceeded safe 1152x648 height")
	root.size = Vector2i(1440, 810)
	await process_frame
	_check(scene.get_node("Margin/Layout").size.y <= 786.0, "M5.1 content exceeds safe 1440x810 height")
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


func _set_current(scene: Control, unit: BattleUnit) -> void:
	scene.current_unit = unit
	scene.turn_index = scene.turn_queue.find(unit)
	scene._clear_action_selection()
	scene._refresh_turn_ui()


func _find_unit(scene: Control, id: StringName) -> BattleUnit:
	for unit: BattleUnit in scene.party_units + scene.enemy_units:
		if unit.stable_id == id:
			return unit
	return null


func _combat_snapshot(scene: Control) -> Dictionary:
	return {
		"party_hp": scene.party_units.map(func(unit: BattleUnit) -> int: return unit.current_hp),
		"enemy_hp": scene.enemy_units.map(func(unit: BattleUnit) -> int: return unit.current_hp),
		"jukain_line": scene.jukain_unit.line,
		"round": scene.round_number,
		"turn_index": scene.turn_index,
		"current": scene.current_unit.stable_id if scene.current_unit != null else &"",
		"queue": _ids(scene.turn_queue),
		"result": scene.battle_result,
		"enemy_pending": scene.enemy_action_pending,
	}


func _ids(units: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for unit: BattleUnit in units:
		result.append(unit.stable_id)
	return result


func _display_names(units: Array) -> Array[String]:
	var result: Array[String] = []
	for unit: BattleUnit in units:
		result.append(unit.display_name)
	return result


func _inside_viewport(control: Control) -> bool:
	var rect := control.get_global_rect()
	return rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= 1152.0 and rect.end.y <= 648.0


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
